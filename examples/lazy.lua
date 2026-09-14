-- lazy.nvim spec for aiswarm.nvim installed from its own repository.
-- Replace <owner> with the GitHub account that hosts the repository.
return {
  "<owner>/aiswarm.nvim",
  name = "aiswarm.nvim",
  main = "aiswarm",
  dependencies = { "folke/snacks.nvim" },
  cmd = {
    "AISwarm",
    -- legacy aliases (compat.hive_commands)
    "Hive", "HivePick", "HiveAdd", "HiveResults", "HiveTail", "HivePeek", "HiveGo", "HiveKill", "HivePause", "HiveRefresh",
  },
  keys = {
    { "<leader>Aa", "<cmd>AISwarm<cr>", desc = "AI swarm: workspace" },
    { "<leader>Ap", "<cmd>AISwarm pick<cr>", desc = "AI swarm: search tasks" },
    { "<leader>An", ":AISwarm new<cr>", desc = "AI swarm: new task (visual = context)", mode = { "n", "v" } },
    { "<leader>Al", "<cmd>AISwarm activity<cr>", desc = "AI swarm: activity" },
    { "<leader>Ar", "<cmd>AISwarm results<cr>", desc = "AI swarm: reports" },
  },
  -- `bin` defaults to the bundled bin/aiswarm of this checkout; set it only to use another launcher.
  opts = {},
}
