-- v3 command table for runtime/cli.lua (control commands; telemetry/stream commands register later).
local U = require("aiswarm.runtime.util")
local B = require("aiswarm.runtime.board")
local O = require("aiswarm.runtime.ops")
local P = require("aiswarm.protocol")
local C = {}
local fail = B.fail
C.table = {}

local function reg(name, spec) C.table[name] = spec; return spec end
function C.get(name) return C.table[name] end
local function load(a) return B.load(a.root) end
local function read_prompt(a)
  if a.opts.file then
    local text = U.read(a.opts.file); if not text then fail(2, "cannot read prompt file: " .. a.opts.file) end
    return text
  end
  if a.opts.prompt then return a.opts.prompt end
  local text = io.stdin:read("*a") or ""
  return text
end
local function list_opt(v) if v == nil then return nil end if type(v) == "table" then return v end return { v } end

-- ---------------------------------------------------------------- board
reg("init", { bools = { force = true }, run = function(a)
  local root = a.opts.root or a.root
  local board, created = B.init(root, { name = a.opts.name, wip = a.opts.wip, tick = a.opts.tick, provider = a.opts.provider, worktrees = a.opts.worktrees })
  if a.json then return { root = root, board_id = board.board_id, created = created } end
  return (created and "initialized " or "already initialized ") .. root .. " (board " .. board.board_id .. ")"
end })

