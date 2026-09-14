-- SDD-023 add, SDD-024 edit, SDD-025 dependencies, SDD-026 reorder, SDD-027 attempt identity.
local sb = require("helpers.sandbox")
local v3 = require("helpers.v3")
return {
  { id = "queue.add_atomic_and_structured", tasks = { "SDD-023" }, suites = { "core" }, run = function(t)
    local root = v3.board(t, "add")
    local r = v3.cli_json(t, root, { "add", "--title", "hello", "--priority", "7" }, { stdin = "prompt line 1\n\nline 3\n" })
    t:eq(r.id, "T-001"); t:eq(r.revision, 1); t:eq(r.task.provider, "mock")
    t:eq(sb.read(root .. "/prompts/T-001/r1.md"), "prompt line 1\n\nline 3\n")
    local r2 = v3.cli_json(t, root, { "add", "--id", "custom-9" }, { stdin = "x\n" }); t:eq(r2.id, "custom-9")
    local dup = v3.cli(root, { "add", "--id", "T-001" }, { stdin = "x\n" }); t:eq(dup.code, 3); t:match(dup.stderr, "already exists")
    local empty = v3.cli(root, { "add" }, { stdin = "  \n" }); t:eq(empty.code, 3); t:match(empty.stderr, "prompt is empty")
    local bad = v3.cli(root, { "add", "--priority", "-1" }, { stdin = "x\n" }); t:eq(bad.code, 3)
    local snap = v3.cli_json(t, root, { "snapshot" }); t:eq(#snap.tasks, 2, "invalid inputs left the board unchanged")
    t:eq(snap.control_seq, 2)
  end },
  { id = "queue.simultaneous_auto_ids_unique", tasks = { "SDD-023" }, suites = { "core", "reliability" }, run = function(t)
    local root = v3.board(t, "auto")
    local jobs = {}
    for i = 1, 10 do jobs[i] = vim.system({ sb.bin("aiswarm"), "add" }, { text = true, env = sb.env(root), cwd = vim.fs.dirname(root), stdin = "p" .. i .. "\n" }) end
    local ids = {}
    for _, j in ipairs(jobs) do local o = j:wait(30000); t:eq(o.code, 0, o.stderr); ids[#ids + 1] = vim.trim(o.stdout) end
    table.sort(ids)
    for i = 1, 10 do t:eq(ids[i], ("T-%03d"):format(i)) end
    for _, id in ipairs(ids) do t:ok(sb.exists(root .. "/prompts/" .. id .. "/r1.md"), id .. " prompt present") end
  end },
  { id = "queue.crash_cannot_split_task_and_prompt", tasks = { "SDD-023" }, suites = { "core", "reliability" }, run = function(t)
    local m = v3.mods()
    local root, ctx = v3.board(t, "crash")
    ctx.fault = "before_append"
    pcall(v3.add, t, ctx, { id = "T-001" })
    ctx.fault = nil
    local snap = m.B.snapshot(m.B.load(root))
    t:eq(snap.tasks, {}, "no visible task without a committed record")
    -- the staged prompt is garbage, and a retry with the same id succeeds (no phantom conflict from a stale prompt of the same id? it is a conflict by design)
    local ok, err = pcall(v3.add, t, ctx, { id = "T-001" })
    t:ok(not ok and err.message:match("already exists"), "staged prompt of an uncommitted add is reported as a conflict, never a half task")
    -- committed after append: task and prompt both visible
    ctx.fault = "after_append"; pcall(v3.add, t, ctx, { id = "T-002" }); ctx.fault = nil
    local snap2 = m.B.snapshot(m.B.load(root))
    t:eq(#snap2.tasks, 1); t:ok(sb.exists(snap2.tasks[1].prompt_path))
  end },
  { id = "queue.edit_atomic_with_revision", tasks = { "SDD-024" }, suites = { "core" }, run = function(t)
    local root = v3.board(t, "edit")
    v3.cli_json(t, root, { "add", "--id", "T-001", "--title", "a" }, { stdin = "x\n" })
    local bad = v3.cli(root, { "set", "T-001", "--expect-revision", "1", "--provider", "nope", "--timeout", "-1", "--title", "changed" })
    t:eq(bad.code, 3)
    local snap = v3.cli_json(t, root, { "snapshot" })
    t:eq(snap.tasks[1].title, "a", "no partial write"); t:eq(snap.tasks[1].revision, 1)
    local stale = v3.cli(root, { "set", "T-001", "--expect-revision", "5", "--title", "b" }); t:eq(stale.code, 3); t:match(stale.stderr, "revision conflict")
    local pf = t:tmpdir("p") .. "/p.md"; sb.write(pf, "new prompt\n")
    local ok = v3.cli_json(t, root, { "set", "T-001", "--expect-revision", "1", "--title", "b", "--timeout", "60", "--file", pf })
    t:eq(ok.revision, 2); t:eq(ok.task.prompt_revision, 2); t:eq(sb.read(root .. "/prompts/T-001/r2.md"), "new prompt\n")
    t:ok(sb.exists(root .. "/prompts/T-001/r1.md"), "old prompt revision retained")
    local legacy = v3.cli(root, { "set", "T-001", "priority=3" }); t:eq(legacy.code, 0); t:match(legacy.stderr, "legacy set semantics")
    local invalid_legacy = v3.cli(root, { "set", "T-001", "timeout=-1" }); t:eq(invalid_legacy.code, 3, "legacy form shares the validator")
  end },
  { id = "queue.edit_rejected_once_running", tasks = { "SDD-024" }, suites = { "core" }, run = function(t)
    local m = v3.mods()
    local root, ctx = v3.board(t, "edit2")
    local task = v3.add(t, ctx, { id = "T-001" })
    -- simulate dispatch reserving an attempt
    m.B.txn(ctx, {}, function(state)
      local a, nt = m.O.reserve_attempt(ctx, state.tasks["T-001"], { cwd = root })
      return { { type = "attempt.reserved", task_id = "T-001", attempt_id = a.attempt_id, payload = { attempt = a, task = nt } } }
    end)
    local ok, err = pcall(m.O.edit, ctx, "T-001", { expected_revision = 2, title = "late" })
    t:ok(not ok and err.message:match("only queued"), "running task's prompt/config is immutable")
    t:eq(sb.exists(root .. "/prompts/T-001/r2.md"), false)
  end },
  { id = "queue.dependency_graph_validation", tasks = { "SDD-025" }, suites = { "core" }, run = function(t)
    local root = v3.board(t, "deps")
    local miss = v3.cli(root, { "add", "--id", "T-001", "--dep", "MISSING" }, { stdin = "x\n" }); t:eq(miss.code, 3); t:match(miss.stderr, "unknown dependency")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "add", "--id", "T-002", "--dep", "T-001" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "add", "--id", "T-003", "--dep", "T-002" }, { stdin = "x\n" })
    local self_dep = v3.cli(root, { "set", "T-001", "--expect-revision", "1", "--deps", "T-001" }); t:eq(self_dep.code, 3); t:match(self_dep.stderr, "itself")
    local direct = v3.cli(root, { "set", "T-001", "--expect-revision", "1", "--deps", "T-002" }); t:eq(direct.code, 3); t:match(direct.stderr, "cycle")
    local indirect = v3.cli(root, { "set", "T-001", "--expect-revision", "1", "--deps", "T-003" }); t:eq(indirect.code, 3); t:match(indirect.stderr, "cycle")
  end },
  { id = "queue.blockers_derived_from_upstream_outcomes", tasks = { "SDD-025" }, suites = { "core" }, run = function(t)
    local m = v3.mods()
    local root, ctx = v3.board(t, "block")
    v3.add(t, ctx, { id = "T-001" }); v3.add(t, ctx, { id = "T-002", depends_on = { "T-001" } })
    local snap = m.B.snapshot(ctx)
    t:eq(snap.tasks[2].display, "Blocked"); t:eq(snap.tasks[2].blockers[1].text, "waiting for T-001 (queued)")
    -- upstream fails
    local attempt
    m.B.txn(ctx, {}, function(state)
      local a, nt = m.O.reserve_attempt(ctx, state.tasks["T-001"], {}); attempt = a
      return { { type = "attempt.reserved", task_id = "T-001", attempt_id = a.attempt_id, payload = { attempt = a, task = nt } } }
    end)
    m.O.attempt_finished(ctx, attempt.attempt_id, { state = "failed", exit_code = 1, reason = "exit 1" })
    snap = m.B.snapshot(ctx)
    local t2 = vim.tbl_filter(function(x) return x.id == "T-002" end, snap.tasks)[1]
    t:eq(t2.display, "Blocked"); t:eq(t2.blockers[1].text, "blocked by T-001 (failed)")
    -- retry alone does not unblock
    m.O.retry(ctx, "T-001")
    snap = m.B.snapshot(ctx); t2 = vim.tbl_filter(function(x) return x.id == "T-002" end, snap.tasks)[1]
    t:eq(t2.blockers[1].reason, "queued")
    -- upstream success unblocks
    m.B.txn(ctx, {}, function(state)
      local a, nt = m.O.reserve_attempt(ctx, state.tasks["T-001"], {}); attempt = a
      return { { type = "attempt.reserved", task_id = "T-001", attempt_id = a.attempt_id, payload = { attempt = a, task = nt } } }
    end)
    m.O.attempt_finished(ctx, attempt.attempt_id, { state = "succeeded", exit_code = 0 })
    snap = m.B.snapshot(ctx); t2 = vim.tbl_filter(function(x) return x.id == "T-002" end, snap.tasks)[1]
    t:eq(t2.display, "Queued"); t:eq(t2.blockers, {})
    t:eq(snap.counts.blocked, 0)
  end },
  { id = "queue.reorder_numeric", tasks = { "SDD-026" }, suites = { "core" }, run = function(t)
    local root = v3.board(t, "move")
    v3.cli_json(t, root, { "add", "--id", "T-001", "--priority", "0" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "add", "--id", "T-002", "--priority", "0" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "add", "--id", "T-003", "--priority", "2000000" }, { stdin = "x\n" })
    local function order()
      local snap = v3.cli_json(t, root, { "snapshot" })
      local out = {}
      for _, task in ipairs(snap.tasks) do out[#out + 1] = task.id .. ":" .. task.priority end
      return out
    end
    t:eq(order(), { "T-001:0", "T-002:0", "T-003:2000000" }, "ties by creation time; large priorities sort numerically")
    local r = v3.cli_json(t, root, { "move", "T-002", "--first" })
    local o = order()
    t:eq(o[1]:match("^T%-002"), "T-002", "move-first at priority 0 stays legal (rebalanced)")
    for _, entry in ipairs(o) do t:ok(tonumber(entry:match(":(%d+)$")) >= 0, "no negative priority: " .. entry) end
    v3.cli_json(t, root, { "move", "T-003", "--before", "T-001" })
    o = order(); t:eq(o[1]:match("^T%-%d+"), "T-002"); t:eq(o[2]:match("^T%-%d+"), "T-003"); t:eq(o[3]:match("^T%-%d+"), "T-001")
    v3.cli_json(t, root, { "move", "T-002", "--last" })
    o = order(); t:eq(o[3]:match("^T%-%d+"), "T-002", "repeated moves give the requested order")
  end },
  { id = "queue.reorder_cannot_touch_running", tasks = { "SDD-026" }, suites = { "core" }, run = function(t)
    local m = v3.mods()
    local root, ctx = v3.board(t, "move2")
    v3.add(t, ctx, { id = "T-001" }); v3.add(t, ctx, { id = "T-002" })
    m.B.txn(ctx, {}, function(state)
      local a, nt = m.O.reserve_attempt(ctx, state.tasks["T-001"], {})
      return { { type = "attempt.reserved", task_id = "T-001", attempt_id = a.attempt_id, payload = { attempt = a, task = nt } } }
    end)
    local ok, err = pcall(m.O.move, ctx, "T-001", "last"); t:ok(not ok and err.message:match("only queued"))
    local ok2, err2 = pcall(m.O.move, ctx, "T-002", "before", "T-001"); t:ok(not ok2 and err2.message:match("must be queued"))
  end },
  { id = "attempt.identities_immutable_and_disjoint", tasks = { "SDD-027" }, suites = { "core" }, run = function(t)
    local m = v3.mods()
    local root, ctx = v3.board(t, "att")
    v3.add(t, ctx, { id = "T-001", timeout = 30 })
    local a1
    m.B.txn(ctx, {}, function(state)
      local a, nt = m.O.reserve_attempt(ctx, state.tasks["T-001"], { cwd = "/tmp/x" }); a1 = a
      return { { type = "attempt.reserved", task_id = "T-001", attempt_id = a.attempt_id, payload = { attempt = a, task = nt } } }
    end)
    m.O.attempt_finished(ctx, a1.attempt_id, { state = "failed", exit_code = 2 })
    local task = m.O.retry(ctx, "T-001")
    -- task edit after retry must not rewrite the reserved attempt's frozen config
    m.O.edit(ctx, "T-001", { expected_revision = task.revision, timeout = 99 })
    local a2
    m.B.txn(ctx, {}, function(state)
      local a, nt = m.O.reserve_attempt(ctx, state.tasks["T-001"], { cwd = "/tmp/y" }); a2 = a
      return { { type = "attempt.reserved", task_id = "T-001", attempt_id = a.attempt_id, payload = { attempt = a, task = nt } } }
    end)
    t:neq(a1.attempt_id, a2.attempt_id); t:eq(a1.ordinal, 1); t:eq(a2.ordinal, 2)
    t:neq(a1.paths.dir, a2.paths.dir); t:neq(a1.paths.report, a2.paths.report); t:neq(a1.paths.stdout, a2.paths.stdout)
    local st = m.B.read_state(ctx)
    t:eq(st.attempts[a1.attempt_id].config.timeout, 30, "reserved config frozen"); t:eq(st.attempts[a2.attempt_id].config.timeout, 99)
    t:eq(st.tasks["T-001"].attempts, { a1.attempt_id, a2.attempt_id })
    t:eq(st.tasks["T-001"].current_attempt_id, a2.attempt_id, "task id vs current attempt identity distinguished")
    local imported = { attempt_id = m.U.uuid(), task_id = "T-001", ordinal = 1, state = "failed", config = {}, paths = {}, imported = { legacy = true, history = "unknown" } }
    t:ok(m.P.validate_attempt(imported)); t:ok(imported.imported.legacy, "imported identity remains explicitly distinguishable")
  end },
}
