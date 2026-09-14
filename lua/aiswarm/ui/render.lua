-- Render scheduler (SDD-048): dirty regions, coalescing, bounded batches; hidden views never render.
local uv = vim.uv
local R = {}
R.views = {}
R.stats = { marks = 0, batches = 0, renders = 0, skipped_hidden = 0, view_ms = {} }
R.MIN_INTERVAL_MS = 16
R._dirty, R._scheduled, R._last = {}, false, 0

---@param name string
---@param view { render: fun(), visible: fun(): boolean }
function R.register(name, view) R.views[name] = view end
function R.unregister(name) R.views[name] = nil; R._dirty[name] = nil end

function R.mark(name)
  R.stats.marks = R.stats.marks + 1
  if name then R._dirty[name] = true else for n in pairs(R.views) do R._dirty[n] = true end end
  R.schedule()
end

function R.schedule()
  if R._scheduled then return end
  R._scheduled = true
  local elapsed = uv.now() - R._last
  local delay = math.max(0, R.MIN_INTERVAL_MS - elapsed)
  vim.defer_fn(function() R._scheduled = false; R.flush() end, delay)
end

--- Render all dirty visible views in one batch.
function R.flush()
  local dirty = R._dirty
  R._dirty = {}
  local rendered = 0
  for name in pairs(dirty) do
    local view = R.views[name]
    if view then
      if view.visible() then
        local s = uv.hrtime()
        local ok, err = pcall(view.render)
        local ms = (uv.hrtime() - s) / 1e6
        local v = R.stats.view_ms[name] or { n = 0, total = 0, max = 0 }
        v.n, v.total, v.max = v.n + 1, v.total + ms, math.max(v.max, ms); R.stats.view_ms[name] = v
        rendered = rendered + 1
        R.stats.renders = R.stats.renders + 1
        if not ok then R.last_error = tostring(err) end
      else
        R.stats.skipped_hidden = R.stats.skipped_hidden + 1
      end
    end
  end
  if rendered > 0 or next(dirty) then R.stats.batches = R.stats.batches + 1 end
  R._last = uv.now()
end

function R.reset() R.views, R._dirty, R._scheduled = {}, {}, false; R.stats = { marks = 0, batches = 0, renders = 0, skipped_hidden = 0, view_ms = {} } end

return R
