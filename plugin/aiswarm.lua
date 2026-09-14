if vim.g.loaded_aiswarm then return end
vim.g.loaded_aiswarm = true

require("aiswarm.commands").register()
