-- Disposable board/tmux/provider fixtures for tests (SDD-001).
local M = {}
local env = vim.env

M.plugin = env.AISWARM_TEST_PLUGIN
M.repo = env.AISWARM_TEST_REPO
M.socket = env.AISWARM_TEST_TMUX_SOCKET

--- Absolute path to a bundled executable, preferring the canonical name.
function M.bin(name)
  local p = M.plugin .. "/bin/" .. name
  if vim.fn.executable(p) == 1 then return p end
  return nil
end

--- Environment for a backend invocation against `root`. Legacy and canonical
--- variables are both set so either binary resolves the same board.
function M.env(root, extra)
  local e = {
    HIVE_ROOT = root, AISWARM_ROOT = root, PATH = env.PATH, HOME = env.HOME, TMPDIR = env.TMPDIR,
    TMUX_TMPDIR = env.TMUX_TMPDIR or env.TMPDIR, AISWARM_TEST_TMUX_SOCKET = M.socket, AISWARM_TMUX_SOCKET = M.socket, AISWARM_NVIM = env.AISWARM_NVIM,
    HIVE_PROVIDER = "mock", AISWARM_PROVIDER = "mock", HIVE_MOCK_SLEEP = "0", AISWARM_MOCK_SLEEP = "0",
    XDG_CONFIG_HOME = env.XDG_CONFIG_HOME, XDG_DATA_HOME = env.XDG_DATA_HOME, XDG_STATE_HOME = env.XDG_STATE_HOME,
  }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

--- Run a command synchronously. Returns { code, stdout, stderr }.
function M.run(argv, opts)
  opts = opts or {}
  local o = vim.system(argv, { text = true, env = opts.env, cwd = opts.cwd, stdin = opts.stdin, timeout = opts.timeout or 20000 }):wait()
  return { code = o.code, stdout = o.stdout or "", stderr = o.stderr or "" }
end

--- Run the legacy hive CLI against a board.
function M.hive(root, args, opts)
  opts = opts or {}
  local bin = M.bin("hive") or error("bin/hive not found")
  local env2 = M.env(root, opts.env)
  return M.run(vim.list_extend({ bin }, args), { env = env2, cwd = opts.cwd or vim.fs.dirname(root), stdin = opts.stdin, timeout = opts.timeout })
end

--- Run the canonical aiswarm CLI (falls back to hive while it does not exist).
function M.aiswarm(root, args, opts)
  opts = opts or {}
  local bin = M.bin("aiswarm") or M.bin("hive") or error("no backend executable")
  local env2 = M.env(root, opts.env)
  return M.run(vim.list_extend({ bin }, args), { env = env2, cwd = opts.cwd or vim.fs.dirname(root), stdin = opts.stdin, timeout = opts.timeout })
end

--- tmux on the dedicated test socket.
function M.tmux(args, opts)
  return M.run(vim.list_extend({ "tmux", "-L", M.socket }, args), opts)
end

function M.json(text)
  local ok, v = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  return ok and v or nil, ok and nil or v
end

function M.read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end
function M.write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w")); f:write(text); f:close()
end
function M.exists(path) return vim.uv.fs_stat(path) ~= nil end

--- Create an initialized legacy v2 board under t:tmpdir(). Returns root.
function M.legacy_board(t, name)
  local dir = t:tmpdir(name or "board")
  local root = dir .. "/.hive"
  local r = M.hive(root, { "init" })
  t:eq(r.code, 0, "hive init: " .. r.stderr)
  return root
end

--- Add a task with an inline prompt to a legacy board.
function M.legacy_add(t, root, args, prompt)
  local r = M.hive(root, vim.list_extend({ "add" }, args), { stdin = prompt or "do the thing\n" })
  t:eq(r.code, 0, "hive add: " .. r.stderr)
  return vim.trim(r.stdout)
end

--- Fake provider script directory. Files are executable scripts under tests/fixtures/providers.
function M.fake_provider(name)
  local p = M.plugin .. "/tests/fixtures/providers/" .. name
  return vim.fn.executable(p) == 1 and p or nil
end

--- Sleep while pumping the loop.
function M.sleep(ms) vim.wait(ms, function() return false end, 5) end

return M
