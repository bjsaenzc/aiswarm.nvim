-- Opaque composite cursors (SDD-082, ADR 0003): base64url of a versioned JSON position set.
local P = require("aiswarm.protocol")
local C = {}

local function b64url_encode(s)
  local b = vim.base64.encode(s)
  return (b:gsub("+", "-"):gsub("/", "_"):gsub("=+$", ""))
end
local function b64url_decode(s)
  s = s:gsub("-", "+"):gsub("_", "/")
  local pad = (4 - #s % 4) % 4
  local ok, out = pcall(vim.base64.decode, s .. string.rep("=", pad))
  return ok and out or nil
end

function C.encode(pos)
  return b64url_encode(vim.json.encode({ v = 1, board = pos.board, control = { g = pos.control.g, seq = pos.control.seq }, attempts = pos.attempts or {}, logs = pos.logs or {} }))
end

--- Decode and structurally validate. Returns pos or nil, err.
function C.decode(text)
  if type(text) ~= "string" or text == "" then return nil, "empty cursor" end
  local raw = b64url_decode(text)
  if not raw then return nil, "cursor is not base64url" end
  local ok, pos = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
  if not ok or type(pos) ~= "table" then return nil, "cursor is not JSON" end
  local vok, err = P.validate_cursor(pos)
  if not vok then return nil, err end
  pos.attempts, pos.logs = pos.attempts or {}, pos.logs or {}
  return pos
end

--- Compare with committed positions. Returns "ok" | "wrong_board" | "resync_required" | "invalid_cursor", detail.
function C.check(pos, board, committed)
  if pos.board ~= board.board_id then return "wrong_board", "cursor belongs to board " .. tostring(pos.board) end
  if pos.control.g ~= board.journal_generation then return "resync_required", ("cursor generation %s, journal generation %s"):format(tostring(pos.control.g), tostring(board.journal_generation)) end
  if pos.control.seq > committed.control_seq then return "invalid_cursor", ("cursor control seq %d beyond committed %d"):format(pos.control.seq, committed.control_seq) end
  for id, ap in pairs(pos.attempts) do
    local cp = committed.attempts and committed.attempts[id]
    if cp and ap.g == cp.g and ap.seq > cp.seq then return "invalid_cursor", ("cursor attempt %s seq %d beyond written %d"):format(id, ap.seq, cp.seq) end
  end
  return "ok"
end

--- Monotonic comparison for acknowledgements: true when `new` is >= `old` on every source.
function C.at_least(new, old)
  if new.control.g < old.control.g then return false end
  if new.control.g == old.control.g and new.control.seq < old.control.seq then return false end
  for id, op in pairs(old.attempts) do
    local np = new.attempts[id]
    if np and np.g == op.g and np.seq < op.seq then return false end
  end
  return true
end

return C
