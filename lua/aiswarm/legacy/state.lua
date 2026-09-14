-- A session owns one root, one snapshot request, and one ordered event cursor.
local H = function() return require("aiswarm") end
local S = {
  tasks = {}, meta = {}, seq = 0, snapshot_seq = 0, _subs = {},
  _generation = 0, _stopped = true, _pending = {}, _waiting = {},
}
local ORDER = { active = 1, ready = 2, failed = 3, done = 4 }
local DECODE = { luanil = { object = true, array = true } }

local function close_timer(timer)
  if timer and not timer:is_closing() then timer:stop(); timer:close() end
end
local function kill(job)
  if job then pcall(job.kill, job, 15) end
end

function S.subscribe(fn)
  table.insert(S._subs, fn)
  return function()
    for i, f in ipairs(S._subs) do if f == fn then table.remove(S._subs, i); break end end
  end
end
function S.emit(kind, payload)
  for _, fn in ipairs(vim.list_extend({}, S._subs)) do
    local ok, err = pcall(fn, kind, payload)
    if not ok then H().err("subscriber failed: " .. tostring(err)) end
  end
end
local function failure(err)
  if S.meta.error ~= err then
    S.meta.error = err
    S.emit("error", err)
    H().warn(err)
  end
end

local function decode_snapshot(text)
  local ok, snap = pcall(vim.json.decode, text, DECODE)
  if not ok or type(snap) ~= "table" or type(snap.seq) ~= "number"
    or snap.seq < 0 or snap.seq % 1 ~= 0 or type(snap.tasks) ~= "table"
    or not vim.islist(snap.tasks)
    or (snap.capabilities ~= nil and type(snap.capabilities) ~= "table") then
    return nil, "invalid hive json snapshot"
  end
  local ids, counts = {}, { ready = 0, active = 0, done = 0, failed = 0 }
  for _, t in ipairs(snap.tasks) do
    if type(t) ~= "table" or type(t.id) ~= "string" or not t.id:match("^[A-Za-z0-9][A-Za-z0-9_-]*$")
      or not ORDER[t.state] or ids[t.id] then
      return nil, "invalid task in hive json snapshot"
    end
    for _, key in ipairs({ "title", "provider", "created", "session" }) do
      if t[key] ~= nil and type(t[key]) ~= "string" then return nil, "invalid task " .. key end
    end
    for _, key in ipairs({ "outcome", "health", "blockers", "attempts" }) do
      if t[key] ~= nil and type(t[key]) ~= "table" then return nil, "invalid task " .. key end
    end
    for _, key in ipairs({ "elapsed_s", "duration_s", "priority", "cost_usd" }) do
      if t[key] ~= nil and type(t[key]) ~= "number" then return nil, "invalid task " .. key end
    end
    ids[t.id], counts[t.state] = true, counts[t.state] + 1
  end
  snap.counts = counts
  return snap
end

--- Serialize snapshots. Requests made in flight get a fresh subsequent snapshot.
--- cb(snapshot, error) runs on both success and failure.
function S.refresh(cb)
  if S._request then
    S._queued = true
    if cb then table.insert(S._waiting, cb) end
    return
  end
  local generation = S._generation
  local request = { callbacks = cb and { cb } or {} }
  S._request = request
  request.job = H().run({ "json" }, function(o)
    if generation ~= S._generation or S._request ~= request then return end
    local snap, err
    if o.code == 0 then snap, err = decode_snapshot(o.stdout)
    else err = H().failure(o) end
    if snap and S._initialized and snap.seq < S.snapshot_seq then
      snap, err = nil, "journal moved backwards; reopen the project after resetting a board"
    end
    if snap then
      local keep = {}
      for _, t in ipairs(snap.tasks) do
        t.last_progress = S.tasks[t.id] and S.tasks[t.id].last_progress
        keep[t.id] = t
      end
      S.tasks, snap.tasks = keep, nil
      S.meta, S.snapshot_seq = snap, snap.seq
      if not S._initialized then
        -- Historical events at attachment time are deliberately not replayed.
        if not S._received_event then S.seq = snap.seq end
        S._initialized = true
      end
      S.emit("refresh", snap)
      if not S._stopped then
        S.register_server()
        if H().config.follow then S.follow() end
        if snap.seq > S.seq then S.recover() end
      end
    else failure(err) end
    -- Leave _request set while callbacks run, so reentrant refreshes queue safely.
    for _, callback in ipairs(request.callbacks) do
      local ok, callback_err = pcall(callback, snap, err)
      if not ok then H().err(tostring(callback_err)) end
    end
    if generation ~= S._generation then return end
    S._request = nil
    if S._queued then
      local callbacks = S._waiting
      S._queued, S._waiting = false, {}
      S.refresh(function(next_snap, next_err)
        for _, callback in ipairs(callbacks) do
          local ok, callback_err = pcall(callback, next_snap, next_err)
          if not ok then H().err(tostring(callback_err)) end
        end
      end)
    end
  end)
