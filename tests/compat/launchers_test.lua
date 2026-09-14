-- Canonical launcher quoting and exit status on both board schemas.
local sb = require("helpers.sandbox")
local v3 = require("helpers.v3")
local cases = {}
for _, schema in ipairs({ "v2", "v3" }) do
  cases[#cases + 1] = { id = "launcher.quoted_arguments_" .. schema, tasks = { "SDD-010" }, suites = { "core", "compatibility" }, run = function(t)
    local root = schema == "v2" and sb.legacy_board(t) or v3.board(t)
    local pf = t:tmpdir("prompts") .. "/my prompt file.md"
    local prompt = "quoted 'prompt' with spaces\n"
    sb.write(pf, prompt)
    local title = 'spaced "title" here'
    local added = sb.aiswarm(root, { "add", "--id", "T-001", "--title", title, "--file", pf })
    t:eq(added.code, 0, added.stderr)
    local shown = sb.aiswarm(root, { "show", "T-001" })
    t:eq(shown.code, 0, shown.stderr)
    local decoded = sb.json(shown.stdout)
    t:eq((schema == "v3" and decoded.task or decoded).title, title)
    local path = schema == "v2" and "/tasks/prompts/T-001.md" or "/prompts/T-001/r1.md"
    t:eq(sb.read(root .. path), prompt)
    local version = sb.aiswarm(root, { "--version" })
    t:eq(version.code, 0); t:match(version.stdout, "^aiswarm ")
    t:eq(sb.aiswarm(root, { "show", "NOPE" }).code, 2)
  end }
end
return cases
