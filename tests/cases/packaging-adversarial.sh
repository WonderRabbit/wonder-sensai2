#!/bin/sh

packaging_adversarial_clone_source() {
  PA_CLONE_ROOT=$1
  mkdir -p "$PA_CLONE_ROOT/bin" "$PA_CLONE_ROOT/output" || return 70
  cp "$SOURCE_ROOT/bin/sensai" "$PA_CLONE_ROOT/bin/sensai" || return 70
  cp "$SOURCE_ROOT/manifest.txt" "$PA_CLONE_ROOT/manifest.txt" || return 70
  cp -R "$SOURCE_ROOT/output/." "$PA_CLONE_ROOT/output" || return 70
  chmod 755 "$PA_CLONE_ROOT/bin/sensai" || return 70
}

packaging_adversarial_surface_hash() {
  PA_HASH_ROOT=$1
  PA_HASH_DEST=$2
  : >"$PA_HASH_DEST.lines" || return 70
  for PA_HASH_FIXED in bin/sensai manifest.txt; do
    tooling_sha256_file "$PA_HASH_ROOT/$PA_HASH_FIXED" || return 70
    printf '%s  %s\n' "$TOOLING_SHA256" "$PA_HASH_FIXED" >>"$PA_HASH_DEST.lines" || return 70
  done
  while IFS= read -r PA_HASH_ENTRY; do
    tooling_sha256_file "$PA_HASH_ROOT/output/$PA_HASH_ENTRY" || return 70
    printf '%s  output/%s\n' "$TOOLING_SHA256" "$PA_HASH_ENTRY" >>"$PA_HASH_DEST.lines" || return 70
  done <"$PA_HASH_ROOT/manifest.txt"
  tooling_sha256_file "$PA_HASH_DEST.lines" || return 70
  printf '%s\n' "$TOOLING_SHA256" >"$PA_HASH_DEST" || return 70
}

packaging_adversarial_reason() {
  PA_REASON_FILE=$1
  sed -n 's/^오류 reason=\([^ ]*\) detail=.*/\1/p' "$PA_REASON_FILE" | sed -n '1p'
}

packaging_adversarial_no_transaction_artifacts() {
  PA_CLEAN_PARENT=$1
  test -d "$PA_CLEAN_PARENT" || return 0
  if find "$PA_CLEAN_PARENT" -maxdepth 1 \
      \( -name '.sensai-package.*' -o -name '.sensai-package-lock.*' -o \
         -name '.sensai-install.*' -o -name '.sensai-install-lock' \) \
      -print -quit | grep -q .; then
    return 1
  fi
  return 0
}

packaging_adversarial_record_matrix() {
  PA_MATRIX_ID=$1
  PA_MATRIX_EXPECT_EXIT=$2
  PA_MATRIX_ACTUAL_EXIT=$3
  PA_MATRIX_EXPECT_REASON=$4
  PA_MATRIX_ACTUAL_REASON=$5
  PA_MATRIX_TARGET_ABSENT=$6
  PA_MATRIX_CLEAN=$7
  jq -cn \
    --arg id "$PA_MATRIX_ID" \
    --argjson expected_exit "$PA_MATRIX_EXPECT_EXIT" \
    --argjson actual_exit "$PA_MATRIX_ACTUAL_EXIT" \
    --arg expected_reason "$PA_MATRIX_EXPECT_REASON" \
    --arg actual_reason "$PA_MATRIX_ACTUAL_REASON" \
    --argjson target_absent "$PA_MATRIX_TARGET_ABSENT" \
    --argjson transaction_cleanup "$PA_MATRIX_CLEAN" \
    '{id:$id,expected_exit:$expected_exit,actual_exit:$actual_exit,expected_reason:$expected_reason,actual_reason:$actual_reason,target_absent:$target_absent,transaction_cleanup:$transaction_cleanup,pass:($expected_exit==$actual_exit and $expected_reason==$actual_reason and $target_absent and $transaction_cleanup)}' \
    >>"$PA_MATRIX_JSONL" || return 70
}

