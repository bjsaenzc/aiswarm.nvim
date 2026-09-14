-- SDD-098: real-terminal screenshots (tmux + actual Neovim TUI). Checks essential content survives
-- every size and variant; the reviewer checklist lives in docs/aiswarm-evidence/manual/SDD-098.md.
local sb = require("helpers.sandbox")
return {
  { id = "terminal.screens_at_every_size", tasks = { "SDD-098" }, suites = { "terminal" }, run = function(t)
    local out = t:tmpdir("screens")
    local o = sb.run({ "bash", sb.repo .. "/scripts/screenshot-aiswarm.sh", out }, { env = { PATH = vim.env.PATH, HOME = vim.env.HOME, TMPDIR = vim.env.TMPDIR, AISWARM_NVIM = vim.env.AISWARM_NVIM, AISWARM_TEST_SNACKS = vim.env.AISWARM_TEST_SNACKS }, timeout = 400000 })
    t:eq(o.code, 0, o.stderr:sub(-500))
    local function screen(name) local s = sb.read(out .. "/" .. name .. ".txt"); t:ok(s, "capture " .. name); return s or "" end
    -- wide: three panes, footer hints, selected row, wide glyphs intact, activity tray
    local wide = screen("140x45-dark-01-workspace")
    for _, needle in ipairs({ "RUNNING · 1", "ATTENTION · 1", "QUEUED", "FINISHED", "Enter inspect", "q close", "aiswarm", "Activity", "日本語", "Blocked", "blocked by T-0", "Editing login copy" }) do t:ok(wide:find(needle, 1, true), "140x45 shows " .. needle) end
    t:ok(not wide:find("updates", 1, true), "no toast storm for history at attach")
    t:ok(screen("140x45-dark-03-inspect"):find("[Overview]", 1, true), "inspector tab bar")
    t:ok(screen("140x45-dark-05-output-tab"):find("Output ·", 1, true), "output tab")
    t:ok(screen("140x45-dark-08-cancel-confirm"):find("Cancel T-", 1, true), "cancel confirmation names the target")
    t:ok(screen("140x45-dark-10-composer"):find("Title:", 1, true) and screen("140x45-dark-10-composer"):find("prompt below", 1, true), "composer")
    t:ok(screen("140x45-dark-09-actions-menu"):find("Actions for T-", 1, true), "action menu names its target")
    t:ok(screen("60x20-dark-01-workspace"):find("日本語 タイトル 🚀", 1, true), "wide glyphs intact where the row is not truncated")
    -- medium keeps both panes; narrow shows one pane and Backspace returns; minimal explains
    t:ok(screen("100x30-dark-01-workspace"):find("[Overview]", 1, true) or screen("100x30-dark-01-workspace"):find("Overview", 1, true), "100x30 has an inspector")
    local narrow = screen("60x20-dark-01-workspace"); t:ok(narrow:find("QUEUED", 1, true) and not narrow:find("[Overview]", 1, true), "60x20 shows one pane")
    t:ok(screen("60x20-dark-03-inspect"):find("Overview", 1, true), "60x20 Enter navigates into the inspector")
    t:ok(screen("60x20-dark-07-back"):find("QUEUED", 1, true), "60x20 Backspace returns to the task list")
    t:ok(screen("35x10-dark-01-workspace"):find("40", 1, true) or screen("35x10-dark-01-workspace"):find("picker", 1, true), "35x10 explains the minimum size")
    -- ascii needs no special glyphs; light theme renders the same text
    local ascii = screen("140x45-ascii-01-workspace")
    for _, glyph in ipairs({ "●", "○", "✓", "✗", "◌", "⊘" }) do t:ok(not ascii:find(glyph, 1, true), "ascii variant uses no icon glyph " .. glyph) end
    t:ok(ascii:find("QUEUED", 1, true))
    t:ok(screen("140x45-light-01-workspace"):find("QUEUED", 1, true))
    -- breakpoint edges: 110x30 → 108x27 interior → medium; only ≥112 cols and ≥32 rows would be wide
    t:ok(screen("110x30-boundary-01-workspace"):find("Overview", 1, true))
    -- nothing essential clipped: every capture has the footer's close hint or the minimal explanation
    for _, f in ipairs(vim.fn.glob(out .. "/*-01-workspace.txt", false, true)) do
      local s = sb.read(f)
      -- wide footer: "q close"; narrow footer compacts to "? more  q"; minimal explains the 40-column floor / picker
      t:ok(s:find("q close", 1, true) or s:find("? more  q", 1, true) or s:find("picker", 1, true) or s:find("40", 1, true), "essential action visible in " .. vim.fn.fnamemodify(f, ":t"))
    end
    t:log("screens", out)
  end },
}
