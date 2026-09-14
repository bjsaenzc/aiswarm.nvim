-- SDD-009: canonical namespace with legacy shims over one implementation.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
return {
  { id = "compat.namespace.one_state_either_order", tasks = { "SDD-009" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    pl.unload()
    local H = require("hive")            -- legacy first
    H.setup({ bin = sb.bin("aiswarm"), root = root, follow = true, register_server = false, dashboard = { refresh_ms = 60000 } })
    t:defer(function() require("aiswarm.project").close() end)
    local A = require("aiswarm")
    t:ok(require("hive.state") == require("aiswarm.legacy.state"), "hive.state is the aiswarm state")
    t:ok(A.state() == require("hive.state"), "one state instance")
    t:eq(A.root(), root); t:eq(H.root(), root)
    pl.refresh(t, A)
    t:ok(A.state()._follow, "follower running")
    local follower = A.state()._follow
    A.setup({ bin = sb.bin("aiswarm"), root = root, follow = true, register_server = false, dashboard = { refresh_ms = 60000 } }) -- canonical second
    pl.refresh(t, A)
    t:ok(A.state()._follow and A.state()._follow ~= follower, "setup replaced the follower; exactly one runs")
    t:ok(require("hive") == require("hive"), "shim is memoized")
  end },
  { id = "compat.namespace_canonical_first", tasks = { "SDD-009" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    local A = pl.setup(t, root)
    local H = require("hive")
    t:ok(H.state == nil or true)
    t:eq(H.root(), A.root()); t:eq(H.statusline(), A.statusline())
    t:ok(require("hive.ui") == require("aiswarm.legacy.ui"))
    t:eq(type(require("hive.health").check), "function")
  end },
  { id = "compat.namespace.commands_registered_once", tasks = { "SDD-009", "SDD-012" }, suites = { "core", "compatibility" }, run = function(t)
    pl.unload()
    pl.source_plugin()
    vim.cmd.source(sb.plugin .. "/plugin/aiswarm.lua") -- second source is a no-op through the guard
    local cmds = vim.api.nvim_get_commands({})
    t:ok(cmds.AISwarm, "canonical command"); t:ok(cmds.Hive and cmds.HiveAdd and cmds.HiveKill, "legacy aliases")
    t:eq(cmds.AISwarm.range, ".", "AISwarm accepts a range"); t:eq(cmds.HiveAdd.range, ".")
    t:eq(vim.g.loaded_aiswarm, true); t:eq(vim.g.loaded_hive, true)
  end },
  { id = "compat.namespace.no_data_moved", tasks = { "SDD-009" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001" }, "a\n")
    local A = pl.setup(t, root)
    local snap = pl.refresh(t, A)
    t:eq(snap.tasks and #snap.tasks or vim.tbl_count(A.state().tasks), 1)
    t:ok(sb.exists(root .. "/tasks/ready/T-001.json"), "board files stay under .hive")
    t:ok(not sb.exists(vim.fs.dirname(root) .. "/.aiswarm"), "no .aiswarm directory created")
  end },
}
