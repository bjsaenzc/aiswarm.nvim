-- Canonical package ownership; schema compatibility never loads a second plugin.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
return {
  { id = "namespace.single_runtime", tasks = { "SDD-009" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    local A = pl.setup(t, root, { follow = true })
    pl.refresh(t, A)
    t:ok(A.state() == require("aiswarm.legacy.state"))
    local follower = A.state()._follow
    t:ok(follower, "schema-v2 follower starts")
    A.setup({ root = root, follow = true, register_server = false })
    pl.refresh(t, A)
    t:ok(A.state()._follow and A.state()._follow ~= follower, "setup replaces the owned follower")
    t:ok(require("aiswarm") == A, "one memoized public API")
  end },
  { id = "namespace.one_command_registration", tasks = { "SDD-009", "SDD-012" }, suites = { "core", "compatibility" }, run = function(t)
    pl.unload()
    local before = vim.api.nvim_get_commands({})
    pl.source_plugin()
    vim.cmd.source(sb.plugin .. "/plugin/aiswarm.lua")
    local after, added = vim.api.nvim_get_commands({}), {}
    for name in pairs(after) do if not before[name] then added[#added + 1] = name end end
    t:eq(added, { "AISwarm" }, "plugin registers only its canonical command")
    t:eq(after.AISwarm.range, ".")
    t:eq(vim.g.loaded_aiswarm, true)
    t:eq(dofile(sb.plugin .. "/examples/lazy.lua").cmd, { "AISwarm" })
  end },
  { id = "namespace.explicit_board_is_not_moved", tasks = { "SDD-009" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001" }, "a\n")
    local alternate = vim.fs.dirname(root) .. "/import-board"
    assert(vim.uv.fs_rename(root, alternate))
    local A = pl.setup(t, alternate); pl.refresh(t, A)
    t:eq(A.root(), alternate)
    t:ok(sb.exists(alternate .. "/tasks/ready/T-001.json"))
    t:ok(not sb.exists(root), "opening an explicit schema-v2 board never moves it")
  end },
}
