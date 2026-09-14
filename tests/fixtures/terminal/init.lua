-- Minimal real-terminal init for screenshot evidence (SDD-098): loads only snacks.nvim and the plugin
-- from this repository and opens the workspace on the fixture board. Driven by scripts/screenshot-aiswarm.sh.
local plugin = os.getenv("AISWARM_SHOT_PLUGIN")
local snacks = os.getenv("AISWARM_SHOT_SNACKS")
local root = os.getenv("AISWARM_SHOT_ROOT")
vim.opt.runtimepath:prepend(plugin)
if snacks and snacks ~= "" then vim.opt.runtimepath:append(snacks) end
vim.o.swapfile, vim.o.shada, vim.o.termguicolors = false, "", os.getenv("AISWARM_SHOT_TRUECOLOR") ~= "0"
vim.o.background = os.getenv("AISWARM_SHOT_BACKGROUND") or "dark"
vim.o.laststatus, vim.o.cmdheight = 2, 1
vim.g.mapleader = " "
require("snacks").setup({ notifier = { enabled = true }, picker = { enabled = true } })
require("aiswarm").setup({
  bin = plugin .. "/bin/aiswarm", root = root, follow = true, register_server = false,
  ui = { icons = os.getenv("AISWARM_SHOT_ICONS") or "unicode", motion = false },
  telemetry = { reconcile_ms = 2000 },
})
vim.cmd.source(plugin .. "/plugin/aiswarm.lua")
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.defer_fn(function() vim.cmd("AISwarm") end, 300) end })
