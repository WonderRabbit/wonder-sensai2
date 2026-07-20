#!/bin/sh

packaging_adversarial_run_source_leaf_cases() {
  for PA_LEAF_CASE in missing fifo directory symlink broken_symlink ancestor_symlink unmanaged; do
    PA_ROOT=$PA_BASE/leaf-$PA_LEAF_CASE-source
    packaging_adversarial_clone_source "$PA_ROOT" || return 70
    PA_EXPECT_REASON=package.source_exact_set_mismatch
    case "$PA_LEAF_CASE" in
      missing)
        rm "$PA_ROOT/output/AGENTS.md" || return 70
        ;;
      fifo)
        rm "$PA_ROOT/output/AGENTS.md" && mkfifo "$PA_ROOT/output/AGENTS.md" || return 70
        PA_EXPECT_REASON=package.source_leaf_invalid
        ;;
      directory)
        rm "$PA_ROOT/output/AGENTS.md" && mkdir "$PA_ROOT/output/AGENTS.md" || return 70
        ;;
      symlink)
        rm "$PA_ROOT/output/AGENTS.md" && ln -s "$PA_ROOT/output/opencode.json" "$PA_ROOT/output/AGENTS.md" || return 70
        PA_EXPECT_REASON=package.source_leaf_invalid
        ;;
      broken_symlink)
        rm "$PA_ROOT/output/AGENTS.md" && ln -s "$PA_ROOT/output/not-present" "$PA_ROOT/output/AGENTS.md" || return 70
        PA_EXPECT_REASON=package.source_leaf_invalid
        ;;
      ancestor_symlink)
        mv "$PA_ROOT/output/agents" "$PA_ROOT/agents-real" || return 70
        ln -s "$PA_ROOT/agents-real" "$PA_ROOT/output/agents" || return 70
        ;;
      unmanaged)
        printf '%s\n' '관리되지 않은 leaf' >"$PA_ROOT/output/unmanaged.txt" || return 70
        ;;
    esac
    packaging_adversarial_run_failure "source_$PA_LEAF_CASE" "$PA_ROOT" \
      "$PA_BASE/leaf-$PA_LEAF_CASE-target" 65 "$PA_EXPECT_REASON" || return 70
  done
}

packaging_adversarial_run_drift_cases() {
  PA_ROOT=$PA_BASE/source-drift-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  PA_TARGET=$PA_BASE/source-drift-target
  PA_READY=$PA_BASE/.sensai-test-ready.source-drift
  env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_PACKAGE_PAUSE=after-source-hash \
    SENSAI_TEST_PACKAGE_READY="$PA_READY" \
    "$PA_ROOT/bin/sensai" stage "$PA_TARGET" \
    >"$RUN_TMP/pa-source-drift.out" 2>"$RUN_TMP/pa-source-drift.err" &
  ACTIVE_CHILD_PID=$!
  packaging_adversarial_wait_ready "$PA_READY" || return 70
  printf '\n격리 source race\n' >>"$PA_ROOT/output/AGENTS.md" || return 70
  : >"$PA_READY.release" || return 70
  tooling_wait_active_child
  PA_RC=$?
  PA_REASON=$(packaging_adversarial_reason "$RUN_TMP/pa-source-drift.err") || return 70
  assert_eq packaging-adversarial.source_drift.exit 65 "$PA_RC" || true
  assert_eq packaging-adversarial.source_drift.reason package.source_hash_drift "$PA_REASON" || true
  PA_ABSENT=true; test ! -e "$PA_TARGET" || PA_ABSENT=false
  PA_CLEAN=true; packaging_adversarial_no_transaction_artifacts "$PA_BASE" || PA_CLEAN=false
  packaging_adversarial_record_matrix source_drift 65 "$PA_RC" package.source_hash_drift "$PA_REASON" "$PA_ABSENT" "$PA_CLEAN" || return 70
  rm -f "$PA_READY" "$PA_READY.release" || return 70

  PA_ROOT=$PA_BASE/staged-drift-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  PA_TARGET=$PA_BASE/staged-drift-target
  set +e
  env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_PACKAGE_FAULT=staged-byte-drift \
    "$PA_ROOT/bin/sensai" stage "$PA_TARGET" \
    >"$RUN_TMP/pa-staged-drift.out" 2>"$RUN_TMP/pa-staged-drift.err"
  PA_RC=$?
  PA_REASON=$(packaging_adversarial_reason "$RUN_TMP/pa-staged-drift.err") || return 70
  assert_eq packaging-adversarial.staged_drift.exit 65 "$PA_RC" || true
  assert_eq packaging-adversarial.staged_drift.reason package.stage_hash_mismatch "$PA_REASON" || true
  PA_ABSENT=true; test ! -e "$PA_TARGET" || PA_ABSENT=false
  PA_CLEAN=true; packaging_adversarial_no_transaction_artifacts "$PA_BASE" || PA_CLEAN=false
  packaging_adversarial_record_matrix staged_drift 65 "$PA_RC" package.stage_hash_mismatch "$PA_REASON" "$PA_ABSENT" "$PA_CLEAN" || return 70
}
