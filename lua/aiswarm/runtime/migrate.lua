-- Legacy (v2) board migration: inventory, quiescence, backup, conversion, staged publication,
-- resume and rollback (SDD-038–041).
local uv = vim.uv
local U = require("aiswarm.runtime.util")
local B = require("aiswarm.runtime.board")
local P = require("aiswarm.protocol")
local T = require("aiswarm.runtime.tmux")
local J = require("aiswarm.runtime.journal")
local R = require("aiswarm.runtime.reducer")
local M = {}
local fail = B.fail

local STATES = { "ready", "active", "done", "failed" }

local function is_v2(root) return U.is_dir(root .. "/tasks/ready") and not U.exists(root .. "/board.json") end
local function manifest_path(root) return root .. "/migration/manifest.json" end
local function marker_path(root) return root .. "/locks/migration.marker" end

-- ---------------------------------------------------------------- hashing
local function sha(path)
  local data = U.read(path)
  if data == nil then return nil end
  return vim.fn.sha256(data)
end
--- Relative file list (excluding migration/ and locks/) with sha256 + size.
function M.checksums(root)
  local out = {}
  local function walk(dir, rel)
    for _, e in ipairs(U.list(dir)) do
      local r = rel == "" and e.name or (rel .. "/" .. e.name)
      if not (rel == "" and (e.name == "migration" or e.name == "locks")) then
        if e.type == "directory" then walk(dir .. "/" .. e.name, r)
        else
          local st = uv.fs_stat(dir .. "/" .. e.name)
          out[r] = { sha256 = sha(dir .. "/" .. e.name), size = st and st.size or 0, mtime = st and st.mtime.sec or 0 }
        end
      end
    end
  end
  walk(root, "")
  return out
end

