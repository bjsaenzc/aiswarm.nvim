-- SDD-015: explicit project session ownership.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
local function project() return require("aiswarm.project") end
return {
  { id = "compat.project().nested_and_symlink_discovery", tasks = { "SDD-015" }, suites = { "core", "compatibility" }, run = function(t)
    local dir = t:tmpdir("proj")
    local root = sb.legacy_board(t, "proj-board")
    local base = vim.fs.dirname(root)
    vim.fn.mkdir(base .. "/a/b", "p")
    vim.env.AISWARM_ROOT = nil
    local r = project().resolve({}, base .. "/a/b")
    t:eq(r.root, root); t:eq(r.source, "discovery"); t:eq(r.schema, "v2")
    local link = dir .. "/link"; vim.uv.fs_symlink(base, link)
    local r2 = project().resolve({}, link .. "/a")
    t:eq(r2.root, root, "symlinked cwd resolves to the canonical board path")
    local r3 = project().resolve({ root = link .. "/.aiswarm/" }, dir)
    t:eq(r3.root, root, "explicit option canonicalized (symlink + trailing slash)")
  end },
  { id = "compat.project().cwd_change_does_not_retarget", tasks = { "SDD-015" }, suites = { "core", "compatibility" }, run = function(t)
    local root1 = sb.legacy_board(t, "one"); local root2 = sb.legacy_board(t, "two")
    local A = pl.setup(t, root1)
    local cwd = vim.uv.cwd(); vim.cmd.cd(vim.fs.dirname(root2)); t:defer(function() vim.cmd.cd(cwd) end)
    t:eq(A.root(), root1, "cwd change alone keeps the session")
    local s = project().suggestion()
    t:ok(s and s.root == root2, "a switch is suggested, not applied")
  end },
  { id = "compat.project().explicit_switch_keeps_prefs_invalidates_callbacks", tasks = { "SDD-015" }, suites = { "core", "compatibility" }, run = function(t)
    local root1 = sb.legacy_board(t, "one"); local root2 = sb.legacy_board(t, "two")
    local A = pl.setup(t, root1, { peek_lines = 33 })
    local token = project().token()
    local result
    A.run({ "json" }, function(o) result = o end)   -- in flight during the switch
    project().open(root2)
    t:eq(A.root(), root2); t:eq(A.config.peek_lines, 33, "preferences preserved across switch")
    t:eq(project().alive(token), false)
    t:wait(5000, function() return result ~= nil end)
    t:eq(result.code, 125, "obsolete callback receives a project-changed result, not data")
    t:eq(project().current.generation, token + 1)
  end },
  { id = "compat.project().open_creates_nothing", tasks = { "SDD-015" }, suites = { "core", "compatibility" }, run = function(t)
    local dir = t:tmpdir("empty")
    vim.env.AISWARM_ROOT = nil
    local r = project().resolve({}, dir)
    t:eq(r.candidate, true); t:eq(r.schema, "missing")
    pl.unload(); local A = require("aiswarm")
    local cwd = vim.uv.cwd(); vim.cmd.cd(dir); t:defer(function() vim.cmd.cd(cwd) end)
    A.setup({ bin = sb.bin("aiswarm"), follow = false, register_server = false })
    t:defer(function() project().close() end)
    vim.wait(100)
    t:ok(not sb.exists(dir .. "/.aiswarm") and not sb.exists(dir .. "/.aiswarm"), "opening never creates a board")
  end },
}
