# aiswarm evidence ledger

Automated records written by `scripts/test-aiswarm.sh --task <ID> --record`. Manual records live in `manual/`.
One section per task; a rerun replaces the section.

### SDD-001 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-001`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T035745Z-58399
- Recorded: 2026-09-14T03:57:45Z
- Expected: every case tagged SDD-001 passes
- Actual: 4 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T035745Z-58399/evidence.json`
- Cases:
  - runner.passes: passed
  - runner.isolated_environment: passed
  - runner.tmux_socket_isolated: passed
  - runner.evidence_written: passed


### SDD-002 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-002`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T035745Z-58468
- Recorded: 2026-09-14T03:57:48Z
- Expected: every case tagged SDD-002 passes
- Actual: 21 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T035745Z-58468/evidence.json`
- Cases:
  - legacy.cli.version_and_doctor: passed
  - legacy.cli.snapshot_api_v2_shape: passed
  - legacy.cli.auto_id_and_duplicate_conflict: passed
  - legacy.cli.events_since_and_journal_order: passed
  - legacy.cli.pause_resume_and_exit_codes: passed
  - legacy.cli.mock_exec_lifecycle: passed
  - legacy.quirk.no_automatic_progress: passed
  - legacy.quirk.kill_requeues: passed
  - legacy.quirk.stale_report_after_rerun: passed
  - legacy.quirk.missing_dependency_accepted: passed
  - legacy.quirk.move_first_negative_priority: passed
  - legacy.quirk.set_accepts_invalid_values: passed
  - legacy.quirk.session_name_is_global: passed
  - legacy.lua.commands_and_api_forwards: passed
  - legacy.lua.root_resolution_is_frozen: passed
  - legacy.lua.id_completion_prefix: passed
  - legacy.lua.event_order_dedup: passed
  - legacy.lua.on_event_json_root_check: passed
  - legacy.lua.form_preserves_prompt: passed
  - legacy.lua.snapshot_validation: passed
  - legacy.quirk.dashboard_selection_drift: passed


### SDD-003 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-003`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T035749Z-60237
- Recorded: 2026-09-14T03:57:50Z
- Expected: every case tagged SDD-003 passes
- Actual: 14 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T035749Z-60237/evidence.json`
- Cases:
  - fake.manifest_lists_every_scenario: passed
  - fake.never_resolves_real_provider: passed
  - fake.success_writes_report: passed
  - fake.failure_has_no_report: passed
  - fake.missing_report_exits_zero: passed
  - fake.partial_utf8_bytes: passed
  - fake.interleaved_streams_ordered: passed
  - fake.timeout_runs_until_killed: passed
  - fake.quiet_waits_for_barrier: passed
  - fake.input_request_then_barrier: passed
  - fake.flood_line_count: passed
  - fake.late_finish_leaves_grandchild: passed
  - fake.progress_helper_invoked: passed
  - fake.control_sequences_present_raw: passed


### SDD-004 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-004`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T035750Z-60362
- Recorded: 2026-09-14T03:57:51Z
- Expected: every case tagged SDD-004 passes
- Actual: 6 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T035750Z-60362/evidence.json`
- Cases:
  - spike.clean_startup_time: passed
  - spike.sentinel_user_config_never_loaded: passed
  - spike.records_stream_while_provider_runs: passed
  - spike.record_to_reader_latency: passed
  - spike.process_tree_terminated_on_cancel: passed
  - spike.ten_workers_footprint: passed


### SDD-006 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-006`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T035751Z-60592
- Recorded: 2026-09-14T03:57:51Z
- Expected: every case tagged SDD-006 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T035751Z-60592/evidence.json`
- Cases:
  - protocol.fixtures.valid_round_trip: passed
  - protocol.fixtures.frames_are_jsonl: passed
  - protocol.fixtures.invalid_declare_expectation: passed


### SDD-008 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-008`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T035824Z-60708
- Recorded: 2026-09-14T03:58:24Z
- Expected: every case tagged SDD-008 passes
- Actual: 10 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T035824Z-60708/evidence.json`
- Cases:
  - plan.real_plan_is_valid: passed
  - plan.minimal_valid: passed
  - plan.duplicate_task_reported: passed
  - plan.missing_dependency_reported: passed
  - plan.cycle_reported: passed
  - plan.checked_without_evidence_reported: passed
  - plan.nonexistent_artifact_reported: passed
  - plan.completed_task_with_incomplete_dependency: passed
  - plan.generated_artifacts_ignored_by_git: passed
  - runner.evidence_written: passed


### SDD-009 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-009`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T041043Z-69208
- Recorded: 2026-09-14T04:10:46Z
- Expected: every case tagged SDD-009 passes
- Actual: 4 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T041043Z-69208/evidence.json`
- Cases:
  - compat.namespace.one_state_either_order: passed
  - compat.namespace_canonical_first: passed
  - compat.namespace.commands_registered_once: passed
  - compat.namespace.no_data_moved: passed


### SDD-010 — passed

- Kind: automated
- Status: passed
- Commit: a7ff41d
- Command: `bash scripts/test-aiswarm.sh --task SDD-010`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T153347Z-20463
- Recorded: 2026-09-14T15:33:48Z
- Expected: every case tagged SDD-010 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T153347Z-20463/evidence.json`
- Cases:
  - compat.launchers.wrappers_preserve_argv: passed
  - compat.launchers.old_documented_path_resolves: passed
  - compat.launchers.never_recurse: passed

