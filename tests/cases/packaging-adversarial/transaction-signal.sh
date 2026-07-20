#!/bin/sh

packaging_adversarial_run_install_fault_case() {
  PA_ROOT=$PA_BASE/install-fault-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  PA_INSTALL_HOME=$PA_BASE/install-fault-home
  PA_INSTALL_CONFIG=$PA_INSTALL_HOME/.config/opencode
  PA_INSTALL_CLI=$PA_INSTALL_HOME/.local/bin/sensai
  mkdir -p "$PA_INSTALL_CONFIG" || return 70
  cp "$PA_ROOT/output/AGENTS.md" "$PA_INSTALL_CONFIG/AGENTS.md" || return 70
  printf '%s\n' '보존해야 하는 비관리 파일' >"$PA_INSTALL_CONFIG/unmanaged.txt" || return 70
  tooling_sha256_file "$PA_INSTALL_CONFIG/AGENTS.md" || return 70
  PA_EQUAL_BEFORE=$TOOLING_SHA256
  tooling_sha256_file "$PA_INSTALL_CONFIG/unmanaged.txt" || return 70
  PA_UNMANAGED_BEFORE=$TOOLING_SHA256
  set +e
  env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$PA_INSTALL_HOME" \
    SENSAI_TEST_INTERNAL=1 SENSAI_TEST_PACKAGE_FAULT=before-cli-publish \
    "$PA_ROOT/bin/sensai" install \
    >"$RUN_TMP/pa-install-fault.out" 2>"$RUN_TMP/pa-install-fault.err"
  PA_RC=$?
  PA_REASON=$(packaging_adversarial_reason "$RUN_TMP/pa-install-fault.err") || return 70
  PA_CREATED_ABSENT=true
  while IFS= read -r PA_INSTALL_ENTRY; do
    test "$PA_INSTALL_ENTRY" = AGENTS.md && continue
    if test -e "$PA_INSTALL_CONFIG/$PA_INSTALL_ENTRY" || \
       test -L "$PA_INSTALL_CONFIG/$PA_INSTALL_ENTRY"; then
      PA_CREATED_ABSENT=false
      break
    fi
  done <"$PA_ROOT/manifest.txt"
  tooling_sha256_file "$PA_INSTALL_CONFIG/AGENTS.md" || return 70
  PA_EQUAL_AFTER=$TOOLING_SHA256
  tooling_sha256_file "$PA_INSTALL_CONFIG/unmanaged.txt" || return 70
  PA_UNMANAGED_AFTER=$TOOLING_SHA256
  PA_EQUAL_PRESERVED=false
  test "$PA_EQUAL_BEFORE" = "$PA_EQUAL_AFTER" && PA_EQUAL_PRESERVED=true
  PA_UNMANAGED_PRESERVED=false
  test "$PA_UNMANAGED_BEFORE" = "$PA_UNMANAGED_AFTER" && PA_UNMANAGED_PRESERVED=true
  PA_CLI_ABSENT=true
  test ! -e "$PA_INSTALL_CLI" && test ! -L "$PA_INSTALL_CLI" || PA_CLI_ABSENT=false
  PA_CLEAN=true
  packaging_adversarial_no_transaction_artifacts "$PA_INSTALL_CONFIG" || PA_CLEAN=false
  packaging_adversarial_no_transaction_artifacts "$PA_INSTALL_HOME/.local/bin" || PA_CLEAN=false
  test ! -e "$PA_INSTALL_HOME/.local" && test ! -L "$PA_INSTALL_HOME/.local" || PA_CLEAN=false

  assert_eq packaging-adversarial.install_fault.exit 73 "$PA_RC" || true
  assert_eq packaging-adversarial.install_fault.reason package.publish_failed "$PA_REASON" || true
  assert_eq packaging-adversarial.install_fault.created_managed_absent true "$PA_CREATED_ABSENT" || true
  assert_eq packaging-adversarial.install_fault.preexisting_equal_preserved true "$PA_EQUAL_PRESERVED" || true
  assert_eq packaging-adversarial.install_fault.unmanaged_preserved true "$PA_UNMANAGED_PRESERVED" || true
  assert_eq packaging-adversarial.install_fault.cli_target_absent true "$PA_CLI_ABSENT" || true
  assert_eq packaging-adversarial.install_fault.cleanup true "$PA_CLEAN" || true
  jq -n --argjson exit "$PA_RC" --arg reason "$PA_REASON" \
    --argjson created_managed_absent_after_failure "$PA_CREATED_ABSENT" \
    --argjson preexisting_equal_preserved "$PA_EQUAL_PRESERVED" \
    --argjson unmanaged_preserved "$PA_UNMANAGED_PRESERVED" \
    --argjson cli_target_absent "$PA_CLI_ABSENT" --argjson cleanup "$PA_CLEAN" \
    '{fault:"before-cli-publish",exit:$exit,reason:$reason,created_managed_absent_after_failure:$created_managed_absent_after_failure,preexisting_equal_preserved:$preexisting_equal_preserved,unmanaged_preserved:$unmanaged_preserved,cli_target_absent:$cli_target_absent,cleanup:$cleanup}' \
    >"$EVIDENCE_DIR/install-fault-rollback.json" || return 70
}

