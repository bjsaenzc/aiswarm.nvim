-- Durable external consumer fixture (SDD-086): reads `aiswarm stream --follow --consumer NAME`,
-- deduplicates by event_id, persists accepted batches to an inbox file (fsync) and acknowledges
-- only afterwards. Fault points (AISWARM_CONSUMER_FAULT): before_accept | after_accept | after_ack.
--   nvim -l consumer.lua --bin <aiswarm> --root <root> --name <consumer> --inbox <file> [--max N] [--exit-after-idle MS]
local uv = vim.uv
local args = {}
local argv = _G.arg or {}
for i = 1, #argv, 2 do args[argv[i]:gsub("^%-%-", "")] = argv[i + 1] end
local fault, max = vim.env.AISWARM_CONSUMER_FAULT, tonumber(args.max or 0)
local inbox = args.inbox
local seen = {}
for line in ((function() local f = io.open(inbox, "r"); if not f then return "" end local s = f:read("*a"); f:close(); return s end)()):gmatch("[^\n]+") do
  local ok, rec = pcall(vim.json.decode, line); if ok and rec.event_id then seen[rec.event_id] = true end
end
local accepted, batch, last_cursor, faulted = 0, {}, nil, false
local env = vim.fn.environ()
env.AISWARM_ROOT = args.root
local envlist = {}
for k, v in pairs(env) do envlist[#envlist + 1] = k .. "=" .. v end
local stdout = uv.new_pipe(false)
-- --history is ignored by the stream once the consumer has a bookmark; on the first run it supplies context
local proc = uv.spawn(args.bin, { args = { "stream", "--follow", "--consumer", args.name, "--history", "200" }, env = envlist, stdio = { nil, stdout, nil } }, function() end)
local buf = ""
local idle_timer = uv.new_timer()
local acking = false
local function ack(on_done)
  if not last_cursor then return on_done() end
  acking = true
  local cursor = last_cursor
  local handle
  handle = uv.spawn(args.bin, { args = { "ack", "--consumer", args.name, "--cursor", cursor }, env = envlist, stdio = { nil, nil, nil } }, function(code)
    acking = false
    io.stdout:write(("ACK %s\n"):format(code)); io.stdout:flush()
    if handle then handle:close() end
    on_done(code)
  end)
  if not handle then acking = false; on_done(1) end
end
local function flush_batch()
  if #batch == 0 or acking then return end
  if fault == "before_accept" and not faulted then faulted = true; io.stdout:write("FAULT before_accept\n"); io.stdout:flush(); os.exit(9) end
  local f = assert(io.open(inbox, "a"))
  for _, ev in ipairs(batch) do
    local sec, usec = uv.gettimeofday()
    f:write(vim.json.encode({ event_id = ev.event_id, type = ev.type, task_id = ev.task_id, attempt_id = ev.attempt_id, received_at_ms = sec * 1000 + math.floor(usec / 1000), received_wall = ev.received_wall, observed_at = ev.observed_at }), "\n")
  end
  f:flush()
  local fd = uv.fs_open(inbox, "a", 420); if fd then uv.fs_fsync(fd); uv.fs_close(fd) end
  f:close()
  accepted = accepted + #batch
  batch = {}
  if fault == "after_accept" and not faulted then faulted = true; io.stdout:write("FAULT after_accept\n"); io.stdout:flush(); os.exit(9) end
  ack(function()
    if fault == "after_ack" and not faulted then faulted = true; io.stdout:write("FAULT after_ack\n"); io.stdout:flush(); os.exit(9) end
    if max > 0 and accepted >= max then io.stdout:write("DONE " .. accepted .. "\n"); io.stdout:flush(); os.exit(0) end
  end)
end
local function reset_idle()
  local ms = tonumber(args["exit-after-idle"] or 0)
  if ms > 0 then idle_timer:stop(); idle_timer:start(ms, 0, function() io.stdout:write("IDLE " .. accepted .. "\n"); io.stdout:flush(); os.exit(0) end) end
end
stdout:read_start(function(err, data)
  if not data then return end
  buf = buf .. data
  while true do
    local nl = buf:find("\n", 1, true); if not nl then break end
    local line = buf:sub(1, nl - 1); buf = buf:sub(nl + 1)
    local ok, frame = pcall(vim.json.decode, line)
    if ok and type(frame) == "table" then
      if frame.frame == "event" then
        last_cursor = frame.next_cursor
        if not seen[frame.event.event_id] then seen[frame.event.event_id] = true; local sec, usec = uv.gettimeofday(); frame.event.received_wall = sec * 1000 + math.floor(usec / 1000); batch[#batch + 1] = frame.event end
        if #batch >= tonumber(args.batch or 5) then flush_batch() end
      elseif frame.frame == "status" and frame.state == "live" then
        last_cursor = frame.next_cursor; flush_batch()
      elseif frame.frame == "snapshot" then last_cursor = frame.next_cursor end
      reset_idle()
    end
  end
end)
local tick = uv.new_timer(); tick:start(300, 300, function() flush_batch() end)
reset_idle()
uv.run("default")