### SDD-011 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-011`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T041043Z-69208
- Recorded: 2026-09-14T04:10:46Z
- Expected: every case tagged SDD-011 passes
- Actual: 11 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T041043Z-69208/evidence.json`
- Cases:
  - compat.env.cli_canonical_wins: passed
  - compat.env.nvim_canonical_wins: passed
  - compat.env.cli_legacy_only_warns: passed
  - compat.env.nvim_legacy_only_warns: passed
  - compat.env.cli_canonical_only: passed
  - compat.env.nvim_canonical_only: passed
  - compat.env.cli_unset_discovers: passed
  - compat.env.nvim_unset_discovers: passed
  - compat.env.invalid_settings_fail_before_jobs: passed
  - compat.env.provider_default_is_mock: passed
  - compat.env.legacy_notify_keys_translated: passed


### SDD-012 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-012`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T041043Z-69208
- Recorded: 2026-09-14T04:10:46Z
- Expected: every case tagged SDD-012 passes
- Actual: 7 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T041043Z-69208/evidence.json`
- Cases:
  - compat.commands.both_orders_register_once: passed
  - compat.commands.completion: passed
  - compat.commands.unknown_subcommand_fails_clearly: passed
  - compat.commands.v3_only_actions_gated: passed
  - compat.commands.visual_range_reaches_composer: passed
  - compat.commands.legacy_optional_id_still_noop: passed
  - compat.namespace.commands_registered_once: passed


### SDD-013 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-013`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T041043Z-69208
- Recorded: 2026-09-14T04:10:46Z
- Expected: every case tagged SDD-013 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T041043Z-69208/evidence.json`
- Cases:
  - compat.keys.spec_uses_ai_swarm_group: passed
  - compat.keys.no_runtime_conflicts: passed


### SDD-014 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-014`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T041043Z-69208
- Recorded: 2026-09-14T04:10:46Z
- Expected: every case tagged SDD-014 passes
- Actual: 4 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T041043Z-69208/evidence.json`
- Cases:
  - compat.push.duplicate_delivery_one_event: passed
  - compat.push.script_round_trip: passed
  - compat.push.teardown_is_owner_checked: passed
  - compat.push.failed_registration_keeps_follower: passed


### SDD-015 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-015`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T041043Z-69208
- Recorded: 2026-09-14T04:10:46Z
- Expected: every case tagged SDD-015 passes
- Actual: 5 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T041043Z-69208/evidence.json`
- Cases:
  - compat.project().nested_and_symlink_discovery: passed
  - compat.project().both_directories_require_selection: passed
  - compat.project().cwd_change_does_not_retarget: passed
  - compat.project().explicit_switch_keeps_prefs_invalidates_callbacks: passed
  - compat.project().open_creates_nothing: passed


### SDD-016 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-016`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T041043Z-69208
- Recorded: 2026-09-14T04:10:46Z
- Expected: every case tagged SDD-016 passes
- Actual: 5 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T041043Z-69208/evidence.json`
- Cases:
  - compat.env.provider_default_is_mock: passed
  - compat.providers.stable_ids_and_executables: passed
  - compat.providers.unavailable_is_visible_not_silent: passed
  - compat.providers.composer_default_matches_cli: passed
  - compat.providers.generic_capabilities_only: passed


### SDD-017 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-017`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-017 passes
- Actual: 6 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - protocol.valid_fixtures_accepted: passed
  - protocol.invalid_fixtures_rejected: passed
  - protocol.task_ids_are_path_safe: passed
  - protocol.numeric_and_type_checks: passed
  - protocol.unknown_types_inspectable_no_state_change: passed
  - protocol.mutation_arguments_reject_reserved_overrides: passed


