-- Combined activity feed (SDD-066): typed/provenanced records, filters, pinned scope, follow/unread.
local M = { rows = {} }
local function A() return require("aiswarm") end
local store = require("aiswarm.store")
local V = require("aiswarm.view_state")
local T = require("aiswarm.ui.text")
local R = require("aiswarm.ui.render")
local ns = vim.api.nvim_create_namespace("aiswarm-activity")
local function ws() return require("aiswarm.ui.workspace") end

function M.scope()
  local f = V.feed.filters
  local scope = { min_level = f.min_level, show_hidden = f.show_hidden, text = f.text, provider = f.provider, kinds = f.kinds }
  if V.feed.pinned then scope.task_id, scope.attempt_id = V.feed.pinned.task_id, V.feed.pinned.attempt_id end
  return scope
end

M.VIEW_LINES = 600   -- rendered tail; the store keeps 2,000 records, the filter reaches all of them

function M.build(width)
  local all = store.activity_for(M.scope())
  local recs = all
  local hidden_older = 0
  if #all > M.VIEW_LINES then recs = {}; for i = #all - M.VIEW_LINES + 1, #all do recs[#recs + 1] = all[i] end; hidden_older = #all - M.VIEW_LINES end
  local lines, rows = {}, {}
  local hdr = T.line()
  hdr:add("Activity · " .. (V.feed.pinned and ("pinned to " .. V.feed.pinned.task_id) or "All agents"), "AISwarmSection")
  if hidden_older > 0 then hdr:add(("   (latest %d of %d; narrow the filter for older records)"):format(#recs, #all), "AISwarmMuted") end
  hdr:add(V.feed.follow and "   Live" or ("   View paused · " .. tostring(V.feed.unread) .. " unread"), V.feed.follow and "AISwarmDone" or "AISwarmBlocked")
  if V.feed.filters.text ~= "" then hdr:add("   /" .. V.feed.filters.text, "AISwarmAccent") end
  if V.feed.filters.show_hidden then hdr:add("   verbose", "AISwarmMuted") end
  if store.activity.gap then hdr:add("   (older records evicted)", "AISwarmMuted") end
  lines[#lines + 1] = { hdr:build() }
  if #recs == 0 then lines[#lines + 1] = { "  no activity yet", { { 0, 20, "AISwarmMuted" } } } end
  for _, r in ipairs(recs) do
    local row = T.line()
    row:add(T.fit((r.ts or ""):match("T(%d%d:%d%d:%d%d)") or (r.ts or ""), 9), "AISwarmMuted")
    row:add(T.fit(r.task_id or "", 8), "AISwarmId")
    row:add(T.fit(r.provider or (store.task(r.task_id or "") or {}).provider or "", 8), "AISwarmProvider")
    row:add(T.fit(r.kind or "", 10), r.level == "error" and "AISwarmFailed" or r.level == "warn" and "AISwarmBlocked" or "AISwarmMuted")
    local text = T.sanitize(r.text or "")
    row:add(T.truncate(text, math.max(10, width - 44)), r.level == "error" and "AISwarmFailed" or "AISwarmValue")
    if r.count and r.count > 1 then row:add(("  ×%d"):format(r.count), "AISwarmMuted") end
    lines[#lines + 1] = { row:build() }
    rows[#lines] = { task_id = r.task_id, attempt_id = r.attempt_id }
  end
  return lines, rows, #recs
end

function M.render()
  local W = ws()
  local buf = W.buf("activity")
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local win = W.win_of("activity")
  local width = win and vim.api.nvim_win_get_width(win) or 100
  local lines, rows, n = M.build(width)
  if M.last_n and not V.feed.follow and n > M.last_n then V.feed.unread = V.feed.unread + (n - M.last_n) end
  M.last_n = n
  M.rows = rows
  local saved = win and vim.api.nvim_win_get_cursor(win) or nil
  M._setting = true
  T.set_lines(buf, ns, lines)
  if win then
    if V.feed.follow then pcall(vim.api.nvim_win_set_cursor, win, { #lines, 0 })
    elseif saved then pcall(vim.api.nvim_win_set_cursor, win, { math.min(saved[1], #lines), saved[2] }) end
  end
  M._setting = false
  if M._watch_buf ~= buf then
    M._watch_buf = buf
    vim.api.nvim_create_autocmd("CursorMoved", { buffer = buf, callback = function()
      if M._setting then return end
      local w = ws().win_of("activity"); if not w then return end
      if V.feed.follow and vim.api.nvim_win_get_cursor(w)[1] < vim.api.nvim_buf_line_count(buf) then V.feed.follow, V.feed.unread = false, 0; R.mark("activity"); ws().update_chrome() end
    end })
  end
  W.update_chrome()
end

function M.toggle_follow() V.feed.follow = not V.feed.follow; V.feed.unread = 0; R.mark("activity") end
function M.jump_end() V.feed.follow, V.feed.unread = true, 0; R.mark("activity") end
function M.toggle_verbose() V.feed.filters.show_hidden = not V.feed.filters.show_hidden; V.feed.filters.min_level = V.feed.filters.show_hidden and "debug" or "info"; R.mark("activity") end
function M.prompt_filter()
  vim.ui.input({ prompt = "filter activity (text, task:ID, provider:NAME, kind:K, level:L): ", default = V.feed.filters.text }, function(text)
    if text == nil then return end
    local f = { min_level = "info", show_hidden = V.feed.filters.show_hidden, text = "" }
    for word in text:gmatch("%S+") do
      local k, v = word:match("^(%w+):(.+)$")
      if k == "task" then V.feed.pinned = { task_id = v }
      elseif k == "provider" then f.provider = v
      elseif k == "kind" then f.kinds = f.kinds or {}; f.kinds[v] = true
      elseif k == "level" then f.min_level = v
      else f.text = (f.text == "" and word) or (f.text .. " " .. word) end
    end
    if text == "" then V.feed.pinned = nil end
    V.feed.filters = f
    R.mark("activity")
  end)
end
function M.pin_scope()
  if V.feed.pinned then V.feed.pinned = nil else V.feed.pinned = { task_id = V.selected.task_id } end
  R.mark("activity")
end
function M.enter()
  local win = ws().win_of("activity"); if not win then return end
  local entry = M.rows[vim.api.nvim_win_get_cursor(win)[1]]
  if entry and entry.task_id and store.task(entry.task_id) then ws().inspect(entry.task_id, entry.attempt_id, "activity") end
end

return M
