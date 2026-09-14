local H = function() return require("aiswarm") end
local S = function() return require("aiswarm.legacy.state") end

local U = {}
local ns = vim.api.nvim_create_namespace("aiswarm")

local GLYPH = {
  active = { "●", "DiagnosticWarn" },
  ready  = { "○", "Comment" },
  done   = { "✓", "DiagnosticOk" },
  failed = { "✗", "DiagnosticError" },
}

local function strip_ansi(s)
  return (s:gsub("\27%[[%d;?]*[%a]", ""):gsub("\r", ""))
end

local function fmt_time(t)
  local s = t.elapsed_s or t.duration_s
  if not s then return "-" end
  if s < 90 then return s .. "s" end
  return string.format("%dm", math.floor(s / 60))
end

local function fmt_cost(t)
  if not t.cost_usd then return "" end
  return string.format("$%.2f", t.cost_usd)
end

local function need_snacks()
  if not package.loaded["snacks"] then
    local ok = pcall(require, "snacks")
    if not ok then H().err("snacks.nvim is required for the UI"); return false end
  end
  return true
end

-- ---------------------------------------------------------------- actions
function U.go(id)
  if not id then return end
  if not vim.env.TMUX then return H().warn("not inside tmux; run: tmux attach -t agent-" .. id) end
  local ok, err = pcall(vim.system, { "tmux", "switch-client", "-t", "agent-" .. id }, {}, vim.schedule_wrap(function(o)
    if o.code ~= 0 then H().warn("no live session for " .. id .. " (try :HiveTail)") end
  end))
  if not ok then H().err(tostring(err)) end
end

function U.kill(id)
  if not id then return end
  H().run({ "kill", id }, function(o)
    if o.code ~= 0 then return H().err(H().failure(o)) end
    H().notify("cancelled " .. id .. " and requeued it (legacy kill semantics)")
    S().refresh()
  end)
end

function U.toggle_pause()
  local paused = S().meta.paused
  H().run({ paused and "resume" or "pause" }, function(o)
    if o.code ~= 0 then return H().err(H().failure(o)) end
    S().refresh()
  end)
end

function U.tail(id)
  if not id or not need_snacks() then return end
  local cfg = H().config.tail
  Snacks.terminal(H().cmd({ "tail", id, "-f" }), {
    env = H().env(),
    interactive = false,
    win = { position = cfg.position, height = cfg.height, title = " aiswarm tail " .. id .. " ", title_pos = "center" },
  })
end

--- Current screen (live) or transcript tail (finished), ANSI stripped.
---@return string[]
function U.peek_lines(id, n)
  if not id then return { "(no task selected)" } end
  n = n or H().config.peek_lines
  local t = S().tasks[id]
  local args = (t and t.live) and { "peek", id, tostring(n) } or { "tail", id, "-n", tostring(n) }
  local started = vim.uv.hrtime()
  local out, code = H().run_sync(args, 1500)
  if t and t.live and (code ~= 0 or vim.trim(out) == "") then
    local remaining = 1500 - math.ceil((vim.uv.hrtime() - started) / 1e6)
    if remaining > 0 then out, code = H().run_sync({ "tail", id, "-n", tostring(n) }, remaining) end
  end
  if code ~= 0 or vim.trim(out) == "" then
    -- fall back to the result report if there is one
    local r = H().root() .. "/results/" .. id .. ".md"
    if vim.fn.filereadable(r) == 1 then return vim.fn.readfile(r), "markdown" end
    return { "(no output yet)" }, nil
  end
  return vim.split(strip_ansi(out), "\n", { trimempty = true }), nil
end

