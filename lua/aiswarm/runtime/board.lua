-- Board manifest, projections, recovery, transactions and snapshots (SDD-018/020/021/022).
local uv = vim.uv
local U = require("aiswarm.runtime.util")
local J = require("aiswarm.runtime.journal")
local L = require("aiswarm.runtime.lock")
local R = require("aiswarm.runtime.reducer")
local P = require("aiswarm.protocol")
local B = {}

B.VERSION = "3.0.0-dev"

function B.paths(root)
  return {
    root = root, manifest = root .. "/board.json", control = root .. "/control", journal = J.path(root),
    tasks = root .. "/control/tasks", attempts = root .. "/control/attempts", scheduler = root .. "/control/scheduler.json", cache = root .. "/control/state.json",
    applied = root .. "/control/applied.json", consumers = root .. "/control/consumers", prompts = root .. "/prompts",
    attempt_dirs = root .. "/attempts", context = root .. "/context", locks = root .. "/locks", migration = root .. "/migration",
    scheduler_heartbeat = root .. "/control/scheduler.heartbeat", scheduler_stop = root .. "/control/scheduler.stop",
  }
end

local function fail(code, msg) error({ code = code, message = msg }, 0) end
B.fail = fail

function B.manifest(root) return U.read_json(root .. "/board.json") end

--- Create a v3 board. Idempotent: an existing board keeps its identity and context.
function B.init(root, opts)
  opts = opts or {}
  local p = B.paths(root)
  local existing = B.manifest(root)
  if existing then
    if existing.schema_version ~= P.BOARD_SCHEMA then fail(3, "board at " .. root .. " has schema " .. tostring(existing.schema_version)) end
    return existing, false
  end
  if U.is_dir(root .. "/tasks/ready") then fail(3, root .. " is a legacy (v2) board; run `aiswarm migrate` to upgrade it") end
  for _, d in ipairs({ p.control, p.tasks, p.attempts, p.consumers, p.prompts, p.attempt_dirs, p.context, p.locks, p.migration, J.quarantine_dir(root) }) do U.mkdirp(d) end
  local board = {
    schema_version = P.BOARD_SCHEMA, board_id = U.uuid(), journal_generation = 1, name = opts.name or vim.fs.basename(vim.fs.dirname(root)),
    created_at = U.now_iso(), created_by = U.identity(), version = B.VERSION,
    scheduler_defaults = { wip = tonumber(opts.wip) or 3, tick_s = tonumber(opts.tick) or 3, timeout_s = 1800, provider = opts.provider or "mock",
      worktrees_dir = opts.worktrees or nil },
  }
  local templates = {
    ["MISSION.md"] = "# Mission\n<one paragraph: what we are building and what \"done\" means>\n\n## Invariants (never violate)\n- Never push to main. Work on your own branch.\n- Tests must pass before a task is reported complete.\n\n## Glossary / domain facts\n",
    ["DECISIONS.md"] = "# Decision log (append-only; newest last)\nFormat: <UTC timestamp> | <task-id> | <decision> | <rationale>\n",
    ["INTERFACES.md"] = "# Contracts between workstreams\nAnything one agent must not change without renegotiating with the orchestrator:\nfunction signatures, schemas, endpoints, file ownership.\n",
  }
  for name, text in pairs(templates) do if not U.exists(p.context .. "/" .. name) then U.write_atomic(p.context .. "/" .. name, text) end end
  if not U.exists(p.journal) then U.write_atomic(p.journal, "") end
  U.write_atomic(J.sidecar(root), "0")
  U.write_json_atomic(p.applied, { seq = 0 })
  U.write_json_atomic(p.scheduler, { state = "stopped", paused = false, wip = board.scheduler_defaults.wip, tick_s = board.scheduler_defaults.tick_s })
  -- the manifest is the last thing written: a crash before this leaves no board
  assert(U.write_json_atomic(p.manifest, board))
  return board, true
end

--- Load a board context or fail with "missing".
function B.load(root)
  local board = B.manifest(root)
  if not board then
    if U.is_dir(root .. "/tasks/ready") then fail(4, "legacy (v2) board at " .. root .. "; run `aiswarm migrate --dry-run`") end
    fail(4, "no board at " .. root .. "; run `aiswarm init`")
  end
  if board.schema_version ~= P.BOARD_SCHEMA then fail(4, "unsupported board schema " .. tostring(board.schema_version)) end
  return { root = root, board = board, paths = B.paths(root) }
end

