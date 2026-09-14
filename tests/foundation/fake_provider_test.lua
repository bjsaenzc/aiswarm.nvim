-- SDD-003: deterministic worker scenarios.
local sb = require("helpers.sandbox")
local exe = sb.fake_provider("fake-provider")
local manifest = sb.json(sb.read(sb.plugin .. "/tests/fixtures/providers/scenarios.json"))

local function run(t, scenario, extra_env, opts)
  opts = opts or {}
  local dir = t:tmpdir(scenario)
  local env = { PATH = vim.env.PATH, AISWARM_FAKE_SCENARIO = scenario, AISWARM_FAKE_TICK_MS = "5",
    AISWARM_FAKE_REPORT = dir .. "/report.md", AISWARM_FAKE_BARRIER = dir .. "/barrier" }
  for k, v in pairs(extra_env or {}) do env[k] = v end
  local started = vim.uv.hrtime()
  local job = vim.system({ exe }, { text = false, env = env, timeout = opts.timeout or 5000 })
  if opts.release_after_ms then
    vim.wait(opts.release_after_ms, function() return false end, 5)
    sb.write(dir .. "/barrier", "go")
  end
  local o = job:wait()
  return o, dir, (vim.uv.hrtime() - started) / 1e6
end

local cases = {
  { id = "fake.manifest_lists_every_scenario", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    t:ok(exe, "fake-provider executable present")
    local src = sb.read(exe)
    for name in pairs(manifest) do t:ok(src:find("\n  " .. name .. ")", 1, true), "scenario implemented: " .. name) end
  end },
  { id = "fake.never_resolves_real_provider", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local src = sb.read(exe)
    for _, real in ipairs({ "claude", "codex", "gemini", "aider", "cursor%-agent", "curl", "wget", "nc " }) do
      t:ok(not src:match("\n[^#]*" .. real), "fake provider does not invoke " .. real)
    end
  end },
  { id = "fake.success_writes_report", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o, dir = run(t, "success")
    t:eq(o.code, 0); t:ok(sb.exists(dir .. "/report.md")); t:match(o.stdout, "fake: done")
  end },
  { id = "fake.failure_has_no_report", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o, dir = run(t, "failure")
    t:eq(o.code, 1); t:ok(not sb.exists(dir .. "/report.md")); t:match(o.stderr, "boom")
  end },
  { id = "fake.missing_report_exits_zero", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o, dir = run(t, "missing-report")
    t:eq(o.code, 0); t:ok(not sb.exists(dir .. "/report.md"))
  end },
  { id = "fake.partial_utf8_bytes", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o = run(t, "partial-utf8")
    for _, s in ipairs(manifest["partial-utf8"].stdout_bytes_contain) do t:ok(o.stdout:find(s, 1, true), "contains " .. s) end
  end },
  { id = "fake.interleaved_streams_ordered", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o = run(t, "interleaved")
    t:eq(vim.split(vim.trim(o.stdout), "\n"), manifest.interleaved.stdout_lines)
    t:eq(vim.split(vim.trim(o.stderr), "\n"), manifest.interleaved.stderr_lines)
  end },
  { id = "fake.timeout_runs_until_killed", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o, _, ms = run(t, "timeout", nil, { timeout = 200 })
    t:ok(o.code ~= 0, "killed run is nonzero"); t:ok(ms >= 150, "ran until the harness timeout")
  end },
  { id = "fake.quiet_waits_for_barrier", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o, _, ms = run(t, "quiet", { AISWARM_FAKE_TICK_MS = "1" }, { release_after_ms = 120 })
    t:eq(o.code, 0); t:ok(ms >= 100, "blocked on the barrier before finishing")
  end },
  { id = "fake.input_request_then_barrier", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o = run(t, "input-request", nil, { release_after_ms = 50 })
    t:eq(o.code, 0); t:match(o.stdout, "input_required id=req%-1")
  end },
  { id = "fake.flood_line_count", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o = run(t, "flood", { AISWARM_FAKE_LINES = "5000" })
    local n = select(2, o.stdout:gsub("\n", "")); t:eq(n, 5000); t:eq(o.code, 0)
  end },
  { id = "fake.late_finish_leaves_grandchild", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o = run(t, "late-finish")
    t:eq(o.code, 0)
    local pid = tonumber(o.stdout:match("grandchild=(%d+)"))
    t:ok(pid, "grandchild pid reported")
    t:ok(vim.uv.kill(pid, 0) == 0, "grandchild still alive after provider exit")
    vim.uv.kill(pid, 9)
  end },
  { id = "fake.progress_helper_invoked", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local dir = t:tmpdir("helper")
    local helper = dir .. "/progress.sh"
    sb.write(helper, "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> '" .. dir .. "/calls'\n")
    vim.uv.fs_chmod(helper, 493)
    local o = run(t, "progress", { AISWARM_FAKE_PROGRESS = helper })
    t:eq(o.code, 0)
    local calls = vim.split(vim.trim(sb.read(dir .. "/calls") or ""), "\n")
    t:eq(#calls, 3); t:match(calls[3], "testing")
  end },
  { id = "fake.control_sequences_present_raw", tasks = { "SDD-003" }, suites = { "core" }, run = function(t)
    local o = run(t, "control-sequences")
    t:ok(o.stdout:find("\27]0;evil title\7", 1, true), "OSC title sequence delivered raw for sanitizer tests")
  end },
}
return cases
