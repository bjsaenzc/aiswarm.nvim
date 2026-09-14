-- SDD-006: the frozen contract fixtures round-trip as JSON and carry the documented keys.
local sb = require("helpers.sandbox")
local dir = sb.plugin .. "/tests/fixtures/protocol"
return {
  { id = "protocol.fixtures.valid_round_trip", tasks = { "SDD-006" }, suites = { "core" }, run = function(t)
    for _, f in ipairs(vim.fn.glob(dir .. "/valid/*.json", false, true)) do
      local text = sb.read(f); local obj, err = sb.json(text)
      t:ok(obj, f .. ": " .. tostring(err))
      t:eq(sb.json(vim.json.encode(obj)), obj, "round trip " .. f)
      if obj.schema_version then
        for _, key in ipairs({ "board_id", "event_id", "observed_at", "type", "payload" }) do t:ok(obj[key] ~= nil, f .. " has " .. key) end
      end
    end
  end },
  { id = "protocol.fixtures.frames_are_jsonl", tasks = { "SDD-006" }, suites = { "core" }, run = function(t)
    local kinds = {}
    for line in (sb.read(dir .. "/valid/frames.jsonl") or ""):gmatch("[^\n]+") do
      local fr = sb.json(line); t:ok(fr and fr.frame, "frame decodes"); kinds[#kinds + 1] = fr.frame
      if fr.frame ~= "hello" and fr.frame ~= "error" then t:ok(fr.next_cursor, fr.frame .. " carries next_cursor") end
    end
    t:eq(kinds, { "hello", "snapshot", "event", "gap", "status" })
  end },
  { id = "protocol.fixtures.invalid_declare_expectation", tasks = { "SDD-006" }, suites = { "core" }, run = function(t)
    local files = vim.fn.glob(dir .. "/invalid/*.json", false, true)
    t:ok(#files >= 7, "invalid fixtures present")
    for _, f in ipairs(files) do
      local obj = sb.json(sb.read(f)); t:ok(obj and type(obj.expect) == "string", f .. " declares expect")
      t:ok(obj.record or obj.cursor, f .. " carries a record or cursor")
    end
  end },
}