end

function S.list()
  local out = vim.tbl_values(S.tasks)
  table.sort(out, function(a, b)
    local oa, ob = ORDER[a.state] or 9, ORDER[b.state] or 9
    if oa ~= ob then return oa < ob end
    if a.state == "ready" and (a.priority or 50) ~= (b.priority or 50) then
      return (a.priority or 50) < (b.priority or 50)
    end
    if (a.created or "") ~= (b.created or "") then return (a.created or "") < (b.created or "") end
    return a.id < b.id
  end)
  return out
end
function S.ids() return vim.tbl_map(function(t) return t.id end, S.list()) end
function S.statusline()
  if S.meta.error then return "hive: disconnected" end
  local c = S.meta.counts or {}
  if next(c) == nil then return "" end
  return string.format("%sR:%d A:%d ✓%d ✗%d", S.meta.paused and "⏸ " or "",
    c.ready or 0, c.active or 0, c.done or 0, c.failed or 0)
end

local NOTIFY_KEY = { done = "completed", failed = "failed", started = "started", progress = "progress" }
local function deliver(e)
  if e.type == "progress" and S.tasks[e.task] then S.tasks[e.task].last_progress = vim.uv.now() end
  local key = NOTIFY_KEY[e.type]
  if key and H().config.notify[key] then
    local title = (S.tasks[e.task] or {}).title
    local reason = e.type == "failed" and e.rc == "orphaned" and "orphaned" or e.type
    local msg = reason .. " " .. (e.task or "") .. (title and ("\n" .. title) or "")
    H().notify(msg, e.type == "failed" and vim.log.levels.ERROR or vim.log.levels.INFO)
  end
  S.emit("event", e)
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "AISwarmEvent", data = e })
  if not ok then H().err("AISwarmEvent callback failed: " .. tostring(err)) end
  require("aiswarm.compat").emit_hive_event(e)
end

--- Deduplicate and buffer out-of-order push events until the journal fills gaps.
function S.on_event(e)
  if S._stopped or type(e) ~= "table" or type(e.seq) ~= "number" or e.seq < 1
    or e.seq % 1 ~= 0 or type(e.type) ~= "string"
    or (e.task ~= nil and type(e.task) ~= "string") then return false end
  if e.seq <= S.seq then return true end
  S._received_event = true
  S._pending[e.seq] = e
  local changed, generation = false, S._generation
  while S._pending[S.seq + 1] do
    local event = S._pending[S.seq + 1]
    S.seq = S.seq + 1
    S._pending[S.seq] = nil
    changed = changed or (event.type ~= "message" and event.type ~= "progress")
    deliver(event)
    if generation ~= S._generation then return true end
  end
  if changed then S.refresh() end
  if next(S._pending) and not S._recovery then S.recover() end
  return true
end
function S.on_event_json(text, root)
  if root and vim.fs.normalize(root):gsub("/$", "") ~= H().root() then return false end
  local ok, e = pcall(vim.json.decode, text, DECODE)
  return ok and S.on_event(e) or false
end

