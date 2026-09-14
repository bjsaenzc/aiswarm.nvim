-- SDD-018 init, SDD-019 locks, SDD-020 committed transactions, SDD-021 projections, SDD-022 recovery.
local sb = require("helpers.sandbox")
local v3 = require("helpers.v3")
local uv = vim.uv

local function fake_owner(t, root, owner)
  local dir = root .. "/locks/control.d"; vim.fn.mkdir(dir, "p")
  sb.write(dir .. "/owner.json", vim.json.encode(owner))
end

return {
  -- ------------------------------------------------------------ SDD-018
  { id = "board.init_is_explicit_and_idempotent", tasks = { "SDD-018" }, suites = { "core" }, run = function(t)
    local root, ctx = v3.board(t, "b1")
    local m = v3.mods()
    t:ok(m.P.valid_uuid(ctx.board.board_id)); t:eq(ctx.board.schema_version, 3); t:eq(ctx.board.journal_generation, 1)
    sb.write(root .. "/context/MISSION.md", "# custom mission\n")
    local again, created = m.B.init(root); t:eq(created, false); t:eq(again.board_id, ctx.board.board_id)
    t:eq(sb.read(root .. "/context/MISSION.md"), "# custom mission\n", "context preserved")
    local _, ctx2 = v3.board(t, "b2"); t:neq(ctx2.board.board_id, ctx.board.board_id, "separate boards get different identities")
  end },
  { id = "board.reads_on_missing_board_create_nothing", tasks = { "SDD-018" }, suites = { "core" }, run = function(t)
    local dir = t:tmpdir("nb"); local root = dir .. "/.aiswarm"
    local r = v3.cli(root, { "snapshot" }); t:eq(r.code, 4); t:match(r.stderr, "no board")
    local r2 = v3.cli(root, { "add", "--id", "T-1" }, { stdin = "x\n" }); t:eq(r2.code, 4)
    t:ok(not sb.exists(root), "no board directory created by commands against a missing board")
    t:ok(not sb.exists(root .. "/locks"), "no locks fragment")
    local d = v3.cli_json(t, root, { "doctor" }); t:eq(d.schema, "missing"); t:eq(d.api_version, 3)
    t:ok(not sb.exists(root), "doctor creates nothing either")
  end },
  { id = "board.init_cli_creates_v3", tasks = { "SDD-018" }, suites = { "core" }, run = function(t)
    local dir = t:tmpdir("cli"); local root = dir .. "/.aiswarm"
    local r = v3.cli_json(t, root, { "init", "--name", "demo" }); t:eq(r.created, true)
    local d = v3.cli_json(t, root, { "doctor" }); t:eq(d.schema, "v3"); t:eq(d.board_id, r.board_id)
    local snap = v3.cli_json(t, root, { "snapshot" }); t:eq(snap.control_seq, 0); t:eq(snap.tasks, {}); t:eq(snap.name, "demo")
  end },
  -- ------------------------------------------------------------ SDD-019
  { id = "lock.contenders_serialize", tasks = { "SDD-019" }, suites = { "core", "reliability" }, run = function(t)
    local root = v3.board(t, "lock")
    -- N concurrent adds through the CLI must all succeed with unique ids
    local jobs = {}
    for i = 1, 6 do
      jobs[i] = vim.system({ sb.bin("aiswarm"), "add", "--title", "c" .. i }, { text = true, env = sb.env(root), cwd = vim.fs.dirname(root), stdin = "p\n" })
    end
    local ids = {}
    for _, j in ipairs(jobs) do local o = j:wait(30000); t:eq(o.code, 0, o.stderr); ids[vim.trim(o.stdout)] = true end
    t:eq(vim.tbl_count(ids), 6, "unique ids under contention")
    t:eq(sb.exists(root .. "/locks/control.d"), false, "lock released")
  end },
  { id = "lock.live_owner_never_stolen", tasks = { "SDD-019" }, suites = { "core", "reliability" }, run = function(t)
    local root = v3.board(t, "lock2")
    local m = v3.mods()
    local holder = vim.system({ "sleep", "30" }, {})  -- a live process that "owns" the lock
    t:defer(function() holder:kill(9) end)
    fake_owner(t, root, { pid = holder.pid, pid_start = m.U.pid_start(holder.pid), host = uv.os_gethostname(), acquired_at = m.U.now_iso(), purpose = "test" })
    local h, err = m.L.acquire(root, { timeout_ms = 300 })
    t:eq(h, nil); t:match(err, "timed out waiting for the control lock held by pid " .. holder.pid)
    t:ok(sb.exists(root .. "/locks/control.d/owner.json"), "live owner's lock untouched")
  end },
  { id = "lock.dead_owner_recovered", tasks = { "SDD-019" }, suites = { "core", "reliability" }, run = function(t)
    local root = v3.board(t, "lock3")
    local m = v3.mods()
    local dead = vim.system({ "sleep", "30" }, {}); local pid = dead.pid; local start = m.U.pid_start(pid)
    dead:kill(9); dead:wait(2000)
    fake_owner(t, root, { pid = pid, pid_start = start, host = uv.os_gethostname(), acquired_at = m.U.now_iso(), purpose = "crashed" })
    local h, err = m.L.acquire(root, { timeout_ms = 2000 })
    t:ok(h, tostring(err)); m.L.release(h)
    t:ok(#vim.fn.glob(root .. "/locks/stale-*", false, true) == 1, "stale lock moved aside, not deleted blindly")
  end },
  { id = "lock.pid_reuse_or_unknown_owner_not_deleted", tasks = { "SDD-019" }, suites = { "core", "reliability" }, run = function(t)
    local root = v3.board(t, "lock4")
    local m = v3.mods()
    -- reused pid: a live process whose start time differs from the recorded one → treated as dead (recovered),
    local live = vim.system({ "sleep", "30" }, {}); t:defer(function() live:kill(9) end)
    fake_owner(t, root, { pid = live.pid, pid_start = "Mon Jan  1 00:00:00 1990", host = uv.os_gethostname(), acquired_at = m.U.now_iso() })
    local h = m.L.acquire(root, { timeout_ms = 2000 }); t:ok(h, "different start time proves PID reuse"); m.L.release(h)
    -- unknown host: never deleted
    fake_owner(t, root, { pid = 1, pid_start = "x", host = "some-other-host", acquired_at = m.U.now_iso() })
    local h2, err = m.L.acquire(root, { timeout_ms = 300 })
    t:eq(h2, nil); t:match(err, "unknown owner")
    t:ok(sb.exists(root .. "/locks/control.d/owner.json"))
    vim.fn.delete(root .. "/locks/control.d", "rf")
  end },
  { id = "lock.sigkilled_holder_leaves_recoverable_lock", tasks = { "SDD-019" }, suites = { "core", "reliability" }, run = function(t)
    local root = v3.board(t, "lock5")
    -- a runtime process holding the lock while blocked, then SIGKILLed
    local script = t:tmpdir("hold") .. "/hold.lua"
    sb.write(script, ([[
      package.path = %q .. "/lua/?.lua;" .. package.path
      local L = require("aiswarm.runtime.lock")
      local h = assert(L.acquire(%q, { purpose = "holder" }))
      io.stdout:write("held\n"); io.stdout:flush()
      vim.uv.sleep(60000)
    ]]):format(sb.plugin, root))
    local held = false
    local job = vim.system({ vim.env.AISWARM_NVIM, "--clean", "--headless", "-u", "NONE", "-i", "NONE", "-l", script }, { text = true,
      stdout = function(_, d) if d and d:find("held") then held = true end end })
    t:wait(5000, function() return held end, "holder acquired")
    job:kill(9); job:wait(2000)
    local m = v3.mods()
    local h, err = m.L.acquire(root, { timeout_ms = 3000 }); t:ok(h, tostring(err)); m.L.release(h)
  end },
  -- ------------------------------------------------------------ SDD-020
  { id = "journal.concurrent_writers_unique_contiguous", tasks = { "SDD-020" }, suites = { "core", "reliability" }, run = function(t)
    local root = v3.board(t, "j1")
    local jobs = {}
    for i = 1, 8 do jobs[i] = vim.system({ sb.bin("aiswarm"), "add", "--title", "w" .. i }, { text = true, env = sb.env(root), cwd = vim.fs.dirname(root), stdin = "p\n" }) end
    for _, j in ipairs(jobs) do t:eq(j:wait(30000).code, 0) end
    local recs = v3.journal_records(root)
    t:eq(#recs, 8)
    for i, r in ipairs(recs) do t:eq(r.control_seq, i, "contiguous sequence") end
    t:eq(vim.trim(sb.read(root .. "/control/seq")), "8")
  end },
  { id = "journal.fault_injection_never_reuses_committed_seq", tasks = { "SDD-020", "SDD-022" }, suites = { "core", "reliability" }, run = function(t)
    local m = v3.mods()
    for _, fault in ipairs({ "before_append", "after_append", "after_sidecar", "mid_projection" }) do
      local root, ctx = v3.board(t, fault)
      v3.add(t, ctx, { id = "T-001" })
      ctx.fault = fault
      local ok, err = pcall(v3.add, t, ctx, { id = "T-002" })
      t:ok(not ok and tostring(err.message or err):match("fault injected"), fault .. " raised")
      ctx.fault = nil
      -- a fresh process view: recover then add another task
      local ctx2 = m.B.load(root)
      local t3 = v3.add(t, ctx2, { id = "T-003" })
      local recs = v3.journal_records(root)
      local seqs = {}
      for _, r in ipairs(recs) do t:ok(not seqs[r.control_seq], fault .. ": seq " .. r.control_seq .. " unique"); seqs[r.control_seq] = r end
      for i = 2, #recs do t:eq(recs[i].control_seq, recs[i - 1].control_seq + 1, fault .. ": contiguous") end
      local snap = m.B.snapshot(ctx2)
      local ids = vim.tbl_map(function(x) return x.id end, snap.tasks); table.sort(ids)
      if fault == "before_append" then t:eq(ids, { "T-001", "T-003" }, fault .. ": uncommitted add absent")
      else t:eq(ids, { "T-001", "T-002", "T-003" }, fault .. ": committed add recovered into projections") end
      t:eq(snap.control_seq, recs[#recs].control_seq, fault .. ": snapshot reports the fully applied committed seq")
      t:ok(sb.exists(root .. "/prompts/T-003/r1.md"))
      t:eq(t3.id, "T-003")
    end
  end },
  { id = "journal.missing_sidecar_and_fragment_recovered", tasks = { "SDD-020", "SDD-022" }, suites = { "core", "reliability" }, run = function(t)
    local root, ctx = v3.board(t, "j3")
    local m = v3.mods()
    v3.add(t, ctx, { id = "T-001" }); v3.add(t, ctx, { id = "T-002" })
    os.remove(root .. "/control/seq")
    -- append an uncommitted trailing fragment (crash mid-write)
    local f = io.open(root .. "/control/journal.jsonl", "a"); f:write('{"control_seq":3,"type":"task.queued","payl'); f:close()
    local ctx2 = m.B.load(root)
    local task = v3.add(t, ctx2, { id = "T-003" })
    local recs = v3.journal_records(root)
    t:eq(#recs, 3); t:eq(recs[3].control_seq, 3); t:eq(recs[3].payload.task.id, "T-003")
    t:eq(#vim.fn.glob(root .. "/control/quarantine/*.jsonl", false, true), 1, "fragment quarantined, not lost silently")
    t:eq(vim.trim(sb.read(root .. "/control/seq")), "3")
  end },
  { id = "journal.incomplete_txn_tail_quarantined", tasks = { "SDD-020", "SDD-022" }, suites = { "core", "reliability" }, run = function(t)
    local root, ctx = v3.board(t, "j4")
    local m = v3.mods()
    v3.add(t, ctx, { id = "T-001" })
    -- write a two-record txn with only the first record (last=false) present
    local rec = vim.deepcopy(v3.journal_records(root)[1])
    rec.control_seq, rec.event_id = 2, rec.board_id .. ":c:1:2"; rec.txn = { id = "tx-partial", index = 1, count = 2, last = false }
    rec.payload.task.id = "T-GHOST"
    local f = io.open(root .. "/control/journal.jsonl", "a"); f:write(vim.json.encode(rec) .. "\n"); f:close()
    local snap = m.B.snapshot(m.B.load(root))
    t:eq(vim.tbl_map(function(x) return x.id end, snap.tasks), { "T-001" }, "half a transaction is never visible")
    t:eq(snap.control_seq, 1)
  end },
  -- ------------------------------------------------------------ SDD-021
  { id = "projection.replay_twice_identical", tasks = { "SDD-021" }, suites = { "core" }, run = function(t)
    local root, ctx = v3.board(t, "p1")
    local m = v3.mods()
    v3.add(t, ctx, { id = "T-001", priority = 5 }); v3.add(t, ctx, { id = "T-002", depends_on = { "T-001" } })
    m.O.edit(ctx, "T-002", { expected_revision = 1, title = "renamed" })
    local recs = v3.journal_records(root)
    local s1 = { tasks = {}, attempts = {}, scheduler = {} }; m.R.replay(s1, recs)
    local s2 = { tasks = {}, attempts = {}, scheduler = {} }; m.R.replay(s2, recs); m.R.replay(s2, recs)
    t:eq(s1.tasks, s2.tasks)
    local snap = m.B.snapshot(ctx)
    t:eq(snap.counts.queued, 2); t:eq(snap.counts.blocked, 1)
    t:eq(vim.tbl_map(function(x) return x.id end, snap.tasks), { "T-001", "T-002" })
  end },
  { id = "projection.stale_applied_is_rebuilt", tasks = { "SDD-021", "SDD-022" }, suites = { "core", "reliability" }, run = function(t)
    local root, ctx = v3.board(t, "p2")
    local m = v3.mods()
    v3.add(t, ctx, { id = "T-001" }); v3.add(t, ctx, { id = "T-002" })
    os.remove(root .. "/control/tasks/T-002.json"); sb.write(root .. "/control/applied.json", '{"seq":1}')
    local snap = m.B.snapshot(m.B.load(root))
    t:eq(#snap.tasks, 2, "missing projection restored from committed history")
    -- projections ahead of the journal (journal truncated): rebuilt from committed records only
    sb.write(root .. "/control/applied.json", '{"seq":99}')
    sb.write(root .. "/control/tasks/T-999.json", vim.json.encode(vim.tbl_extend("force", snap.tasks[1], { id = "T-999" })))
    local snap2 = m.B.snapshot(m.B.load(root))
    t:eq(vim.tbl_map(function(x) return x.id end, snap2.tasks), { "T-001", "T-002" }, "phantom projection removed")
    t:eq(snap2.control_seq, 2)
  end },
  { id = "projection.snapshot_never_sees_half_operation", tasks = { "SDD-021" }, suites = { "core", "reliability" }, run = function(t)
    local root, ctx = v3.board(t, "p3")
    for i = 1, 5 do v3.add(t, ctx, { id = ("T-%03d"):format(i), priority = 0 }) end
    -- a mover renumbers everything (multi-record txn: all priorities are 0) while snapshots run concurrently
    local mover = vim.system({ sb.bin("aiswarm"), "move", "T-005", "--first" }, { text = true, env = sb.env(root), cwd = vim.fs.dirname(root) })
    local readers = {}
    for i = 1, 4 do readers[i] = vim.system({ sb.bin("aiswarm"), "snapshot" }, { text = true, env = sb.env(root), cwd = vim.fs.dirname(root) }) end
    t:eq(mover:wait(20000).code, 0)
    for _, r in ipairs(readers) do
      local o = r:wait(20000); t:eq(o.code, 0, o.stderr)
      local snap = sb.json(o.stdout)
      local prios = {}
      for _, task in ipairs(snap.tasks) do prios[#prios + 1] = task.priority end
      table.sort(prios)
      if snap.control_seq == 5 then t:eq(prios, { 0, 0, 0, 0, 0 }, "before the move")
      else t:eq(snap.control_seq, 9, "T-005 already had priority 0, so four records change"); t:eq(prios, { 0, 10, 20, 30, 40 }, "after the whole move; never a mix") end
    end
  end },
  -- ------------------------------------------------------------ SDD-022
  { id = "recovery.corrupt_interior_record_not_skipped_silently", tasks = { "SDD-022" }, suites = { "core", "reliability" }, run = function(t)
    local root, ctx = v3.board(t, "r1")
    local m = v3.mods()
    v3.add(t, ctx, { id = "T-001" }); v3.add(t, ctx, { id = "T-002" }); v3.add(t, ctx, { id = "T-003" })
    local lines = vim.split(sb.read(root .. "/control/journal.jsonl"), "\n", { trimempty = true })
    lines[2] = lines[2]:sub(1, 40) .. "CORRUPT"
    sb.write(root .. "/control/journal.jsonl", table.concat(lines, "\n") .. "\n")
    local ctx2 = m.B.load(root)
    local recs = v3.journal_records(root)
    t:eq(#recs, 2, "corrupt interior record is not decodable")
    -- recovery must report it: the sidecar/applied seq stays honest and quarantine is not used for interior damage
    local state, rep = m.L.with(root, {}, function() return m.B.recover(ctx2) end)
    t:eq(rep.committed_seq, 3, "committed sequence from the last valid record")
    local snap = m.B.snapshot(ctx2)
    t:ok(#snap.tasks == 3, "existing projections preserved; interior corruption does not delete state")
  end },
  { id = "recovery.restart_at_every_crash_point_matches_committed", tasks = { "SDD-022" }, suites = { "core", "reliability" }, run = function(t)
    local m = v3.mods()
    for _, fault in ipairs({ "after_append", "after_sidecar", "mid_projection" }) do
      local root, ctx = v3.board(t, "rc-" .. fault)
      v3.add(t, ctx, { id = "T-001" })
      ctx.fault = fault
      pcall(m.O.edit, ctx, "T-001", { expected_revision = 1, title = "edited" })
      ctx.fault = nil
      local recs = v3.journal_records(root)
      local snap = m.B.snapshot(m.B.load(root))
      t:eq(snap.tasks[1].title, recs[#recs].payload.task.title, fault .. ": projection equals committed record")
      t:eq(snap.tasks[1].revision, 2); t:eq(snap.control_seq, 2)
    end
  end },
}
