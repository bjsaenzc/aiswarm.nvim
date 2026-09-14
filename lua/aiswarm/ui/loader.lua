-- Cancellable, bounded asynchronous file reads with selection tokens and identity cache (SDD-054).
local uv = vim.uv
local M = { cache = {}, cache_order = {}, stats = { reads = 0, hits = 0, stale = 0 } }
M.MAX_CACHE = 64

local function remember(key, value)
  M.cache[key] = value
  M.cache_order[#M.cache_order + 1] = key
  if #M.cache_order > M.MAX_CACHE then M.cache[table.remove(M.cache_order, 1)] = nil end
end

---@class aiswarm.LoadResult
---@field status "content"|"empty"|"missing"|"error"|"cancelled"
---@field text? string
---@field size? number
---@field truncated? boolean
---@field error? string
---@field mtime? number

--- Read up to `max_bytes` (from the tail when tail=true). cb(result) on the main loop, only if
--- `is_current()` still returns true at delivery time.
---@param opts { max_bytes?: number, tail?: boolean, token?: any, is_current?: fun(): boolean, delay_ms?: number }
function M.read(path, opts, cb)
  opts = opts or {}
  local max_bytes = opts.max_bytes or 2 * 1024 * 1024
  local current = opts.is_current or function() return true end
  local function deliver(res)
    vim.schedule(function()
      if not current() then M.stats.stale = M.stats.stale + 1; return end
      cb(res)
    end)
  end
  if not path then return deliver({ status = "missing" }) end
  M.stats.reads = M.stats.reads + 1
  uv.fs_stat(path, function(serr, st)
    if serr or not st then return deliver({ status = serr and serr:match("ENOENT") and "missing" or "error", error = serr }) end
    if st.type == "directory" then return deliver({ status = "error", error = "is a directory" }) end
    local key = ("%s:%d:%d"):format(path, st.mtime.sec, st.size)
    if M.cache[key] then M.stats.hits = M.stats.hits + 1; return deliver(M.cache[key]) end
    if st.size == 0 then local r = { status = "empty", size = 0, mtime = st.mtime.sec }; remember(key, r); return deliver(r) end
    local n = math.min(st.size, max_bytes)
    local offset = opts.tail and (st.size - n) or 0
    uv.fs_open(path, "r", 292, function(oerr, fd)
      if oerr or not fd then return deliver({ status = "error", error = oerr }) end
      local function finish()
        uv.fs_read(fd, n, offset, function(rerr, data)
          uv.fs_close(fd)
          if rerr then return deliver({ status = "error", error = rerr }) end
          if opts.tail and offset > 0 and data then
            local nl = data:find("\n", 1, true)
            if nl then data = data:sub(nl + 1) end
          end
          local r = { status = "content", text = data or "", size = st.size, truncated = st.size > max_bytes, mtime = st.mtime.sec }
          remember(key, r)
          deliver(r)
        end)
      end
      if opts.delay_ms and opts.delay_ms > 0 then
        local t = uv.new_timer(); t:start(opts.delay_ms, 0, function() t:close(); finish() end)
      else finish() end
    end)
  end)
end

function M.reset() M.cache, M.cache_order = {}, {} end

return M
