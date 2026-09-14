-- Live task picker (SDD-060): subscribes to store updates while open, preserves query/selection,
-- cancellable previews, Enter opens the inspector.
local M = {}
local function A() return require("aiswarm") end
local store = require("aiswarm.store")
local T = require("aiswarm.ui.text")
local H = require("aiswarm.ui.highlights")
local loader = require("aiswarm.ui.loader")

local function items()
  local out = {}
  local g = store.grouped()
  for _, name in ipairs(store.GROUPS) do
    for _, t in ipairs(g.groups[name]) do
      out[#out + 1] = { id = t.id, text = table.concat({ t.id, t.title or "", t.state, t.provider or "", t.display or "" }, " "), task = t, group = name, revision = t.revision }
    end
  end
  return out
end

local function format(item)
  local t = store.task(item.id) or item.task
  local icons = T.icons()
  local icon = t.state == "queued" and t.blockers and #t.blockers > 0 and icons.blocked or icons[t.state] or "?"
  return {
    { icon .. " ", H.for_task(t) },
    { T.fit(t.id, 9), "AISwarmId" },
    { T.fit(t.provider or "", 8), "AISwarmProvider" },
    { T.fit(t.display or t.state, 14), H.for_task(t) },
    { T.sanitize(t.title or ""), (t.state == "succeeded" or t.state == "cancelled") and "AISwarmMuted" or "Normal" },
  }
end

local function preview(ctx)
  local item = ctx.item
  if not item then return end
  local t = store.task(item.id)
  if not t then ctx.preview:set_lines({ "(task no longer exists)" }); return end
  local I = require("aiswarm.ui.inspector")
  local attempt = store.current_attempt(t.id)
  local paths = I.paths(t, attempt)
  ctx.preview:set_title(t.id .. " · " .. (t.display or t.state))
  ctx.preview:set_lines({ "loading…" })
  local picker = ctx.picker
  local function is_current()
    if not picker or picker.closed then return false end
    local cur = picker:current()
    return type(cur) == "table" and cur.id == item.id
  end
  loader.read(paths.stdout, { max_bytes = 64 * 1024, tail = true, is_current = is_current }, function(res)
    if res.status == "content" then
      local lines = vim.split(T.sanitize(res.text or ""), "\n", { plain = true })
      ctx.preview:set_lines(lines)
    elseif res.status == "missing" then
      loader.read(paths.report, { max_bytes = 64 * 1024, is_current = is_current }, function(r2)
        if r2.status == "content" then ctx.preview:set_lines(vim.split(r2.text, "\n", { plain = true })); ctx.preview:highlight({ ft = "markdown" })
        else ctx.preview:set_lines({ t.state == "running" and "(no output yet)" or "(no output or report for this task)" }) end
      end)
    elseif res.status == "empty" then ctx.preview:set_lines({ "(zero bytes of output)" })
    else ctx.preview:set_lines({ "read failed: " .. tostring(res.error) }) end
  end)
end

--- Open the picker. opts.on_select(task_id) overrides the default inspect action.
function M.pick(opts)
  opts = opts or {}
  if not pcall(require, "snacks") then return A().err("snacks.nvim is required") end
  local unsub
  local picker = Snacks.picker.pick({
    title = opts.prompt or "aiswarm tasks",
    finder = function() return items() end,
    format = format,
    preview = preview,
    confirm = function(p, item)
      if not item then return end
      local id = item.id
      p:close()
      if not store.task(id) then return A().warn("Task changed; review current state (" .. id .. " no longer exists)") end
      if opts.on_select then return opts.on_select(id) end
      require("aiswarm.ui.workspace").inspect(id, nil, "overview")
    end,
    actions = {
      aiswarm_output = function(p, item) if item then p:close(); require("aiswarm.ui.workspace").inspect(item.id, nil, "output") end end,
      aiswarm_report = function(p, item) if item then p:close(); require("aiswarm.ui.workspace").inspect(item.id, nil, "report") end end,
      aiswarm_cancel = function(p, item) if item then local actions = require("aiswarm.ui.actions"); actions.run("cancel", actions.target(item.id)) end end,
      aiswarm_retry = function(p, item) if item then local actions = require("aiswarm.ui.actions"); actions.run("retry", actions.target(item.id)) end end,
      aiswarm_attach = function(p, item) if item then p:close(); local actions = require("aiswarm.ui.actions"); actions.run("attach", actions.target(item.id)) end end,
    },
    win = { input = { keys = {
      ["<c-t>"] = { "aiswarm_output", mode = { "n", "i" }, desc = "output" },
      ["<c-r>"] = { "aiswarm_report", mode = { "n", "i" }, desc = "report" },
      ["<c-x>"] = { "aiswarm_cancel", mode = { "n", "i" }, desc = "cancel" },
      ["<c-y>"] = { "aiswarm_retry", mode = { "n", "i" }, desc = "retry" },
      ["<c-g>"] = { "aiswarm_attach", mode = { "n", "i" }, desc = "attach" },
    } } },
    on_close = function() if unsub then unsub(); unsub = nil end; M.current = nil end,
  })
  M.current = picker
  unsub = store.subscribe(function(change)
    if change.kind == "activity" or change.kind == "connection" then return end
    if picker.closed then return end
    -- re-run the finder; Snacks keeps the input pattern and re-matches
    vim.schedule(function() if not picker.closed then picker:find({ refresh = true }) end end)
  end)
  return picker
end

return M
