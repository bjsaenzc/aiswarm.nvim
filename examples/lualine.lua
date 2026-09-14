-- lualine.nvim component for aiswarm: reads the plugin's cached store only when it is already loaded,
-- so statusline redraws never trigger lazy-loading, subprocesses or file reads.
return {
  "nvim-lualine/lualine.nvim",
  opts = {
    sections = {
      lualine_x = {
        {
          function()
            local ok, aiswarm = pcall(function() return package.loaded["aiswarm"] end)
            if not ok or not aiswarm then return "" end
            return aiswarm.statusline()
          end,
          cond = function() return package.loaded["aiswarm"] ~= nil end,
          on_click = function() if package.loaded["aiswarm"] then require("aiswarm").open() end end,
        },
        "encoding", "fileformat", "filetype",
      },
    },
  },
}
