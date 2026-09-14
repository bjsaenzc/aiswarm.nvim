-- Stream frame codec: JSONL with additive-field tolerance, schema checks and a 256 KiB partial limit (SDD-078).
local P = require("aiswarm.protocol")
local F = {}
F.__index = F
F.MAX_PARTIAL = 256 * 1024
F.KINDS = { hello = true, snapshot = true, event = true, gap = true, status = true, error = true }

function F.encode(frame) return vim.json.encode(frame) .. "\n" end

--- Validate a decoded frame. Returns ok, err, kind ("incompatible" for unsupported schema majors).
function F.validate(frame)
  if type(frame) ~= "table" or type(frame.frame) ~= "string" then return false, "frame must carry a frame kind" end
  if not F.KINDS[frame.frame] then return false, "unknown frame kind: " .. frame.frame end
  if frame.frame == "hello" then
    if type(frame.schema_version) ~= "number" then return false, "hello lacks schema_version" end
    if frame.schema_version > P.SCHEMA_VERSION then return false, "unsupported schema_version " .. frame.schema_version, "incompatible" end
    if not P.valid_uuid(frame.board_id) then return false, "hello lacks board_id" end
  elseif frame.frame == "event" then
    if type(frame.event) ~= "table" or type(frame.event.type) ~= "string" then return false, "event frame lacks an event" end
    if type(frame.next_cursor) ~= "string" then return false, "event frame lacks next_cursor" end
  elseif frame.frame == "snapshot" then
    if type(frame.tasks) ~= "table" or type(frame.next_cursor) ~= "string" then return false, "snapshot lacks tasks/next_cursor" end
  elseif frame.frame == "error" then
    if type(frame.code) ~= "string" then return false, "error frame lacks code" end
  end
  return true
end

--- Incremental decoder. feed(data) -> frames[], diagnostics[]
function F.decoder()
  return setmetatable({ buf = "", frames = 0, dropped = 0, resyncing = false }, F)
end

function F:feed(data)
  local out, diags = {}, {}
  self.buf = self.buf .. data
  while true do
    local nl = self.buf:find("\n", 1, true)
    if not nl then
      if #self.buf > F.MAX_PARTIAL then
        -- oversized partial frame: discard and resync at the next newline
        self.dropped = self.dropped + 1
        diags[#diags + 1] = { code = "oversized_frame", bytes = #self.buf }
        self.buf, self.resyncing = "", true
      end
      break
    end
    local line = self.buf:sub(1, nl - 1)
    self.buf = self.buf:sub(nl + 1)
    if self.resyncing then
      self.resyncing = false   -- the remainder of the oversized frame ended here
    elseif line ~= "" then
      local ok, frame = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
      if not ok then self.dropped = self.dropped + 1; diags[#diags + 1] = { code = "malformed_frame", error = tostring(frame) }
      else
        local vok, err, kind = F.validate(frame)
        if vok then self.frames = self.frames + 1; out[#out + 1] = frame
        else self.dropped = self.dropped + 1; diags[#diags + 1] = { code = kind or "invalid_frame", error = err, frame = frame } end
      end
    end
  end
  return out, diags
end

return F
