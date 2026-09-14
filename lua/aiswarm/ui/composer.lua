-- Prompt-first composer with validated fields, durable drafts and atomic submit (SDD-061–064).
local M = { open_bufs = {} }
local function A() return require("aiswarm") end
local store = require("aiswarm.store")
local P = require("aiswarm.protocol")
local registry = require("aiswarm.providers.registry")
local backend = require("aiswarm.backend")
local project = require("aiswarm.project")
local ns = vim.api.nvim_create_namespace("aiswarm-composer")
local diag_ns = vim.api.nvim_create_namespace("aiswarm-composer-diagnostics")

M.FIELDS = { "Title", "Provider", "Isolation", "Dependencies", "Priority", "Timeout" }
M.ADVANCED = { Dependencies = true, Priority = true, Timeout = true }
M.DRAFT_DEBOUNCE_MS = 500
M.SEPARATOR = "--- prompt below this line -------------------------------------------"

-- ---------------------------------------------------------------- drafts (SDD-063)
local function draft_dir()
  local root = project.root() or (A()._resolved or {}).root or "none"
  local key = vim.fn.sha256(root):sub(1, 12)
  local dir = vim.fn.stdpath("state") .. "/aiswarm/drafts/" .. key
  vim.fn.mkdir(dir, "p")
  return dir, root
