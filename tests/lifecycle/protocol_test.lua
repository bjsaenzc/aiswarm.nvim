-- SDD-017: shared versioned validation.
local sb = require("helpers.sandbox")
local v3 = require("helpers.v3")
local fixtures = sb.plugin .. "/tests/fixtures/protocol"
return {
  { id = "protocol.valid_fixtures_accepted", tasks = { "SDD-017" }, suites = { "core" }, run = function(t)
    local P = v3.mods().P
    local ctl = sb.json(sb.read(fixtures .. "/valid/control_task_queued.json"))
    local ok, err = P.validate_control_record(ctl); t:ok(ok, tostring(err))
    for _, f in ipairs({ "telemetry_progress", "telemetry_output", "telemetry_unknown_type_additive" }) do
      local rec = sb.json(sb.read(fixtures .. "/valid/" .. f .. ".json"))
      local tok, terr = P.validate_telemetry_record(rec); t:ok(tok, f .. ": " .. tostring(terr))
    end
    local cur = sb.json(sb.read(fixtures .. "/valid/cursor.json")); t:ok(P.validate_cursor(cur))
  end },
  { id = "protocol.invalid_fixtures_rejected", tasks = { "SDD-017" }, suites = { "core" }, run = function(t)
    local P = v3.mods().P
    for _, f in ipairs(vim.fn.glob(fixtures .. "/invalid/*.json", false, true)) do
      local fx = sb.json(sb.read(f))
      if fx.record then
        local ok, err, kind = false, nil, nil
        if fx.record.control_seq ~= nil then ok, err, kind = P.validate_control_record(fx.record) else ok, err, kind = P.validate_telemetry_record(fx.record) end
        t:ok(not ok, f .. " must be rejected")
        if fx.expect == "incompatible" then t:eq(kind, "incompatible", f) end
        if fx.expect == "reserved_payload_key" then t:match(err, "reserved key") end
        if fx.expect == "invalid_task_id" then t:match(err, "task_id") end
      end
    end
  end },
  { id = "protocol.task_ids_are_path_safe", tasks = { "SDD-017" }, suites = { "core" }, run = function(t)
    local P = v3.mods().P
    for _, bad in ipairs({ "../x", "a/b", ".", "..", "", "-x", "_x", ("x"):rep(65), "a b", "a\n" }) do t:ok(not P.valid_task_id(bad), "rejects " .. vim.inspect(bad)) end
    for _, good in ipairs({ "T-001", "x", "A_b-9", ("x"):rep(64) }) do t:ok(P.valid_task_id(good), "accepts " .. good) end
  end },
  { id = "protocol.numeric_and_type_checks", tasks = { "SDD-017" }, suites = { "core" }, run = function(t)
    local P = v3.mods().P
    local _, e1 = P.check_task_fields({ provider = "mock", priority = -3 }); t:match(e1, "priority")
    local _, e2 = P.check_task_fields({ provider = "mock", timeout = 0 }); t:match(e2, "timeout")
    local _, e3 = P.check_task_fields({ provider = "mock", timeout = "12x" }); t:match(e3, "timeout")
    local _, e4 = P.check_task_fields({ provider = "nope" }, { providers = { mock = true } }); t:match(e4, "unknown provider")
    local _, e5 = P.check_task_fields({ provider = "mock", isolation = "maybe" }); t:match(e5, "isolation")
    local _, e6 = P.check_task_fields({ provider = "mock", title = ("x"):rep(201) }); t:match(e6, "title")
    local _, e7 = P.check_task_fields({ id = "T-1", provider = "mock", depends_on = "T-1" }); t:match(e7, "itself")
    local ok = P.check_task_fields({ provider = "mock", priority = "7", timeout = "30", depends_on = "T-2, T-3 T-2" })
    t:eq(ok.priority, 7); t:eq(ok.timeout, 30); t:eq(ok.depends_on, { "T-2", "T-3" })
  end },
  { id = "protocol.unknown_types_inspectable_no_state_change", tasks = { "SDD-017", "SDD-021" }, suites = { "core" }, run = function(t)
    local m = v3.mods()
    local rec = sb.json(sb.read(fixtures .. "/valid/control_task_queued.json"))
    rec.type = "task.something_new"; rec.payload = { note = "additive" }
    t:ok(m.P.validate_control_record(rec), "unknown control type accepted for inspection")
    local state = { tasks = {}, attempts = {}, scheduler = {} }
    t:eq(m.R.apply(state, rec), {}); t:eq(state.tasks, {})
  end },
  { id = "protocol.mutation_arguments_reject_reserved_overrides", tasks = { "SDD-017" }, suites = { "core" }, run = function(t)
    local P = v3.mods().P
    local ok, err = P.validate_inbox({ board_id = "57fc3ea0-6b8f-45c2-8e8f-3a5f98cc4ed3", task_id = "T-1", attempt_id = "6520181b-1cb0-4563-985b-3b60d78775db",
      type = "agent.progress", message_id = "m1", payload = { attempt_seq = 99 } })
    t:ok(not ok); t:match(err, "reserved")
  end },
}