### SDD-018 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-018`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-018 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - board.init_is_explicit_and_idempotent: passed
  - board.reads_on_missing_board_create_nothing: passed
  - board.init_cli_creates_v3: passed


### SDD-019 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-019`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-019 passes
- Actual: 5 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - lock.contenders_serialize: passed
  - lock.live_owner_never_stolen: passed
  - lock.dead_owner_recovered: passed
  - lock.pid_reuse_or_unknown_owner_not_deleted: passed
  - lock.sigkilled_holder_leaves_recoverable_lock: passed


### SDD-020 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-020`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-020 passes
- Actual: 4 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - journal.concurrent_writers_unique_contiguous: passed
  - journal.fault_injection_never_reuses_committed_seq: passed
  - journal.missing_sidecar_and_fragment_recovered: passed
  - journal.incomplete_txn_tail_quarantined: passed


### SDD-021 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-021`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-021 passes
- Actual: 4 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - projection.replay_twice_identical: passed
  - projection.stale_applied_is_rebuilt: passed
  - projection.snapshot_never_sees_half_operation: passed
  - protocol.unknown_types_inspectable_no_state_change: passed


### SDD-022 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-022`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-022 passes
- Actual: 6 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - journal.fault_injection_never_reuses_committed_seq: passed
  - journal.missing_sidecar_and_fragment_recovered: passed
  - journal.incomplete_txn_tail_quarantined: passed
  - projection.stale_applied_is_rebuilt: passed
  - recovery.corrupt_interior_record_not_skipped_silently: passed
  - recovery.restart_at_every_crash_point_matches_committed: passed


### SDD-023 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-023`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-023 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - queue.add_atomic_and_structured: passed
  - queue.simultaneous_auto_ids_unique: passed
  - queue.crash_cannot_split_task_and_prompt: passed


### SDD-024 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-024`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-024 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - queue.edit_atomic_with_revision: passed
  - queue.edit_rejected_once_running: passed


### SDD-025 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-025`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-025 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - queue.dependency_graph_validation: passed
  - queue.blockers_derived_from_upstream_outcomes: passed


### SDD-026 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-026`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-026 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - queue.reorder_numeric: passed
  - queue.reorder_cannot_touch_running: passed


### SDD-027 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-027`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-027 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - attempt.identities_immutable_and_disjoint: passed


### SDD-028 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-028`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-028 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - tmux.two_boards_same_task_id_coexist: passed
  - tmux.finished_pane_retained_and_peekable: passed


### SDD-029 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-029`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-029 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - scheduler.singleton_and_authoritative_wip: passed
  - scheduler.stop_does_not_kill_workers: passed


### SDD-030 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-030`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-030 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - isolation.preflight_rejects_unrunnable: passed
  - isolation.worktree_created_or_failed_never_shared: passed


### SDD-031 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-031`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-031 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - dispatch.concurrent_respects_wip_and_uniqueness: passed
  - dispatch.blocked_skipped_and_spawn_failure_released: passed
  - reconcile.startup_timeout: passed


### SDD-032 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-032`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-032 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - fence.duplicate_finish_one_outcome: passed
  - fence.late_finish_cannot_alter_new_attempt: passed
  - fence.exit_and_timeout_reasons: passed


### SDD-033 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-033`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-033 passes
- Actual: 4 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - cancel.no_automatic_requeue: passed
  - cancel.unresponsive_is_force_killed: passed
  - cancel.queued_and_completed_targets: passed
  - cancel.race_with_finish_one_terminal_result: passed


