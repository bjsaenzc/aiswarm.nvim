-- stream / ack / logs / report-event / briefing / retention commands (SDD-079–087).
local uv = vim.uv
local U = require("aiswarm.runtime.util")
local B = require("aiswarm.runtime.board")
local P = require("aiswarm.protocol")
local Cur = require("aiswarm.runtime.cursor")
local Stream = require("aiswarm.runtime.stream")
local M = {}
local fail = B.fail

local function resolve_attempt(ctx, id, which)
  local st = B.read_state(ctx)
  local task = st.tasks[id] or fail(2, "no such task: " .. id)
  local aid
  if which == nil or which == "" then aid = task.current_attempt_id or task.attempts[#task.attempts]
  elseif P.valid_uuid(which) then aid = which
  else
    local n = tonumber(which) or fail(3, "attempt must be an ordinal or an attempt id")
    for _, a in ipairs(task.attempts) do local att = st.attempts[a]; if att and att.ordinal == n then aid = a end end
  end
  if not aid or not st.attempts[aid] then fail(2, ("no attempt %s for %s"):format(tostring(which or "current"), id)) end
  if st.attempts[aid].task_id ~= id then fail(3, "attempt does not belong to " .. id) end
  return st.attempts[aid], task, st
end

--- Segments of a raw stream, sorted.
local function segments(dir, stream)
  local out = {}
  for _, e in ipairs(U.list(dir, "^" .. stream .. "%.%d+%.log$")) do out[#out + 1] = { n = tonumber(e.name:match("%.(%d+)%.log$")), path = dir .. "/" .. e.name } end
  table.sort(out, function(a, b) return a.n < b.n end)
  return out
end
M.segments = segments

function M.register(C)
  C.table.stream = { bools = { follow = true, f = true, once = true }, run = function(a)
    local ctx = B.load(a.root)
    local cursor
    if a.opts.cursor then
      local pos, err = Cur.decode(a.opts.cursor)
      if not pos then io.stdout:write(vim.json.encode({ frame = "error", code = "invalid_cursor", message = err }) .. "\n"); os.exit(3) end
      cursor = pos
    elseif a.opts.consumer then
      if not P.valid_consumer(a.opts.consumer) then fail(3, "invalid consumer name") end
      local bm = U.read_json(ctx.paths.consumers .. "/" .. a.opts.consumer .. ".json")
      if bm and bm.cursor then cursor = Cur.decode(bm.cursor) end
    end
    local filters = {}
    if a.opts.types then filters.types = vim.split(a.opts.types, ",", { trimempty = true }) end
    if a.opts.task then filters.task = a.opts.task end
    if a.opts.attempt then filters.attempt = a.opts.attempt end
    local out = io.stdout
    local reader = Stream.new(ctx, { cursor = cursor, filters = filters, history = tonumber(a.opts.history), follow = (a.opts.follow or a.opts.f) and not a.opts.once,
      stop_after = tonumber(a.opts.stop_after), write = function(line) local ok = out:write(line); if not ok then os.exit(0) end; out:flush() end })
    local code = reader:run()
    os.exit(code)
  end }

  C.table.ack = { run = function(a)
    local ctx = B.load(a.root)
    local name = a.opts.consumer or fail(1, "usage: ack --consumer NAME --cursor CURSOR")
    if not P.valid_consumer(name) then fail(3, "invalid consumer name: " .. name) end
    local pos, err = Cur.decode(a.opts.cursor or ""); if not pos then fail(3, "invalid cursor: " .. tostring(err)) end
    -- committed positions under the lock
    local _, checkpoints = Stream.bootstrap(ctx, {})
    local kind, detail = Cur.check(pos, ctx.board, { control_seq = checkpoints.control.seq, attempts = checkpoints.attempts })
    if kind ~= "ok" then fail(3, kind .. ": " .. detail) end
    for id in pairs(pos.attempts) do if not checkpoints.attempts[id] then fail(3, "cursor references unknown attempt " .. id) end end
    local path = ctx.paths.consumers .. "/" .. name .. ".json"
    local existing = U.read_json(path)
    if existing and existing.positions and not Cur.at_least(pos, existing.positions) then fail(3, "stale acknowledgement: bookmark for " .. name .. " is already ahead") end
    local record = { consumer = name, cursor = a.opts.cursor, positions = pos, acked_at = U.now_iso(), by = U.identity() }
    assert(U.write_json_atomic(path, record))
    if a.json then return record end
    return ("acknowledged %s at control seq %d"):format(name, pos.control.seq)
  end }

  C.table.consumers = { always_json = true, run = function(a)
    local ctx = B.load(a.root)
    local out = {}
    for _, e in ipairs(U.list(ctx.paths.consumers, "%.json$")) do out[#out + 1] = U.read_json(ctx.paths.consumers .. "/" .. e.name) end
    return out
  end }

  C.table.logs = { bools = { follow = true, f = true }, run = function(a)
    local ctx = B.load(a.root)
    local id = a.pos[1] or fail(1, "usage: logs <id> [--attempt N|ID] [--stream stdout|stderr] [--segment N] [--offset BYTES] [--limit BYTES] [--follow]")
    local attempt = resolve_attempt(ctx, id, a.opts.attempt)
    local stream = a.opts.stream or "stdout"
    if stream ~= "stdout" and stream ~= "stderr" then fail(3, "stream must be stdout or stderr") end
    local segs = segments(attempt.paths.dir, stream)
    local seg_n = tonumber(a.opts.segment)
    local offset = tonumber(a.opts.offset) or 0
    local limit = math.min(tonumber(a.opts.limit) or 65536, 4 * 1024 * 1024)
    local function page(seg, off)
      local st = uv.fs_stat(seg.path)
      if not st then return nil, "io" end
      local n = math.max(0, math.min(limit, st.size - off))
      local fd = uv.fs_open(seg.path, "r", 292); if not fd then return nil, "io" end
      local data = n > 0 and uv.fs_read(fd, n, off) or ""; uv.fs_close(fd)
      return { attempt_id = attempt.attempt_id, ordinal = attempt.ordinal, stream = stream, segment = seg.n, offset = off, bytes = #data, data = data, next_offset = off + #data,
        eof = off + #data >= st.size, segment_size = st.size, attempt_state = attempt.state }
    end
    if #segs == 0 then
      local r = { attempt_id = attempt.attempt_id, ordinal = attempt.ordinal, stream = stream, segment = 1, offset = 0, bytes = 0, data = "", next_offset = 0, eof = true, absent = true, attempt_state = attempt.state }
      if a.json then return r end
      return ""
    end
    local seg = segs[1]
    if seg_n then
      seg = nil
      for _, s in ipairs(segs) do if s.n == seg_n then seg = s end end
      if not seg then
        local r = { attempt_id = attempt.attempt_id, stream = stream, segment = seg_n, gap = true, reason = "segment evicted by retention", available = vim.tbl_map(function(s) return s.n end, segs) }
        if a.json then return r end
        fail(2, "segment " .. seg_n .. " of " .. stream .. " was evicted; available: " .. table.concat(r.available, ","))
      end
    else seg = segs[#segs]; if not a.opts.offset then offset = math.max(0, (uv.fs_stat(seg.path) or { size = 0 }).size - limit) end end
    local r, err = page(seg, offset)
    if not r then fail(1, "read error on " .. seg.path .. ": " .. tostring(err)) end
    if a.opts.follow or a.opts.f then
      io.stdout:write(r.data); io.stdout:flush()
      local off = r.next_offset
      while true do
        uv.sleep(200)
        local st = uv.fs_stat(seg.path)
        if st and st.size > off then local p = page(seg, off); if p then io.stdout:write(p.data); io.stdout:flush(); off = p.next_offset end end
        local at = B.read_state(ctx).attempts[attempt.attempt_id]
        if at and P.TERMINAL[at.state] and st and st.size <= off then break end
      end
      return nil
    end
    if a.json then return r end
    return r.data
  end }

  C.table["report-event"] = { run = function(a)
    local ctx = B.load(a.root)
    local task_id, attempt_id = a.opts.task or vim.env.AISWARM_TASK, a.opts.attempt or vim.env.AISWARM_ATTEMPT
    if not task_id or not attempt_id then fail(3, "report-event needs --task and --attempt (or the worker environment)") end
    local typ = a.opts.type or (a.opts.path and "agent.artifact") or "agent.progress"
    local payload = {}
    if a.opts.payload then local ok, p = pcall(vim.json.decode, a.opts.payload); if not ok or type(p) ~= "table" then fail(3, "payload must be a JSON object") end payload = p end
    if a.opts.path then payload.path = a.opts.path end
    if a.opts.message then payload.message = a.opts.message end
    if a.opts.phase then payload.phase = a.opts.phase end
    payload.provenance = payload.provenance or "worker_report"
    local msg = { message_id = a.opts.id or (U.now_iso() .. "-" .. uv.os_getpid() .. "-" .. math.random(1000, 9999)), board_id = ctx.board.board_id, task_id = task_id, attempt_id = attempt_id, type = typ, source = "worker_inbox", observed_at = U.now_iso(), payload = payload }
    local ok, err = P.validate_inbox(msg)
    if not ok then fail(3, err) end
    local st = B.read_state(ctx)
    local att = st.attempts[attempt_id] or fail(2, "no such attempt")
    if att.task_id ~= task_id then fail(3, "attempt does not belong to " .. task_id) end
    U.mkdirp(att.paths.inbox)
    local tmp = att.paths.inbox .. "/." .. msg.message_id .. ".tmp"
    assert(U.write_atomic(tmp, vim.json.encode(msg)))
    assert(uv.fs_rename(tmp, att.paths.inbox .. "/" .. msg.message_id .. ".json"))
    if a.json then return { accepted = true, message_id = msg.message_id } end
    return "accepted " .. msg.message_id
  end }

  C.table.briefing = { run = function(a)
    local ctx = B.load(a.root)
    local snap = B.snapshot(ctx)
    local activity = {}
    local reader = Stream.new(ctx, { filters = { types = { "progress", "input", "warning" } }, write = function() end })
    local _, checkpoints, state = Stream.bootstrap(ctx, {})
    reader:position({ control = { g = ctx.board.journal_generation, seq = checkpoints.control.seq }, attempts = {} }, state)
    local collected = {}
    reader:pump({ collect = collected })
    for _, c in ipairs(collected) do activity[#activity + 1] = c.rec end
    local b = require("aiswarm.runtime.briefing").build(snap, activity, { limits = { tasks = tonumber(a.opts.tasks), chars = tonumber(a.opts.chars) } })
    if a.json then return b end
    return b.text .. "\n"
  end }

  C.table.retention = { bools = { dry_run = true }, run = function(a)
    local ctx = B.load(a.root)
    local r = require("aiswarm.runtime.retention").run(ctx, { dry_run = a.opts.dry_run, days = tonumber(a.opts.days) })
    if a.json then return r end
    return ("retention: %d attempt dirs evicted, %d segments removed (%s)"):format(#r.evicted_attempts, #r.evicted_segments, a.opts.dry_run and "dry run" or "applied")
  end }
end

return M
