-- Editor-side v3 stream transport (SDD-088, SDD-090, SDD-091): owns the `aiswarm stream --follow`
-- process, frame decoding, cursor, deduplication, subscriber delivery, reconnect/backoff, the
-- periodic fallback reconciliation, and the compatibility push bridge.
local uv = vim.uv
local M = { supported = true, _subs = {}, stats = { frames = 0, events = 0, reconnects = 0, dropped_frames = 0, resyncs = 0, snapshots = 0 } }
local function A() return require("aiswarm") end
local store = require("aiswarm.store")
local P = require("aiswarm.protocol")
local F = require("aiswarm.runtime.frames")
local backend = require("aiswarm.backend")

M.BACKOFF_MIN_MS, M.BACKOFF_MAX_MS, M.HEALTHY_MS = 250, 5000, 10000
M.tasks = store.tasks   -- the store keeps this table's identity across resets and snapshots (no __pairs in LuaJIT)
M.meta = setmetatable({}, { __index = function(_, k)
  if k == "paused" then return store.scheduler.paused end
  if k == "capabilities" then return store.board.capabilities end
  if k == "error" then return store.connection.error end
  if k == "counts" then return store.counts() end
  if k == "root" then return store.board.root end
  if k == "wip" then return store.scheduler.wip end
  if k == "seq" then return store.seq end
  return nil
end })

-- ---------------------------------------------------------------- subscriptions (legacy-compatible kinds)
function M.subscribe(fn)
  table.insert(M._subs, fn)
  return function() for i, f in ipairs(M._subs) do if f == fn then table.remove(M._subs, i); return end end end
end
local function emit(kind, payload)
  for _, fn in ipairs(vim.list_extend({}, M._subs)) do
    local ok, err = pcall(fn, kind, payload)
    if not ok then A().err("subscriber failed: " .. tostring(err)) end
  end
end

-- ---------------------------------------------------------------- normalization
local function derive_display(task)
  local blockers = task.state == "queued" and P.blockers(task, store.tasks) or nil
  task.blockers = blockers
  local attempt = task.current_attempt_id and store.attempts[task.current_attempt_id] or nil
  task.display, task.display_detail = P.display_state(task, attempt or (task.state == "running" and { state = "running" } or nil), task.health, { quiet_after_s = A().config.ui.quiet_after_s })
  return task
end