### SDD-034 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-034`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-034 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - retry.fresh_attempt_keeps_history: passed
  - retry.running_and_stale_conflict: passed


### SDD-035 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-035`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-035 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - reconcile.dead_worker_becomes_orphaned: passed
  - reconcile.quiet_and_missing_heartbeat_not_failure: passed
  - reconcile.startup_timeout: passed


### SDD-036 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-036`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-036 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - report.quality_bound_to_exact_attempt: passed


### SDD-037 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-037`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T043914Z-35440
- Recorded: 2026-09-14T04:39:49Z
- Expected: every case tagged SDD-037 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T043914Z-35440/evidence.json`
- Cases:
  - legacy.kill_requeues_once_on_v3: passed
  - legacy.no_compat_path_bypasses_validation: passed


### SDD-038 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-038`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T045529Z-49232
- Recorded: 2026-09-14T04:55:42Z
- Expected: every case tagged SDD-038 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T045529Z-49232/evidence.json`
- Cases:
  - migrate.dry_run_is_read_only: passed


### SDD-039 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-039`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T045529Z-49232
- Recorded: 2026-09-14T04:55:42Z
- Expected: every case tagged SDD-039 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T045529Z-49232/evidence.json`
- Cases:
  - migrate.refuses_live_writer_and_scheduler: passed
  - migrate.backup_verified_and_failure_leaves_source: passed


### SDD-040 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-040`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T045529Z-49232
- Recorded: 2026-09-14T04:55:42Z
- Expected: every case tagged SDD-040 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T045529Z-49232/evidence.json`
- Cases:
  - migrate.converts_evidence_without_inventing_history: passed


### SDD-041 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-041`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T045529Z-49232
- Recorded: 2026-09-14T04:55:42Z
- Expected: every case tagged SDD-041 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T045529Z-49232/evidence.json`
- Cases:
  - migrate.interrupt_resume_and_rollback: passed


### SDD-042 — passed

- Kind: automated
- Status: passed
- Commit: 7bc8340
- Command: `bash scripts/test-aiswarm.sh --task SDD-042`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T045529Z-49232
- Recorded: 2026-09-14T04:55:42Z
- Expected: every case tagged SDD-042 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T045529Z-49232/evidence.json`
- Cases:
  - migrate.project_views_show_legacy_state: passed


### SDD-043 — passed

- Kind: automated
- Status: passed
- Commit: 885cbbc
- Command: `bash scripts/test-aiswarm.sh --task SDD-043`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T132409Z-29893
- Recorded: 2026-09-14T13:24:10Z
- Expected: every case tagged SDD-043 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T132409Z-29893/evidence.json`
- Cases:
  - matrix.both_names_v2_and_v3_boards: passed
  - matrix.unsupported_combinations_fail_explicitly: passed
  - matrix.no_unintended_data_move: passed

### SDD-044 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-044`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-044 passes
- Actual: 4 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - backend.delayed_command_never_blocks: passed
  - backend.timeout_and_start_failure_one_callback: passed
  - backend.project_switch_suppresses_result: passed
  - backend.metacharacters_stay_literal: passed


### SDD-045 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-045`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-045 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - adapter.legacy_snapshot_normalized_with_capabilities: passed
  - adapter.order_and_duplicates_preserved_no_initial_toast: passed
  - adapter.v3_board_through_compat_read_has_attempts: passed


### SDD-046 — passed

- Kind: automated
- Status: passed
- Commit: 885cbbc
- Command: `bash scripts/test-aiswarm.sh --task SDD-046`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T132410Z-31483
- Recorded: 2026-09-14T13:24:10Z
- Expected: every case tagged SDD-046 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T132410Z-31483/evidence.json`
- Cases:
  - store.idempotent_replay_and_selectors: passed
  - store.attempt_identity_fence_and_subscriber_isolation: passed
  - store.activity_bounded_and_coalesced: passed

### SDD-047 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-047`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-047 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - viewstate.selection_by_identity: passed
  - tasks.live_status_change_keeps_selection: passed


### SDD-048 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-048`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-048 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - render.burst_is_coalesced_and_hidden_skipped: passed


