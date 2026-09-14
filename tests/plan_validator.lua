-- SDD-008: validate the SDD plan and its evidence.
--   nvim --clean --headless -l plan_validator.lua <plan.md> <evidence-dir> [--allow-missing-artifacts]
-- Reports: duplicate task IDs, unknown dependencies, dependency cycles, tasks
-- without a requirement label, requirement rows naming unknown tasks, checked
-- tasks without a passing evidence record, malformed records, and evidence
-- pointing at nonexistent artifacts. Exit 0 when valid, 1 otherwise, 2 on usage.
local plan_path, evidence_dir = arg[1], arg[2]
local allow_missing = false
for i = 3, #arg do if arg[i] == "--allow-missing-artifacts" then allow_missing = true end end
if not plan_path or not evidence_dir then io.stderr:write("usage: plan_validator.lua <plan.md> <evidence-dir>\n"); os.exit(2) end
local function read(p) local f = io.open(p, "r"); if not f then return nil end local s = f:read("*a"); f:close(); return s end
local plan = read(plan_path); if not plan then io.stderr:write("cannot read " .. plan_path .. "\n"); os.exit(2) end
plan = plan:gsub("–", "-") -- en dash ranges become ASCII so byte-oriented patterns match
local repo = vim.fs.dirname(vim.fs.dirname(plan_path))
local problems = {}
local function report(kind, msg) problems[#problems + 1] = kind .. ": " .. msg end

-- ---------------------------------------------------------------- tasks
local tasks, order = {}, {}
local current
for line in plan:gmatch("[^\n]*\n?") do
  local box, id, title = line:match("^#### %[([ xX])%] (SDD%-%d%d%d[a-z]?) — (.-)%s*$")
  if id then
    if tasks[id] then report("duplicate", id) end
    current = { id = id, title = title, done = box ~= " ", requires = {}, requirements = {}, line = line }
    tasks[id], order[#order + 1] = current, id
  elseif current and line:match("^%- %*%*Requires:%*%*") then
    local req = line:match("%*%*Requires:%*%*%s*(.-)%.%s*%*%*Requirement:%*%*") or line:match("%*%*Requires:%*%*%s*(.-)%.")
    local reqs = line:match("%*%*Requirement:%*%*%s*(.-)%.")
    if req and req ~= "none" then
      -- ranges: "SDD-001–099" / "SDD-101–105"; singles: "SDD-016"
      for a, b in req:gmatch("SDD%-(%d%d%d)%-(%d%d%d)") do
        for n = tonumber(a), tonumber(b) do current.requires[#current.requires + 1] = ("SDD-%03d"):format(n) end
      end
      local stripped = req:gsub("SDD%-%d%d%d%-%d%d%d", "")
      for dep in stripped:gmatch("SDD%-%d%d%d[a-z]?") do current.requires[#current.requires + 1] = dep end
    end
    for r in (reqs or ""):gmatch("R%d%d") do current.requirements[#current.requirements + 1] = r end
    if #current.requirements == 0 then report("requirement", current.id .. " names no requirement label") end
  end
end
if #order == 0 then report("plan", "no task cards found") end

for _, id in ipairs(order) do
  local t = tasks[id]
  for _, dep in ipairs(t.requires) do
    if not tasks[dep] then report("dependency", id .. " requires unknown " .. dep) end
    if dep == id then report("dependency", id .. " requires itself") end
  end
end
-- cycles
local state = {}
local function visit(id, stack)
  if state[id] == "done" then return end
  if state[id] == "active" then report("cycle", table.concat(stack, " -> ") .. " -> " .. id); return end
  state[id] = "active"; stack[#stack + 1] = id
  for _, dep in ipairs((tasks[id] or {}).requires) do if tasks[dep] then visit(dep, stack) end end
  stack[#stack] = nil; state[id] = "done"
end
for _, id in ipairs(order) do visit(id, {}) end
-- dependencies of a completed task must be completed
for _, id in ipairs(order) do
  local t = tasks[id]
  if t.done then for _, dep in ipairs(t.requires) do if tasks[dep] and not tasks[dep].done then report("ordering", id .. " is complete but depends on incomplete " .. dep) end end end
end

-- ---------------------------------------------------------------- requirement ownership
local owned = {}
for row in plan:gmatch("\n| R%d%d [^\n]*") do
  local label = row:match("| (R%d%d) ")
  local cells = {}
  for cell in row:gmatch("|([^|]*)") do cells[#cells + 1] = cell end
  local owners = cells[#cells - 0] or ""
  -- last non-empty cell is the owning tasks list
  for i = #cells, 1, -1 do if vim.trim(cells[i]) ~= "" then owners = cells[i]; break end end
  for a, b in owners:gmatch("SDD%-(%d%d%d)%-(%d%d%d)") do for n = tonumber(a), tonumber(b) do owned[("SDD-%03d"):format(n)] = true end end
  for id in owners:gsub("SDD%-%d%d%d%-%d%d%d", ""):gmatch("SDD%-%d%d%d") do
    owned[id] = true
    if not tasks[id] then report("traceability", label .. " names unknown task " .. id) end
  end
end
for _, id in ipairs(order) do if not owned[id] and not id:match("[a-z]$") then report("traceability", id .. " is not owned by any requirement row") end end

-- ---------------------------------------------------------------- evidence
local function parse_record(text, path)
  local rec = { path = path, fields = {} }
  rec.id = text:match("^#+%s*(SDD%-%d%d%d[a-z]?)") or text:match("\n#+%s*(SDD%-%d%d%d[a-z]?)")
  for k, v in text:gmatch("\n%- ([%w/ ]+):%s*([^\n]*)") do rec.fields[k] = vim.trim(v) end
  return rec
end
local records = {}
local ledger = read(evidence_dir .. "/ledger.md") or ""
local starts = {}
for pos in ledger:gmatch("()\n### SDD%-") do starts[#starts + 1] = pos + 1 end
for i, s in ipairs(starts) do
  local section = ledger:sub(s, (starts[i + 1] or (#ledger + 1)) - 1)
  local rec = parse_record(section, evidence_dir .. "/ledger.md")
  if rec.id then records[rec.id] = records[rec.id] or {}; table.insert(records[rec.id], rec) end
end
for _, f in ipairs(vim.fn.glob(evidence_dir .. "/manual/*.md", false, true)) do
  local rec = parse_record(read(f) or "", f)
  rec.manual = true
  local id = rec.id or vim.fn.fnamemodify(f, ":t:r")
  records[id] = records[id] or {}; table.insert(records[id], rec)
end
local required = { "Status", "Commit", "Environment", "Expected", "Actual" }
for id, list in pairs(records) do
  for _, rec in ipairs(list) do
    if not tasks[id] then report("evidence", rec.path .. " records unknown task " .. id) end
    for _, k in ipairs(required) do if not rec.fields[k] or rec.fields[k] == "" then report("evidence", id .. " record in " .. rec.path .. " lacks " .. k) end end
    if rec.manual then
      if rec.fields.Kind ~= "manual" then report("evidence", id .. " manual record must declare Kind: manual") end
      if not rec.fields.Procedure then report("evidence", id .. " manual record lacks Procedure") end
    else
      if not rec.fields.Command then report("evidence", id .. " automated record lacks Command") end
    end
    for art in (rec.fields.Artifacts or ""):gmatch("`([^`]+)`") do
      local p = art:match("^/") and art or (repo .. "/" .. art)
      if not vim.uv.fs_stat(p) then report(allow_missing and "artifact-missing(allowed)" or "artifact", id .. " points at nonexistent artifact " .. art) end
    end
  end
end
for _, id in ipairs(order) do
  local t = tasks[id]
  if t.done then
    local ok = false
    for _, rec in ipairs(records[id] or {}) do if rec.fields.Status == "passed" then ok = true end end
    if not ok then report("evidence", id .. " is checked but has no passing evidence record") end
  end
end

-- ---------------------------------------------------------------- report
local counts = { total = #order, done = 0 }
for _, id in ipairs(order) do if tasks[id].done then counts.done = counts.done + 1 end end
local hard = 0
for _, p in ipairs(problems) do if not p:match("^artifact%-missing%(allowed%)") then hard = hard + 1 end end
io.stdout:write(("plan: %d tasks, %d complete, %d evidence ids, %d problems\n"):format(counts.total, counts.done, vim.tbl_count(records), hard))
table.sort(problems)
for _, p in ipairs(problems) do io.stdout:write("  " .. p .. "\n") end
io.stdout:flush()
os.exit(hard > 0 and 1 or 0)
