-- SDD-016: provider registry().
local sb = require("helpers.sandbox")
local function registry() return require("aiswarm.providers.registry") end
return {
  { id = "compat.providers.stable_ids_and_executables", tasks = { "SDD-016" }, suites = { "core", "compatibility" }, run = function(t)
    t:eq(registry().ids(), { "claude", "codex", "gemini", "aider", "cursor", "mock" })
    t:eq(registry().executable("cursor"), "cursor-agent"); t:eq(registry().executable("mock"), nil)
    t:ok(registry().valid("mock")); t:ok(not registry().valid("not-a-provider"))
  end },
  { id = "compat.providers.unavailable_is_visible_not_silent", tasks = { "SDD-016" }, suites = { "core", "compatibility" }, run = function(t)
    registry().reset_probes()
    for _, p in ipairs(registry().list()) do
      if p.id == "mock" then t:eq(p.available, true) else t:eq(p.available, false, p.id .. " is unavailable in the sandbox") end
    end
    local U = require("aiswarm.legacy.ui")
    local _, _, err = U.parse_form({ "#: id = T-1", "#: provider = claude", "---", "x" })
    t:match(err, "unavailable")
    local args = U.parse_form({ "#: id = T-1", "#: provider = mock", "---", "x" })
    t:ok(vim.tbl_contains(args, "mock"))
  end },
  { id = "compat.providers.composer_default_matches_cli", tasks = { "SDD-016" }, suites = { "core", "compatibility" }, run = function(t)
    vim.env.AISWARM_PROVIDER, vim.env.HIVE_PROVIDER = nil, nil
    local U = require("aiswarm.legacy.ui")
    local line = U.form_template()[4]
    t:eq(line, "#: provider = " .. registry().default()); t:eq(registry().default(), "mock")
  end },
  { id = "compat.providers.generic_capabilities_only", tasks = { "SDD-016" }, suites = { "core", "compatibility" }, run = function(t)
    for _, id in ipairs(registry().ids()) do
      t:ok(registry().has(id, "raw_output") and registry().has(id, "exit") and registry().has(id, "heartbeat"))
      t:ok(not registry().has(id, "input") and not registry().has(id, "tools") and not registry().has(id, "usage"), id .. " advertises no unproven capability")
    end
    t:ok(registry().has("mock", "simulated"))
  end },
}