-- ---------------------------------------------------------------- projections
--- Projections. A whole-state cache (control/state.json) is used when its applied sequence matches
--- applied.json; otherwise the per-entity files are read (they remain the source for the stream).
function B.read_state(ctx)
  local p = ctx.paths
  local applied = U.read_json(p.applied) or { seq = 0 }
  local cached = U.read_json(p.cache)
  if cached and cached.applied_seq == (applied.seq or 0) and type(cached.tasks) == "table" and type(cached.attempts) == "table" then
    cached.board = ctx.board
    cached.scheduler = cached.scheduler or U.read_json(p.scheduler) or { state = "stopped" }
    return cached
  end
  local state = { tasks = {}, attempts = {}, scheduler = U.read_json(p.scheduler) or { state = "stopped" }, board = ctx.board }
  for _, e in ipairs(U.list(p.tasks, "%.json$")) do
    local t = U.read_json(p.tasks .. "/" .. e.name); if t and t.id then state.tasks[t.id] = t end
  end
  for _, e in ipairs(U.list(p.attempts, "%.json$")) do
    local a = U.read_json(p.attempts .. "/" .. e.name); if a and a.attempt_id then state.attempts[a.attempt_id] = a end
  end
  local applied = U.read_json(p.applied) or { seq = 0 }
  state.applied_seq = applied.seq or 0
  return state
end

function B.publish(ctx, state, touched, seq)
  local p = ctx.paths
  for key in pairs(touched) do
    local kind, id = key:match("^(%w+):(.+)$")
    if kind == "task" then assert(U.write_json_atomic(p.tasks .. "/" .. id .. ".json", state.tasks[id]))
    elseif kind == "attempt" then assert(U.write_json_atomic(p.attempts .. "/" .. id .. ".json", state.attempts[id]))
    elseif key == "scheduler" then assert(U.write_json_atomic(p.scheduler, state.scheduler))
    elseif key == "board" then assert(U.write_json_atomic(p.manifest, state.board)) end
  end
  assert(U.write_json_atomic(p.applied, { seq = seq }))
  state.applied_seq = seq
  U.write_json_atomic(p.cache, { applied_seq = seq, tasks = state.tasks, attempts = state.attempts, scheduler = state.scheduler })
end

--- Recovery (caller holds the lock): repair the journal tail, reconcile the sidecar, replay projections.
function B.recover(ctx)
  local rec = J.recover(ctx.root)
  local state = B.read_state(ctx)
  if state.applied_seq < rec.committed_seq then
    local records = J.after(ctx.root, state.applied_seq)
    local touched = R.replay(state, records)
    B.publish(ctx, state, touched, rec.committed_seq)
    rec.replayed = #records
  elseif state.applied_seq > rec.committed_seq then
    -- projections claim more than the journal holds: rebuild everything from committed history
    state = { tasks = {}, attempts = {}, scheduler = { state = "stopped" }, board = ctx.board, applied_seq = 0 }
    local touched = R.replay(state, J.after(ctx.root, 0))
    for _, e in ipairs(U.list(ctx.paths.tasks, "%.json$")) do if not state.tasks[e.name:sub(1, -6)] then os.remove(ctx.paths.tasks .. "/" .. e.name) end end
    B.publish(ctx, state, touched, rec.committed_seq)
    rec.rebuilt = true
  end
  ctx.committed_seq = rec.committed_seq
  return state, rec
end

-- ---------------------------------------------------------------- transactions
--- Run fn(state) under the lock after recovery. fn returns a list of partial records
--- ({type, task_id?, attempt_id?, payload}) or nil for a read-only operation. Commits atomically.
---@return table records, table state
function B.txn(ctx, opts, fn)
  opts = opts or {}
  return L.with(ctx.root, { purpose = opts.purpose or "mutation", timeout_ms = opts.timeout_ms }, function(lock)
    ctx.lock = lock
    local state = B.recover(ctx)
    local records = fn(state)
    if records and #records > 0 then B.commit(ctx, state, records, opts.actor) end
    ctx.lock = nil
    return records or {}, state
  end)
end

