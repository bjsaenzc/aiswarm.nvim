-- Validated control transactions: add/edit/reorder/cancel/retry and attempt lifecycle (SDD-023–027, 032–034).
local U = require("aiswarm.runtime.util")
local B = require("aiswarm.runtime.board")
local P = require("aiswarm.protocol")
local O = {}
local fail = B.fail

function O.providers()
  local ok, registry = pcall(require, "aiswarm.providers.registry")
  if ok then
    local set = {}
    for _, id in ipairs(registry.ids()) do set[id] = true end
    return set, registry
  end
  return { claude = true, codex = true, gemini = true, aider = true, cursor = true, mock = true }, nil
end

local function next_id(ctx, state)
  local max = 0
  for id in pairs(state.tasks) do local n = tonumber(id:match("^T%-(%d+)$")); if n and n > max then max = n end end
  for _, e in ipairs(U.list(ctx.paths.prompts)) do local n = tonumber(e.name:match("^T%-(%d+)$")); if n and n > max then max = n end end
  return ("T-%03d"):format(max + 1)
end

local function write_prompt(ctx, id, revision, text)
  local dir = ctx.paths.prompts .. "/" .. id
  U.mkdirp(dir)
  local path = dir .. "/r" .. revision .. ".md"
  local ok, err = U.write_atomic(path, text)
  if not ok then fail(1, "cannot write prompt: " .. tostring(err)) end
  return path
end

local function isolation_preflight(ctx, fields)
  if fields.isolation ~= "worktree" then return end
  local dir = vim.env.AISWARM_WORKTREES or (ctx.board.scheduler_defaults or {}).worktrees_dir
  if not dir or dir == "" then fail(3, "isolation=worktree requires a worktrees directory (AISWARM_WORKTREES or board scheduler_defaults.worktrees_dir)") end
  if vim.fn.executable("git") == 0 then fail(4, "isolation=worktree requires git") end
  local base = vim.fs.dirname(ctx.root)
  local o = vim.system({ "git", "-C", base, "rev-parse", "--show-toplevel" }, { text = true }):wait(5000)
  if not o or o.code ~= 0 then fail(3, "isolation=worktree requires the project to be a git repository: " .. base) end
  if not U.exists(dir) then U.mkdirp(dir) end
  if not U.is_dir(dir) then fail(3, "worktrees directory is not a directory: " .. dir) end
end

-- ---------------------------------------------------------------- add (SDD-023)
---@param args { id?: string, title?: string, provider?: string, depends_on?: string[]|string, priority?, timeout?, isolation?, prompt: string }
function O.add(ctx, args)
  local providers, registry = O.providers()
  if type(args.prompt) ~= "string" or vim.trim(args.prompt) == "" then fail(3, "prompt is empty") end
  if args.id ~= nil and not P.valid_task_id(args.id) then fail(3, "invalid task id: " .. tostring(args.id)) end
  local fields = { id = args.id, title = args.title, provider = args.provider or (registry and registry.default() or "mock"),
    priority = args.priority, timeout = args.timeout, isolation = args.isolation, depends_on = args.depends_on }
  local norm, err = P.check_task_fields(fields, { providers = providers })
  if not norm then fail(3, err) end
  if norm.title == "" then norm.title = (args.prompt:match("^[^\n]*") or ""):sub(1, 72) end
  isolation_preflight(ctx, norm)
  local task
  B.txn(ctx, { purpose = "add", actor = args.actor }, function(state)
    local id = args.id or next_id(ctx, state)
    if state.tasks[id] or U.exists(ctx.paths.prompts .. "/" .. id) then fail(3, "task already exists: " .. id) end
    local gok, gerr = P.check_dependency_graph(id, norm.depends_on, state.tasks)
    if not gok then fail(3, gerr) end
    local path = write_prompt(ctx, id, 1, args.prompt)   -- staged before the record; unreferenced on failure
    task = { id = id, title = norm.title, provider = norm.provider, depends_on = norm.depends_on, priority = norm.priority,
      timeout = norm.timeout, isolation = norm.isolation, revision = 1, prompt_revision = 1, prompt_path = path,
      state = "queued", current_attempt_id = nil, attempts = {}, created_at = U.now_iso(), updated_at = U.now_iso(),
      source = args.source }
    return { { type = "task.queued", task_id = id, payload = { task = task } } }
  end)
  return task
end

