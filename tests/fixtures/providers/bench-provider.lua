-- Exact-rate load generator for SDD-097 (no subprocesses): writes AISWARM_BENCH_PROGRESS_PER_S inbox
-- messages per second and AISWARM_BENCH_OUTPUT_BPS bytes of stdout per second for
-- AISWARM_BENCH_TASK_SECONDS seconds, then writes the attempt report. Run as `nvim -l bench-provider.lua`.
local uv = vim.uv
local per_s = tonumber(os.getenv("AISWARM_BENCH_PROGRESS_PER_S")) or 20
local bps = tonumber(os.getenv("AISWARM_BENCH_OUTPUT_BPS")) or 102400
local secs = tonumber(os.getenv("AISWARM_BENCH_TASK_SECONDS")) or 5
local inbox, report = os.getenv("AISWARM_INBOX"), os.getenv("AISWARM_REPORT_PATH")
local board, task, attempt = os.getenv("AISWARM_BOARD_ID") or "", os.getenv("AISWARM_TASK") or "", os.getenv("AISWARM_ATTEMPT") or ""
local TICK_MS = 50
local line = string.rep("x", 200) .. "\n"
local n = 0
local pid = uv.os_getpid()
local started = uv.hrtime()
local sent_bytes = 0
local function write_msg()
  n = n + 1
  local id = ("bench-%d-%d"):format(pid, n)
  local body = vim.json.encode({ message_id = id, board_id = board, task_id = task, attempt_id = attempt, type = "agent.progress", source = "worker_inbox",
    payload = { phase = "working", message = "bench step " .. n, provenance = "worker_report" } })
  local tmp = inbox .. "/." .. id .. ".tmp"
  local fd = uv.fs_open(tmp, "w", 420)
  if fd then uv.fs_write(fd, body, 0); uv.fs_close(fd); uv.fs_rename(tmp, inbox .. "/" .. id .. ".json") end
end
-- wall-clock pacing: whatever the timer lag, the amounts due since start are caught up each tick
local timer = uv.new_timer()
timer:start(0, TICK_MS, function()
  local elapsed = (uv.hrtime() - started) / 1e9
  local due_msgs = math.floor(elapsed * per_s)
  if inbox then while n < due_msgs do write_msg() end end
  local due_bytes = math.floor(elapsed * bps)
  local out = {}
  while sent_bytes + #line <= due_bytes do out[#out + 1] = line; sent_bytes = sent_bytes + #line end
  if #out > 0 then io.stdout:write(table.concat(out)); io.stdout:flush() end
  if elapsed >= secs then
    timer:stop()
    if report and report ~= "" then
      local f = io.open(report, "w")
      if f then f:write(("## Summary\nbench %d records\n\n## Files changed\n(none)\n\n## Decisions\n(none)\n\n## Verification\nnot run\n\n## Follow-ups\n(none)\n"):format(n)); f:close() end
    end
    io.stdout:flush()
    os.exit(0)
  end
end)
uv.run("default")