--- Commit already-validated partial records (lock held, state recovered).
function B.commit(ctx, state, partials, actor)
  assert(ctx.lock, "commit requires the control lock")
  local seq = ctx.committed_seq
  local txn_id, now = U.uuid(), U.now_iso()
  local records = {}
  for i, r in ipairs(partials) do
    seq = seq + 1
    local rec = {
      schema_version = P.SCHEMA_VERSION, board_id = ctx.board.board_id, journal_generation = ctx.board.journal_generation,
      control_seq = seq, event_id = ("%s:c:%d:%d"):format(ctx.board.board_id, ctx.board.journal_generation, seq),
      txn = { id = txn_id, index = i, count = #partials, last = i == #partials }, observed_at = now,
      type = r.type, task_id = r.task_id, attempt_id = r.attempt_id, actor = actor or ctx.actor or ("pid:" .. uv.os_getpid()),
      payload = r.payload or {},
    }
    local ok, err = P.validate_control_record(rec)
    if not ok then fail(3, "refusing to commit invalid record (" .. rec.type .. "): " .. err) end
    records[#records + 1] = rec
  end
  if ctx.fault == "before_append" then fail(1, "fault injected before append") end
  local ok, err = J.append(ctx.root, records)
  if not ok then fail(1, "journal append failed: " .. tostring(err)) end
  if ctx.fault == "after_append" then fail(1, "fault injected after append") end
  ctx.committed_seq = seq
  U.write_atomic(J.sidecar(ctx.root), tostring(seq))
  if ctx.fault == "after_sidecar" then fail(1, "fault injected after sidecar") end
  local touched = R.replay(state, records)
  if ctx.fault == "mid_projection" then
    -- publish only the first touched entity, then die
    for key in pairs(touched) do B.publish_one(ctx, state, key); break end
    fail(1, "fault injected mid projection")
  end
  B.publish(ctx, state, touched, seq)
  return records
end
function B.publish_one(ctx, state, key)
  local kind, id = key:match("^(%w+):(.+)$")
  if kind == "task" then U.write_json_atomic(ctx.paths.tasks .. "/" .. id .. ".json", state.tasks[id])
  elseif kind == "attempt" then U.write_json_atomic(ctx.paths.attempts .. "/" .. id .. ".json", state.attempts[id]) end
end

-- ---------------------------------------------------------------- snapshot
--- Derived, display-ready snapshot of fully applied committed state.
function B.derive(ctx, state, opts)
  opts = opts or {}
  local now = U.now_s()
  local tasks = {}
  local counts = { queued = 0, blocked = 0, running = 0, succeeded = 0, failed = 0, cancelled = 0 }
  for _, t in pairs(state.tasks) do
    local task = vim.deepcopy(t)
    if task.state == "queued" then task.blockers = P.blockers(task, state.tasks); if #task.blockers > 0 then counts.blocked = counts.blocked + 1 end end
    counts[task.state] = (counts[task.state] or 0) + 1
    local attempt = task.current_attempt_id and state.attempts[task.current_attempt_id] or nil
    local health = attempt and B.health(ctx, attempt, now, opts) or nil
    task.health = health
    task.display, task.display_detail = P.display_state(task, attempt, health, opts)
    tasks[#tasks + 1] = task
  end
  table.sort(tasks, function(a, b)
    local order = { running = 1, queued = 2, failed = 3, cancelled = 3, succeeded = 4 }
    local oa, ob = order[a.state] or 9, order[b.state] or 9
    if oa ~= ob then return oa < ob end
    if a.state == "queued" then return P.compare_queue(a, b) end
    if a.state == "succeeded" or a.state == "failed" or a.state == "cancelled" then
      local fa, fb = a.outcome and a.outcome.finished_at or "", b.outcome and b.outcome.finished_at or ""
      if fa ~= fb then return fa > fb end
    end
    return a.id < b.id
  end)
  local attempts = vim.tbl_values(state.attempts)
  table.sort(attempts, function(a, b) if a.task_id ~= b.task_id then return a.task_id < b.task_id end return a.ordinal < b.ordinal end)
  local scheduler = vim.deepcopy(state.scheduler or { state = "stopped" })
  local hb = U.read_json(ctx.paths.scheduler_heartbeat)
  if scheduler.state == "running" then
    local alive = U.owner_alive(scheduler.owner)
    scheduler.process_alive = alive
    scheduler.heartbeat_at = hb and hb.at or nil
    if alive == false then scheduler.health = "dead" elseif alive == nil then scheduler.health = "unknown" else scheduler.health = "alive" end
  end
  return {
    schema_version = P.SCHEMA_VERSION, api_version = 3, board_id = ctx.board.board_id, journal_generation = ctx.board.journal_generation,
    root = ctx.root, name = ctx.board.name, control_seq = state.applied_seq, counts = counts, tasks = tasks, attempts = attempts,
    scheduler = scheduler, capabilities = { attempts = true, telemetry = true, ack = true, cancel = true, retry = true, atomic_add = true },
    generated_at = U.now_iso(),
  }
end

--- Health inputs for a running attempt from persisted worker/activity files (no subprocesses).
function B.health(ctx, attempt, now, opts)
  if attempt.state ~= "running" and attempt.state ~= "starting" then return nil end
  local dir = attempt.paths and attempt.paths.dir
  local act = dir and U.read_json(dir .. "/activity.json") or nil
  local h = { heartbeat_at = act and act.heartbeat_at, output_at = act and act.output_at, activity_at = act and act.activity_at,
    phase = act and act.phase, message = act and act.message, provenance = act and act.provenance }
  local hb_s = (opts.heartbeat_ms or 5000) / 1000
  local hb = act and U.parse_iso(act.heartbeat_at)
  if attempt.state == "running" then
    if hb then
      h.heartbeat_age_s = math.floor(now - hb)
      if now - hb > 3 * hb_s then h.stale, h.stale_for_s = true, math.floor(now - hb) end
    else
      local started = U.parse_iso(attempt.started_at)
      if started and now - started > 3 * hb_s then h.stale, h.stale_for_s = true, math.floor(now - started) end
    end
    local last = act and (U.parse_iso(act.output_at) or U.parse_iso(act.activity_at)) or U.parse_iso(attempt.started_at)
    if last then
      h.quiet_for_s = math.floor(now - last)
      if now - last > (opts.quiet_after_s or 60) then h.quiet = true end
    end
    if act and act.input_required then h.input_required = act.input_required end
  end
  return h
end

--- Consistent snapshot: lock, recover, read, derive.
function B.snapshot(ctx, opts)
  local _, state = B.txn(ctx, { purpose = "snapshot" }, function() return nil end)
  return B.derive(ctx, state, opts)
end

return B
