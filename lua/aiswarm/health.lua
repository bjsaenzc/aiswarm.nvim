-- :checkhealth aiswarm (SDD-094): consistent with `aiswarm doctor`, plus editor-side stream health,
-- registration and telemetry state. Every finding names the action that fixes it.
local M = {}

--- Pure assessment used by both :checkhealth and tests. Returns a list of { level, text }.
---@param d table doctor JSON
---@param editor { setup_done: boolean, root: string?, source: string?, schema: string, connection: table, scheduler: table, registration: table?, nvim_ok: boolean, snacks: boolean, providers: table[], default_provider: string }
function M.assess(d, editor)
  local out = {}
  local function add(level, text) out[#out + 1] = { level = level, text = text } end
  if not editor.nvim_ok then add("error", "Neovim 0.10.4 or newer is required (this is " .. tostring(vim.version()) .. ")") end
  if not editor.setup_done then add("warn", "setup() has not run; the lazy spec calls it on first use") end
  if not d then add("error", "`aiswarm doctor --json` failed; check that bin points at the bundled launcher and that bash/jq are installed"); return out end
  if (d.api_version or 0) < 2 then add("error", "backend API " .. tostring(d.api_version) .. " is too old; use the bundled bin/aiswarm") end
  add(d.tmux and d.tmux ~= "missing" and "ok" or "error", "tmux: " .. tostring(d.tmux) .. (d.tmux == "missing" and " — install tmux 3.2+ (workers run in tmux sessions)" or ""))
  add(d.jq and "ok" or "error", "jq: " .. tostring(d.jq) .. (not d.jq and " — install jq (legacy v2 boards and the launcher use it)" or ""))
  add(d.nvim and "ok" or "error", "headless Neovim runtime for v3 workers/streams: " .. tostring(d.nvim or "not found — set AISWARM_NVIM or put nvim on PATH; v3 boards cannot run workers without it"))
  add(d.timeout and "ok" or "info", "GNU timeout: " .. tostring(d.timeout) .. (not d.timeout and " (only legacy v2 boards need it; v3 workers enforce deadlines themselves)" or ""))
  add(d.git and "ok" or "info", "git: " .. tostring(d.git) .. (not d.git and " (worktree isolation unavailable)" or ""))
  add("info", "locking: " .. tostring(d.locking or "unknown"))
  local schema = editor.schema or d.schema
  add("info", ("board: %s (%s, schema %s)"):format(tostring(editor.root or d.root), tostring(editor.source), tostring(schema)))
  if schema == "v2" then add("warn", "legacy v2 board: no attempt history, cancel/retry, or structured telemetry — review `:AISwarm migrate --dry-run`, then `:AISwarm migrate --upgrade`") end
  if schema == "migrating" then add("error", "interrupted migration — run `:AISwarm migrate --resume` or `--rollback` before using this board") end
  if schema == "conflict" then add("error", "both .aiswarm and .hive exist — choose one with `:AISwarm project choose`") end
  if schema == "missing" then add("info", "no board yet — `:AISwarm init` creates one explicitly") end
  if d.migration == "in-progress" then add("error", "a migration marker is present; compliant writers refuse mutations until it completes") end
  local s = editor.scheduler or d.scheduler or {}
  if schema == "v3" then
    if s.state == "running" and (s.alive == true or s.health == "alive") then add("ok", ("scheduler running (wip %s%s)"):format(tostring(s.wip), s.paused and ", dispatch paused — `:AISwarm scheduler resume`" or ""))
    elseif s.state == "running" then add("warn", "scheduler recorded as running but its process is " .. tostring(s.health or "unknown") .. " — `:AISwarm scheduler start` after checking `aiswarm scheduler status`")
    else add("warn", "scheduler stopped — queued tasks wait until `:AISwarm scheduler start`") end
  end
  if d.lock and d.lock ~= "free" then add(d.lock == "alive" and "info" or "warn", "control lock: " .. tostring(d.lock) .. (d.lock == "dead" and " (will be recovered on the next command)" or "")) end
  local c = editor.connection or {}
  if c.state == "live" then add("ok", "stream: live")
  elseif c.state == "reconnecting" then add("warn", ("stream: reconnecting (%s; last data %ss ago) — Ctrl-r in the workspace reconnects now"):format(tostring(c.error), tostring(c.age_s)))
  elseif c.state == "offline" then add("error", ("stream: offline (%s) — check `aiswarm doctor` and the board path"):format(tostring(c.error)))
  elseif c.state == "incompatible" then add("error", "stream: incompatible schema (" .. tostring(c.error) .. ") — update the plugin and backend together")
  elseif c.state == "connecting" then add("info", "stream: connecting") end
  if editor.registration then
    if editor.registration.server == false then add("warn", "push registration failed (" .. tostring(editor.registration.error) .. "); the live stream still works without it")
    elseif editor.registration.dead then add("warn", "stale push registration from another editor at " .. tostring(editor.registration.path) .. " — it is replaced on the next setup()") end
  end
  if editor.telemetry_degraded then add("warn", "telemetry degraded: records were dropped or a gap was recorded; the Activity view shows the gap") end
  local avail = {}
  for _, p in ipairs(editor.providers or {}) do if p.available and p.exe then avail[#avail + 1] = p.id .. " (" .. p.exe .. ")" end end
  add(#avail > 0 and "ok" or "warn", #avail > 0 and ("providers: " .. table.concat(avail, ", ")) or "no agent CLI found (claude, codex, gemini, aider, cursor-agent); only `mock` will run")
  add("info", "default provider: " .. tostring(editor.default_provider) .. " (AISWARM_PROVIDER overrides; native provider events are not enabled — output/heartbeat/progress are generic)")
  add(editor.snacks and "ok" or "error", editor.snacks and "snacks.nvim present" or "snacks.nvim missing — the workspace, pickers and composer need it")
  return out
end

function M.collect()
  local A = require("aiswarm")
  local project = require("aiswarm.project")
  local d
  if vim.fn.executable(A.config.bin) == 1 then
    local out, code = A.run_sync({ "doctor", "--json" }, 3000)
    if code == 0 and out ~= "" then local ok, v = pcall(vim.json.decode, out, { luanil = { object = true, array = true } }); if ok and type(v) == "table" then d = v end end
  end
  local store = require("aiswarm.store")
  local root = A.root()
  local reg
  local ok_session, session = pcall(require, "aiswarm.session")
  local engine = ok_session and session.engine or nil
  if engine and engine._registration then reg = vim.deepcopy(engine._registration) end
  if root and vim.uv.fs_stat(root .. "/nvim.server") then
    local lines = vim.fn.readfile(root .. "/nvim.server")
    if lines[1] and lines[1] ~= vim.v.servername and not vim.uv.fs_stat(lines[1]) then reg = vim.tbl_extend("force", reg or {}, { dead = true, path = root .. "/nvim.server" }) end
  end
  local registry = require("aiswarm.providers.registry")
  return d, {
    setup_done = A._setup_done == true, root = root, source = (A._resolved or {}).source, schema = project.schema(root), connection = store.connection,
    scheduler = store.scheduler, registration = reg, nvim_ok = vim.fn.has("nvim-0.10.4") == 1, snacks = pcall(require, "snacks"),
    providers = registry.list(), default_provider = registry.default(), telemetry_degraded = store.activity.gap == true or store.stats.dropped_activity > 0,
  }
end

function M.check()
  vim.health.start("aiswarm")
  local d, editor = M.collect()
  for _, f in ipairs(M.assess(d, editor)) do vim.health[f.level](f.text) end
end

return M
