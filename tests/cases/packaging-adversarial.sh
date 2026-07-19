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
      \( -name '.sensai-package.*' -o -name '.sensai-package-lock.*' \) \
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

case_packaging_adversarial() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  PA_BASE=$RUN_TMP/packaging-adversarial
  PA_MATRIX_JSONL=$EVIDENCE_DIR/attack-matrix.jsonl
  mkdir -p "$PA_BASE" || return 70
  PA_BASE=$(CDPATH= cd -- "$PA_BASE" 2>/dev/null && pwd -P) || return 70
  : >"$PA_MATRIX_JSONL" || return 70

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

  PA_ROOT=$PA_BASE/relative-target-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  set +e
  (cd "$PA_BASE" && "$PA_ROOT/bin/sensai" stage relative-target) \
    >"$RUN_TMP/pa-relative-target.out" 2>"$RUN_TMP/pa-relative-target.err"
  PA_RC=$?
  PA_REASON=$(packaging_adversarial_reason "$RUN_TMP/pa-relative-target.err") || return 70
  assert_eq packaging-adversarial.relative_target.exit 65 "$PA_RC" || true
  assert_eq packaging-adversarial.relative_target.reason package.target_not_absolute "$PA_REASON" || true
  PA_ABSENT=true; test ! -e "$PA_BASE/relative-target" || PA_ABSENT=false
  PA_CLEAN=true; packaging_adversarial_no_transaction_artifacts "$PA_BASE" || PA_CLEAN=false
  packaging_adversarial_record_matrix relative_target 65 "$PA_RC" package.target_not_absolute "$PA_REASON" "$PA_ABSENT" "$PA_CLEAN" || return 70

  PA_ROOT=$PA_BASE/normalized-target-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  mkdir -p "$PA_BASE/normalized-parent/child" || return 70
  packaging_adversarial_run_failure normalized_target "$PA_ROOT" \
    "$PA_BASE/normalized-parent/child/../target" 65 package.target_not_normalized || return 70

  PA_ROOT=$PA_BASE/parent-symlink-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  mkdir "$PA_BASE/parent-real" || return 70
  ln -s "$PA_BASE/parent-real" "$PA_BASE/parent-link" || return 70
  packaging_adversarial_run_failure parent_symlink "$PA_ROOT" \
    "$PA_BASE/parent-link/target" 73 package.parent_invalid || return 70

  PA_ROOT=$PA_BASE/missing-parent-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  packaging_adversarial_run_failure missing_parent "$PA_ROOT" \
    "$PA_BASE/missing-parent/target" 73 package.parent_invalid || return 70

  for PA_MANIFEST_CASE in absolute traversal normalized_duplicate blank comment duplicate; do
    PA_ROOT=$PA_BASE/manifest-$PA_MANIFEST_CASE-source
    packaging_adversarial_clone_source "$PA_ROOT" || return 70
    case "$PA_MANIFEST_CASE" in
      absolute)
        sed '1s#.*#/tmp/AGENTS.md#' "$PA_ROOT/manifest.txt" | LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
      traversal)
        sed '1s#.*#../AGENTS.md#' "$PA_ROOT/manifest.txt" | LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
      normalized_duplicate)
        sed '2s#.*#./AGENTS.md#' "$PA_ROOT/manifest.txt" | LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
      blank)
        sed '1s#.*##' "$PA_ROOT/manifest.txt" | LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
      comment)
        awk 'NR == 1 {print "# loader metadata"; next} {print}' "$PA_ROOT/manifest.txt" | \
          LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
      duplicate)
        sed '2s#.*#AGENTS.md#' "$PA_ROOT/manifest.txt" | LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
    esac
    mv "$PA_ROOT/manifest.new" "$PA_ROOT/manifest.txt" || return 70
    packaging_adversarial_run_failure "manifest_$PA_MANIFEST_CASE" "$PA_ROOT" \
      "$PA_BASE/manifest-$PA_MANIFEST_CASE-target" 65 package.manifest_invalid || return 70
  done

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

  PA_ROOT=$PA_BASE/existing-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  PA_TARGET=$PA_BASE/existing-target
  mkdir "$PA_TARGET" || return 70
  chmod 711 "$PA_TARGET" || return 70
  printf '%s\n' '보존 대상' >"$PA_TARGET/marker.txt" || return 70
  chmod 640 "$PA_TARGET/marker.txt" || return 70
  tooling_sha256_file "$PA_TARGET/marker.txt" || return 70
  PA_EXISTING_HASH_BEFORE=$TOOLING_SHA256
  PA_EXISTING_DIR_MODE_BEFORE=$(stat -f '%Lp' "$PA_TARGET") || return 70
  PA_EXISTING_FILE_MODE_BEFORE=$(stat -f '%Lp' "$PA_TARGET/marker.txt") || return 70
  set +e
  "$PA_ROOT/bin/sensai" install "$PA_TARGET" >"$RUN_TMP/pa-existing.out" 2>"$RUN_TMP/pa-existing.err"
  PA_RC=$?
  PA_REASON=$(packaging_adversarial_reason "$RUN_TMP/pa-existing.err") || return 70
  tooling_sha256_file "$PA_TARGET/marker.txt" || return 70
  PA_EXISTING_HASH_AFTER=$TOOLING_SHA256
  PA_EXISTING_DIR_MODE_AFTER=$(stat -f '%Lp' "$PA_TARGET") || return 70
  PA_EXISTING_FILE_MODE_AFTER=$(stat -f '%Lp' "$PA_TARGET/marker.txt") || return 70
  assert_eq packaging-adversarial.existing_target.exit 73 "$PA_RC" || true
  assert_eq packaging-adversarial.existing_target.reason package.target_exists "$PA_REASON" || true
  assert_eq packaging-adversarial.existing_target.bytes "$PA_EXISTING_HASH_BEFORE" "$PA_EXISTING_HASH_AFTER" || true
  assert_eq packaging-adversarial.existing_target.dir_mode "$PA_EXISTING_DIR_MODE_BEFORE" "$PA_EXISTING_DIR_MODE_AFTER" || true
  assert_eq packaging-adversarial.existing_target.file_mode "$PA_EXISTING_FILE_MODE_BEFORE" "$PA_EXISTING_FILE_MODE_AFTER" || true

  PA_ROOT=$PA_BASE/concurrent-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  PA_TARGET=$PA_BASE/concurrent-target
  PA_READY=$PA_BASE/.sensai-test-ready.concurrent
  env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_PACKAGE_PAUSE=after-lock \
    SENSAI_TEST_PACKAGE_READY="$PA_READY" \
    "$PA_ROOT/bin/sensai" stage "$PA_TARGET" \
    >"$RUN_TMP/pa-concurrent-first.out" 2>"$RUN_TMP/pa-concurrent-first.err" &
  ACTIVE_CHILD_PID=$!
  PA_FIRST_PID=$ACTIVE_CHILD_PID
  packaging_adversarial_wait_ready "$PA_READY" || return 70
  set +e
  "$PA_ROOT/bin/sensai" stage "$PA_TARGET" \
    >"$RUN_TMP/pa-concurrent-second.out" 2>"$RUN_TMP/pa-concurrent-second.err"
  PA_RC=$?
  PA_REASON=$(packaging_adversarial_reason "$RUN_TMP/pa-concurrent-second.err") || return 70
  assert_eq packaging-adversarial.concurrent.exit 75 "$PA_RC" || true
  assert_eq packaging-adversarial.concurrent.reason package.locked "$PA_REASON" || true
  kill -TERM "$PA_FIRST_PID" 2>/dev/null || return 70
  wait "$PA_FIRST_PID"
  PA_INTERRUPT_RC=$?
  ACTIVE_CHILD_PID=''
  assert_eq packaging-adversarial.interrupt.exit 130 "$PA_INTERRUPT_RC" || true
  PA_ABSENT=true; test ! -e "$PA_TARGET" || PA_ABSENT=false
  PA_CLEAN=true; packaging_adversarial_no_transaction_artifacts "$PA_BASE" || PA_CLEAN=false
  packaging_adversarial_record_matrix concurrent 75 "$PA_RC" package.locked "$PA_REASON" "$PA_ABSENT" "$PA_CLEAN" || return 70
  jq -n --argjson exit "$PA_INTERRUPT_RC" --argjson target_absent "$PA_ABSENT" \
    --argjson cleanup "$PA_CLEAN" '{signal:"TERM",exit:$exit,target_absent:$target_absent,cleanup:$cleanup}' \
    >"$EVIDENCE_DIR/interrupt.json" || return 70
  jq -n --argjson second_exit "$PA_RC" --arg second_reason "$PA_REASON" \
    --argjson first_exit "$PA_INTERRUPT_RC" --argjson cleanup "$PA_CLEAN" \
    '{first_exit:$first_exit,second_exit:$second_exit,second_reason:$second_reason,cleanup:$cleanup}' \
    >"$EVIDENCE_DIR/lock.json" || return 70
  rm -f "$PA_READY" || return 70

  PA_ROOT=$PA_BASE/atomic-error-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  PA_TARGET=$PA_BASE/atomic-error-target
  set +e
  env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_PACKAGE_FAULT=atomic-move \
    "$PA_ROOT/bin/sensai" stage "$PA_TARGET" \
    >"$RUN_TMP/pa-atomic-error.out" 2>"$RUN_TMP/pa-atomic-error.err"
  PA_RC=$?
  PA_REASON=$(packaging_adversarial_reason "$RUN_TMP/pa-atomic-error.err") || return 70
  assert_eq packaging-adversarial.atomic_error.exit 73 "$PA_RC" || true
  assert_eq packaging-adversarial.atomic_error.reason package.atomic_move_failed "$PA_REASON" || true
  PA_ABSENT=true; test ! -e "$PA_TARGET" || PA_ABSENT=false
  PA_CLEAN=true; packaging_adversarial_no_transaction_artifacts "$PA_BASE" || PA_CLEAN=false
  packaging_adversarial_record_matrix cross_filesystem_error 73 "$PA_RC" package.atomic_move_failed "$PA_REASON" "$PA_ABSENT" "$PA_CLEAN" || return 70

  PA_ROOT=$PA_BASE/loader-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  PA_TARGET=$PA_BASE/loader-target
  "$PA_ROOT/bin/sensai" stage "$PA_TARGET" >"$RUN_TMP/pa-loader.out" 2>"$RUN_TMP/pa-loader.err" || return 70
  printf '%s\n' '# OpenCode loader가 만든 폐기 가능한 파일' >"$PA_TARGET/.gitignore" || return 70
  find "$PA_TARGET" -mindepth 1 ! -type d -print | \
    sed "s#^$PA_TARGET/##" | LC_ALL=C sort >"$RUN_TMP/pa-loader.leaves" || return 70
  sed '/^\.gitignore$/d' "$RUN_TMP/pa-loader.leaves" >"$RUN_TMP/pa-loader.payload-leaves" || return 70
  if cmp -s "$PA_ROOT/manifest.txt" "$RUN_TMP/pa-loader.payload-leaves" && \
     test "$(grep -c '^\.gitignore$' "$RUN_TMP/pa-loader.leaves")" -eq 1; then
    assert_record packaging-adversarial.loader_gitignore 0 'loader가 만든 root .gitignore 하나만 폐기 가능한 metadata로 허용한다' || true
  else
    assert_record packaging-adversarial.loader_gitignore 1 'loader metadata 허용 범위가 정확하지 않다' || true
  fi
  rm "$PA_TARGET/.gitignore" || return 70

  PA_TRANSACTION_REMAINDER=$(find "$PA_BASE" \
    \( -name '.sensai-package.*' -o -name '.sensai-package-lock.*' \) -print | wc -l | tr -d ' ') || return 70
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
