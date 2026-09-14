-- tmux operations scoped to board and attempt ownership (SDD-028).
local U = require("aiswarm.runtime.util")
local T = {}

function T.argv(args)
  local base = { "tmux" }
  local sock = vim.env.AISWARM_TMUX_SOCKET
  if sock and sock ~= "" then vim.list_extend(base, { "-L", sock }) end
  return vim.list_extend(base, args)
end
function T.run(args, opts)
  local ok, o = pcall(function() return vim.system(T.argv(args), { text = true, env = opts and opts.env }):wait((opts and opts.timeout) or 10000) end)
  if not ok then return 127, "", tostring(o) end
  return o.code, o.stdout or "", o.stderr or ""
end
function T.available() return vim.fn.executable("tmux") == 1 end

function T.session_name(board_id, attempt_id) return ("aiswarm-%s-%s"):format(U.short(board_id), U.short(attempt_id)) end
function T.scheduler_session(board_id) return ("aiswarm-%s-scheduler"):format(U.short(board_id)) end

function T.has(session) return T.run({ "has-session", "-t", "=" .. session }) == 0 end

--- Stored ownership options of a session (nil when the session does not exist).
function T.owner(session)
  if not T.has(session) then return nil end
  local code, out = T.run({ "show-options", "-t", session, "-v", "@aiswarm_board" })
  if code ~= 0 then return { board_id = "", attempt_id = "", task_id = "" } end
  local _, attempt = T.run({ "show-options", "-t", session, "-v", "@aiswarm_attempt" })
  local _, task = T.run({ "show-options", "-t", session, "-v", "@aiswarm_task" })
  return { board_id = vim.trim(out), attempt_id = vim.trim(attempt), task_id = vim.trim(task) }
end

--- Verify a session belongs to this board (and attempt when given) before touching it.
function T.owned(session, board_id, attempt_id)
  local o = T.owner(session)
  if not o then return false, "no such session: " .. session end
  if o.board_id ~= board_id then return false, ("session %s belongs to another board (%s)"):format(session, o.board_id ~= "" and o.board_id or "unowned") end
  if attempt_id and o.attempt_id ~= attempt_id then return false, ("session %s belongs to attempt %s, not %s"):format(session, o.attempt_id, attempt_id) end
  return true
end

--- Spawn a detached session running argv in cwd with env, and stamp ownership. The command runs
--- directly in the new session (respawn-pane on a fresh pane fails intermittently on macOS); the
--- window option remain-on-exit and the ownership options are set immediately afterwards. A
--- command that exits before that (for example a missing executable) leaves no session and is
--- reported as a spawn failure right away.
function T.spawn(session, cwd, env, argv, owner)
  local cmd = {}
  for _, a in ipairs(argv) do cmd[#cmd + 1] = vim.fn.shellescape(a) end
  local args = { "new-session", "-d", "-s", session, "-c", cwd }
  for k, v in pairs(env or {}) do vim.list_extend(args, { "-e", k .. "=" .. v }) end
  args[#args + 1] = table.concat(cmd, " ")
  local code, err
  for attempt = 1, 5 do
    local _
    code, _, err = T.run(args)
    if code == 0 then break end
    if not vim.trim(err):match("fork failed") then break end
    vim.uv.sleep(50 * attempt)   -- transient pty allocation failure under a burst of sessions
  end
  if code ~= 0 then return false, "tmux new-session failed: " .. vim.trim(err) end
  local target = "=" .. session .. ":"
  T.run({ "set-option", "-w", "-t", target, "remain-on-exit", "on" })
  T.run({ "set-option", "-t", session, "@aiswarm_board", owner.board_id })
  T.run({ "set-option", "-t", session, "@aiswarm_attempt", owner.attempt_id or "" })
  T.run({ "set-option", "-t", session, "@aiswarm_task", owner.task_id or "" })
  if not T.has(session) then return false, "command exited before the session could be retained (is the executable present?)" end
  local _, pane = T.run({ "display-message", "-p", "-t", target, "#{pane_id}" })
  return true, vim.trim(pane)
end

function T.kill(session, board_id, attempt_id)
  local ok, err = T.owned(session, board_id, attempt_id)
  if not ok then return false, err end
  local code, _, e = T.run({ "kill-session", "-t", "=" .. session })
  return code == 0, e
end

--- Sessions stamped with this board id.
function T.list_owned(board_id)
  local code, out = T.run({ "list-sessions", "-F", "#{session_name}\t#{@aiswarm_board}\t#{@aiswarm_attempt}\t#{@aiswarm_task}\t#{pane_dead}" })
  local list = {}
  if code ~= 0 then return list end
  for line in out:gmatch("[^\n]+") do
    local name, board, attempt, task, dead = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if board == board_id then list[#list + 1] = { session = name, attempt_id = attempt, task_id = task, pane_dead = dead == "1" } end
  end
  return list
end

function T.capture(session, board_id, lines)
  local ok, err = T.owned(session, board_id)
  if not ok then return nil, err end
  local code, out, e = T.run({ "capture-pane", "-p", "-e", "-S", "-" .. tostring(lines or 120), "-t", "=" .. session .. ":" })
  if code ~= 0 then return nil, vim.trim(e) end
  return out
end

function T.pane_dead(session)
  local code, out = T.run({ "display-message", "-p", "-t", "=" .. session .. ":", "#{pane_dead}" })
  if code ~= 0 then return nil end
  return vim.trim(out) == "1"
end

return T
