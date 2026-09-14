-- SDD-013: user entry keys under <leader>A, no Hive <leader>H mappings.
local sb = require("helpers.sandbox")
-- the config repository's spec when nested under a Neovim config, else the shipped example spec
local function spec_path() local p = sb.repo .. "/lua/plugins/nvim-aiswarm.lua"; return sb.exists(p) and p or sb.plugin .. "/examples/lazy.lua" end
return {
  { id = "compat.keys.spec_uses_ai_swarm_group", tasks = { "SDD-013" }, suites = { "core", "compatibility" }, run = function(t)
    local spec = dofile(spec_path())
    t:eq(spec.main, "aiswarm"); t:eq(spec.name, "aiswarm.nvim")
    local lhs = {}
    for _, k in ipairs(spec.keys) do
      lhs[k[1]] = k
      t:ok(k[1]:match("^<leader>A"), "key under <leader>A: " .. k[1])
      t:ok(k.desc and k.desc:match("^AI swarm"), "accurate description: " .. tostring(k.desc))
    end
    for _, key in ipairs({ "<leader>Aa", "<leader>Ap", "<leader>An", "<leader>Al", "<leader>Ar" }) do t:ok(lhs[key], key) end
    t:eq(lhs["<leader>An"].mode, { "n", "v" }); t:ok(lhs["<leader>An"][2]:match("^:AISwarm new<cr>$"), "visual An keeps '<,'> range")
    t:ok(not sb.exists(sb.repo .. "/lua/plugins/nvim-hive.lua"), "old spec removed")
    t:ok(not vim.tbl_contains(vim.tbl_map(function(k) return k[1] end, spec.keys), "<leader>Hh"))
    local wk = sb.read(sb.repo .. "/lua/plugins/which-key.lua")
    if wk then t:ok(wk:find('{ "<leader>A", group = "AI swarm" }', 1, true), "which-key group registered") end
  end },
  { id = "compat.keys.no_runtime_conflicts", tasks = { "SDD-013" }, suites = { "core", "compatibility" }, run = function(t)
    local spec = dofile(spec_path())
    -- install the spec's mappings the way lazy would, then a gitsigns-style buffer-local <leader>Hr and Sidekick <leader>aa
    vim.g.mapleader = " "
    for _, k in ipairs(spec.keys) do vim.keymap.set(k.mode or "n", k[1], k[2], { desc = k.desc }) end
    t:defer(function() for _, k in ipairs(spec.keys) do pcall(vim.keymap.del, k.mode or "n", k[1]) end end)
    local buf = vim.api.nvim_create_buf(false, true); vim.api.nvim_set_current_buf(buf)
    vim.keymap.set("n", "<leader>Hr", "<cmd>echo 'git reset hunk'<cr>", { buffer = buf, desc = "Git: Reset hunk" })
    vim.keymap.set("n", "<leader>aa", "<cmd>echo 'sidekick'<cr>", { desc = "Sidekick" })
    t:defer(function() pcall(vim.keymap.del, "n", "<leader>aa") end)
    local function find(mode, lhs, buffer)
      for _, m in ipairs(buffer and vim.api.nvim_buf_get_keymap(buf, mode) or vim.api.nvim_get_keymap(mode)) do if m.lhs == " " .. lhs:sub(9) then return m end end
    end
    t:ok(find("n", "<leader>Hr", true).desc:match("^Git"), "Git H action intact")
    t:ok(find("n", "<leader>aa", false).desc == "Sidekick", "Sidekick lowercase a intact")
    t:ok(find("n", "<leader>Ap", false).rhs:match("AISwarm pick"), "Ap opens the picker")
    t:eq(find("n", "<leader>Hp", true), nil, "Hive no longer advertises <leader>Hp")
    t:ok(find("v", "<leader>An", false), "visual An present")
  end },
}
