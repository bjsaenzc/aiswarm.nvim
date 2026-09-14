-- SDD-002: characterization of the legacy Neovim client (require("aiswarm")).
local sb = require("helpers.sandbox")

local function force_done(root, id)
  local src, dst = root .. "/tasks/ready/" .. id .. ".json", root .. "/tasks/done/" .. id .. ".json"
  local task = sb.json(sb.read(src)); task.state = "done"; task.rc = 0
  sb.write(dst, vim.json.encode(task)); os.remove(src)
end

local function fresh_aiswarm(t, root)
  for name in pairs(package.loaded) do if name == "aiswarm" or name:match("^aiswarm%.") then package.loaded[name] = nil end end
  vim.g.loaded_aiswarm = nil
  local H = require("aiswarm")
  H.setup({ bin = sb.bin("aiswarm"), root = root, follow = false, register_server = false, dashboard = { refresh_ms = 60000 } })
  t:defer(function() require("aiswarm.legacy.state").stop() end)
  return H, require("aiswarm.legacy.state")
end

return {
  { id = "legacy.lua.commands_and_api_forwards", tasks = { "SDD-002" }, suites = { "core", "legacy", "compatibility" }, run = function(t)
    vim.g.loaded_aiswarm = nil
    vim.cmd.source(sb.plugin .. "/plugin/aiswarm.lua")
    local cmds = vim.api.nvim_get_commands({})
    t:ok(cmds.AISwarm, "canonical command registered")
    t:eq(cmds.AISwarm.range, ".", "AISwarm accepts a range")
    local H = require("aiswarm")
    for _, fn in ipairs({ "open", "pick", "results", "add", "tail", "peek", "go", "kill", "toggle_pause", "statusline", "on_event", "on_event_json", "refresh", "setup", "root", "run", "run_sync" }) do
      t:eq(type(H[fn]), "function", "api: " .. fn)
    end
  end },
  { id = "legacy.lua.root_resolution_is_frozen", tasks = { "SDD-002" }, suites = { "core", "legacy", "compatibility" }, run = function(t)
    local dir = t:tmpdir("root")
    local H = fresh_aiswarm(t, dir .. "/.aiswarm")
    t:eq(H.root(), dir .. "/.aiswarm")
    vim.env.AISWARM_ROOT = dir .. "/other"
    t:eq(H.root(), dir .. "/.aiswarm", "root is session-owned; env/cwd changes do not retarget (A14 fixed by explicit sessions)")
    vim.env.AISWARM_ROOT = nil
    t:errors(function() H.setup({ bin = sb.bin("aiswarm"), root = dir .. "/.aiswarm", command_timeout_ms = -1 }) end, "positive integer")
  end },
  { id = "legacy.lua.id_completion_prefix", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001" }, "a\n"); sb.legacy_add(t, root, { "--id", "X-9" }, "b\n")
    local H, S = fresh_aiswarm(t, root)
    local snap
    H.refresh(function(s) snap = s end)
    t:wait(5000, function() return snap ~= nil end)
    t:eq(S.ids(), { "T-001", "X-9" })
    vim.g.loaded_aiswarm = nil; vim.cmd.source(sb.plugin .. "/plugin/aiswarm.lua")
    t:eq(vim.fn.getcompletion("AISwarm tail T", "cmdline"), { "T-001" })
  end },
  { id = "legacy.lua.event_order_dedup", tasks = { "SDD-002" }, suites = { "core", "legacy", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    local H, S = fresh_aiswarm(t, root)
    local snap; H.refresh(function(s) snap = s end); t:wait(5000, function() return snap ~= nil end)
    local got = {}
    t:defer(S.subscribe(function(kind, e) if kind == "event" then got[#got + 1] = e.seq end end))
    t:eq(H.on_event({ seq = 2, type = "message" }), true)
    t:eq(got, {}, "future event buffers")
    t:eq(H.on_event({ seq = 1, type = "message" }), true)
    t:eq(got, { 1, 2 })
    t:eq(H.on_event({ seq = 2, type = "message" }), true)
    t:eq(got, { 1, 2 }, "duplicate is ignored")
    t:eq(H.on_event({ seq = 0, type = "message" }), false); t:eq(H.on_event("junk"), false)
    t:eq(S.seq, 2)
  end },
  { id = "legacy.lua.on_event_json_root_check", tasks = { "SDD-002" }, suites = { "core", "legacy", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    local H = fresh_aiswarm(t, root)
    t:eq(H.on_event_json('{"seq":1,"type":"message"}', "/elsewhere/.aiswarm"), false, "foreign root rejected")
    t:eq(H.on_event_json('{"seq":1,"type":"message"}', root .. "/"), true, "trailing slash normalized")
    t:eq(H.on_event_json("not json"), false)
  end },
  { id = "legacy.lua.form_preserves_prompt", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local U = require("aiswarm.legacy.ui")
    local lines = U.form_template({ "first", "", "#: literal prompt line", "# not a header", "last" })
    local args, prompt, err = U.parse_form(lines)
    t:eq(err, nil)
    t:eq(prompt, { "first", "", "#: literal prompt line", "# not a header", "last" })
    t:eq(args[1], "add"); t:eq(args[2], "--id")
    local _, _, e2 = U.parse_form({ "#: id = T-1", "---", "   " }); t:eq(e2, "prompt is empty")
    local _, _, e3 = U.parse_form({ "#: id = T-1", "#: bogus = 1", "---", "x" }); t:eq(e3, "unknown field: bogus")
    local _, _, e4 = U.parse_form({ "#: id = T-1", "#: deps = T-1", "---", "x" }); t:match(e4, "invalid dependency")
  end },
  { id = "legacy.lua.snapshot_validation", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001" }, "a\n")
    local H, S = fresh_aiswarm(t, root)
    local snap, err; H.refresh(function(s, e) snap, err = s, e end); t:wait(5000, function() return snap ~= nil or err ~= nil end)
    t:eq(err, nil); t:eq(snap.counts, { ready = 1, active = 0, done = 0, failed = 0 }, "counts recomputed client-side")
    t:eq(H.statusline(), "R:1 A:0 ✓0 ✗0")
  end },
  { id = "legacy.quirk.dashboard_selection_drift", tasks = { "SDD-002" }, suites = { "core", "legacy" }, run = function(t)
    if not pcall(require, "snacks") then t:skip("snacks.nvim not available in the sandbox") end
    local root = sb.legacy_board(t)
    sb.legacy_add(t, root, { "--id", "T-001" }, "a\n"); sb.legacy_add(t, root, { "--id", "T-002" }, "b\n")
    local H, S = fresh_aiswarm(t, root)
    local snap; H.refresh(function(s) snap = s end); t:wait(5000, function() return snap ~= nil end)
    local U = require("aiswarm.legacy.ui")
    U.dashboard()
    t:defer(function() if U._dash and U._dash.win:valid() then U._dash.win:close() end end)
    t:wait(2000, function() return U._dash and U._dash.map[3] ~= nil end)
    t:eq(U._dash.map[3], "T-001"); t:eq(U._dash.map[4], "T-002")
    vim.api.nvim_win_set_cursor(U._dash.win.win, { 3, 0 })
    -- T-001 finishes: done sorts after ready, so the row under the cursor becomes T-002.
    force_done(root, "T-001")
    snap = nil; H.refresh(function(s) snap = s end); t:wait(5000, function() return snap ~= nil end)
    U.render()
    t:eq(vim.api.nvim_win_get_cursor(U._dash.win.win)[1], 3, "cursor row unchanged")
    t:eq(U._dash.map[3], "T-002", "LEGACY QUIRK A04: selection drifted from T-001 to T-002")
  end },
}
