-- SDD-008: the validator reports duplicate tasks, missing dependencies, cycles,
-- absent evidence and nonexistent artifacts, and accepts the real plan.
local sb = require("helpers.sandbox")
local validator = sb.plugin .. "/tests/plan_validator.lua"
local plan_src = sb.read(sb.repo .. "/docs/aiswarm-implementation-sdd-plan.md")

local function validate(t, plan_text, evidence_dir, extra)
  local dir = t:tmpdir("plan")
  local plan = dir .. "/docs/plan.md"; sb.write(plan, plan_text)
  evidence_dir = evidence_dir or (dir .. "/docs/evidence"); vim.fn.mkdir(evidence_dir .. "/manual", "p")
  local o = sb.run(vim.list_extend({ vim.env.AISWARM_NVIM, "--clean", "--headless", "--noplugin", "-u", "NONE", "-i", "NONE", "-n", "-l", validator, plan, evidence_dir }, extra or {}),
    { env = { PATH = vim.env.PATH, HOME = vim.env.HOME } })
  return o
end
local mini = [[
| Requirement | Source | Owning tasks |
|---|---|---|
| R01 Thing | x | SDD-001–003 |

#### [ ] SDD-001 — first

- **Requires:** none. **Requirement:** R01. **Scope:** x.

#### [ ] SDD-002 — second

- **Requires:** SDD-001. **Requirement:** R01. **Scope:** x.

#### [ ] SDD-003 — third

- **Requires:** SDD-001, SDD-002. **Requirement:** R01. **Scope:** x.
]]
return {
  { id = "plan.real_plan_is_valid", tasks = { "SDD-008" }, suites = { "core" }, run = function(t)
    local o = validate(t, plan_src, sb.repo .. "/docs/aiswarm-evidence", { "--allow-missing-artifacts" })
    t:eq(o.code, 0, o.stdout .. o.stderr); t:match(o.stdout, "107 tasks")
  end },
  { id = "plan.minimal_valid", tasks = { "SDD-008" }, suites = { "core" }, run = function(t)
    local o = validate(t, mini); t:eq(o.code, 0, o.stdout)
  end },
  { id = "plan.duplicate_task_reported", tasks = { "SDD-008" }, suites = { "core" }, run = function(t)
    local o = validate(t, mini .. "\n#### [ ] SDD-002 — again\n\n- **Requires:** none. **Requirement:** R01.\n")
    t:eq(o.code, 1); t:match(o.stdout, "duplicate: SDD%-002")
  end },
  { id = "plan.missing_dependency_reported", tasks = { "SDD-008" }, suites = { "core" }, run = function(t)
    local o = validate(t, (mini:gsub("SDD%-001, SDD%-002%.", "SDD-001, SDD-099.")))
    t:eq(o.code, 1); t:match(o.stdout, "dependency: SDD%-003 requires unknown SDD%-099")
  end },
  { id = "plan.cycle_reported", tasks = { "SDD-008" }, suites = { "core" }, run = function(t)
    local o = validate(t, (mini:gsub("%*%*Requires:%*%* none%.", "**Requires:** SDD-003.")))
    t:eq(o.code, 1); t:match(o.stdout, "cycle: ")
  end },
  { id = "plan.checked_without_evidence_reported", tasks = { "SDD-008" }, suites = { "core" }, run = function(t)
    local o = validate(t, (mini:gsub("#### %[ %] SDD%-001", "#### [x] SDD-001")))
    t:eq(o.code, 1); t:match(o.stdout, "SDD%-001 is checked but has no passing evidence record")
  end },
  { id = "plan.nonexistent_artifact_reported", tasks = { "SDD-008" }, suites = { "core" }, run = function(t)
    local dir = t:tmpdir("ev")
    sb.write(dir .. "/manual/SDD-001.md", "### SDD-001\n\n- Kind: manual\n- Status: passed\n- Commit: abc\n- Environment: x\n- Procedure: y\n- Expected: z\n- Actual: z\n- Artifacts: `artifacts/aiswarm/does-not-exist/evidence.json`\n")
    local o = validate(t, (mini:gsub("#### %[ %] SDD%-001", "#### [x] SDD-001")), dir)
    t:eq(o.code, 1); t:match(o.stdout, "nonexistent artifact")
    local ok = validate(t, (mini:gsub("#### %[ %] SDD%-001", "#### [x] SDD-001")), dir, { "--allow-missing-artifacts" })
    t:eq(ok.code, 0, "allowed when explicitly tolerated: " .. ok.stdout)
  end },
  { id = "plan.completed_task_with_incomplete_dependency", tasks = { "SDD-008" }, suites = { "core" }, run = function(t)
    local dir = t:tmpdir("ev2")
    sb.write(dir .. "/manual/SDD-002.md", "### SDD-002\n\n- Kind: manual\n- Status: passed\n- Commit: abc\n- Environment: x\n- Procedure: y\n- Expected: z\n- Actual: z\n")
    local o = validate(t, (mini:gsub("#### %[ %] SDD%-002", "#### [x] SDD-002")), dir)
    t:eq(o.code, 1); t:match(o.stdout, "ordering: SDD%-002 is complete but depends on incomplete SDD%-001")
  end },
  { id = "plan.generated_artifacts_ignored_by_git", tasks = { "SDD-008" }, suites = { "core" }, run = function(t)
    local inside = sb.run({ "git", "-C", sb.repo, "rev-parse", "--is-inside-work-tree" }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME } })
    if inside.code ~= 0 then t:skip("not a git checkout") end
    local o = sb.run({ "git", "-C", sb.repo, "check-ignore", "-q", "artifacts/aiswarm/x/evidence.json" }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME } })
    t:eq(o.code, 0, "artifacts/ is ignored")
    local st = sb.run({ "git", "-C", sb.repo, "status", "--porcelain", "--", "artifacts" }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME } })
    t:eq(vim.trim(st.stdout), "", "no artifact enters git status")
  end },
}
