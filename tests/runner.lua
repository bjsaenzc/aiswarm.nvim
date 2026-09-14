-- aiswarm test runner (SDD-001). Executed by scripts/test-aiswarm.sh inside a
-- clean headless Neovim:  nvim --clean --headless -u NONE -i NONE -l runner.lua
--
-- Test files: <plugin>/tests/**/*_test.lua, each returning a list of cases:
--   { id = "area.case", tasks = {"SDD-001"}, suites = {"core"}, run = function(t) ... end }
-- A case passes when `run` returns, fails when it raises, and is recorded as
-- "unverified" when it calls t.skip(reason) (never counted as a pass).
local uv = vim.uv
local env = vim.env
local plugin = env.AISWARM_TEST_PLUGIN or vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
local run_dir = env.AISWARM_TEST_RUN_DIR
if not run_dir then
  io.stderr:write("runner.lua must be started through scripts/test-aiswarm.sh\n")
  os.exit(3)
end

-- ---------------------------------------------------------------- arguments
local opts = { tasks = {}, suites = {}, cases = {}, list = false, verbose = false }
local argv = _G.arg or {}
local i = 1
while i <= #argv do
  local a = argv[i]
  if a == "--task" then opts.tasks[#opts.tasks + 1] = argv[i + 1]; i = i + 2
  elseif a == "--suite" then opts.suites[#opts.suites + 1] = argv[i + 1]; i = i + 2
  elseif a == "--case" then opts.cases[#opts.cases + 1] = argv[i + 1]; i = i + 2
  elseif a == "--list" then opts.list = true; i = i + 1
  elseif a == "--verbose" or a == "-v" then opts.verbose = true; i = i + 1
  elseif a == "--record" then opts.record = true; i = i + 1
  elseif a == "--child" then opts.child = true; i = i + 1
  else io.stderr:write("runner: unknown argument " .. tostring(a) .. "\n"); os.exit(2) end
end
for _, list in ipairs({ opts.tasks, opts.suites, opts.cases }) do
  for _, v in ipairs(list) do if not v or v == "" then io.stderr:write("runner: missing selector value\n"); os.exit(2) end end
end

-- ---------------------------------------------------------------- runtime paths
vim.opt.runtimepath:prepend(plugin)
package.path = plugin .. "/lua/?.lua;" .. plugin .. "/lua/?/init.lua;" .. plugin .. "/tests/?.lua;" .. plugin .. "/tests/?/init.lua;" .. package.path
if env.AISWARM_TEST_SNACKS and env.AISWARM_TEST_SNACKS ~= "" then
  vim.opt.runtimepath:append(env.AISWARM_TEST_SNACKS)
end
vim.opt.swapfile = false
vim.o.shada = ""

-- ---------------------------------------------------------------- discovery
local files = vim.fs.find(function(name) return name:match("_test%.lua$") ~= nil end,
  { path = plugin .. "/tests", type = "file", limit = math.huge })
table.sort(files)
local cases, seen = {}, {}
for _, file in ipairs(files) do
  local chunk, load_err = loadfile(file)
  if not chunk then io.stderr:write("runner: cannot load " .. file .. ": " .. tostring(load_err) .. "\n"); os.exit(3) end
  local ok, list = pcall(chunk)
  if not ok then io.stderr:write("runner: error loading " .. file .. ": " .. tostring(list) .. "\n"); os.exit(3) end
  for _, c in ipairs(list or {}) do
    if type(c.id) ~= "string" or type(c.run) ~= "function" then
      io.stderr:write("runner: malformed case in " .. file .. "\n"); os.exit(3)
    end
    if seen[c.id] then io.stderr:write("runner: duplicate case id " .. c.id .. "\n"); os.exit(3) end
    seen[c.id] = true
    c.file, c.tasks, c.suites = file, c.tasks or {}, c.suites or {}
    cases[#cases + 1] = c
  end
end

local function has(list, value) for _, v in ipairs(list) do if v == value then return true end end return false end
local known_tasks, known_suites = {}, {}
for _, c in ipairs(cases) do
  for _, t in ipairs(c.tasks) do known_tasks[t] = true end
  for _, s in ipairs(c.suites) do known_suites[s] = true end
end

if opts.list then
  for _, c in ipairs(cases) do
    io.stdout:write(string.format("%-40s tasks=%s suites=%s\n", c.id, table.concat(c.tasks, ","), table.concat(c.suites, ",")))
  end
  os.exit(0)
end

local selected = {}
if #opts.tasks + #opts.suites + #opts.cases == 0 then
  io.stderr:write("runner: select cases with --task ID, --suite NAME or --case ID (or --list)\n"); os.exit(2)
end
for _, t in ipairs(opts.tasks) do
  if not known_tasks[t] then io.stderr:write("runner: no automated cases are tagged " .. t .. "\n"); os.exit(2) end
end
for _, s in ipairs(opts.suites) do
  if not known_suites[s] then io.stderr:write("runner: unknown suite " .. s .. "\n"); os.exit(2) end
end
for _, id in ipairs(opts.cases) do
  if not seen[id] then io.stderr:write("runner: unknown case " .. id .. "\n"); os.exit(2) end
end
for _, c in ipairs(cases) do
  local pick = has(opts.cases, c.id)
  for _, t in ipairs(opts.tasks) do if has(c.tasks, t) then pick = true end end
  for _, s in ipairs(opts.suites) do if has(c.suites, s) then pick = true end end
  if pick then selected[#selected + 1] = c end
end
if #selected == 0 then io.stderr:write("runner: selection is empty\n"); os.exit(2) end

-- ---------------------------------------------------------------- assertions
local Skip = {}
local T = {}
T.__index = T

local function inspect(v) return vim.inspect(v, { newline = " ", indent = "" }) end
function T.fail(_, msg) error({ assertion = msg or "failed" }, 2) end
function T.ok(t, cond, msg) if not cond then t:fail(msg or "expected truthy value") end return cond end
function T.eq(t, actual, expected, msg)
  if not vim.deep_equal(actual, expected) then
    t:fail((msg and (msg .. ": ") or "") .. "expected " .. inspect(expected) .. " but got " .. inspect(actual))
  end
end
function T.neq(t, actual, unexpected, msg)
  if vim.deep_equal(actual, unexpected) then t:fail((msg and (msg .. ": ") or "") .. "did not expect " .. inspect(unexpected)) end
end
function T.match(t, s, pattern, msg)
  if type(s) ~= "string" or not s:match(pattern) then
    t:fail((msg and (msg .. ": ") or "") .. "expected " .. inspect(s) .. " to match " .. pattern)
  end
end
function T.errors(t, fn, pattern)
  local ok, err = pcall(fn)
  if ok then t:fail("expected an error" .. (pattern and (" matching " .. pattern) or "")) end
  if pattern and not tostring(err):match(pattern) then t:fail("error " .. inspect(err) .. " does not match " .. pattern) end
  return err
end
function T.skip(_, reason) error(setmetatable({ reason = reason or "skipped" }, Skip), 2) end
function T.log(t, ...) local parts = {} for _, v in ipairs({ ... }) do parts[#parts + 1] = type(v) == "string" and v or inspect(v) end t.logs[#t.logs + 1] = table.concat(parts, " ") end
--- Poll `cond` while pumping the event loop; fails after `ms`.
function T.wait(t, ms, cond, msg)
  if vim.wait(ms, cond, 10) then return true end
  t:fail(msg or ("timed out after " .. ms .. "ms"))
end
function T.sleep(_, ms) vim.wait(ms, function() return false end, 10) end
--- Fresh scratch directory inside the sandbox, recorded for cleanup.
function T.tmpdir(t, name)
  local dir = run_dir .. "/tmp/" .. t.case.id:gsub("[^%w]", "_") .. "-" .. (name or tostring(#t.dirs + 1))
  vim.fn.mkdir(dir, "p")
  t.dirs[#t.dirs + 1] = dir
  return dir
end
function T.defer(t, fn) t.deferred[#t.deferred + 1] = fn end
T.plugin, T.run_dir, T.repo = plugin, run_dir, env.AISWARM_TEST_REPO
T.tmux_socket = env.AISWARM_TEST_TMUX_SOCKET

-- ---------------------------------------------------------------- execution
-- vim.notify prints into the headless output; collect it per case instead.
_G.__aiswarm_notifications = {}
vim.notify = function(msg, level, o) table.insert(_G.__aiswarm_notifications, { msg = tostring(msg), level = level, opts = o }) end
local results, counts = {}, { passed = 0, failed = 0, unverified = 0 }
local started_all = uv.hrtime()
local function run_child(c)
  -- crash-prone cases (real windows on a resized headless grid) run in their own process
  local argv = { env.AISWARM_NVIM or vim.v.progpath, "--clean", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n", "-l", plugin .. "/tests/runner.lua", "--case", c.id, "--child" }
  local o = vim.system(argv, { text = true }):wait(tonumber(os.getenv("AISWARM_TEST_CHILD_TIMEOUT_MS")) or 600000)
  local line = (o.stdout or ""):match("RESULT (%b{})")
  if line then
    local ok, res = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
    if ok then return res end
  end
  return { status = "failed", detail = ("child process exited with code %s and no result: %s"):format(tostring(o.code), ((o.stderr or "") .. (o.stdout or "")):sub(-400)), logs = {} }
end

for _, c in ipairs(selected) do
  _G.__aiswarm_notifications = {}
  local t = setmetatable({ case = c, logs = {}, dirs = {}, deferred = {}, notifications = _G.__aiswarm_notifications }, T)
  local started = uv.hrtime()
  local status, detail
  if c.isolated and not opts.child then
    local res = run_child(c)
    status, detail, t.logs = res.status, res.detail, res.logs or {}
  else
    local ok, err = xpcall(function() c.run(t) end, function(e)
      if type(e) == "table" and (getmetatable(e) == Skip or e.assertion) then return e end
      return { assertion = tostring(e), traceback = debug.traceback("", 2) }
    end)
    for j = #t.deferred, 1, -1 do pcall(t.deferred[j]) end
    status, detail = "passed", nil
    if not ok then
      if getmetatable(err) == Skip then status, detail = "unverified", err.reason
      else
        status, detail = "failed", (err.assertion or tostring(err)) .. (err.traceback or "")
        if #t.notifications > 0 then
          local notes = {}
          for _, n in ipairs(t.notifications) do notes[#notes + 1] = "notify: " .. n.msg:gsub("\n", " ") end
          detail = detail .. "\n" .. table.concat(notes, "\n")
        end
      end
    end
  end
  counts[status] = counts[status] + 1
  local ms = (uv.hrtime() - started) / 1e6
  results[#results + 1] = { id = c.id, file = c.file:sub(#plugin + 2), tasks = c.tasks, suites = c.suites,
    status = status, detail = detail, ms = ms, logs = t.logs }
  if opts.child then
    io.stdout:write("RESULT " .. vim.json.encode({ status = status, detail = detail, logs = t.logs }) .. "\n"); io.stdout:flush()
    os.exit(0)
  end
  local mark = ({ passed = "PASS", failed = "FAIL", unverified = "UNVERIFIED" })[status]
  io.stdout:write(string.format("%-10s %-44s %7.1fms%s\n", mark, c.id, ms, detail and ("\n           " .. detail:gsub("\n", "\n           ")) or ""))
  if opts.verbose then for _, l in ipairs(t.logs) do io.stdout:write("           | " .. l .. "\n") end end
  io.stdout:flush()
end

local versions = {
  nvim = tostring(vim.version()),
  tmux = (vim.fn.system({ "tmux", "-V" }) or ""):gsub("%s+$", ""),
  jq = (vim.fn.system({ "jq", "--version" }) or ""):gsub("%s+$", ""),
  bash = (vim.fn.system({ "bash", "-c", "echo $BASH_VERSION" }) or ""):gsub("%s+$", ""),
  os = uv.os_uname().sysname .. " " .. uv.os_uname().release,
}
local commit = (vim.fn.system({ "git", "-C", env.AISWARM_TEST_REPO or plugin, "rev-parse", "--short", "HEAD" }) or ""):gsub("%s+$", "")
local evidence = {
  run_id = env.AISWARM_TEST_RUN_ID, plugin = plugin, commit = commit, versions = versions,
  selection = opts, counts = counts, total_ms = (uv.hrtime() - started_all) / 1e6, results = results,
}
local f = assert(io.open(run_dir .. "/evidence.json", "w"))
f:write(vim.json.encode(evidence)); f:close()
io.stdout:write(string.format("\n%d passed, %d failed, %d unverified (%.0fms)\n", counts.passed, counts.failed, counts.unverified, evidence.total_ms))
io.stdout:flush()

-- ---------------------------------------------------------------- evidence ledger (SDD-008)
if opts.record and env.AISWARM_TEST_REPO then
  local ledger = env.AISWARM_TEST_REPO .. "/docs/aiswarm-evidence/ledger.md"
  local text = (function() local f = io.open(ledger, "r"); if not f then return nil end local s = f:read("*a"); f:close(); return s end)()
    or "# aiswarm evidence ledger\n\nAutomated records written by `scripts/test-aiswarm.sh --task <ID> --record`. Manual records live in `manual/`.\nOne section per task; a rerun replaces the section.\n"
  for _, task in ipairs(opts.tasks) do
    local mine, st = {}, { passed = 0, failed = 0, unverified = 0 }
    for _, r in ipairs(results) do if has(r.tasks, task) then mine[#mine + 1] = r; st[r.status] = st[r.status] + 1 end end
    local status = st.failed > 0 and "failed" or (st.unverified > 0 and "unverified" or "passed")
    local lines = {
      "### " .. task .. " — " .. status, "",
      "- Kind: automated", "- Status: " .. status, "- Commit: " .. (commit ~= "" and commit or "unknown"),
      "- Command: `bash scripts/test-aiswarm.sh --task " .. task .. "`",
      ("- Environment: Neovim %s, %s, %s, bash %s, %s"):format(versions.nvim, versions.tmux, versions.jq, versions.bash, versions.os),
      "- Run: " .. tostring(env.AISWARM_TEST_RUN_ID), "- Recorded: " .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
      "- Expected: every case tagged " .. task .. " passes",
      ("- Actual: %d passed, %d failed, %d unverified"):format(st.passed, st.failed, st.unverified),
      "- Artifacts: `artifacts/aiswarm/" .. tostring(env.AISWARM_TEST_RUN_ID) .. "/evidence.json`",
      "- Cases:",
    }
    for _, r in ipairs(mine) do lines[#lines + 1] = ("  - %s: %s%s"):format(r.id, r.status, r.detail and (" — " .. r.detail:gsub("\n.*", "")) or "") end
    local section = table.concat(lines, "\n") .. "\n\n"
    local pattern_start = text:find("\n### " .. task:gsub("%-", "%%-") .. " — ", 1)
    if pattern_start then
      local next_start = text:find("\n### SDD%-", pattern_start + 1)
      text = text:sub(1, pattern_start) .. section .. (next_start and text:sub(next_start + 1) or "")
    else
      text = text .. "\n" .. section
    end
    local f = assert(io.open(ledger, "w")); f:write(text); f:close()
    io.stdout:write("recorded " .. task .. " (" .. status .. ") in docs/aiswarm-evidence/ledger.md\n")
  end
end
os.exit(counts.failed > 0 and 1 or 0)