function U.peek(id)
  if not id or not need_snacks() then return end
  local lines = U.peek_lines(id)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local win = Snacks.win({
    buf = buf, width = 0.8, height = 0.7, border = "rounded",
    title = " " .. id .. " ", title_pos = "center",
    bo = { bufhidden = "wipe" }, wo = { wrap = false, cursorline = false },
    keys = { q = "close", ["<esc>"] = "close" },
  })
  vim.api.nvim_win_set_cursor(win.win, { math.max(1, #lines), 0 })
end

-- ---------------------------------------------------------------- picker
local function picker_items()
  local items = {}
  for _, t in ipairs(S().list()) do
    items[#items + 1] = {
      id = t.id, task = t,
      text = table.concat({ t.id, t.title or "", t.state, t.provider or "" }, " "),
    }
  end
  return items
end

local function picker_format(item)
  local t = item.task
  local g = GLYPH[t.state] or { "?", "Comment" }
  return {
    { g[1] .. " ", g[2] },
    { string.format("%-8s", t.id), "Title" },
    { string.format("%-8s", t.provider or ""), "Comment" },
    { string.format("%6s ", fmt_time(t)), "Number" },
    { t.title or "", t.state == "done" and "Comment" or "Normal" },
  }
end

local function picker_preview(ctx)
  if not ctx.item then return end
  local id = ctx.item.id
  local lines, ft = U.peek_lines(id, 60)
  ctx.preview:set_lines(lines)
  ctx.preview:set_title(id)
  if ft then ctx.preview:highlight({ ft = ft }) end
end

function U.pick()
  if not need_snacks() then return end
  S().refresh(function(snap)
    if not snap then return end
    Snacks.picker.pick({
      title = "aiswarm tasks",
      items = picker_items(),
      format = picker_format,
      preview = picker_preview,
      confirm = function(picker, item)
        if not item then return end
        picker:close()
        U.go(item.id)
      end,
      actions = {
        hive_tail = function(picker, item) if item then picker:close(); U.tail(item.id) end end,
        hive_peek = function(picker, item) if item then picker:close(); U.peek(item.id) end end,
        hive_kill = function(picker, item) if item then U.kill(item.id) end end,
        hive_result = function(picker, item)
          if not item then return end
          local path = H().root() .. "/results/" .. item.id .. ".md"
          if vim.fn.filereadable(path) == 0 then return H().warn("no report for " .. item.id) end
          picker:close()
          vim.cmd.edit(vim.fn.fnameescape(path))
        end,
      },
      win = {
        input = {
          keys = {
            ["<c-t>"] = { "hive_tail",   mode = { "n", "i" }, desc = "tail -f" },
            ["<c-p>"] = { "hive_peek",   mode = { "n", "i" }, desc = "peek" },
            ["<c-x>"] = { "hive_kill",   mode = { "n", "i" }, desc = "kill + requeue" },
            ["<c-r>"] = { "hive_result", mode = { "n", "i" }, desc = "open report" },
          },
        },
      },
    })
  end)
end

function U.results()
  if not need_snacks() then return end
  local items = {}
  for _, f in ipairs(vim.fn.glob(H().root() .. "/results/*.md", false, true)) do
    local id = vim.fn.fnamemodify(f, ":t:r")
    local t = S().tasks[id] or {}
    items[#items + 1] = { file = f, id = id, text = id .. " " .. (t.title or ""), task = t }
  end
  Snacks.picker.pick({
    title = "aiswarm results",
    items = items,
    format = function(item)
      local g = GLYPH[item.task.state or ""] or { " ", "Comment" }
      return { { g[1] .. " ", g[2] }, { item.id .. "  ", "Title" }, { item.task.title or "", "Normal" } }
    end,
    preview = "file",
  })
end

-- ---------------------------------------------------------------- dashboard
U._dash = nil

local function dash_lines()
  local m, lines, map, hl = S().meta, {}, {}, {}
  local paused = m.paused and "  [PAUSED]" or ""
  lines[1] = string.format(" aiswarm  %s   wip %s   seq %s%s", m.root or H().root(), m.wip or "?", m.seq or 0, paused)
  hl[1] = { { 0, -1, "Title" } }
  if m.paused then hl[1] = { { 0, #lines[1] - #paused, "Title" }, { #lines[1] - #paused, -1, "DiagnosticWarn" } } end
  local schema = require("aiswarm.project").schema(H().root())
  if m.error then
    lines[2] = " disconnected: " .. m.error:gsub("[\r\n]", " "); hl[2] = { { 0, -1, "DiagnosticError" } }
  elseif schema == "migrating" then
    lines[2] = " interrupted migration: :AISwarm migrate --resume (or --rollback) before using this board"; hl[2] = { { 0, -1, "DiagnosticWarn" } }
  elseif schema == "v2" then
    lines[2] = " legacy board (v2): no attempt history, cancel/retry or structured telemetry — :AISwarm migrate --dry-run to review the upgrade"; hl[2] = { { 0, -1, "DiagnosticWarn" } }
  else
    lines[2] = " " .. string.rep("─", 74); hl[2] = { { 0, -1, "Comment" } }
  end
  local list = S().list()
  if #list == 0 then
    lines[3] = "   (no tasks)  a: add   q: close"
    hl[3] = { { 0, -1, "Comment" } }
  end
  for i, t in ipairs(list) do
    local g = GLYPH[t.state] or { "?", "Comment" }
    local line = string.format(" %s %-8s %-8s %6s %7s  %s", g[1], t.id, t.provider or "", fmt_time(t), fmt_cost(t), t.title or "")
    if t.state == "active" and t.last_progress then
      local ago = math.floor((vim.uv.now() - t.last_progress) / 1000)
      line = line .. string.format("   (activity %ds ago)", ago)
    end
    local n = #lines + 1
    lines[n] = line
    map[n] = t.id
    hl[n] = { { 1, 4, g[2] }, { 3, 11, "Title" } }
    if t.state == "done" then hl[n] = { { 1, 4, g[2] }, { 3, -1, "Comment" } } end
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = " ⏎ go   t tail   p peek   x kill   a add   P pause   r refresh   R results   q close"
  hl[#lines] = { { 0, -1, "Comment" } }
  return lines, map, hl
end

function U.render()
  local d = U._dash
  if not d or not d.win:valid() then return end
  local buf = d.win.buf
  local lines, map, hl = dash_lines()
  d.map = map
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for lnum, spans in pairs(hl) do
    for _, sp in ipairs(spans) do
      vim.api.nvim_buf_set_extmark(buf, ns, lnum - 1, sp[1], { end_col = sp[2] == -1 and #lines[lnum] or sp[2], hl_group = sp[3] })
    end
  end
end

local function cursor_id()
  local d = U._dash
  if not d then return nil end
  local row = vim.api.nvim_win_get_cursor(d.win.win)[1]
  return d.map[row]
end

function U.dashboard()
  if not need_snacks() then return end
  if U._dash and U._dash.win:valid() then
    U._dash.win:focus()
    S().refresh()
    return
  end
  local cfg = H().config.dashboard
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].undolevels = -1
  local d = { map = {} }
  U._dash = d
  d.win = Snacks.win({
    buf = buf, width = cfg.width, height = cfg.height, border = "rounded",
    title = " aiswarm ", title_pos = "center",
    bo = { filetype = "aiswarm", bufhidden = "wipe", modifiable = false },
    wo = { cursorline = true, wrap = false, number = false, signcolumn = "no" },
    keys = {
      q = "close", ["<esc>"] = "close",
      ["<cr>"] = function(self) local id = cursor_id(); self:close(); U.go(id) end,
      t = function(self) local id = cursor_id(); self:close(); U.tail(id) end,
      p = function() U.peek(cursor_id()) end,
      x = function() U.kill(cursor_id()) end,
      a = function(self) self:close(); U.add_form() end,
      P = function() U.toggle_pause() end,
      r = function() S().refresh() end,
      R = function(self) self:close(); U.results() end,
    },
    on_close = function()
      if d.unsub then d.unsub() end
      U._dash = nil
    end,
  })
  d.unsub = S().subscribe(function(kind) if kind == "refresh" or kind == "error" or kind == "event" then U.render() end end)
  U.render()
  S().refresh()
  vim.api.nvim_win_set_cursor(d.win.win, { 3, 0 })
end

-- ---------------------------------------------------------------- new-task form
local FIELDS = { id = true, title = true, provider = true, deps = true, priority = true, worktree = true, timeout = true }
local registry = require("aiswarm.providers.registry")
local function valid_id(id) return id and id:match("^[A-Za-z0-9][A-Za-z0-9_-]*$") ~= nil end

local function next_id()
  local n = 0
  for id in pairs(S().tasks) do
    local k = tonumber(id:match("^T%-(%d+)$"))
    if k and k > n then n = k end
  end
  return string.format("T-%03d", n + 1)
end

function U.form_template(prefill)
  local lines = {
    "# aiswarm task — fill the fields, write the prompt below, then :w (or <C-s>) to queue it.",
    "#: id = " .. next_id(),
    "#: title = ",
    "#: provider = " .. registry.default(),
    "#: deps = ",
    "#: priority = 50",
    "#: worktree = false",
    "#: timeout = 1800",
    "---",
  }
  vim.list_extend(lines, prefill or { "" })
  return lines
end

--- Parse a form buffer into flags + prompt lines. Pure, testable.
---@return string[] args, string[] prompt, string? err
function U.parse_form(lines)
  local f, prompt, body = {}, {}, false
  for _, line in ipairs(lines) do
    if body then prompt[#prompt + 1] = line
    elseif line == "---" then body = true
    else
      local key, value = line:match("^#:%s*(%w+)%s*=%s*(.-)%s*$")
      if key then
        if not FIELDS[key] then return {}, {}, "unknown field: " .. key end
        if f[key] ~= nil then return {}, {}, "duplicate field: " .. key end
        f[key] = value
      elseif not line:match("^#") and line ~= "" then
        return {}, {}, "separate the header and prompt with ---"
      end
    end
  end
  if not body then return {}, {}, "missing --- before prompt" end
  if vim.trim(table.concat(prompt, "\n")) == "" then return {}, {}, "prompt is empty" end
  if not valid_id(f.id) then return {}, {}, "id must use letters, digits, underscores or hyphens" end
  if f.provider and f.provider ~= "" and not registry.valid(f.provider) then return {}, {}, "unknown provider" end
  if f.provider and f.provider ~= "" and not registry.probe(f.provider).available then
    return {}, {}, ("provider %s is unavailable (%s not found on PATH)"):format(f.provider, registry.executable(f.provider))
  end
  for _, key in ipairs({ "priority", "timeout" }) do
    local value = f[key]
    if value and value ~= "" and (not value:match("^%d+$") or (key == "timeout" and tonumber(value) == 0)) then
      return {}, {}, key .. " must be " .. (key == "timeout" and "a positive" or "a non-negative") .. " integer"
    end
  end
  if f.worktree and f.worktree ~= "true" and f.worktree ~= "false" then return {}, {}, "worktree must be true or false" end
  for dep in (f.deps or ""):gmatch("[^,%s]+") do
    if not valid_id(dep) or dep == f.id then return {}, {}, "invalid dependency: " .. dep end
  end
  local args = { "add", "--id", f.id }
  if f.title and f.title ~= "" then vim.list_extend(args, { "--title", f.title }) end
  if f.provider and f.provider ~= "" then vim.list_extend(args, { "--provider", f.provider }) end
  if f.priority and f.priority ~= "" then vim.list_extend(args, { "--priority", f.priority }) end
  if f.timeout and f.timeout ~= "" then vim.list_extend(args, { "--timeout", f.timeout }) end
  if f.worktree == "true" then args[#args + 1] = "--worktree" end
  for d in (f.deps or ""):gmatch("[^,%s]+") do vim.list_extend(args, { "--dep", d }) end
  return args, prompt, nil
end

function U.submit_form(buf, win)
  if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].hive_submitting then return end
  if vim.b[buf].hive_root and vim.b[buf].hive_root ~= H().root() then return H().err("project changed; open a new task form") end
  if not (S().meta.capabilities or {}).atomic_add then
    return H().err("task creation requires the bundled aiswarm CLI with atomic_add support")
  end
  local root = H().root()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local args, prompt, err = U.parse_form(lines)
  if err then return H().err(err) end
  local tmp = vim.fn.tempname()
  local ok, write_err = pcall(vim.fn.writefile, prompt, tmp)
  if not ok or write_err ~= 0 then return H().err("could not write prompt: " .. tostring(write_err)) end
  vim.b[buf].hive_submitting = true
  vim.list_extend(args, { "--file", tmp })
  H().run(args, function(o)
    os.remove(tmp)
    if vim.api.nvim_buf_is_valid(buf) then vim.b[buf].hive_submitting = false end
    if root ~= H().root() then return end
    if o.code ~= 0 then return H().err(H().failure(o)) end
    H().notify("queued " .. vim.trim(o.stdout))
    if vim.api.nvim_buf_is_valid(buf) then vim.bo[buf].modified = false end
    if win and win:valid() then win:close() end
    S().refresh()
  end)
end

local function open_form(prefill)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, U.form_template(prefill))
  vim.b[buf].hive_root = H().root()
  vim.api.nvim_buf_set_name(buf, "aiswarm://task/" .. buf)
  local win
  win = Snacks.win({
    buf = buf, width = 0.7, height = 0.6, border = "rounded",
    title = " new aiswarm task ", title_pos = "center",
    bo = { buftype = "acwrite", filetype = "markdown", bufhidden = "wipe" },
    wo = { wrap = true, number = false },
    keys = {
      ["<c-s>"] = { function() U.submit_form(buf, win) end, mode = { "n", "i" }, desc = "queue task" },
      ["<esc>"] = { "close", mode = { "n" } },
    },
  })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function() U.submit_form(buf, win) end,
  })
  vim.api.nvim_win_set_cursor(win.win, { #U.form_template(prefill), 0 })
  vim.cmd.startinsert({ bang = true })
end

function U.add_form(prefill)
  if not need_snacks() then return end
  S().refresh(function(snap) if snap then open_form(prefill) end end)
end

return U
