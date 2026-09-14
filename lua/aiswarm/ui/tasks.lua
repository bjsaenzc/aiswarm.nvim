-- Grouped task list renderer (SDD-051).
local T = require("aiswarm.ui.text")
local H = require("aiswarm.ui.highlights")
local M = {}
M.ns = vim.api.nvim_create_namespace("aiswarm-tasks")
M.LABEL = { running = "RUNNING", attention = "ATTENTION", queued = "QUEUED", finished = "FINISHED" }

local function state_icon(t, icons)
  if t.state == "queued" and t.blockers and #t.blockers > 0 then return icons.blocked end
  if t.state == "running" and t.display == "Starting" then return icons.starting end
  if t.state == "running" and t.health and (t.health.stale or t.health.input_required) then return icons.stale end
  if t.state == "failed" then return icons.failed end
  return icons[t.state] or "?"
end

local function activity_text(t, store)
  local a = store.current_attempt(t.id)
  local h = t.health or {}
  if t.state == "running" then
    if h.input_required then return "waiting for input" end
    if h.message then return h.message end
    if h.phase then return h.phase end
    if t.display_detail then return t.display_detail end
    return "no activity reported yet"
  elseif t.state == "queued" then
    return t.blockers and #t.blockers > 0 and t.blockers[1].text or ("priority " .. tostring(t.priority))
  else
    local o = t.outcome or {}
    local parts = {}
    if o.reason then parts[#parts + 1] = o.reason elseif o.exit_code then parts[#parts + 1] = "exit " .. o.exit_code end
    if o.report and o.report ~= "complete" then parts[#parts + 1] = "report " .. o.report end
    if a and a.imported then parts[#parts + 1] = "imported history" end
    return table.concat(parts, " · ")
  end
end

local function age_of(t, store)
  local h = t.health or {}
  if t.state == "running" then
    local since = h.output_at or h.activity_at
    local s = since and T.since_iso(since)
    if s then return T.age(s) .. " ago" end
    if t.elapsed_s then return T.duration(t.elapsed_s) end
    local a = store.current_attempt(t.id)
    local st = a and a.started_at and T.since_iso(a.started_at)
    return st and T.duration(st) or ""
  elseif t.state == "queued" then
    return ""
  else
    local o = t.outcome or {}
    local s = o.finished_at and T.since_iso(o.finished_at)
    return s and (T.age(s) .. " ago") or ""
  end
end

M._rows = {}   -- task id → { sig, primary = {text, spans}, secondary = {text, spans} }

local function row_signature(t, store, selected, width, compact)
  local h = t.health or {}
  local att = store.attention[t.id]
  return table.concat({ tostring(t.revision), t.state, t.display or "", t.display_detail or "", tostring(h.message), tostring(h.phase), tostring(h.output_at), tostring(h.activity_at),
    tostring(h.stale), tostring(h.input_required ~= nil), tostring(selected), tostring(width), tostring(compact), tostring(att and att.acknowledged), tostring(t.outcome and t.outcome.finished_at),
    tostring(t.blockers and t.blockers[1] and t.blockers[1].text), tostring(t.title), tostring(t.elapsed_s and math.floor(t.elapsed_s / 5)) }, "\1")
end

--- Build lines and a row map for the visible width. Returns lines, rowmap, visible_ids.
--- Rows are memoized by a signature of everything they display, so a redraw of a large list costs
--- only the rows that changed.
---@param opts { width: number, compact?: boolean, focused?: boolean }
function M.build(store, V, opts)
  local icons = T.icons()
  local width = math.max(20, opts.width or 60)
  local lines, rowmap, visible = {}, {}, {}
  local g = store.grouped(V.filter)
  local counts = store.counts()
  -- header: filter chips
  local header = T.line()
  local chips = { { "all", "All " .. counts.all }, { "running", "Running " .. counts.running }, { "queued", "Queued " .. counts.queued }, { "attention", "Attention " .. counts.attention }, { "finished", "Finished " .. counts.finished } }
  for i, c in ipairs(chips) do
    local active = V.filter.group == c[1]
    header:add(active and ("[" .. c[2] .. "]") or (" " .. c[2] .. " "), active and "AISwarmAccent" or "AISwarmMuted")
    if i < #chips then header:add(" ") end
  end
  if V.filter.text ~= "" then header:add("  /" .. V.filter.text, "AISwarmAccent") end
  lines[#lines + 1] = { header:build() }
  rowmap[#lines] = { header = true }
  local compact = opts.compact or width < 60
  for _, name in ipairs(store.GROUPS) do
    local list = g.groups[name]
    if #list > 0 or (V.filter.group == "all" and name ~= "attention") then
      local hdr = T.line()
      hdr:add((V.collapsed[name] and icons.collapsed or icons.expanded) .. " ", "AISwarmMuted")
      hdr:add(M.LABEL[name] .. " · " .. #list, name == "attention" and #list > 0 and "AISwarmAttention" or "AISwarmHeader")
      lines[#lines + 1] = { hdr:build() }
      rowmap[#lines] = { group = name }
      if not V.collapsed[name] then
        for _, t in ipairs(list) do
          local selected = V.selected.task_id == t.id
          local sig = row_signature(t, store, selected, width, compact)
          local cached = M._rows[t.id]
          if cached and cached.sig == sig then
            lines[#lines + 1] = cached.primary; rowmap[#lines] = { task_id = t.id, group = name, primary = true }; visible[#visible + 1] = t.id
            lines[#lines + 1] = cached.secondary; rowmap[#lines] = { task_id = t.id, group = name, secondary = true }
            goto continue
          end
          local row = T.line()
          row:add((selected and ">" or " ") .. " ", "AISwarmAccent")
          row:add(state_icon(t, icons) .. " ", H.for_task(t))
          row:add(T.fit(t.id, 8), "AISwarmId")
          local right = compact and "" or (T.fit(t.provider or "", 8) .. " " .. T.fit(age_of(t, store), 9, true))
          local title_w = width - 12 - T.width(right) - (compact and 0 or 2)
          local hl = (t.state == "succeeded" or t.state == "cancelled") and "AISwarmMuted" or "AISwarmValue"
          row:add(T.fit(T.sanitize(t.title or ""), math.max(6, title_w)), hl)
          if not compact then row:add("  " .. right, "AISwarmProvider") end
          local built, spans = row:build()
          lines[#lines + 1] = { built, spans }
          rowmap[#lines] = { task_id = t.id, group = name, primary = true }
          visible[#visible + 1] = t.id
          -- secondary line: explicit state text plus the latest meaningful detail
          local detail = T.line()
          local state_hl = H.for_task(t)
          detail:add("      " .. T.fit(t.display or t.state, 16), state_hl)
          if compact then detail:add(T.fit(t.provider or "", 7) .. " ", "AISwarmProvider") end
          local text = T.sanitize(activity_text(t, store))
          detail:add(T.truncate(text, math.max(4, width - 24)), t.state == "queued" and t.blockers and #t.blockers > 0 and "AISwarmBlocked" or "AISwarmMuted")
          if store.attention[t.id] and not store.attention[t.id].acknowledged then detail:add(" " .. icons.attention, "AISwarmAttention") end
          local b2, s2 = detail:build()
          lines[#lines + 1] = { b2, s2 }
          rowmap[#lines] = { task_id = t.id, group = name, secondary = true }
          M._rows[t.id] = { sig = sig, primary = lines[#lines - 1], secondary = lines[#lines] }
          ::continue::
        end
      end
      lines[#lines + 1] = { "" }
      rowmap[#lines] = { blank = true }
    end
  end
  if g.total == 0 then
    lines[#lines + 1] = { "   No tasks yet.", { { 0, 15, "AISwarmMuted" } } }
    lines[#lines + 1] = { "   n  compose a task        ?  actions", { { 0, 40, "AISwarmHint" } } }
  elseif g.shown == 0 then
    lines[#lines + 1] = { "   No task matches the filter (/ to change, / then <Esc> to clear).", { { 0, 70, "AISwarmMuted" } } }
  end
  return lines, rowmap, visible
end

--- First row (1-based) whose map entry is the primary row of task id.
function M.row_of(rowmap, task_id)
  for i, r in pairs(rowmap) do if r.task_id == task_id and r.primary then return i end end
  return nil
end

return M