packaging_adversarial_run_failure() {
  PA_RUN_ID=$1
  PA_RUN_ROOT=$2
  PA_RUN_TARGET=$3
  PA_RUN_EXPECT_EXIT=$4
  PA_RUN_EXPECT_REASON=$5
  PA_RUN_OUT=$RUN_TMP/pa-$PA_RUN_ID.out
  PA_RUN_ERR=$RUN_TMP/pa-$PA_RUN_ID.err
  set +e
  "$PA_RUN_ROOT/bin/sensai" stage "$PA_RUN_TARGET" >"$PA_RUN_OUT" 2>"$PA_RUN_ERR"
  PA_RUN_RC=$?
  PA_RUN_REASON=$(packaging_adversarial_reason "$PA_RUN_ERR") || return 70
  evidence_log_command "packaging-adversarial-$PA_RUN_ID" \
    './bin/sensai stage <isolated-adversarial-target>' "$PA_RUN_RC"
  assert_eq "packaging-adversarial.$PA_RUN_ID.exit" "$PA_RUN_EXPECT_EXIT" "$PA_RUN_RC" || true
  assert_eq "packaging-adversarial.$PA_RUN_ID.reason" "$PA_RUN_EXPECT_REASON" "$PA_RUN_REASON" || true
  if ! test -e "$PA_RUN_TARGET" && ! test -L "$PA_RUN_TARGET"; then
    PA_RUN_ABSENT=true
    assert_record "packaging-adversarial.$PA_RUN_ID.target_absent" 0 '부분 target이 공개되지 않았다' || true
  else
    PA_RUN_ABSENT=false
    assert_record "packaging-adversarial.$PA_RUN_ID.target_absent" 1 '실패 뒤 부분 target이 남았다' || true
  fi
  PA_RUN_PARENT=$(dirname -- "$PA_RUN_TARGET") || return 70
  if packaging_adversarial_no_transaction_artifacts "$PA_RUN_PARENT"; then
    PA_RUN_CLEAN=true
    assert_record "packaging-adversarial.$PA_RUN_ID.cleanup" 0 '소유한 lock과 임시 stage가 남지 않았다' || true
  else
    PA_RUN_CLEAN=false
    assert_record "packaging-adversarial.$PA_RUN_ID.cleanup" 1 'lock 또는 임시 stage가 남았다' || true
  fi
  packaging_adversarial_record_matrix "$PA_RUN_ID" "$PA_RUN_EXPECT_EXIT" "$PA_RUN_RC" \
    "$PA_RUN_EXPECT_REASON" "$PA_RUN_REASON" "$PA_RUN_ABSENT" "$PA_RUN_CLEAN"
}

packaging_adversarial_wait_ready() {
  PA_WAIT_READY=$1
  PA_WAIT_ATTEMPT=0
  while ! test -f "$PA_WAIT_READY"; do
    sleep 1
    PA_WAIT_ATTEMPT=$((PA_WAIT_ATTEMPT + 1))
    test "$PA_WAIT_ATTEMPT" -lt 10 || return 70
  done
}

PACKAGING_ADVERSARIAL_MODULE_DIR=$SCRIPT_DIR/cases/packaging-adversarial
for PACKAGING_ADVERSARIAL_MODULE in path-input source-stage-integrity transaction-signal; do
  PACKAGING_ADVERSARIAL_MODULE_PATH=$PACKAGING_ADVERSARIAL_MODULE_DIR/$PACKAGING_ADVERSARIAL_MODULE.sh
  if ! test -f "$PACKAGING_ADVERSARIAL_MODULE_PATH" || test -L "$PACKAGING_ADVERSARIAL_MODULE_PATH"; then
    printf 'INFRA_ERROR invalid_test_module path=%s\n' "$PACKAGING_ADVERSARIAL_MODULE_PATH" >&2
    exit 70
  fi
  . "$PACKAGING_ADVERSARIAL_MODULE_PATH"
done

