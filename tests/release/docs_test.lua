-- SDD-096: documentation, help tags, links, notices and the documented quickstart.
local sb = require("helpers.sandbox")
return {
  { id = "docs.help_tags_and_links_resolve", tasks = { "SDD-096" }, suites = { "core" }, run = function(t)
    local docdir = t:tmpdir("doc")
    for _, f in ipairs({ "aiswarm.txt", "hive.txt" }) do sb.write(docdir .. "/" .. f, sb.read(sb.plugin .. "/doc/" .. f)) end
    vim.cmd("helptags " .. vim.fn.fnameescape(docdir))
    local tags = sb.read(docdir .. "/tags")
    for _, tag in ipairs({ "aiswarm-setup", ":AISwarm", "aiswarm-keys", "aiswarm-compat", "aiswarm-limits", "hive-setup" }) do t:ok(tags:find(tag, 1, true), "tag " .. tag) end
    -- every |tag| referenced inside aiswarm.txt exists
    for ref in sb.read(sb.plugin .. "/doc/aiswarm.txt"):gmatch("|([%w%-:]+)|") do t:ok(tags:find("\n" .. ref .. "\t", 1, true) or tags:find("^" .. ref .. "\t"), "help link " .. ref) end
    -- README local links and referenced files resolve
    local readme = sb.read(sb.repo .. "/README.md")
    for target in readme:gmatch("%]%(([^)#h][^)]*)%)") do
      target = target:gsub("#.*$", "")
      if target ~= "" and not target:match("^https?://") then t:ok(sb.exists(sb.repo .. "/" .. target), "README link " .. target) end
    end
    for _, path in ipairs({ "scripts/aiswarm-quickstart.sh", "docs/aiswarm-decisions/0001-worker-runtime.md" }) do t:ok(sb.exists(sb.repo .. "/" .. path), path) end
    for _, path in ipairs({ "bin/aiswarm", "LICENSE", "THIRD_PARTY_NOTICES.md" }) do t:ok(sb.exists(sb.plugin .. "/" .. path), path) end
    t:ok(readme:find("`:HiveKill` keeps its cancel%-and%-requeue meaning"), "old kill semantics unmistakable")
    t:ok(readme:find("SDD%-101–107") and readme:find("not implemented"), "optional capabilities unmistakable")
    t:ok(readme:find("headless Neovim"), "standalone runtime prerequisite stated")
    t:ok(not readme:find("hive.nvim/bin/hive`") or readme:find("Transitional aliases"), "old binary path documented as transitional")
    local notices = sb.read(sb.plugin .. "/THIRD_PARTY_NOTICES.md")
    t:ok(notices:find("public domain / CC0", 1, true) and notices:find("MIT", 1, true), "notices carry the pre-existing licence statements")
    t:ok(sb.read(sb.plugin .. "/bin/aiswarm"):find("License: public domain / CC0", 1, true), "backend notice retained in the script")
  end },
  { id = "docs.quickstart_runs_with_mock", tasks = { "SDD-096" }, suites = { "core" }, run = function(t)
    t:defer(function() sb.tmux({ "kill-server" }) end)
    local o = sb.run({ "bash", sb.repo .. "/scripts/aiswarm-quickstart.sh" }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME, TMPDIR = vim.env.TMPDIR, AISWARM_NVIM = vim.env.AISWARM_NVIM, AISWARM_MOCK_SLEEP = "0", AISWARM_QUIET_LEGACY = "1" }, timeout = 120000 })
    t:eq(o.code, 0, o.stdout .. o.stderr); t:match(o.stdout, "== result: T%-001 succeeded")
    t:ok(o.stdout:find('"frame":"snapshot"', 1, true), "the documented stream example resolves the renamed binary")
  end },
}