-- ---------------------------------------------------------------- edit (SDD-024)
---@param args { expected_revision: number, title?, provider?, depends_on?, priority?, timeout?, isolation?, prompt? }
function O.edit(ctx, id, args)
  local providers = O.providers()
  if not P.valid_task_id(id) then fail(3, "invalid task id") end
  if not P.is_int(args.expected_revision, 1) then fail(3, "expected_revision is required") end
  local fields = { id = id, title = args.title, provider = args.provider, priority = args.priority, timeout = args.timeout,
    isolation = args.isolation, depends_on = args.depends_on }
  local norm, err, field = P.check_task_fields(fields, { partial = true, providers = providers })
  if not norm then fail(3, err, field) end
  if args.prompt ~= nil and vim.trim(args.prompt) == "" then fail(3, "prompt is empty") end
  local task
  B.txn(ctx, { purpose = "edit", actor = args.actor }, function(state)
    local cur = state.tasks[id]
    if not cur then fail(2, "no such task: " .. id) end
    if cur.state ~= "queued" then fail(3, id .. " is " .. cur.state .. "; only queued tasks can be edited") end
    if cur.revision ~= args.expected_revision then fail(3, ("revision conflict: %s is at revision %d, expected %d"):format(id, cur.revision, args.expected_revision)) end
    task = vim.deepcopy(cur)
    for k, v in pairs(norm) do task[k] = v end
    if norm.isolation then isolation_preflight(ctx, task) end
    local gok, gerr = P.check_dependency_graph(id, task.depends_on, state.tasks)
    if not gok then fail(3, gerr) end
    if args.prompt ~= nil then
      task.prompt_revision = cur.prompt_revision + 1
      task.prompt_path = write_prompt(ctx, id, task.prompt_revision, args.prompt)
    end
    task.revision, task.updated_at = cur.revision + 1, U.now_iso()
    return { { type = "task.edited", task_id = id, payload = { task = task, changed = vim.tbl_keys(norm) } } }
  end)
  return task
end