end
function M.drafts()
  local dir, root = draft_dir()
  local out = {}
  for _, f in ipairs(vim.fn.glob(dir .. "/*.json", false, true)) do
    local ok, d = pcall(vim.json.decode, table.concat(vim.fn.readfile(f), "\n"), { luanil = { object = true, array = true } })
    if ok and type(d) == "table" and d.root == root then d.path = f; out[#out + 1] = d end
  end
  table.sort(out, function(a, b) return (a.updated_at or "") > (b.updated_at or "") end)
  return out
end
local function save_draft(state)
  local dir, root = draft_dir()
  if root ~= state.root then return end -- never write a draft of one project into another
  local data = vim.deepcopy(state.fields)
  data.prompt, data.root, data.draft_id, data.updated_at = state.prompt, state.root, state.draft_id, os.date("!%Y-%m-%dT%H:%M:%SZ")
  data.mode, data.task_id, data.expected_revision, data.source = state.mode, state.task_id, state.expected_revision, state.source
  local path = dir .. "/" .. state.draft_id .. ".json"
  local tmp = path .. ".tmp"
  vim.fn.writefile({ vim.json.encode(data) }, tmp)
  vim.uv.fs_rename(tmp, path)
  state.draft_path = path
end
function M.discard_draft(draft_id)
  local dir = draft_dir()
  os.remove(dir .. "/" .. draft_id .. ".json")
end

-- ---------------------------------------------------------------- buffer text <-> fields
function M.render_lines(fields, prompt_lines)
  local lines = {
    "Title:        " .. (fields.Title or ""),
    "Provider:     " .. (fields.Provider or registry.default()),
    "Isolation:    " .. (fields.Isolation or "shared"),
    "Dependencies: " .. (fields.Dependencies or ""),
    "Priority:     " .. tostring(fields.Priority or 50),
    "Timeout:      " .. tostring(fields.Timeout or 1800),
    M.SEPARATOR,
  }
  vim.list_extend(lines, prompt_lines or { "" })
  return lines
end

--- Parse the buffer into fields and prompt. Pure.
function M.parse(lines)
  local fields, prompt, in_prompt, lnums = {}, {}, false, {}
  for i, line in ipairs(lines) do
    if in_prompt then prompt[#prompt + 1] = line
    elseif line == M.SEPARATOR or line:match("^%-%-%- prompt below") then in_prompt = true
    else
      local k, v = line:match("^(%a+):%s*(.-)%s*$")
      if k and vim.tbl_contains(M.FIELDS, k) then fields[k], lnums[k] = v, i
      elseif vim.trim(line) ~= "" then return nil, nil, "unexpected line before the prompt separator: " .. line, i end
    end
  end
  if not in_prompt then return nil, nil, "missing prompt separator line", #lines end
  return fields, prompt, nil, lnums
end

--- Validate parsed fields with the shared schema plus local availability checks.
---@return table? normalized, {field: string, message: string}[] errors
function M.validate(fields, prompt, opts)
  opts = opts or {}
  local errors = {}
  local providers = {}
  for _, id in ipairs(registry.ids()) do providers[id] = true end
  local norm, err, field = P.check_task_fields({ id = opts.task_id, title = fields.Title, provider = fields.Provider ~= "" and fields.Provider or nil,
    priority = fields.Priority ~= "" and fields.Priority or nil, timeout = fields.Timeout ~= "" and fields.Timeout or nil,
    isolation = fields.Isolation ~= "" and fields.Isolation or nil, depends_on = fields.Dependencies }, { providers = providers })
  if not norm then
    local map = { title = "Title", provider = "Provider", priority = "Priority", timeout = "Timeout", isolation = "Isolation", depends_on = "Dependencies" }
    errors[#errors + 1] = { field = map[field] or "Title", message = err }
  else
    local probe = registry.probe(norm.provider)
    if not probe.available then errors[#errors + 1] = { field = "Provider", message = ("%s is unavailable (%s not found on PATH)"):format(norm.provider, tostring(registry.executable(norm.provider))) } end
    for _, d in ipairs(norm.depends_on) do
      if not store.task(d) then errors[#errors + 1] = { field = "Dependencies", message = "unknown dependency: " .. d } end
    end
    if opts.task_id then
      local ok, gerr = P.check_dependency_graph(opts.task_id, norm.depends_on, store.tasks)
      if not ok then errors[#errors + 1] = { field = "Dependencies", message = gerr } end
    end
    if norm.isolation == "worktree" and not opts.skip_isolation_check then
      local dir = vim.env.AISWARM_WORKTREES
      if not dir or dir == "" then errors[#errors + 1] = { field = "Isolation", message = "worktree isolation needs AISWARM_WORKTREES (or the board's worktrees_dir); shared mode must be chosen explicitly" } end
    end
  end
  if vim.trim(table.concat(prompt or {}, "\n")) == "" then errors[#errors + 1] = { field = "prompt", message = "prompt is empty" } end
  return norm, errors
end

--- Effective working directory description for display.
function M.effective_cwd(fields)
  local base = project.root() and vim.fs.dirname(project.root()) or vim.uv.cwd()
  if fields.Isolation == "worktree" then
    local dir = vim.env.AISWARM_WORKTREES
    return dir and (dir .. "/<task-id> (git worktree)") or "worktree (needs AISWARM_WORKTREES)"
  end
  return base .. " (shared)"
end

-- ---------------------------------------------------------------- legacy #: import/export (SDD-064)
function M.import_legacy(lines)
  local U = require("aiswarm.legacy.ui")
  local f, prompt, body = {}, {}, false
  for _, line in ipairs(lines) do
    if body then prompt[#prompt + 1] = line
    elseif line == "---" then body = true
    else local k, v = line:match("^#:%s*(%w+)%s*=%s*(.-)%s*$"); if k then f[k] = v end end
  end
  return { Title = f.title or "", Provider = f.provider or registry.default(), Isolation = f.worktree == "true" and "worktree" or "shared",
    Dependencies = f.deps or "", Priority = f.priority or "50", Timeout = f.timeout or "1800", Id = f.id }, prompt
end
function M.export_legacy(fields, prompt)
  local lines = { "# aiswarm task (legacy #: form)", "#: id = " .. (fields.Id or ""), "#: title = " .. (fields.Title or ""), "#: provider = " .. (fields.Provider or ""),
    "#: deps = " .. (fields.Dependencies or ""), "#: priority = " .. tostring(fields.Priority or 50), "#: worktree = " .. tostring(fields.Isolation == "worktree"),
    "#: timeout = " .. tostring(fields.Timeout or 1800), "---" }
  vim.list_extend(lines, prompt)
  return lines
end

-- ---------------------------------------------------------------- UI
local function state_of(buf) return M.open_bufs[buf] end

local function show_errors(buf, errors)
  local diags = {}
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local _, _, _, lnums = M.parse(lines)
  local first
  for _, e in ipairs(errors) do
    local lnum = (type(lnums) == "table" and lnums[e.field]) or (#lines)
    if e.field == "prompt" then for i, l in ipairs(lines) do if l == M.SEPARATOR then lnum = math.min(#lines, i + 1) end end end
    diags[#diags + 1] = { lnum = lnum - 1, col = 0, message = e.message, severity = vim.diagnostic.severity.ERROR, source = "aiswarm" }
    first = first or lnum
  end
  vim.diagnostic.set(diag_ns, buf, diags)
  return first
end

function M.collect(buf)
  local st = state_of(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fields, prompt, err, at = M.parse(lines)
  if not fields then return nil, { { field = "prompt", message = err } } end
  st.fields, st.prompt = fields, table.concat(prompt, "\n")
  return fields, prompt
end

function M.autosave(buf)
  local st = state_of(buf); if not st then return end
  if st.timer then st.timer:stop(); st.timer:close() end
  st.timer = vim.uv.new_timer()
  st.timer:start(M.DRAFT_DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    if st.timer then st.timer:close(); st.timer = nil end
    if not vim.api.nvim_buf_is_valid(buf) or st.closed then return end
    local f = M.collect(buf)
    if f then save_draft(st); st.saved = true end
  end))
end
function M.flush_draft(buf)
  local st = state_of(buf); if not st or st.closed then return end
  if st.timer then st.timer:stop(); st.timer:close(); st.timer = nil end
  if M.collect(buf) then save_draft(st); st.saved = true end
end

--- Submit: validated add or edit; keeps input and focuses the first error on failure.
function M.submit(buf)
  local st = state_of(buf); if not st then return end
  if st.submitting then return A().warn("submission already in progress") end
  if st.root ~= project.root() then return A().err("project changed; this draft belongs to " .. tostring(st.root)) end
  local fields, prompt = M.collect(buf)
  if not fields then show_errors(buf, prompt); return A().err(prompt[1].message) end
  local norm, errors = M.validate(fields, prompt, { task_id = st.task_id, skip_isolation_check = true })
  if #errors > 0 then
    local first = show_errors(buf, errors)
    if first then pcall(vim.api.nvim_win_set_cursor, 0, { first, 0 }) end
    return A().err(errors[1].field .. ": " .. errors[1].message)
  end
  vim.diagnostic.reset(diag_ns, buf)
  if not store.capability("atomic_add") and st.mode == "new" then return A().err("task creation requires the bundled aiswarm CLI with atomic_add support") end
  st.submitting = true
  local tmp = vim.fn.tempname()
  vim.fn.writefile(prompt, tmp)
  local args
  if st.mode == "edit" then
    args = { "set", st.task_id, "--expect-revision", tostring(st.expected_revision), "--title", norm.title, "--provider", norm.provider, "--priority", tostring(norm.priority),
      "--timeout", tostring(norm.timeout), "--isolation", norm.isolation, "--deps", table.concat(norm.depends_on, ","), "--file", tmp }
  else
    args = { "add", "--title", norm.title, "--provider", norm.provider, "--priority", tostring(norm.priority), "--timeout", tostring(norm.timeout), "--isolation", norm.isolation, "--file", tmp }
    if st.fields.Id and st.fields.Id ~= "" then vim.list_extend(args, { "--id", st.fields.Id }) end
    for _, d in ipairs(norm.depends_on) do vim.list_extend(args, { "--dep", d }) end
    if st.source and st.source.path then vim.list_extend(args, { "--source", st.source.path .. ":" .. tostring(st.source.line1) .. "-" .. tostring(st.source.line2) }) end
  end
  M.stats.submits = (M.stats.submits or 0) + 1
  backend.call(args, { json = store.capability("attempts"), timeout_ms = 30000 }, function(res)
    os.remove(tmp)
    st.submitting = false
    if res.stale then return end
    if not res.ok then
      -- keep the draft, surface the backend error inline
      local field = "Title"
      local msg = tostring(res.error or "backend rejected the task")
      if msg:match("[Dd]ependen") or msg:match("cycle") then field = "Dependencies" elseif msg:match("provider") then field = "Provider" elseif msg:match("priority") then field = "Priority" elseif msg:match("timeout") then field = "Timeout" elseif msg:match("worktree") or msg:match("isolation") then field = "Isolation" elseif msg:match("prompt") then field = "prompt" end
      local first = show_errors(buf, { { field = field, message = msg } })
      if first and vim.api.nvim_get_current_buf() == buf then pcall(vim.api.nvim_win_set_cursor, 0, { first, 0 }) end
      return A().err(msg)
    end
    local id = st.task_id
    if type(res.data) == "table" then id = res.data.id or id else id = vim.trim(tostring(res.data or "")):match("%S+") or id end
    M.discard_draft(st.draft_id)
    st.closed = true
    if vim.api.nvim_buf_is_valid(buf) then vim.bo[buf].modified = false end
    if st.win and st.win:valid() then st.win:close() end
    A().notify((st.mode == "edit" and "updated " or "queued ") .. tostring(id))
    A().refresh(function()
      local ws = require("aiswarm.ui.workspace")
      if id and ws.is_open() then require("aiswarm.view_state").select(id); ws.render_all() end
      if id and st.select_after ~= false and not ws.is_open() and st.open_workspace then ws.open({ task = id }) end
    end)
  end)
end

--- Open the composer. opts: { prefill?: string[], edit?: task_id, draft?: draft table, legacy_lines?: string[], source?: {path, line1, line2} }
function M.open(opts)
  opts = opts or {}
  if not pcall(require, "snacks") then return A().err("snacks.nvim is required") end
  local root = project.root()
  if not root then return A().err("no board is open; run :AISwarm init or :AISwarm project") end
  local st = { root = root, mode = "new", fields = {}, prompt = "", draft_id = tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999)), source = opts.source }
  local prompt_lines = opts.prefill or { "" }
  if opts.edit then
    local t = store.task(opts.edit)
    if not t then return A().err("no such task: " .. opts.edit) end
    if t.state ~= "queued" then return A().err(opts.edit .. " is " .. t.state .. "; only queued tasks can be edited") end
    st.mode, st.task_id, st.expected_revision = "edit", t.id, t.revision
    st.fields = { Title = t.title, Provider = t.provider, Isolation = t.isolation, Dependencies = table.concat(t.depends_on or {}, ", "), Priority = tostring(t.priority), Timeout = tostring(t.timeout) }
    local text = t.prompt_path and vim.uv.fs_stat(t.prompt_path) and table.concat(vim.fn.readfile(t.prompt_path), "\n") or ""
    prompt_lines = vim.split(text, "\n", { plain = true })
  elseif opts.legacy_lines then
    st.fields, prompt_lines = M.import_legacy(opts.legacy_lines)
  elseif opts.draft then
    local d = opts.draft
    st.draft_id, st.mode, st.task_id, st.expected_revision, st.source = d.draft_id, d.mode or "new", d.task_id, d.expected_revision, d.source
    st.fields = { Title = d.Title, Provider = d.Provider, Isolation = d.Isolation, Dependencies = d.Dependencies, Priority = d.Priority, Timeout = d.Timeout, Id = d.Id }
    prompt_lines = vim.split(d.prompt or "", "\n", { plain = true })
  elseif not opts.prefill then
    local drafts = M.drafts()
    if drafts[1] and not opts.fresh then return M.open(vim.tbl_extend("force", opts, { draft = drafts[1] })) end
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.render_lines(st.fields, prompt_lines))
  vim.api.nvim_buf_set_name(buf, "aiswarm://compose/" .. st.draft_id)
  M.open_bufs[buf] = st
  local title = st.mode == "edit" and (" edit " .. st.task_id .. " (revision " .. st.expected_revision .. ") ") or " new aiswarm task "
  local win
  win = Snacks.win({
    buf = buf, width = 0.75, height = 0.7, border = "rounded", title = title, title_pos = "center", enter = true, zindex = Snacks.win.zindex(60),
    footer = " Ctrl-s / :w queue   Esc keep draft   Ctrl-p provider   Ctrl-d dependencies   Ctrl-a advanced   Ctrl-e export #: form   Ctrl-q discard draft ", footer_pos = "center",
    bo = { buftype = "acwrite", filetype = "markdown", bufhidden = "wipe" }, wo = { wrap = true, number = false, foldenable = true, foldmethod = "manual", foldlevel = 0 },
    keys = {
      ["<c-s>"] = { function() M.submit(buf) end, mode = { "n", "i" }, desc = "queue task" },
      ["<esc>"] = { function() M.flush_draft(buf); win:close() end, mode = { "n" }, desc = "close, keep draft" },
      ["<c-p>"] = { function() M.pick_provider(buf) end, mode = { "n", "i" }, desc = "provider" },
      ["<c-d>"] = { function() M.pick_dependencies(buf) end, mode = { "n", "i" }, desc = "dependencies" },
      ["<c-a>"] = { function() M.toggle_advanced(buf) end, mode = { "n", "i" }, desc = "advanced" },
      ["<c-e>"] = { function() M.export(buf) end, mode = { "n" }, desc = "export #: form" },
      ["<c-q>"] = { function() require("aiswarm.ui.actions").confirm("Discard this draft?", function(yes) if yes then st.closed = true; M.discard_draft(st.draft_id); win:close() end end) end, mode = { "n" }, desc = "discard draft" },
    },
    on_close = function() if not st.closed then M.flush_draft(buf) end; M.open_bufs[buf] = nil end,
  })
  st.win, st.buf = win, buf
  vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = buf, callback = function() M.submit(buf) end })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { buffer = buf, callback = function() M.autosave(buf) end })
  M.render_hints(buf)
  -- advanced fields start collapsed (fold over Dependencies/Priority/Timeout)
  pcall(vim.api.nvim_win_call, win.win, function() vim.cmd("silent! 4,6fold") end)
  st.advanced = false
  local sep = 7
  local target = st.mode == "edit" and sep + 1 or (opts.prefill and sep + #prompt_lines or sep + 1)
  pcall(vim.api.nvim_win_set_cursor, win.win, { target, 0 })
  if st.mode ~= "edit" and not opts.prefill then vim.cmd.startinsert({ bang = true }) end
  return buf
end

function M.render_hints(buf)
  local st = state_of(buf); if not st then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local fields = M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) or {}
  local prov = fields.Provider or ""
  local probe = registry.valid(prov) and registry.probe(prov) or { available = false }
  local hint = registry.valid(prov) and (probe.available and (prov == "mock" and "simulated execution" or "available") or ("unavailable: " .. tostring(registry.executable(prov)) .. " not on PATH")) or "unknown provider"
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { virt_text = { { "  " .. hint, probe.available and "AISwarmMuted" or "AISwarmBlocked" } }, virt_text_pos = "eol" })
  vim.api.nvim_buf_set_extmark(buf, ns, 2, 0, { virt_text = { { "  runs in " .. M.effective_cwd(fields), "AISwarmMuted" } }, virt_text_pos = "eol" })
  vim.api.nvim_buf_set_extmark(buf, ns, 3, 0, { virt_text = { { "  ids separated by commas; Ctrl-d picks", "AISwarmMuted" } }, virt_text_pos = "eol" })
end

function M.toggle_advanced(buf)
  local st = state_of(buf); if not st or not st.win or not st.win:valid() then return end
  st.advanced = not st.advanced
  pcall(vim.api.nvim_win_call, st.win.win, function() vim.cmd(st.advanced and "silent! 4,6foldopen" or "silent! 4,6foldclose") end)
end

local function set_field(buf, name, value)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, l in ipairs(lines) do
    if l:match("^" .. name .. ":") then vim.api.nvim_buf_set_lines(buf, i - 1, i, false, { ("%-13s %s"):format(name .. ":", value) }); M.render_hints(buf); M.autosave(buf); return end
  end
end

function M.pick_provider(buf)
  local items = registry.list()
  local labels = {}
  for _, p in ipairs(items) do labels[#labels + 1] = ("%-8s %s%s"):format(p.id, p.available and "available" or "unavailable", p.id == "mock" and " (simulated, no tokens)" or "") end
  vim.ui.select(labels, { prompt = "provider" }, function(_, idx) if idx then set_field(buf, "Provider", items[idx].id) end end)
end

function M.pick_dependencies(buf)
  local st = state_of(buf)
  local candidates = {}
  for _, t in pairs(store.tasks) do if t.id ~= st.task_id then candidates[#candidates + 1] = t end end
  table.sort(candidates, function(a, b) return a.id < b.id end)
  if #candidates == 0 then return A().notify("no other tasks to depend on") end
  local current = {}
  local fields = M.parse(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) or {}
  for d in (fields.Dependencies or ""):gmatch("[^,%s]+") do current[d] = true end
  local labels = {}
  for _, t in ipairs(candidates) do labels[#labels + 1] = ("%s %-8s %-10s %s"):format(current[t.id] and "[x]" or "[ ]", t.id, t.state, t.title or "") end
  vim.ui.select(labels, { prompt = "toggle dependency (select repeatedly)" }, function(_, idx)
    if not idx then return end
    local id = candidates[idx].id
    current[id] = not current[id] or nil
    local list = {}
    for d in pairs(current) do list[#list + 1] = d end
    table.sort(list)
    set_field(buf, "Dependencies", table.concat(list, ", "))
  end)
end

function M.export(buf)
  local fields, prompt = M.collect(buf)
  if not fields then return end
  local nb = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(nb, 0, -1, false, M.export_legacy(fields, prompt))
  vim.bo[nb].filetype = "markdown"
  vim.api.nvim_set_current_buf(nb)
end

M.stats = { submits = 0 }
return M
