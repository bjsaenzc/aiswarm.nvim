# ADR 0004 — Workspace layout breakpoints and focus/action contract

Task: SDD-007 · Status: **accepted** · Date: 2026-09-14 · Requirement: R07, R16

## Breakpoints

Inputs are the workspace **interior** width `W` and height `H` in display cells (float: after subtracting the border; docked: the editor area minus other windows). The resolver is a total function over integer pairs:

```
if W < 40 or H < 12            -> minimal
elseif W < 80 or H < 24        -> narrow
elseif W >= 110 and H >= 28    -> wide
else                           -> medium      (80..109 columns, or >=110 columns with 24..27 rows)
```

| Layout | Panes | Geometry |
|---|---|---|
| wide | tasks, inspector, activity tray | tasks `floor(W*0.35)` (min 30), inspector the rest, tray `max(5, floor(H*0.25))` rows at the bottom spanning both columns |
| medium | tasks, inspector | tasks `floor(W*0.38)` (min 30), inspector the rest; Activity becomes an inspector tab; optional columns (cost, secondary metadata) hidden |
| narrow | one of tasks / inspector / activity | the visible pane uses the whole interior; `Enter` on a task shows the inspector, `Backspace`/`Esc` returns to tasks with selection intact |
| minimal | message + picker | a single pane with the text "aiswarm needs at least 40×12 cells; `p` opens the task picker, `:` a command" and the counts line; no window may receive width/height < 1 |

This resolves the specification gap at ≥110 columns with 24–27 rows by choosing the two-pane layout without a tray. Every resize recomputes the layout and preserves selected task/attempt IDs, active tab, filters, and log scroll/follow state.

## Focus and keys

| Context | Keys |
|---|---|
| any pane | `Tab`/`S-Tab` cycle focus Tasks → Inspector → Activity (only visible panes); `q` closes the workspace; `?` action menu; `Ctrl-r` reconciliation; `P` toggle dispatch pause; `n` compose |
| tasks | `j/k` move; `Enter` inspect (focus inspector; narrow: navigate in); `t` Output tab; `R` Report tab; `g` attach tmux explicitly; `e` edit queued; `x` cancel; `r` retry; `/` filter; `zc/zo` collapse/expand group; `1-5` jump to group |
| inspector | `[`/`]` or `H`/`L` switch tabs; `p` pin/unpin; `f` pause/resume *view following* (Output/Activity tabs only); `G` jump to end; `o` open full transcript; `Backspace`/`Esc` back to tasks (narrow only) |
| activity | `f` pause/resume view following, `G` end, `/` filter, `p` pin scope |
| composer | `Ctrl-s`/`:w` submit; `Esc` (normal mode) closes to a saved draft; `Ctrl-a` toggles Advanced fields; `Ctrl-p` provider picker; `Ctrl-d` dependency picker |
| cancel confirmation | inline prompt naming task and attempt; `y`/`Enter` confirm, `n`/`Esc` abort; focus returns to the invoking pane |

`Ctrl-w` keeps Neovim's window semantics.

## Selection rules

- Selection is `{task_id, attempt_id?}`; rows are looked up by id after every render.
- When the selected task leaves the visible list (filter, collapse, removal), select the row that now occupies its former index; if none, the previous row; if the list is empty, the empty state (no target; actions disabled).
- A **pinned** inspector keeps its `{task_id, attempt_id, tab}` while the task cursor moves; unpinning re-syncs to the cursor. A pinned activity scope keeps its filter while the cursor moves.
- Actions capture `{board_id, task_id, attempt_id, expected_revision}` when invoked; execution re-validates and reports "Task changed; review current state" on conflict.

## Key walkthrough (verified in SDD-053/068)

Tasks `j` → `Enter` (inspector focused, Overview) → `]` (Activity) → `Backspace` (narrow: tasks; wide: no-op) → `n` (composer) → `Esc` (draft saved, workspace focus) → `x` (confirmation names `T-014 · attempt 2`) → `n` (aborted, tasks focused) → `t` (Output, following) → `k` (following paused, unread counter starts) → `f` (following resumed).

The clarification changes no core interaction or latency requirement of the specification.
