-- Control journal: committed append with fsync, tail recovery and sequential reads (SDD-020/022, ADR 0002).
local uv = vim.uv
local U = require("aiswarm.runtime.util")
local J = {}
local DECODE = { luanil = { object = true, array = true } }

function J.path(root) return root .. "/control/journal.jsonl" end
function J.sidecar(root) return root .. "/control/seq" end
function J.quarantine_dir(root) return root .. "/control/quarantine" end

local function decode(line)
  local ok, v = pcall(vim.json.decode, line, DECODE)
  if ok and type(v) == "table" and type(v.control_seq) == "number" then return v end
  return nil
end
J.decode = decode

--- Read the tail: last complete record, committed seq, trailing fragment, incomplete txn records.
function J.tail(root)
  local path = J.path(root)
  local st = uv.fs_stat(path)
  if not st then return { size = 0, committed_seq = 0, records = {} } end
  local size = st.size
  local chunk = 65536
  local data = ""
  local pos = size
  -- read backwards until we have at least two newlines (last complete record) or reach the start
  while pos > 0 do
    local n = math.min(chunk, pos)
    pos = pos - n
    local fd = uv.fs_open(path, "r", 292)
    local piece = uv.fs_read(fd, n, pos); uv.fs_close(fd)
    data = piece .. data
    local _, count = data:gsub("\n", "")
    if count >= 2 or pos == 0 then
      -- ensure the data starts at a line boundary unless at file start
      if pos > 0 then
        local first_nl = data:find("\n", 1, true)
        data = data:sub(first_nl + 1); pos = pos + first_nl
      end
      -- if there is still no complete line, keep reading (single huge record)
      if select(2, data:gsub("\n", "")) >= 1 or pos == 0 then break end
    end
  end
  local lines, fragment = {}, nil
  local start = 1
  while true do
    local nl = data:find("\n", start, true)
    if not nl then fragment = data:sub(start); break end
    lines[#lines + 1] = data:sub(start, nl - 1)
    start = nl + 1
  end
  if fragment == "" then fragment = nil end
  local records = {}
  for _, l in ipairs(lines) do records[#records + 1] = { line = l, rec = decode(l) } end
  local last
  for i = #records, 1, -1 do if records[i].rec then last = records[i].rec; break end end
  return { size = size, committed_seq = last and last.control_seq or 0, last = last, fragment = fragment,
    records = records, tail_offset = pos }
end

--- Recovery under the lock: quarantine a trailing fragment / undecodable tail / incomplete txn, truncate.
---@return { committed_seq: number, quarantined: number, truncated: boolean }
function J.recover(root)
  local path = J.path(root)
  local t = J.tail(root)
  if t.size == 0 then
    U.write_atomic(J.sidecar(root), "0")
    return { committed_seq = 0, quarantined = 0, truncated = false }
  end
  local bad = {}       -- lines to quarantine (from the end)
  local keep_bytes = t.size
  if t.fragment then bad[#bad + 1] = t.fragment; keep_bytes = keep_bytes - #t.fragment end
  -- undecodable trailing lines and incomplete trailing transaction
  local i = #t.records
  while i >= 1 do
    local r = t.records[i]
    if not r.rec then bad[#bad + 1] = r.line; keep_bytes = keep_bytes - #r.line - 1; i = i - 1
    else break end
  end
  if i >= 1 and t.records[i].rec.txn and t.records[i].rec.txn.last == false then
    local txn_id = t.records[i].rec.txn.id
    while i >= 1 and t.records[i].rec and t.records[i].rec.txn and t.records[i].rec.txn.id == txn_id do
      bad[#bad + 1] = t.records[i].line; keep_bytes = keep_bytes - #t.records[i].line - 1; i = i - 1
    end
  end
  local truncated = false
  if #bad > 0 then
    U.mkdirp(J.quarantine_dir(root))
    local qpath = ("%s/%s-%d.jsonl"):format(J.quarantine_dir(root), os.date("!%Y%m%dT%H%M%S"), uv.os_getpid())
    local rev = {}
    for k = #bad, 1, -1 do rev[#rev + 1] = bad[k] end
    U.write_atomic(qpath, table.concat(rev, "\n") .. "\n")
    local fd = uv.fs_open(path, "r+", 420)
    uv.fs_ftruncate(fd, keep_bytes); uv.fs_fsync(fd); uv.fs_close(fd)
    truncated = true
  end
  local committed = 0
  if i >= 1 then committed = t.records[i].rec.control_seq
  elseif keep_bytes > 0 then
    -- the kept tail buffer had no decodable record; scan the whole file for the last valid one
    committed = 0
    J.each(root, function(rec) committed = rec.control_seq end)
  end
  U.write_atomic(J.sidecar(root), tostring(committed))
  return { committed_seq = committed, quarantined = #bad, truncated = truncated }
end

--- Append a committed transaction: one write, one fsync.
function J.append(root, records)
  local parts = {}
  for _, r in ipairs(records) do parts[#parts + 1] = vim.json.encode(r) end
  return U.append_fsync(J.path(root), table.concat(parts, "\n") .. "\n")
end

--- Iterate every decodable record from `offset` (default 0). fn(rec, line_end_offset) may return false to stop.
--- Returns the offset after the last complete line consumed.
function J.each(root, fn, offset)
  local path = J.path(root)
  local fd = uv.fs_open(path, "r", 292)
  if not fd then return offset or 0 end
  local pos, buf = offset or 0, ""
  local consumed = pos
  while true do
    local chunk = uv.fs_read(fd, 65536, pos)
    if not chunk or #chunk == 0 then break end
    pos = pos + #chunk
    buf = buf .. chunk
    local start = 1
    while true do
      local nl = buf:find("\n", start, true)
      if not nl then break end
      local line = buf:sub(start, nl - 1)
      start = nl + 1
      consumed = consumed + #line + 1
      local rec = decode(line)
      if rec and fn(rec, consumed) == false then uv.fs_close(fd); return consumed end
    end
    buf = buf:sub(start)
  end
  uv.fs_close(fd)
  return consumed
end

--- Records with control_seq > since (optionally at most `limit`).
function J.after(root, since, limit)
  local out = {}
  J.each(root, function(rec)
    if rec.control_seq > since then out[#out + 1] = rec; if limit and #out >= limit then return false end end
  end)
  return out
end

return J