packaging_adversarial_run_preexisting_directory_cases() {
  PA_ROOT=$PA_BASE/preexisting-directory-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  for PA_DIRECTORY_KIND in directory symlink_directory; do
    PA_INSTALL_HOME=$PA_BASE/preexisting-$PA_DIRECTORY_KIND-home
    PA_INSTALL_CONFIG=$PA_INSTALL_HOME/.config/opencode
    mkdir -p "$PA_INSTALL_CONFIG/target-real" || return 70
    if test "$PA_DIRECTORY_KIND" = directory; then
      mkdir "$PA_INSTALL_CONFIG/AGENTS.md" || return 70
      PA_DIRECTORY_TARGET=$PA_INSTALL_CONFIG/AGENTS.md
    else
      ln -s "$PA_INSTALL_CONFIG/target-real" "$PA_INSTALL_CONFIG/AGENTS.md" || return 70
      PA_DIRECTORY_TARGET=$PA_INSTALL_CONFIG/target-real
    fi
    printf '%s\n' preserved >"$PA_DIRECTORY_TARGET/sentinel.txt" || return 70
    set +e
    env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$PA_INSTALL_HOME" \
      "$PA_ROOT/bin/sensai" install \
      >"$RUN_TMP/pa-preexisting-$PA_DIRECTORY_KIND.out" \
      2>"$RUN_TMP/pa-preexisting-$PA_DIRECTORY_KIND.err"
    PA_RC=$?
    PA_REASON=$(packaging_adversarial_reason \
      "$RUN_TMP/pa-preexisting-$PA_DIRECTORY_KIND.err") || return 70
    PA_DIRECTORY_CLEAN=true
    test "$(cat "$PA_DIRECTORY_TARGET/sentinel.txt")" = preserved || PA_DIRECTORY_CLEAN=false
    if find "$PA_DIRECTORY_TARGET" -maxdepth 1 -name '.sensai-install.*' \
        -print -quit | grep -q .; then
      PA_DIRECTORY_CLEAN=false
    fi
    assert_eq "packaging-adversarial.preexisting_$PA_DIRECTORY_KIND.exit" 73 "$PA_RC" || true
    assert_eq "packaging-adversarial.preexisting_$PA_DIRECTORY_KIND.reason" \
      package.managed_conflict "$PA_REASON" || true
    assert_eq "packaging-adversarial.preexisting_$PA_DIRECTORY_KIND.preserved" \
      true "$PA_DIRECTORY_CLEAN" || true
  done
}