### SDD-049 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-049`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-049 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - workspace.single_instance_and_release_only_views: passed
  - workspace.docked_layout_preserves_editing_windows: passed


### SDD-050 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-050`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-050 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - text.cells_truncation_and_sanitize: passed
  - highlights.theme_defaults_preserve_user_overrides: passed


### SDD-051 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-051`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-051 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - tasks.grouped_thousand_fixture: passed
  - tasks.live_status_change_keeps_selection: passed


### SDD-052 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-052`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-052 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - actions.conflict_when_state_changes_under_confirmation: passed
  - actions.taskless_row_cannot_act_and_keys_are_explicit: passed
  - actions.commands_resolve_context_or_picker: passed


### SDD-053 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-053`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-053 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - layout.resolver_is_total_and_matches_adr: passed
  - layout.resize_preserves_navigation_state: passed


### SDD-054 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-054`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-054 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - inspector.delayed_read_only_current_selection_renders: passed


### SDD-055 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-055`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-055 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - inspector.overview_labels_are_honest: passed


### SDD-056 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-056`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-056 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - inspector.output_bounded_follow_and_transcript: passed


### SDD-057 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-057`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-057 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - inspector.report_bound_to_attempt: passed


### SDD-058 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-058`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-058 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - inspector.files_with_provenance: passed


### SDD-059 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-059`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-059 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - inspector.attempt_history_navigation: passed


### SDD-060 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-060`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-060 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - picker.live_updates_keep_query: passed


### SDD-061 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-061`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-061 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - composer.prompt_first_and_provider_default: passed


### SDD-062 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-062`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-062 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - composer.advanced_validation_identifies_fields: passed


### SDD-063 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-063`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-063 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - composer.drafts_persist_and_stay_scoped: passed


### SDD-064 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-064`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-064 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - composer.submit_edit_and_legacy_round_trip: passed


### SDD-065 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-065`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-065 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - firstuse.no_board_to_running_scheduler: passed


### SDD-066 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-066`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-066 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - store.activity_bounded_and_coalesced: passed
  - activity.feed_filters_bounds_and_follow: passed


### SDD-067 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-067`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-067 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - notify.dedupe_bursts_and_no_storm: passed


### SDD-068 — passed

