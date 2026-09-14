-- SDD-038 inventory, SDD-039 quiescence/backup, SDD-040 conversion, SDD-041 publish/resume/rollback, SDD-042 project views.
local sb = require("helpers.sandbox")
local v3 = require("helpers.v3")
local pl = require("helpers.plugin")

local function mods() local m = v3.mods(); m.MIG = require("aiswarm.runtime.migrate"); return m end
local function force_state(root, id, from, to, extra)
  local src = root .. "/tasks/" .. from .. "/" .. id .. ".json"
  local task = sb.json(sb.read(src)); task.state = to
  for k, v in pairs(extra or {}) do task[k] = v end
  sb.write(root .. "/tasks/" .. to .. "/" .. id .. ".json", vim.json.encode(task)); os.remove(src)
end
--- A legacy board with ready/done/failed/active(no session) tasks and real execution evidence.
local function fixture(t, name)
  local root = sb.legacy_board(t, name or "legacy")
  sb.legacy_add(t, root, { "--id", "T-001", "--title", "done one" }, "p1\n")
  sb.legacy_add(t, root, { "--id", "T-002", "--dep", "T-001" }, "p2\n")
  sb.legacy_add(t, root, { "--id", "T-003", "--dep", "MISSING" }, "p3\n")
  sb.legacy_add(t, root, { "--id", "T-004", "--provider", "codex" }, "p4\n")
  sb.legacy_add(t, root, { "--id", "T-005" }, "p5\n")
  force_state(root, "T-001", "ready", "active", { started_epoch = os.time(), started_at = "2026-01-01T00:00:00Z" })
  t:eq(sb.aiswarm(root, { "exec", "T-001" }, { timeout = 15000 }).code, 0)          -- mock: done with a real report
  force_state(root, "T-004", "ready", "active", { started_epoch = os.time(), started_at = "2026-01-01T00:00:00Z" })
  local dir = t:tmpdir("stub"); sb.write(dir .. "/codex", "#!/usr/bin/env bash\necho stub; exit 1\n"); vim.uv.fs_chmod(dir .. "/codex", 493)
  t:eq(sb.aiswarm(root, { "exec", "T-004" }, { env = { PATH = dir .. ":" .. vim.env.PATH }, timeout = 15000 }).code, 0) -- failed, synthesized report
  force_state(root, "T-005", "ready", "active", { started_epoch = os.time(), started_at = "2026-01-01T00:00:00Z", session = "agent-T-005" }) -- active, no session
  return root
end
local function migrate(t, root, extra)
  local r = v3.cli(root, vim.list_extend({ "migrate", "--json" }, extra or {}))
  return r, r.code == 0 and sb.json(r.stdout) or nil
end
local function kill_server(t) t:defer(function() sb.tmux({ "kill-server" }) end) end

