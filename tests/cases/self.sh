#!/bin/sh

self_run() {
  SELF_NAME=$1
  shift
  SELF_OUT="$RUN_TMP/$SELF_NAME.out"
  set +e
  "$@" >"$SELF_OUT" 2>&1
  SELF_RC=$?
  evidence_log_command "$SELF_NAME" "$*" "$SELF_RC"
  return "$SELF_RC"
}

self_prepare_unborn_root() {
  SELF_ROOT=$1
  mkdir -p "$SELF_ROOT" || return 1
  git -C "$SELF_ROOT" init -q || return 1
  printf '%s\n' '.DS_Store' '.omo/' '.debug-journal.md' '.private-state/' \
    >>"$SELF_ROOT/.git/info/exclude" || return 1
  printf 'untracked fingerprint canary\n' >"$SELF_ROOT/marker.txt" || return 1
}

case_self() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  SELF_BASE="$RUN_TMP/self"
  mkdir -p "$SELF_BASE" || return 70

  self_run unknown-selector "$TEST_RUNNER" __definitely_unknown__
  assert_eq self.unknown_exit 64 "$?" || true

  self_run assertion-semantics env SENSAI_TEST_INTERNAL=1 "$TEST_RUNNER" __assertion-probe --evidence "$SELF_BASE/assertion"
  assert_eq self.assertion_exit 1 "$?" || true
  assert_jq self.assertion_receipt '.result == "ASSERTION_FAILURE" and .assertion_count == 1 and .failed_assertion_count == 1 and .failed_assertion_ids == ["self.intentional"]' "$SELF_BASE/assertion/receipt.json" || true

  self_run infrastructure-fault env SENSAI_TEST_FAULT=infra "$TEST_RUNNER" core-readiness --evidence "$SELF_BASE/infra"
  assert_eq self.infrastructure_exit 70 "$?" || true
  assert_jq self.infrastructure_receipt '.result == "INFRASTRUCTURE_ERROR" and .exit == 70' "$SELF_BASE/infra/receipt.json" || true

  self_run empty-discovery env SENSAI_TEST_INTERNAL=1 "$TEST_RUNNER" __empty-probe --evidence "$SELF_BASE/empty"
  assert_eq self.empty_discovery_exit 70 "$?" || true

  self_run misleading-pass env SENSAI_TEST_INTERNAL=1 "$TEST_RUNNER" __misleading-probe --evidence "$SELF_BASE/misleading"
  assert_eq self.misleading_exit 1 "$?" || true
  assert_jq self.misleading_receipt '.result == "ASSERTION_FAILURE" and .exit == 1' "$SELF_BASE/misleading/receipt.json" || true

  self_run missing-command env SENSAI_TEST_FAULT=missing-command "$TEST_RUNNER" core-readiness --evidence "$SELF_BASE/missing-command"
  assert_eq self.missing_command_exit 70 "$?" || true

  for SELF_REJECTED_EXIT in 64 70 127; do
    self_run "expected-failure-reject-$SELF_REJECTED_EXIT" env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_EXPECT_FORCED_EXIT="$SELF_REJECTED_EXIT" "$TEST_RUNNER" expect-fail core-not-ready --evidence "$SELF_BASE/expected-reject-$SELF_REJECTED_EXIT"
    assert_eq "self.expected_failure_reject_$SELF_REJECTED_EXIT" 70 "$?" || true
    assert_jq "self.expected_failure_reject_${SELF_REJECTED_EXIT}_receipt" ".result == \"INFRASTRUCTURE_ERROR\" and .exit == 70 and (.reason_codes | index(\"EXPECTED_FAILURE_INNER_EXIT_$SELF_REJECTED_EXIT\")) != null" "$SELF_BASE/expected-reject-$SELF_REJECTED_EXIT/receipt.json" || true
  done

  SELF_UNBORN_ROOT="$SELF_BASE/unborn-root"
  self_prepare_unborn_root "$SELF_UNBORN_ROOT" || return 70
  self_run source-root-override env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint"
  assert_eq self.source_root_override_exit 0 "$?" || true
  assert_jq self.unborn_fingerprint '.source.git_state == "UNBORN" and .source.untracked_count == 1 and (.source.untracked_inventory | index("?? marker.txt")) != null and .source.file_count == 1' "$SELF_BASE/fingerprint/receipt.json" || true

  SELF_FINGERPRINT_BEFORE_DS_STORE=$(jq -r '.source.fingerprint' "$SELF_BASE/fingerprint/receipt.json") || return 70
  mkdir "$SELF_UNBORN_ROOT/nested" || return 70
  printf 'finder metadata canary\n' >"$SELF_UNBORN_ROOT/.DS_Store" || return 70
  printf 'nested finder metadata canary\n' >"$SELF_UNBORN_ROOT/nested/.DS_Store" || return 70
  self_run source-root-ds-store-excluded env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-ds-store"
  assert_eq self.ds_store_exclusion_exit 0 "$?" || true
  assert_jq self.ds_store_exclusion_receipt ".source.fingerprint == \"$SELF_FINGERPRINT_BEFORE_DS_STORE\" and .source.file_count == 1 and .source.untracked_count == 1 and ([.source.untracked_inventory[] | select(test(\"(^|/)\\\\.DS_Store$\"))] | length) == 0" "$SELF_BASE/fingerprint-ds-store/receipt.json" || true

  mkdir "$SELF_UNBORN_ROOT/.omo" || return 70
  printf 'orchestrator state canary\n' >"$SELF_UNBORN_ROOT/.omo/ledger.jsonl" || return 70
  self_run source-root-omo-excluded env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-omo"
  assert_eq self.omo_exclusion_exit 0 "$?" || true
  assert_jq self.omo_exclusion_receipt ".source.fingerprint == \"$SELF_FINGERPRINT_BEFORE_DS_STORE\" and .source.file_count == 1 and .source.untracked_count == 1 and ([.source.untracked_inventory[] | select(startswith(\"?? .omo\"))] | length) == 0" "$SELF_BASE/fingerprint-omo/receipt.json" || true

  printf 'temporary debug journal\n' >"$SELF_UNBORN_ROOT/.debug-journal.md" || return 70
  self_run source-root-debug-journal-created env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-debug-journal-created"
  assert_eq self.debug_journal_created_exit 0 "$?" || true
  assert_jq self.debug_journal_created_receipt ".source.fingerprint == \"$SELF_FINGERPRINT_BEFORE_DS_STORE\" and .source.file_count == 1 and .source.untracked_count == 1 and (.source.untracked_inventory | index(\"?? .debug-journal.md\")) == null" "$SELF_BASE/fingerprint-debug-journal-created/receipt.json" || true

  printf 'modified temporary debug journal\n' >"$SELF_UNBORN_ROOT/.debug-journal.md" || return 70
  self_run source-root-debug-journal-modified env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-debug-journal-modified"
  assert_eq self.debug_journal_modified_exit 0 "$?" || true
  assert_jq self.debug_journal_modified_receipt ".source.fingerprint == \"$SELF_FINGERPRINT_BEFORE_DS_STORE\" and .source.file_count == 1 and .source.untracked_count == 1" "$SELF_BASE/fingerprint-debug-journal-modified/receipt.json" || true

  rm "$SELF_UNBORN_ROOT/.debug-journal.md" || return 70
  self_run source-root-debug-journal-deleted env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-debug-journal-deleted"
  assert_eq self.debug_journal_deleted_exit 0 "$?" || true
  assert_jq self.debug_journal_deleted_receipt ".source.fingerprint == \"$SELF_FINGERPRINT_BEFORE_DS_STORE\" and .source.file_count == 1 and .source.untracked_count == 1" "$SELF_BASE/fingerprint-debug-journal-deleted/receipt.json" || true

  printf 'similar root path remains source\n' >"$SELF_UNBORN_ROOT/.debug-journal.md.keep" || return 70
  printf 'nested product remains source\n' >"$SELF_UNBORN_ROOT/nested/product.md" || return 70
  self_run source-root-debug-journal-similar-included env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-debug-journal-similar"
  assert_eq self.debug_journal_similar_exit 0 "$?" || true
  assert_jq self.debug_journal_similar_receipt ".source.fingerprint != \"$SELF_FINGERPRINT_BEFORE_DS_STORE\" and .source.file_count == 3 and .source.untracked_count == 3 and (.source.untracked_inventory | index(\"?? .debug-journal.md.keep\")) != null and (.source.untracked_inventory | index(\"?? nested/product.md\")) != null" "$SELF_BASE/fingerprint-debug-journal-similar/receipt.json" || true
  SELF_PRODUCT_FINGERPRINT=$(jq -r '.source.fingerprint' "$SELF_BASE/fingerprint-debug-journal-similar/receipt.json") || return 70

  mkdir "$SELF_UNBORN_ROOT/.private-state" || return 70
  printf 'ignored private state\n' >"$SELF_UNBORN_ROOT/.private-state/session.log" || return 70
  self_run source-root-private-state-ignored env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-private-state"
  assert_eq self.private_state_ignored_exit 0 "$?" || true
  assert_jq self.private_state_ignored_receipt ".source.fingerprint == \"$SELF_PRODUCT_FINGERPRINT\" and .source.file_count == 3 and .source.untracked_count == 3 and ([.source.untracked_inventory[] | select(contains(\".private-state\"))] | length) == 0" "$SELF_BASE/fingerprint-private-state/receipt.json" || true

  printf 'tracked before ignore\n' >"$SELF_UNBORN_ROOT/tracked-private.md" || return 70
  git -C "$SELF_UNBORN_ROOT" add tracked-private.md || return 70
  printf '%s\n' 'tracked-private.md' >>"$SELF_UNBORN_ROOT/.git/info/exclude" || return 70
  self_run source-root-tracked-then-ignored env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-tracked-ignored"
  assert_eq self.tracked_then_ignored_exit 0 "$?" || true
  assert_jq self.tracked_then_ignored_receipt ".source.fingerprint != \"$SELF_PRODUCT_FINGERPRINT\" and .source.file_count == 4 and ([.source.untracked_inventory[] | select(endswith(\"tracked-private.md\"))] | length) == 1" "$SELF_BASE/fingerprint-tracked-ignored/receipt.json" || true
  SELF_TRACKED_FINGERPRINT=$(jq -r '.source.fingerprint' "$SELF_BASE/fingerprint-tracked-ignored/receipt.json") || return 70

  printf 'tracked and modified after ignore\n' >"$SELF_UNBORN_ROOT/tracked-private.md" || return 70
  self_run source-root-tracked-ignored-modified env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-tracked-ignored-modified"
  assert_eq self.tracked_ignored_modified_exit 0 "$?" || true
  assert_jq self.tracked_ignored_modified_receipt ".source.fingerprint != \"$SELF_TRACKED_FINGERPRINT\" and .source.file_count == 4 and ([.source.untracked_inventory[] | select(endswith(\"tracked-private.md\"))] | length) == 1" "$SELF_BASE/fingerprint-tracked-ignored-modified/receipt.json" || true

  printf 'tracked regular placeholder\n' >"$SELF_UNBORN_ROOT/tracked-link.md" || return 70
  git -C "$SELF_UNBORN_ROOT" add tracked-link.md || return 70
  rm "$SELF_UNBORN_ROOT/tracked-link.md" || return 70
  ln -s marker.txt "$SELF_UNBORN_ROOT/tracked-link.md" || return 70
  self_run source-root-tracked-symlink-rejected env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-tracked-symlink"
  assert_eq self.tracked_symlink_rejected_exit 70 "$?" || true
  assert_jq self.tracked_symlink_rejected_receipt '.result == "INFRASTRUCTURE_ERROR" and .exit == 70 and (.reason_codes | index("SOURCE_FINGERPRINT_FAILED")) != null' "$SELF_BASE/fingerprint-tracked-symlink/receipt.json" || true
  rm "$SELF_UNBORN_ROOT/tracked-link.md" || return 70
  git -C "$SELF_UNBORN_ROOT" rm --cached -f -q tracked-link.md || return 70

  printf 'tracked regular placeholder\n' >"$SELF_UNBORN_ROOT/tracked-nonregular.md" || return 70
  git -C "$SELF_UNBORN_ROOT" add tracked-nonregular.md || return 70
  rm "$SELF_UNBORN_ROOT/tracked-nonregular.md" || return 70
  mkfifo "$SELF_UNBORN_ROOT/tracked-nonregular.md" || return 70
  self_run source-root-tracked-nonregular-rejected env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT="$SELF_UNBORN_ROOT" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/fingerprint-tracked-nonregular"
  assert_eq self.tracked_nonregular_rejected_exit 70 "$?" || true
  assert_jq self.tracked_nonregular_rejected_receipt '.result == "INFRASTRUCTURE_ERROR" and .exit == 70 and (.reason_codes | index("SOURCE_FINGERPRINT_FAILED")) != null' "$SELF_BASE/fingerprint-tracked-nonregular/receipt.json" || true
  rm "$SELF_UNBORN_ROOT/tracked-nonregular.md" || return 70
  git -C "$SELF_UNBORN_ROOT" rm --cached -f -q tracked-nonregular.md || return 70

  self_run source-root-escape env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_SOURCE_ROOT=../escape "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_BASE/escape"
  assert_eq self.source_root_escape_exit 70 "$?" || true

  self_run stale-first env SENSAI_TEST_INTERNAL=1 "$TEST_RUNNER" __pass-probe --evidence "$SELF_BASE/stale"
  assert_eq self.stale_first_exit 0 "$?" || true
  self_run stale-second env SENSAI_TEST_INTERNAL=1 "$TEST_RUNNER" __pass-probe --evidence "$SELF_BASE/stale"
  assert_eq self.stale_second_exit 70 "$?" || true

  mkdir "$SELF_BASE/symlink-target" || return 70
  ln -s "$SELF_BASE/symlink-target" "$SELF_BASE/symlink-parent" || return 70
  self_run evidence-ancestor-symlink env SENSAI_TEST_INTERNAL=1 "$TEST_RUNNER" __pass-probe --evidence "$SELF_BASE/symlink-parent/escaped-evidence"
  assert_eq self.evidence_ancestor_symlink_exit 70 "$?" || true
  if ! test -e "$SELF_BASE/symlink-target/escaped-evidence"; then
    assert_record self.evidence_ancestor_symlink_no_write 0 'target received no evidence' || true
  else
    assert_record self.evidence_ancestor_symlink_no_write 1 'target received redirected evidence' || true
  fi

  self_run evidence-parent-traversal env SENSAI_TEST_INTERNAL=1 "$TEST_RUNNER" __pass-probe --evidence "$SELF_BASE/evidence-parent/../escaped-evidence"
  assert_eq self.evidence_parent_traversal_exit 70 "$?" || true

  printf 'not a directory\n' >"$SELF_BASE/evidence-file" || return 70
  self_run evidence-nondirectory-ancestor env SENSAI_TEST_INTERNAL=1 "$TEST_RUNNER" __pass-probe --evidence "$SELF_BASE/evidence-file/child"
  assert_eq self.evidence_nondirectory_ancestor_exit 70 "$?" || true

  SELF_TERM_SOURCE="$SELF_BASE/term-source"
  SELF_TERM_EVIDENCE="$SELF_BASE/term-evidence"
  SELF_TERM_READY="$SELF_BASE/term-ready"
  mkdir "$SELF_TERM_SOURCE" || return 70
  git -C "$SELF_TERM_SOURCE" init -q || return 70
  printf 'delayed fingerprint\n' >"$SELF_TERM_SOURCE/marker.txt" || return 70
  env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_DELAY_FINGERPRINT=1 SENSAI_TEST_DELAY_READY="$SELF_TERM_READY" SENSAI_TEST_SOURCE_ROOT="$SELF_TERM_SOURCE" "$TEST_RUNNER" __fingerprint-probe --evidence "$SELF_TERM_EVIDENCE" >"$SELF_BASE/term.out" 2>&1 &
  SELF_TERM_RUNNER_PID=$!
  SELF_TERM_ATTEMPT=0
  while ! test -f "$SELF_TERM_READY" && test "$SELF_TERM_ATTEMPT" -lt 500; do
    kill -0 "$SELF_TERM_RUNNER_PID" 2>/dev/null || break
    sleep 0.01
    SELF_TERM_ATTEMPT=$((SELF_TERM_ATTEMPT + 1))
  done
  if test -f "$SELF_TERM_READY"; then
    read -r SELF_TERM_CHILD_PID <"$SELF_TERM_READY" || return 70
    kill -TERM "$SELF_TERM_RUNNER_PID" 2>/dev/null || return 70
  else
    kill -TERM "$SELF_TERM_RUNNER_PID" 2>/dev/null || true
    wait "$SELF_TERM_RUNNER_PID" 2>/dev/null || true
    return 70
  fi
  SELF_TERM_ATTEMPT=0
  while ! test -f "$SELF_TERM_EVIDENCE/cleanup.json" && test "$SELF_TERM_ATTEMPT" -lt 500; do
    sleep 0.01
    SELF_TERM_ATTEMPT=$((SELF_TERM_ATTEMPT + 1))
  done
  if ! test -f "$SELF_TERM_EVIDENCE/cleanup.json"; then
    kill -TERM "$SELF_TERM_CHILD_PID" 2>/dev/null || true
    kill -TERM "$SELF_TERM_RUNNER_PID" 2>/dev/null || true
    wait "$SELF_TERM_RUNNER_PID" 2>/dev/null || true
    assert_record self.term_prompt 1 'cleanup receipt missing after bounded wait' || true
  else
    wait "$SELF_TERM_RUNNER_PID" 2>/dev/null
    SELF_TERM_EXIT=$?
    evidence_log_command term-during-fingerprint "$TEST_RUNNER __fingerprint-probe <TERM>" "$SELF_TERM_EXIT"
    assert_eq self.term_exit 130 "$SELF_TERM_EXIT" || true
    if ! kill -0 "$SELF_TERM_CHILD_PID" 2>/dev/null; then
      assert_record self.term_child_reaped 0 "child=$SELF_TERM_CHILD_PID" || true
    else
      kill -TERM "$SELF_TERM_CHILD_PID" 2>/dev/null || true
      assert_record self.term_child_reaped 1 "live_child=$SELF_TERM_CHILD_PID" || true
    fi
    assert_jq self.term_cleanup_receipt ".status == \"PASS\" and .exit == 130 and .signal == \"TERM\" and .signal_child_pid == \"$SELF_TERM_CHILD_PID\" and .signal_child_reaped == true and .temp_removed == true" "$SELF_TERM_EVIDENCE/cleanup.json" || true
    SELF_TERM_TMP=$(jq -r '.temp_root' "$SELF_TERM_EVIDENCE/cleanup.json")
    if ! test -e "$SELF_TERM_TMP"; then
      assert_record self.term_temp_removed 0 "removed=$SELF_TERM_TMP" || true
    else
      assert_record self.term_temp_removed 1 "remaining=$SELF_TERM_TMP" || true
    fi
  fi

  if jq -s -e 'length >= 17 and ([.[].exit] | index(64)) != null and ([.[].exit] | index(70)) != null and ([.[].exit] | index(130)) != null and ([.[].exit] | index(1)) != null' "$EVIDENCE_DIR/commands.jsonl" >/dev/null 2>&1; then
    assert_record self.outer_command_inventory 0 'actual nested command exits include 64,70,1' || true
  else
    assert_record self.outer_command_inventory 1 'missing required nested command exits' || true
  fi

  if test -f "$SELF_BASE/fingerprint/cleanup.json" && jq -e '.status == "PASS" and .temp_removed == true' "$SELF_BASE/fingerprint/cleanup.json" >/dev/null 2>&1; then
    SELF_NESTED_TMP=$(jq -r '.temp_root' "$SELF_BASE/fingerprint/cleanup.json")
    if ! test -e "$SELF_NESTED_TMP"; then
      assert_record self.cleanup_trap 0 "removed=$SELF_NESTED_TMP" || true
    else
      assert_record self.cleanup_trap 1 "remaining=$SELF_NESTED_TMP" || true
    fi
  else
    assert_record self.cleanup_trap 1 'missing or invalid nested cleanup receipt' || true
  fi
}
