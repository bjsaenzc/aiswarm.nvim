-- SDD-078 frames, SDD-079 logs, SDD-080 multiplex, SDD-081 bootstrap, SDD-082 cursors, SDD-083 ack,
-- SDD-084 retention, SDD-085 degradation, SDD-086 durable consumer, SDD-087 briefing.
local sb = require("helpers.sandbox")
local v3 = require("helpers.v3")
local uv = vim.uv
local function kill_server(t) t:defer(function() sb.tmux({ "kill-server" }) end) end
local function env_for(scenario, extra) return v3.provider_env(scenario, vim.tbl_extend("force", { AISWARM_HEARTBEAT_MS = "100", AISWARM_FLUSH_MS = "30" }, extra or {})) end
local function snapshot(t, root) return v3.cli_json(t, root, { "snapshot" }) end
local function task_of(snap, id) for _, x in ipairs(snap.tasks) do if x.id == id then return x end end end
local function attempt_of(snap, id) for _, a in ipairs(snap.attempts) do if a.task_id == id then return a end end end
local function terminal(x) return x.state == "succeeded" or x.state == "failed" or x.state == "cancelled" end
local function wait_task(t, root, id, pred, ms)
  local task
  t:wait(ms or 20000, function() local s = sb.json(v3.cli(root, { "snapshot", "--json" }).stdout); task = s and task_of(s, id); return task and pred(task) end, "task " .. id)
  return task
end
local function run(t, root, id, scenario, extra)
  v3.cli_json(t, root, { "add", "--id", id }, { stdin = "x\n" })
  v3.cli_json(t, root, { "dispatch" }, { env = env_for(scenario, extra) })
  return wait_task(t, root, id, terminal), attempt_of(snapshot(t, root), id)
