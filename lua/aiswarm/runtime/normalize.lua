-- Incremental normalization of raw provider output (SDD-074): UTF-8 safe line splitting across
-- callbacks, bounded previews, and generic (non-native) records that never invent structure.
local T_LIMIT = require("aiswarm.protocol").LIMITS
local N = {}
N.__index = N

N.MAX_LINE = 64 * 1024

--- Number of trailing bytes that form an incomplete UTF-8 sequence (0..3).
function N.incomplete_utf8_tail(s)
  local n = #s
  if n == 0 then return 0 end
  for back = 1, math.min(3, n) do
    local b = s:byte(n - back + 1)
    if b >= 0xC0 then
      local need = b >= 0xF0 and 4 or (b >= 0xE0 and 3 or 2)
      return back < need and back or 0
    elseif b < 0x80 then return 0 end
  end
  return 0
end

--- Strip control/OSC sequences and clamp for a preview (bytes, not cells).
function N.preview(s, max)
  max = max or T_LIMIT.preview
  s = s:gsub("\27%][^\7\27]*\7", ""):gsub("\27%[[%d;?<>=!]*[%a@`]", ""):gsub("\27.", ""):gsub("\r", ""):gsub("[%z\1-\8\11\12\14-\31\127]", "")
  if #s > max then
    s = s:sub(1, max)
    s = s:sub(1, #s - N.incomplete_utf8_tail(s)) .. "…"
  end
  return s
end

function N.new(opts)
  opts = opts or {}
  return setmetatable({ buf = "", lines = 0, bytes = 0, oversized = 0, max_line = opts.max_line or N.MAX_LINE, adapter = opts.adapter }, N)
end

--- Feed bytes; returns complete lines (UTF-8 boundary safe) and the pending partial length.
---@return string[] lines
function N:feed(data)
  self.bytes = self.bytes + #data
  self.buf = self.buf .. data
  local out = {}
  while true do
    local nl = self.buf:find("\n", 1, true)
    if not nl then break end
    local line = self.buf:sub(1, nl - 1)
    self.buf = self.buf:sub(nl + 1)
    if #line > self.max_line then self.oversized = self.oversized + 1; line = line:sub(1, self.max_line); line = line:sub(1, #line - N.incomplete_utf8_tail(line)) end
    out[#out + 1] = line
    self.lines = self.lines + 1
  end
  if #self.buf > self.max_line then
    -- a line that never ends: emit a bounded chunk, keep the (safe) tail
    local cut = self.max_line - N.incomplete_utf8_tail(self.buf:sub(1, self.max_line))
    out[#out + 1] = self.buf:sub(1, cut); self.oversized = self.oversized + 1; self.lines = self.lines + 1
    self.buf = self.buf:sub(cut + 1)
  end
  return out
end

--- Flush the trailing partial line at exit.
function N:finish()
  if self.buf == "" then return {} end
  local line = self.buf; self.buf = ""; self.lines = self.lines + 1
  return { line }
end

--- Try a provider-native adapter on a complete line. Returns a normalized record spec or nil,
--- plus a diagnostic when the adapter rejected malformed native input. Unknown → nil (raw stays).
function N:native(line)
  if not self.adapter or not self.adapter.parse_line then return nil end
  local ok, rec, diag = pcall(self.adapter.parse_line, line)
  if not ok then return nil, { message = "adapter parse error: " .. tostring(rec) } end
  return rec, diag
end

return N