function M.normalize_snapshot(snap)
  local tasks = {}
  for _, t in ipairs(snap.tasks or {}) do t.legacy = false; tasks[#tasks + 1] = t end
  return { tasks = tasks, attempts = snap.attempts or {}, scheduler = snap.scheduler, seq = snap.control_seq,
    board = { root = snap.root, board_id = snap.board_id, schema = "v3", journal_generation = snap.journal_generation, api_version = 3 },
    capabilities = snap.capabilities or { attempts = true, cancel = true, retry = true, telemetry = true } }
end

local KIND = { ["agent.progress"] = "progress", ["agent.output"] = "output", ["agent.heartbeat"] = "heartbeat", ["agent.input_required"] = "input_required",
  ["agent.tool.started"] = "tool", ["agent.tool.finished"] = "tool", ["agent.artifact"] = "artifact", ["agent.usage"] = "usage",
  ["telemetry.warning"] = "warning", ["stream.gap"] = "gap", ["stream.status"] = "status" }
local HIDDEN = { output = true, heartbeat = true }

--- Telemetry record → activity record + in-place health update.
function M.apply_telemetry(rec)
  local p = rec.payload or {}
  local kind = KIND[rec.type] or rec.type
  local text
  if kind == "progress" then text = (p.phase and ("[" .. p.phase .. "] ") or "") .. tostring(p.message or "")
  elseif kind == "output" then text = ("%s %s"):format(p.stream or "stdout", p.preview or ("+" .. tostring(p.bytes) .. " bytes"))
  elseif kind == "heartbeat" then text = p.alive == false and "process exited" or "alive"
  elseif kind == "input_required" then text = tostring(p.prompt or p.request_id)
  elseif kind == "tool" then text = ("%s %s"):format(rec.type:match("started") and "started" or "finished", tostring(p.name or "tool"))
  elseif kind == "artifact" then text = "artifact " .. tostring(p.path)
  elseif kind == "gap" then text = ("gap: %s%s"):format(tostring(p.reason), p.discarded_bytes and (" (" .. p.discarded_bytes .. " bytes discarded)") or "")
  else text = tostring(p.message or rec.type) end
  local task = store.tasks[rec.task_id]
  local level = rec.level or "info"
  if kind == "gap" then level = "warn" end
  local activity = { event_id = rec.event_id, ts = rec.observed_at, task_id = rec.task_id, attempt_id = rec.attempt_id, kind = kind, level = level, text = text,
    source = rec.source, provenance = p.provenance or (rec.source == "worker" and "observed" or rec.source), hidden = HIDDEN[kind] or nil, path = p.path, raw = rec }
  -- health: separate heartbeat/output/activity ages; heartbeats never overwrite messages
  if task and task.current_attempt_id == rec.attempt_id then
    local h = task.health or {}
    if kind == "heartbeat" then h.heartbeat_at = rec.observed_at; h.stale = false; h.stale_for_s = nil
    elseif kind == "output" then h.output_at = rec.observed_at; h.quiet = false
    elseif kind == "progress" then h.activity_at = rec.observed_at; h.message = p.message or h.message; h.phase = p.phase or h.phase; h.provenance = p.provenance or "worker_report"; h.quiet = false
    elseif kind == "input_required" then h.input_required = { request_id = p.request_id, prompt = p.prompt, actions = p.actions }; h.activity_at = rec.observed_at
    elseif kind == "tool" then h.activity_at = rec.observed_at end
    task.health = h
    derive_display(task)
    store.emit({ kind = "health", ids = { task.id } })
  end
  store.apply_activity(activity)
end

local LIFECYCLE_TEXT = { ["task.queued"] = "queued", ["task.edited"] = "edited", ["task.reordered"] = "reordered", ["task.cancelled"] = "cancelled", ["task.retried"] = "retried (queued again)",
  ["attempt.reserved"] = "dispatch reserved", ["attempt.started"] = "started", ["scheduler.changed"] = "scheduler changed", ["task.imported"] = "imported" }

--- Control record → store control event (+ lifecycle activity).
function M.apply_control(rec, opts)
  opts = opts or {}
  local p = rec.payload or {}
  local task = p.task and vim.deepcopy(p.task) or nil
  if task then
    task.legacy = false
    local cur = store.tasks[task.id]
    if cur and cur.health and task.current_attempt_id == cur.current_attempt_id then task.health = cur.health end
    if p.attempt and p.attempt.attempt_id then store.attempts[p.attempt.attempt_id] = p.attempt end
    derive_display(task)
  end
  local ev = { event_id = rec.event_id, seq = rec.control_seq, type = rec.type, task_id = rec.task_id, attempt_id = rec.attempt_id, ts = rec.observed_at,
    task = task, attempt = p.attempt, scheduler = p.scheduler, needs_refresh = task == nil and p.scheduler == nil, historical = opts.historical }
  local applied = store.apply_control(ev)
  if applied and not opts.historical then
    local text = LIFECYCLE_TEXT[rec.type] or rec.type
    local level = "info"
    if rec.type == "task.finished" or rec.type == "attempt.finished" then
      local st = (task and task.state) or (p.attempt and p.attempt.state) or "finished"
      text = st .. ((p.attempt and p.attempt.reason) and (" · " .. p.attempt.reason) or ""); if st == "failed" then level = "error" end
    end
    if rec.task_id then
      store.apply_activity({ event_id = rec.event_id .. ":a", ts = rec.observed_at, task_id = rec.task_id, attempt_id = rec.attempt_id, kind = "lifecycle", level = level, text = text, source = rec.actor or "backend", provenance = "backend" })
    end
    local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "AISwarmEvent", data = rec })
    if not ok then A().err("AISwarmEvent callback failed: " .. tostring(err)) end
    if A().config.compat.hive_events then
      local e = require("aiswarm.runtime.compat").v2_event(rec)
      if e then require("aiswarm.compat").emit_hive_event(e) end
    end
    emit("event", rec)
  end
  return applied
