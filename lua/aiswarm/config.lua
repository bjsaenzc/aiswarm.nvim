-- Configuration defaults, validation and environment aliases (SDD-011).
local M = {}

---@class aiswarm.Config
M.defaults = {
  bin = (function()               -- launcher: the bundled bin/aiswarm when this checkout has it, else PATH lookup
    local here = debug.getinfo(1, "S").source:sub(2)
    local bundled = vim.fn.fnamemodify(here, ":h:h:h") .. "/bin/aiswarm"
    return vim.uv.fs_stat(bundled) and bundled or "aiswarm"
  end)(),
  root = nil,                      -- explicit board root; overrides every environment variable
  follow = true,                   -- run the journal follower (v2) / stream (v3)
  register_server = true,          -- write v:servername to <root>/nvim.server for the push hook
  peek_lines = 80,
  command_timeout_ms = 5000,
  notify = { completed = true, failed = true, input_required = true, started = false, progress = false,
             done = nil, orphaned = nil }, -- done/orphaned are legacy aliases of completed/failed
  dashboard = { width = 0.85, height = 0.8, refresh_ms = 3000 },
  tail = { position = "bottom", height = 0.35 },
  ui = { layout = "float", width = 0.92, height = 0.86, icons = "unicode", motion = false, quiet_after_s = 60 },
  telemetry = { enabled = true, heartbeat_ms = 5000, flush_ms = 100, reconcile_ms = 10000 },
  compat = { hive_commands = true, hive_events = false },
}

local warned = {}
--- Warn once per process for a legacy environment variable or option.
function M.warn_legacy(key, msg)
  if warned[key] then return end
  warned[key] = true
  vim.schedule(function() vim.notify(msg, vim.log.levels.WARN, { title = "aiswarm" }) end)
end
function M._reset_warnings() warned = {} end

--- Canonical environment wins; legacy is accepted with a one-time warning.
---@return string? value, string? source
function M.env(canonical, legacy)
  local v = vim.env[canonical]
  if v and v ~= "" then return v, canonical end
  v = vim.env[legacy]
  if v and v ~= "" then
    M.warn_legacy(legacy, ("%s is deprecated; use %s"):format(legacy, canonical))
    return v, legacy
  end
  return nil, nil
end

local function positive_int(name, value)
  if type(value) ~= "number" or value <= 0 or value % 1 ~= 0 then error(name .. " must be a positive integer", 0) end
end
local function fraction(name, value)
  if type(value) ~= "number" or value <= 0 or value > 1 then error(name .. " must be a number in (0, 1]", 0) end
end
local function one_of(name, value, allowed)
  for _, a in ipairs(allowed) do if a == value then return end end
  error(name .. " must be one of " .. table.concat(allowed, ", "), 0)
end

--- Validate a complete configuration. Raises a descriptive error.
function M.validate(c)
  if type(c.bin) ~= "string" or c.bin == "" then error("bin must be a non-empty string", 0) end
  if c.root ~= nil and (type(c.root) ~= "string" or c.root == "") then error("root must be a non-empty string", 0) end
  if type(c.follow) ~= "boolean" then error("follow must be a boolean", 0) end
  if type(c.register_server) ~= "boolean" then error("register_server must be a boolean", 0) end
  positive_int("peek_lines", c.peek_lines); positive_int("command_timeout_ms", c.command_timeout_ms)
  positive_int("dashboard.refresh_ms", c.dashboard.refresh_ms)
  fraction("dashboard.width", c.dashboard.width); fraction("dashboard.height", c.dashboard.height)
  fraction("tail.height", c.tail.height); one_of("tail.position", c.tail.position, { "bottom", "top", "left", "right", "float" })
  one_of("ui.layout", c.ui.layout, { "float", "editor" }); fraction("ui.width", c.ui.width); fraction("ui.height", c.ui.height)
  if type(c.ui.icons) ~= "table" then one_of("ui.icons", c.ui.icons, { "unicode", "ascii" }) end
  if type(c.ui.motion) ~= "boolean" then error("ui.motion must be a boolean", 0) end
  positive_int("ui.quiet_after_s", c.ui.quiet_after_s)
  if type(c.telemetry.enabled) ~= "boolean" then error("telemetry.enabled must be a boolean", 0) end
  positive_int("telemetry.heartbeat_ms", c.telemetry.heartbeat_ms); positive_int("telemetry.flush_ms", c.telemetry.flush_ms)
  positive_int("telemetry.reconcile_ms", c.telemetry.reconcile_ms)
  for k, v in pairs(c.notify) do if type(v) ~= "boolean" then error("notify." .. k .. " must be a boolean", 0) end end
  for k, v in pairs(c.compat) do if type(v) ~= "boolean" then error("compat." .. k .. " must be a boolean", 0) end end
  return c
end

--- Merge user options over defaults, translate legacy keys and validate.
---@param opts? table
---@return aiswarm.Config
function M.resolve(opts)
  opts = vim.deepcopy(opts or {})
  if type(opts.notify) == "table" then
    if opts.notify.done ~= nil then opts.notify.completed = opts.notify.done; M.warn_legacy("notify.done", "notify.done is deprecated; use notify.completed") end
    if opts.notify.orphaned ~= nil then M.warn_legacy("notify.orphaned", "notify.orphaned is deprecated; orphaned attempts notify through notify.failed") end
    opts.notify.done, opts.notify.orphaned = nil, nil
  end
  local c = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  c.notify.done, c.notify.orphaned = nil, nil
  M.validate(c)
  if c.bin:find("/", 1, true) then c.bin = vim.fn.fnamemodify(vim.fn.expand(c.bin), ":p") end
  return c
end

--- Effective provider default shared with the launcher: AISWARM_PROVIDER → HIVE_PROVIDER → registry default.
function M.default_provider()
  local v = M.env("AISWARM_PROVIDER", "HIVE_PROVIDER")
  return v
end

return M
