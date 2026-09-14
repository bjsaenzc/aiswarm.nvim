-- SDD-010: canonical launchers and old-name wrappers.
local sb = require("helpers.sandbox")
return {
  { id = "compat.launchers.wrappers_preserve_argv", tasks = { "SDD-010" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    local dir = t:tmpdir("prompts")
    local pf = dir .. "/my prompt file.md"; sb.write(pf, "quoted 'prompt' with spaces\n")
    local a = sb.hive(root, { "add", "--id", "T-001", "--title", "spaced \"title\" here", "--file", pf }); t:eq(a.code, 0, a.stderr)
    local b = sb.aiswarm(root, { "add", "--id", "T-002", "--title", "spaced \"title\" here", "--file", pf }); t:eq(b.code, 0, b.stderr)
    local s1, s2 = sb.hive(root, { "show", "T-001" }), sb.aiswarm(root, { "show", "T-002" })
    local j1, j2 = sb.json(s1.stdout), sb.json(s2.stdout)
    t:eq(j1.title, "spaced \"title\" here"); t:eq(j2.title, j1.title)
    t:eq(sb.read(root .. "/tasks/prompts/T-001.md"), sb.read(root .. "/tasks/prompts/T-002.md"))
    local v1, v2 = sb.hive(root, { "--version" }), sb.aiswarm(root, { "--version" })
    t:eq(v1.stdout, v2.stdout); t:eq(v1.code, v2.code)
    local e1, e2 = sb.hive(root, { "show", "NOPE" }), sb.aiswarm(root, { "show", "NOPE" })
    t:eq(e1.code, e2.code); t:eq(e1.stderr, e2.stderr)
  end },
  { id = "compat.launchers.old_documented_path_resolves", tasks = { "SDD-010" }, suites = { "core", "compatibility" }, run = function(t)
    local old = sb.repo .. "/lua/myPlugins/hive.nvim/bin/hive"
    if not sb.exists(sb.repo .. "/lua/myPlugins/hive.nvim") then t:skip("legacy hive.nvim directory is not part of this checkout") end
    t:eq(vim.fn.executable(old), 1, "transitional alias exists")
    local o = sb.run({ old, "--version" }, { env = sb.env(t:tmpdir("x")) }); t:eq(o.code, 0); t:match(o.stdout, "^aiswarm")
    local push = sb.repo .. "/lua/myPlugins/hive.nvim/bin/hive-push"
    t:eq(vim.fn.executable(push), 1)
  end },
  { id = "compat.launchers.never_recurse", tasks = { "SDD-010" }, suites = { "core", "compatibility" }, run = function(t)
    for _, name in ipairs({ "hive", "hive-push" }) do
      local src = sb.read(sb.plugin .. "/bin/" .. name)
      t:ok(src:match('exec "[^\n]*/aiswarm'), name .. " execs the canonical binary")
      t:ok(not src:match("/hive[\"' ]"), name .. " never references itself")
    end
    local canonical = sb.read(sb.plugin .. "/bin/aiswarm")
    t:ok(not canonical:match("bin/hive"), "aiswarm never calls the wrapper")
  end },
}
