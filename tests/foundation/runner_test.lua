-- SDD-001: the runner itself. These cases prove the isolation guarantees.
local sb = require("helpers.sandbox")
return {
  { id = "runner.passes", tasks = { "SDD-001" }, suites = { "core" }, run = function(t)
    t:eq(1 + 1, 2)
    t:ok(vim.uv.fs_stat(t.run_dir), "run dir exists")
  end },
  { id = "runner.self_fail", tasks = { "SELF-FAIL" }, suites = {}, run = function(t)
    t:fail("intentional failure used to verify the nonzero exit path")
  end },
  { id = "runner.self_skip", tasks = { "SELF-SKIP" }, suites = {}, run = function(t)
    t:skip("intentional skip used to verify the unverified status")
  end },
  { id = "runner.isolated_environment", tasks = { "SDD-001" }, suites = { "core" }, run = function(t)
    local e = vim.env
    t:ok(e.HOME:find(t.run_dir, 1, true) == 1, "HOME lives in the run dir: " .. e.HOME)
    t:ok(e.XDG_CONFIG_HOME:find(t.run_dir, 1, true) == 1, "XDG_CONFIG_HOME isolated")
    t:ok(e.NVIM_LOG_FILE:find(t.run_dir, 1, true) == 1, "Neovim log inside the sandbox")
    t:eq(e.TMUX, nil, "not attached to the caller's tmux")
    t:eq(e.HIVE_ROOT, nil); t:eq(e.AISWARM_ROOT, nil)
    t:eq(vim.o.shada, "", "shada disabled")
    -- in a standalone checkout the repository root is the plugin itself and belongs on the runtimepath
    if t.repo ~= vim.env.AISWARM_TEST_PLUGIN then
      for _, entry in ipairs(vim.opt.runtimepath:get()) do
        t:ok(entry ~= t.repo and entry ~= t.repo .. "/after", "user config root is not on runtimepath: " .. entry)
      end
    end
    -- the harness keeps sockets on a short private path (sun_path limit), never the caller's default socket dir
    local sock = vim.env.TMUX_TMPDIR or ""
    t:ok(sock:find(t.run_dir, 1, true) == 1 or sock:match("^/tmp/aisw%-t%.%w+$"), "default tmux socket dir isolated: " .. sock)
    t:eq(package.loaded["lazy"], nil, "lazy.nvim is not loaded")
    t:ok(vim.fn.stdpath("config"):find(t.run_dir, 1, true) == 1, "stdpath(config) isolated")
    for _, prov in ipairs({ "claude", "codex", "gemini", "aider", "cursor-agent" }) do
      t:eq(vim.fn.executable(prov), 0, prov .. " must not be reachable on the sandbox PATH")
    end
    for _, tool in ipairs({ "tmux", "jq", "bash" }) do t:eq(vim.fn.executable(tool), 1, tool .. " available") end
  end },
  { id = "runner.tmux_socket_isolated", tasks = { "SDD-001" }, suites = { "core" }, run = function(t)
    t:ok(sb.socket and sb.socket:match("^aiswarm%-test%-%d+$"), "dedicated tmux socket name")
    local r = sb.tmux({ "new-session", "-d", "-s", "probe", "sleep 30" })
    t:eq(r.code, 0, "tmux server starts on the test socket: " .. r.stderr)
    t:defer(function() sb.tmux({ "kill-session", "-t", "probe" }) end)
    local ls = sb.tmux({ "list-sessions", "-F", "#{session_name}" })
    t:match(ls.stdout, "probe")
    -- The sandbox default server (private TMUX_TMPDIR) must not see it either.
    local default = sb.run({ "tmux", "list-sessions", "-F", "#{session_name}" })
    t:ok(not default.stdout:match("^probe\n") and not default.stdout:match("\nprobe\n"), "probe session invisible on the default server")
  end },
  { id = "runner.evidence_written", tasks = { "SDD-001", "SDD-008" }, suites = { "core" }, run = function(t)
    -- Evidence for this very run is written after the run; check the previous runs' shape instead.
    local dirs = vim.fn.glob(t.repo .. "/artifacts/aiswarm/*/evidence.json", false, true)
    for _, f in ipairs(dirs) do
      local data = sb.json(sb.read(f))
      t:ok(data and data.run_id and data.counts and data.results, "evidence has run_id/counts/results: " .. f)
    end
    t:log("previous evidence files", #dirs)
  end },
}
