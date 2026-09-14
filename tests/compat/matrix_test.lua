-- SDD-043: compatibility and migration matrix (evidence collection; each cell is an assertion).
local sb = require("helpers.sandbox")
local v3 = require("helpers.v3")
local pl = require("helpers.plugin")
return {
  { id = "matrix.both_names_v2_and_v3_boards", tasks = { "SDD-043" }, suites = { "compatibility" }, run = function(t)
    local v2root = sb.legacy_board(t, "v2"); sb.legacy_add(t, v2root, { "--id", "T-001" }, "x\n")
    local v3root = v3.board(t, "v3"); v3.cli_json(t, v3root, { "add", "--id", "T-001" }, { stdin = "x\n" })
    for _, bin in ipairs({ "hive", "aiswarm" }) do
      for _, root in ipairs({ v2root, v3root }) do
        local o = sb.run({ sb.bin(bin), "json" }, { env = sb.env(root), cwd = vim.fs.dirname(root) })
        t:eq(o.code, 0, bin .. " json on " .. root .. ": " .. o.stderr)
        local snap = sb.json(o.stdout); t:eq(snap.api_version, 2, bin .. " serves the v2 read shape on both boards"); t:eq(snap.tasks[1].id, "T-001")
        local ev = sb.run({ sb.bin(bin), "events", "--since", "0" }, { env = sb.env(root), cwd = vim.fs.dirname(root) }); t:eq(ev.code, 0)
      end
    end
    -- both Lua names against both boards through one runtime
    for _, root in ipairs({ v2root, v3root }) do
      local A = pl.setup(t, root); local snap = pl.refresh(t, A)
      t:ok(snap and vim.tbl_count(A.state().tasks) == 1, "editor reads " .. root)
      t:eq(require("hive").root(), root)
    end
  end },
  { id = "matrix.unsupported_combinations_fail_explicitly", tasks = { "SDD-043" }, suites = { "compatibility" }, run = function(t)
    local v3root = v3.board(t, "v3b")
    -- v3-only commands on a v2 board fail clearly, not silently
    local v2root = sb.legacy_board(t, "v2b")
    local c = v3.cli(v2root, { "cancel", "T-001" }); t:eq(c.code, 4); t:match(c.stderr, "legacy %(v2%) board")
    local s = v3.cli(v2root, { "stream" }); t:ok(s.code ~= 0)
    -- v2-only tooling on a v3 board: `hive exec` is not a v3 command
    local e = sb.run({ sb.bin("hive"), "exec", "T-001" }, { env = sb.env(v3root), cwd = vim.fs.dirname(v3root) }); t:ok(e.code ~= 0)
    -- conflicting roots
    vim.fn.mkdir(vim.fs.dirname(v2root) .. "/.aiswarm", "p")
    local conflict = sb.run({ sb.bin("aiswarm"), "json" }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME, TMUX_TMPDIR = vim.env.TMUX_TMPDIR or vim.env.TMPDIR }, cwd = vim.fs.dirname(v2root) })
    t:eq(conflict.code, 4); t:match(conflict.stderr, "both")
  end },
  { id = "matrix.no_unintended_data_move", tasks = { "SDD-043" }, suites = { "compatibility" }, run = function(t)
    local root = sb.legacy_board(t, "keep"); sb.legacy_add(t, root, { "--id", "T-001" }, "x\n")
    local r = v3.cli(root, { "migrate" }, { env = { AISWARM_INVOKED_AS = "" } }); t:eq(r.code, 0, r.stderr)
    t:ok(sb.exists(root .. "/board.json") and vim.fs.basename(root) == ".hive", "board stays at .hive after upgrade")
    t:ok(not sb.exists(vim.fs.dirname(root) .. "/.aiswarm"), "no directory move")
    t:ok(sb.exists(root .. "/tasks/ready/T-001.json") and sb.exists(root .. "/tasks/prompts/T-001.md"), "v2 files untouched")
  end },
}
