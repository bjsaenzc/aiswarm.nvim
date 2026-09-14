-- Scheduler ownership, atomic dispatch, worktree isolation, cancellation, reconciliation and
-- board-scoped session commands (SDD-028–035, SDD-037).
local uv = vim.uv
local U = require("aiswarm.runtime.util")
local B = require("aiswarm.runtime.board")
local O = require("aiswarm.runtime.ops")
local P = require("aiswarm.protocol")
local L = require("aiswarm.runtime.lock")
local T = require("aiswarm.runtime.tmux")
local M = {}
local fail = B.fail

M.STARTUP_DEADLINE_S = 30
M.DEFAULT_GRACE_S = 5

local function plugin_root() return _G.AISWARM_PLUGIN_ROOT or vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))) end
local function nvim_bin() return vim.env.AISWARM_NVIM or vim.v.progpath end
function M.worker_argv(root, attempt_id)
  return { nvim_bin(), "--clean", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n", "-l", plugin_root() .. "/runtime/worker.lua", "--root", root, "--attempt", attempt_id }
end
function M.child_env(ctx, extra)
  local env = { AISWARM_ROOT = ctx.root, HIVE_ROOT = ctx.root, AISWARM_BOARD_ID = ctx.board.board_id, AISWARM_NVIM = nvim_bin(), AISWARM_QUIET_LEGACY = "1",
    PATH = vim.env.PATH, HOME = vim.env.HOME, TMPDIR = vim.env.TMPDIR, TMUX_TMPDIR = vim.env.TMUX_TMPDIR, AISWARM_TMUX_SOCKET = vim.env.AISWARM_TMUX_SOCKET,
    AISWARM_WORKTREES = vim.env.AISWARM_WORKTREES, AISWARM_MAX_TURNS = vim.env.AISWARM_MAX_TURNS, AISWARM_MOCK_SLEEP = vim.env.AISWARM_MOCK_SLEEP,
    LANG = vim.env.LANG, LC_ALL = vim.env.LC_ALL, TERM = vim.env.TERM or "xterm-256color", USER = vim.env.USER, SHELL = vim.env.SHELL }
  for k, v in pairs(vim.fn.environ()) do if k:match("^AISWARM_") and env[k] == nil then env[k] = v end end
  for k, v in pairs(extra or {}) do env[k] = v end
  local out = {}
  for k, v in pairs(env) do if v ~= nil then out[k] = v end end
  return out
end

-- ---------------------------------------------------------------- worktrees (SDD-030)
local function project_dir(ctx) return vim.fs.dirname(ctx.root) end
local function worktrees_dir(ctx) return vim.env.AISWARM_WORKTREES or (ctx.board.scheduler_defaults or {}).worktrees_dir end

--- Effective cwd for a task; provisions/validates the worktree for isolation=worktree. Never falls back.
---@return string? cwd, table? isolation_info, string? err
function M.prepare_cwd(ctx, task, attempt_id)
  local base = project_dir(ctx)
  if task.isolation ~= "worktree" then return base, { mode = "shared", path = base } end
  local dir = worktrees_dir(ctx)
  if not dir or dir == "" then return nil, nil, "no worktrees directory configured" end
  if vim.fn.executable("git") == 0 then return nil, nil, "git is not installed" end
  local wt = dir .. "/" .. task.id
  local branch = "aiswarm/" .. task.id
  local function git(args, cwd) local o = vim.system(vim.list_extend({ "git", "-C", cwd or base }, args), { text = true }):wait(30000); return o.code, vim.trim(o.stdout or ""), vim.trim(o.stderr or "") end
  local code, top = git({ "rev-parse", "--show-toplevel" })
  if code ~= 0 then return nil, nil, "project is not a git repository: " .. base end
  if U.exists(wt) then
    local c2, wtop = git({ "rev-parse", "--show-toplevel" }, wt)
    local c3, common = git({ "rev-parse", "--git-common-dir" }, wt)
    local _, main_common = git({ "rev-parse", "--git-common-dir" })
    local function abs(p, cwd) if p:sub(1, 1) == "/" then return vim.fs.normalize(p) end return vim.fs.normalize(cwd .. "/" .. p) end
    if c2 ~= 0 or c3 ~= 0 or vim.fs.normalize(wtop) ~= vim.fs.normalize(wt) or abs(common, wt) ~= abs(main_common, base) then
      return nil, nil, ("existing path %s is not a worktree of this repository"):format(wt)
    end
    return wt, { mode = "worktree", path = wt, branch = branch, reused = true }
  end
  U.mkdirp(dir)
  local created_dir = not U.exists(wt)
  local c, _, err = git({ "worktree", "add", "-b", branch, wt })
  if c ~= 0 then
    c, _, err = git({ "worktree", "add", wt, branch })
    if c ~= 0 then
      if created_dir and U.exists(wt) then git({ "worktree", "remove", "--force", wt }); U.rm_rf(wt) end
      git({ "worktree", "prune" })
      return nil, nil, "git worktree add failed: " .. err
    end
  end
  U.write_json_atomic(wt .. "/.aiswarm-worktree.json", { board_id = ctx.board.board_id, task_id = task.id, attempt_id = attempt_id, created_at = U.now_iso() })
  return wt, { mode = "worktree", path = wt, branch = branch, created = true }
end

--- Remove a worktree created by a failed preparation for this board only.
function M.cleanup_worktree(ctx, info)
  if not info or info.mode ~= "worktree" or not info.created then return end
  local meta = U.read_json(info.path .. "/.aiswarm-worktree.json")
  if not meta or meta.board_id ~= ctx.board.board_id then return end
  vim.system({ "git", "-C", project_dir(ctx), "worktree", "remove", "--force", info.path }, { text = true }):wait(30000)
  U.rm_rf(info.path)
end

-- ---------------------------------------------------------------- dispatch (SDD-031)
local function running_count(state)
  local n = 0
  for _, t in pairs(state.tasks) do if t.state == "running" then n = n + 1 end end
  return n
end

--- One dispatch pass. Selection and attempt reservation happen under the control lock; the tmux
--- spawn happens outside it (it takes ~100 ms per worker and must not block worker commits); the
--- spawn outcome is then committed in a second short transaction. A concurrent dispatcher cannot
--- start a reserved task twice because it is already running with a current attempt.
--- opts.instance_id: scheduler identity that must own the board (nil = one-shot CLI, allowed only when no live scheduler).
function M.dispatch(ctx, opts)
  opts = opts or {}
  local report = { dispatched = {}, failed = {}, skipped = {} }
  local reserved = {}
  L.with(ctx.root, { purpose = "dispatch" }, function(lock)
    ctx.lock = lock
    local state = B.recover(ctx)
    local sched = state.scheduler or {}
    if sched.state == "running" and sched.owner then
      if opts.instance_id and sched.instance_id ~= opts.instance_id then report.skipped[#report.skipped + 1] = "another scheduler instance owns this board"; ctx.lock = nil; return end
      if not opts.instance_id and U.owner_alive(sched.owner) then report.skipped[#report.skipped + 1] = "a live scheduler owns dispatch; use scheduler pause/stop"; ctx.lock = nil; return end
    end
    if sched.paused then report.paused = true; ctx.lock = nil; return end
    local wip = tonumber(sched.wip) or (ctx.board.scheduler_defaults or {}).wip or 3
    local running = running_count(state)
    local queue = {}
    for _, t in pairs(state.tasks) do if t.state == "queued" then queue[#queue + 1] = t end end
    table.sort(queue, P.compare_queue)
    local records = {}
    for _, task in ipairs(queue) do
      if running >= wip then break end
      local blockers = P.blockers(task, state.tasks)
      if #blockers > 0 then report.skipped[#report.skipped + 1] = task.id .. ": " .. blockers[1].text
      else
        local attempt_id = U.uuid()
        local cwd, iso, ierr = M.prepare_cwd(ctx, task, attempt_id)
        local attempt, nt = O.reserve_attempt(ctx, task, { cwd = cwd, scheduler = sched.instance_id })
        attempt.attempt_id = attempt_id; attempt.paths = O.attempt_paths(ctx, attempt_id)
        nt.current_attempt_id = attempt_id; nt.attempts[#nt.attempts] = attempt_id
        attempt.config.isolation_info = iso
        if not cwd then
          attempt.state, attempt.finished_at, attempt.reason = "failed", U.now_iso(), "isolation_failed: " .. ierr
          attempt.report = { status = "missing" }
          local ft = vim.deepcopy(nt); ft.state = "failed"; ft.outcome = { attempt_id = attempt_id, reason = attempt.reason, finished_at = attempt.finished_at, report = "missing" }
          vim.list_extend(records, { { type = "attempt.reserved", task_id = task.id, attempt_id = attempt_id, payload = { attempt = attempt, task = nt } },
            { type = "attempt.finished", task_id = task.id, attempt_id = attempt_id, payload = { attempt = attempt } },
            { type = "task.finished", task_id = task.id, payload = { task = ft } } })
          report.failed[#report.failed + 1] = { id = task.id, reason = attempt.reason }
        else
          attempt.tmux = { session = T.session_name(ctx.board.board_id, attempt_id) }
          U.mkdirp(attempt.paths.dir)
          records[#records + 1] = { type = "attempt.reserved", task_id = task.id, attempt_id = attempt_id, payload = { attempt = attempt, task = nt } }
          reserved[#reserved + 1] = { attempt = attempt, cwd = cwd, iso = iso, task_id = task.id }
          running = running + 1
        end
      end
    end
    if #records > 0 then B.commit(ctx, state, records, opts.actor or "scheduler") end
    ctx.lock = nil
  end)
  -- spawn outside the lock
  for _, r in ipairs(reserved) do
    local ok, pane_or_err = M.spawn_worker(ctx, r.attempt, r.cwd)
    r.ok, r.pane, r.err = ok, ok and pane_or_err or nil, (not ok) and pane_or_err or nil
    if not ok then M.cleanup_worktree(ctx, r.iso) end
    uv.sleep(30)   -- pace session creation; pty allocation is flaky under tight bursts
  end
  if #reserved > 0 then
    L.with(ctx.root, { purpose = "dispatch.spawned" }, function(lock)
      ctx.lock = lock
      local state = B.recover(ctx)
      local records = {}
      for _, r in ipairs(reserved) do
        local cur = state.attempts[r.attempt.attempt_id]
        if cur and not P.TERMINAL[cur.state] then
          if r.ok then
            local a2 = vim.deepcopy(cur); a2.tmux = a2.tmux or {}; a2.tmux.pane = r.pane; a2.spawned_at = U.now_iso()
            if a2.state == "starting" then records[#records + 1] = { type = "attempt.reserved", task_id = r.task_id, attempt_id = a2.attempt_id, payload = { attempt = a2, task = state.tasks[r.task_id] } } end
            report.dispatched[#report.dispatched + 1] = { id = r.task_id, attempt_id = r.attempt.attempt_id, session = r.attempt.tmux.session }
          else
            local a2 = vim.deepcopy(cur)
            a2.state, a2.finished_at, a2.reason, a2.report = "failed", U.now_iso(), "spawn_failed: " .. tostring(r.err), { status = "missing" }
            local ft = vim.deepcopy(state.tasks[r.task_id]); ft.state = "failed"; ft.revision = ft.revision + 1
            ft.outcome = { attempt_id = a2.attempt_id, reason = a2.reason, finished_at = a2.finished_at, report = "missing" }
            vim.list_extend(records, { { type = "attempt.finished", task_id = r.task_id, attempt_id = a2.attempt_id, payload = { attempt = a2 } },
              { type = "task.finished", task_id = r.task_id, payload = { task = ft } } })
            report.failed[#report.failed + 1] = { id = r.task_id, reason = a2.reason }
          end
        elseif r.ok then
          report.dispatched[#report.dispatched + 1] = { id = r.task_id, attempt_id = r.attempt.attempt_id, session = r.attempt.tmux.session, note = "attempt already terminal (cancelled during spawn)" }
        end
      end
      if #records > 0 then B.commit(ctx, state, records, opts.actor or "scheduler") end
      ctx.lock = nil
    end)
  end
  return report
end

--- Start the worker for a reserved attempt in its own tmux session.
function M.spawn_worker(ctx, attempt, cwd)
  if not T.available() then return false, "tmux is not installed" end
  if vim.fn.executable(nvim_bin()) == 0 then return false, "Neovim runtime not found: " .. tostring(nvim_bin()) end
  local session = attempt.tmux.session
  local env = M.child_env(ctx, { AISWARM_TASK = attempt.task_id, AISWARM_ATTEMPT = attempt.attempt_id })
  return T.spawn(session, cwd, env, M.worker_argv(ctx.root, attempt.attempt_id), { board_id = ctx.board.board_id, attempt_id = attempt.attempt_id, task_id = attempt.task_id })
end

-- ---------------------------------------------------------------- reconciliation (SDD-035)
function M.reconcile(ctx, opts)
  opts = opts or {}
  local report = { orphaned = {}, startup_timeout = {}, quiet = {}, stale = {} }
  local now = U.now_s()
  L.with(ctx.root, { purpose = "reconcile" }, function(lock)
    ctx.lock = lock
    local state = B.recover(ctx)
    for _, a in pairs(state.attempts) do
      local task = state.tasks[a.task_id]
      if task and task.current_attempt_id == a.attempt_id and not P.TERMINAL[a.state] then
        local worker_alive = nil
        if a.worker then worker_alive = U.owner_alive(a.worker) end
        local session_alive = a.tmux and a.tmux.session and T.has(a.tmux.session) or false
        local pane_dead = session_alive and T.pane_dead(a.tmux.session) or nil
        if a.state == "starting" then
          local age = now - (U.parse_iso(a.reserved_at) or now)
          if worker_alive == nil and (pane_dead or not session_alive or age > (opts.startup_deadline_s or M.STARTUP_DEADLINE_S)) then
            local reason = (pane_dead or not session_alive) and "orphaned" or "startup_timeout"
            M.finish_locked(ctx, state, a, { state = "failed", reason = reason, actor = "reconcile" })
            report[reason == "orphaned" and "orphaned" or "startup_timeout"][#report[reason == "orphaned" and "orphaned" or "startup_timeout"] + 1] = a.task_id
          end
        elseif a.state == "running" then
          if worker_alive == false then
            M.finish_locked(ctx, state, a, { state = "failed", reason = "orphaned", actor = "reconcile" })
            report.orphaned[#report.orphaned + 1] = a.task_id
          else
            local h = B.health(ctx, a, now, opts)
            if h and h.stale then report.stale[#report.stale + 1] = a.task_id end
            if h and h.quiet then report.quiet[#report.quiet + 1] = a.task_id end
          end
        end
      end
    end
    ctx.lock = nil
  end)
  return report
end

--- Terminal outcome while already holding the lock (mirrors O.attempt_finished).
function M.finish_locked(ctx, state, a, outcome)
  if P.TERMINAL[a.state] then return end
  local na = vim.deepcopy(a)
  na.state, na.finished_at, na.reason = outcome.state, U.now_iso(), outcome.reason
  na.exit = { code = outcome.exit_code, signal = outcome.signal }
  na.report = O.report_quality(a.paths.report)
  local task = state.tasks[a.task_id]
  local records = { { type = "attempt.finished", task_id = a.task_id, attempt_id = a.attempt_id, payload = { attempt = na } } }
  if task and task.current_attempt_id == a.attempt_id then
    local nt = vim.deepcopy(task)
    nt.state, nt.revision, nt.updated_at = outcome.state, task.revision + 1, U.now_iso()
    nt.outcome = { attempt_id = a.attempt_id, reason = outcome.reason, exit_code = outcome.exit_code, finished_at = na.finished_at, report = na.report.status }
    records[#records + 1] = { type = outcome.state == "cancelled" and "task.cancelled" or "task.finished", task_id = task.id, payload = { task = nt } }
  end
  B.commit(ctx, state, records, outcome.actor)
end

-- ---------------------------------------------------------------- cancel (SDD-033)
--- Terminate an attempt's owned process tree: TERM, grace, KILL. Returns true if anything was signalled.
function M.terminate_tree(attempt, grace_s)
  local w = attempt.worker
  if not w then return false end
  local target = w.pgid and -w.pgid or w.pid
  if not target then return false end
  local signalled = U.kill(target, "sigterm")
  local deadline = U.now_s() + (grace_s or M.DEFAULT_GRACE_S)
  while U.now_s() < deadline do
    if not U.pid_alive(w.pid) then return signalled end
    uv.sleep(50)
  end
  U.kill(target, "sigkill")
  return signalled
end

function M.cancel(ctx, id, opts)
  opts = opts or {}
  local r = O.cancel_queued(ctx, id, opts)
  if not r.running then return { task = r.task, running = false } end
  local attempt = r.attempt
  if opts.attempt_id and opts.attempt_id ~= attempt.attempt_id then fail(3, ("attempt %s is not the current attempt of %s"):format(opts.attempt_id, id)) end
  local grace = opts.grace_s or M.DEFAULT_GRACE_S
  U.mkdirp(attempt.paths.dir)
  U.write_json_atomic(attempt.paths.cancel, { requested_at = U.now_iso(), grace_s = grace, by = opts.actor or U.identity(), attempt_id = attempt.attempt_id })
  -- wait for the worker to commit the cancelled outcome
  local deadline = U.now_s() + grace + 3
  local final
  while U.now_s() < deadline do
    local st = B.read_state(ctx)
    local a = st.attempts[attempt.attempt_id]
    if a and P.TERMINAL[a.state] then final = a; break end
    if a and a.worker and U.owner_alive(a.worker) == false then break end -- worker is dead: no point waiting
    if not a or not a.worker then
      -- still starting (no worker yet): give it a moment, then take over
      if U.now_s() > deadline - grace - 2 then break end
    end
    uv.sleep(100)
  end
  if not final then
    -- unresponsive or dead worker: terminate the tree ourselves and commit the outcome
    local st = B.read_state(ctx)
    local a = st.attempts[attempt.attempt_id] or attempt
    M.terminate_tree(a, math.min(grace, 2))
    local res = O.attempt_finished(ctx, attempt.attempt_id, { state = "cancelled", reason = a.worker and "cancelled_forced" or "cancelled_before_start", actor = opts.actor or "cancel" })
    final = res.attempt
  end
  local st = B.read_state(ctx)
  return { task = st.tasks[id], attempt = final, running = true }
end

--- Legacy kill: cancel then requeue as one serialized compatibility operation (SDD-037).
function M.kill_requeue(ctx, id)
  local st = B.read_state(ctx)
  local task = st.tasks[id] or fail(2, "no such task: " .. id)
  if task.state ~= "running" then fail(3, id .. " is not active") end
  local c = M.cancel(ctx, id, { actor = "legacy-kill" })
  local task = O.retry(ctx, id, { actor = "legacy-kill" })
  return { cancelled = c, task = task, warning = "legacy kill semantics: cancelled and requeued" }
end

-- ---------------------------------------------------------------- scheduler (SDD-029)
function M.scheduler_status(ctx)
  local snap = B.snapshot(ctx)
  return snap.scheduler
end

local function scheduler_argv(ctx, opts)
  local argv = { nvim_bin(), "--clean", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n", "-l", plugin_root() .. "/runtime/cli.lua", "scheduler", "loop" }
  if opts.wip then vim.list_extend(argv, { "--wip", tostring(opts.wip) }) end
  if opts.tick then vim.list_extend(argv, { "--tick", tostring(opts.tick) }) end
  return argv
end

function M.scheduler_start(ctx, opts)
  opts = opts or {}
  local session = T.scheduler_session(ctx.board.board_id)
  local s
  -- serialize concurrent starts: check and spawn under the control lock
  L.with(ctx.root, { purpose = "scheduler.start" }, function()
    local st = B.read_state(ctx)
    s = st.scheduler or {}
    if s.state == "running" and s.owner and U.owner_alive(s.owner) then fail(3, ("scheduler already running (pid %d since %s)"):format(s.owner.pid, tostring(s.started_at))) end
    if T.available() and T.has(session) and T.pane_dead(session) == false then
      fail(3, "scheduler already starting in tmux session " .. session)
    end
    local argv = scheduler_argv(ctx, opts)
    local env = M.child_env(ctx)
    os.remove(ctx.paths.scheduler_stop)
    if T.available() then
      if T.has(session) then T.kill(session, ctx.board.board_id) end
      local ok, err = T.spawn(session, project_dir(ctx), env, argv, { board_id = ctx.board.board_id, task_id = "scheduler" })
      if not ok then fail(4, err) end
    else
      M.spawn_detached(argv, env, project_dir(ctx))
    end
  end)
  do
  end
  local deadline = U.now_s() + 10
  while U.now_s() < deadline do
    local cur = (B.read_state(ctx).scheduler or {})
    if cur.state == "running" and cur.owner and U.owner_alive(cur.owner) and (not s.instance_id or cur.instance_id ~= s.instance_id) then return cur end
    uv.sleep(100)
  end
  fail(4, "scheduler did not report running within 10s (inspect tmux session " .. session .. ")")
end

function M.scheduler_stop(ctx, opts)
  opts = opts or {}
  local st = B.read_state(ctx)
  local s = st.scheduler or {}
  if s.state ~= "running" then return s, "scheduler is not running" end
  if not (s.owner and U.owner_alive(s.owner)) then
    return O.scheduler_changed(ctx, { state = "stopped", stopped_at = U.now_iso(), stop_reason = "owner dead" }), "scheduler process was already gone; marked stopped"
  end
  U.write_json_atomic(ctx.paths.scheduler_stop, { requested_at = U.now_iso(), by = U.identity() })
  local deadline = U.now_s() + (tonumber(s.tick_s) or 3) + 5
  while U.now_s() < deadline do
    local cur = B.read_state(ctx).scheduler or {}
    if cur.state == "stopped" then return cur, "monitoring stopped; running workers continue and will be reconciled when a scheduler starts again" end
    uv.sleep(100)
  end
  return B.read_state(ctx).scheduler, "stop requested but the scheduler has not acknowledged yet"
end

function M.spawn_detached(argv, env, cwd)
  local envlist = {}
  for k, v in pairs(env) do envlist[#envlist + 1] = k .. "=" .. v end
  local handle = uv.spawn(argv[1], { args = vim.list_slice(argv, 2), env = envlist, cwd = cwd, detached = true, stdio = { nil, nil, nil } }, function() end)
  if not handle then fail(4, "cannot start the scheduler process") end
  uv.unref(handle)
end

--- The scheduler loop (runs inside its own process).
function M.scheduler_loop(ctx, opts)
  opts = opts or {}
  local me = U.identity()
  local instance_id = U.uuid()
  local defaults = ctx.board.scheduler_defaults or {}
  local wip = tonumber(opts.wip) or tonumber(vim.env.AISWARM_WIP) or defaults.wip or 3
  local tick = tonumber(opts.tick) or tonumber(vim.env.AISWARM_TICK) or defaults.tick_s or 3
  local mine = O.scheduler_changed(ctx, { state = "running", owner = me, instance_id = instance_id, started_at = U.now_iso(), wip = wip, tick_s = tick, stopped_at = vim.NIL },
    { guard = function(s) return not (s.state == "running" and s.owner and U.owner_alive(s.owner) and s.owner.pid ~= me.pid) end })
  if mine.instance_id ~= instance_id then fail(3, "another scheduler instance is running for this board") end
  os.remove(ctx.paths.scheduler_stop)
  io.stdout:write(("aiswarm scheduler %s running (wip %d, tick %ss)\n"):format(U.short(instance_id), wip, tostring(tick))); io.stdout:flush()
  local ticks = 0
  while true do
    ticks = ticks + 1
    local stop = U.read_json(ctx.paths.scheduler_stop)
    local cur = B.read_state(ctx).scheduler or {}
    if cur.instance_id ~= instance_id then io.stdout:write("aiswarm scheduler: ownership changed; exiting\n"); return end
    if stop then
      O.scheduler_changed(ctx, { state = "stopped", stopped_at = U.now_iso(), stop_reason = "requested" })
      os.remove(ctx.paths.scheduler_stop)
      io.stdout:write("aiswarm scheduler: stopped (workers keep running)\n"); return
    end
    local ok, err = pcall(function()
      M.reconcile(ctx, {})
      M.dispatch(ctx, { instance_id = instance_id, actor = "scheduler:" .. U.short(instance_id) })
    end)
    if not ok then io.stderr:write("aiswarm scheduler: " .. tostring(type(err) == "table" and err.message or err) .. "\n") end
    U.write_json_atomic(ctx.paths.scheduler_heartbeat, { at = U.now_iso(), instance_id = instance_id, ticks = ticks, pid = me.pid })
    if opts.once then return end
    uv.sleep(math.floor(tick * 1000))
  end
end

-- ---------------------------------------------------------------- session commands (SDD-028)
local function current_attempt(ctx, id)
  local st = B.read_state(ctx)
  local task = st.tasks[id] or fail(2, "no such task: " .. id)
  local aid = task.current_attempt_id or task.attempts[#task.attempts]
  if not aid then fail(2, id .. " has no attempt yet") end
  return st.attempts[aid], task, st
end

function M.attach(ctx, id, opts)
  local a = current_attempt(ctx, id)
  local session = a.tmux and a.tmux.session
  if not session then fail(2, "attempt has no tmux session recorded") end
  local ok, err = T.owned(session, ctx.board.board_id, a.attempt_id)
  if not ok then fail(3, err) end
  if opts and opts.dry_run then return { session = session, attempt_id = a.attempt_id } end
  if vim.env.TMUX then T.run({ "switch-client", "-t", "=" .. session }) else T.run({ "attach-session", "-t", "=" .. session }) end
  return { session = session, attempt_id = a.attempt_id }
end

function M.peek(ctx, id, lines)
  local a = current_attempt(ctx, id)
  local session = a.tmux and a.tmux.session or fail(2, "attempt has no tmux session recorded")
  local out, err = T.capture(session, ctx.board.board_id, lines)
  if not out then fail(2, err) end
  return out
end

function M.wait(ctx, id, timeout_s)
  local deadline = U.now_s() + (timeout_s or 3600)
  while U.now_s() < deadline do
    local st = B.read_state(ctx)
    local task = st.tasks[id] or fail(2, "no such task: " .. id)
    if P.TERMINAL[task.state] then return task end
    uv.sleep(250)
  end
  fail(1, "timed out waiting for " .. id)
end

function M.gc(ctx)
  local st = B.read_state(ctx)
  local killed = {}
  for _, s in ipairs(T.list_owned(ctx.board.board_id)) do
    local a = s.attempt_id ~= "" and st.attempts[s.attempt_id] or nil
    if a and P.TERMINAL[a.state] then
      if T.kill(s.session, ctx.board.board_id, s.attempt_id) then killed[#killed + 1] = s.session end
    end
  end
  return killed
end

function M.down(ctx)
  local _, msg = M.scheduler_stop(ctx)
  local killed = {}
  for _, s in ipairs(T.list_owned(ctx.board.board_id)) do
    if T.kill(s.session, ctx.board.board_id) then killed[#killed + 1] = s.session end
  end
  return { scheduler = msg, killed = killed }
end

-- ---------------------------------------------------------------- command registration
function M.register(C)
  local function load(a) return B.load(a.root) end
  C.table.dispatch = { bools = { once = true }, run = function(a)
    local r = M.dispatch(load(a), { actor = "cli" })
    if a.json then return r end
    return ("dispatched %d, failed %d, skipped %d%s"):format(#r.dispatched, #r.failed, #r.skipped, r.paused and " (paused)" or "")
  end }
  C.table.reconcile = { run = function(a)
    local r = M.reconcile(load(a), {})
    if a.json then return r end
    return ("orphaned %d, startup timeouts %d, stale %d, quiet %d"):format(#r.orphaned, #r.startup_timeout, #r.stale, #r.quiet)
  end }
  C.table.scheduler = { bools = { once = true }, run = function(a)
    local ctx = load(a)
    local sub = a.pos[1] or "status"
    if sub == "status" then local s = M.scheduler_status(ctx); if a.json then return s end
      return ("scheduler %s%s wip=%s tick=%ss owner=%s health=%s"):format(s.state, s.paused and " (paused)" or "", tostring(s.wip), tostring(s.tick_s), s.owner and tostring(s.owner.pid) or "-", tostring(s.health))
    elseif sub == "start" then local s = M.scheduler_start(ctx, { wip = a.opts.wip, tick = a.opts.tick }); if a.json then return s end
      return ("scheduler started (pid %d, wip %s, tick %ss)"):format(s.owner.pid, tostring(s.wip), tostring(s.tick_s))
    elseif sub == "stop" then local s, msg = M.scheduler_stop(ctx); if a.json then return { scheduler = s, message = msg } end return msg
    elseif sub == "pause" then O.scheduler_changed(ctx, { paused = true }); return "dispatch paused (running workers continue)"
    elseif sub == "resume" then O.scheduler_changed(ctx, { paused = false }); return "dispatch resumed"
    elseif sub == "loop" then M.scheduler_loop(ctx, { wip = a.opts.wip, tick = a.opts.tick, once = a.opts.once }); return nil
    end
    fail(1, "usage: scheduler status|start|stop|pause|resume [--wip N] [--tick S]")
  end }
  C.table.attach = { bools = { dry_run = true }, run = function(a)
    local id = a.pos[1] or fail(1, "usage: attach <id>")
    local r = M.attach(load(a), id, { dry_run = a.opts.dry_run }); if a.json then return r end; return r.session
  end }
  C.table.peek = { run = function(a)
    local id = a.pos[1] or fail(1, "usage: peek <id> [lines]")
    return M.peek(load(a), id, tonumber(a.pos[2]) or tonumber(a.opts.lines))
  end }
  C.table.wait = { run = function(a)
    local id = a.pos[1] or fail(1, "usage: wait <id>")
    local task = M.wait(load(a), id, tonumber(a.opts.timeout)); if a.json then return task end; return id .. " " .. task.state
  end }
  C.table.gc = { run = function(a) local k = M.gc(load(a)); if a.json then return k end; return ("closed %d finished sessions"):format(#k) end }
  C.table.down = { run = function(a) local r = M.down(load(a)); if a.json then return r end; return r.scheduler .. ("; closed %d sessions"):format(#r.killed) end }
end

return M
