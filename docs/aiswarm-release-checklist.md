# aiswarm core release checklist (SDD-100)

Every requirement row of the plan maps to passing evidence in `docs/aiswarm-evidence/` (`ledger.md` for automated records, `manual/` for reviewed records). `bash scripts/validate-aiswarm-plan.sh` checks that every checked task has a passing record and that dependencies are complete.

| Requirement | Evidence | Status |
|---|---|---|
| R01 Brand/compatibility | SDD-002, 009–016, 037, 043, 045, 090, 096 | passed |
| R02 Project/first use | SDD-015, 018, 029, 042, 065 | passed |
| R03 Persistence | SDD-005–006, 017–024 | passed (process-crash safety; power-loss not claimed) |
| R04 Queue/dependencies | SDD-023–026, 031, 062 | passed |
| R05 Attempts/isolation | SDD-027–036, 055, 059, 071 | passed |
| R06 Migration | SDD-038–043 | passed |
| R07 Workspace | SDD-007, 044–053, 060, 068 | passed (headless + real-terminal captures) |
| R08 Inspector/actions | SDD-052, 054–060, 068 | passed |
| R09 Composer | SDD-061–065 | passed |
| R10 Activity/notifications | SDD-055–056, 066–067, 089 | passed |
| R11 Worker telemetry | SDD-003–004, 069–077, 089, 093 | passed |
| R12 Replay/consumer | SDD-006, 078–083, 086–088, 090–091, 093, (106 optional) | passed; SDD-106 not implemented |
| R13 Bounds/retention | SDD-048, 056, 066, 070, 073–074, 078–079, 084–085 | passed |
| R14 Lifecycle cleanup | SDD-015, 044–045, 088, 091–092 | passed |
| R15 Provider capabilities | SDD-016, 074, 094, (101–107 optional) | core passed; native adapters not implemented; SDD-105 (Cursor) dropped by owner decision |
| R16 Accessibility | SDD-007, 050, 053, 098 | passed |
| R17 Integration/package | SDD-008, 013–014, 094–096 | passed |
| R18 Release evidence | SDD-001–008, 043, 068, 093, 097–100 | passed on macOS arm64 (measured values in SDD-097, matrix in SDD-099); Linux, Neovim 0.10.4 minimum, real ENOSPC and power loss unverified |

## Supported versions (recorded, not "latest")

- Neovim: minimum 0.10.4 (documented, health-checked); evidence collected on `v0.12.0-dev-1781+g3afe0c6740`.
- snacks.nvim: `882c996cf28183f4d63640de0b4c02ec886d01f2` (lazy-lock.json).
- tmux 3.6a, jq 1.7.1, bash 3.2.57, macOS 25.6.0 (arm64). Linux: **unverified** (no runner available in this environment; see SDD-099).

## Advertised versus shipped

- Shipped: canonical rename with compatibility, v3 boards with journaled control, attempts, scheduler ownership, cancel/retry, migration, the workspace/composer/activity UI, generic worker telemetry (output, heartbeat, explicit progress), `stream`/`ack`/`logs`/`briefing`, editor transport with reconnect, retention, health, statusline, docs.
- Not shipped and not advertised: provider-native event adapters (SDD-101–104; SDD-105 Cursor dropped, not a target provider), delivery into a named orchestrator runtime (SDD-106), interactive input action (SDD-107). The UI hides these actions; the docs list them under Limits.

## Demonstration

`bash scripts/aiswarm-demo.sh` exercises, from one disposable board: the canonical and legacy names, a full keyboard-free journey (queue → run → cancel → retry → report), live logs and progress through `stream`, and an external consumer restarted mid-delivery. `scripts/screenshot-aiswarm.sh` produces the real-terminal captures.

No commit or publication is implied by this document.
