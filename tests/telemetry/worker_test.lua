-- SDD-069 worker bootstrap, SDD-070 raw capture, SDD-071 outcomes, SDD-072 heartbeats, SDD-073 telemetry
-- journal, SDD-074 normalization, SDD-075 inbox, SDD-076 worker context, SDD-077 activity projection.
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
local function records(path)
  local out = {}
  for line in (sb.read(path) or ""):gmatch("[^\n]+") do local r = sb.json(line); if r then out[#out + 1] = r end end
  return out
end
local function run(t, root, id, scenario, extra, opts)
  v3.cli_json(t, root, { "add", "--id", id }, { stdin = (opts and opts.prompt) or "x\n" })
  local d = v3.cli_json(t, root, { "dispatch" }, { env = env_for(scenario, extra) })
  t:ok(#d.dispatched == 1, "dispatched: " .. vim.inspect(d))
  return wait_task(t, root, id, terminal), attempt_of(snapshot(t, root), id)
end

return {
  -- ------------------------------------------------------------ SDD-069
  { id = "worker.never_loads_user_config", tasks = { "SDD-069" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local cfg = vim.env.XDG_CONFIG_HOME .. "/nvim"
    local marker = t:tmpdir("poison") .. "/touched"
    sb.write(cfg .. "/init.lua", ("local f = io.open(%q, 'a'); f:write('init'); f:close()\n"):format(marker))
    sb.write(cfg .. "/plugin/poison.lua", ("local f = io.open(%q, 'a'); f:write('plugin'); f:close()\n"):format(marker))
    sb.write(vim.env.XDG_STATE_HOME .. "/nvim/shada/main.shada", "poison")
    t:defer(function() vim.fn.delete(cfg, "rf") end)
    local root = v3.board(t, "poison")
    local task, attempt = run(t, root, "T-001", "success")
    t:eq(task.state, "succeeded"); t:ok(not sb.exists(marker), "sentinel init/plugin never executed by the worker or the scheduler runtime")
    t:ok(sb.exists(attempt.paths.report), "worker ran inside tmux without any editor")
  end },
  { id = "worker.paths_with_spaces", tasks = { "SDD-069" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local base = t:tmpdir("spaced") .. "/dir with spaces"
    vim.fn.mkdir(base, "p")
    local root = base .. "/.aiswarm"
    v3.mods().B.init(root)
    local task, attempt = run(t, root, "T-001", "success")
    t:eq(task.state, "succeeded"); t:eq(attempt.report.status, "complete")
    t:match(attempt.paths.stdout, "dir with spaces")
  end },
  { id = "worker.missing_runtime_is_environment_error", tasks = { "SDD-069" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "nonvim")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local d = v3.cli_json(t, root, { "dispatch" }, { env = { AISWARM_NVIM = "/nonexistent/nvim" } })
    t:eq(#d.failed, 1); t:match(d.failed[1].reason, "Neovim runtime not found")
    t:eq(snapshot(t, root).counts.running, 0, "no phantom running task")
  end },
  -- ------------------------------------------------------------ SDD-070
  { id = "capture.byte_streams_reconstructed_with_exact_offsets", tasks = { "SDD-070" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "cap")
    local _, a = run(t, root, "T-001", "interleaved")
    t:eq(sb.read(a.paths.stdout), "out 1\nout 2\nout 3\nout 4\nout 5\n"); t:eq(sb.read(a.paths.stderr), "err 1\nerr 2\nerr 3\nerr 4\nerr 5\n")
    local next_off = { stdout = 0, stderr = 0 }
    local n = 0
    for _, r in ipairs(records(a.paths.telemetry)) do
      if r.type == "agent.output" then
        n = n + 1
        t:eq(r.payload.offset, next_off[r.payload.stream], "offsets are contiguous per stream"); next_off[r.payload.stream] = r.payload.offset + r.payload.bytes
        local seg = sb.read(a.paths.dir .. ("/%s.%06d.log"):format(r.payload.stream, r.payload.segment))
        t:ok(#seg >= r.payload.offset + r.payload.bytes, "offset range references flushed bytes")
      end
    end
    t:eq(next_off.stdout, 30); t:eq(next_off.stderr, 30); t:ok(n >= 2)
    local _, b = run(t, root, "T-002", "partial-utf8")
    t:ok(sb.read(b.paths.stdout):find("café ok\n日本語 テスト\n🚀 launch\ne\204\129 combining\n", 1, true), "split multibyte output reconstructed exactly")
  end },
  { id = "capture.output_before_exit_and_flood_does_not_block", tasks = { "SDD-070", "SDD-085" }, suites = { "core", "performance" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "flood")
    local barrier = vim.fs.dirname(root) .. "/barrier"
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "dispatch" }, { env = env_for("grandchild-hold", { AISWARM_FAKE_BARRIER = barrier }) })
    local a
    t:wait(10000, function() a = attempt_of(snapshot(t, root), "T-001"); return a and a.state == "running" and #records(a.paths.telemetry) > 0 end)
    t:wait(5000, function() for _, r in ipairs(records(a.paths.telemetry)) do if r.type == "agent.output" then return true end end return false end, "output records arrive while the provider runs")
    sb.write(barrier, "go"); wait_task(t, root, "T-001", terminal)
    local started = uv.hrtime()
    local _, f = run(t, root, "T-002", "flood", { AISWARM_FAKE_LINES = "40000", AISWARM_MAX_QUEUE_BYTES = "65536" })
    local ms = (uv.hrtime() - started) / 1e6
    local size = uv.fs_stat(f.paths.stdout).size
    t:ok(size > 0 and ms < 30000, ("flood captured (%d bytes) without stalling supervision: %.0f ms"):format(size, ms))
    local telemetry = records(f.paths.telemetry)
    t:ok(#telemetry < 2000, "records batched, not one per line: " .. #telemetry)
    local hb = 0; for _, r in ipairs(telemetry) do if r.type == "agent.heartbeat" then hb = hb + 1 end end
    t:ok(hb >= 1, "heartbeats kept flowing during the flood")
  end },
  -- ------------------------------------------------------------ SDD-071
  { id = "outcome.collector_failure_not_misreported", tasks = { "SDD-071", "SDD-085" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "coll")
    local task, a = run(t, root, "T-001", "flood", { AISWARM_FAULT_LOG_WRITES = "2", AISWARM_FAKE_LINES = "3000", AISWARM_FLUSH_MS = "5" })
    t:eq(task.state, "succeeded", "storage failure of the collector is not the provider's exit")
    local warn, gap = false, false
    for _, r in ipairs(records(a.paths.telemetry)) do
      if r.type == "telemetry.warning" and r.payload.message:match("degraded") then warn = true end
      if r.type == "stream.gap" and r.payload.reason == "storage" and (r.payload.discarded_bytes or 0) > 0 then gap = true end
    end
    if not (warn and gap) then t:log("types", vim.tbl_map(function(r) return r.type .. ":" .. vim.inspect(r.payload):sub(1, 80) end, records(a.paths.telemetry))) end
    t:ok(warn, "degraded capture reported"); t:ok(gap, "recovery persisted a gap with discarded byte count")
  end },
  { id = "outcome.late_callback_cannot_revive_cancelled", tasks = { "SDD-071", "SDD-032" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "late")
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    local env = env_for("unresponsive")
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    t:wait(10000, function() local a = attempt_of(snapshot(t, root), "T-001"); return a and a.worker ~= nil end)
    local r = v3.cli_json(t, root, { "cancel", "T-001", "--grace", "1" }, { env = env, timeout = 30000 })
    t:eq(r.attempt.state, "cancelled")
    vim.wait(2000)  -- the worker's own finish arrives late
    local snap = snapshot(t, root)
    t:eq(task_of(snap, "T-001").state, "cancelled"); t:eq(attempt_of(snap, "T-001").state, "cancelled")
    local finishes = 0
    for _, rec in ipairs(v3.journal_records(root)) do if rec.type == "attempt.finished" then finishes = finishes + 1 end end
    t:eq(finishes, 1)
  end },
  -- ------------------------------------------------------------ SDD-072
  { id = "heartbeat.independent_of_output_and_stops_after_exit", tasks = { "SDD-072" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "hb")
    local barrier = vim.fs.dirname(root) .. "/barrier"
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "dispatch" }, { env = env_for("quiet", { AISWARM_FAKE_BARRIER = barrier }) })
    local a
    local function beats() local n = 0; for _, r in ipairs(records(a.paths.telemetry)) do if r.type == "agent.heartbeat" and not r.payload.final then n = n + 1 end end return n end
    t:wait(10000, function() a = attempt_of(snapshot(t, root), "T-001"); return a and a.paths and beats() >= 4 end, "quiet process emits heartbeats")
    local act = sb.json(sb.read(a.paths.activity))
    t:ok(act.heartbeat_at and not act.output_at, "heartbeat health is separate from last output")
    sb.write(barrier, "go"); wait_task(t, root, "T-001", terminal)
    local after = beats(); vim.wait(400); t:eq(beats(), after, "stopped worker emits no future heartbeats")
    t:ok(sb.exists(a.paths.dir .. "/telemetry.owner.json") == false, "writer ownership released")
  end },
  -- ------------------------------------------------------------ SDD-073
  { id = "journal.ten_attempts_attributed_and_ordered", tasks = { "SDD-073" }, suites = { "core", "reliability", "performance" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "ten", { wip = 10 })
    local barrier = vim.fs.dirname(root) .. "/barrier"
    for i = 1, 10 do v3.cli_json(t, root, { "add", "--id", ("T-%03d"):format(i) }, { stdin = "x\n" }) end
    local env = env_for("quiet", { AISWARM_FAKE_BARRIER = barrier, AISWARM_HEARTBEAT_MS = "50" })
    local d = v3.cli_json(t, root, { "dispatch" }, { env = env }); t:log("dispatch", d); t:eq(#d.dispatched, 10, vim.inspect(d))
    local ok10 = vim.wait(30000, function() local s = snapshot(t, root); local n = 0; for _, a in ipairs(s.attempts) do if a.state == "running" then n = n + 1 end end return n == 10 end, 200)
    if not ok10 then t:log("states", vim.tbl_map(function(a) return a.task_id .. ":" .. a.state .. ":" .. tostring(a.reason) end, snapshot(t, root).attempts)); t:fail("ten attempts running") end
    -- control mutation stays responsive under telemetry flood
    local started = uv.hrtime(); v3.cli_json(t, root, { "add", "--id", "T-011" }, { stdin = "x\n" })
    t:ok((uv.hrtime() - started) / 1e6 < 3000, "add under load is quick")
    vim.wait(600)
    for _, a in ipairs(snapshot(t, root).attempts) do
      if a.task_id ~= "T-011" then
        local recs = records(a.paths.telemetry); local last = 0
        for _, r in ipairs(recs) do t:eq(r.attempt_id, a.attempt_id); t:eq(r.task_id, a.task_id); t:ok(r.attempt_seq > last, "monotonic seq"); last = r.attempt_seq end
        t:ok(#recs >= 3, "records per attempt")
      end
    end
    sb.write(barrier, "go")
    for i = 1, 10 do wait_task(t, root, ("T-%03d"):format(i), terminal) end
  end },
  { id = "journal.single_writer_and_generation_on_restart", tasks = { "SDD-073" }, suites = { "core" }, run = function(t)
    local m = v3.mods()
    local root, ctx = v3.board(t, "writer")
    local Writer = require("aiswarm.runtime.telemetry")
    local attempt = { attempt_id = m.U.uuid(), task_id = "T-001", paths = m.O.attempt_paths(ctx, m.U.uuid()) }
    attempt.paths = m.O.attempt_paths(ctx, attempt.attempt_id)
    local w1 = assert(Writer.open(ctx, attempt))
    local w2, err = Writer.open(ctx, attempt); t:eq(w2, nil); t:match(err, "already owned")
    w1:emit("agent.progress", { message = "one" }); w1:emit("agent.heartbeat", { pid = 1 }, { level = "debug" }); w1:close()
    local w3 = assert(Writer.open(ctx, attempt)); w3:emit("agent.progress", { message = "two" }); w3:close()
    local recs = records(attempt.paths.telemetry)
    local ids = {}; for _, r in ipairs(recs) do t:ok(not ids[r.event_id], "event id unique across restarts: " .. r.event_id); ids[r.event_id] = true end
    t:eq(recs[3].stream_generation, "2"); t:eq(recs[3].attempt_seq, 1)
  end },
  -- ------------------------------------------------------------ SDD-074
  { id = "normalize.utf8_lines_previews_and_oversize", tasks = { "SDD-074" }, suites = { "core" }, run = function(t)
    local N = require("aiswarm.runtime.normalize")
    local p = N.new({ max_line = 64 })
    t:eq(p:feed("caf\195"), {}); t:eq(p:feed("\169 ok\n日本"), { "café ok" }); t:eq(p:feed("語\n"), { "日本語" })
    local big = p:feed(("x"):rep(100) .. "\n"); t:eq(#big[1], 64); t:eq(p.oversized, 1)
    t:eq(p:feed("tail"), {}); t:eq(p:finish(), { "tail" })
    t:eq(N.preview("\27]0;evil\7\27[31mred\27[0m plain\r\n", 100), "red plain\n")
    local pv = N.preview("日本語テスト", 8); t:ok(#pv <= 11 and not pv:find("\226\128\166", 12), "preview cut on a character boundary: " .. pv)
    local adapter = { parse_line = function(line) if line:match("^{") then local ok, r = pcall(vim.json.decode, line); if not ok then error("bad json") end return { type = "agent.progress", payload = { message = r.msg } } end return nil end }
    local q = N.new({ adapter = adapter })
    t:eq(q:native('{"msg":"hi"}').payload.message, "hi")
    t:eq(q:native("plain text"), nil, "unknown output stays raw")
    local rec, diag = q:native("{not json"); t:eq(rec, nil); t:match(diag.message, "adapter parse error")
  end },
  { id = "normalize.worker_never_invents_structure", tasks = { "SDD-074" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "norm")
    local task, a = run(t, root, "T-001", "control-sequences")
    t:eq(task.state, "succeeded")
    local act = sb.json(sb.read(a.paths.activity))
    t:eq(act.phase, nil, "no phase invented from raw output"); t:eq(act.input_required, nil); t:eq(act.usage, nil)
    for _, r in ipairs(records(a.paths.telemetry)) do
      if r.type == "agent.output" then t:ok(not r.payload.preview:find("\27", 1, true), "preview sanitized"); t:ok(#vim.json.encode(r) <= 65536) end
    end
    t:ok(sb.read(a.paths.stdout):find("\27]0;evil title\7", 1, true), "raw bytes preserved on disk")
  end },
  -- ------------------------------------------------------------ SDD-075
  { id = "inbox.concurrent_accepted_partial_ignored_bad_rejected", tasks = { "SDD-075" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "inbox")
    local barrier = vim.fs.dirname(root) .. "/barrier"
    v3.cli_json(t, root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    v3.cli_json(t, root, { "dispatch" }, { env = env_for("quiet", { AISWARM_FAKE_BARRIER = barrier }) })
    local a
    t:wait(10000, function() a = attempt_of(snapshot(t, root), "T-001"); return a and a.worker ~= nil end)
    local helper = sb.plugin .. "/bin/aiswarm-progress"
    local jobs = {}
    local env = { PATH = vim.env.PATH, AISWARM_ROOT = root, AISWARM_TASK = "T-001", AISWARM_ATTEMPT = a.attempt_id, AISWARM_BOARD_ID = snapshot(t, root).board_id }
    for i = 1, 6 do jobs[i] = vim.system({ helper, "--phase", "editing", "--message", "step " .. i }, { env = env }) end
    for _, j in ipairs(jobs) do t:eq(j:wait(5000).code, 0) end
    -- partial spool file, mismatched attempt, reserved-key override, duplicate message id
    sb.write(a.paths.inbox .. "/.partial.tmp", '{"message_id":"partial"')
    local bad = { message_id = "bad-attempt", board_id = env.AISWARM_BOARD_ID, task_id = "T-001", attempt_id = "00000000-0000-4000-8000-000000000009", type = "agent.progress", payload = { message = "x" } }
    sb.write(a.paths.inbox .. "/bad-attempt.json", vim.json.encode(bad))
    local reserved = vim.tbl_extend("force", bad, { message_id = "reserved", attempt_id = a.attempt_id, payload = { message = "x", attempt_seq = 999 } })
    sb.write(a.paths.inbox .. "/reserved.json", vim.json.encode(reserved))
    local dup = vim.tbl_extend("force", bad, { message_id = "dup", attempt_id = a.attempt_id, payload = { message = "dup" } })
    sb.write(a.paths.inbox .. "/dup.json", vim.json.encode(dup)); vim.wait(400)
    sb.write(a.paths.inbox .. "/dup-again.json", vim.json.encode(dup))
    local ok = vim.wait(5000, function() local n = 0; for _, r in ipairs(records(a.paths.telemetry)) do if r.type == "agent.progress" then n = n + 1 end end return n >= 7 end, 50)
    if not ok then
      t:log("inbox listing", vim.tbl_map(function(e) return e.name end, require("aiswarm.runtime.util").list(a.paths.inbox)))
      t:log("telemetry types", vim.tbl_map(function(r) return r.type .. ":" .. tostring(r.payload.message) end, records(a.paths.telemetry)))
      t:fail("accepted messages became records")
    end
    vim.wait(500)
    local progress, warnings, dups = {}, 0, 0
    for _, r in ipairs(records(a.paths.telemetry)) do
      if r.type == "agent.progress" then progress[#progress + 1] = r; if r.payload.message == "dup" then dups = dups + 1 end end
      if r.type == "telemetry.warning" and r.payload.message:match("rejected inbox") then warnings = warnings + 1 end
    end
    t:eq(#progress, 7, "6 concurrent + 1 dup accepted once"); t:eq(dups, 1); t:eq(warnings, 2, "mismatched attempt and reserved key rejected with diagnostics")
    t:ok(sb.exists(a.paths.inbox .. "/.partial.tmp"), "partial spool file ignored")
    local seqs = {}; for _, r in ipairs(records(a.paths.telemetry)) do seqs[#seqs + 1] = r.attempt_seq end
    for i = 2, #seqs do t:ok(seqs[i] > seqs[i - 1], "single-writer sequence") end
    local act = sb.json(sb.read(a.paths.activity)); t:eq(act.provenance, "worker_report"); t:eq(act.phase, "editing")
    sb.write(barrier, "go"); wait_task(t, root, "T-001", terminal)
    local ev = v3.cli_json(t, root, { "report-event", "--task", "T-001", "--attempt", a.attempt_id, "--path", "src/x.lua" })
    t:eq(ev.accepted, true, "report-event CLI spools an artifact message")
  end },
  -- ------------------------------------------------------------ SDD-076
  { id = "context.rendered_prompt_points_into_attempt", tasks = { "SDD-076" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "ctx")
    local up = run(t, root, "T-001", "success")
    v3.cli_json(t, root, { "add", "--id", "T-002", "--dep", "T-001" }, { stdin = "downstream\n" })
    v3.cli_json(t, root, { "dispatch" }, { env = env_for("progress", { AISWARM_FAKE_PROGRESS = sb.plugin .. "/bin/aiswarm-progress" }) })
    local task = wait_task(t, root, "T-002", terminal)
    local a = attempt_of(snapshot(t, root), "T-002")
    local prompt = sb.read(a.paths.prompt)
    t:ok(prompt:find('worker agent "T-002" (attempt 1, id ' .. a.attempt_id, 1, true), "identity in the rendered prompt")
    t:ok(prompt:find(a.paths.report, 1, true), "exact attempt report path"); t:ok(prompt:find("bin/aiswarm%-progress"), "absolute progress helper")
    t:ok(prompt:find("### T%-001 %(attempt 1, succeeded%)"), "dependency report included"); t:ok(prompt:find("fake success", 1, true))
    t:ok(prompt:find("<mission>") and prompt:find("<interfaces>") and prompt:find("<decisions>"))
    t:ok(prompt:find("recorded as your report, not as an independently verified fact", 1, true), "provenance rule stated")
    local act = sb.json(sb.read(a.paths.activity)); t:eq(act.phase, "testing"); t:eq(act.message, "Running focused tests")
    t:eq(task.state, "succeeded")
  end },
  { id = "context.helper_from_worktree_and_generic_fallback", tasks = { "SDD-076" }, suites = { "core" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "wt")
    local base = vim.fs.dirname(root)
    local genv = { PATH = vim.env.PATH, HOME = vim.env.HOME, GIT_AUTHOR_NAME = "t", GIT_AUTHOR_EMAIL = "t@x", GIT_COMMITTER_NAME = "t", GIT_COMMITTER_EMAIL = "t@x" }
    sb.run({ "git", "init", "-q", base }, { env = genv }); sb.write(base .. "/README", "x"); sb.run({ "git", "-C", base, "add", "." }, { env = genv }); sb.run({ "git", "-C", base, "commit", "-q", "-m", "i" }, { env = genv })
    local wts = t:tmpdir("wts")
    local env = env_for("progress", { AISWARM_WORKTREES = wts, AISWARM_FAKE_PROGRESS = sb.plugin .. "/bin/aiswarm-progress" })
    v3.cli_json(t, root, { "add", "--id", "T-001", "--isolation", "worktree" }, { stdin = "x\n", env = env })
    v3.cli_json(t, root, { "dispatch" }, { env = env })
    wait_task(t, root, "T-001", terminal)
    local a = attempt_of(snapshot(t, root), "T-001")
    t:eq(a.config.cwd, wts .. "/T-001"); t:eq(sb.json(sb.read(a.paths.activity)).phase, "testing", "helper called from the worktree")
    -- a provider that ignores the instructions still yields heartbeat and output
    local _, b = run(t, root, "T-002", "success")
    local kinds = {}; for _, r in ipairs(records(b.paths.telemetry)) do kinds[r.type] = true end
    t:ok(kinds["agent.heartbeat"] and kinds["agent.output"], "generic telemetry without cooperation"); t:eq(sb.json(sb.read(b.paths.activity)).phase, nil)
  end },
  -- ------------------------------------------------------------ SDD-077
  { id = "activity.projection_recovered_and_aged", tasks = { "SDD-077" }, suites = { "core", "reliability" }, run = function(t)
    kill_server(t)
    local root = v3.board(t, "proj")
    local _, a = run(t, root, "T-001", "progress", { AISWARM_FAKE_PROGRESS = sb.plugin .. "/bin/aiswarm-progress" })
    local before = sb.json(sb.read(a.paths.activity))
    t:eq(before.message, "Running focused tests")
    -- crash between append and projection replacement: the projection is stale/missing
    os.remove(a.paths.activity)
    local out = v3.cli(root, { "stream", "--once" }); t:eq(out.code, 0, out.stderr)
    local snap
    for line in out.stdout:gmatch("[^\n]+") do local fr = sb.json(line); if fr and fr.frame == "snapshot" then snap = fr end end
    local act = snap.activity[a.attempt_id]
    t:eq(act.message, "Running focused tests", "rebuilt from the journal"); t:eq(act.rebuilt, true); t:eq(act.checkpoint.attempt_seq, before.checkpoint.attempt_seq)
    t:ok(act.activity_at, "age of the prior progress is available to a fresh editor")
    -- heartbeats never overwrite meaningful progress
    local Writer = require("aiswarm.runtime.telemetry")
    local w = setmetatable({ activity = { message = "keep", phase = "testing" }, generation = "1", seq = 0 }, Writer)
    w:touch({ type = "agent.heartbeat", observed_at = "2026-09-14T00:00:00Z", payload = {} })
    t:eq(w.activity.message, "keep"); t:eq(w.activity.phase, "testing"); t:eq(w.activity.heartbeat_at, "2026-09-14T00:00:00Z")
    -- an old attempt's projection is its own file; the current attempt's is untouched
    v3.cli_json(t, root, { "retry", "T-001" })
    v3.cli_json(t, root, { "dispatch" }, { env = env_for("success") })
    wait_task(t, root, "T-001", terminal)
    local b = attempt_of(snapshot(t, root), "T-001")
    for _, x in ipairs(snapshot(t, root).attempts) do if x.task_id == "T-001" and x.ordinal == 2 then b = x end end
    t:neq(b.paths.activity, a.paths.activity); t:eq(sb.json(sb.read(b.paths.activity)).phase, nil)
  end },
}
