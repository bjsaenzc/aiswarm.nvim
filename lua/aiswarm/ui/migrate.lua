-- :AISwarm migrate [--dry-run|--upgrade|--resume|--rollback] (SDD-042): inventory in a scratch buffer, explicit upgrade.
local M = {}
local function A() return require("aiswarm") end
local project = require("aiswarm.project")

local function show(title, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable, vim.bo[buf].bufhidden, vim.bo[buf].filetype = false, "wipe", "aiswarm-migrate"
  if package.loaded["snacks"] and _G.Snacks and Snacks.win then
    Snacks.win({ buf = buf, width = 0.8, height = 0.7, border = "rounded", title = " " .. title .. " ", title_pos = "center", zindex = Snacks.win.zindex(60), keys = { q = "close", ["<esc>"] = "close" } })
  else
    vim.cmd("botright split"); vim.api.nvim_win_set_buf(0, buf)
  end
  M.last_buf = buf
  return buf
end

function M.run(args)
  local flag = args[1] or "--dry-run"
  local root = project.root() or (A()._resolved or {}).root
  if not root then return A().err("no board selected; run :AISwarm project") end
  local schema = project.schema(root)
  if flag == "--dry-run" then
    A().run({ "migrate", "--dry-run" }, function(o)
      if o.code ~= 0 then return A().err(A().failure(o)) end
      local lines = vim.split(o.stdout, "\n", { trimempty = true })
      table.insert(lines, ""); table.insert(lines, "This is a read-only inventory. Run :AISwarm migrate --upgrade to convert (a verified backup is written first).")
      if schema == "migrating" then table.insert(lines, 1, "!! an interrupted migration exists: use :AISwarm migrate --resume or --rollback") end
      show("aiswarm migration inventory", lines)
    end)
  elseif flag == "--upgrade" or flag == "--resume" or flag == "--rollback" then
    local argv = { "migrate" }
    if flag ~= "--upgrade" then argv[#argv + 1] = flag end
    A().run(argv, function(o)
      if o.code ~= 0 then return A().err(A().failure(o)) end
      A().notify(vim.trim(o.stdout))
      project.open(root, { source = "explicit" })   -- reopen with the new schema; the scheduler is never started here
    end)
  else
    A().err("usage: AISwarm migrate [--dry-run|--upgrade|--resume|--rollback]")
  end
end

return M