-- ---------------------------------------------------------------- reorder (SDD-026)
--- Move a queued task: where = "first"|"last"|"before"|"after" (+ other). Rebalances priorities when needed.
function O.move(ctx, id, where, other)
  if not P.valid_task_id(id) then fail(3, "invalid task id") end
  if (where == "before" or where == "after") and not P.valid_task_id(other or "") then fail(3, "usage: move <id> --before <id>|--after <id>|--first|--last") end
  local result
  B.txn(ctx, { purpose = "move" }, function(state)
    local task = state.tasks[id]
    if not task then fail(2, "no such task: " .. id) end
    if task.state ~= "queued" then fail(3, id .. " is " .. task.state .. "; only queued tasks can be reordered") end
    local queue = {}
    for _, t in pairs(state.tasks) do if t.state == "queued" and t.id ~= id then queue[#queue + 1] = t end end
    table.sort(queue, P.compare_queue)
    local index
    if where == "first" then index = 1
    elseif where == "last" then index = #queue + 1
    else
      local o = state.tasks[other]
      if not o or o.state ~= "queued" then fail(3, "reference task must be queued: " .. tostring(other)) end
      for i, t in ipairs(queue) do if t.id == other then index = where == "before" and i or i + 1 end end
    end
    table.insert(queue, index, task)
    -- assign priorities: keep existing values where the order already holds, else renumber with stride 10
    local changed = {}
    local prev = queue[index - 1]; local nxt = queue[index + 1]
    local lo = prev and prev.priority or nil
    local hi = nxt and nxt.priority or nil
    local target
    if lo == nil and hi == nil then target = task.priority
    elseif lo == nil then target = hi >= 1 and hi - 1 or nil
    elseif hi == nil then target = lo + 1
    elseif hi - lo >= 2 then target = lo + math.floor((hi - lo) / 2)
    else target = nil end
    if target ~= nil and target >= 0 then
      if target ~= task.priority then local nt = vim.deepcopy(task); nt.priority = target; nt.revision = nt.revision + 1; nt.updated_at = U.now_iso(); changed[#changed + 1] = nt end
    else
      for i, t in ipairs(queue) do
        local want = (i - 1) * 10
        if t.priority ~= want then local nt = vim.deepcopy(t); nt.priority = want; nt.revision = nt.revision + 1; nt.updated_at = U.now_iso(); changed[#changed + 1] = nt end
      end
    end
    if #changed == 0 then result = { moved = id, changed = {} }; return nil end
    local records = {}
    for _, t in ipairs(changed) do records[#records + 1] = { type = "task.reordered", task_id = t.id, payload = { task = t, moved = id } } end
    result = { moved = id, changed = vim.tbl_map(function(t) return { id = t.id, priority = t.priority } end, changed) }
    return records
  end)
  return result
end

-- ---------------------------------------------------------------- attempts (SDD-027)
function O.attempt_paths(ctx, attempt_id)
  local dir = ctx.paths.attempt_dirs .. "/" .. attempt_id
  return { dir = dir, config = dir .. "/config.json", prompt = dir .. "/prompt.rendered.md", stdout = dir .. "/stdout.000001.log",
    stderr = dir .. "/stderr.000001.log", telemetry = dir .. "/telemetry.jsonl", activity = dir .. "/activity.json",
    inbox = dir .. "/inbox", report = dir .. "/report.md", cancel = dir .. "/cancel.request", worker = dir .. "/worker.json" }
end

--- Build a reserved attempt for `task` (pure apart from the uuid). Freezes the execution config.
function O.reserve_attempt(ctx, task, info)
  info = info or {}
  local attempt_id = U.uuid()
  local paths = O.attempt_paths(ctx, attempt_id)
  local attempt = {
    attempt_id = attempt_id, task_id = task.id, board_id = ctx.board.board_id, ordinal = #(task.attempts or {}) + 1,
    provider = task.provider, state = "starting", reserved_at = U.now_iso(),
    config = { prompt_revision = task.prompt_revision, prompt_path = task.prompt_path, timeout = task.timeout, isolation = task.isolation,
      cwd = info.cwd, provider = task.provider, task_revision = task.revision },
    paths = paths, scheduler = info.scheduler, tmux = info.tmux,
  }
  local nt = vim.deepcopy(task)
  nt.state, nt.current_attempt_id, nt.revision, nt.updated_at = "running", attempt_id, task.revision + 1, U.now_iso()
  nt.attempts = vim.list_extend(vim.list_extend({}, task.attempts or {}), { attempt_id })
  nt.outcome = nil
  return attempt, nt
end

--- Worker acknowledges startup (SDD-032). Fenced by current attempt and state.
function O.attempt_started(ctx, attempt_id, info)
  local out
  B.txn(ctx, { purpose = "attempt.started", actor = "worker:" .. attempt_id }, function(state)
    local a = state.attempts[attempt_id]
    if not a then fail(2, "no such attempt: " .. attempt_id) end
    local task = state.tasks[a.task_id]
    if not task or task.current_attempt_id ~= attempt_id then fail(3, "attempt is not the task's current attempt") end
    if a.state ~= "starting" then
      if a.state == "running" then out = a; return nil end
      fail(3, "attempt is " .. a.state)
    end
    local na = vim.deepcopy(a)
    na.state, na.started_at = "running", U.now_iso()
    na.worker = { pid = info.pid, pid_start = info.pid_start, pgid = info.pgid, host = info.host }
    na.tmux = info.tmux or a.tmux
    na.config.cwd = info.cwd or a.config.cwd
    out = na
    return { { type = "attempt.started", task_id = a.task_id, attempt_id = attempt_id, payload = { attempt = na } } }
  end)
  return out
end

local function report_quality(path)
  local text = U.read(path)
  if not text then return { status = "missing", path = path } end
  local sections = { "Summary", "Files changed", "Decisions", "Verification", "Follow-ups" }
  local found = 0
  for _, s in ipairs(sections) do if text:match("\n## " .. s:gsub("%-", "%%-")) or text:match("^## " .. s:gsub("%-", "%%-")) then found = found + 1 end end
  if found == #sections then return { status = "complete", path = path, bytes = #text } end
  if vim.trim(text) == "" then return { status = "incomplete", path = path, bytes = #text, reason = "empty" } end
  return { status = "incomplete", path = path, bytes = #text, sections = found }
end
O.report_quality = report_quality

--- Terminal outcome (SDD-032/036): idempotent, fenced by attempt identity; never moves backwards.
---@param outcome { state: "succeeded"|"failed"|"cancelled", exit_code?: number, signal?: number, reason?: string, usage?: table }
function O.attempt_finished(ctx, attempt_id, outcome)
  local result
  B.txn(ctx, { purpose = "attempt.finished", actor = outcome.actor or ("worker:" .. attempt_id) }, function(state)
    local a = state.attempts[attempt_id]
    if not a then fail(2, "no such attempt: " .. attempt_id) end
    if P.TERMINAL[a.state] then result = { attempt = a, task = state.tasks[a.task_id], duplicate = true }; return nil end
    if not P.TERMINAL[outcome.state] then fail(3, "outcome state must be terminal") end
    local na = vim.deepcopy(a)
    na.state, na.finished_at = outcome.state, U.now_iso()
    na.exit = { code = outcome.exit_code, signal = outcome.signal }
    na.reason = outcome.reason
    na.usage = outcome.usage  -- nil unless the provider reported it
    na.report = report_quality(a.paths.report)
    local started = U.parse_iso(a.started_at or a.reserved_at)
    na.duration_s = started and math.floor(U.now_s() - started) or nil
    local records = { { type = "attempt.finished", task_id = a.task_id, attempt_id = attempt_id, payload = { attempt = na } } }
    local task = state.tasks[a.task_id]
    if task and task.current_attempt_id == attempt_id then
      local nt = vim.deepcopy(task)
      nt.state, nt.revision, nt.updated_at = outcome.state, task.revision + 1, U.now_iso()
      nt.outcome = { attempt_id = attempt_id, exit_code = outcome.exit_code, signal = outcome.signal, reason = outcome.reason,
        finished_at = na.finished_at, report = na.report.status, duration_s = na.duration_s }
      records[#records + 1] = { type = outcome.state == "cancelled" and "task.cancelled" or "task.finished", task_id = task.id, payload = { task = nt } }
      result = { attempt = na, task = nt }
    else
      -- late record from an older attempt: history only, current task untouched
      result = { attempt = na, task = task, late = true }
    end
    return records
  end)
  return result
end

-- ---------------------------------------------------------------- cancel (SDD-033) and retry (SDD-034)
--- Cancel a queued task in one transaction, or return the running attempt for process termination.
function O.cancel_queued(ctx, id, opts)
  local result
  B.txn(ctx, { purpose = "cancel", actor = opts and opts.actor }, function(state)
    local task = state.tasks[id]
    if not task then fail(2, "no such task: " .. id) end
    if opts and opts.expected_revision and task.revision ~= opts.expected_revision then
      fail(3, ("task changed: %s is at revision %d, expected %d"):format(id, task.revision, opts.expected_revision))
    end
    if task.state == "queued" then
      local nt = vim.deepcopy(task)
      nt.state, nt.revision, nt.updated_at = "cancelled", task.revision + 1, U.now_iso()
      nt.outcome = { reason = "cancelled_before_start", finished_at = nt.updated_at }
      result = { task = nt, running = false }
      return { { type = "task.cancelled", task_id = id, payload = { task = nt } } }
    elseif task.state == "running" then
      result = { task = task, attempt = state.attempts[task.current_attempt_id], running = true }
      return nil
    else
      fail(3, id .. " is already " .. task.state .. "; nothing to cancel")
    end
  end)
  return result
end

function O.retry(ctx, id, opts)
  local result
  B.txn(ctx, { purpose = "retry", actor = opts and opts.actor }, function(state)
    local task = state.tasks[id]
    if not task then fail(2, "no such task: " .. id) end
    if opts and opts.expected_revision and task.revision ~= opts.expected_revision then
      fail(3, ("task changed: %s is at revision %d, expected %d"):format(id, task.revision, opts.expected_revision))
    end
    if not P.TERMINAL[task.state] then fail(3, id .. " is " .. task.state .. "; only finished tasks can be retried") end
    local nt = vim.deepcopy(task)
    nt.state, nt.current_attempt_id, nt.revision, nt.updated_at = "queued", nil, task.revision + 1, U.now_iso()
    nt.outcome, nt.previous_outcome = nil, task.outcome
    result = nt
    return { { type = "task.retried", task_id = id, payload = { task = nt } } }
  end)
  return result
end

-- ---------------------------------------------------------------- scheduler record
function O.scheduler_changed(ctx, changes, opts)
  local out
  B.txn(ctx, { purpose = "scheduler", actor = opts and opts.actor }, function(state)
    local s = vim.deepcopy(state.scheduler or { state = "stopped" })
    if opts and opts.guard and not opts.guard(s) then out = s; return nil end
    for k, v in pairs(changes) do if v == vim.NIL then s[k] = nil else s[k] = v end end
    s.updated_at = U.now_iso()
    out = s
    return { { type = "scheduler.changed", payload = { scheduler = s, changed = vim.tbl_keys(changes) } } }
  end)
  return out
end

return O
