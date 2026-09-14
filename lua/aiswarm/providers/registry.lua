-- Provider registry: stable IDs, executables, probes, defaults and capabilities (SDD-016).
local M = {}

---@class aiswarm.Provider
---@field id string
---@field exe string|nil   executable name (nil = built-in mock)
---@field label string
---@field capabilities table<string, boolean>
M.providers = {
  { id = "claude", exe = "claude",       label = "Claude Code",  capabilities = { raw_output = true, exit = true, heartbeat = true } },
  { id = "codex",  exe = "codex",        label = "Codex CLI",    capabilities = { raw_output = true, exit = true, heartbeat = true } },
  { id = "gemini", exe = "gemini",       label = "Gemini CLI",   capabilities = { raw_output = true, exit = true, heartbeat = true } },
  { id = "aider",  exe = "aider",        label = "Aider",        capabilities = { raw_output = true, exit = true, heartbeat = true } },
  { id = "cursor", exe = "cursor-agent", label = "Cursor Agent", capabilities = { raw_output = true, exit = true, heartbeat = true } },
  { id = "mock",   exe = nil,            label = "Mock (simulated execution, no tokens)", capabilities = { raw_output = true, exit = true, heartbeat = true, simulated = true } },
}
local by_id = {}
for _, p in ipairs(M.providers) do by_id[p.id] = p end

function M.get(id) return by_id[id] end
function M.ids() return vim.tbl_map(function(p) return p.id end, M.providers) end
function M.valid(id) return by_id[id] ~= nil end

--- Executable used for a provider id (cursor → cursor-agent).
function M.executable(id) local p = by_id[id]; return p and p.exe or nil end

local probes = {}
--- Availability probe. Synchronous executable lookup; version is filled in lazily.
---@return { available: boolean, exe: string?, path: string?, version: string? }
function M.probe(id, opts)
  local p = by_id[id]
  if not p then return { available = false, reason = "unknown provider" } end
  if not p.exe then return { available = true, exe = nil, builtin = true } end
  if probes[id] and not (opts and opts.refresh) then return probes[id] end
  local path = vim.fn.exepath(p.exe)
  local r = { available = path ~= "", exe = p.exe, path = path ~= "" and path or nil }
  probes[id] = r
  return r
end
function M.reset_probes() probes = {} end

--- Every provider with availability, for pickers.
function M.list()
  local out = {}
  for _, p in ipairs(M.providers) do
    local probe = M.probe(p.id)
    out[#out + 1] = { id = p.id, label = p.label, exe = p.exe, available = probe.available, path = probe.path, capabilities = p.capabilities }
  end
  return out
end

--- Effective default provider: AISWARM_PROVIDER → mock (the backend default).
function M.default()
  local v = require("aiswarm.config").default_provider()
  if v and by_id[v] then return v end
  return "mock"
end

--- Executable actually used at run time: AISWARM_PROVIDER_EXEC_<id> override, else the registry name,
--- else the bundled mock script.
function M.resolve_executable(id)
  local override = vim.env["AISWARM_PROVIDER_EXEC_" .. id]
  if override and override ~= "" then return override end
  local p = by_id[id]
  if not p then return nil end
  if p.exe then return p.exe end
  local root = _G.AISWARM_PLUGIN_ROOT or vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
  return root .. "/runtime/mock-provider"
end

--- Argument vector for a one-shot run. Mirrors the v2 launcher exactly (no speculative flags).
---@param id string
---@param rendered_path string path of the rendered prompt file
---@param opts? { max_turns?: number|string }
function M.build_argv(id, rendered_path, opts)
  opts = opts or {}
  local exe = M.resolve_executable(id)
  if not exe then return nil, "unknown provider: " .. tostring(id) end
  local f = io.open(rendered_path, "r")
  local text = f and f:read("*a") or ""
  if f then f:close() end
  local max_turns = tostring(opts.max_turns or vim.env.AISWARM_MAX_TURNS or 40)
  if id == "claude" then return { exe, "-p", text, "--output-format", "text", "--permission-mode", "acceptEdits", "--max-turns", max_turns }
  elseif id == "codex" then return { exe, "exec", "--skip-git-repo-check", "--sandbox", "workspace-write", text }
  elseif id == "gemini" then return { exe, "-p", text }
  elseif id == "aider" then return { exe, "--yes", "--no-auto-commit", "--message-file", rendered_path }
  elseif id == "cursor" then return { exe, "-p", text }
  elseif id == "mock" then return { exe, rendered_path } end
  return nil, "no argv builder for " .. id
end

--- Capability check that never claims what the adapter cannot demonstrate.
function M.has(id, capability) local p = by_id[id]; return p ~= nil and p.capabilities[capability] == true end

return M
