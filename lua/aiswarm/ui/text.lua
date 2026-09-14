-- Display-cell-safe text primitives and sanitization (SDD-050).
local T = {}

T.ICONS = {
  unicode = { running = "●", queued = "○", blocked = "◌", succeeded = "✓", failed = "✗", cancelled = "⊘", attention = "!", starting = "◔", stale = "?", pin = "📌", collapsed = "▸", expanded = "▾", spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }, sep = "│" },
  ascii   = { running = "*", queued = "o", blocked = ".", succeeded = "+", failed = "x", cancelled = "-", attention = "!", starting = "~", stale = "?", pin = "P", collapsed = ">", expanded = "v", spinner = { "|", "/", "-", "\\" }, sep = "|" },
}
function T.icons()
  local cfg = require("aiswarm").config.ui.icons
  if type(cfg) == "table" then return vim.tbl_extend("force", T.ICONS.unicode, cfg) end
  return T.ICONS[cfg] or T.ICONS.unicode
end

function T.width(s)
  s = s or ""
  if s:find("\t", 1, true) then return vim.fn.strdisplaywidth(s) end
  return vim.api.nvim_strwidth(s)   -- C API: same double-width/combining handling, much cheaper per call
end

--- Truncate to `width` display cells with an ellipsis, never splitting a character.
function T.truncate(s, width, ellipsis)
  s = s or ""
  ellipsis = ellipsis or "…"
  if width <= 0 then return "" end
  if T.width(s) <= width then return s end
  local ew = T.width(ellipsis)
  if width <= ew then return vim.fn.strcharpart(ellipsis, 0, width) end
  local out, w = {}, 0
  for _, ch in ipairs(vim.fn.split(s, "\\zs")) do
    local cw = T.width(ch)
    if w + cw > width - ew then break end
    out[#out + 1] = ch; w = w + cw
  end
  return table.concat(out) .. ellipsis
end

--- Pad or truncate to exactly `width` cells (left-aligned unless right=true).
function T.fit(s, width, right)
  s = T.truncate(s or "", width)
  local pad = width - T.width(s)
  if pad <= 0 then return s end
  return right and (string.rep(" ", pad) .. s) or (s .. string.rep(" ", pad))
end

--- Remove terminal control content: ESC/CSI/OSC sequences, C0 controls (except tab), DEL and C1.
function T.sanitize(s)
  if type(s) ~= "string" then return "" end
  s = s:gsub("\27%][^\7\27]*[\7]", "")        -- OSC ... BEL
      :gsub("\27%][^\27]*\27\\", "")          -- OSC ... ST
      :gsub("\27%[[%d;?<>=!]*[%a@`]", "")     -- CSI
      :gsub("\27[PX^_][^\27]*\27\\", "")      -- DCS/SOS/PM/APC
      :gsub("\27[%(%)][%w]", "")               -- charset
      :gsub("\27.", "")                        -- lone ESC + char
      :gsub("\r", "")
      :gsub("[%z\1-\8\11\12\14-\31\127]", "")   -- C0 except \t \n
      :gsub("\194[\128-\159]", "")             -- C1 (UTF-8 encoded)
  return s
end

--- Relative age text.
function T.age(seconds)
  if not seconds then return "-" end
  seconds = math.max(0, math.floor(seconds))
  if seconds < 60 then return seconds .. "s" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
  if seconds < 86400 then return ("%dh%02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)) end
  return math.floor(seconds / 86400) .. "d"
end
function T.duration(seconds)
  if not seconds then return "-" end
  seconds = math.floor(seconds)
  if seconds < 90 then return seconds .. "s" end
  return ("%02d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end
function T.since_iso(iso)
  local ts = require("aiswarm.runtime.util").parse_iso(iso)
  if not ts then return nil end
  return os.time() - ts
end

-- ---------------------------------------------------------------- line builder with byte-accurate spans
local Line = {}
Line.__index = Line
function T.line() return setmetatable({ parts = {}, spans = {}, len = 0 }, Line) end
function Line:add(text, hl)
  text = text or ""
  if text == "" then return self end
  self.parts[#self.parts + 1] = text
  if hl then self.spans[#self.spans + 1] = { self.len, self.len + #text, hl } end
  self.len = self.len + #text
  return self
end
function Line:width() return T.width(table.concat(self.parts)) end
function Line:build() return table.concat(self.parts), self.spans end

T.LAZY_THRESHOLD, T.LAZY_MARGIN = 400, 60
T._lazy = {}

--- Apply highlights for lines [first, last] (1-based, inclusive).
local function apply_spans(buf, ns, lines, first, last)
  for i = math.max(1, first), math.min(#lines, last) do
    local l = lines[i]
    for _, sp in ipairs(l[2] or {}) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, i - 1, sp[1], { end_col = math.min(sp[2], #l[1]), hl_group = sp[3], strict = false })
    end
    if l.virt then pcall(vim.api.nvim_buf_set_extmark, buf, ns, i - 1, 0, { virt_text = l.virt, virt_text_pos = "right_align", strict = false }) end
  end
end

--- Viewport (first, last line) of the first window showing buf, or the whole buffer.
local function viewport(buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      local ok, top = pcall(vim.api.nvim_win_call, win, function() return vim.fn.line("w0"), vim.fn.line("w$") end)
      if ok then local bot = select(2, pcall(vim.api.nvim_win_call, win, function() return vim.fn.line("w$") end)); return top, bot or top + vim.api.nvim_win_get_height(win) end
    end
  end
  return 1, math.huge
end

--- Replace buffer contents with built lines and apply extmark highlights. Large buffers (more than
--- LAZY_THRESHOLD lines) get highlights only around the viewport, refreshed on scroll, so a render
--- batch stays bounded regardless of task count.
---@param lines { [1]: string, [2]: table }[] list of {text, spans}
function T.set_lines(buf, ns, lines, opts)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local texts = {}
  for i, l in ipairs(lines) do texts[i] = l[1] end
  local was = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, texts)
  vim.bo[buf].modifiable = was and (opts and opts.keep_modifiable) or false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if #lines <= T.LAZY_THRESHOLD then
    T._lazy[buf] = nil
    apply_spans(buf, ns, lines, 1, #lines)
    return
  end
  local top, bot = viewport(buf)
  T._lazy[buf] = { ns = ns, lines = lines, applied = { top - T.LAZY_MARGIN, bot + T.LAZY_MARGIN } }
  apply_spans(buf, ns, lines, top - T.LAZY_MARGIN, bot + T.LAZY_MARGIN)
  if not T._lazy_aug then
    T._lazy_aug = vim.api.nvim_create_augroup("AISwarmLazyHighlights", { clear = true })
    vim.api.nvim_create_autocmd({ "WinScrolled", "CursorMoved" }, { group = T._lazy_aug, callback = function(ev)
      local st = T._lazy[ev.buf]
      if not st or not vim.api.nvim_buf_is_valid(ev.buf) then return end
      local t2, b2 = viewport(ev.buf)
      if t2 >= st.applied[1] + T.LAZY_MARGIN / 2 and b2 <= st.applied[2] - T.LAZY_MARGIN / 2 then return end
      vim.api.nvim_buf_clear_namespace(ev.buf, st.ns, 0, -1)
      st.applied = { t2 - T.LAZY_MARGIN, b2 + T.LAZY_MARGIN }
      apply_spans(ev.buf, st.ns, st.lines, st.applied[1], st.applied[2])
    end })
  end
end

return T