reg("doctor", { run = function(a)
  local schema = require("aiswarm.project") and (function()
    if U.exists(a.root .. "/board.json") then return "v3" elseif U.is_dir(a.root .. "/tasks/ready") then return "v2" end return "missing" end)()
  local function have(x) return vim.fn.executable(x) == 1 end
  local providers = {}
  for _, p in ipairs({ "claude", "codex", "gemini", "aider", "cursor-agent" }) do if have(p) then providers[#providers + 1] = p end end
  local tmux = have("tmux") and vim.trim(vim.system({ "tmux", "-V" }, { text = true }):wait().stdout or "") or "missing"
  local d = { api_version = 3, version = B.VERSION, capabilities = { atomic_add = true, attempts = true, telemetry = true, ack = true },
    locking = "mkdir+owner", tmux = tmux, jq = have("jq"), timeout = have("timeout"), git = have("git"), nvim = vim.v.progpath,
    nvim_version = tostring(vim.version()), schema = schema, root = a.root, blackboard = schema ~= "missing", providers = providers }
  if schema == "v3" then
    local ctx = B.load(a.root)
    d.board_id, d.journal_generation = ctx.board.board_id, ctx.board.journal_generation
    local st = U.read_json(ctx.paths.scheduler) or {}
    d.scheduler = { state = st.state, paused = st.paused, wip = st.wip, alive = st.owner and U.owner_alive(st.owner) or nil }
    d.lock = require("aiswarm.runtime.lock").inspect(a.root)
    d.migration = U.exists(a.root .. "/locks/migration.marker") and "in-progress" or nil
  end
  if a.json then return d end
  local lines = {}
  for _, k in ipairs({ "version", "root", "schema", "tmux", "jq", "timeout", "git", "nvim", "locking" }) do lines[#lines + 1] = ("  %-10s %s"):format(k, tostring(d[k])) end
  lines[#lines + 1] = "  providers  " .. (#providers > 0 and table.concat(providers, ", ") or "(none; mock only)")
  if d.scheduler then lines[#lines + 1] = "  scheduler  " .. tostring(d.scheduler.state) .. (d.scheduler.paused and " (paused)" or "") .. " alive=" .. tostring(d.scheduler.alive) end
  return table.concat(lines, "\n") .. "\n"
end })

-- ---------------------------------------------------------------- tasks
reg("add", { bools = { worktree = true }, run = function(a)
  local ctx = load(a)
  local task = O.add(ctx, { id = a.opts.id, title = a.opts.title, provider = a.opts.provider, depends_on = list_opt(a.opts.dep) or a.opts.deps,
    priority = a.opts.priority, timeout = a.opts.timeout, isolation = a.opts.isolation or (a.opts.worktree and "worktree" or nil),
    prompt = read_prompt(a), actor = a.opts.actor, source = a.opts.source })
  if a.json then return { id = task.id, revision = task.revision, task = task } end
  return task.id
end })

reg("set", { run = function(a)
  local ctx = load(a)
  local id = a.pos[1]; if not id then fail(1, "usage: set <id> --expect-revision N [--title ..] [--provider ..] [--deps a,b] [--priority N] [--timeout S] [--isolation shared|worktree] [--file prompt.md]") end
  local rev = tonumber(a.opts.expect_revision)
  local fields = { expected_revision = rev, title = a.opts.title, provider = a.opts.provider, depends_on = a.opts.deps or list_opt(a.opts.dep),
    priority = a.opts.priority, timeout = a.opts.timeout, isolation = a.opts.isolation, actor = a.opts.actor }
  if a.opts.file then fields.prompt = read_prompt(a) end
  -- legacy key=value pairs (hive set) map onto the same validator with the current revision
  for _, kv in ipairs(a.pos) do
    local k, v = kv:match("^([%w_]+)=(.*)$")
    if k then
      if k == "depends_on" or k == "deps" then fields.depends_on = v elseif k == "worktree" then fields.isolation = (v == "true") and "worktree" or "shared"
      elseif k == "priority" or k == "timeout" or k == "title" or k == "provider" or k == "isolation" then fields[k] = v
      else fail(3, "field not editable: " .. k) end
    end
  end
  if not rev then
    local snap = B.snapshot(ctx)
    for _, t in ipairs(snap.tasks) do if t.id == id then fields.expected_revision = t.revision end end
    io.stderr:write("aiswarm: --expect-revision not given; using the current revision (legacy set semantics)\n")
  end
  local task = O.edit(ctx, id, fields)
  if a.json then return { id = task.id, revision = task.revision, task = task } end
  return ("%s revision %d"):format(task.id, task.revision)
end })

reg("move", { bools = { first = true, last = true }, run = function(a)
  local ctx = load(a)
  local id = a.pos[1]; if not id then fail(1, "usage: move <id> --first|--last|--before <id>|--after <id>") end
  local where, other
  if a.opts.first then where = "first" elseif a.opts.last then where = "last"
  elseif a.opts.before then where, other = "before", a.opts.before elseif a.opts.after then where, other = "after", a.opts.after
  else fail(1, "usage: move <id> --first|--last|--before <id>|--after <id>") end
  local r = O.move(ctx, id, where, other)
  if a.json then return r end
  return ("moved %s (%d priorities changed)"):format(id, #r.changed)
end })
C.table.reorder = C.table.move

reg("retry", { run = function(a)
  local ctx = load(a)
  local id = a.pos[1]; if not id then fail(1, "usage: retry <id>") end
  local task = O.retry(ctx, id, { expected_revision = tonumber(a.opts.expect_revision), actor = a.opts.actor })
  if a.json then return { id = task.id, revision = task.revision, state = task.state } end
  return ("%s queued again (revision %d)"):format(task.id, task.revision)
end })

reg("cancel", { run = function(a)
  local ctx = load(a)
  local id = a.pos[1]; if not id then fail(1, "usage: cancel <id> [--grace S]") end
  local r = require("aiswarm.runtime.lifecycle").cancel(ctx, id, { expected_revision = tonumber(a.opts.expect_revision),
    grace_s = tonumber(a.opts.grace), actor = a.opts.actor, attempt_id = a.opts.attempt })
  if a.json then return r end
  return ("cancelled %s%s"):format(id, r.attempt and (" (attempt " .. r.attempt.ordinal .. ", " .. tostring(r.attempt.reason) .. ")") or " (queued, never started)")
end })

-- ---------------------------------------------------------------- reads
local function snapshot(a) return B.snapshot(load(a), { heartbeat_ms = 5000 }) end
reg("snapshot", { always_json = true, run = function(a) return snapshot(a) end })
reg("json", { always_json = true, run = function(a) return require("aiswarm.runtime.compat").v2_snapshot(snapshot(a)) end })
C.table.dump = C.table.json
reg("status", { run = function(a)
  local snap = snapshot(a)
  if a.json then return require("aiswarm.runtime.compat").v2_snapshot(snap) end
  return require("aiswarm.runtime.compat").render_status(snap)
end })
reg("show", { always_json = true, run = function(a)
  local ctx = load(a)
  local id = a.pos[1]; if not id then fail(1, "usage: show <id>") end
  local snap = B.snapshot(ctx)
  for _, t in ipairs(snap.tasks) do
    if t.id == id then
      local attempts = vim.tbl_filter(function(x) return x.task_id == id end, snap.attempts)
      local out = { task = t, attempts = attempts }
      if a.opts.legacy or a.opts.with_result then return require("aiswarm.runtime.compat").v2_task(t, attempts, ctx) end
      return out
    end
  end
  fail(2, "no such task: " .. id)
end })

reg("progress", { run = function(a)
  -- canonical: progress --task ID --attempt A --phase P --message M ; legacy: progress <task-id> [note]
  local args = { a.plugin .. "/bin/aiswarm-progress", "--root", a.root }
  if a.opts.task then vim.list_extend(args, { "--task", a.opts.task }) end
  if a.opts.attempt then vim.list_extend(args, { "--attempt", a.opts.attempt }) end
  if a.opts.phase then vim.list_extend(args, { "--phase", a.opts.phase }) end
  if a.opts.message then vim.list_extend(args, { "--message", a.opts.message }) end
  if not a.opts.task and a.pos[1] then
    local ctx = load(a); local st = B.read_state(ctx); local task = st.tasks[a.pos[1]] or fail(2, "no such task: " .. a.pos[1])
    vim.list_extend(args, { "--task", task.id, "--attempt", task.current_attempt_id or fail(3, task.id .. " is not running") })
    if a.pos[2] then vim.list_extend(args, { "--message", table.concat(vim.list_slice(a.pos, 2), " ") }) end
  end
  local o = vim.system(args, { text = true, env = vim.fn.environ() }):wait(5000)
  if o.code ~= 0 then fail(o.code, vim.trim(o.stderr)) end
  return a.json and { accepted = true } or "progress recorded"
end })

reg("attempt", { run = function(a)
  local ctx = load(a)
  local sub, attempt_id = a.pos[1], a.pos[2]
  if sub == "started" then
    local r = O.attempt_started(ctx, attempt_id, { pid = tonumber(a.opts.pid), pid_start = a.opts.pid_start, pgid = tonumber(a.opts.pgid), host = a.opts.host, cwd = a.opts.cwd,
      tmux = a.opts.session and { session = a.opts.session, pane = a.opts.pane } or nil })
    return a.json and r or ("started " .. attempt_id)
  elseif sub == "finished" then
    local r = O.attempt_finished(ctx, attempt_id, { state = a.opts.state, exit_code = tonumber(a.opts.exit), signal = tonumber(a.opts.signal), reason = a.opts.reason })
    return a.json and r or ((r.duplicate and "already finished " or "finished ") .. attempt_id)
  elseif sub == "show" then
    local st = B.read_state(ctx); return st.attempts[attempt_id] or fail(2, "no such attempt")
  end
  fail(1, "usage: attempt started|finished|show <attempt-id> [--pid N ...]")
end })

reg("help", { run = function()
  return [[
aiswarm v3 commands (board with board.json):
  init [--root R] [--name N] [--wip N] [--provider P] [--worktrees DIR]
  add [--id ID] [--title T] [--provider P] [--dep ID]... [--priority N] [--timeout S] [--isolation shared|worktree] [--file F]
  set <id> --expect-revision N [--title ..] [--provider ..] [--deps a,b] [--priority N] [--timeout S] [--file F]
  move <id> --first|--last|--before ID|--after ID
  cancel <id> [--grace S]     retry <id>
  snapshot | json | status [--json] | show <id>
  scheduler status|start|stop|pause|resume [--wip N]     dispatch [--once]     reconcile
  attach <id> | peek <id> [N] | wait <id> | gc | down
  progress --task ID --attempt A --phase P --message M     report-event ...
  stream [--follow] [--cursor C] [--types a,b] [--history N]     ack --consumer NAME --cursor C     logs <id> [--attempt N] [--stream stdout|stderr] [--follow]
  migrate [--dry-run|--resume|--rollback]     doctor [--json]
  legacy aliases: events, tail, peek, go, kill (cancel+requeue), pause, resume, up, loop
]]
end })

-- later packages register more commands here
pcall(function() require("aiswarm.runtime.lifecycle").register(C) end)
pcall(function() require("aiswarm.runtime.compat").register(C) end)
pcall(function() require("aiswarm.runtime.telemetry_commands").register(C) end)
pcall(function() require("aiswarm.runtime.migrate").register(C) end)

return C
