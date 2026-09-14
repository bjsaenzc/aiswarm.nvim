-- Owned board mutation lock with liveness-based stale recovery (SDD-019, ADR 0002).
local uv = vim.uv
local U = require("aiswarm.runtime.util")
local L = {}

L.WAIT_MS, L.STEP_MS, L.ORPHAN_MS = 10000, 25, 2000

local function lock_dir(root) return root .. "/locks/control.d" end
local function owner_path(root) return lock_dir(root) .. "/owner.json" end

--- Diagnose an existing lock: "alive", "dead", "orphan" (no owner file for a while), "unknown".
function L.inspect(root)
  local dir = lock_dir(root)
  local st = uv.fs_stat(dir)
  if not st then return "free" end
  local owner = U.read_json(owner_path(root))
  if not owner then
    local age_ms = (U.now_s() - (st.mtime.sec + st.mtime.nsec / 1e9)) * 1000
    return age_ms > L.ORPHAN_MS and "orphan" or "pending", nil
  end
  if U.exists(root .. "/locks/migration.marker") and owner.purpose ~= "migration" then
    -- a migration marker exists: writers must not proceed even if the marker owner died
  end
  local alive = U.owner_alive(owner)
  if alive == true then return "alive", owner end
  if alive == false then return "dead", owner end
  return "unknown", owner
end

--- Rename a provably stale lock aside; returns true when this contender won the recovery.
local function recover(root, why)
  local aside = ("%s/locks/stale-%s-%d.d"):format(root, os.date("!%Y%m%dT%H%M%S"), uv.os_getpid())
  local ok = uv.fs_rename(lock_dir(root), aside)
  if ok then
    U.write_atomic(aside .. "/recovered.json", vim.json.encode({ reason = why, at = U.now_iso(), by = U.identity() }))
  end
  return ok
end

--- Acquire the control lock. Returns a handle or nil, err (actionable).
---@param opts? { timeout_ms?: number, purpose?: string, migration?: boolean }
function L.acquire(root, opts)
  opts = opts or {}
  U.mkdirp(root .. "/locks")
  local deadline = U.now_s() + (opts.timeout_ms or L.WAIT_MS) / 1000
  local dir = lock_dir(root)
  while true do
    if not opts.migration and U.exists(root .. "/locks/migration.marker") then
      local m = U.read_json(root .. "/locks/migration.marker") or {}
      return nil, ("board is being migrated (started %s by pid %s); retry after migration completes or run `aiswarm migrate --resume`"):format(tostring(m.started_at), tostring(m.pid))
    end
    local ok = uv.fs_mkdir(dir, 493)
    if ok then
      local handle = { root = root, dir = dir, owner = U.identity() }
      handle.owner.acquired_at, handle.owner.purpose = U.now_iso(), opts.purpose or "mutation"
      local wok, werr = U.write_atomic(owner_path(root), vim.json.encode(handle.owner))
      if not wok then uv.fs_rmdir(dir); return nil, "cannot write lock owner: " .. tostring(werr) end
      return handle
    end
    local state, owner = L.inspect(root)
    if state == "dead" then
      recover(root, "owner pid " .. tostring(owner.pid) .. " is dead")
    elseif state == "orphan" then
      recover(root, "lock directory without an owner file")
    elseif state == "unknown" then
      return nil, ("control lock is held by an unknown owner (%s); remove %s only if you are certain it is not running"):format(vim.inspect(owner), dir)
    end
    if U.now_s() >= deadline then
      return nil, ("timed out waiting for the control lock held by pid %s (%s, since %s); if that process is gone, it will be recovered automatically on the next attempt"):format(
        tostring(owner and owner.pid), tostring(owner and owner.purpose), tostring(owner and owner.acquired_at))
    end
    uv.sleep(L.STEP_MS)
  end
end

function L.release(handle)
  if not handle or handle.released then return end
  handle.released = true
  -- Only remove the lock if it is still ours (recovery may have renamed it away).
  local owner = U.read_json(owner_path(handle.root))
  if owner and owner.pid == handle.owner.pid and owner.acquired_at == handle.owner.acquired_at then
    os.remove(owner_path(handle.root))
    uv.fs_rmdir(handle.dir)
  end
end

--- Run fn under the lock; releases on error and re-raises.
function L.with(root, opts, fn)
  local handle, err = L.acquire(root, opts)
  if not handle then error({ code = 4, message = err }, 0) end
  local results = { pcall(fn, handle) }
  L.release(handle)
  if not results[1] then error(results[2], 0) end
  return unpack(results, 2, table.maxn(results))
end

return L
