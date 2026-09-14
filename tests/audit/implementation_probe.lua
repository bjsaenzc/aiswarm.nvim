-- Read-only implementation probes plus disposable file fixtures; intentionally outside *_test.lua.
-- Run: nvim --clean --headless -u NONE -i NONE -n -l tests/audit/implementation_probe.lua
-- Observations are diagnostic data, not passing acceptance tests. No workers or tmux are started.
local root = vim.fn.getcwd()
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
local S = require("aiswarm.store")
local A = require("aiswarm.ui.actions")
local observed = {}
S.reset(); S.board.board_id = "board-a"
S.tasks["T-001"] = { id = "T-001", state = "queued", revision = 1 }
local target = A.target("T-001")
S.board.board_id = "board-b"
observed.cross_board_target_accepted = A.revalidate(target)
S.reset()
for i = 1, 600 do S.apply_activity({ event_id = "e" .. i, kind = "progress", task_id = "T-001", attempt_id = "attempt-a", text = tostring(i) }) end
observed.per_attempt_records = #S.activity.records
observed.per_attempt_limit = S.LIMITS.per_attempt
S.reset()
for _, id in ipairs({ "attempt-a", "attempt-b" }) do S.apply_activity({ event_id = id, kind = "progress", task_id = "T-001", attempt_id = id, text = "Testing" }) end
observed.distinct_attempts_coalesced_to_records = #S.activity.records
S.reset()
S.apply_activity({ event_id = "raw", kind = "output", text = "x", raw = { payload = string.rep("x", 60000) } })
observed.accounted_bytes_for_60k_payload = S.activity.bytes
local state = { tasks = {}, attempts = {} }
require("aiswarm.runtime.reducer").apply(state, { type = "unknown.future.type", payload = { task = { id = "T-001", state = "failed" } } })
observed.unknown_event_changes_task = state.tasks["T-001"] ~= nil
local tmp = vim.fn.tempname(); vim.fn.mkdir(tmp, "p")
local function write(path, value) local f = assert(io.open(path, "wb")); f:write(value); f:close() end
local ok, err = xpcall(function()
  local loader = require("aiswarm.ui.loader")
  local path = tmp .. "/text"; write(path, "HEAD\nMIDDLE\nTAIL\n")
  local first, last
  loader.read(path, { max_bytes = 5 }, function(r) first = r.text end)
  assert(vim.wait(2000, function() return first ~= nil end), "head callback timed out")
  loader.read(path, { max_bytes = 5, tail = true }, function(r) last = r.text end)
  assert(vim.wait(2000, function() return last ~= nil end), "tail callback timed out")
  observed.head_read, observed.tail_read = first, last
  local J = require("aiswarm.runtime.journal")
  vim.fn.mkdir(tmp .. "/control", "p")
  local lines = { vim.json.encode({ control_seq = 1, type = "committed" }) }
  for i = 2, 101 do
    lines[#lines + 1] = vim.json.encode({ control_seq = i, txn = { id = "incomplete", last = false }, payload = { text = string.rep("x", 2048) } })
  end
  write(J.path(tmp), table.concat(lines, "\n") .. "\n")
  local recovered = J.recover(tmp)
  observed.incomplete_large_transaction_committed_seq = recovered.committed_seq
  observed.expected_last_committed_seq = 1
end, debug.traceback)
vim.fn.delete(tmp, "rf")
if not ok then error(err) end
io.stdout:write(vim.json.encode({ date = "2026-09-14", nvim = vim.version(), observations = observed }), "\n")
