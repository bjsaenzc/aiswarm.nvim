-- SDD-014: legacy and canonical push both reach the one session; registration is owner-checked.
local sb = require("helpers.sandbox")
local pl = require("helpers.plugin")
return {
  { id = "compat.push.duplicate_delivery_one_event", tasks = { "SDD-014" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    local A = pl.setup(t, root); pl.refresh(t, A)
    local got = {}
    t:defer(A.subscribe(function(kind, e) if kind == "event" then got[#got + 1] = e.seq end end))
    local payload = '{"seq":1,"type":"message","task":"T-0"}'
    t:eq(require("hive").on_event_json(payload, root), true)
    t:eq(require("aiswarm").on_event_json(payload, root), true)
    t:eq(got, { 1 }, "delivered once through both names")
    t:eq(A.on_event_json(payload, "/some/other/.hive"), false, "mismatched root rejected")
  end },
  { id = "compat.push.script_round_trip", tasks = { "SDD-014" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    local A = pl.setup(t, root, { register_server = true }); pl.refresh(t, A)
    t:wait(2000, function() return sb.exists(root .. "/nvim.server") end, "registration written")
    local got = {}
    t:defer(A.subscribe(function(kind, e) if kind == "event" then got[#got + 1] = e end end))
    local env = { PATH = vim.env.PATH, HOME = vim.env.HOME, AISWARM_ROOT = root }
    for _, script in ipairs({ "aiswarm-push", "hive-push" }) do
      local finished = false
      vim.system({ sb.bin(script), '{"seq":1,"type":"message","task":"T-0","text":"it\'s quoted"}' }, { env = env }, function() finished = true end)
      -- nvim --remote-expr needs this editor's loop to answer; pump until the push exits
      t:wait(5000, function() return finished end, script .. " finished")
    end
    t:wait(5000, function() return #got >= 1 end, "push arrived through RPC")
    t:eq(#got, 1, "duplicate push delivered once"); t:eq(got[1].text, "it's quoted")
  end },
  { id = "compat.push.teardown_is_owner_checked", tasks = { "SDD-014" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    local A, S = pl.setup(t, root, { register_server = true }); pl.refresh(t, A)
    t:wait(2000, function() return S._registration and S._registration.server end)
    sb.write(root .. "/nvim.server", "/tmp/another-editor.sock\n") -- another editor took over
    S.unregister_server()
    t:eq(vim.trim(sb.read(root .. "/nvim.server")), "/tmp/another-editor.sock", "another editor's registration survives our teardown")
  end },
  { id = "compat.push.failed_registration_keeps_follower", tasks = { "SDD-014" }, suites = { "core", "compatibility" }, run = function(t)
    local root = sb.legacy_board(t)
    vim.uv.fs_chmod(root, 365) -- r-xr-xr-x: registration file cannot be written
    t:defer(function() vim.uv.fs_chmod(root, 493) end)
    local A, S
    local seen = pl.capture_notify(function()
      A, S = pl.setup(t, root, { register_server = true, follow = true }); pl.refresh(t, A)
      vim.wait(200)
    end)
    local warned = false
    for _, n in ipairs(seen) do if n.msg:match("push registration failed") then warned = true end end
    t:ok(warned, "useful diagnostic: " .. vim.inspect(seen))
    t:ok(S._follow, "follower still running")
  end },
}