- Kind: automated
- Status: passed
- Commit: 7278463
- Command: `bash scripts/test-aiswarm.sh --task SDD-068`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T105007Z-11098
- Recorded: 2026-09-14T10:50:27Z
- Expected: every case tagged SDD-068 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T105007Z-11098/evidence.json`
- Cases:
  - journey.new_queue_inspect_cancel_retry_report: passed
  - journey.blocked_task_recovery: passed


### SDD-069 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-069`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T113852Z-91091
- Recorded: 2026-09-14T11:39:20Z
- Expected: every case tagged SDD-069 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T113852Z-91091/evidence.json`
- Cases:
  - worker.never_loads_user_config: passed
  - worker.paths_with_spaces: passed
  - worker.missing_runtime_is_environment_error: passed


### SDD-070 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-070`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T113852Z-91091
- Recorded: 2026-09-14T11:39:20Z
- Expected: every case tagged SDD-070 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T113852Z-91091/evidence.json`
- Cases:
  - capture.byte_streams_reconstructed_with_exact_offsets: passed
  - capture.output_before_exit_and_flood_does_not_block: passed


### SDD-071 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-071`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T113852Z-91091
- Recorded: 2026-09-14T11:39:20Z
- Expected: every case tagged SDD-071 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T113852Z-91091/evidence.json`
- Cases:
  - fence.exit_and_timeout_reasons: passed
  - outcome.collector_failure_not_misreported: passed
  - outcome.late_callback_cannot_revive_cancelled: passed


### SDD-072 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-072`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T113852Z-91091
- Recorded: 2026-09-14T11:39:20Z
- Expected: every case tagged SDD-072 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T113852Z-91091/evidence.json`
- Cases:
  - heartbeat.independent_of_output_and_stops_after_exit: passed


### SDD-073 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-073`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T113852Z-91091
- Recorded: 2026-09-14T11:39:20Z
- Expected: every case tagged SDD-073 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T113852Z-91091/evidence.json`
- Cases:
  - journal.ten_attempts_attributed_and_ordered: passed
  - journal.single_writer_and_generation_on_restart: passed


### SDD-074 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-074`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T113852Z-91091
- Recorded: 2026-09-14T11:39:20Z
- Expected: every case tagged SDD-074 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T113852Z-91091/evidence.json`
- Cases:
  - normalize.utf8_lines_previews_and_oversize: passed
  - normalize.worker_never_invents_structure: passed


### SDD-075 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-075`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T113852Z-91091
- Recorded: 2026-09-14T11:39:20Z
- Expected: every case tagged SDD-075 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T113852Z-91091/evidence.json`
- Cases:
  - inbox.concurrent_accepted_partial_ignored_bad_rejected: passed


### SDD-076 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-076`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T113852Z-91091
- Recorded: 2026-09-14T11:39:20Z
- Expected: every case tagged SDD-076 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T113852Z-91091/evidence.json`
- Cases:
  - context.rendered_prompt_points_into_attempt: passed
  - context.helper_from_worktree_and_generic_fallback: passed


### SDD-077 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-077`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T113852Z-91091
- Recorded: 2026-09-14T11:39:20Z
- Expected: every case tagged SDD-077 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T113852Z-91091/evidence.json`
- Cases:
  - activity.projection_recovered_and_aged: passed


### SDD-078 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-078`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T114337Z-17383
- Recorded: 2026-09-14T11:43:55Z
- Expected: every case tagged SDD-078 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T114337Z-17383/evidence.json`
- Cases:
  - frames.every_split_round_trips: passed
  - frames.malformed_oversized_and_incompatible: passed


### SDD-079 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-079`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T114337Z-17383
- Recorded: 2026-09-14T11:43:55Z
- Expected: every case tagged SDD-079 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T114337Z-17383/evidence.json`
- Cases:
  - logs.paged_by_segment_offset_and_stream: passed


### SDD-080 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-080`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T114337Z-17383
- Recorded: 2026-09-14T11:43:55Z
- Expected: every case tagged SDD-080 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T114337Z-17383/evidence.json`
- Cases:
  - stream.multiplex_follow_discovers_new_attempts: passed


### SDD-081 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-081`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T114337Z-17383
- Recorded: 2026-09-14T11:43:55Z
- Expected: every case tagged SDD-081 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T114337Z-17383/evidence.json`
- Cases:
  - stream.multiplex_follow_discovers_new_attempts: passed
  - stream.bootstrap_matches_committed_state: passed


### SDD-082 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-082`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T114337Z-17383
- Recorded: 2026-09-14T11:43:55Z
- Expected: every case tagged SDD-082 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T114337Z-17383/evidence.json`
- Cases:
  - cursor.resume_filter_and_rejections: passed


### SDD-083 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-083`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T114337Z-17383
- Recorded: 2026-09-14T11:43:55Z
- Expected: every case tagged SDD-083 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T114337Z-17383/evidence.json`
- Cases:
  - ack.independent_monotonic_validated: passed


### SDD-084 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-084`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T114337Z-17383
- Recorded: 2026-09-14T11:43:55Z
- Expected: every case tagged SDD-084 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T114337Z-17383/evidence.json`
- Cases:
  - retention.rotation_eviction_and_gaps: passed


### SDD-085 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-085`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T114337Z-17383
- Recorded: 2026-09-14T11:43:55Z
- Expected: every case tagged SDD-085 passes
- Actual: 3 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T114337Z-17383/evidence.json`
- Cases:
  - degrade.lifecycle_commit_failure_reports_recovery_required: passed
  - capture.output_before_exit_and_flood_does_not_block: passed
  - outcome.collector_failure_not_misreported: passed


### SDD-086 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-086`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T114337Z-17383
- Recorded: 2026-09-14T11:43:55Z
- Expected: every case tagged SDD-086 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T114337Z-17383/evidence.json`
- Cases:
  - consumer.durable_delivery_survives_restarts: passed


### SDD-087 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-087`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T114337Z-17383
- Recorded: 2026-09-14T11:43:55Z
- Expected: every case tagged SDD-087 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T114337Z-17383/evidence.json`
- Cases:
  - briefing.bounded_prioritized_with_refs: passed


### SDD-088 — passed

- Kind: automated
- Status: passed
- Commit: 885cbbc
- Command: `bash scripts/test-aiswarm.sh --task SDD-088`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T132413Z-34126
- Recorded: 2026-09-14T13:24:14Z
- Expected: every case tagged SDD-088 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T132413Z-34126/evidence.json`
- Cases:
  - transport.selected_for_v3_and_dedupes: passed

