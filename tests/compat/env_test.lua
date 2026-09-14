-- SDD-011: configuration/environment aliases and validation.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
local function config() return require("aiswarm.config") end

local cases = {}
local table_driven = {
  { name = "canonical_wins", env = { AISWARM_ROOT = "A", HIVE_ROOT = "B" }, expect = "A", warn = false },
  { name = "legacy_only_warns", env = { HIVE_ROOT = "B" }, expect = "B", warn = true },
  { name = "canonical_only", env = { AISWARM_ROOT = "A" }, expect = "A", warn = false },
  { name = "unset_discovers", env = {}, expect = nil, warn = false },
}
for _, row in ipairs(table_driven) do
  cases[#cases + 1] = { id = "compat.env.cli_" .. row.name, tasks = { "SDD-011" }, suites = { "core", "compatibility" }, run = function(t)
    local dir = t:tmpdir("cli")
    sb.run({ "git", "init", "-q", dir }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME } }) -- own git toplevel for the candidate rule
    local a, b = dir .. "/A", dir .. "/B"
    local env = { PATH = vim.env.PATH, HOME = vim.env.HOME, TMUX_TMPDIR = vim.env.TMUX_TMPDIR or vim.env.TMPDIR }
    for k, v in pairs(row.env) do env[k] = (v == "A" and a) or (v == "B" and b) or v end
    local o = sb.run({ sb.bin("aiswarm"), "doctor", "--json" }, { env = env, cwd = dir })
    t:eq(o.code, 0, o.stderr)
    local d = sb.json(o.stdout)
    local expect = row.expect and ((row.expect == "A" and a) or b) or (dir .. "/.aiswarm")
    t:eq(d.root, expect, "effective root")
    t:eq(o.stderr:find("HIVE_ROOT is deprecated", 1, true) ~= nil, row.warn, "legacy warning presence")
    if row.warn then t:eq(select(2, o.stderr:gsub("deprecated", "")), 1, "warned exactly once") end
  end }
  cases[#cases + 1] = { id = "compat.env.nvim_" .. row.name, tasks = { "SDD-011" }, suites = { "core", "compatibility" }, run = function(t)
    local dir = t:tmpdir("nvim")
    sb.run({ "git", "init", "-q", dir }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME } })
    local a, b = dir .. "/A", dir .. "/B"
    vim.fn.mkdir(a, "p"); vim.fn.mkdir(b, "p")
    vim.env.AISWARM_ROOT, vim.env.HIVE_ROOT = nil, nil
    for k, v in pairs(row.env) do vim.env[k] = (v == "A" and a) or (v == "B" and b) or v end
    t:defer(function() vim.env.AISWARM_ROOT, vim.env.HIVE_ROOT = nil, nil end)
    config()._reset_warnings()
    local project = require("aiswarm.project")
    local seen = pl.capture_notify(function()
      local r = project.resolve({}, dir)
      local expect = row.expect and ((row.expect == "A" and a) or b) or (dir .. "/.aiswarm")
      t:eq(r.root, expect)
      vim.wait(50)
    end)
    local warned = false
    for _, n in ipairs(seen) do if n.msg:find("HIVE_ROOT is deprecated", 1, true) then warned = true end end
    t:eq(warned, row.warn)
  end }
end
cases[#cases + 1] = { id = "compat.env.invalid_settings_fail_before_jobs", tasks = { "SDD-011" }, suites = { "core", "compatibility" }, run = function(t)
  pl.unload()
  local A = require("aiswarm")
  local dir = t:tmpdir("invalid")
  for _, bad in ipairs({
    { opts = { bin = "" }, err = "bin must be" },
    { opts = { bin = sb.bin("aiswarm"), command_timeout_ms = -1 }, err = "command_timeout_ms must be a positive integer" },
    { opts = { bin = sb.bin("aiswarm"), ui = { layout = "sideways" } }, err = "ui.layout must be one of" },
    { opts = { bin = sb.bin("aiswarm"), ui = { width = 2 } }, err = "ui.width" },
    { opts = { bin = sb.bin("aiswarm"), telemetry = { heartbeat_ms = 0.5 } }, err = "telemetry.heartbeat_ms" },
    { opts = { bin = sb.bin("aiswarm"), notify = { failed = "yes" } }, err = "notify.failed must be a boolean" },
    { opts = { bin = sb.bin("aiswarm"), follow = 1 }, err = "follow must be a boolean" },
  }) do
    bad.opts.root = dir .. "/.hive"
    t:errors(function() A.setup(bad.opts) end, bad.err)
  end
  t:eq(require("aiswarm.project").current, nil, "no session started by invalid setup")
  t:ok(not sb.exists(dir .. "/.hive"), "no files created")
end }
cases[#cases + 1] = { id = "compat.env.provider_default_is_mock", tasks = { "SDD-011", "SDD-016" }, suites = { "core", "compatibility" }, run = function(t)
  vim.env.AISWARM_PROVIDER, vim.env.HIVE_PROVIDER = nil, nil
  local registry = require("aiswarm.providers.registry")
  t:eq(registry.default(), "mock")
  local root = sb.legacy_board(t)
  local r = sb.run({ sb.bin("aiswarm"), "add", "--id", "T-001" }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME, AISWARM_ROOT = root, TMUX_TMPDIR = vim.env.TMUX_TMPDIR or vim.env.TMPDIR }, stdin = "x\n" })
  t:eq(r.code, 0, r.stderr)
  t:eq(sb.json(sb.aiswarm(root, { "show", "T-001" }).stdout).provider, "mock", "CLI default matches the registry default")
  vim.env.HIVE_PROVIDER = "codex"; config()._reset_warnings()
  t:eq(registry.default(), "codex", "legacy provider variable honoured")
  vim.env.AISWARM_PROVIDER = "gemini"
  t:eq(registry.default(), "gemini", "canonical wins")
  vim.env.AISWARM_PROVIDER, vim.env.HIVE_PROVIDER = nil, nil
end }
cases[#cases + 1] = { id = "compat.env.legacy_notify_keys_translated", tasks = { "SDD-011" }, suites = { "core", "compatibility" }, run = function(t)
  config()._reset_warnings()
  local c = config().resolve({ notify = { done = false, orphaned = true } })
  t:eq(c.notify.completed, false); t:eq(c.notify.done, nil); t:eq(c.notify.orphaned, nil)
end }
return cases
