-- Per-attempt telemetry journal writer and activity projection (SDD-073, SDD-077).
-- One writer per attempt (ownership file), stable stream generation, monotonic attempt_seq,
-- bounded append queue, no control-lock dependency.
local uv = vim.uv
local U = require("aiswarm.runtime.util")
local P = require("aiswarm.protocol")
local W = {}
W.__index = W

W.MAX_QUEUE = 4096

--- Open (own) the telemetry writer of an attempt. Rejects a second live appender.
function W.open(ctx, attempt, opts)
  opts = opts or {}
  local dir = attempt.paths.dir
  U.mkdirp(dir); U.mkdirp(attempt.paths.inbox)
  local owner_path = dir .. "/telemetry.owner.json"
  local existing = U.read_json(owner_path)
  if existing and U.owner_alive(existing) and not opts.force then
    return nil, ("telemetry writer already owned by pid %d"):format(existing.pid)
  end
  local seqfile = U.read_json(dir .. "/telemetry.seq") or {}
  local generation = tostring((tonumber(existing and existing.generation or seqfile.generation) or 0) + 1)
  local self = setmetatable({
    ctx = ctx, attempt = attempt, dir = dir, path = attempt.paths.telemetry, generation = generation,
    seq = tonumber(seqfile.seq) or 0, queue = {}, queued_bytes = 0, dropped = 0, activity = U.read_json(attempt.paths.activity) or {},
    owner = vim.tbl_extend("force", U.identity(), { generation = generation, attempt_id = attempt.attempt_id }),
  }, W)
  -- every writer instance is a new generation; the per-generation sequence restarts at 0 and
  -- event ids (<attempt>:<generation>:<seq>) stay unique
  self.seq = 0
  U.write_json_atomic(owner_path, self.owner)
  self.activity.stream_generation = generation
  return self
end

