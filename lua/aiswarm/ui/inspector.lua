-- Task inspector: overview, activity, output, report, files and attempts tabs (SDD-054–059).
local M = { current = {}, token = 0, loaded = {}, following = true }
local function A() return require("aiswarm") end
local store = require("aiswarm.store")
local V = require("aiswarm.view_state")
local T = require("aiswarm.ui.text")
local H = require("aiswarm.ui.highlights")
local R = require("aiswarm.ui.render")
local loader = require("aiswarm.ui.loader")
local ns = vim.api.nvim_create_namespace("aiswarm-inspector")
M.LIMITS = { output_lines = 10000, output_bytes = 2 * 1024 * 1024, report_bytes = 1024 * 1024 }
M.TABS = { "overview", "activity", "output", "report", "files", "attempts" }
M.rows = {}

local function ws() return require("aiswarm.ui.workspace") end
function M.tab() local _, _, tab = V.target(); return tab or "overview" end
function M.following() return M.tab() == "output" and V.output.follow or (M.tab() == "activity" and V.feed.follow) end

-- ---------------------------------------------------------------- selection and loading
--- Artifact paths for an attempt (v3) or a legacy task.
function M.paths(task, attempt)
  if attempt and attempt.paths then return { stdout = attempt.paths.stdout, stderr = attempt.paths.stderr, report = attempt.paths.report, dir = attempt.paths.dir, cwd = attempt.config and attempt.config.cwd } end
  local root = A().root()
  if not root or not task then return {} end
  return { stdout = root .. "/logs/" .. task.id .. ".log", report = root .. "/results/" .. task.id .. ".md", cwd = task.cwd, legacy = true }
end

local function key_for(kind, task_id, attempt_id) return kind .. ":" .. tostring(task_id) .. ":" .. tostring(attempt_id) end

