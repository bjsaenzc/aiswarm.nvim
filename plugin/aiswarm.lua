if vim.g.loaded_aiswarm or vim.g.loaded_hive then return end
vim.g.loaded_aiswarm, vim.g.loaded_hive = true, true

require("aiswarm.commands").register()
-- Legacy :Hive* aliases stay registered through one compatibility release; they can be
-- disabled with setup({ compat = { hive_commands = false } }) before the plugin loads.
local disabled = vim.g.aiswarm_compat_hive_commands == false
if not disabled then require("aiswarm.compat").register_legacy_commands() end