end
--- Run `stream` (non-follow) and decode frames.
local function stream(t, root, args, opts)
  local r = v3.cli(root, vim.list_extend({ "stream" }, args or {}), opts)
  local frames = {}
  for line in r.stdout:gmatch("[^\n]+") do local f = sb.json(line); if f then frames[#frames + 1] = f end end
  return frames, r
end
local function events(frames) local out = {}; for _, f in ipairs(frames) do if f.frame == "event" then out[#out + 1] = f end end return out end
local function last_cursor(frames) local c; for _, f in ipairs(frames) do if f.next_cursor and f.next_cursor ~= "" then c = f.next_cursor end end return c end

return {
  -- ------------------------------------------------------------ SDD-078
  { id = "frames.every_split_round_trips", tasks = { "SDD-078" }, suites = { "core" }, run = function(t)
    local F = require("aiswarm.runtime.frames")
    local fx = sb.read(sb.plugin .. "/tests/fixtures/protocol/valid/frames.jsonl")
    local expected = {}
    for line in fx:gmatch("[^\n]+") do expected[#expected + 1] = sb.json(line) end
    for split = 1, #fx - 1 do
      local d = F.decoder()
      local a = d:feed(fx:sub(1, split)); local b = d:feed(fx:sub(split + 1))
      local got = vim.list_extend(a, b)
      t:eq(#got, #expected, "split at " .. split); t:eq(got[#got].frame, "status")
    end
    for _, f in ipairs(expected) do t:eq(sb.json(F.encode(f)), f) end
  end },
  { id = "frames.malformed_oversized_and_incompatible", tasks = { "SDD-078" }, suites = { "core", "reliability" }, run = function(t)
    local F = require("aiswarm.runtime.frames")
    local d = F.decoder()
    local frames, diags = d:feed("{bad json\n\255\254 not utf8\n" .. F.encode({ frame = "status", state = "live", next_cursor = "c" }))
    t:eq(#frames, 1); t:eq(#diags, 2); t:eq(diags[1].code, "malformed_frame")
    local d2 = F.decoder()
    local _, dg = d2:feed(("x"):rep(F.MAX_PARTIAL + 10))
    t:eq(dg[1].code, "oversized_frame"); t:ok(#d2.buf == 0, "no unbounded accumulation")
    local after = d2:feed("tail-of-oversized\n" .. F.encode({ frame = "status", state = "live", next_cursor = "c" }))
    t:eq(#after, 1, "resynchronized at the next newline")
    local d3 = F.decoder()
    local _, dg3 = d3:feed(F.encode({ frame = "hello", schema_version = 99, board_id = "57fc3ea0-6b8f-45c2-8e8f-3a5f98cc4ed3" }))
    t:eq(dg3[1].code, "incompatible")
    local ok, _, kind = F.validate({ frame = "hello", schema_version = 2, board_id = "57fc3ea0-6b8f-45c2-8e8f-3a5f98cc4ed3" }); t:eq(ok, false); t:eq(kind, "incompatible")
    t:ok(F.validate({ frame = "event", event = { type = "x", extra_additive = 1 }, next_cursor = "c", additive = true }), "additive fields tolerated")
  end },
  -- ------------------------------------------------------------ SDD-079
  { id = "logs.paged_by_segment_offset_and_stream", tasks = { "SDD-079" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "logs")
    local _, a = run(t, root, "T-001", "interleaved")
    local p1 = v3.cli_json(t, root, { "logs", "T-001", "--offset", "0", "--limit", "12" })
    t:eq(p1.data, "out 1\nout 2\n"); t:eq(p1.next_offset, 12); t:eq(p1.eof, false); t:eq(p1.attempt_id, a.attempt_id); t:eq(p1.segment, 1)
    local p2 = v3.cli_json(t, root, { "logs", "T-001", "--offset", tostring(p1.next_offset), "--limit", "1000" })
    t:eq(p2.data, "out 3\nout 4\nout 5\n"); t:eq(p2.eof, true)
    local e = v3.cli_json(t, root, { "logs", "T-001", "--stream", "stderr", "--offset", "0" }); t:eq(e.data, "err 1\nerr 2\nerr 3\nerr 4\nerr 5\n")
    local byord = v3.cli_json(t, root, { "logs", "T-001", "--attempt", "1", "--offset", "0", "--limit", "6" }); t:eq(byord.attempt_id, a.attempt_id)
    t:eq(v3.cli(root, { "logs", "T-001", "--attempt", "7" }).code, 2, "unknown ordinal")
    -- absent output differs from an I/O error
    v3.cli_json(t, root, { "add", "--id", "T-002" }, { stdin = "x\n" })
    local absent = v3.cli(root, { "logs", "T-002", "--json" }); t:eq(absent.code, 2)
    local m = v3.mods()
    local ctx = m.B.load(root)
    m.B.txn(ctx, {}, function(state) local x, nt = m.O.reserve_attempt(ctx, state.tasks["T-002"], {}); return { { type = "attempt.reserved", task_id = "T-002", attempt_id = x.attempt_id, payload = { attempt = x, task = nt } } } end)
    local none = v3.cli_json(t, root, { "logs", "T-002" }); t:eq(none.absent, true); t:eq(none.bytes, 0)
    vim.uv.fs_chmod(a.paths.stdout, 0)
    local io_err = v3.cli(root, { "logs", "T-001", "--offset", "0" }); t:eq(io_err.code, 1); t:match(io_err.stderr, "read error")
    vim.uv.fs_chmod(a.paths.stdout, 420)
    -- an evicted segment is an explicit gap, never silently repeated bytes
    local gap = v3.cli_json(t, root, { "logs", "T-001", "--segment", "9" }); t:eq(gap.gap, true); t:eq(gap.available, { 1 })
  end },
  -- ------------------------------------------------------------ SDD-080 / SDD-081
  { id = "stream.multiplex_follow_discovers_new_attempts", tasks = { "SDD-080", "SDD-081" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "mux")
    run(t, root, "T-001", "progress", { AISWARM_FAKE_PROGRESS = sb.plugin .. "/bin/aiswarm-progress" })
    -- a long-lived reader; a new attempt and appends must become visible while it stays alive
    local lines, job = {}, nil
    job = vim.system({ sb.bin("aiswarm"), "stream", "--follow", "--history", "0" }, { text = true, env = vim.tbl_extend("force", sb.env(root), { AISWARM_NO_FS_EVENTS = "1", AISWARM_STREAM_POLL_MS = "100" }),
      stdout = function(_, data) if data then for l in data:gmatch("[^\n]+") do lines[#lines + 1] = l end end end })
    t:defer(function() pcall(function() job:kill(9) end) end)
    t:wait(5000, function() for _, l in ipairs(lines) do local f = sb.json(l); if f and f.frame == "status" and f.state == "live" then return true end end return false end, "reader live")
    local before = #lines
    run(t, root, "T-002", "progress", { AISWARM_FAKE_PROGRESS = sb.plugin .. "/bin/aiswarm-progress" })
    t:wait(10000, function()
      for i = before + 1, #lines do local f = sb.json(lines[i]); if f and f.frame == "event" and f.event.task_id == "T-002" and f.event.type == "agent.progress" then return true end end
      return false
    end, "new attempt's telemetry delivered without a reader restart (polling fallback only)")
    t:wait(10000, function() for i = before + 1, #lines do local f = sb.json(lines[i]); if f and f.frame == "event" and f.event.type == "task.finished" then return true end end return false end, "completion delivered")
    local kinds, control_seqs = {}, {}
    for i = before + 1, #lines do local f = sb.json(lines[i]); if f and f.frame == "event" then kinds[f.event.type] = true; if f.event.control_seq then control_seqs[#control_seqs + 1] = f.event.control_seq end end end
    t:ok(kinds["task.queued"] and kinds["attempt.reserved"] and kinds["task.finished"], "control records delivered: " .. vim.inspect(vim.tbl_keys(kinds)))
    for i = 2, #control_seqs do t:ok(control_seqs[i] > control_seqs[i - 1], "control order preserved") end
    job:kill(15)
  end },
  { id = "stream.bootstrap_matches_committed_state", tasks = { "SDD-081" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "boot")
    run(t, root, "T-001", "success")
    for i = 2, 4 do v3.cli_json(t, root, { "add", "--id", ("T-%03d"):format(i) }, { stdin = "x\n" }) end
    -- appends racing with attach: snapshot + subsequent events must cover them
    local adders = {}
    for i = 5, 8 do adders[#adders + 1] = vim.system({ sb.bin("aiswarm"), "add", "--id", ("T-%03d"):format(i) }, { text = true, env = sb.env(root), cwd = vim.fs.dirname(root), stdin = "x\n" }) end
    local frames = stream(t, root, { "--once" })
    for _, j in ipairs(adders) do j:wait(20000) end
    local frames2 = stream(t, root, { "--cursor", last_cursor(frames), "--once" })
    local R = require("aiswarm.runtime.reducer")
    local snapf = frames[2]; t:eq(snapf.frame, "snapshot")
    local state = { tasks = {}, attempts = {}, scheduler = snapf.scheduler }
    for _, x in ipairs(snapf.tasks) do state.tasks[x.id] = x end
    for _, a in ipairs(snapf.attempts) do state.attempts[a.attempt_id] = a end
    for _, f in ipairs(vim.list_extend(events(frames), events(frames2))) do if f.event.control_seq then R.apply(state, f.event) end end
    local committed = snapshot(t, root)
    t:eq(vim.tbl_count(state.tasks), #committed.tasks, "consumer reconstruction has every committed task")
    for _, ct in ipairs(committed.tasks) do t:eq(state.tasks[ct.id].revision, ct.revision, ct.id .. " revision") end
    t:ok(frames2[2].control_seq >= snapf.control_seq)
    -- history request: at most 200 context records, all marked historical, no bookmark touched
    local hist = stream(t, root, { "--history", "3", "--once" })
    local h = 0; for _, f in ipairs(events(hist)) do if f.historical then h = h + 1 end end
    t:ok(h > 0 and h <= 3, "bounded history: " .. h)
    t:eq(v3.cli_json(t, root, { "consumers" }), {}, "attach/history never acknowledges")
    -- the initial snapshot's cursor points after the attempt checkpoint: nothing already applied is replayed
    local first_events = events(frames)
    for _, f in ipairs(first_events) do t:ok(not f.event.attempt_seq or f.event.attempt_seq > 0) end
  end },
  -- ------------------------------------------------------------ SDD-082
  { id = "cursor.resume_filter_and_rejections", tasks = { "SDD-082" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "cur")
    run(t, root, "T-001", "progress", { AISWARM_FAKE_PROGRESS = sb.plugin .. "/bin/aiswarm-progress" })
    local all = stream(t, root, { "--history", "200", "--once" })
    local evs = events(all)
    t:ok(#evs >= 8, "enough records: " .. #evs)
    -- stop mid-stream: resume from the cursor after event k delivers exactly the rest
    local k = math.floor(#evs / 2)
    local rest = events(stream(t, root, { "--cursor", evs[k].next_cursor, "--once" }))
    local ids = {}; for i = k + 1, #evs do ids[#ids + 1] = evs[i].event.event_id end
    local got = {}; for _, f in ipairs(rest) do got[#got + 1] = f.event.event_id end
    table.sort(ids); table.sort(got)
    t:eq(got, ids, "no loss, duplicates keep their ids")
    -- filtered page: skipped records advance the cursor; changing filters applies from the cursor on
    local filtered = stream(t, root, { "--history", "200", "--types", "lifecycle", "--once" })
    for _, f in ipairs(events(filtered)) do t:ok(f.event.control_seq ~= nil, "only lifecycle records") end
    local after_filter = events(stream(t, root, { "--cursor", last_cursor(filtered), "--once" }))
    t:eq(#after_filter, 0, "records filtered out earlier are not re-delivered by a later unfiltered resume")
    -- append after completion: a later resume delivers only the new records
    v3.cli_json(t, root, { "add", "--id", "T-002" }, { stdin = "x\n" })
    local more = events(stream(t, root, { "--cursor", last_cursor(all), "--once" }))
    t:eq(#more, 1); t:eq(more[1].event.type, "task.queued")
    -- rejections: another board, impossible future position, old generation
    local Cur = require("aiswarm.runtime.cursor")
    local pos = Cur.decode(last_cursor(all))
    local wrong = Cur.encode(vim.tbl_extend("force", pos, { board = "00000000-0000-4000-8000-000000000000" }))
    local r1 = stream(t, root, { "--cursor", wrong, "--once" }); t:eq(r1[1].frame, "error"); t:eq(r1[1].code, "wrong_board")
    local future = Cur.encode(vim.tbl_extend("force", pos, { control = { g = pos.control.g, seq = 999999 } }))
    local r2 = stream(t, root, { "--cursor", future, "--once" }); t:eq(r2[1].code, "invalid_cursor")
    local old = Cur.encode(vim.tbl_extend("force", pos, { control = { g = 0, seq = 1 } }))
    local r3 = stream(t, root, { "--cursor", old, "--once" }); t:eq(r3[1].code, "resync_required"); t:eq(r3[2].frame, "gap"); t:eq(r3[4].frame, "snapshot")
    local r4 = v3.cli(root, { "stream", "--cursor", "not-a-cursor", "--once" }); t:eq(r4.code, 3)
  end },
  -- ------------------------------------------------------------ SDD-083
  { id = "ack.independent_monotonic_validated", tasks = { "SDD-083" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "ack")
    run(t, root, "T-001", "success")
    local all = stream(t, root, { "--history", "200", "--once" })
    local evs = events(all)
    local mid, last = evs[2].next_cursor, last_cursor(all)
    t:eq(v3.cli_json(t, root, { "ack", "--consumer", "a", "--cursor", mid }).consumer, "a")
    t:eq(v3.cli_json(t, root, { "ack", "--consumer", "b", "--cursor", last }).consumer, "b")
    local list = v3.cli_json(t, root, { "consumers" }); t:eq(#list, 2, "two consumers advance independently")
    local stale = v3.cli(root, { "ack", "--consumer", "b", "--cursor", mid }); t:eq(stale.code, 3); t:match(stale.stderr, "stale")
    t:eq(v3.cli(root, { "ack", "--consumer", "bad name!", "--cursor", last }).code, 3)
    t:eq(v3.cli(root, { "ack", "--consumer", "c", "--cursor", "zzz" }).code, 3)
    local Cur = require("aiswarm.runtime.cursor")
    local pos = Cur.decode(last)
    t:eq(v3.cli(root, { "ack", "--consumer", "c", "--cursor", Cur.encode(vim.tbl_extend("force", pos, { board = "00000000-0000-4000-8000-000000000000" })) }).code, 3, "unrelated board")
    t:eq(v3.cli(root, { "ack", "--consumer", "c", "--cursor", Cur.encode(vim.tbl_extend("force", pos, { control = { g = pos.control.g, seq = 9999 } })) }).code, 3, "unissued/future")
    -- a resumed stream for consumer a starts from its bookmark, not from the end
    local resumed = events(stream(t, root, { "--consumer", "a", "--once" }))
    t:eq(#resumed, #evs - 2)
    -- bookmark file is always a whole valid document (atomic replace)
    local bm = sb.json(sb.read(root .. "/control/consumers/a.json")); t:ok(bm and bm.cursor == mid)
    t:eq(#vim.fn.glob(root .. "/control/consumers/*.tmp*", false, true), 0)
  end },
  -- ------------------------------------------------------------ SDD-084
  { id = "retention.rotation_eviction_and_gaps", tasks = { "SDD-084" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "ret")
    local _, a = run(t, root, "T-001", "flood", { AISWARM_FAKE_LINES = "6000", AISWARM_LOG_SEGMENT_BYTES = "40000", AISWARM_RAW_CAP_BYTES = "100000", AISWARM_FLUSH_MS = "5", AISWARM_TELEMETRY_CAP_BYTES = "6000" })
    local segs = require("aiswarm.runtime.telemetry_commands").segments(a.paths.dir, "stdout")
    t:ok(#segs >= 2, "rotated into several segments: " .. #segs)
    t:ok(segs[1].n > 1, "oldest closed segments evicted under the cap; the latest (open) segment survived")
    t:ok(sb.exists(a.paths.dir .. "/retention.json"))
    local total = 0; for _, s in ipairs(segs) do total = total + uv.fs_stat(s.path).size end
    t:ok(total <= 100000 + 65536, "combined size bounded: " .. total)
    local gap = v3.cli_json(t, root, { "logs", "T-001", "--segment", "1" }); t:eq(gap.gap, true)
    t:ok(sb.exists(a.paths.report), "report kept")
    -- telemetry rotated by generation: the stream reports an explicit generation gap and remains replayable
    local closed = vim.fn.glob(a.paths.dir .. "/telemetry.g*.closed.jsonl", false, true)
    t:ok(#closed >= 1, "telemetry journal rotated: " .. #closed)
    local frames = stream(t, root, { "--history", "200", "--once" })
    local gaps = 0; for _, f in ipairs(frames) do if f.frame == "gap" and f.reason == "generation" then gaps = gaps + 1 end end
    t:ok(gaps >= 1, "generation gap emitted")
    t:ok(#events(frames) > 0, "retained records replayable")
    -- inactive history eviction keeps reports and control outcomes
    local r = v3.cli_json(t, root, { "retention", "--days", "0" })
    t:eq(r.evicted_attempts, { a.attempt_id })
    t:ok(sb.exists(a.paths.report) and sb.exists(a.paths.config)); t:ok(not sb.exists(a.paths.telemetry))
    t:eq(task_of(snapshot(t, root), "T-001").state, "succeeded", "control outcome untouched")
  end },
  -- ------------------------------------------------------------ SDD-085
  { id = "degrade.lifecycle_commit_failure_reports_recovery_required", tasks = { "SDD-085" }, suites = { "core", "reliability" }, run = function(t)
    local m = v3.mods()
    local root, ctx = v3.board(t, "commit")
    v3.add(t, ctx, { id = "T-001" })
    uv.fs_chmod(root .. "/control/journal.jsonl", 256) -- read-only journal: append must fail
    t:defer(function() uv.fs_chmod(root .. "/control/journal.jsonl", 420) end)
    local r = v3.cli(root, { "cancel", "T-001" })
    t:ok(r.code ~= 0, "no durable success claimed"); t:match(r.stderr, "journal append failed")
    uv.fs_chmod(root .. "/control/journal.jsonl", 420)
    t:eq(task_of(snapshot(t, root), "T-001").state, "queued", "state unchanged after the failed commit")
  end },
  -- ------------------------------------------------------------ SDD-086
  { id = "consumer.durable_delivery_survives_restarts", tasks = { "SDD-086" }, suites = { "core", "reliability" }, isolated = false, run = function(t)
    kill_server(t)
    local root = v3.board(t, "consumer")
    run(t, root, "T-001", "progress", { AISWARM_FAKE_PROGRESS = sb.plugin .. "/bin/aiswarm-progress" })
    local inbox = t:tmpdir("inbox") .. "/inbox.jsonl"
    local function consumer(fault, opts)
      opts = opts or {}
      local env = vim.tbl_extend("force", sb.env(root), { AISWARM_CONSUMER_FAULT = fault, AISWARM_NO_FS_EVENTS = "1", AISWARM_STREAM_POLL_MS = "100" })
      local o = vim.system({ vim.env.AISWARM_NVIM, "--clean", "--headless", "-u", "NONE", "-i", "NONE", "-l", sb.plugin .. "/tests/fixtures/consumer/consumer.lua",
        "--bin", sb.bin("aiswarm"), "--root", root, "--name", "orchestrator-main", "--inbox", inbox, "--batch", "3", "--exit-after-idle", tostring(opts.idle or 1500) },
        { text = true, env = env }):wait(30000)
      return o
    end
    local o1 = consumer("before_accept"); t:match(o1.stdout, "FAULT before_accept"); t:eq(sb.read(inbox), nil, "nothing accepted before the crash")
    local o2 = consumer("after_accept"); t:match(o2.stdout, "FAULT after_accept")
    local o3 = consumer("after_ack"); t:match(o3.stdout, "FAULT after_ack")
    local o4 = consumer(nil); t:match(o4.stdout, "IDLE")
    -- new work while the consumer is away, then a final run picks it up
    v3.cli_json(t, root, { "add", "--id", "T-002" }, { stdin = "x\n" })
    local o5 = consumer(nil); t:match(o5.stdout, "IDLE")
    local seen, dup = {}, 0
    for line in (sb.read(inbox) or ""):gmatch("[^\n]+") do local r = sb.json(line); if seen[r.event_id] then dup = dup + 1 end seen[r.event_id] = true end
    t:eq(dup, 0, "duplicates have one inbox effect")
    local all = events(stream(t, root, { "--history", "200", "--once" }))
    for _, f in ipairs(all) do t:ok(seen[f.event.event_id], "every retained event eventually accepted: " .. f.event.event_id) end
    local bm = sb.json(sb.read(root .. "/control/consumers/orchestrator-main.json")); t:ok(bm and bm.cursor, "bookmark persisted")
    -- two consumer instances at once: bookmarks stay valid documents and never regress
    local c1 = vim.system({ vim.env.AISWARM_NVIM, "--clean", "--headless", "-u", "NONE", "-i", "NONE", "-l", sb.plugin .. "/tests/fixtures/consumer/consumer.lua", "--bin", sb.bin("aiswarm"), "--root", root, "--name", "orchestrator-main", "--inbox", inbox, "--exit-after-idle", "1000" }, { text = true, env = vim.tbl_extend("force", sb.env(root), { AISWARM_NO_FS_EVENTS = "1" }) })
    local c2 = vim.system({ vim.env.AISWARM_NVIM, "--clean", "--headless", "-u", "NONE", "-i", "NONE", "-l", sb.plugin .. "/tests/fixtures/consumer/consumer.lua", "--bin", sb.bin("aiswarm"), "--root", root, "--name", "orchestrator-main", "--inbox", inbox, "--exit-after-idle", "1000" }, { text = true, env = vim.tbl_extend("force", sb.env(root), { AISWARM_NO_FS_EVENTS = "1" }) })
    c1:wait(20000); c2:wait(20000)
    local bm2 = sb.json(sb.read(root .. "/control/consumers/orchestrator-main.json")); t:ok(bm2 and bm2.positions and bm2.positions.control.seq >= bm.positions.control.seq)
  end },
  -- ------------------------------------------------------------ SDD-087
  { id = "briefing.bounded_prioritized_with_refs", tasks = { "SDD-087" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "brief")
    run(t, root, "T-001", "failure")
    v3.cli_json(t, root, { "add", "--id", "T-002", "--dep", "T-001", "--title", "downstream" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "add", "--id", "T-003" }, { stdin = "x\n" })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    v3.cli_json(t, root, { "dispatch" }, { env = env_for("progress", { AISWARM_FAKE_PROGRESS = sb.plugin .. "/bin/aiswarm-progress", AISWARM_FAKE_BARRIER = barrier }) })
    wait_task(t, root, "T-003", terminal)
    local b = v3.cli_json(t, root, { "briefing" })
    t:match(b.text, "^T%-001 failed: exit 1; blocks T%-002"); t:match(b.text, "T%-002 blocked: blocked by T%-001 %(failed%)"); t:match(b.text, "T%-003 succeeded")
    t:eq(b.truncated, 0); t:ok(#b.refs >= 1)
    local snap = snapshot(t, root)
    for _, ref in ipairs(b.refs) do t:ok(attempt_of(snap, ref.task) ~= nil or ref.ref:match(":%d+$"), "reference resolvable: " .. tostring(ref.ref)) end
    local small = v3.cli_json(t, root, { "briefing", "--tasks", "1" })
    t:eq(small.truncated, 2); t:match(small.text, "2 more task%(s%) omitted")
    local unit = require("aiswarm.runtime.briefing").build({ tasks = { { id = "T-9", state = "running", display = "Running", current_attempt_id = "a" } }, control_seq = 1 },
      { { type = "agent.progress", task_id = "T-9", event_id = "a:1:5", payload = { message = "testing now" } } })
    t:match(unit.text, "T%-9 running: testing now"); t:eq(unit.refs[1].ref, "a:1:5")
  end },
}
