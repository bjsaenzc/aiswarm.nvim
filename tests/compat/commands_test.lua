-- SDD-012: canonical subcommands.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
return {
  { id = "compat.commands.completion", tasks = { "SDD-012" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t); sb.legacy_add(t, root, { "--id", "T-001" }, "a\n")
    local A = pl.setup(t, root); pl.refresh(t, A); pl.source_plugin()
    local subs = vim.fn.getcompletion("AISwarm ", "cmdline")
    for _, s in ipairs({ "open", "pick", "new", "inspect", "cancel", "retry", "scheduler" }) do t:ok(vim.tbl_contains(subs, s), "completes " .. s) end
    t:eq(vim.fn.getcompletion("AISwarm inspect T", "cmdline"), { "T-001" })
    t:eq(vim.fn.getcompletion("AISwarm scheduler p", "cmdline"), { "pause" })
  end },
  { id = "compat.commands.unknown_subcommand_fails_clearly", tasks = { "SDD-012" }, suites = { "core", "compatibility" }, run = function(t)
    local A = pl.setup(t, sb.legacy_board(t)); pl.source_plugin()
    local seen = pl.capture_notify(function() vim.cmd("AISwarm nosuchthing") end)
    t:ok(#seen >= 1 and seen[1].msg:match("unknown AISwarm subcommand: nosuchthing"), vim.inspect(seen))
    t:eq(seen[1].level, vim.log.levels.ERROR)
  end },
  { id = "compat.commands.v3_only_actions_gated", tasks = { "SDD-012" }, suites = { "core", "compatibility" }, run = function(t)
    local A = pl.setup(t, sb.legacy_board(t)); pl.source_plugin()
    for _, cmd in ipairs({ "AISwarm cancel T-1", "AISwarm retry T-1", "AISwarm scheduler start" }) do
      local seen = pl.capture_notify(function() vim.cmd(cmd) end)
      t:ok(#seen >= 1 and seen[1].msg:match("not available yet"), cmd .. " -> " .. vim.inspect(seen))
    end
    local seen = pl.capture_notify(function() vim.cmd("AISwarm inspect T-1") end)
    t:ok(#seen >= 1 and seen[1].msg:match("no such task"), "inspect resolves ids and reports unknown ones clearly")
  end },
  { id = "compat.commands.visual_range_reaches_composer", tasks = { "SDD-012" }, suites = { "core", "compatibility" }, run = function(t)
    local A = pl.setup(t, sb.legacy_board(t)); pl.source_plugin()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "", "#: three", "four" }); vim.api.nvim_set_current_buf(buf)
    local got
    local ui = require("aiswarm.ui"); local orig = ui.new; ui.new = function(prefill) got = prefill end
    t:defer(function() ui.new = orig end)
    vim.cmd("1,3AISwarm new"); t:eq(got, { "one", "", "#: three" })
    got = "unset"; vim.cmd("AISwarm new"); t:eq(got, nil, "no range → no prefill")
  end },

}
