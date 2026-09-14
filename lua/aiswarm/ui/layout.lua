-- Responsive layout resolver and Snacks layout definitions (SDD-053, ADR 0004).
local L = {}

--- Total function over integer interior dimensions.
function L.resolve(w, h)
  if w < 40 or h < 12 then return "minimal" end
  if w < 80 or h < 24 then return "narrow" end
  if w >= 110 and h >= 28 then return "wide" end
  return "medium"
end

--- Interior size available to the workspace. Small terminals (< 120 columns or < 40 rows) get the
--- whole screen minus the border so the two-pane layout stays reachable; larger ones use the
--- configured fractions.
function L.interior(cfg)
  cfg = cfg or require("aiswarm").config.ui
  local cols, lines = vim.o.columns, vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)
  if cfg.layout == "editor" then
    return cols - 2, math.max(1, math.floor(lines * 0.45) - 2)
  end
  local w = cols < 120 and (cols - 2) or (math.floor(cols * cfg.width) - 2)
  local h = lines < 40 and (lines - 2) or (math.floor(lines * cfg.height) - 2)
  return math.max(1, w), math.max(1, h)
end

--- Pane geometry for a mode inside interior (w, h).
function L.geometry(mode, w, h)
  if mode == "wide" then
    local tray = math.max(5, math.floor(h * 0.25))
    return { tasks = math.max(30, math.floor(w * 0.35)), tray = tray, inspector = w - math.max(30, math.floor(w * 0.35)) - 1, body = h - tray - 1 }
  elseif mode == "medium" then
    return { tasks = math.max(30, math.floor(w * 0.38)), inspector = w - math.max(30, math.floor(w * 0.38)) - 1, body = h }
  end
  return { main = w, body = h }
end

--- Snacks layout box for a mode. `wins` names must match the workspace's window table.
function L.definition(mode, cfg)
  cfg = cfg or require("aiswarm").config.ui
  local w, h = L.interior(cfg)
  local g = L.geometry(mode, w, h)
  local root = { box = "vertical", border = "rounded", title = " aiswarm ", title_pos = "left", footer_pos = "left", backdrop = cfg.layout ~= "editor" and 60 or false }
  if cfg.layout == "editor" then root.position, root.height = "bottom", 0.45
  else root.width, root.height = w, h end
  if mode == "wide" then
    root[1] = { box = "horizontal", { win = "tasks", width = g.tasks, border = "right" }, { win = "inspector" } }
    root[2] = { win = "activity", height = g.tray, border = "top" }
  elseif mode == "medium" then
    root[1] = { box = "horizontal", { win = "tasks", width = g.tasks, border = "right" }, { win = "inspector" } }
  else
    root[1] = { win = "main" }
  end
  return root, mode, { w = w, h = h, geometry = g }
end

--- Which panes exist in a mode.
function L.panes(mode)
  if mode == "wide" then return { "tasks", "inspector", "activity" } end
  if mode == "medium" then return { "tasks", "inspector" } end
  return { "main" }
end

return L
