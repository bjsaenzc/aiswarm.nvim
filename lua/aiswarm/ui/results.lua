-- Reports picker with explicit task/attempt identity (SDD-057).
local M = {}
local function A() return require("aiswarm") end
local store = require("aiswarm.store")
local T = require("aiswarm.ui.text")
local H = require("aiswarm.ui.highlights")

function M.items()
  local out = {}
  local I = require("aiswarm.ui.inspector")
  for _, t in pairs(store.tasks) do
    local atts = store.attempts_of(t.id)
    if #atts == 0 then
      local p = I.paths(t, nil)
      if p.report and vim.uv.fs_stat(p.report) then out[#out + 1] = { file = p.report, id = t.id, text = t.id .. " " .. (t.title or ""), task = t, label = "legacy report" } end
    else
      for _, a in ipairs(atts) do
        if a.paths and a.paths.report and vim.uv.fs_stat(a.paths.report) then
          out[#out + 1] = { file = a.paths.report, id = t.id, attempt = a, text = ("%s attempt %d %s"):format(t.id, a.ordinal or 0, t.title or ""), task = t,
            label = ("attempt %d · %s%s"):format(a.ordinal or 0, a.report and a.report.status or "?", a.imported and " · imported" or "") }
        end
      end
    end
  end
  table.sort(out, function(x, y) if x.id ~= y.id then return x.id < y.id end return (x.attempt and x.attempt.ordinal or 0) > (y.attempt and y.attempt.ordinal or 0) end)
  return out
end

function M.pick()
  if not pcall(require, "snacks") then return A().err("snacks.nvim is required") end
  Snacks.picker.pick({
    title = "aiswarm reports", items = M.items(), preview = "file",
    format = function(item)
      local icons = T.icons()
      return { { (icons[item.task.state] or "?") .. " ", H.for_task(item.task) }, { T.fit(item.id, 9), "AISwarmId" }, { T.fit(item.label, 30), "AISwarmMuted" }, { item.task.title or "", "Normal" } }
    end,
    confirm = function(picker, item) if item then picker:close(); vim.cmd.edit(vim.fn.fnameescape(item.file)) end end,
  })
end

return M