### SDD-089 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-089`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T115200Z-28409
- Recorded: 2026-09-14T11:52:17Z
- Expected: every case tagged SDD-089 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T115200Z-28409/evidence.json`
- Cases:
  - live.progress_and_output_visible_before_completion: passed


### SDD-090 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-090`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T115200Z-28409
- Recorded: 2026-09-14T11:52:17Z
- Expected: every case tagged SDD-090 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T115200Z-28409/evidence.json`
- Cases:
  - push.restricted_to_control_and_optional_legacy_translation: passed


### SDD-091 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-091`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T115200Z-28409
- Recorded: 2026-09-14T11:52:17Z
- Expected: every case tagged SDD-091 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T115200Z-28409/evidence.json`
- Cases:
  - reconnect.backoff_states_and_gap_resync: passed


### SDD-092 — passed

- Kind: automated
- Status: passed
- Commit: 885cbbc
- Command: `bash scripts/test-aiswarm.sh --task SDD-092`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T132410Z-31651
- Recorded: 2026-09-14T13:24:13Z
- Expected: every case tagged SDD-092 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T132410Z-31651/evidence.json`
- Cases:
  - cleanup.repeated_cycles_return_to_baseline: passed

### SDD-093 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-093`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T115200Z-28409
- Recorded: 2026-09-14T11:52:17Z
- Expected: every case tagged SDD-093 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T115200Z-28409/evidence.json`
- Cases:
  - gate.mock_pipeline_scenarios_through_editor_and_consumer: passed


### SDD-094 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-094`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T115731Z-16605
- Recorded: 2026-09-14T11:57:34Z
- Expected: every case tagged SDD-094 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T115731Z-16605/evidence.json`
- Cases:
  - health.fixtures_map_to_severity_and_action: passed
  - health.doctor_and_checkhealth_agree_on_real_boards: passed

### SDD-095 — passed

- Kind: automated
- Status: passed
- Commit: 2fa87ec
- Command: `bash scripts/test-aiswarm.sh --task SDD-095`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T115731Z-16605
- Recorded: 2026-09-14T11:57:34Z
- Expected: every case tagged SDD-095 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T115731Z-16605/evidence.json`
- Cases:
  - statusline.cached_no_io_and_states: passed

### SDD-096 — passed

- Kind: automated
- Status: passed
- Commit: a7ff41d
- Command: `bash scripts/test-aiswarm.sh --task SDD-096`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T153348Z-21117
- Recorded: 2026-09-14T15:33:50Z
- Expected: every case tagged SDD-096 passes
- Actual: 2 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T153348Z-21117/evidence.json`
- Cases:
  - docs.help_tags_and_links_resolve: passed
  - docs.quickstart_runs_with_mock: passed

### SDD-097 — passed

- Kind: automated
- Status: passed
- Commit: 885cbbc
- Command: `bash scripts/test-aiswarm.sh --task SDD-097`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T124518Z-15461
- Recorded: 2026-09-14T12:55:54Z
- Expected: every case tagged SDD-097 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T124518Z-15461/evidence.json`
- Cases:
  - bench.reference_load_envelope: passed


### SDD-098 — passed

- Kind: automated
- Status: passed
- Commit: 885cbbc
- Command: `bash scripts/test-aiswarm.sh --task SDD-098`
- Environment: Neovim 0.12.0-dev+g3afe0c6740, tmux 3.6a, jq-1.7.1-apple, bash 3.2.57(1)-release, Darwin 25.6.0
- Run: 20260914T131338Z-68741
- Recorded: 2026-09-14T13:15:31Z
- Expected: every case tagged SDD-098 passes
- Actual: 1 passed, 0 failed, 0 unverified
- Artifacts: `artifacts/aiswarm/20260914T131338Z-68741/evidence.json`
- Cases:
  - terminal.screens_at_every_size: passed

