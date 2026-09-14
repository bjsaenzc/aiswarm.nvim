-- SDD-094 health diagnostics, SDD-095 cached statusline.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
local v3 = require("helpers.v3")
local function H() return require("aiswarm.health") end
local base_doctor = { api_version = 3, tmux = "tmux 3.6a", jq = true, timeout = true, git = true, nvim = "/usr/local/bin/nvim", locking = "mkdir+owner", schema = "v3", lock = "free" }
local base_editor = { setup_done = true, root = "/x/.aiswarm", source = "option", schema = "v3", connection = { state = "live" }, scheduler = { state = "running", alive = true, wip = 3 },
  nvim_ok = true, snacks = true, providers = { { id = "mock", available = true } }, default_provider = "mock" }
local function levels(list, level) local out = {}; for _, f in ipairs(list) do if f.level == level then out[#out + 1] = f.text end end return out end
local function find(list, pat) for _, f in ipairs(list) do if f.text:match(pat) then return f end end end

return {
  { id = "health.fixtures_map_to_severity_and_action", tasks = { "SDD-094" }, suites = { "core" }, run = function(t)
    pl.unload(); require("aiswarm")
    local ok = H().assess(base_doctor, base_editor)
    t:eq(#levels(ok, "error"), 0, vim.inspect(levels(ok, "error"))); t:ok(find(ok, "^scheduler running")); t:ok(find(ok, "^stream: live"))
    local md = vim.deepcopy(base_doctor); md.tmux, md.nvim = "missing", nil
    local missing = H().assess(md, base_editor)
    t:ok(find(missing, "^tmux: missing").level == "error"); t:match(find(missing, "^tmux").text, "install tmux"); t:ok(find(missing, "headless Neovim").level == "error")
    local old = H().assess(base_doctor, vim.tbl_extend("force", base_editor, { nvim_ok = false })); t:ok(find(old, "0.10.4").level == "error")
    local legacy = H().assess(vim.tbl_extend("force", base_doctor, { schema = "v2" }), vim.tbl_extend("force", base_editor, { schema = "v2", scheduler = { legacy = true } }))
    t:ok(find(legacy, "legacy v2 board").level == "warn"); t:match(find(legacy, "legacy v2 board").text, "migrate")
    local stopped = H().assess(base_doctor, vim.tbl_extend("force", base_editor, { scheduler = { state = "stopped" } })); t:match(find(stopped, "scheduler stopped").text, "scheduler start"); t:eq(find(stopped, "scheduler stopped").level, "warn")
    local dead = H().assess(base_doctor, vim.tbl_extend("force", base_editor, { registration = { dead = true, path = "/x/nvim.server" } })); t:ok(find(dead, "stale push registration").level == "warn")
    local degraded = H().assess(base_doctor, vim.tbl_extend("force", base_editor, { telemetry_degraded = true, connection = { state = "reconnecting", error = "stream exited", age_s = 12 } }))
    t:ok(find(degraded, "telemetry degraded").level == "warn"); t:match(find(degraded, "^stream: reconnecting").text, "12s ago")
    local nodoctor = H().assess(nil, base_editor); t:ok(find(nodoctor, "doctor").level == "error")
    t:ok(find(ok, "headless Neovim runtime").text:match("v3 workers/streams"), "standalone runtime requirement explicit")
  end },
  { id = "health.doctor_and_checkhealth_agree_on_real_boards", tasks = { "SDD-094" }, suites = { "core" }, run = function(t)
    local root = v3.board(t, "h")
    local A = pl.setup(t, root, { follow = true }); t:wait(10000, function() return require("aiswarm.store").connection.state == "live" end)
    local d, editor = H().collect()
    t:eq(d.schema, "v3"); t:eq(d.api_version, 3); t:eq(editor.schema, "v3"); t:eq(editor.connection.state, "live")
    local findings = H().assess(d, editor)
    t:eq(#levels(findings, "error"), 0, vim.inspect(levels(findings, "error"))); t:ok(find(findings, "scheduler stopped"))
    local calls = {}
    local orig = vim.health; vim.health = setmetatable({ start = function() end }, { __index = function(_, k) return function(msg) calls[#calls + 1] = k .. ": " .. msg end end })
    H().check(); vim.health = orig
    t:ok(#calls >= 8, "checkhealth reports the same findings: " .. #calls)
    local legacy = sb.legacy_board(t, "lh")
    pl.setup(t, legacy); pl.refresh(t, require("aiswarm"))
    local d2, e2 = H().collect(); t:eq(d2.schema, "v2"); t:ok(find(H().assess(d2, e2), "legacy v2 board"))
  end },
  { id = "statusline.cached_no_io_and_states", tasks = { "SDD-095" }, suites = { "core", "performance" }, run = function(t)
    pl.unload()
    t:eq(require("aiswarm").statusline(), "", "unobtrusive before setup")
    local root = v3.board(t, "sl")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local A = pl.setup(t, root, { follow = true }); t:wait(10000, function() return require("aiswarm.store").connection.state == "live" end)
    local backend = require("aiswarm.backend"); local store = require("aiswarm.store")
    local calls, reads = backend.stats.calls, 0
    local orig = vim.uv.fs_open; vim.uv.fs_open = function(...) reads = reads + 1; return orig(...) end
    local started = vim.uv.hrtime()
    for _ = 1, 2000 do A.statusline() end
    local ms = (vim.uv.hrtime() - started) / 1e6
    vim.uv.fs_open = orig
    t:eq(backend.stats.calls, calls, "no subprocess per redraw"); t:eq(reads, 0, "no file I/O per redraw"); t:ok(ms < 200, "2000 redraws in " .. ms .. " ms")
    t:eq(A.statusline(), "R:1 A:0 ✓0 ✗0")
    -- state changes appear after store updates; stale counts are never shown as live
    store.apply_control({ event_id = "s1", type = "task.finished", task = vim.tbl_extend("force", store.task("T-001"), { state = "failed", outcome = { reason = "exit 1", finished_at = "x" } }) })
    t:match(A.statusline(), "✗1"); t:match(A.statusline(), "!1")
    store.acknowledge("T-001"); t:ok(not A.statusline():find("!"))
    store.scheduler.paused = true; store._cache = {}; t:match(A.statusline(), "^⏸")
    store.set_connection({ state = "offline", error = "x" }); t:eq(A.statusline(), "aiswarm: offline")
    store.set_connection({ state = "reconnecting" }); t:match(A.statusline(), "…")
    local lualine = sb.repo .. "/lua/plugins/lualine-nvim.lua"
    local spec = dofile(sb.exists(lualine) and lualine or sb.plugin .. "/examples/lualine.lua")
    local comp = spec.opts.sections.lualine_x[1]
    t:eq(type(comp[1]), "function"); t:eq(comp.cond(), true)
    package.loaded["aiswarm"] = nil
    t:eq(comp.cond(), false, "component stays inactive without triggering a load"); t:eq(comp[1](), "")
  end },
}