--- Queue a record; flushes when the queue is large. Returns the record or nil when dropped.
function W:emit(type_, payload, opts)
  opts = opts or {}
  if #self.queue >= W.MAX_QUEUE then self.dropped = self.dropped + 1; return nil end
  self.seq = self.seq + 1
  local rec = {
    schema_version = P.SCHEMA_VERSION, board_id = self.ctx.board.board_id, task_id = self.attempt.task_id, attempt_id = self.attempt.attempt_id,
    source = opts.source or "worker", stream_generation = self.generation, attempt_seq = self.seq,
    event_id = ("%s:%s:%d"):format(self.attempt.attempt_id, self.generation, self.seq), observed_at = U.now_iso(),
    type = type_, level = opts.level or "info", payload = payload or {},
  }
  local ok, err = P.validate_telemetry_record(rec)
  if not ok then
    self.seq = self.seq - 1
    return nil, err
  end
  local line = vim.json.encode(rec)
  if #line > P.LIMITS.record_bytes then
    self.seq = self.seq - 1
    return self:emit("telemetry.warning", { message = "record exceeds 64 KiB and was dropped", original_type = type_ }, { level = "warn" })
  end
  self.queue[#self.queue + 1] = line
  self.queued_bytes = self.queued_bytes + #line + 1
  self:touch(rec)
  if self.queued_bytes >= 16384 or opts.flush then self:flush() end
  return rec
end

--- Update the latest-activity projection in memory (published on flush).
function W:touch(rec)
  local a = self.activity
  local p = rec.payload or {}
  if rec.type == "agent.heartbeat" then a.heartbeat_at = rec.observed_at
  elseif rec.type == "agent.output" then a.output_at = rec.observed_at; a.last_output_preview = p.preview; a.last_output_stream = p.stream
  elseif rec.type == "agent.progress" then
    a.activity_at = rec.observed_at; a.phase = p.phase or a.phase; a.message = p.message or a.message; a.provenance = p.provenance or "worker_report"
    a.completed, a.total = p.completed, p.total
  elseif rec.type == "agent.input_required" then a.activity_at = rec.observed_at; a.input_required = { request_id = p.request_id, prompt = p.prompt, actions = p.actions }
  elseif rec.type:match("^agent%.tool") then a.activity_at = rec.observed_at; a.message = p.name and ("tool " .. p.name) or a.message; a.provenance = "adapter"
  elseif rec.type == "agent.usage" then a.usage = p
  end
  a.checkpoint = { stream_generation = self.generation, attempt_seq = self.seq }
  a.updated_at = rec.observed_at
  self.activity_dirty = true
end

--- Rotate the journal when it exceeds the cap: the closed file keeps its generation name and the
--- writer continues in a fresh generation (readers see an explicit generation gap).
function W:maybe_rotate()
  local cap = tonumber(os.getenv("AISWARM_TELEMETRY_CAP_BYTES")) or 50 * 1024 * 1024
  local st = uv.fs_stat(self.path)
  if not st or st.size < cap then return false end
  uv.fs_rename(self.path, ("%s/telemetry.g%s.closed.jsonl"):format(self.dir, self.generation))
  self.generation = tostring(tonumber(self.generation) + 1)
  self.seq = 0
  self.owner.generation = self.generation
  U.write_json_atomic(self.dir .. "/telemetry.owner.json", self.owner)
  self.activity.stream_generation = self.generation
  self.rotations = (self.rotations or 0) + 1
  return true
end

--- Append queued records with one write + fsync, then publish the projection atomically.
function W:flush()
  if #self.queue > 0 then
    self:maybe_rotate()
    local data = table.concat(self.queue, "\n") .. "\n"
    local ok, err = U.append_fsync(self.path, data)
    if not ok then self.write_error = err; return false, err end
    self.queue, self.queued_bytes = {}, 0
    U.write_json_atomic(self.dir .. "/telemetry.seq", { seq = self.seq, generation = self.generation })
  end
  if self.activity_dirty then
    U.write_json_atomic(self.attempt.paths.activity, self.activity)
    self.activity_dirty = false
  end
  return true
end

function W:close()
  self:flush()
  os.remove(self.dir .. "/telemetry.owner.json")
end

--- Consume validated inbox messages (SDD-075): each *.json is a message; partial files are ignored.
function W:drain_inbox()
  local n = 0
  for _, e in ipairs(U.list(self.attempt.paths.inbox, "%.json$")) do
    local path = self.attempt.paths.inbox .. "/" .. e.name
    local msg = U.read_json(path)
    if msg then
      local ok, err = P.validate_inbox(msg)
      local accepted = ok and msg.board_id == self.ctx.board.board_id and msg.task_id == self.attempt.task_id and msg.attempt_id == self.attempt.attempt_id
      if accepted then
        self.seen_messages = self.seen_messages or {}
        if not self.seen_messages[msg.message_id] then
          self.seen_messages[msg.message_id] = true
          local payload = vim.tbl_extend("force", msg.payload or {}, { provenance = msg.payload and msg.payload.provenance or "worker_report", message_id = msg.message_id })
          self:emit(msg.type, payload, { source = msg.source or "worker_inbox" })
        end
        n = n + 1
      else
        self:emit("telemetry.warning", { message = "rejected inbox message: " .. tostring(err or "identity mismatch"), file = e.name }, { level = "warn" })
      end
      os.remove(path)
    end
  end
  if n > 0 then self:flush() end
  return n
end

--- Rebuild the activity projection from the journal (used when the projection is stale/missing).
function W.rebuild_activity(attempt)
  local a = { rebuilt = true }
  local self = setmetatable({ activity = a, generation = "?", seq = 0 }, W)
  local text = U.read(attempt.paths.telemetry) or ""
  for line in text:gmatch("[^\n]+") do
    local ok, rec = pcall(vim.json.decode, line)
    if ok and type(rec) == "table" and rec.type then self.generation, self.seq = rec.stream_generation, rec.attempt_seq; self:touch(rec) end
  end
  U.write_json_atomic(attempt.paths.activity, a)
  return a
end

return W