packaging_adversarial_prepare() {
  packaging_adversarial_surface_hash "$SOURCE_ROOT" "$RUN_TMP/source-before.sha256" || return 70
  read -r PA_SOURCE_BEFORE <"$RUN_TMP/source-before.sha256" || return 70
  PA_CODEGRAPH_LINK=$SOURCE_ROOT/.codegraph
  PA_CODEGRAPH_TARGET=''
  PA_CODEGRAPH_BEFORE=ABSENT
  if test -L "$PA_CODEGRAPH_LINK"; then
    PA_CODEGRAPH_TARGET=$(readlink "$PA_CODEGRAPH_LINK") || return 70
    if test -f "$PA_CODEGRAPH_TARGET/source.json" && ! test -L "$PA_CODEGRAPH_TARGET/source.json"; then
      tooling_sha256_file "$PA_CODEGRAPH_TARGET/source.json" || return 70
      PA_CODEGRAPH_BEFORE=$TOOLING_SHA256
    fi
  fi
  PA_GLOBAL_FILE=${HOME:-}/.config/opencode/opencode.json
  PA_GLOBAL_BEFORE=ABSENT
  if test -f "$PA_GLOBAL_FILE" && ! test -L "$PA_GLOBAL_FILE"; then
    tooling_sha256_file "$PA_GLOBAL_FILE" || return 70
    PA_GLOBAL_BEFORE=$TOOLING_SHA256
  fi
}