packaging_adversarial_run_rollback_drift_case() {
  PA_ROOT=$PA_BASE/rollback-drift-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  PA_INSTALL_HOME=$PA_BASE/rollback-drift-home
  PA_INSTALL_CONFIG=$PA_INSTALL_HOME/.config/opencode
  PA_READY=$PA_INSTALL_CONFIG/.sensai-test-ready.rollback-drift
  mkdir -p "$PA_INSTALL_CONFIG" || return 70
  env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$PA_INSTALL_HOME" \
    SENSAI_TEST_INTERNAL=1 SENSAI_TEST_PACKAGE_PAUSE=before-cli-publish \
    SENSAI_TEST_PACKAGE_READY="$PA_READY" SENSAI_TEST_PACKAGE_FAULT=before-cli-publish \
    "$PA_ROOT/bin/sensai" install \
    >"$RUN_TMP/pa-rollback-drift.out" 2>"$RUN_TMP/pa-rollback-drift.err" &
  ACTIVE_CHILD_PID=$!
  packaging_adversarial_wait_ready "$PA_READY" || return 70
  printf '%s\n' 'concurrent in-place drift' >>"$PA_INSTALL_CONFIG/AGENTS.md" || return 70
  : >"$PA_READY.release" || return 70
  tooling_wait_active_child
  PA_DRIFT_RC=$?
  PA_DRIFT_PRESERVED=false
  rg -F -q --no-config 'concurrent in-place drift' "$PA_INSTALL_CONFIG/AGENTS.md" && \
    PA_DRIFT_PRESERVED=true
  PA_DRIFT_REFUSED=false
  rg -F -q --no-config 'reason=package.rollback_failed' \
    "$RUN_TMP/pa-rollback-drift.err" && PA_DRIFT_REFUSED=true
  PA_DRIFT_CLEAN=true
  packaging_adversarial_no_transaction_artifacts "$PA_INSTALL_CONFIG" || PA_DRIFT_CLEAN=false
  packaging_adversarial_no_transaction_artifacts "$PA_INSTALL_HOME/.local/bin" || PA_DRIFT_CLEAN=false
  assert_eq packaging-adversarial.rollback_drift.exit 75 "$PA_DRIFT_RC" || true
  assert_eq packaging-adversarial.rollback_drift.expected_hash_refusal true \
    "$PA_DRIFT_REFUSED" || true
  assert_eq packaging-adversarial.rollback_drift.preserved true "$PA_DRIFT_PRESERVED" || true
  assert_eq packaging-adversarial.rollback_drift.cleanup true "$PA_DRIFT_CLEAN" || true
  jq -n --argjson exit "$PA_DRIFT_RC" --argjson preserved "$PA_DRIFT_PRESERVED" \
    --argjson expected_hash_refusal "$PA_DRIFT_REFUSED" --argjson cleanup "$PA_DRIFT_CLEAN" \
    '{exit:$exit,drifted_target_preserved:$preserved,expected_hash_refusal:$expected_hash_refusal,cleanup:$cleanup}' \
    >"$EVIDENCE_DIR/rollback-drift.json" || return 70
  rm -f "$PA_READY" "$PA_READY.release" || return 70
}

packaging_adversarial_run_publish_ownership_cases() {
  PA_ROOT=$PA_BASE/publish-signal-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  PA_INSTALL_HOME=$PA_BASE/publish-signal-home
  PA_INSTALL_CONFIG=$PA_INSTALL_HOME/.config/opencode
  PA_READY=$PA_INSTALL_CONFIG/.sensai-test-ready.publish-signal
  mkdir -p "$PA_INSTALL_CONFIG" || return 70
  env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$PA_INSTALL_HOME" \
    SENSAI_TEST_INTERNAL=1 SENSAI_TEST_PACKAGE_PAUSE=after-publish-before-journal \
    SENSAI_TEST_PACKAGE_READY="$PA_READY" \
    "$PA_ROOT/bin/sensai" install \
    >"$RUN_TMP/pa-publish-signal.out" 2>"$RUN_TMP/pa-publish-signal.err" &
  ACTIVE_CHILD_PID=$!
  PA_SIGNAL_PID=$ACTIVE_CHILD_PID
  packaging_adversarial_wait_ready "$PA_READY" || return 70
  kill -TERM "$PA_SIGNAL_PID" 2>/dev/null || return 70
  wait "$PA_SIGNAL_PID"
  PA_SIGNAL_RC=$?
  ACTIVE_CHILD_PID=''
  PA_SIGNAL_TARGET_ABSENT=true
  test ! -e "$PA_INSTALL_CONFIG/AGENTS.md" && \
    test ! -L "$PA_INSTALL_CONFIG/AGENTS.md" || PA_SIGNAL_TARGET_ABSENT=false
  PA_SIGNAL_CLEAN=true
  packaging_adversarial_no_transaction_artifacts "$PA_INSTALL_CONFIG" || \
    PA_SIGNAL_CLEAN=false
  packaging_adversarial_no_transaction_artifacts "$PA_INSTALL_HOME/.local/bin" || \
    PA_SIGNAL_CLEAN=false
  assert_eq packaging-adversarial.publish_signal.exit 130 "$PA_SIGNAL_RC" || true
  assert_eq packaging-adversarial.publish_signal.target_absent true \
    "$PA_SIGNAL_TARGET_ABSENT" || true
  assert_eq packaging-adversarial.publish_signal.cleanup true "$PA_SIGNAL_CLEAN" || true
  jq -n --argjson signal_exit "$PA_SIGNAL_RC" \
    --argjson signal_target_absent "$PA_SIGNAL_TARGET_ABSENT" \
    --argjson cleanup "$PA_SIGNAL_CLEAN" \
    '{signal:{exit:$signal_exit,pending_target_absent:$signal_target_absent},cleanup:$cleanup}' \
    >"$EVIDENCE_DIR/publish-ownership.json" || return 70
  rm -f "$PA_READY" || return 70
}

packaging_adversarial_run_lock_interrupt_and_atomic_cases() {
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
}

packaging_adversarial_run_loader_metadata_case() {
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
}