return {
  { id = "migrate.dry_run_is_read_only", tasks = { "SDD-038" }, suites = { "core", "compatibility" }, run = function(t)
    local m = mods()
    local root = fixture(t)
    local before = m.MIG.checksums(root)
    local r = v3.cli(root, { "migrate", "--dry-run", "--json" }); t:eq(r.code, 0, r.stderr)
    local inv = sb.json(r.stdout)
    t:eq(m.MIG.checksums(root), before, "dry run changes no file")
    t:eq(inv.schema, "v2"); t:eq(inv.counts.ready, 2); t:eq(inv.counts.done, 1); t:eq(inv.counts.failed, 1); t:eq(inv.counts.active, 1)
    local texts = vim.tbl_map(function(f) return (f.task or "") .. ":" .. f.text end, inv.findings)
    t:ok(vim.tbl_contains(texts, "T-003:depends on unknown task MISSING (will show as blocked: missing dependency)"), vim.inspect(texts))
    t:ok(vim.iter(texts):any(function(x) return x:match("^T%-005:active task without a live session") end))
    t:eq(inv.blocking, 0)
    local human = v3.cli(root, { "migrate", "--dry-run" }); t:match(human.stdout, "ready to migrate")
    -- An unrelated board beside an explicit import root is not an identity conflict.
    local sibling = vim.fs.dirname(root) .. "/another-board"
    vim.fn.mkdir(sibling, "p")
    local inv2 = sb.json(v3.cli(root, { "migrate", "--dry-run", "--json" }).stdout)
    t:eq(inv2.blocking, inv.blocking)

  end },
  { id = "migrate.refuses_live_writer_and_scheduler", tasks = { "SDD-039" }, suites = { "core", "compatibility" }, run = function(t)
    kill_server(t)
    local root = fixture(t, "live")
    sb.tmux({ "new-session", "-d", "-s", "agent-T-005", "sleep 60" })
    local r = migrate(t, root); t:eq(r.code, 3); t:match(r.stderr, "live tmux session")
    sb.tmux({ "kill-session", "-t", "agent-T-005" })
    sb.tmux({ "new-session", "-d", "-s", "aiswarm", "sleep 60" })
    local r2 = migrate(t, root); t:eq(r2.code, 3); t:match(r2.stderr, "scheduler session")
    sb.tmux({ "kill-session", "-t", "aiswarm" })
    vim.fn.mkdir(root .. "/locks/dispatch.d", "p")
    local r3 = migrate(t, root); t:eq(r3.code, 3); t:match(r3.stderr, "legacy writer may be active")
    vim.fn.delete(root .. "/locks/dispatch.d", "d")
    t:ok(not sb.exists(root .. "/board.json"), "nothing published while blocked")
  end },
  { id = "migrate.backup_verified_and_failure_leaves_source", tasks = { "SDD-039" }, suites = { "core", "compatibility", "reliability" }, run = function(t)
    local m = mods()
    local root = fixture(t, "backup")
    local before = m.MIG.checksums(root)
    local r = migrate(t, root, { "--fault", "after_backup" }); t:eq(r.code, 1); t:match(r.stderr, "fault injected")
    t:eq(m.MIG.checksums(root), before, "source unchanged after a failed migration")
    local man = m.MIG.manifest(root); t:eq(man.phase, "failed")
    local ok = m.MIG.verify_backup(man.backup); t:ok(ok, "backup verifies")
    sb.write(man.backup .. "/tasks/prompts/T-001.md", "TAMPERED")
    local ok2, bad = m.MIG.verify_backup(man.backup); t:ok(not ok2); t:eq(bad, { "tasks/prompts/T-001.md" }, "corruption detected")
    t:ok(not sb.exists(root .. "/locks/migration.marker"), "marker removed after failure")
    -- a marker blocks compliant writers on a v3 board
    local vroot = v3.board(t, "marked")
    sb.write(vroot .. "/locks/migration.marker", '{"started_at":"now","pid":1}')
    local blocked = v3.cli(vroot, { "add" }, { stdin = "x\n" }); t:eq(blocked.code, 4); t:match(blocked.stderr, "being migrated")
  end },
  { id = "migrate.converts_evidence_without_inventing_history", tasks = { "SDD-040" }, suites = { "core", "compatibility" }, run = function(t)
    kill_server(t)
    local m = mods()
    local root = fixture(t, "convert")
    local report_sha = vim.fn.sha256(sb.read(root .. "/results/T-001.md"))
    local log_sha = vim.fn.sha256(sb.read(root .. "/logs/T-001.log"))
    local r, res = migrate(t, root); t:eq(r.code, 0, r.stderr); t:eq(res.phase, "completed")
    local snap = v3.cli_json(t, root, { "snapshot" })
    local by = {}; for _, x in ipairs(snap.tasks) do by[x.id] = x end
    t:eq(by["T-001"].state, "succeeded"); t:eq(by["T-002"].state, "queued"); t:eq(by["T-002"].display, "Queued", "upstream succeeded"); t:eq(by["T-003"].display, "Blocked")
    t:eq(by["T-003"].blockers[1].reason, "missing"); t:eq(by["T-004"].state, "failed"); t:eq(by["T-005"].state, "failed")
    t:eq(by["T-005"].outcome.reason, "orphaned_at_migration")
    local atts = {}; for _, a in ipairs(snap.attempts) do atts[a.task_id] = a end
    t:eq(atts["T-001"].imported.legacy, true); t:eq(atts["T-001"].imported.history, "unknown"); t:eq(atts["T-001"].ordinal, 1)
    t:eq(atts["T-001"].report.status, "complete"); t:eq(atts["T-004"].report.status, "synthesized")
    t:eq(atts["T-002"], nil, "no attempt invented for a task that never ran")
    t:eq(vim.fn.sha256(sb.read(atts["T-001"].paths.report)), report_sha, "report bytes preserved")
    t:eq(vim.fn.sha256(sb.read(atts["T-001"].paths.stdout)), log_sha, "log bytes preserved")
    t:eq(by["T-001"].imported.created_at_source, "task_record")
    t:eq(snap.scheduler.state, "stopped", "migration starts no scheduler")
    t:eq(sb.tmux({ "list-sessions" }).code ~= 0 or sb.tmux({ "list-sessions" }).stdout == "", true, "no worker/scheduler side effect")
    t:ok(sb.exists(root .. "/tasks/ready/T-002.json"), "raw v2 files remain in place")
    t:eq(sb.read(root .. "/prompts/T-002/r1.md"), "p2\n")
  end },
  { id = "migrate.interrupt_resume_and_rollback", tasks = { "SDD-041" }, suites = { "core", "compatibility", "reliability" }, run = function(t)
    local m = mods()
    for _, fault in ipairs({ "after_staging", "mid_publish", "before_manifest" }) do
      local root = fixture(t, "int-" .. fault)
      local before = m.MIG.checksums(root)
      local r = migrate(t, root, { "--fault", fault }); t:eq(r.code, 1, fault)
      local man = m.MIG.manifest(root)
      local v3_marker = sb.exists(root .. "/board.json")
      t:ok(not v3_marker or man.phase == "published", fault .. ": board.json only after publication")
      -- exactly one authoritative schema: either the v2 layout without board.json, or v3 with it
      local resumed = migrate(t, root, { "--resume" }); t:eq(resumed.code, 0, fault .. " resume: " .. resumed.stderr)
      t:eq(m.MIG.manifest(root).phase, "completed")
      t:ok(sb.exists(root .. "/board.json")); t:ok(not sb.exists(root .. "/locks/migration.marker"))
      t:eq(#v3.cli_json(t, root, { "snapshot" }).tasks, 5, fault .. ": all tasks present after resume")
      -- rollback before new work restores the original checksums
      local rb = migrate(t, root, { "--rollback" }); t:eq(rb.code, 0, rb.stderr)
      t:eq(m.MIG.checksums(root), before, fault .. ": rollback restores the v2 board byte for byte")
      t:ok(not sb.exists(root .. "/board.json"))
    end
    -- rollback after new v3 work refuses and explains
    local root = fixture(t, "newwork")
    t:eq(migrate(t, root).code, 0)
    v3.cli_json(t, root, { "add", "--id", "T-100" }, { stdin = "new work\n" })
    local rb = migrate(t, root, { "--rollback" }); t:eq(rb.code, 3); t:match(rb.stderr, "Export them first")
    t:ok(sb.exists(root .. "/board.json"), "v3 board kept")
    local forced = migrate(t, root, { "--rollback", "--force" }); t:eq(forced.code, 0)
    t:ok(not sb.exists(root .. "/board.json"))
    -- twice: a completed migration cannot be rerun onto a v3 board, and a second migrate after rollback works
    t:eq(migrate(t, root).code, 0, "migrate again after rollback")
    t:eq(migrate(t, root).code, 3)
  end },
  { id = "migrate.project_views_show_legacy_state", tasks = { "SDD-042" }, suites = { "core", "compatibility" }, run = function(t)
    if not pcall(require, "snacks") then t:skip("snacks.nvim not available") end
    local root = fixture(t, "views")
    local A = pl.setup(t, root); pl.refresh(t, A); pl.source_plugin()
    t:eq(require("aiswarm.project").schema(root), "v2")
    local U = require("aiswarm.legacy.ui")
    U.dashboard(); t:defer(function() if U._dash and U._dash.win:valid() then U._dash.win:close() end end)
    t:wait(2000, function() return U._dash ~= nil end)
    local lines = vim.api.nvim_buf_get_lines(U._dash.win.buf, 0, 3, false)
    t:match(lines[2], "legacy board %(v2%)"); t:match(lines[2], "migrate %-%-dry%-run")
    local seen = pl.capture_notify(function() vim.cmd("AISwarm cancel T-002") end)
    t:match(seen[1].msg, "not available yet")
    -- inventory view
    local mig = require("aiswarm.ui.migrate")
    vim.cmd("AISwarm migrate --dry-run")
    t:wait(10000, function() return mig.last_buf ~= nil and vim.api.nvim_buf_is_valid(mig.last_buf) end, "inventory buffer opens")
    local inv = table.concat(vim.api.nvim_buf_get_lines(mig.last_buf, 0, -1, false), "\n")
    t:match(inv, "legacy board"); t:match(inv, "read%-only inventory")
    -- interrupted upgrade shows recovery state instead of an empty queue
    migrate(t, root, { "--fault", "before_manifest" })
    t:eq(require("aiswarm.project").schema(root), "migrating")
    U.render()
    lines = vim.api.nvim_buf_get_lines(U._dash.win.buf, 0, 3, false)
    t:match(lines[2], "interrupted migration")
    -- explicit upgrade through the editor, no scheduler start
    vim.cmd("AISwarm migrate --resume")
    t:wait(15000, function() return require("aiswarm.project").schema(root) == "v3" and require("aiswarm.project").current and require("aiswarm.project").current.schema == "v3" end, "board reopened as v3")
    local snap = v3.cli_json(t, root, { "snapshot" }); t:eq(snap.scheduler.state, "stopped")
  end },
}