end

-- ---------------------------------------------------------------- frames
function M.handle_frame(frame)
  M.stats.frames = M.stats.frames + 1
  if frame.frame == "hello" then
    if frame.board_id and store.board.board_id and frame.board_id ~= store.board.board_id then store.set_connection({ state = "incompatible", error = "stream belongs to another board" }); return M.stop_process() end
    store.board.board_id, store.board.journal_generation = frame.board_id, frame.journal_generation
    if frame.resumed_from == "resync" then M.stats.resyncs = M.stats.resyncs + 1 end
  elseif frame.frame == "snapshot" then
    M.stats.snapshots = M.stats.snapshots + 1
    local norm = M.normalize_snapshot(frame)
    -- keep health already learned from telemetry when the snapshot has none
    for _, t in ipairs(norm.tasks) do local cur = store.tasks[t.id]; if cur and cur.health and not t.health then t.health = cur.health end end
    store.apply_snapshot(norm, { connection = false })
    if frame.activity then
      for aid, act in pairs(frame.activity) do
        local a = store.attempts[aid]
        local task = a and store.tasks[a.task_id]
        if task and task.current_attempt_id == aid then
          task.health = vim.tbl_extend("force", task.health or {}, { heartbeat_at = act.heartbeat_at, output_at = act.output_at, activity_at = act.activity_at, message = act.message, phase = act.phase, provenance = act.provenance, input_required = act.input_required })
          derive_display(task)
        end
      end
      store.emit({ kind = "snapshot" })
    end
    M.cursor = frame.next_cursor
    M.last_success = uv.now()
    emit("refresh", M.meta)
  elseif frame.frame == "event" then
    M.stats.events = M.stats.events + 1
    local rec = frame.event
    if rec.control_seq then M.apply_control(rec, { historical = frame.historical }) else
      if not frame.historical or true then M.apply_telemetry(rec) end
    end
    M.cursor = frame.next_cursor or M.cursor
    M.last_success = uv.now()
  elseif frame.frame == "gap" then
    store.activity.gap = true
    store.apply_activity({ event_id = "gap:" .. tostring(frame.source) .. ":" .. tostring(frame.from) .. ":" .. tostring(frame.to) .. ":" .. tostring(uv.hrtime()), ts = os.date("!%Y-%m-%dT%H:%M:%SZ"), kind = "gap", level = "warn",
      text = ("gap on %s: %s (%s → %s)"):format(tostring(frame.source), tostring(frame.reason), tostring(frame.from), tostring(frame.to)), source = "stream", provenance = "stream" })
    if frame.next_cursor and frame.next_cursor ~= "" then M.cursor = frame.next_cursor end
  elseif frame.frame == "status" then
    if frame.state == "live" then
      store.set_connection({ state = "live", error = nil, retry_at = nil, last_success = uv.now() }); M.healthy_since = uv.now()
      M.backoff_ms = M.BACKOFF_MIN_MS
    end
    M.cursor = frame.next_cursor or M.cursor
  elseif frame.frame == "error" then
    if frame.code == "resync_required" or frame.code == "invalid_cursor" or frame.code == "wrong_board" then
      M.cursor = nil; M.stats.resyncs = M.stats.resyncs + 1
      store.set_connection({ state = "reconnecting", error = frame.code .. ": " .. tostring(frame.message) })
    elseif frame.code == "incompatible" then
      store.set_connection({ state = "incompatible", error = tostring(frame.message) })
    else store.set_connection({ error = tostring(frame.message) }) end
  end
