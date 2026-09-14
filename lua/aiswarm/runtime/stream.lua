-- Multiplexed replay/follow of the control journal and every attempt's telemetry journal
-- (SDD-080–082, SDD-084 gaps): incremental offsets, checkpoint bootstrap, deterministic merge,
-- filesystem watch with a 250 ms polling fallback, opaque cursors.
local uv = vim.uv
local U = require("aiswarm.runtime.util")
local B = require("aiswarm.runtime.board")
local J = require("aiswarm.runtime.journal")
local L = require("aiswarm.runtime.lock")
local P = require("aiswarm.protocol")
local F = require("aiswarm.runtime.frames")
local Cur = require("aiswarm.runtime.cursor")
local Writer = require("aiswarm.runtime.telemetry")
local S = {}
S.__index = S

S.POLL_MS = 250
local DECODE = { luanil = { object = true, array = true } }

local TYPE_GROUPS = {
  lifecycle = function(t) return t:match("^task%.") or t:match("^attempt%.") or t:match("^scheduler%.") or t:match("^board%.") end,
  progress = function(t) return t == "agent.progress" end, output = function(t) return t == "agent.output" end,
  heartbeat = function(t) return t == "agent.heartbeat" end, warning = function(t) return t == "telemetry.warning" end,
  tool = function(t) return t:match("^agent%.tool") end, input = function(t) return t == "agent.input_required" end,
  artifact = function(t) return t == "agent.artifact" end, usage = function(t) return t == "agent.usage" end,
}

