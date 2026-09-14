-- SDD-028 tmux ownership, SDD-029 scheduler, SDD-030 isolation, SDD-031 dispatch.
local sb = require("helpers.sandbox")
local v3 = require("helpers.v3")
local uv = vim.uv

local function env_for(scenario, extra) return v3.provider_env(scenario, extra) end
local function wait_task(t, root, id, pred, ms)
  local task
  t:wait(ms or 15000, function()
    local snap = sb.json(v3.cli(root, { "snapshot", "--json" }).stdout)
    if not snap then return false end
    for _, x in ipairs(snap.tasks) do if x.id == id then task = x end end
    return task and pred(task)
  end, "task " .. id .. " reaches the expected state")
  return task
end
local function attempts_of(root, id)
  local snap = sb.json(v3.cli(root, { "snapshot", "--json" }).stdout)
  return vim.tbl_filter(function(a) return a.task_id == id end, snap.attempts)
end
local function terminal(task) return task.state == "succeeded" or task.state == "failed" or task.state == "cancelled" end
local function kill_server(t) t:defer(function() sb.tmux({ "kill-server" }) end) end

return {
  { id = "tmux.two_boards_same_task_id_coexist", tasks = { "SDD-028" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local ra = v3.board(t, "A"); local rb = v3.board(t, "B")
    for _, root in ipairs({ ra, rb }) do
      v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
      local r = v3.cli_json(t, root, { "dispatch" }, { env = env_for("quiet") }); t:log("dispatch", r); t:eq(#r.dispatched, 1, root)
    end
    local sa, sb_ = attempts_of(ra, "T-001")[1].tmux.session, attempts_of(rb, "T-001")[1].tmux.session
    t:neq(sa, sb_, "sessions are namespaced by board/attempt")
    t:ok(sb.tmux({ "has-session", "-t", "=" .. sa }).code == 0 and sb.tmux({ "has-session", "-t", "=" .. sb_ }).code == 0)
    -- `down` on A leaves B's session alone
    local d = v3.cli_json(t, ra, { "down" }); t:eq(#d.killed, 1)
    t:ok(sb.tmux({ "has-session", "-t", "=" .. sa }).code ~= 0, "A's session gone")
    t:ok(sb.tmux({ "has-session", "-t", "=" .. sb_ }).code == 0, "B's session untouched")
    -- a forged session name (renamed to look like B's) fails ownership checks
    sb.tmux({ "new-session", "-d", "-s", "agent-forged", "sleep 30" })
    sb.tmux({ "set-option", "-t", "agent-forged", "@aiswarm_board", "not-this-board" })
    local m = v3.mods(); local T = require("aiswarm.runtime.tmux")
    local ok, err = T.owned("agent-forged", m.B.load(rb).board.board_id); t:ok(not ok); t:match(err, "another board")
    t:eq(#T.list_owned(m.B.load(rb).board.board_id), 1, "cleanup never scans arbitrary sessions")
    -- release B's provider
    local a = attempts_of(rb, "T-001")[1]
    sb.write(vim.fs.dirname(rb) .. "/barrier", "go")
  end },
  { id = "tmux.finished_pane_retained_and_peekable", tasks = { "SDD-028" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "peek")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "dispatch" }, { env = env_for("success") })
    wait_task(t, root, "T-001", terminal)
    local out = v3.cli(root, { "peek", "T-001" }); t:eq(out.code, 0, out.stderr); t:match(out.stdout, "aiswarm worker")
    local att = v3.cli(root, { "attach", "T-001", "--dry-run" }); t:eq(att.code, 0, att.stderr)
    local gc = v3.cli_json(t, root, { "gc" }); t:eq(#gc, 1, "gc closes the finished attempt's session only")
    t:eq(v3.cli(root, { "peek", "T-001" }).code, 2, "after gc the pane is gone; reported, not crashed")
  end },
  -- ------------------------------------------------------------ SDD-029
  { id = "scheduler.singleton_and_authoritative_wip", tasks = { "SDD-029" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "sched")
    local jobs = {}
    for i = 1, 3 do jobs[i] = vim.system({ sb.bin("aiswarm"), "scheduler", "start", "--wip", "2", "--tick", "1", "--json" }, { text = true, env = vim.tbl_extend("force", sb.env(root), { AISWARM_TMUX_SOCKET = sb.socket }), cwd = vim.fs.dirname(root) }) end
    local okc = 0
    for _, j in ipairs(jobs) do local o = j:wait(30000); if o.code == 0 then okc = okc + 1 else t:match(o.stderr, "already") end end
    t:ok(okc >= 1, "at least one start succeeded")
    local s = v3.cli_json(t, root, { "scheduler", "status" })
    t:eq(s.state, "running"); t:eq(s.wip, 2); t:eq(s.health, "alive")
    t:eq(#sb.tmux({ "list-sessions", "-F", "#{session_name}" }).stdout:gsub("[^\n]", ""), 1, "exactly one scheduler session")
    -- editor environment cannot change the reported WIP
    local j = v3.cli_json(t, root, { "json" }, { env = { AISWARM_WIP = "9", HIVE_WIP = "9" } }); t:eq(j.wip, 2)
    -- pause stops new dispatch, workers continue
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local paused = v3.cli(root, { "scheduler", "pause" }); t:eq(paused.code, 0)
    v3.cli_json(t, root, { "add", "--id", "T-002" }, { stdin = "x\n" })
    vim.wait(2500)
    local snap = v3.cli_json(t, root, { "snapshot" })
    for _, task in ipairs(snap.tasks) do t:eq(task.state, "queued", task.id .. " not dispatched while paused") end
    t:eq(snap.scheduler.paused, true)
    v3.cli(root, { "scheduler", "resume" })
    -- resume: the loop dispatches with the fake provider (quiet, barrier)
    local stop = v3.cli(root, { "scheduler", "stop" }); t:eq(stop.code, 0); t:match(stop.stdout, "monitoring stopped")
    t:eq(v3.cli_json(t, root, { "scheduler", "status" }).state, "stopped")
  end },
  { id = "scheduler.stop_does_not_kill_workers", tasks = { "SDD-029" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "sched2")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    local env = env_for("quiet", { AISWARM_FAKE_BARRIER = barrier })
    local st = v3.cli(root, { "scheduler", "start", "--tick", "1" }, { env = env }); t:eq(st.code, 0, st.stderr)
    local task = wait_task(t, root, "T-001", function(x) return x.state == "running" end)
    local a = attempts_of(root, "T-001")[1]
    t:wait(10000, function() local x = attempts_of(root, "T-001")[1]; return x.worker ~= nil end, "worker registered")
    a = attempts_of(root, "T-001")[1]
    v3.cli(root, { "scheduler", "stop" })
    t:eq(v3.cli_json(t, root, { "scheduler", "status" }).state, "stopped")
    t:ok(uv.kill(a.worker.pid, 0) == 0, "worker still alive after scheduler stop")
    t:eq(attempts_of(root, "T-001")[1].state, "running", "scheduler stopped is not interpreted as workers dead")
    sb.write(barrier, "go")
    wait_task(t, root, "T-001", terminal)
    t:eq(attempts_of(root, "T-001")[1].state, "succeeded")
  end },
  -- ------------------------------------------------------------ SDD-030
  { id = "isolation.preflight_rejects_unrunnable", tasks = { "SDD-030" }, suites = { "core" }, run = function(t)
    local root = v3.board(t, "iso")
    local r = v3.cli(root, { "add", "--id", "T-001", "--isolation", "worktree" }, { stdin = "x\n" })
    t:eq(r.code, 3); t:match(r.stderr, "worktrees directory")
    local wt = t:tmpdir("wt")
    local r2 = v3.cli(root, { "add", "--id", "T-001", "--isolation", "worktree" }, { stdin = "x\n", env = { AISWARM_WORKTREES = wt } })
    t:eq(r2.code, 3); t:match(r2.stderr, "git repository")
    t:eq(#v3.cli_json(t, root, { "snapshot" }).tasks, 0, "no runnable task was created")
    local file = wt .. "/file"; sb.write(file, "x")
    local base = vim.fs.dirname(root); sb.run({ "git", "init", "-q", base }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME } })
    local r3 = v3.cli(root, { "add", "--id", "T-001", "--isolation", "worktree" }, { stdin = "x\n", env = { AISWARM_WORKTREES = file } })
    t:eq(r3.code, 3); t:match(r3.stderr, "not a directory")
  end },
  { id = "isolation.worktree_created_or_failed_never_shared", tasks = { "SDD-030" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "iso2")
    local base = vim.fs.dirname(root)
    local genv = { PATH = vim.env.PATH, HOME = vim.env.HOME, GIT_AUTHOR_NAME = "t", GIT_AUTHOR_EMAIL = "t@x", GIT_COMMITTER_NAME = "t", GIT_COMMITTER_EMAIL = "t@x" }
    sb.run({ "git", "init", "-q", base }, { env = genv }); sb.write(base .. "/README", "hi"); sb.run({ "git", "-C", base, "add", "." }, { env = genv }); sb.run({ "git", "-C", base, "commit", "-q", "-m", "init" }, { env = genv })
    local wt = t:tmpdir("wts")
    local env = env_for("success", { AISWARM_WORKTREES = wt })
    v3.cli_json(t, root, { "add", "--id", "T-001", "--isolation", "worktree" }, { stdin = "x\n", env = env })
    v3.cli_json(t, root, { "add", "--id", "T-002" }, { stdin = "x\n", env = env })
    local d = v3.cli_json(t, root, { "dispatch" }, { env = env }); t:eq(#d.dispatched, 2, vim.inspect(d))
    wait_task(t, root, "T-001", terminal); wait_task(t, root, "T-002", terminal)
    local a1, a2 = attempts_of(root, "T-001")[1], attempts_of(root, "T-002")[1]
    t:eq(a1.config.cwd, wt .. "/T-001"); t:eq(a1.config.isolation_info.mode, "worktree"); t:eq(a1.config.isolation_info.created, true)
    t:eq(a2.config.cwd, base, "explicit shared mode records its path"); t:eq(a2.config.isolation_info.mode, "shared")
    t:ok(sb.exists(wt .. "/T-001/.aiswarm-worktree.json"))
    -- retry reuses its own worktree; an unrelated directory of the same name is refused
    v3.cli_json(t, root, { "retry", "T-001" })
    local d2 = v3.cli_json(t, root, { "dispatch" }, { env = env }); t:eq(#d2.dispatched, 1)
    wait_task(t, root, "T-001", terminal)
    t:eq(attempts_of(root, "T-001")[2].config.isolation_info.reused, true)
    v3.cli_json(t, root, { "add", "--id", "T-003", "--isolation", "worktree" }, { stdin = "x\n", env = env })
    vim.fn.mkdir(wt .. "/T-003", "p"); sb.write(wt .. "/T-003/stray", "not a worktree")
    local d3 = v3.cli_json(t, root, { "dispatch" }, { env = env })
    t:eq(#d3.failed, 1); t:match(d3.failed[1].reason, "isolation_failed")
    local t3 = wait_task(t, root, "T-003", terminal); t:eq(t3.state, "failed"); t:match(t3.outcome.reason, "isolation_failed")
    t:ok(sb.exists(wt .. "/T-003/stray"), "cleanup never removes resources it did not create")
  end },
  -- ------------------------------------------------------------ SDD-031
  { id = "dispatch.concurrent_respects_wip_and_uniqueness", tasks = { "SDD-031" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "disp", { wip = 2 })
    for i = 1, 5 do v3.cli_json(t, root, { "add", "--id", ("T-%03d"):format(i) }, { stdin = "x\n" }) end
    local barrier = vim.fs.dirname(root) .. "/barrier"
    local env = vim.tbl_extend("force", sb.env(root), env_for("quiet", { AISWARM_FAKE_BARRIER = barrier, AISWARM_TMUX_SOCKET = sb.socket }))
    local jobs = {}
    for i = 1, 3 do jobs[i] = vim.system({ sb.bin("aiswarm"), "dispatch", "--json" }, { text = true, env = env, cwd = vim.fs.dirname(root) }) end
    local total = 0
    for _, j in ipairs(jobs) do local o = j:wait(30000); t:eq(o.code, 0, o.stderr); total = total + #(sb.json(o.stdout).dispatched) end
    t:eq(total, 2, "concurrent dispatchers cannot exceed WIP")
    local snap = v3.cli_json(t, root, { "snapshot" })
    t:eq(snap.counts.running, 2)
    local per_task = {}
    for _, a in ipairs(snap.attempts) do per_task[a.task_id] = (per_task[a.task_id] or 0) + 1; t:eq(per_task[a.task_id], 1, "no task started twice") end
    sb.write(barrier, "go")
    for i = 1, 2 do wait_task(t, root, ("T-%03d"):format(i), terminal) end
  end },
  { id = "dispatch.blocked_skipped_and_spawn_failure_released", tasks = { "SDD-031" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "disp2", { wip = 1 })
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "add", "--id", "T-002", "--dep", "T-001" }, { stdin = "x\n" })
    -- spawn failure: no Neovim runtime for the worker
    local d = v3.cli_json(t, root, { "dispatch" }, { env = { AISWARM_NVIM = "/nonexistent/nvim" } })
    t:eq(#d.failed, 1); t:match(d.failed[1].reason, "spawn_failed"); t:eq(d.failed[1].id, "T-001")
    v3.cli_json(t, root, { "add", "--id", "T-003" }, { stdin = "x\n" })
    local snap = v3.cli_json(t, root, { "snapshot" })
    t:eq(snap.counts.running, 0, "failed spawn releases capacity: no phantom active task")
    local t1 = vim.tbl_filter(function(x) return x.id == "T-001" end, snap.tasks)[1]; t:eq(t1.state, "failed"); t:match(t1.outcome.reason, "spawn_failed")
    t:eq(#vim.tbl_filter(function(a) return a.task_id == "T-001" end, snap.attempts), 1, "one accurate outcome")
    -- next pass: T-002 is blocked by the failed upstream, T-003 runs
    local d2 = v3.cli_json(t, root, { "dispatch" }, { env = env_for("success") })
    t:eq(#d2.dispatched, 1); t:eq(d2.dispatched[1].id, "T-003"); t:match(d2.skipped[1], "blocked by T%-001")
    wait_task(t, root, "T-003", terminal)
  end },
}