function S.recover()
  if S._recovery or S._stopped then return end
  local request, generation = {}, S._generation
  S._recovery = request
  request.job = H().run({ "events", "--since", tostring(S.seq) }, function(o)
    if generation ~= S._generation or S._recovery ~= request then return end
    if o.code == 0 then
      for line in (o.stdout or ""):gmatch("[^\n]+") do S.on_event_json(line) end
    else failure("event recovery: " .. H().failure(o)) end
    if generation ~= S._generation then return end
    S._recovery = nil -- periodic snapshots retry gaps, including a lost final push
  end)
end

function S.follow()
  if S._follow or S._reconnect or S._stopped then return end
  local generation, token = S._generation, {}
  S._follow_token, S._linebuf = token, ""
  local function current() return generation == S._generation and S._follow_token == token end
  local function restart()
    if not current() then return end
    S._follow, S._linebuf = nil, ""
    local timer = vim.uv.new_timer()
    S._reconnect = timer
    timer:start(2000, 0, vim.schedule_wrap(function()
      close_timer(timer)
      if not current() then return end
      S._reconnect = nil
      S.follow()
    end))
  end
  local ok, job = pcall(vim.system, H().cmd({ "events", "--since", tostring(S.seq), "--follow" }), {
    env = H().env(), stderr = false,
    stdout = vim.schedule_wrap(function(err, data)
      if not current() then return end
      if err then failure("event stream: " .. tostring(err)) end
      if not data then return end
      S._linebuf = S._linebuf .. data
      while true do
        local nl = S._linebuf:find("\n", 1, true)
        if not nl then break end
        local line = S._linebuf:sub(1, nl - 1)
        S._linebuf = S._linebuf:sub(nl + 1)
        if line ~= "" then S.on_event_json(line) end
        if not current() then return end
      end
    end),
  }, vim.schedule_wrap(restart))
  if ok then S._follow = job
  else failure("event follower: " .. tostring(job)); restart() end
end

function S.unregister_server()
  local reg = S._registration
  S._registration = nil
  if not reg then return end
  local ok, lines = pcall(vim.fn.readfile, reg.path)
  if ok and lines[1] == reg.server then os.remove(reg.path) end
end
function S.register_server()
  if S._registration or not H().config.register_server then return end
  local path = H().root() .. "/nvim.server"
  local ok, err = pcall(function()
    local server = vim.v.servername
    if server == "" then server = vim.fn.serverstart() end
    assert(server ~= "", "could not start Neovim server")
    local tmp = path .. "." .. vim.fn.getpid()
    if vim.fn.writefile({ server }, tmp) ~= 0 then error("could not write " .. tmp) end
    local renamed, rename_err = os.rename(tmp, path)
    if not renamed then os.remove(tmp); error(rename_err) end
    S._registration = { path = path, server = server }
  end)
  if not ok then
    H().warn("push registration failed: " .. tostring(err))
    -- Retry on explicit setup, not every snapshot.
    S._registration = { path = path, server = false }
  end
end

function S.stop()
  S._stopped, S._generation = true, S._generation + 1
  close_timer(S._poll); close_timer(S._reconnect)
  kill(S._follow); kill(S._request and S._request.job); kill(S._recovery and S._recovery.job)
  S._poll, S._reconnect, S._follow, S._follow_token = nil, nil, nil, nil
  S._request, S._recovery, S._queued, S._waiting, S._linebuf = nil, nil, false, {}, ""
  S.unregister_server()
end
function S.start(root)
  S._stopped, S._initialized, S._received_event = false, false, false
  S.root = root or H().root()
  S.tasks, S.meta, S.seq, S.snapshot_seq, S._pending = {}, {}, 0, 0, {}
  S.emit("refresh", S.meta)
  local generation = S._generation
  local group = vim.api.nvim_create_augroup("AISwarmLifecycle", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = S.stop })
  S._poll = vim.uv.new_timer()
  S._poll:start(H().config.dashboard.refresh_ms, H().config.dashboard.refresh_ms, vim.schedule_wrap(function()
    if generation == S._generation and vim.fn.isdirectory(H().root()) == 1 then S.refresh() end
  end))
  if vim.fn.isdirectory(H().root()) == 1 then S.refresh() end
end
return S