--- Written telemetry checkpoints for every attempt (seq/generation from the writer's sidecar).
function S.attempt_checkpoints(ctx, state)
  local out = {}
  for id, a in pairs(state.attempts) do
    local sf = a.paths and U.read_json(a.paths.dir .. "/telemetry.seq") or nil
    out[id] = { g = tostring(sf and sf.generation or "1"), seq = tonumber(sf and sf.seq) or 0 }
  end
  return out
end

--- Activity projections, rebuilt when stale relative to the written checkpoint (SDD-077).
function S.activity_projections(state, checkpoints)
  local out = {}
  for id, a in pairs(state.attempts) do
    if a.paths and a.paths.activity then
      local act = U.read_json(a.paths.activity)
      local cp = checkpoints[id]
      local stale = not act or not act.checkpoint or (act.checkpoint.attempt_seq or 0) < cp.seq or tostring(act.checkpoint.stream_generation) ~= cp.g
      if stale and U.exists(a.paths.telemetry) then act = Writer.rebuild_activity(a) end
      if act then act.checkpoint = act.checkpoint or { stream_generation = cp.g, attempt_seq = cp.seq }; out[id] = act end
    end
  end
  return out
end

--- Consistent bootstrap: snapshot plus per-source checkpoints under the lock (SDD-081).
function S.bootstrap(ctx, opts)
  local _, state = B.txn(ctx, { purpose = "stream.bootstrap" }, function() return nil end)
  local checkpoints = S.attempt_checkpoints(ctx, state)
  local snap = B.derive(ctx, state, opts)
  snap.activity = S.activity_projections(state, checkpoints)
  return snap, { control = { g = ctx.board.journal_generation, seq = state.applied_seq }, attempts = checkpoints }, state
end

-- ---------------------------------------------------------------- reader
---@param opts { cursor?: table, filters?: table, history?: number, follow?: boolean, write: fun(line: string), on_idle?: fun() }
function S.new(ctx, opts)
  local self = setmetatable({ ctx = ctx, opts = opts, write = opts.write, filters = opts.filters or {}, pos = nil, sources = {}, emitted = 0, scanned = 0 }, S)
  return self
end

function S:emit(frame)
  self.write(F.encode(frame))
end

function S:cursor()
  local attempts = {}
  for id, src in pairs(self.sources) do attempts[id] = { g = tostring(src.g), seq = src.seq } end
  return Cur.encode({ board = self.ctx.board.board_id, control = { g = self.ctx.board.journal_generation, seq = self.control.seq }, attempts = attempts })
end

function S:wanted(rec)
  local f = self.filters
  if f.task and rec.task_id ~= f.task then return false end
  if f.attempt and rec.attempt_id ~= f.attempt then return false end
  if f.types then
    for _, t in ipairs(f.types) do
      local g = TYPE_GROUPS[t]
      if (g and g(rec.type)) or rec.type == t then return true end
    end
    return false
  end
  return true
end

--- Prime source positions from a cursor position set or the bootstrap checkpoints.
function S:position(pos, state)
  self.control = { seq = pos.control.seq, offset = 0 }
  -- byte offset of the first record after seq (sequential scan once)
  local off = 0
  J.each(self.ctx.root, function(rec, consumed) if rec.control_seq <= pos.control.seq then off = consumed else return false end end)
  self.control.offset = off
  for id, a in pairs(state.attempts) do self:add_source(id, a, pos.attempts[id]) end
end

function S:add_source(id, attempt, cp)
  if self.sources[id] or not attempt.paths then return end
  local src = { id = id, path = attempt.paths.telemetry, dir = attempt.paths.dir, g = cp and cp.g or nil, seq = cp and cp.seq or 0, offset = 0, buf = "" }
  -- locate the byte offset after the checkpoint within the current generation
  if cp and cp.seq > 0 then
    local text = U.read(src.path) or ""
    local pos, consumed = 1, 0
    while true do
      local nl = text:find("\n", pos, true); if not nl then break end
      local ok, rec = pcall(vim.json.decode, text:sub(pos, nl - 1), DECODE)
      if ok and type(rec) == "table" and tostring(rec.stream_generation) == tostring(cp.g) and rec.attempt_seq <= cp.seq then consumed = nl else break end
      pos = nl + 1
    end
    src.offset = consumed
  end
  self.sources[id] = src
end

--- Read new records from one telemetry source. Emits gap frames on generation changes.
function S:read_source(src, out)
  local st = uv.fs_stat(src.path)
  if not st or st.size <= src.offset then
    if st and st.size < src.offset then -- truncated/replaced file: treat as a gap and restart
      out[#out + 1] = { gap = { source = "attempt:" .. src.id, from = src.seq, to = 0, reason = "truncated" } }
      src.offset, src.seq, src.buf = 0, 0, ""
    end
    return
  end
  local fd = uv.fs_open(src.path, "r", 292); if not fd then return end
  local data = uv.fs_read(fd, st.size - src.offset, src.offset); uv.fs_close(fd)
  if not data then return end
  src.offset = src.offset + #data
  src.buf = src.buf .. data
  while true do
    local nl = src.buf:find("\n", 1, true); if not nl then break end
    local line = src.buf:sub(1, nl - 1); src.buf = src.buf:sub(nl + 1)
    local ok, rec = pcall(vim.json.decode, line, DECODE)
    if ok and type(rec) == "table" and rec.type then
      local g = tostring(rec.stream_generation)
      if src.g and g ~= src.g then
        out[#out + 1] = { gap = { source = "attempt:" .. src.id, from = src.seq, to = rec.attempt_seq, reason = "generation", generation = g } }
        src.g, src.seq = g, 0
      end
      src.g = src.g or g
      if rec.attempt_seq > src.seq then out[#out + 1] = { rec = rec, src = src } end
    end
  end
  if #src.buf > F.MAX_PARTIAL then src.buf = "" end
end

function S:read_control(out)
  local consumed = J.each(self.ctx.root, function(rec)
    if rec.control_seq > self.control.seq then out[#out + 1] = { rec = rec, control = true } end
  end, self.control.offset)
  self.control.offset = consumed
end

--- Discover attempt directories created after bootstrap.
function S:discover()
  for _, e in ipairs(U.list(self.ctx.paths.attempt_dirs)) do
    if e.type == "directory" and not self.sources[e.name] and P.valid_uuid(e.name) then
      local dir = self.ctx.paths.attempt_dirs .. "/" .. e.name
      self:add_source(e.name, { paths = { telemetry = dir .. "/telemetry.jsonl", dir = dir } }, nil)
    end
  end
end

local function sort_key(item)
  local r = item.rec
  return (r.observed_at or ""), item.control and 0 or 1, item.control and r.control_seq or r.attempt_seq
end

--- One pass: collect, order, emit. Returns the number of frames emitted.
function S:pump(opts)
  opts = opts or {}
  local batch = {}
  self:read_control(batch)
  self:discover()
  for _, src in pairs(self.sources) do self:read_source(src, batch) end
  table.sort(batch, function(a, b)
    if a.gap or b.gap then return (a.gap ~= nil) and not (b.gap ~= nil) end
    local ta, sa, na = sort_key(a); local tb, sb, nb = sort_key(b)
    if ta ~= tb then return ta < tb end
    if sa ~= sb then return sa < sb end
    if a.rec.attempt_id ~= b.rec.attempt_id then return tostring(a.rec.attempt_id) < tostring(b.rec.attempt_id) end
    return na < nb
  end)
  local n = 0
  for _, item in ipairs(batch) do
    if item.gap then
      self:emit(vim.tbl_extend("force", { frame = "gap" }, item.gap, { next_cursor = self:cursor() }))
      n = n + 1
    else
      if item.control then self.control.seq = item.rec.control_seq else item.src.seq = item.rec.attempt_seq end
      self.scanned = self.scanned + 1
      if self:wanted(item.rec) then
        if opts.collect then opts.collect[#opts.collect + 1] = { rec = item.rec, cursor = self:cursor() }
        else self:emit({ frame = "event", event = item.rec, next_cursor = self:cursor(), historical = opts.historical or nil }); n = n + 1; self.emitted = self.emitted + 1 end
      end
    end
  end
  return n
end

--- Run the whole protocol: hello, snapshot, replay, optional follow.
function S:run()
  local ctx, opts = self.ctx, self.opts
  local snap, checkpoints, state = S.bootstrap(ctx, {})
  local resumed, pos = nil, nil
  if opts.cursor then
    local kind, detail = Cur.check(opts.cursor, ctx.board, { control_seq = checkpoints.control.seq, attempts = checkpoints.attempts })
    if kind == "wrong_board" then self:emit({ frame = "error", code = "wrong_board", message = detail }); return 3
    elseif kind == "invalid_cursor" then self:emit({ frame = "error", code = "invalid_cursor", message = detail }); return 3
    elseif kind == "resync_required" then
      self:emit({ frame = "error", code = "resync_required", message = detail })
      self:emit({ frame = "gap", source = "control", from = opts.cursor.control.seq, to = 0, reason = "generation", next_cursor = "" })
      pos = checkpoints; resumed = "resync"
    else pos = opts.cursor; resumed = "cursor" end
  end
  self:emit({ frame = "hello", schema_version = P.SCHEMA_VERSION, board_id = ctx.board.board_id, journal_generation = ctx.board.journal_generation,
    capabilities = { attempts = true, telemetry = true, ack = true, history = 200, filters = { "types", "task", "attempt" } }, resumed_from = resumed })
  -- history: replay the most recent N feed records from the beginning as historical context
  if opts.history and opts.history > 0 and not opts.cursor then
    self:position({ control = { g = ctx.board.journal_generation, seq = 0 }, attempts = {} }, state)
    local collected = {}
    self:pump({ collect = collected })
    local start = math.max(1, #collected - math.min(opts.history, 200) + 1)
    -- the snapshot cursor sits just before the historical window so a consumer can resume from any of them
    snap.next_cursor = collected[start] and (start > 1 and collected[start - 1].cursor or Cur.encode({ board = ctx.board.board_id, control = { g = ctx.board.journal_generation, seq = 0 }, attempts = {} })) or self:cursor()
    self:emit(vim.tbl_extend("force", { frame = "snapshot" }, snap))
    for i = start, #collected do self:emit({ frame = "event", event = collected[i].rec, next_cursor = collected[i].cursor, historical = true }) end
  else
    self:position(pos or checkpoints, state)
    snap.next_cursor = self:cursor()
    self:emit(vim.tbl_extend("force", { frame = "snapshot" }, snap))
    self:pump()
  end
  if not opts.follow then self:emit({ frame = "status", state = "end", next_cursor = self:cursor() }); return 0 end
  self:emit({ frame = "status", state = "live", next_cursor = self:cursor() })
  -- follow: fs events wake the reader early; polling guarantees progress
  local pending = false
  local function wake() pending = true end
  local watchers = {}
  if not os.getenv("AISWARM_NO_FS_EVENTS") then
    for _, dir in ipairs({ ctx.paths.control, ctx.paths.attempt_dirs }) do
      local ev = uv.new_fs_event()
      if ev and ev:start(dir, {}, function() wake() end) then watchers[#watchers + 1] = ev end
    end
  end
  local poll_ms = tonumber(os.getenv("AISWARM_STREAM_POLL_MS")) or S.POLL_MS
  local timer = uv.new_timer()
  local stop = false
  timer:start(poll_ms, poll_ms, function()
    pending = false
    if uv.os_getppid() == 1 then stop = true; return end   -- the consumer/editor that started us is gone
    local ok, err = pcall(function() self:pump() end)
    if not ok then stop = true; self.error = err end
    if opts.stop_after and self.emitted >= opts.stop_after then stop = true end
  end)
  while not stop do uv.run("once") end
  timer:stop(); timer:close()
  for _, w in ipairs(watchers) do w:stop() end
  if self.error then self:emit({ frame = "error", code = "reader_failed", message = tostring(self.error) }); return 1 end
  self:emit({ frame = "status", state = "end", next_cursor = self:cursor() })
  return 0
end

return S
