-- :AISwarm project / init / migrate (SDD-015, SDD-018, SDD-042). Keyboard-only, no silent retargeting.
local M = {}
local function A() return require("aiswarm") end
local project = require("aiswarm.project")

local function describe()
  local cur = project.current
  local r = A()._resolved or {}
  local lines = {}
  if cur then
    lines[#lines + 1] = ("project: %s (%s, schema %s)"):format(cur.root, cur.source, project.schema(cur.root))
  else
    lines[#lines + 1] = "project: none open"
    if r.candidate then lines[#lines + 1] = "candidate: " .. r.root .. " (not created; run :AISwarm init)" end
  end
  local s = project.suggestion()
  if s then lines[#lines + 1] = ("editor cwd suggests %s (%s); :AISwarm project open %s"):format(s.root, s.schema, s.root) end
  return lines
end

--- :AISwarm project [open <root>|choose|show]
function M.run(args)
  local action = args[1] or "show"
  if action == "show" then return A().notify(table.concat(describe(), "\n")) end
  if action == "open" then
    local root = args[2]
    if not root or root == "" then return A().err("usage: AISwarm project open <root>") end
    local schema = project.schema(project.canonical(root))
    if schema == "missing" then return A().err(root .. " has no board; run :AISwarm init " .. root) end
    local cur = project.open(root, { source = "explicit" })
    return A().notify("opened " .. cur.root .. " (schema " .. cur.schema .. ")")
  end
  if action == "choose" then
    local r = A()._resolved or project.resolve(A().config)
    local candidates = {}
    local s = project.suggestion(); if s then candidates[#candidates + 1] = s.root end
    if project.current then candidates[#candidates + 1] = project.current.root end
    if #candidates == 0 then return A().notify("nothing to choose; " .. table.concat(describe(), " ")) end
    vim.ui.select(candidates, { prompt = "aiswarm board" }, function(choice)
      if choice then project.open(choice, { source = "explicit" }); A().notify("opened " .. choice) end
    end)
    return
  end
  A().err("usage: AISwarm project [show|open <root>|choose]")
end

--- :AISwarm init [root] — creates a board explicitly; never implied by opening.
function M.init(args)
  local root = args[1]
  if not root or root == "" then
    local r = A()._resolved or project.resolve(A().config)
    root = project.current and project.current.root or r.root
  end
  if not root then return A().err("no board location; pass a path: AISwarm init <root>") end
  root = project.canonical(root)
  local cmd = A().cmd({ "init" })
  local env = A().env(); env.AISWARM_ROOT = root
  vim.system(cmd, { text = true, env = env }, vim.schedule_wrap(function(o)
    if o.code ~= 0 then return A().err(A().failure(o)) end
    project.open(root, { source = "explicit" })
    A().notify("initialized " .. root .. "\n" .. vim.trim(o.stdout))
  end))
end

--- :AISwarm migrate [--dry-run|--rollback] — wired in SDD-042.
function M.migrate(args)
  local ok, m = pcall(require, "aiswarm.ui.migrate")
  if ok then return m.run(args) end
  return require("aiswarm.ui").unavailable("migrate", "migration commands (SDD-038–042)")
end

return M
