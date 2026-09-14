-- Workspace test helpers: virtual screen size, keyboard input, buffer text.
local M = {}
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
local v3 = require("helpers.v3")

function M.screen(cols, lines) vim.o.columns, vim.o.lines = cols, lines end

--- Open a v3 board with tasks and the workspace at a given screen size.
function M.board_with_tasks(t, n, opts)
  opts = opts or {}
  local root = v3.board(t, opts.name or "ws")
  for i = 1, n or 3 do v3.cli_json(t, root, { "add", "--id", ("T-%03d"):format(i), "--title", ("task %d"):format(i) }, { stdin = ("prompt %d\n"):format(i) }) end
  local A = pl.setup(t, root, opts.setup)
  pl.refresh(t, A)
  return root, A
end

function M.open(t, opts)
  local ws = require("aiswarm.ui.workspace")
  ws.open(opts or {})
  t:defer(function() pcall(ws.close) end)
  M.flush()
  return ws
end

function M.flush()
  local R = require("aiswarm.ui.render")
  R.flush(); vim.wait(20); R.flush()
end

--- Feed normal-mode keys and process them synchronously.
function M.keys(k)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "x", false)
  M.flush()
end

function M.lines(buf, from, to) return vim.api.nvim_buf_get_lines(buf, from or 0, to or -1, false) end
function M.text(buf) return table.concat(M.lines(buf), "\n") end

--- Refresh the store from the backend and flush renders.
function M.refresh(t, A) pl.refresh(t, A); M.flush() end

return M
