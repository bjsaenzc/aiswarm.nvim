-- Retention: rotate/evict closed raw-log segments and inactive attempt history (SDD-084).
-- Never deletes an open segment, a report, or control outcomes.
local uv = vim.uv
local U = require("aiswarm.runtime.util")
local B = require("aiswarm.runtime.board")
local P = require("aiswarm.protocol")
local M = {}

M.DEFAULTS = { raw_cap = 100 * 1024 * 1024, telemetry_cap = 50 * 1024 * 1024, inactive_days = 7, segment_bytes = 16 * 1024 * 1024 }

function M.limits()
  return {
    raw_cap = tonumber(os.getenv("AISWARM_RAW_CAP_BYTES")) or M.DEFAULTS.raw_cap,
    telemetry_cap = tonumber(os.getenv("AISWARM_TELEMETRY_CAP_BYTES")) or M.DEFAULTS.telemetry_cap,
    inactive_days = tonumber(os.getenv("AISWARM_RETENTION_DAYS")) or M.DEFAULTS.inactive_days,
    segment_bytes = tonumber(os.getenv("AISWARM_LOG_SEGMENT_BYTES")) or M.DEFAULTS.segment_bytes,
  }
end

--- Evict the oldest closed raw segments of an attempt dir until the combined size is under the cap.
--- `open` names the segment numbers currently being written (never evicted).
function M.enforce_raw_cap(dir, cap, open)
  local segs = {}
  local total = 0
  for _, e in ipairs(U.list(dir, "^std%a+%.%d+%.log$")) do
    local st = uv.fs_stat(dir .. "/" .. e.name)
    local stream, n = e.name:match("^(std%a+)%.(%d+)%.log$")
    segs[#segs + 1] = { path = dir .. "/" .. e.name, size = st and st.size or 0, n = tonumber(n), stream = stream }
    total = total + (st and st.size or 0)
  end
  table.sort(segs, function(a, b) return a.n < b.n end)
  local evicted = {}
  for _, s in ipairs(segs) do
    if total <= cap then break end
    if not (open and open[s.stream] == s.n) then
      os.remove(s.path); total = total - s.size; evicted[#evicted + 1] = s.path
      U.write_json_atomic(dir .. "/retention.json", { evicted_through = { [s.stream] = s.n }, at = U.now_iso(), reason = "raw cap " .. cap })
    end
  end
  return evicted, total
end

--- Full retention pass for a board.
function M.run(ctx, opts)
  opts = opts or {}
  local lim = M.limits()
  local days = opts.days or lim.inactive_days
  local st = B.read_state(ctx)
  local now = U.now_s()
  local report = { evicted_attempts = {}, evicted_segments = {}, kept = 0 }
  for id, a in pairs(st.attempts) do
    local dir = a.paths and a.paths.dir
    if dir and U.is_dir(dir) then
      if P.TERMINAL[a.state] then
        local finished = U.parse_iso(a.finished_at) or 0
        if now - finished > days * 86400 then
          -- inactive history: raw logs and telemetry go; report and config stay
          for _, e in ipairs(U.list(dir)) do
            if e.name:match("^std%a+%.%d+%.log$") or e.name:match("^telemetry") or e.name == "activity.json" or e.name == "inbox" or e.name == "prompt.rendered.md" then
              if not opts.dry_run then U.rm_rf(dir .. "/" .. e.name) end
            end
          end
          if not opts.dry_run then U.write_json_atomic(dir .. "/retention.json", { evicted = "history", at = U.now_iso(), reason = ("inactive for more than %d days"):format(days) }) end
          report.evicted_attempts[#report.evicted_attempts + 1] = id
        else
          if not opts.dry_run then local ev = M.enforce_raw_cap(dir, lim.raw_cap, {}); vim.list_extend(report.evicted_segments, ev) end
          report.kept = report.kept + 1
        end
      else report.kept = report.kept + 1 end
    end
  end
  return report
end

return M