packaging_adversarial_finalize() {
  PA_TRANSACTION_REMAINDER=$(find "$PA_BASE" \
    \( -name '.sensai-package.*' -o -name '.sensai-package-lock.*' -o \
       -name '.sensai-install.*' -o -name '.sensai-install-lock' \) \
    -print | wc -l | tr -d ' ') || return 70
  assert_eq packaging-adversarial.transaction_artifacts 0 "$PA_TRANSACTION_REMAINDER" || true

  packaging_adversarial_surface_hash "$SOURCE_ROOT" "$RUN_TMP/source-after.sha256" || return 70
  read -r PA_SOURCE_AFTER <"$RUN_TMP/source-after.sha256" || return 70
  assert_eq packaging-adversarial.source_unchanged "$PA_SOURCE_BEFORE" "$PA_SOURCE_AFTER" || true
  PA_CODEGRAPH_AFTER=ABSENT
  if test -n "$PA_CODEGRAPH_TARGET" && test -f "$PA_CODEGRAPH_TARGET/source.json" && \
     ! test -L "$PA_CODEGRAPH_TARGET/source.json"; then
    tooling_sha256_file "$PA_CODEGRAPH_TARGET/source.json" || return 70
    PA_CODEGRAPH_AFTER=$TOOLING_SHA256
  fi
  assert_eq packaging-adversarial.codegraph_unchanged "$PA_CODEGRAPH_BEFORE" "$PA_CODEGRAPH_AFTER" || true
  PA_GLOBAL_AFTER=ABSENT
  if test -f "$PA_GLOBAL_FILE" && ! test -L "$PA_GLOBAL_FILE"; then
    tooling_sha256_file "$PA_GLOBAL_FILE" || return 70
    PA_GLOBAL_AFTER=$TOOLING_SHA256
  fi
  assert_eq packaging-adversarial.global_config_unchanged "$PA_GLOBAL_BEFORE" "$PA_GLOBAL_AFTER" || true

  jq -s '.' "$PA_MATRIX_JSONL" >"$EVIDENCE_DIR/attack-matrix.json" || return 70
  PA_MATRIX_COUNT=$(jq 'length' "$EVIDENCE_DIR/attack-matrix.json") || return 70
  assert_eq packaging-adversarial.attack_count 21 "$PA_MATRIX_COUNT" || true
  assert_jq packaging-adversarial.attack_matrix_all_pass \
    'length == 21 and all(.[]; .pass == true)' "$EVIDENCE_DIR/attack-matrix.json" || true
  jq -n --arg source_before "$PA_SOURCE_BEFORE" --arg source_after "$PA_SOURCE_AFTER" \
    --arg global_path "$PA_GLOBAL_FILE" --arg global_before "$PA_GLOBAL_BEFORE" --arg global_after "$PA_GLOBAL_AFTER" \
    --arg codegraph_path "$PA_CODEGRAPH_TARGET/source.json" --arg codegraph_before "$PA_CODEGRAPH_BEFORE" --arg codegraph_after "$PA_CODEGRAPH_AFTER" \
    '{source:{before:$source_before,after:$source_after,unchanged:($source_before==$source_after)},global:{path:$global_path,before:$global_before,after:$global_after,unchanged:($global_before==$global_after)},external_codegraph:{path:$codegraph_path,before:$codegraph_before,after:$codegraph_after,unchanged:($codegraph_before==$codegraph_after)},writes:{global:0,external_codegraph:0}}' \
    >"$EVIDENCE_DIR/before-after-external-global.json" || return 70
  jq -n --argjson attacks "$PA_MATRIX_COUNT" --argjson source_unchanged "$(test "$PA_SOURCE_BEFORE" = "$PA_SOURCE_AFTER" && printf true || printf false)" \
    --argjson global_unchanged "$(test "$PA_GLOBAL_BEFORE" = "$PA_GLOBAL_AFTER" && printf true || printf false)" \
    --argjson codegraph_unchanged "$(test "$PA_CODEGRAPH_BEFORE" = "$PA_CODEGRAPH_AFTER" && printf true || printf false)" \
    --argjson transaction_artifacts "$PA_TRANSACTION_REMAINDER" \
    '{attacks:$attacks,source_unchanged:$source_unchanged,global_unchanged:$global_unchanged,codegraph_unchanged:$codegraph_unchanged,partial_targets:0,owned_locks_remaining:$transaction_artifacts,temp_dirs_remaining:$transaction_artifacts}' \
    >"$EVIDENCE_DIR/cleanup-summary.json" || return 70
  tooling_sha256_file "$SOURCE_ROOT/bin/sensai" || return 70
  PA_BIN_SHA=$TOOLING_SHA256
  tooling_sha256_file "$SOURCE_ROOT/manifest.txt" || return 70
  PA_MANIFEST_SHA=$TOOLING_SHA256
  jq -n --arg source_surface_sha256 "$PA_SOURCE_AFTER" --arg bin_sha256 "$PA_BIN_SHA" \
    --arg manifest_sha256 "$PA_MANIFEST_SHA" --arg codegraph_sha256 "$PA_CODEGRAPH_AFTER" \
    --arg global_config_sha256 "$PA_GLOBAL_AFTER" \
    '{source_surface_sha256:$source_surface_sha256,bin_sha256:$bin_sha256,manifest_sha256:$manifest_sha256,external_codegraph_sha256:$codegraph_sha256,global_config_sha256:$global_config_sha256}' \
    >"$EVIDENCE_DIR/current-hashes.json" || return 70
  jq -n --argjson attacks "$PA_MATRIX_COUNT" --arg selector packaging-adversarial \
    '{task:"T21",selector:$selector,attacks:$attacks,status:"IMPLEMENTED",independent_verification:"PENDING"}' \
    >"$EVIDENCE_DIR/done-claim.json" || return 70
}

case_packaging_adversarial() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  PA_BASE=$RUN_TMP/packaging-adversarial
  PA_MATRIX_JSONL=$EVIDENCE_DIR/attack-matrix.jsonl
  mkdir -p "$PA_BASE" || return 70
  PA_BASE=$(CDPATH= cd -- "$PA_BASE" 2>/dev/null && pwd -P) || return 70
  : >"$PA_MATRIX_JSONL" || return 70

  packaging_adversarial_prepare || return 70
  packaging_adversarial_run_target_and_manifest_cases || return 70
  packaging_adversarial_run_source_leaf_cases || return 70
  packaging_adversarial_run_drift_cases || return 70
  packaging_adversarial_run_install_fault_case || return 70
  packaging_adversarial_run_preexisting_directory_cases || return 70
  packaging_adversarial_run_rollback_drift_case || return 70
  packaging_adversarial_run_publish_ownership_cases || return 70
  packaging_adversarial_run_lock_interrupt_and_atomic_cases || return 70
  packaging_adversarial_run_loader_metadata_case || return 70
  packaging_adversarial_finalize || return 70
}
