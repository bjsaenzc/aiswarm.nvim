-- SDD-002: characterization of the legacy `hive` (v2) backend. Cases named
-- legacy.quirk.* document audited defects as CURRENT behavior; they are not
-- v3 acceptance tests and must be rewritten when the owning v3 task lands.
local sb = require("helpers.sandbox")

local function snapshot(t, root)
  local r = sb.hive(root, { "json" })
  t:eq(r.code, 0, r.stderr)
  local snap = sb.json(r.stdout)
  t:ok(snap, "snapshot decodes")
  return snap
end
local function events(t, root)
  local r = sb.hive(root, { "events" })
  t:eq(r.code, 0, r.stderr)
  local out = {}
  for line in r.stdout:gmatch("[^\n]+") do out[#out + 1] = sb.json(line) end
  return out
end
--- Simulate dispatch the way the audit did: move the task file into active.
local function force_active(root, id)
  local src, dst = root .. "/tasks/ready/" .. id .. ".json", root .. "/tasks/active/" .. id .. ".json"
  local task = sb.json(sb.read(src)); task.state = "active"; task.started_epoch = os.time(); task.started_at = "2026-01-01T00:00:00Z"
  sb.write(dst, vim.json.encode(task)); os.remove(src)
end
--- A stub provider named like a real CLI, reachable only through a private PATH.
local function stub_provider(t, name, body)
  local dir = t:tmpdir("stub-" .. name)
  sb.write(dir .. "/" .. name, "#!/usr/bin/env bash\n" .. body .. "\n")
  vim.uv.fs_chmod(dir .. "/" .. name, 493)
  return dir .. ":" .. vim.env.PATH
end

return {
  { id = "legacy.cli.version_and_doctor", tasks = { "SDD-002" }, suites = { "core", "legacy", "compatibility" }, run = function(t)
    local root = t:tmpdir("nb") .. "/.hive"
    local v = sb.hive(root, { "--version" }); t:eq(v.code, 0); t:match(v.stdout, "2%.1%.0") -- the launcher is now aiswarm; v2 compatibility version stays visible
    local d = sb.hive(root, { "doctor", "--json" }); t:eq(d.code, 0)
    local doc = sb.json(d.stdout)
    t:eq(doc.api_version, 2); t:eq(doc.capabilities.atomic_add, true); t:eq(doc.locking, "mkdir"); t:eq(doc.blackboard, false)
  end },
  { id = "legacy.cli.snapshot_api_v2_shape", tasks = { "SDD-002" }, suites = { "core", "legacy", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    local id = sb.legacy_add(t, root, { "--id", "T-001", "--title", "first" }, "hello\n")
    t:eq(id, "T-001")
    local snap = snapshot(t, root)
    t:eq(snap.api_version, 2); t:eq(snap.capabilities.atomic_add, true); t:eq(snap.paused, false)
    t:eq(snap.counts.ready, 1); t:eq(#snap.tasks, 1); t:eq(snap.seq, 1)
    local task = snap.tasks[1]
    t:eq(task.id, "T-001"); t:eq(task.state, "ready"); t:eq(task.provider, "mock"); t:eq(task.priority, 50)
    t:eq(task.timeout, 1800); t:eq(task.worktree, false); t:eq(task.live, false); t:eq(task.prompt, root .. "/tasks/prompts/T-001.md")
    t:eq(snap.tasks[1].mode, "headless", "mode is stored (and unused)")
  end },
  { id = "legacy.cli.auto_id_and_duplicate_conflict", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    t:eq(sb.legacy_add(t, root, {}, "a\n"), "T-001")
    t:eq(sb.legacy_add(t, root, {}, "b\n"), "T-002")
    local dup = sb.hive(root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    t:eq(dup.code, 3, "duplicate id is a conflict (exit 3)"); t:match(dup.stderr, "already exists")
    t:eq(snapshot(t, root).tasks[1].title, "a", "title defaults to the first prompt line")
  end },
  { id = "legacy.cli.events_since_and_journal_order", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, {}, "a\n"); sb.legacy_add(t, root, {}, "b\n")
    local ev = events(t, root)
    t:eq(#ev, 2); t:eq(ev[1].seq, 1); t:eq(ev[2].seq, 2); t:eq(ev[2].type, "queued"); t:eq(ev[2].task, "T-002")
    local since = sb.hive(root, { "events", "--since", "1" }); t:eq(select(2, since.stdout:gsub("\n", "")), 1)
    t:eq(vim.trim(sb.read(root .. "/seq")), "2")
  end },
  { id = "legacy.cli.pause_resume_and_exit_codes", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    t:eq(sb.hive(root, { "pause" }).code, 0); t:eq(snapshot(t, root).paused, true)
    t:eq(sb.hive(root, { "resume" }).code, 0); t:eq(snapshot(t, root).paused, false)
    t:eq(sb.hive(root, { "show", "NOPE" }).code, 2, "not found is exit 2")
    t:eq(sb.hive(root, { "kill", "NOPE" }).code, 3, "wrong state is exit 3 (validated id)")
    t:eq(sb.hive(t:tmpdir("nb") .. "/.hive", { "json" }).code, 4, "missing board is exit 4")
  end },
  { id = "legacy.cli.mock_exec_lifecycle", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001" }, "mock me\n")
    force_active(root, "T-001")
    local r = sb.hive(root, { "exec", "T-001" }, { timeout = 15000 })
    t:eq(r.code, 0, r.stderr)
    local snap = snapshot(t, root)
    t:eq(snap.tasks[1].state, "done"); t:eq(snap.tasks[1].rc, 0); t:eq(snap.tasks[1].cost_usd, nil, "cost is null, not zero")
    t:ok(sb.exists(root .. "/results/T-001.md")); t:ok(sb.exists(root .. "/logs/T-001.log"))
    local types = vim.tbl_map(function(e) return e.type end, events(t, root))
    t:eq(types, { "queued", "started", "done" })
  end },
  { id = "legacy.quirk.no_automatic_progress", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001" }, "mock me\n"); force_active(root, "T-001")
    sb.hive(root, { "exec", "T-001" }, { timeout = 15000 })
    for _, e in ipairs(events(t, root)) do t:neq(e.type, "progress", "legacy runner emits no automatic progress") end
    t:log("LEGACY QUIRK A07: no heartbeat/progress without an explicit `hive progress` call")
  end },
  { id = "legacy.quirk.kill_requeues", tasks = { "SDD-002" }, suites = { "core", "legacy", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001" }, "x\n"); force_active(root, "T-001")
    local r = sb.hive(root, { "kill", "T-001" }); t:eq(r.code, 0, r.stderr)
    local task = snapshot(t, root).tasks[1]
    t:eq(task.state, "ready", "LEGACY QUIRK A08: kill returns the task to the queue"); t:eq(task.rc, nil); t:eq(task.session, nil)
    local ev = events(t, root); t:eq(ev[#ev].type, "cancelled")
  end },
  { id = "legacy.quirk.stale_report_after_rerun", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001", "--provider", "codex" }, "x\n")
    sb.write(root .. "/results/T-001.md", "STALE PRIOR ATTEMPT\n")
    force_active(root, "T-001")
    local path = stub_provider(t, "codex", 'echo "stub codex ran"; exit 0')
    local r = sb.hive(root, { "exec", "T-001" }, { env = { PATH = path }, timeout = 15000 })
    t:eq(r.code, 0, r.stderr)
    t:eq(snapshot(t, root).tasks[1].state, "done")
    t:eq(sb.read(root .. "/results/T-001.md"), "STALE PRIOR ATTEMPT\n", "LEGACY QUIRK A09: predecessor report is kept as this run's report")
  end },
  { id = "legacy.quirk.missing_dependency_accepted", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001", "--dep", "MISSING" }, "x\n")
    t:eq(snapshot(t, root).tasks[1].depends_on, { "MISSING" }, "LEGACY QUIRK A12: unknown dependency accepted, task waits forever")
  end },
  { id = "legacy.quirk.move_first_negative_priority", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001", "--priority", "0" }, "x\n"); sb.legacy_add(t, root, { "--id", "T-002" }, "y\n")
    t:eq(sb.hive(root, { "move", "T-002", "--first" }).code, 0)
    local snap = snapshot(t, root)
    for _, task in ipairs(snap.tasks) do if task.id == "T-002" then t:eq(task.priority, -1, "LEGACY QUIRK A23: move-first produces -1") end end
  end },
  { id = "legacy.quirk.set_accepts_invalid_values", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001" }, "x\n")
    t:eq(sb.hive(root, { "set", "T-001", "provider=not-a-provider", "timeout=-1" }).code, 0)
    local task = snapshot(t, root).tasks[1]
    t:eq(task.provider, "not-a-provider", "LEGACY QUIRK A22: set skips creation validation"); t:eq(task.timeout, -1)
  end },
  { id = "legacy.quirk.session_name_is_global", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local src = sb.read(sb.bin("aiswarm"))
    t:ok(src:find('tmux new-session -d -s "agent-$id"', 1, true), "LEGACY QUIRK A10: sessions are agent-<id> on the whole tmux server")
    t:ok(src:find("grep '^agent-'", 1, true), "LEGACY QUIRK A10: down/gc scan every agent-* session")
  end },
}
