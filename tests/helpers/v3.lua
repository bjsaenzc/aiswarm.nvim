-- Helpers for v3 board tests: in-process runtime modules plus the CLI surface.
local sb = require("helpers.sandbox")
local M = {}
_G.AISWARM_PLUGIN_ROOT = sb.plugin
vim.env.AISWARM_TMUX_SOCKET = sb.socket   -- in-process tmux helpers use the dedicated test server

function M.mods()
  return {
    U = require("aiswarm.runtime.util"), B = require("aiswarm.runtime.board"), J = require("aiswarm.runtime.journal"),
    L = require("aiswarm.runtime.lock"), O = require("aiswarm.runtime.ops"), P = require("aiswarm.protocol"), R = require("aiswarm.runtime.reducer"),
  }
end

--- Initialize a v3 board under t:tmpdir(); returns root, ctx.
function M.board(t, name, opts)
  local m = M.mods()
  local dir = t:tmpdir(name or "v3")
  local root = dir .. "/.aiswarm"
  m.B.init(root, opts)
  return root, m.B.load(root)
end

--- CLI call against a v3 root (through bin/aiswarm → runtime/cli.lua).
function M.cli(root, args, opts)
  opts = opts or {}
  local env = sb.env(root, opts.env)
  env.AISWARM_TMUX_SOCKET = sb.socket
  return sb.run(vim.list_extend({ sb.bin("aiswarm") }, args), { env = env, cwd = opts.cwd or vim.fs.dirname(root), stdin = opts.stdin, timeout = opts.timeout })
end
function M.cli_json(t, root, args, opts)
  local r = M.cli(root, vim.list_extend(vim.list_extend({}, args), { "--json" }), opts)
  t:eq(r.code, 0, table.concat(args, " ") .. ": " .. r.stderr)
  local v, err = sb.json(r.stdout)
  t:ok(v, "json output: " .. tostring(err) .. " <" .. r.stdout .. ">")
  return v
end

function M.add(t, ctx, args)
  local m = M.mods()
  args = args or {}
  args.prompt = args.prompt or "do the thing\n"
  return m.O.add(ctx, args)
end

--- Queue n tasks in one committed transaction (fixture speed; production adds are one per command).
function M.bulk_add(ctx, n, opts)
  local m = M.mods()
  opts = opts or {}
  m.B.txn(ctx, { purpose = "bulk-add" }, function(state)
    local records = {}
    for i = 1, n do
      local id = ("T-%04d"):format(i)
      local path = ctx.paths.prompts .. "/" .. id .. "/r1.md"
      m.U.mkdirp(ctx.paths.prompts .. "/" .. id); m.U.write_atomic(path, (opts.prompt or "bulk") .. "\n")
      records[#records + 1] = { type = "task.queued", task_id = id, payload = { task = { id = id, title = "task " .. i, provider = "mock", depends_on = {}, priority = 50, timeout = opts.timeout or 1800, isolation = "shared",
        revision = 1, prompt_revision = 1, prompt_path = path, state = "queued", current_attempt_id = nil, attempts = {}, created_at = m.U.now_iso(), updated_at = m.U.now_iso() } } }
    end
    return records
  end)
end

function M.journal_records(root)
  local m = M.mods()
  return m.J.after(root, 0)
end

--- Fake provider environment for a worker run.
function M.provider_env(scenario, extra)
  local e = { AISWARM_PROVIDER_EXEC_mock = sb.fake_provider("fake-provider"), AISWARM_FAKE_SCENARIO = scenario or "success", AISWARM_FAKE_TICK_MS = "5" }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

return M
