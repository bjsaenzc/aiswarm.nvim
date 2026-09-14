-- Semantic highlight groups linked to the theme; user definitions are preserved (SDD-050).
local H = {}
H.GROUPS = {
  AISwarmTitle = "Title", AISwarmMuted = "Comment", AISwarmSelected = "Visual", AISwarmRunning = "DiagnosticInfo",
  AISwarmQueued = "Comment", AISwarmBlocked = "DiagnosticWarn", AISwarmFailed = "DiagnosticError", AISwarmDone = "DiagnosticOk",
  AISwarmCancelled = "Comment", AISwarmBorder = "FloatBorder", AISwarmAccent = "Special", AISwarmHeader = "Title",
  AISwarmKey = "Identifier", AISwarmId = "Identifier", AISwarmProvider = "Comment", AISwarmStderr = "DiagnosticWarn",
  AISwarmStale = "DiagnosticWarn", AISwarmAttention = "DiagnosticError", AISwarmSection = "Statement", AISwarmField = "Label",
  AISwarmValue = "Normal", AISwarmHint = "Comment", AISwarmError = "ErrorMsg",
}
H.STATE = { running = "AISwarmRunning", queued = "AISwarmQueued", blocked = "AISwarmBlocked", succeeded = "AISwarmDone", failed = "AISwarmFailed",
  cancelled = "AISwarmCancelled", starting = "AISwarmRunning", stale = "AISwarmStale" }

--- Define defaults with `default = true` so an explicit user definition is never overridden.
function H.apply()
  for group, link in pairs(H.GROUPS) do vim.api.nvim_set_hl(0, group, { link = link, default = true }) end
end

function H.setup()
  H.apply()
  local aug = vim.api.nvim_create_augroup("AISwarmHighlights", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = aug, callback = H.apply })
end

function H.for_task(t)
  if t.state == "queued" and t.blockers and #t.blockers > 0 then return "AISwarmBlocked" end
  if t.state == "running" and t.health and (t.health.stale or t.health.input_required) then return "AISwarmStale" end
  return H.STATE[t.state] or "AISwarmMuted"
end

return H