--- Start (or reuse) an async load for the current selection's artifact. Renders on completion.
--- A reload keeps the previous content visible until the new read lands (stale-while-revalidate),
--- so a paused view never collapses to a placeholder and never moves the cursor.
function M.load(kind, path, opts)
  local task_id, attempt_id = V.target()
  local key = key_for(kind, task_id, attempt_id)
  local entry = M.loaded[key]
  if entry and entry.path == path and entry.status ~= "loading" and not entry.revalidate and not opts.refresh then
    if not (opts.live and entry.loaded_at and (vim.uv.now() - entry.loaded_at) > (opts.live_ms or 1000)) then return entry end
  end
  if entry and entry.reloading and entry.path == path then return entry end
  M.token = M.token + 1
  local token = M.token
  if entry and entry.path == path and entry.status ~= "loading" then
    entry = vim.tbl_extend("force", entry, { revalidate = false, reloading = true, token = token })
  else
    entry = { status = "loading", path = path, token = token }
  end
  M.loaded[key] = entry
  loader.read(path, { max_bytes = opts.max_bytes, tail = opts.tail, delay_ms = opts.delay_ms, is_current = function()
    local t2, a2 = V.target()
    return t2 == task_id and a2 == attempt_id and M.loaded[key] and M.loaded[key].token == token
  end }, function(res)
    res.path, res.token, res.loaded_at = path, token, vim.uv.now()
    -- lines appended since the previous load of this artifact (from file growth, not the capped view)
    local prev_size = M.sizes[key]
    if res.status == "content" and prev_size and res.size and res.size > prev_size and res.text then
      local appended = res.text:sub(math.max(1, #res.text - (res.size - prev_size) + 1))
      res.new_lines = select(2, appended:gsub("\n", ""))
    end
    if res.size then M.sizes[key] = res.size end
    if res.status == "content" and kind:match("^output") then
      local lines = vim.split(res.text, "\n", { plain = true })
      if lines[#lines] == "" then table.remove(lines) end
      if #lines > M.LIMITS.output_lines then
        local keep = {}
        for i = #lines - M.LIMITS.output_lines + 1, #lines do keep[#keep + 1] = lines[i] end
        lines, res.truncated = keep, true
      end
      res.lines = lines; res.text = nil
    end
    M.loaded[key] = res
    R.mark("inspector")
  end)
  return M.loaded[key]
end
function M.release()
  for _, e in pairs(M.loaded) do e.revalidate = true end
  M.token = M.token + 1
  R.mark("inspector")
end
function M.clear() M.loaded = {}; M.sizes = {}; M.token = M.token + 1 end
M.sizes = {}

-- ---------------------------------------------------------------- tab builders
local function header(task, attempt, tab)
  local lines = {}
  local l = T.line()
  l:add(task.id .. "  ", "AISwarmId"):add(T.sanitize(task.title or ""), "AISwarmTitle")
  if V.pinned then l:add("  " .. T.icons().pin .. " pinned", "AISwarmAccent") end
  lines[#lines + 1] = { l:build() }
  local l2 = T.line()
  l2:add(task.provider or "?", "AISwarmProvider")
  if attempt then l2:add(" · Attempt " .. tostring(attempt.ordinal or "?"), "AISwarmMuted"); if attempt.imported then l2:add(" (imported)", "AISwarmMuted") end end
  l2:add(" · " .. (task.display or task.state), H.for_task(task))
  if task.display_detail then l2:add(" · " .. T.sanitize(task.display_detail), "AISwarmMuted") end
  local dur = attempt and attempt.duration_s or task.duration_s or (task.state == "running" and task.elapsed_s)
  if dur then l2:add(" · " .. T.duration(dur), "AISwarmMuted") end
  lines[#lines + 1] = { l2:build() }
  local tabs = T.line()
  for _, name in ipairs(M.TABS) do
    local label = name:sub(1, 1):upper() .. name:sub(2)
    if name == tab then tabs:add("[" .. label .. "]", "AISwarmAccent") else tabs:add(" " .. label .. " ", "AISwarmMuted") end
  end
  lines[#lines + 1] = { tabs:build() }
  lines[#lines + 1] = { "" }
  return lines
end

local function field(lines, k, v, hl)
  local l = T.line(); l:add(T.fit(k, 18), "AISwarmField"):add(T.sanitize(tostring(v == nil and "-" or v)), hl or "AISwarmValue")
  lines[#lines + 1] = { l:build() }
end

function M.build_overview(task, attempt, width)
  local lines = {}
  local h = task.health or {}
  field(lines, "Provider", task.provider)
  if attempt then
    field(lines, "Attempt", ("%s of %d%s"):format(tostring(attempt.ordinal), #(task.attempts or {}) > 0 and #task.attempts or (attempt.ordinal or 1), attempt.imported and " · imported legacy history (earlier retries unknown)" or ""))
    field(lines, "Attempt id", attempt.attempt_id)
    field(lines, "Working dir", attempt.config and attempt.config.cwd or "-")
    local iso = attempt.config and attempt.config.isolation_info
    field(lines, "Isolation", iso and (iso.mode .. (iso.branch and (" · " .. iso.branch) or "") .. (iso.reused and " (reused)" or "")) or (task.isolation or "shared"))
  else
    field(lines, "Attempt", task.legacy and "unknown (legacy board records no attempts)" or "none yet")
    field(lines, "Isolation", task.isolation or "shared")
  end
  local deps = {}
  for _, d in ipairs(task.depends_on or {}) do
    local dep = store.task(d)
    deps[#deps + 1] = d .. " " .. (dep and (T.icons()[dep.state] or dep.state) or "?")
  end
  field(lines, "Dependencies", #deps > 0 and table.concat(deps, ", ") or "none")
  if task.blockers and #task.blockers > 0 then for _, b in ipairs(task.blockers) do field(lines, "Blocked", b.text, "AISwarmBlocked") end end
  field(lines, "Priority", task.priority); field(lines, "Timeout", task.timeout and (task.timeout .. "s") or "-")
  field(lines, "Created", task.created_at)
  if attempt then field(lines, "Started", attempt.started_at or "-"); field(lines, "Finished", attempt.finished_at or "-") end
  lines[#lines + 1] = { "" }
  local hdr = T.line(); hdr:add("Health", "AISwarmSection"); lines[#lines + 1] = { hdr:build() }
  local function age(iso) local s = iso and T.since_iso(iso); return s and (T.age(s) .. " ago") or "never" end
  if task.state == "running" then
    field(lines, "Heartbeat", (h.heartbeat_at and age(h.heartbeat_at) or (task.legacy and "not reported (legacy)" or "none yet")) .. (h.stale and " (telemetry stale: health unknown until reconciled)" or ""), h.stale and "AISwarmStale" or nil)
    field(lines, "Last output", age(h.output_at))
    field(lines, "Last activity", age(h.activity_at))
    field(lines, "Current activity", h.message and (T.sanitize(h.message) .. (h.phase and (" [" .. h.phase .. "]") or "") .. " · reported by " .. tostring(h.provenance or "worker")) or "none reported")
    if h.input_required then field(lines, "Input", "requested: " .. tostring(h.input_required.prompt or h.input_required.request_id), "AISwarmStale") end
  else
    field(lines, "Process", task.state == "queued" and "not started" or "finished")
  end
  lines[#lines + 1] = { "" }
  local o = T.line(); o:add("Outcome", "AISwarmSection"); lines[#lines + 1] = { o:build() }
  local out = task.outcome or {}
  if task.state == "queued" or task.state == "running" then field(lines, "Execution", task.display or task.state)
  else
    local exec = task.state
    if out.reason then exec = exec .. " · " .. out.reason elseif out.exit_code then exec = exec .. " · exit " .. out.exit_code end
    field(lines, "Execution", exec, H.for_task(task))
  end
  local rq = attempt and attempt.report and attempt.report.status or out.report
  field(lines, "Report", rq == "complete" and "complete (all sections)" or rq == "incomplete" and "incomplete (missing sections)" or rq == "synthesized" and "synthesized by the legacy runner (no agent report)" or rq == "missing" and "not available" or (task.state == "running" and "not available yet" or "unknown"),
    (rq == "missing" or rq == "incomplete") and "AISwarmBlocked" or nil)
  field(lines, "Verification", rq == "complete" and "reported by the agent in its report — not independently verified" or "no verification claim available")
  local usage = attempt and attempt.usage
  field(lines, "Cost", usage and usage.cost_usd and ("$%.2f (%s)"):format(usage.cost_usd, usage.provenance or "reported") or (task.cost_usd and ("$%.2f (legacy)"):format(task.cost_usd)) or "unknown (not reported)")
  return lines
end

function M.build_activity(task, attempt, width)
  local scope = { task_id = task.id, attempt_id = V.feed.scope_all_attempts and nil or (attempt and attempt.attempt_id or nil), min_level = V.feed.filters.min_level, show_hidden = V.feed.filters.show_hidden }
  local recs = store.activity_for(scope)
  local lines = {}
  local l = T.line(); l:add(("Activity · %s · %d records"):format(attempt and ("attempt " .. tostring(attempt.ordinal)) or "all", #recs), "AISwarmSection")
  if not V.feed.follow then l:add(("  · view paused, %d unread (f resumes)"):format(V.output.unread or 0), "AISwarmBlocked") end
  lines[#lines + 1] = { l:build() }
  if #recs == 0 then lines[#lines + 1] = { "  no activity recorded for this attempt", { { 0, 40, "AISwarmMuted" } } } end
  for _, r in ipairs(recs) do
    local row = T.line()
    row:add(T.fit((r.ts or ""):match("T(%d%d:%d%d:%d%d)") or (r.ts or ""), 9), "AISwarmMuted")
    row:add(T.fit(r.kind or "", 12), r.level == "error" and "AISwarmFailed" or r.level == "warn" and "AISwarmBlocked" or "AISwarmProvider")
    row:add(T.truncate(T.sanitize(r.text or ""), math.max(10, width - 30)), r.level == "error" and "AISwarmFailed" or "AISwarmValue")
    if r.count and r.count > 1 then row:add(("  ×%d"):format(r.count), "AISwarmMuted") end
    if r.provenance then row:add("  " .. r.provenance, "AISwarmHint") end
    lines[#lines + 1] = { row:build() }
  end
  return lines
end

function M.build_output(task, attempt, paths, width)
  local stream = V.output.stream
  local path = stream == "stderr" and paths.stderr or paths.stdout
  local entry = M.load("output:" .. stream, path, { max_bytes = M.LIMITS.output_bytes, tail = true, live = task.state == "running" })
  local lines = {}
  local l = T.line()
  l:add(("Output · %s"):format(stream), "AISwarmSection")
  if not paths.stderr and not paths.legacy then l:add(" (stderr unavailable)", "AISwarmMuted") end
  if paths.legacy then l:add(" · legacy merged transcript", "AISwarmMuted") end
  l:add(V.output.follow and "  · following" or ("  · view paused, " .. tostring(V.output.unread) .. " new lines (f resumes, G jumps)"), V.output.follow and "AISwarmMuted" or "AISwarmBlocked")
  if entry.truncated then l:add("  · showing the last part; o opens the full transcript", "AISwarmBlocked") end
  lines[#lines + 1] = { l:build() }
  if entry.status == "loading" then lines[#lines + 1] = { "  loading…", { { 0, 10, "AISwarmMuted" } } }
  elseif entry.status == "missing" then lines[#lines + 1] = { task.state == "running" and "  no output yet" or "  no output was captured for this attempt", { { 0, 50, "AISwarmMuted" } } }
  elseif entry.status == "empty" then lines[#lines + 1] = { "  (zero bytes of output)", { { 0, 24, "AISwarmMuted" } } }
  elseif entry.status == "error" then lines[#lines + 1] = { "  read failed: " .. tostring(entry.error) .. "  (Ctrl-r to retry)", { { 0, 80, "AISwarmFailed" } } }
  else
    for _, ln in ipairs(entry.lines or {}) do lines[#lines + 1] = { T.sanitize(ln), stream == "stderr" and { { 0, #T.sanitize(ln), "AISwarmStderr" } } or {} } end
  end
  return lines, entry
end

local function report_label(status)
  if status == "complete" then return "complete", "AISwarmDone" end
  if status == "incomplete" then return "incomplete: missing required sections", "AISwarmBlocked" end
  if status == "synthesized" then return "synthesized by the legacy runner, not written by the agent", "AISwarmBlocked" end
  if status == "missing" then return "missing: this attempt wrote no report", "AISwarmBlocked" end
  return status or "unknown", "AISwarmMuted"
end

function M.build_report(task, attempt, paths, width)
  local entry = M.load("report", paths.report, { max_bytes = M.LIMITS.report_bytes, live = task.state == "running", live_ms = 5000 })
  local lines = {}
  local status = attempt and attempt.report and attempt.report.status or (task.outcome and task.outcome.report)
  local label, hl = report_label(status or (entry.status == "content" and "present" or entry.status))
  local l = T.line(); l:add(("Report · attempt %s · "):format(attempt and tostring(attempt.ordinal) or "-"), "AISwarmSection"):add(label, hl)
  lines[#lines + 1] = { l:build() }
  lines[#lines + 1] = { "" }
  if entry.status == "loading" then lines[#lines + 1] = { "  loading…", { { 0, 10, "AISwarmMuted" } } }
  elseif entry.status == "missing" then lines[#lines + 1] = { "  No report for this attempt. Earlier attempts' reports are listed under Attempts.", { { 0, 80, "AISwarmMuted" } } }
  elseif entry.status == "empty" then lines[#lines + 1] = { "  (empty report file)", { { 0, 20, "AISwarmMuted" } } }
  elseif entry.status == "error" then lines[#lines + 1] = { "  read failed: " .. tostring(entry.error), { { 0, 60, "AISwarmFailed" } } }
  else
    for _, ln in ipairs(vim.split(entry.text or "", "\n", { plain = true })) do
      local s = T.sanitize(ln)
      lines[#lines + 1] = { s, s:match("^#") and { { 0, #s, "AISwarmSection" } } or {} }
    end
  end
  return lines
end

--- Files from the report's "Files changed" section and artifact activity records, with provenance.
function M.files_of(task, attempt, paths)
  local files = {}
  local entry = M.loaded[key_for("report", task.id, attempt and attempt.attempt_id)] or M.load("report", paths.report, { max_bytes = M.LIMITS.report_bytes })
  if entry.status == "content" then
    local in_section = false
    for _, ln in ipairs(vim.split(entry.text or "", "\n", { plain = true })) do
      if ln:match("^## ") then in_section = ln:match("^## Files changed") ~= nil
      elseif in_section then
        local p = vim.trim(ln:gsub("^[%-%*]%s*", ""):gsub("`", ""))
        if p ~= "" and not p:match("^%(") and not p:match("^none") then files[#files + 1] = { path = p, provenance = "report (agent-written)" } end
      end
    end
  end
  for _, r in ipairs(store.activity_for({ task_id = task.id, attempt_id = attempt and attempt.attempt_id, kinds = { artifact = true }, min_level = "debug", show_hidden = true })) do
    if r.path then files[#files + 1] = { path = r.path, provenance = "artifact event (" .. tostring(r.provenance or r.source) .. ")" } end
  end
  return files
end

function M.build_files(task, attempt, paths, width)
  local files = M.files_of(task, attempt, paths)
  local lines = {}
  local l = T.line(); l:add(("Files · %d"):format(#files), "AISwarmSection")
  local shared = not (attempt and attempt.config and attempt.config.isolation_info and attempt.config.isolation_info.mode == "worktree")
  if shared then l:add("  · shared working directory: changes cannot be attributed to this task alone", "AISwarmMuted") end
  lines[#lines + 1] = { l:build() }
  M.rows = {}
  if #files == 0 then lines[#lines + 1] = { "  no files reported (the report's Files changed section is empty or missing)", { { 0, 80, "AISwarmMuted" } } } end
  for _, f in ipairs(files) do
    local row = T.line(); row:add("  " .. f.path, "AISwarmValue"):add("   " .. f.provenance, "AISwarmHint")
    lines[#lines + 1] = { row:build() }
    M.rows[#lines] = { file = f, cwd = paths.cwd }
  end
  lines[#lines + 1] = { "" }
  lines[#lines + 1] = { "  Enter opens the file (relative paths resolve against the attempt's working directory); d shows a diff when a diff tool is available.", { { 0, 120, "AISwarmHint" } } }
  return lines
end

function M.build_attempts(task, attempt, width)
  local lines = {}
  local atts = store.attempts_of(task.id)
  local l = T.line(); l:add(("Attempts · %d"):format(#atts), "AISwarmSection")
  if task.legacy then l:add("  · legacy board: attempts are not recorded", "AISwarmMuted") end
  lines[#lines + 1] = { l:build() }
  M.rows = {}
  for _, a in ipairs(atts) do
    local row = T.line()
    local cur = attempt and attempt.attempt_id == a.attempt_id
    row:add(cur and "> " or "  ", "AISwarmAccent")
    row:add(T.fit("#" .. tostring(a.ordinal), 4), "AISwarmId")
    row:add(T.fit(a.provider or task.provider or "", 8), "AISwarmProvider")
    row:add(T.fit(a.state or "?", 10), H.STATE[a.state] or "AISwarmMuted")
    row:add(T.fit((a.started_at or a.reserved_at or "-"):sub(1, 19), 20), "AISwarmMuted")
    row:add(T.fit(a.finished_at and a.finished_at:sub(1, 19) or "-", 20), "AISwarmMuted")
    row:add(T.truncate((a.reason or (a.exit and a.exit.code and ("exit " .. a.exit.code)) or "") .. (a.imported and " · imported" or ""), 30), "AISwarmMuted")
    lines[#lines + 1] = { row:build() }
    M.rows[#lines] = { attempt_id = a.attempt_id }
  end
  lines[#lines + 1] = { "" }
  lines[#lines + 1] = { "  Enter selects an attempt: Activity, Output, Report and Files then show that attempt's own artifacts.", { { 0, 110, "AISwarmHint" } } }
  return lines
end

-- ---------------------------------------------------------------- render
function M.render()
  local W = ws()
  local buf = W.buf("inspector")
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local win = W.win_of("inspector")
  local width = win and vim.api.nvim_win_get_width(win) or 80
  local task_id, attempt_id, tab = V.target()
  local task = task_id and store.task(task_id)
  -- streaming tabs re-render only when their artifact read or the selection changed
  if task and (tab == "output" or tab == "report") then
    local k = key_for(tab .. ":" .. V.output.stream, task_id, attempt_id)
    local e = M.loaded[k]
    local memo = table.concat({ task_id, tostring(attempt_id), tab, V.output.stream, tostring(V.output.wrap), tostring(V.output.follow), tostring(e and e.loaded_at), tostring(e and e.status), tostring(V.version), tostring(task.revision), tostring(task.state) }, "|")
    if M._memo == memo and e and e.status ~= "loading" and not e.revalidate and not e.reloading then
      if e.loaded_at and task.state == "running" and (vim.uv.now() - e.loaded_at) > 1000 then M.load(tab == "output" and ("output:" .. V.output.stream) or "report", e.path, { max_bytes = tab == "output" and M.LIMITS.output_bytes or M.LIMITS.report_bytes, tail = tab == "output", live = true }) end
      return
    end
    M._memo = memo
  else
    M._memo = nil
  end
  local lines
  if not task then
    lines = { { "" }, { "  Select a task to inspect it.", { { 0, 30, "AISwarmMuted" } } } }
    M.current = {}
  else
    local attempt = attempt_id and store.attempt(attempt_id) or store.current_attempt(task.id)
    local paths = M.paths(task, attempt)
    lines = header(task, attempt, tab)
    local body, entry
    if tab == "overview" then body = M.build_overview(task, attempt, width)
    elseif tab == "activity" then body = M.build_activity(task, attempt, width)
    elseif tab == "output" then body, entry = M.build_output(task, attempt, paths, width)
    elseif tab == "report" then body = M.build_report(task, attempt, paths, width)
    elseif tab == "files" then body = M.build_files(task, attempt, paths, width)
    else body = M.build_attempts(task, attempt, width) end
    for _, l in ipairs(body) do lines[#lines + 1] = l end
    local prev = M.current
    M.current = { task_id = task.id, attempt_id = attempt and attempt.attempt_id, tab = tab, entry = entry, header = #header(task, attempt, tab) }
    -- unread accounting for paused output views: count appended lines once per load
    if tab == "output" and entry and entry.new_lines and not entry.counted then
      entry.counted = true
      if not V.output.follow then V.output.unread = V.output.unread + entry.new_lines end
    end
  end
  local saved = win and vim.api.nvim_win_get_cursor(win) or nil
  M._setting = true
  T.set_lines(buf, ns, lines)
  if win then
    vim.wo[win].wrap = V.output.wrap and tab == "output"
    local following = (tab == "output" and V.output.follow) or (tab == "activity" and V.feed.follow)
    if (tab == "output" or tab == "activity") and following then
      pcall(vim.api.nvim_win_set_cursor, win, { #lines, 0 })
    elseif saved then
      -- a paused or non-streaming view never moves the cursor under the user
      pcall(vim.api.nvim_win_set_cursor, win, { math.min(saved[1], #lines), saved[2] })
    end
  end
  M._setting = false
  M.install_scroll_watch(buf)
  W.update_chrome()
end

function M.install_scroll_watch(buf)
  if M._watch_buf == buf then return end
  M._watch_buf = buf
  vim.api.nvim_create_autocmd("CursorMoved", { buffer = buf, callback = function()
    if M._setting then return end
    local tab = M.tab()
    local win = ws().win_of("inspector"); if not win then return end
    local last = vim.api.nvim_buf_line_count(buf)
    local row = vim.api.nvim_win_get_cursor(win)[1]
    if tab == "output" and V.output.follow and row < last then V.output.follow = false; V.output.unread = 0; ws().update_chrome(); R.mark("inspector")
    elseif tab == "activity" and V.feed.follow and row < last then V.feed.follow = false; V.feed.unread = 0; ws().update_chrome(); R.mark("inspector") end
  end })
end

-- ---------------------------------------------------------------- key handlers
function M.cycle_tab(dir)
  local cur = M.tab()
  local idx = 1
  for i, t in ipairs(M.TABS) do if t == cur then idx = i end end
  V.set_tab(M.TABS[(idx - 1 + dir) % #M.TABS + 1])
  R.mark("inspector")
end
function M.toggle_follow()
  local tab = M.tab()
  if tab == "output" then V.output.follow = not V.output.follow; V.output.unread = 0
  elseif tab == "activity" then V.feed.follow = not V.feed.follow; V.feed.unread = 0
  else return A().notify("view following applies to the Output and Activity tabs") end
  R.mark("inspector")
end
function M.jump_end()
  local tab = M.tab()
  if tab == "output" then V.output.follow, V.output.unread = true, 0 elseif tab == "activity" then V.feed.follow, V.feed.unread = true, 0 end
  local win = ws().win_of("inspector")
  if win then pcall(vim.api.nvim_win_set_cursor, win, { vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win)), 0 }) end
  R.mark("inspector")
end
function M.toggle_stream() V.output.stream = V.output.stream == "stdout" and "stderr" or "stdout"; V.output.unread = 0; R.mark("inspector") end
function M.toggle_wrap() V.output.wrap = not V.output.wrap; R.mark("inspector") end

function M.enter()
  local win = ws().win_of("inspector"); if not win then return end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local entry = M.rows[row]
  if not entry then return end
  if entry.attempt_id then
    V.select(V.target(), entry.attempt_id); if V.pinned then V.pinned.attempt_id = entry.attempt_id end
    V.set_tab("overview"); R.mark("inspector"); return
  end
  if entry.file then
    local path = entry.file.path
    if not path:match("^/") then path = (entry.cwd or vim.uv.cwd()) .. "/" .. path end
    if vim.uv.fs_stat(path) then
      ws().close(); vim.cmd.edit(vim.fn.fnameescape(path))
    else
      A().warn(("file not found: %s (reported path; resolved against %s)"):format(path, entry.cwd or "cwd"))
    end
  end
end

function M.diff_at_cursor()
  local win = ws().win_of("inspector"); if not win then return end
  local entry = M.rows[vim.api.nvim_win_get_cursor(win)[1]]
  if not entry or not entry.file then return end
  local path = entry.file.path
  if not path:match("^/") then path = (entry.cwd or vim.uv.cwd()) .. "/" .. path end
  if vim.fn.exists(":DiffviewOpen") == 2 then
    ws().close(); vim.cmd("DiffviewOpen -- " .. vim.fn.fnameescape(path))
  elseif vim.fn.executable("git") == 1 and vim.uv.fs_stat(path) then
    ws().close(); vim.cmd.edit(vim.fn.fnameescape(path)); vim.cmd("silent! Gdiffsplit")
  else
    A().warn("no diff tool available (install diffview.nvim or vim-fugitive); the file itself opens with Enter")
  end
end

--- Open the full raw transcript of the target attempt in a normal buffer.
function M.open_transcript(target)
  local task = store.task(target.task_id); if not task then return end
  local attempt = target.attempt_id and store.attempt(target.attempt_id) or store.current_attempt(task.id)
  local paths = M.paths(task, attempt)
  local path = V.output.stream == "stderr" and paths.stderr or paths.stdout
  if not path or not vim.uv.fs_stat(path) then return A().warn("no transcript file for " .. task.id) end
  ws().close()
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.modifiable = false
end

return M
