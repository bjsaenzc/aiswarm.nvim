-- SDD-032 fencing, SDD-033 cancel, SDD-034 retry, SDD-035 reconciliation, SDD-036 report quality, SDD-037 legacy translation.
local sb = require("helpers.sandbox")
local v3 = require("helpers.v3")
local uv = vim.uv

local function env_for(scenario, extra) return v3.provider_env(scenario, extra) end
local function snapshot(t, root) return v3.cli_json(t, root, { "snapshot" }) end
local function task_of(snap, id) for _, x in ipairs(snap.tasks) do if x.id == id then return x end end end
local function attempts_of(snap, id) return vim.tbl_filter(function(a) return a.task_id == id end, snap.attempts) end
local function terminal(task) return task.state == "succeeded" or task.state == "failed" or task.state == "cancelled" end
local function wait_task(t, root, id, pred, ms)
  local task
  t:wait(ms or 15000, function() local s = sb.json(v3.cli(root, { "snapshot", "--json" }).stdout); task = s and task_of(s, id); return task and pred(task) end, "task " .. id)
  return task
end
local function kill_server(t) t:defer(function() sb.tmux({ "kill-server" }) end) end
local function run_to_end(t, root, id, scenario, extra)
  local d = v3.cli_json(t, root, { "dispatch" }, { env = env_for(scenario, extra) })
  t:ok(#d.dispatched >= 1, "dispatched: " .. vim.inspect(d))
  return wait_task(t, root, id, terminal)
end

return {
  -- ------------------------------------------------------------ SDD-032
  { id = "fence.duplicate_finish_one_outcome", tasks = { "SDD-032" }, suites = { "core" }, run = function(t)
    local m = v3.mods()
    local root, ctx = v3.board(t, "f1")
    v3.add(t, ctx, { id = "T-001" })
    local a
    m.B.txn(ctx, {}, function(state) local x, nt = m.O.reserve_attempt(ctx, state.tasks["T-001"], {}); a = x
      return { { type = "attempt.reserved", task_id = "T-001", attempt_id = x.attempt_id, payload = { attempt = x, task = nt } } } end)
    m.O.attempt_started(ctx, a.attempt_id, { pid = 1, pid_start = "x" })
    local r1 = m.O.attempt_finished(ctx, a.attempt_id, { state = "succeeded", exit_code = 0 })
    local r2 = m.O.attempt_finished(ctx, a.attempt_id, { state = "failed", exit_code = 1 })
    t:eq(r2.duplicate, true); t:eq(r2.attempt.state, "succeeded", "terminal outcomes never move")
    local ok, err = pcall(m.O.attempt_started, ctx, a.attempt_id, { pid = 1 }); t:ok(not ok and err.message:match("attempt is succeeded"), "never back to running")
    t:eq(#v3.journal_records(root), 5, "one finish committed (attempt + task records)")
  end },
  { id = "fence.late_finish_cannot_alter_new_attempt", tasks = { "SDD-032" }, suites = { "core" }, run = function(t)
    local m = v3.mods()
    local root, ctx = v3.board(t, "f2")
    v3.add(t, ctx, { id = "T-001" })
    local a1, a2
    m.B.txn(ctx, {}, function(state) local x, nt = m.O.reserve_attempt(ctx, state.tasks["T-001"], {}); a1 = x
      return { { type = "attempt.reserved", task_id = "T-001", attempt_id = x.attempt_id, payload = { attempt = x, task = nt } } } end)
    -- attempt 1 is cancelled and the task retried; attempt 2 starts; then attempt 1's late "success" arrives
    m.O.attempt_finished(ctx, a1.attempt_id, { state = "cancelled", reason = "cancelled" })
    m.O.retry(ctx, "T-001")
    m.B.txn(ctx, {}, function(state) local x, nt = m.O.reserve_attempt(ctx, state.tasks["T-001"], {}); a2 = x
      return { { type = "attempt.reserved", task_id = "T-001", attempt_id = x.attempt_id, payload = { attempt = x, task = nt } } } end)
    local late = m.O.attempt_finished(ctx, a1.attempt_id, { state = "succeeded", exit_code = 0 })
    t:eq(late.duplicate, true)
    local st = m.B.read_state(ctx)
    t:eq(st.tasks["T-001"].state, "running"); t:eq(st.tasks["T-001"].current_attempt_id, a2.attempt_id)
    t:eq(st.attempts[a1.attempt_id].state, "cancelled")
  end },
  { id = "fence.exit_and_timeout_reasons", tasks = { "SDD-032", "SDD-071" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "f3", { wip = 3 })
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local failed = run_to_end(t, root, "T-001", "failure")
    t:eq(failed.state, "failed"); t:eq(failed.outcome.exit_code, 1); t:eq(failed.outcome.reason, "exit 1")
    v3.cli_json(t, root, { "add", "--id", "T-002", "--timeout", "1" }, { stdin = "x\n" })
    local timed = run_to_end(t, root, "T-002", "timeout")
    t:eq(timed.state, "failed"); t:eq(timed.outcome.reason, "timeout")
    local snap = snapshot(t, root)
    t:eq(attempts_of(snap, "T-002")[1].reason, "timeout")
  end },
  -- ------------------------------------------------------------ SDD-033
  { id = "cancel.no_automatic_requeue", tasks = { "SDD-033" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "c1")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    local env = env_for("grandchild-hold", { AISWARM_FAKE_BARRIER = barrier })
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    wait_task(t, root, "T-001", function(x) return x.state == "running" end)
    t:wait(10000, function() local s = snapshot(t, root); local a = attempts_of(s, "T-001")[1]; return a.worker ~= nil end)
    local grandchild
    t:wait(5000, function() local a = attempts_of(snapshot(t, root), "T-001")[1]; local out = sb.read(a.paths.stdout) or ""; grandchild = tonumber(out:match("grandchild=(%d+)")); return grandchild ~= nil end)
    local r = v3.cli_json(t, root, { "cancel", "T-001", "--grace", "2" }, { env = env })
    t:eq(r.task.state, "cancelled"); t:eq(r.attempt.state, "cancelled"); t:eq(r.attempt.reason, "cancelled")
    t:wait(3000, function() return uv.kill(grandchild, 0) ~= 0 end, "grandchild terminated")
    for _ = 1, 3 do v3.cli_json(t, root, { "dispatch" }, { env = env }) end
    local snap = snapshot(t, root)
    t:eq(task_of(snap, "T-001").state, "cancelled", "no rerun after several scheduler ticks"); t:eq(#attempts_of(snap, "T-001"), 1)
    local again = v3.cli(root, { "cancel", "T-001" }); t:eq(again.code, 3); t:match(again.stderr, "already cancelled")
  end },
  { id = "cancel.unresponsive_is_force_killed", tasks = { "SDD-033" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "c2")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local env = env_for("unresponsive")
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    t:wait(10000, function() local a = attempts_of(snapshot(t, root), "T-001")[1]; return a and a.worker ~= nil end)
    local started = uv.hrtime()
    local r = v3.cli_json(t, root, { "cancel", "T-001", "--grace", "1" }, { env = env, timeout = 30000 })
    local ms = (uv.hrtime() - started) / 1e6
    t:eq(r.attempt.state, "cancelled"); t:ok(ms < 8000, "forced within grace + margin: " .. ms .. "ms")
    t:ok(r.attempt.exit and (r.attempt.exit.signal == 9 or r.attempt.exit.signal == 15), "provider ended by signal: " .. vim.inspect(r.attempt.exit))
  end },
  { id = "cancel.queued_and_completed_targets", tasks = { "SDD-033" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "c3")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local r = v3.cli_json(t, root, { "cancel", "T-001" }); t:eq(r.task.state, "cancelled"); t:eq(r.running, false)
    v3.cli_json(t, root, { "add", "--id", "T-002" }, { stdin = "x\n" })
    run_to_end(t, root, "T-002", "success")
    local done = v3.cli(root, { "cancel", "T-002" }); t:eq(done.code, 3, "completed task is a stale target"); t:match(done.stderr, "already succeeded")
    local stale = v3.cli(root, { "cancel", "T-001", "--expect-revision", "1" }); t:eq(stale.code, 3)
  end },
  { id = "cancel.race_with_finish_one_terminal_result", tasks = { "SDD-033" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "c4")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    local env = env_for("quiet", { AISWARM_FAKE_BARRIER = barrier, AISWARM_FAKE_TICK_MS = "1" })
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    t:wait(10000, function() local a = attempts_of(snapshot(t, root), "T-001")[1]; return a and a.worker ~= nil end)
    sb.write(barrier, "go")   -- provider finishes now
    local r = v3.cli(root, { "cancel", "T-001", "--grace", "1", "--json" }, { env = env })
    local snap = snapshot(t, root)
    local a = attempts_of(snap, "T-001")[1]
    t:ok(a.state == "cancelled" or a.state == "succeeded", "exactly one terminal result: " .. a.state)
    t:eq(task_of(snap, "T-001").state, a.state)
    t:eq(#attempts_of(snap, "T-001"), 1)
    local finishes = 0
    for _, rec in ipairs(v3.journal_records(root)) do if rec.type == "attempt.finished" then finishes = finishes + 1 end end
    t:eq(finishes, 1)
  end },
  -- ------------------------------------------------------------ SDD-034
  { id = "retry.fresh_attempt_keeps_history", tasks = { "SDD-034" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "r1")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    run_to_end(t, root, "T-001", "failure")
    local a1 = attempts_of(snapshot(t, root), "T-001")[1]
    local r = v3.cli_json(t, root, { "retry", "T-001" }); t:eq(r.state, "queued")
    local twice = v3.cli(root, { "retry", "T-001" }); t:eq(twice.code, 3, "retry returns work to the queue exactly once")
    run_to_end(t, root, "T-001", "success")
    local snap = snapshot(t, root)
    local atts = attempts_of(snap, "T-001")
    t:eq(#atts, 2); t:neq(atts[1].paths.dir, atts[2].paths.dir)
    t:ok(sb.exists(a1.paths.stdout), "prior log readable"); t:match(sb.read(a1.paths.stdout), "attempting")
    t:eq(atts[1].state, "failed"); t:eq(atts[2].state, "succeeded")
    t:eq(task_of(snap, "T-001").outcome.attempt_id, atts[2].attempt_id)
    local a1_after = sb.read(a1.paths.stdout); t:ok(not a1_after:find("fake: done"), "new execution cannot write into prior artifact paths")
  end },
  { id = "retry.running_and_stale_conflict", tasks = { "SDD-034" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "r2")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    local env = env_for("quiet", { AISWARM_FAKE_BARRIER = barrier })
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    local r = v3.cli(root, { "retry", "T-001" }); t:eq(r.code, 3); t:match(r.stderr, "only finished")
    sb.write(barrier, "go"); wait_task(t, root, "T-001", terminal)
    local task = task_of(snapshot(t, root), "T-001")
    local stale = v3.cli(root, { "retry", "T-001", "--expect-revision", tostring(task.revision - 1) }); t:eq(stale.code, 3); t:match(stale.stderr, "task changed")
  end },
  -- ------------------------------------------------------------ SDD-035
  { id = "reconcile.dead_worker_becomes_orphaned", tasks = { "SDD-035" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "rc1")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    local env = env_for("quiet", { AISWARM_FAKE_BARRIER = barrier })
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    local a
    t:wait(10000, function() a = attempts_of(snapshot(t, root), "T-001")[1]; return a and a.worker ~= nil end)
    local worker = sb.json(sb.read(a.paths.worker))
    t:defer(function() pcall(uv.kill, -worker.pgid, 9) end)
    uv.kill(worker.pid, 9)   -- the worker dies; the pane is retained by tmux
    t:wait(3000, function() return uv.kill(worker.pid, 0) ~= 0 end)
    t:eq(attempts_of(snapshot(t, root), "T-001")[1].state, "running", "session presence alone changes nothing")
    local rep = v3.cli_json(t, root, { "reconcile" })
    t:eq(rep.orphaned, { "T-001" })
    local snap = snapshot(t, root)
    t:eq(task_of(snap, "T-001").state, "failed"); t:eq(task_of(snap, "T-001").display, "Failed: orphaned")
    t:ok(sb.tmux({ "has-session", "-t", "=" .. a.tmux.session }).code == 0, "retained session stays inspectable")
    uv.kill(-worker.pgid, 9)
  end },
  { id = "reconcile.quiet_and_missing_heartbeat_not_failure", tasks = { "SDD-035" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "rc2")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    local env = env_for("quiet", { AISWARM_FAKE_BARRIER = barrier })
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    local a
    t:wait(10000, function() a = attempts_of(snapshot(t, root), "T-001")[1]; return a and a.worker ~= nil end)
    -- corrupt the activity projection so no heartbeat is visible: state is stale/unknown, never failed
    sb.write(a.paths.activity, '{"heartbeat_at":"2000-01-01T00:00:00Z"}')
    local rep = v3.cli_json(t, root, { "reconcile" })
    t:eq(rep.orphaned, {}); t:eq(rep.stale, { "T-001" })
    local task = task_of(snapshot(t, root), "T-001")
    t:eq(task.state, "running"); t:eq(task.display, "Telemetry stale")
    sb.write(barrier, "go"); wait_task(t, root, "T-001", terminal)
  end },
  { id = "reconcile.startup_timeout", tasks = { "SDD-035", "SDD-031" }, suites = { "core", "reliability" }, run = function(t)
    local m = v3.mods()
    local root, ctx = v3.board(t, "rc3")
    v3.add(t, ctx, { id = "T-001" })
    m.B.txn(ctx, {}, function(state) local a, nt = m.O.reserve_attempt(ctx, state.tasks["T-001"], {}); a.reserved_at = "2000-01-01T00:00:00.000Z"
      return { { type = "attempt.reserved", task_id = "T-001", attempt_id = a.attempt_id, payload = { attempt = a, task = nt } } } end)
    local rep = require("aiswarm.runtime.lifecycle").reconcile(ctx, { startup_deadline_s = 1 })
    t:ok(#rep.startup_timeout == 1 or #rep.orphaned == 1, vim.inspect(rep))
    t:eq(m.B.read_state(ctx).tasks["T-001"].state, "failed")
  end },
  -- ------------------------------------------------------------ SDD-036
  { id = "report.quality_bound_to_exact_attempt", tasks = { "SDD-036" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "rep")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local first = run_to_end(t, root, "T-001", "success")
    t:eq(first.outcome.report, "complete")
    v3.cli_json(t, root, { "retry", "T-001" })
    local second = run_to_end(t, root, "T-001", "missing-report")
    t:eq(second.state, "succeeded", "exit 0 is a separate fact"); t:eq(second.outcome.report, "missing", "no predecessor report displayed")
    local atts = attempts_of(snapshot(t, root), "T-001")
    t:eq(atts[1].report.status, "complete"); t:eq(atts[2].report.status, "missing")
    t:eq(atts[2].usage, nil, "usage stays null when not reported")
    t:ok(sb.read(atts[1].paths.report):find("fake: not run"), "model verification text is a report, not a verified fact")
    -- an incomplete report (missing sections)
    sb.write(atts[2].paths.report, "## Summary\nonly a summary\n")
    t:eq(v3.mods().O.report_quality(atts[2].paths.report).status, "incomplete")
  end },
  -- ------------------------------------------------------------ SDD-037
  { id = "legacy.kill_requeues_once_on_v3", tasks = { "SDD-037" }, suites = { "core", "compatibility" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "lk")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    local env = env_for("quiet", { AISWARM_FAKE_BARRIER = barrier })
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    t:wait(10000, function() local a = attempts_of(snapshot(t, root), "T-001")[1]; return a and a.worker ~= nil end)
    local k = v3.cli(root, { "kill", "T-001", "--json" }, { env = env }); t:eq(k.code, 0, k.stderr); t:match(k.stderr, "legacy meaning")
    local snap = snapshot(t, root)
    t:eq(task_of(snap, "T-001").state, "queued", "AISwarmKill semantics: requeued exactly once")
    t:eq(#attempts_of(snap, "T-001"), 1); t:eq(attempts_of(snap, "T-001")[1].state, "cancelled")
    -- canonical cancel afterwards does not requeue
    local c = v3.cli_json(t, root, { "cancel", "T-001" }); t:eq(c.task.state, "cancelled")
    for _ = 1, 2 do v3.cli_json(t, root, { "dispatch" }, { env = env }) end
    t:eq(task_of(snapshot(t, root), "T-001").state, "cancelled")
    -- legacy read surface on a v3 board
    local j = v3.cli_json(t, root, { "json" }); t:eq(j.api_version, 2); t:eq(j.tasks[1].state, "failed"); t:eq(j.capabilities.atomic_add, true)
    local ev = v3.cli(root, { "events", "--since", "0" }); t:eq(ev.code, 0)
    local types = {}
    for line in ev.stdout:gmatch("[^\n]+") do types[#types + 1] = sb.json(line).type end
    t:eq(types[1], "queued"); t:ok(vim.tbl_contains(types, "cancelled"))
    local pause = v3.cli(root, { "pause" }); t:eq(pause.code, 0); t:eq(v3.cli_json(t, root, { "json" }).paused, true)
    v3.cli(root, { "resume" })
  end },
  { id = "legacy.no_compat_path_bypasses_validation", tasks = { "SDD-037" }, suites = { "core", "compatibility" }, run = function(t)
    local root = v3.board(t, "lv")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    t:eq(v3.cli(root, { "set", "T-001", "provider=not-a-provider" }).code, 3)
    t:eq(v3.cli(root, { "set", "T-001", "timeout=-1" }).code, 3)
    t:eq(v3.cli(root, { "set", "T-001", "depends_on=T-001" }).code, 3)
    t:eq(v3.cli(root, { "add", "--id", "../evil" }, { stdin = "x\n" }).code, 3)
    t:eq(v3.cli(root, { "move", "T-001", "--first" }).code, 0)
    t:eq(v3.cli(root, { "kill", "T-001" }).code, 3, "kill on a queued task is a wrong-state conflict, like v2")
  end },
}
