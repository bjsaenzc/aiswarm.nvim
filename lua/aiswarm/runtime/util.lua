-- Filesystem, identity and time helpers shared by the runtime (SDD-005 primitives).
local uv = vim.uv
local U = {}

function U.now_iso()
  local sec, usec = uv.gettimeofday()
  return os.date("!%Y-%m-%dT%H:%M:%S", sec) .. ("%.3d"):format(math.floor(usec / 1000)):gsub("^", ".") .. "Z"
end
function U.now_s() local sec, usec = uv.gettimeofday(); return sec + usec / 1e6 end
function U.parse_iso(s)
  if type(s) ~= "string" then return nil end
  local y, mo, d, h, mi, se = s:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return nil end
  -- os.time interprets as local time; correct with the UTC offset
  local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(se), isdst = false })
  local utc = os.time(os.date("!*t", t)); local off = os.difftime(t, utc)
  local frac = tonumber(s:match("%.(%d+)Z?$") or "0") or 0
  local digits = #(s:match("%.(%d+)Z?$") or "")
  return t + off + (digits > 0 and frac / 10 ^ digits or 0)
end

local urandom
function U.uuid()
  if urandom == nil then urandom = uv.fs_open("/dev/urandom", "r", 292) or false end
  local b
  if urandom then b = uv.fs_read(urandom, 16, -1) end
  if not b or #b ~= 16 then
    math.randomseed(math.floor(uv.hrtime() % 2 ^ 31) + uv.os_getpid())
    local t = {}; for i = 1, 16 do t[i] = string.char(math.random(0, 255)) end; b = table.concat(t)
  end
  local bytes = { b:byte(1, 16) }
  bytes[7] = bit.bor(bit.band(bytes[7], 0x0f), 0x40); bytes[9] = bit.bor(bit.band(bytes[9], 0x3f), 0x80)
  local hex = {}
  for i = 1, 16 do hex[i] = ("%02x"):format(bytes[i]) end
  local s = table.concat(hex)
  return s:sub(1, 8) .. "-" .. s:sub(9, 12) .. "-" .. s:sub(13, 16) .. "-" .. s:sub(17, 20) .. "-" .. s:sub(21, 32)
end
function U.short(id) return (id or ""):sub(1, 8) end

function U.exists(p) return uv.fs_stat(p) ~= nil end
function U.is_dir(p) local st = uv.fs_stat(p); return st ~= nil and st.type == "directory" end
function U.mkdirp(p) vim.fn.mkdir(p, "p") end
function U.read(p)
  local fd = uv.fs_open(p, "r", 292); if not fd then return nil end
  local st = uv.fs_fstat(fd); local data = st and uv.fs_read(fd, st.size, 0) or nil
  uv.fs_close(fd); return data
end
function U.read_json(p)
  local s = U.read(p); if not s then return nil, "missing" end
  local ok, v = pcall(vim.json.decode, s, { luanil = { object = true, array = true } })
  if not ok then return nil, "invalid json: " .. tostring(v) end
  return v
end
local counter = 0
--- Write `data` to `path` atomically: tmp file, fsync, rename.
function U.write_atomic(path, data)
  counter = counter + 1
  local tmp = ("%s.tmp.%d.%d"):format(path, uv.os_getpid(), counter)
  local fd, err = uv.fs_open(tmp, "w", 420)
  if not fd then return false, err end
  local ok, werr = uv.fs_write(fd, data, 0)
  if not ok then uv.fs_close(fd); os.remove(tmp); return false, werr end
  uv.fs_fsync(fd); uv.fs_close(fd)
  local rok, rerr = uv.fs_rename(tmp, path)
  if not rok then os.remove(tmp); return false, rerr end
  return true
end
function U.write_json_atomic(path, tbl) return U.write_atomic(path, vim.json.encode(tbl)) end
--- Append `data` with O_APPEND and fsync (one write call).
function U.append_fsync(path, data)
  local fd, err = uv.fs_open(path, "a", 420)
  if not fd then return false, err end
  local ok, werr = uv.fs_write(fd, data, -1)
  if not ok then uv.fs_close(fd); return false, werr end
  local fok, ferr = uv.fs_fsync(fd)
  uv.fs_close(fd)
  if not fok then return false, ferr end
  return true
end
function U.list(dir, pattern)
  local out = {}
  local h = uv.fs_scandir(dir)
  if not h then return out end
  while true do
    local name, typ = uv.fs_scandir_next(h)
    if not name then break end
    if not pattern or name:match(pattern) then out[#out + 1] = { name = name, type = typ } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end
function U.rm_rf(path) return vim.fn.delete(path, "rf") == 0 end

-- ---------------------------------------------------------------- process identity
function U.pid_alive(pid) return type(pid) == "number" and pid > 0 and uv.kill(pid, 0) == 0 end
local own_start
--- Process start time string (ps lstart) — combined with the pid it survives PID reuse.
function U.pid_start(pid)
  pid = pid or uv.os_getpid()
  if pid == uv.os_getpid() and own_start then return own_start end
  local o = vim.system({ "ps", "-o", "lstart=", "-p", tostring(pid) }, { text = true }):wait(2000)
  local s = o and o.code == 0 and vim.trim(o.stdout or "") or ""
  if pid == uv.os_getpid() and s ~= "" then own_start = s end
  return s ~= "" and s or nil
end
function U.identity()
  return { pid = uv.os_getpid(), pid_start = U.pid_start(), host = uv.os_gethostname() }
end
--- True when `owner` ({pid, pid_start, host}) is provably the same live process.
function U.owner_alive(owner)
  if type(owner) ~= "table" or type(owner.pid) ~= "number" then return nil end
  if owner.host and owner.host ~= uv.os_gethostname() then return nil end -- unknown: different host
  if not U.pid_alive(owner.pid) then return false end
  if owner.pid_start then
    local s = U.pid_start(owner.pid)
    if s and s ~= owner.pid_start then return false end -- PID reused
  end
  return true
end
--- Kill a process group (negative pid) or process. Returns true if the signal was delivered.
function U.kill(pid, sig) return uv.kill(pid, sig or "sigterm") == 0 end

--- Minimal argv parser: positionals + --key value + --flag. `bools` lists flags without values.
function U.parse_args(argv, bools)
  bools = bools or {}
  local pos, opts, i = {}, {}, 1
  while i <= #argv do
    local a = argv[i]
    if a == "--" then for j = i + 1, #argv do pos[#pos + 1] = argv[j] end break end
    local key = a:match("^%-%-([%w%-]+)$")
    local kv, vv = a:match("^%-%-([%w%-]+)=(.*)$")
    if kv then opts[kv:gsub("%-", "_")] = vv; i = i + 1
    elseif key then
      local k = key:gsub("%-", "_")
      if bools[k] or bools[key] then opts[k] = true; i = i + 1
      else
        local v = argv[i + 1]
        if v == nil then return nil, "missing value for --" .. key end
        if opts[k] ~= nil then
          if type(opts[k]) ~= "table" then opts[k] = { opts[k] } end
          table.insert(opts[k], v)
        else opts[k] = v end
        i = i + 2
      end
    else pos[#pos + 1] = a; i = i + 1 end
  end
  return { pos = pos, opts = opts }
end

return U