end

-- ---------------------------------------------------------------- process lifecycle
function M.start(root)
  M.stop()
  M.root, M._stopped, M.generation = root, false, (M.generation or 0) + 1
  M.backoff_ms = M.BACKOFF_MIN_MS
  store.set_connection({ state = "connecting" })
  emit("refresh", {})
  M.connect()
  M.register_server()
  local ms = A().config.telemetry.reconcile_ms
  M._reconcile = uv.new_timer()
  M._reconcile:start(ms, ms, vim.schedule_wrap(function() if not M._stopped then M.refresh() end end))
end

function M.connect()
  if M._stopped or M._job then return end
  local generation = M.generation
  local decoder = F.decoder()
  local args = { "stream", "--follow" }
  if M.cursor then vim.list_extend(args, { "--cursor", M.cursor }) else vim.list_extend(args, { "--history", "200" }) end
  local on_stdout = vim.schedule_wrap(function(err, data)
    if generation ~= M.generation or M._stopped then return end
    if err then store.set_connection({ error = tostring(err) }); return end
    if not data then return end
    local frames, diags = decoder:feed(data)
    M.stats.dropped_frames = M.stats.dropped_frames + #diags
    for _, d in ipairs(diags) do
      if d.code == "incompatible" then store.set_connection({ state = "incompatible", error = tostring(d.error) }) end
    end
    for _, frame in ipairs(frames) do
      local ok, ferr = pcall(M.handle_frame, frame)
      if not ok then A().err("stream frame failed: " .. tostring(ferr)) end
    end
  end)
  local ok, job = pcall(vim.system, A().cmd(args), { text = false, env = A().env(), stdout = on_stdout, stderr = false }, vim.schedule_wrap(function(o)
    if generation ~= M.generation or M._stopped then return end
    M._job = nil
    M.schedule_reconnect(("stream exited with code %s"):format(tostring(o.code)))
  end))
  if ok then M._job = job else M._job = nil; M.schedule_reconnect("cannot start stream: " .. tostring(job)) end
end

--- Jittered exponential backoff 250 ms → 5 s; resets after a healthy interval.
function M.schedule_reconnect(reason)
  if M._stopped or M._retry then return end
  if M.healthy_since and (uv.now() - M.healthy_since) > M.HEALTHY_MS then M.backoff_ms = M.BACKOFF_MIN_MS end
  M.healthy_since = nil
  local delay = M.backoff_ms + math.random(0, math.floor(M.backoff_ms / 4))
  M.backoff_ms = math.min(M.BACKOFF_MAX_MS, M.backoff_ms * 2)
  M.stats.reconnects = M.stats.reconnects + 1
  store.set_connection({ state = M.last_success and "reconnecting" or "offline", error = reason, retry_at = uv.now() + delay,
    age_s = M.last_success and math.floor((uv.now() - M.last_success) / 1000) or nil })
  local generation = M.generation
  M._retry = uv.new_timer()
  M._retry:start(delay, 0, vim.schedule_wrap(function()
    if M._retry then M._retry:stop(); M._retry:close(); M._retry = nil end
    if generation ~= M.generation or M._stopped then return end
    M.connect()
  end))
end

function M.stop_process()
  -- the reader is our own stateless subprocess: end it immediately (Neovim ignores a bare SIGTERM while looping)
  if M._job then pcall(function() M._job:kill(9) end); M._job = nil end
end

function M.stop()
  M._stopped = true
  M.generation = (M.generation or 0) + 1
  M.stop_process()
  if M._retry then M._retry:stop(); M._retry:close(); M._retry = nil end
  if M._reconcile then M._reconcile:stop(); M._reconcile:close(); M._reconcile = nil end
  M.cursor, M.last_success, M.healthy_since = nil, nil, nil
  M.unregister_server()
end