-- ---------------------------------------------------------------- inventory (SDD-038)
local function read_events(root)
  local out = {}
  for line in (U.read(root .. "/events.jsonl") or ""):gmatch("[^\n]+") do
    local ok, e = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
    if ok and type(e) == "table" then out[#out + 1] = e else out[#out + 1] = { invalid = true, line = line } end
  end
  return out
end

function M.inventory(root)
  if not is_v2(root) then
    if U.exists(root .. "/board.json") then return { schema = "v3", root = root, findings = { { level = "info", text = "already a v3 board" } }, blocking = 0, summary = "already v3" } end
    fail(4, "no legacy board at " .. root)
  end
  local inv = { schema = "v2", root = root, tasks = {}, counts = {}, findings = {}, sessions = {}, locks = {}, paths = {}, reports = {}, journal = {} }
  local function finding(level, text, task) inv.findings[#inv.findings + 1] = { level = level, text = text, task = task } end
  local events = read_events(root)
  local invalid = 0
  for _, e in ipairs(events) do if e.invalid then invalid = invalid + 1 end end
  inv.journal = { events = #events - invalid, invalid_lines = invalid, seq_file = tonumber(vim.trim(U.read(root .. "/seq") or "")) }
  if inv.journal.seq_file and inv.journal.seq_file ~= inv.journal.events then finding("warn", ("seq file says %d but the journal holds %d events"):format(inv.journal.seq_file, inv.journal.events)) end
  local first_ts = {}
  for _, e in ipairs(events) do if not e.invalid and e.task and e.type == "queued" and not first_ts[e.task] then first_ts[e.task] = e.ts end end
  local ids = {}
  local function exists_any(id) for _, s in ipairs(STATES) do if U.exists(root .. "/tasks/" .. s .. "/" .. id .. ".json") then return true end end return false end
  for _, st in ipairs(STATES) do
    inv.counts[st] = 0
    for _, e in ipairs(U.list(root .. "/tasks/" .. st, "%.json$")) do
      local id = e.name:sub(1, -6)
      local task, err = U.read_json(root .. "/tasks/" .. st .. "/" .. e.name)
      inv.counts[st] = inv.counts[st] + 1
      if not task then finding("error", "unreadable task file " .. e.name .. ": " .. tostring(err), id)
      else
        if ids[id] then finding("error", "task appears in two state directories", id) end
        ids[id] = true
        local entry = { id = id, state = st, title = task.title, provider = task.provider, priority = task.priority, timeout = task.timeout,
          worktree = task.worktree, depends_on = task.depends_on or {}, created = task.created, started_at = task.started_at, ended_at = task.ended_at,
          rc = task.rc, session = task.session, dir = task.dir, prompt = task.prompt, cost_usd = task.cost_usd, duration_s = task.duration_s }
        if not P.valid_task_id(id) then finding("error", "task id is not valid in v3", id) end
        if task.prompt and task.prompt ~= root .. "/tasks/prompts/" .. id .. ".md" then
          finding("warn", "prompt path is absolute and outside the standard layout: " .. tostring(task.prompt), id); inv.paths[#inv.paths + 1] = task.prompt
        end
        if not U.exists(root .. "/tasks/prompts/" .. id .. ".md") and not (task.prompt and U.exists(task.prompt)) then finding("error", "prompt file missing", id) end
        local report = root .. "/results/" .. id .. ".md"
        local log = root .. "/logs/" .. id .. ".log"
        entry.has_report, entry.has_log = U.exists(report), U.exists(log)
        if entry.has_report then
          local text = U.read(report) or ""
          entry.report_synthesized = text:find("(no structured report written by the agent)", 1, true) ~= nil
        end
        if (st == "done" or st == "failed") and not entry.has_report and not entry.has_log then finding("warn", "finished without report or log (execution evidence missing)", id) end
        if not task.created and not first_ts[id] then finding("warn", "no creation timestamp; will use the file's mtime", id) end
        if st == "active" then
          local live = T.has("agent-" .. id)
          entry.session_live = live
          inv.sessions[#inv.sessions + 1] = { session = "agent-" .. id, live = live, task = id }
          if live then finding("error", "active task has a live tmux session; stop the worker before migrating", id)
          else finding("warn", "active task without a live session will be imported as an orphaned attempt", id) end
        end
        if task.provider and not P.check_task_fields({ provider = task.provider }, { providers = { claude = true, codex = true, gemini = true, aider = true, cursor = true, mock = true } }) then
          finding("warn", "unknown provider " .. tostring(task.provider) .. " will be kept but cannot be dispatched until edited", id)
        end
        if type(task.priority) == "number" and task.priority < 0 then finding("warn", "negative priority will be raised to 0", id) end
        if type(task.timeout) == "number" and task.timeout <= 0 then finding("warn", "invalid timeout will become the default", id) end
        for _, d in ipairs(task.depends_on or {}) do if not exists_any(d) then finding("warn", "depends on unknown task " .. d .. " (will show as blocked: missing dependency)", id) end end
        inv.tasks[#inv.tasks + 1] = entry
      end
    end
  end
  table.sort(inv.tasks, function(a, b) return a.id < b.id end)
  for _, e in ipairs(U.list(root .. "/results", "%.md$")) do
    local id = e.name:sub(1, -4)
    if not ids[id] then finding("info", "report without a task record: results/" .. e.name) end
    inv.reports[#inv.reports + 1] = e.name
  end
  local sched = vim.env.AISWARM_SESSION or vim.env.HIVE_SESSION or "hive"
  inv.scheduler = { session = sched, live = T.has(sched), paused = U.exists(root .. "/paused") }
  if inv.scheduler.live then finding("error", "legacy scheduler session '" .. sched .. "' is running; run `hive down` first") end
  for _, e in ipairs(U.list(root .. "/locks")) do
    local st = uv.fs_stat(root .. "/locks/" .. e.name)
    local age = st and (U.now_s() - st.mtime.sec) or 0
    inv.locks[#inv.locks + 1] = { name = e.name, age_s = math.floor(age) }
    if e.name:match("%.d$") then finding(age > 30 and "warn" or "error", ("lock %s present (%ds old); %s"):format(e.name, math.floor(age), age > 30 and "looks stale" or "a legacy writer may be active")) end
  end
  if U.exists(root .. "/nvim.server") then inv.registration = vim.trim(U.read(root .. "/nvim.server") or ""); finding("info", "editor push registration present: " .. inv.registration) end
  local base = vim.fs.dirname(root)
  if vim.fs.basename(root) == ".hive" and U.is_dir(base .. "/.aiswarm") then finding("error", "both .hive and .aiswarm exist in " .. base .. "; migration keeps .hive in place, choose the board explicitly") end
  local blocking = 0
  for _, f in ipairs(inv.findings) do if f.level == "error" then blocking = blocking + 1 end end
  inv.blocking = blocking
  inv.summary = ("%d tasks (ready %d, active %d, done %d, failed %d), %d reports, %d events, %d blocking findings"):format(
    #inv.tasks, inv.counts.ready or 0, inv.counts.active or 0, inv.counts.done or 0, inv.counts.failed or 0, #inv.reports, inv.journal.events, blocking)
  return inv
end

-- ---------------------------------------------------------------- conversion (SDD-040)
local function iso_from_epoch(sec) return os.date("!%Y-%m-%dT%H:%M:%S", sec) .. ".000Z" end
--- Pure conversion of one inventory entry into v3 task/attempt records (no side effects).
function M.convert_task(root, entry, board, opts)
  opts = opts or {}
  local now = opts.now or U.now_iso()
  local created = entry.created or opts.first_ts[entry.id]
  local created_source = entry.created and "task_record" or (opts.first_ts[entry.id] and "journal" or "file_mtime")
  if not created then
    local st = uv.fs_stat(root .. "/tasks/" .. entry.state .. "/" .. entry.id .. ".json")
    created = iso_from_epoch(st and st.mtime.sec or os.time())
  end
  local fields = P.check_task_fields({ id = entry.id, title = entry.title or "", provider = entry.provider or "mock",
    priority = (type(entry.priority) == "number" and entry.priority >= 0) and entry.priority or 0,
    timeout = (type(entry.timeout) == "number" and entry.timeout > 0) and entry.timeout or 1800,
    isolation = entry.worktree and "worktree" or "shared", depends_on = entry.depends_on })
  fields = fields or { title = tostring(entry.title or ""):sub(1, 200), provider = "mock", priority = 0, timeout = 1800, isolation = "shared", depends_on = {} }
  local state_map = { ready = "queued", active = "failed", done = "succeeded", failed = "failed" }
  local task = { id = entry.id, title = fields.title, provider = entry.provider or "mock", depends_on = fields.depends_on, priority = fields.priority,
    timeout = fields.timeout, isolation = fields.isolation, revision = 1, prompt_revision = 1,
    prompt_path = root .. "/prompts/" .. entry.id .. "/r1.md", state = state_map[entry.state], current_attempt_id = nil, attempts = {},
    created_at = created, updated_at = now, imported = { legacy = true, from_state = entry.state, created_at_source = created_source, original_prompt = entry.prompt } }
  local attempt
  local has_evidence = entry.state ~= "ready" and (entry.started_at or entry.has_log or entry.has_report or entry.rc ~= nil)
  if has_evidence then
    local id = U.uuid()
    local reason
    if entry.state == "active" then reason = "orphaned_at_migration"
    elseif entry.rc == "orphaned" then reason = "orphaned"
    elseif entry.state == "failed" then reason = entry.rc and ("exit " .. tostring(entry.rc)) or "unknown" end
    local report_path = root .. "/results/" .. entry.id .. ".md"
    local report
    if entry.has_report then
      report = require("aiswarm.runtime.ops").report_quality(report_path)
      if entry.report_synthesized then report.status = "synthesized" end
    else report = { status = "missing", path = report_path } end
    local dir = root .. "/attempts/" .. id
    attempt = {
      attempt_id = id, task_id = entry.id, board_id = board.board_id, ordinal = 1, provider = entry.provider or "mock",
      state = entry.state == "done" and "succeeded" or "failed", reserved_at = entry.started_at, started_at = entry.started_at, finished_at = entry.ended_at,
      exit = { code = type(entry.rc) == "number" and entry.rc or nil }, reason = reason, duration_s = entry.duration_s,
      usage = entry.cost_usd and { cost_usd = entry.cost_usd, provenance = "legacy_grep" } or nil, report = report,
      config = { prompt_revision = 1, prompt_path = task.prompt_path, timeout = task.timeout, isolation = task.isolation, cwd = entry.dir, provider = entry.provider },
      paths = { dir = dir, report = report_path, stdout = root .. "/logs/" .. entry.id .. ".log", stderr = dir .. "/stderr.000001.log",
        prompt = root .. "/tasks/prompts/" .. entry.id .. ".rendered.md", telemetry = dir .. "/telemetry.jsonl", activity = dir .. "/activity.json",
        inbox = dir .. "/inbox", cancel = dir .. "/cancel.request", worker = dir .. "/worker.json", config = dir .. "/config.json" },
      tmux = entry.session and { session = entry.session, legacy = true } or nil,
      imported = { legacy = true, history = "unknown", note = "one imported attempt standing for all legacy executions; earlier retries were not recorded by v2" },
    }
    task.attempts = { id }
    task.outcome = { attempt_id = id, exit_code = attempt.exit.code, reason = reason, finished_at = entry.ended_at or now, report = report.status, duration_s = entry.duration_s, imported = true }
  elseif entry.state ~= "ready" then
    task.outcome = { reason = "imported_without_evidence", finished_at = now, imported = true, report = "missing" }
  end
  return task, attempt
end

-- ---------------------------------------------------------------- migration transaction (SDD-039/041)
local function write_manifest(root, m) U.mkdirp(root .. "/migration"); assert(U.write_json_atomic(manifest_path(root), m)) end
function M.manifest(root) return U.read_json(manifest_path(root)) end

local function copy_tree(src, dst, skip)
  U.mkdirp(dst)
  for _, e in ipairs(U.list(src)) do
    if not (skip and skip[e.name]) then
      if e.type == "directory" then copy_tree(src .. "/" .. e.name, dst .. "/" .. e.name)
      else assert(U.write_atomic(dst .. "/" .. e.name, U.read(src .. "/" .. e.name) or "")) end
    end
  end
end

local function require_quiescent(inv)
  if inv.blocking > 0 then
    local msgs = {}
    for _, f in ipairs(inv.findings) do if f.level == "error" then msgs[#msgs + 1] = (f.task and (f.task .. ": ") or "") .. f.text end end
    fail(3, "migration blocked:\n  " .. table.concat(msgs, "\n  "))
  end
end

--- Run the migration. Phases are recorded in migration/manifest.json so it can resume or roll back.
function M.run(root, opts)
  opts = opts or {}
  if U.exists(root .. "/board.json") then fail(3, root .. " is already a v3 board") end
  if not is_v2(root) then fail(4, "no legacy board at " .. root) end
  local inv = M.inventory(root)
  require_quiescent(inv)
  local ts = os.date("!%Y%m%dT%H%M%S") .. "-" .. uv.os_getpid()
  local m = M.manifest(root)
  if m and m.phase ~= "completed" and m.phase ~= "rolled_back" and not opts.resume then
    fail(3, ("an interrupted migration exists (phase %s, started %s); run `aiswarm migrate --resume` or `--rollback`"):format(m.phase, m.started_at))
  end
  m = { started_at = U.now_iso(), phase = "started", by = U.identity(), root = root, backup = root .. "/migration/backup-" .. ts, staging = root .. "/migration/staging-" .. ts, ts = ts }
  write_manifest(root, m)
  -- marker: compliant v3/aiswarm writers refuse mutations while it exists. Unknown old binaries cannot be made cooperative.
  U.mkdirp(root .. "/locks")
  assert(U.write_json_atomic(marker_path(root), { started_at = m.started_at, pid = m.by.pid, phase = "migrating" }))
  local ok, err = pcall(M.phases, root, m, inv, opts)
  if not ok then
    m.error = type(err) == "table" and err.message or tostring(err)
    if m.phase ~= "published" then m.phase = "failed" end
    write_manifest(root, m)
    if m.phase ~= "published" then os.remove(marker_path(root)) end
    error(err, 0)
  end
  return m
end

function M.phases(root, m, inv, opts)
  -- 1. verified backup
  local before = M.checksums(root)
  if opts.fault == "backup" then fail(1, "fault injected during backup") end
  copy_tree(root, m.backup, { migration = true, locks = true })
  local bmanifest = {}
  for rel, info in pairs(before) do
    local h = sha(m.backup .. "/" .. rel)
    if h ~= info.sha256 then fail(1, "backup verification failed for " .. rel) end
    bmanifest[rel] = info
  end
  assert(U.write_json_atomic(m.backup .. "/MANIFEST.json", { created_at = U.now_iso(), files = bmanifest }))
  m.phase = "backup_done"; write_manifest(root, m)
  if opts.fault == "after_backup" then fail(1, "fault injected after backup") end
  -- 2. staging
  local st = m.staging
  U.mkdirp(st .. "/control/tasks"); U.mkdirp(st .. "/control/attempts"); U.mkdirp(st .. "/control/consumers"); U.mkdirp(st .. "/control/quarantine"); U.mkdirp(st .. "/prompts"); U.mkdirp(st .. "/attempts")
  local board = { schema_version = P.BOARD_SCHEMA, board_id = U.uuid(), journal_generation = 1, name = vim.fs.basename(vim.fs.dirname(root)), created_at = U.now_iso(),
    version = B.VERSION, migrated_from = { schema = 2, at = U.now_iso(), backup = m.backup }, scheduler_defaults = { wip = tonumber(vim.env.AISWARM_WIP) or 3, tick_s = 3, timeout_s = 1800, provider = "mock" } }
  local first_ts = {}
  for _, e in ipairs(read_events(root)) do if not e.invalid and e.task and e.type == "queued" and not first_ts[e.task] then first_ts[e.task] = e.ts end end
  local state = { tasks = {}, attempts = {}, scheduler = { state = "stopped", paused = U.exists(root .. "/paused"), wip = board.scheduler_defaults.wip, tick_s = 3 }, board = board }
  local partials = { { type = "board.migrated", payload = { board = { migrated_from = board.migrated_from }, inventory_summary = inv.summary } } }
  for _, entry in ipairs(inv.tasks) do
    local task, attempt = M.convert_task(root, entry, board, { first_ts = first_ts })
    local src = root .. "/tasks/prompts/" .. entry.id .. ".md"
    local text = U.read(src) or (entry.prompt and U.read(entry.prompt)) or ""
    U.mkdirp(st .. "/prompts/" .. entry.id); assert(U.write_atomic(st .. "/prompts/" .. entry.id .. "/r1.md", text))
    if attempt then
      U.mkdirp(st .. "/attempts/" .. attempt.attempt_id)
      assert(U.write_json_atomic(st .. "/attempts/" .. attempt.attempt_id .. "/config.json", attempt.config))
      partials[#partials + 1] = { type = "task.imported", task_id = task.id, attempt_id = attempt.attempt_id, payload = { task = task, attempt = attempt } }
    else
      partials[#partials + 1] = { type = "task.imported", task_id = task.id, payload = { task = task } }
    end
  end
  partials[#partials + 1] = { type = "scheduler.changed", payload = { scheduler = state.scheduler, changed = { "state", "paused" } } }
  local records, txn_id, now = {}, U.uuid(), U.now_iso()
  for i, r in ipairs(partials) do
    local rec = { schema_version = P.SCHEMA_VERSION, board_id = board.board_id, journal_generation = 1, control_seq = i,
      event_id = ("%s:c:1:%d"):format(board.board_id, i), txn = { id = txn_id, index = i, count = #partials, last = i == #partials },
      observed_at = now, type = r.type, task_id = r.task_id, attempt_id = r.attempt_id, actor = "migration", payload = r.payload }
    local ok, err = P.validate_control_record(rec)
    if not ok then fail(3, "staged record invalid (" .. rec.type .. " " .. tostring(rec.task_id) .. "): " .. err) end
    if rec.type == "task.imported" then
      local tok, terr = P.validate_task(rec.payload.task); if not tok then fail(3, "imported task invalid " .. rec.task_id .. ": " .. terr) end
      if rec.payload.attempt then local aok, aerr = P.validate_attempt(rec.payload.attempt); if not aok then fail(3, "imported attempt invalid: " .. aerr) end end
    end
    records[#records + 1] = rec
  end
  local touched = R.replay(state, records)
  for id, task in pairs(state.tasks) do
    for _, aid in ipairs(task.attempts) do if not state.attempts[aid] then fail(3, "task " .. id .. " references missing attempt " .. aid) end end
  end
  for aid, a in pairs(state.attempts) do if not state.tasks[a.task_id] then fail(3, "attempt " .. aid .. " references missing task") end end
  local lines = {}
  for _, rec in ipairs(records) do lines[#lines + 1] = vim.json.encode(rec) end
  assert(U.write_atomic(st .. "/control/journal.jsonl", table.concat(lines, "\n") .. "\n"))
  assert(U.write_atomic(st .. "/control/seq", tostring(#records)))
  for key in pairs(touched) do
    local kind, id = key:match("^(%w+):(.+)$")
    if kind == "task" then assert(U.write_json_atomic(st .. "/control/tasks/" .. id .. ".json", state.tasks[id]))
    elseif kind == "attempt" then assert(U.write_json_atomic(st .. "/control/attempts/" .. id .. ".json", state.attempts[id])) end
  end
  assert(U.write_json_atomic(st .. "/control/scheduler.json", state.scheduler))
  assert(U.write_json_atomic(st .. "/control/applied.json", { seq = #records }))
  assert(U.write_json_atomic(st .. "/board.json", board))
  m.phase, m.board_id, m.records = "staged", board.board_id, #records; write_manifest(root, m)
  if opts.fault == "after_staging" then fail(1, "fault injected after staging") end
  -- 3. publish: move staged directories into place; board.json last (commit marker)
  for _, d in ipairs({ "control", "prompts", "attempts" }) do
    if U.exists(root .. "/" .. d) then fail(3, root .. "/" .. d .. " already exists; refusing to overwrite") end
    assert(uv.fs_rename(st .. "/" .. d, root .. "/" .. d))
    if opts.fault == "mid_publish" and d == "control" then fail(1, "fault injected mid publish") end
  end
  m.phase = "published"; write_manifest(root, m)
  if opts.fault == "before_manifest" then fail(1, "fault injected before the board manifest") end
  assert(uv.fs_rename(st .. "/board.json", root .. "/board.json"))
  -- 4. complete
  os.remove(marker_path(root))
  U.rm_rf(st)
  m.phase, m.completed_at = "completed", U.now_iso(); write_manifest(root, m)
  return m
end

--- Resume an interrupted migration from its manifest.
function M.resume(root, opts)
  local m = M.manifest(root) or fail(2, "no migration manifest at " .. root)
  if m.phase == "completed" then return m, "migration already completed" end
  if m.phase == "rolled_back" then fail(3, "migration was rolled back; run `aiswarm migrate` to start again") end
  if m.phase == "published" then
    if U.exists(m.staging .. "/board.json") and not U.exists(root .. "/board.json") then assert(uv.fs_rename(m.staging .. "/board.json", root .. "/board.json")) end
    if not U.exists(root .. "/board.json") then fail(3, "published state without a board manifest; restore from " .. m.backup) end
    os.remove(marker_path(root)); U.rm_rf(m.staging)
    m.phase, m.completed_at = "completed", U.now_iso(); write_manifest(root, m)
    return m, "completed the interrupted publication"
  end
  -- not yet published: drop partial staging/publication and rerun from the (verified) backup state
  for _, d in ipairs({ "control", "prompts", "attempts" }) do
    if U.exists(root .. "/" .. d) and not U.exists(root .. "/board.json") then U.rm_rf(root .. "/" .. d) end
  end
  if m.staging then U.rm_rf(m.staging) end
  os.remove(marker_path(root))
  m.phase = "rolled_back"; write_manifest(root, m)
  return M.run(root, vim.tbl_extend("force", opts or {}, { resume = true })), "restarted the interrupted migration"
end

--- Verify a backup against its manifest. Returns ok, list of mismatches.
function M.verify_backup(backup)
  local bm = U.read_json(backup .. "/MANIFEST.json")
  if not bm then return false, { "MANIFEST.json missing" } end
  local bad = {}
  for rel, info in pairs(bm.files) do
    if sha(backup .. "/" .. rel) ~= info.sha256 then bad[#bad + 1] = rel end
  end
  return #bad == 0, bad
end

--- Roll back to the v2 board. Refuses when new v3 work exists or the backup is corrupt.
function M.rollback(root, opts)
  opts = opts or {}
  local m = M.manifest(root) or fail(2, "no migration manifest at " .. root)
  local vok, bad = M.verify_backup(m.backup)
  if not vok then fail(3, "backup at " .. m.backup .. " fails checksum verification (" .. table.concat(bad, ", ") .. "); refusing to roll back onto a corrupt backup") end
  if U.exists(root .. "/board.json") then
    local newer = 0
    J.each(root, function(rec) if rec.control_seq > (m.records or 0) then newer = newer + 1 end end)
    if newer > 0 and not opts.force then
      fail(3, ("refusing to overwrite: %d control records were committed after the migration (new attempts/edits would be lost). Export them first (`aiswarm snapshot --json`, `aiswarm stream`) or pass --force to discard."):format(newer))
    end
    for _, d in ipairs({ "control", "prompts", "attempts" }) do U.rm_rf(root .. "/" .. d) end
    os.remove(root .. "/board.json")
  else
    for _, d in ipairs({ "control", "prompts", "attempts" }) do U.rm_rf(root .. "/" .. d) end
  end
  if m.staging then U.rm_rf(m.staging) end
  os.remove(marker_path(root))
  local bm = U.read_json(m.backup .. "/MANIFEST.json") or { files = {} }
  local restored = {}
  for rel, info in pairs(bm.files) do
    if sha(root .. "/" .. rel) ~= info.sha256 then
      U.mkdirp(vim.fs.dirname(root .. "/" .. rel))
      assert(U.write_atomic(root .. "/" .. rel, U.read(m.backup .. "/" .. rel) or ""))
      restored[#restored + 1] = rel
    end
  end
  m.phase, m.rolled_back_at, m.restored = "rolled_back", U.now_iso(), restored; write_manifest(root, m)
  return m
end

function M.render_inventory(inv)
  local lines = { ("  legacy board %s"):format(inv.root), "  " .. inv.summary }
  for _, f in ipairs(inv.findings or {}) do lines[#lines + 1] = ("  [%s] %s%s"):format(f.level, f.task and (f.task .. ": ") or "", f.text) end
  lines[#lines + 1] = (inv.blocking or 0) > 0 and "  migration is blocked until the errors above are resolved" or "  ready to migrate: `aiswarm migrate` (backup is written to migration/ first)"
  return table.concat(lines, "\n") .. "\n"
end

function M.register(C)
  C.table.migrate = { bools = { dry_run = true, resume = true, rollback = true, force = true }, run = function(a)
    local root = a.root
    if a.opts.dry_run then
      local inv = M.inventory(root)
      return a.json and inv or M.render_inventory(inv)
    elseif a.opts.rollback then
      local m = M.rollback(root, { force = a.opts.force })
      return a.json and m or ("rolled back to the v2 board (restored %d files); backup kept at %s"):format(#m.restored, m.backup)
    elseif a.opts.resume then
      local m, msg = M.resume(root, { fault = a.opts.fault })
      return a.json and m or msg
    end
    local m = M.run(root, { fault = a.opts.fault })
    return a.json and m or ("migrated %s to v3 (board %s, %d records); backup at %s. Start the scheduler explicitly with `aiswarm scheduler start`."):format(root, m.board_id, m.records, m.backup)
  end }
end

return M
