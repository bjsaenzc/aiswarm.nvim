-- Explicit project/board session ownership (SDD-015).
-- Root precedence: explicit option → AISWARM_ROOT → discovered board in the
-- cwd's ancestors → candidate <git root or cwd>/.aiswarm (never created here).
local M = { generation = 0, current = nil }
local config = require("aiswarm.config")

--- Canonical absolute path: expanded, normalized, symlinks resolved when the path exists.
function M.canonical(path)
  local p = vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(path), ":p"))
  p = p:gsub("/+$", "")
  local real = vim.uv.fs_realpath(p)
  if real then p = vim.fs.normalize(real):gsub("/+$", "") end
  return p
end

--- Board schema at a root: "v3" (board.json schema 3), "v2" (legacy layout), "missing", or "invalid".
function M.schema(root)
  if not root or vim.fn.isdirectory(root) == 0 then return "missing" end
  if vim.uv.fs_stat(root .. "/locks/migration.marker") then return "migrating" end
  local f = io.open(root .. "/board.json", "r")
  if f then
    local text = f:read("*a"); f:close()
    local ok, board = pcall(vim.json.decode, text)
    if ok and type(board) == "table" and board.schema_version == 3 then return "v3" end
    return "invalid"
  end
  if vim.fn.isdirectory(root .. "/tasks/ready") == 1 then return "v2" end
  return "invalid"
end

--- Walk ancestors of `dir` for .aiswarm boards.
---@return { kind: "aiswarm"|"none", root?: string, candidates: string[], dir?: string }
function M.discover(dir)
  dir = M.canonical(dir or vim.uv.cwd())
  for d in vim.fs.parents(dir .. "/.") do
    local a = d .. "/.aiswarm"
    if vim.fn.isdirectory(a) == 1 then return { kind = "aiswarm", root = a, candidates = { a }, dir = d } end
  end
  return { kind = "none", candidates = {} }
end

--- Git toplevel of `dir` when inside a repository.
function M.git_root(dir)
  local o = vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }):wait(2000)
  if o and o.code == 0 then return M.canonical(vim.trim(o.stdout)) end
  return nil
end

--- Resolve the board for a configuration without side effects.
---@return { root: string?, source: string, schema: string, candidate?: boolean }
function M.resolve(cfg, cwd)
  cfg = cfg or {}
  if cfg.root then
    local root = M.canonical(cfg.root)
    return { root = root, source = "option", schema = M.schema(root) }
  end
  local env, source = config.env("AISWARM_ROOT")
  if env then
    local root = M.canonical(env)
    return { root = root, source = source, schema = M.schema(root) }
  end
  local found = M.discover(cwd)
  if found.kind ~= "none" then
    return { root = found.root, source = "discovery", schema = M.schema(found.root) }
  end
  local base = M.git_root(cwd or vim.uv.cwd()) or M.canonical(cwd or vim.uv.cwd())
  return { root = base .. "/.aiswarm", source = "candidate", schema = "missing", candidate = true }
end

local listeners = {}
function M.on_change(fn) listeners[#listeners + 1] = fn; return function() for i, f in ipairs(listeners) do if f == fn then table.remove(listeners, i) end end end end

--- Switch the session to `root`. Preserves configuration; invalidates pending callbacks of the old session.
---@param root string
---@param opts? { source?: string, remember?: boolean }
function M.open(root, opts)
  opts = opts or {}
  root = M.canonical(root)
  local session = require("aiswarm.session")
  session.stop()
  M.generation = M.generation + 1
  M.current = { root = root, generation = M.generation, source = opts.source or "explicit", schema = M.schema(root), opened_at = os.time() }
  if opts.remember ~= false then M.remembered = root end
  session.start(root)
  for _, fn in ipairs(vim.list_extend({}, listeners)) do pcall(fn, M.current) end
  return M.current
end

--- Close the current session without opening another.
function M.close()
  require("aiswarm.session").stop()
  M.generation = M.generation + 1
  M.current = nil
end

--- Token for pending work; `alive(token)` is false after any switch/close.
function M.token() return M.generation end
function M.alive(token) return token == M.generation end

--- The current root or nil.
function M.root() return M.current and M.current.root or nil end

--- Re-evaluate discovery for the editor cwd; returns a suggestion when it differs from the current session.
function M.suggestion(cwd)
  local r = M.resolve({}, cwd)
  if r.root and M.current and r.root ~= M.current.root and not r.candidate then return r end
  return nil
end

return M