--- Snapshot reconciliation through the backend (also the 10 s fallback). cb(snapshot, err).
function M.refresh(cb)
  if M._stopped then if cb then cb(nil, "stopped") end return end
  local generation = M.generation
  backend.call({ "snapshot" }, { timeout_ms = A().config.command_timeout_ms }, function(res)
    if generation ~= M.generation then return end
    if res.ok then
      local norm = M.normalize_snapshot(res.data)
      for _, t in ipairs(norm.tasks) do local cur = store.tasks[t.id]; if cur and cur.health and not t.health then t.health = cur.health end end
      store.apply_snapshot(norm, { connection = false })
      M.last_success = uv.now()
      emit("refresh", M.meta)
      if cb then cb(res.data) end
    else
      if not res.stale and not res.cancelled then store.set_connection({ error = res.error, age_s = M.last_success and math.floor((uv.now() - M.last_success) / 1000) or nil }); emit("error", res.error) end
      if cb then cb(nil, res.error) end
    end
  end)
end

--- Manual reconnect (Ctrl-r): drop backoff and reconnect immediately.
function M.reconnect()
  if M._retry then M._retry:stop(); M._retry:close(); M._retry = nil end
  M.stop_process(); M.backoff_ms = M.BACKOFF_MIN_MS
  M.connect(); M.refresh()
end

-- ---------------------------------------------------------------- legacy-compatible surface
function M.ids()
  local out = {}
  for _, name in ipairs(store.GROUPS) do for _, t in ipairs(store.grouped().groups[name]) do out[#out + 1] = t.id end end
  return out
end
function M.list()
  local out = {}
  for _, name in ipairs(store.GROUPS) do for _, t in ipairs(store.grouped().groups[name]) do out[#out + 1] = t end end
  return out
end
function M.statusline()
  if store.connection.state == "offline" or store.connection.state == "incompatible" then return "aiswarm: " .. store.connection.state end
  local c = store.counts()
  if c.all == 0 then return "" end
  return ("%sR:%d A:%d ✓%d ✗%d"):format(store.scheduler.paused and "⏸ " or "", c.queued, c.running, c.states.succeeded or 0, (c.states.failed or 0) + (c.states.cancelled or 0))
end

--- Compatibility push bridge (SDD-090): a low-volume control event pushed by aiswarm-push/hive-push
--- shares the stream's identity, so it deduplicates against the stream and only triggers reconciliation.
function M.on_event(e)
  if M._stopped or type(e) ~= "table" or type(e.seq) ~= "number" or e.seq < 1 then return false end
  local id = ("%s:c:%s:%d"):format(tostring(store.board.board_id), tostring(store.board.journal_generation or 1), e.seq)
  local applied = store.apply_control({ event_id = id, seq = e.seq, type = e.v3_type or ("v2." .. tostring(e.type)), task_id = e.task ~= "" and e.task or nil, ts = e.ts, needs_refresh = true })
  if applied then M.refresh() end
  return true
end
function M.on_event_json(text, root)
  if root and require("aiswarm.project").canonical(root) ~= A().root() then return false end
  local ok, e = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  return ok and M.on_event(e) or false
end

function M.register_server()
  if M._registration or not A().config.register_server then return end
  local path = A().root() .. "/nvim.server"
  local ok, err = pcall(function()
    local server = vim.v.servername
    if server == "" then server = vim.fn.serverstart() end
    assert(server ~= "", "could not start Neovim server")
    local tmp = path .. "." .. vim.fn.getpid()
    if vim.fn.writefile({ server }, tmp) ~= 0 then error("could not write " .. tmp) end
    assert(os.rename(tmp, path))
    M._registration = { path = path, server = server }
  end)
  if not ok then A().warn("push registration failed: " .. tostring(err)); M._registration = { path = path, server = false } end
end
function M.unregister_server()
  local reg = M._registration
  M._registration = nil
  if not reg or not reg.server then return end
  local ok, lines = pcall(vim.fn.readfile, reg.path)
  if ok and lines[1] == reg.server then os.remove(reg.path) end
end

return M
