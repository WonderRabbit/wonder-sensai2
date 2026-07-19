#!/bin/sh

commands_orchestration_recipe() {
  COMMANDS_ORCHESTRATION_RECIPE_INPUT=$1
  COMMANDS_ORCHESTRATION_RECIPE_OUTPUT=$2
  COMMANDS_ORCHESTRATION_RECIPE_ERROR=$3
  set +e
  jq -f "$SOURCE_ROOT/output/recipes/progress.jq" \
    "$COMMANDS_ORCHESTRATION_RECIPE_INPUT" \
    >"$COMMANDS_ORCHESTRATION_RECIPE_OUTPUT" \
    2>"$COMMANDS_ORCHESTRATION_RECIPE_ERROR"
  COMMANDS_ORCHESTRATION_RECIPE_RC=$?
  evidence_log_command progress-recipe \
    'jq -f output/recipes/progress.jq <envelope>' \
    "$COMMANDS_ORCHESTRATION_RECIPE_RC"
  return "$COMMANDS_ORCHESTRATION_RECIPE_RC"
}

commands_orchestration_expect_failure() {
  COMMANDS_ORCHESTRATION_FAILURE_ID=$1
  COMMANDS_ORCHESTRATION_FAILURE_INPUT=$2
  COMMANDS_ORCHESTRATION_FAILURE_REASON=$3
  COMMANDS_ORCHESTRATION_FAILURE_OUTPUT="$RUN_TMP/$COMMANDS_ORCHESTRATION_FAILURE_ID.out"
  COMMANDS_ORCHESTRATION_FAILURE_ERROR="$RUN_TMP/$COMMANDS_ORCHESTRATION_FAILURE_ID.err"
  if commands_orchestration_recipe \
    "$COMMANDS_ORCHESTRATION_FAILURE_INPUT" \
    "$COMMANDS_ORCHESTRATION_FAILURE_OUTPUT" \
    "$COMMANDS_ORCHESTRATION_FAILURE_ERROR"; then
    assert_record "$COMMANDS_ORCHESTRATION_FAILURE_ID" 1 \
      "unexpected_success reason=$COMMANDS_ORCHESTRATION_FAILURE_REASON" || true
  elif rg -F -q --no-config "$COMMANDS_ORCHESTRATION_FAILURE_REASON" \
    "$COMMANDS_ORCHESTRATION_FAILURE_ERROR"; then
    assert_record "$COMMANDS_ORCHESTRATION_FAILURE_ID" 0 \
      "rejected reason=$COMMANDS_ORCHESTRATION_FAILURE_REASON" || true
  else
    assert_record "$COMMANDS_ORCHESTRATION_FAILURE_ID" 1 \
      "wrong_failure expected=$COMMANDS_ORCHESTRATION_FAILURE_REASON" || true
  fi
}

commands_orchestration_check_inventory() {
  COMMANDS_ORCHESTRATION_COMMANDS_ACTUAL="$RUN_TMP/orchestration-commands-actual.txt"
  COMMANDS_ORCHESTRATION_RECIPES_ACTUAL="$RUN_TMP/orchestration-recipes-actual.txt"
  find "$SOURCE_ROOT/output/commands" -type f -print | \
    sed "s#^$SOURCE_ROOT/output/##" | LC_ALL=C sort \
    >"$COMMANDS_ORCHESTRATION_COMMANDS_ACTUAL" || return 70
  find "$SOURCE_ROOT/output/recipes" -type f -print | \
    sed "s#^$SOURCE_ROOT/output/##" | LC_ALL=C sort \
    >"$COMMANDS_ORCHESTRATION_RECIPES_ACTUAL" || return 70

  if cmp -s "$SOURCE_ROOT/tests/contracts/commands.txt" \
    "$COMMANDS_ORCHESTRATION_COMMANDS_ACTUAL"; then
    assert_record commands-orchestration.command_exact_9 0 'command exact-set 9/9' || true
  else
    assert_record commands-orchestration.command_exact_9 1 'command exact-set mismatch' || true
  fi
  if cmp -s "$SOURCE_ROOT/tests/contracts/recipes.txt" \
    "$COMMANDS_ORCHESTRATION_RECIPES_ACTUAL"; then
    assert_record commands-orchestration.recipe_exact_5 0 'recipe exact-set 5/5' || true
  else
    assert_record commands-orchestration.recipe_exact_5 1 'recipe exact-set mismatch' || true
  fi

  assert_eq commands-orchestration.command_count 9 \
    "$(wc -l <"$COMMANDS_ORCHESTRATION_COMMANDS_ACTUAL" | tr -d ' ')" || true
  assert_eq commands-orchestration.recipe_count 5 \
    "$(wc -l <"$COMMANDS_ORCHESTRATION_RECIPES_ACTUAL" | tr -d ' ')" || true

  if test ! -e "$SOURCE_ROOT/commands" && test ! -e "$SOURCE_ROOT/recipes" && \
     test ! -e "$SOURCE_ROOT/.opencode"; then
    assert_record commands-orchestration.no_runtime_duplicates 0 'root runtime duplicate가 없다' || true
  else
    assert_record commands-orchestration.no_runtime_duplicates 1 'root runtime duplicate가 있다' || true
  fi
}

commands_orchestration_check_frontmatter() {
  COMMANDS_ORCHESTRATION_FRONTMATTER_OK=1
  for COMMANDS_ORCHESTRATION_NAME in run resume status; do
    COMMANDS_ORCHESTRATION_FILE="$SOURCE_ROOT/output/commands/sensai/$COMMANDS_ORCHESTRATION_NAME.md"
    COMMANDS_ORCHESTRATION_META="$RUN_TMP/orchestration-$COMMANDS_ORCHESTRATION_NAME-meta.json"
    if ! test -f "$COMMANDS_ORCHESTRATION_FILE" || test -L "$COMMANDS_ORCHESTRATION_FILE" || \
       ! yq --front-matter=extract -o=json '.' "$COMMANDS_ORCHESTRATION_FILE" \
         >"$COMMANDS_ORCHESTRATION_META" 2>/dev/null || \
       ! jq -e '
         (keys | sort) == (["agent","description","subtask"] | sort)
         and .agent == "sensai-analysis-lead" and .subtask == false
         and (.description | type == "string" and test("[가-힣]"))
       ' "$COMMANDS_ORCHESTRATION_META" >/dev/null 2>&1; then
      COMMANDS_ORCHESTRATION_FRONTMATTER_OK=0
    fi
  done
  assert_eq commands-orchestration.frontmatter 1 "$COMMANDS_ORCHESTRATION_FRONTMATTER_OK" || true
}

commands_orchestration_check_command_contracts() {
  COMMANDS_ORCHESTRATION_RUN="$SOURCE_ROOT/output/commands/sensai/run.md"
  COMMANDS_ORCHESTRATION_RESUME="$SOURCE_ROOT/output/commands/sensai/resume.md"
  COMMANDS_ORCHESTRATION_STATUS="$SOURCE_ROOT/output/commands/sensai/status.md"

  if rg -F -q --no-config '`F0`:' "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -F -q --no-config '`F1`:' "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -F -q --no-config '`F2`:' "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -F -q --no-config '`F3`:' "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -F -q --no-config '`F4`:' "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -F -q --no-config '`F5`:' "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -q --no-config '`F0`.*`F3`.*`F5`.*hard' "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -q --no-config 'actor_role: human.*source: elicited.*verdict: accepted\|rejected' \
       "$COMMANDS_ORCHESTRATION_RUN"; then
    assert_record commands-orchestration.f0_f5_human_receipts 0 'F0-F5와 F0/F3/F5 사람 영수증이 명시됐다' || true
  else
    assert_record commands-orchestration.f0_f5_human_receipts 1 'F0-F5 또는 사람 영수증 계약이 빠졌다' || true
  fi

  if rg -q --no-config 'trace\.json.*>.*progress\.json.*>.*status\.md.*>.*todo' \
       "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -q --no-config '임시 파일.*원자적 rename.*progress\.json' \
       "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -q --no-config '이전 `revision \+ 1`|이전 `revision` \+ 1' \
       "$COMMANDS_ORCHESTRATION_RESUME"; then
    assert_record commands-orchestration.atomic_truth_priority 0 '원자적 revision과 진실 우선순위가 명시됐다' || true
  else
    assert_record commands-orchestration.atomic_truth_priority 1 '원자성 또는 진실 우선순위가 빠졌다' || true
  fi

  if rg -F -q --no-config '`pending`, `in_progress`, `completed`' \
       "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -q --no-config '`blocked`.*(기본|native).*`?todo`? 상태.*(만들지|발명하지)' \
       "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -q --no-config 'todo_snapshot.*(복원|복원한다)' \
       "$COMMANDS_ORCHESTRATION_RESUME"; then
    assert_record commands-orchestration.todo_restore_native_status 0 'todo 복원은 세 native 상태만 사용한다' || true
  else
    assert_record commands-orchestration.todo_restore_native_status 1 'todo 복원 또는 native 상태 계약이 빠졌다' || true
  fi

  if rg -F -q --no-config '`progress.resume.concurrent`' "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -F -q --no-config '`progress.resume.stale_hash`' "$COMMANDS_ORCHESTRATION_RESUME" && \
     rg -F -q --no-config '`progress.resume.stale_revision`' "$COMMANDS_ORCHESTRATION_RESUME" && \
     rg -F -q --no-config '`progress.resume.double_resume`' "$COMMANDS_ORCHESTRATION_RESUME" && \
     rg -q --no-config '잠금.*원자적.*(획득|획득한다)' "$COMMANDS_ORCHESTRATION_RESUME"; then
    assert_record commands-orchestration.concurrency_contract 0 '동일 미션 stale/double/concurrent 재개를 거부한다' || true
  else
    assert_record commands-orchestration.concurrency_contract 1 '재개 동시성 계약이 빠졌다' || true
  fi

  if rg -q --no-config '읽기 전용' "$COMMANDS_ORCHESTRATION_STATUS" && \
     rg -q --no-config '작성·수정·삭제하지' "$COMMANDS_ORCHESTRATION_STATUS" && \
     rg -q --no-config '`status`.*모드.*Markdown.*그대로' "$COMMANDS_ORCHESTRATION_STATUS" && \
     rg -q --no-config '`revision` 증가.*수행하지' "$COMMANDS_ORCHESTRATION_STATUS"; then
    assert_record commands-orchestration.status_read_only_derived 0 'status는 progress 파생 읽기 전용이다' || true
  else
    assert_record commands-orchestration.status_read_only_derived 1 'status 읽기 전용 또는 파생 계약이 빠졌다' || true
  fi

  if ! rg -q --no-config '(^|[^/])docs/analysis/progress\.json|/progress\.json' \
       "$COMMANDS_ORCHESTRATION_RUN" "$COMMANDS_ORCHESTRATION_RESUME" \
       "$COMMANDS_ORCHESTRATION_STATUS" && \
     rg -q --no-config '전역.*progress.*(읽거나 쓰지|쓰지|변경하지)' \
       "$COMMANDS_ORCHESTRATION_RUN" "$COMMANDS_ORCHESTRATION_RESUME" \
       "$COMMANDS_ORCHESTRATION_STATUS"; then
    assert_record commands-orchestration.no_global_progress 0 '미션별 progress만 사용한다' || true
  else
    assert_record commands-orchestration.no_global_progress 1 '전역 progress 경로 또는 금지 계약 누락' || true
  fi

  if rg -F -q --no-config '`/sensai/document-asis`' "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -F -q --no-config '`/sensai/change-design`' "$COMMANDS_ORCHESTRATION_RUN" && \
     rg -F -q --no-config '`/sensai/deliver`' "$COMMANDS_ORCHESTRATION_RUN" && \
     ! test -e "$SOURCE_ROOT/output/commands/sensai/design.md"; then
    assert_record commands-orchestration.ownership_split 0 'AS-IS/change/delivery 소유권이 분리됐다' || true
  else
    assert_record commands-orchestration.ownership_split 1 'command 소유권 분리가 불완전하다' || true
  fi
}

commands_orchestration_make_envelopes() {
  COMMANDS_ORCHESTRATION_PROGRESS="$SOURCE_ROOT/fixtures/expected/progress.json"
  tooling_sha256_file "$COMMANDS_ORCHESTRATION_PROGRESS" || return 70
  COMMANDS_ORCHESTRATION_PROGRESS_HASH=$TOOLING_SHA256

  jq -n --slurpfile progress "$COMMANDS_ORCHESTRATION_PROGRESS" \
    '{mode:"validate",progress:$progress[0]}' \
    >"$RUN_TMP/orchestration-validate.json" || return 70

  jq -n --slurpfile progress "$COMMANDS_ORCHESTRATION_PROGRESS" \
    --arg hash "$COMMANDS_ORCHESTRATION_PROGRESS_HASH" '
    {
      mode:"resume",
      progress:$progress[0],
      progress_sha256:$hash,
      active_progress_sha256:$hash,
      expected_revision:$progress[0].revision,
      observed_fingerprints:{
        trace:$progress[0].precondition_fingerprints.trace,
        inputs:$progress[0].precondition_fingerprints.inputs
      },
      lock:{
        mission_id:$progress[0].mission_id,
        owner:"test-session",
        base_revision:$progress[0].revision,
        base_progress_sha256:$hash,
        exclusive:true
      }
    }' >"$RUN_TMP/orchestration-resume-valid.json" || return 70

  jq '.active_progress_sha256=("0" * 64)' \
    "$RUN_TMP/orchestration-resume-valid.json" \
    >"$RUN_TMP/orchestration-resume-stale.json" || return 70
  jq '.expected_revision += 1' \
    "$RUN_TMP/orchestration-resume-valid.json" \
    >"$RUN_TMP/orchestration-resume-revision.json" || return 70
  jq '.lock.base_revision += 1' \
    "$RUN_TMP/orchestration-resume-valid.json" \
    >"$RUN_TMP/orchestration-resume-double.json" || return 70
  jq '.lock.exclusive=false' \
    "$RUN_TMP/orchestration-resume-valid.json" \
    >"$RUN_TMP/orchestration-resume-concurrent.json" || return 70
  jq '.progress.phase="F6"' \
    "$RUN_TMP/orchestration-resume-valid.json" \
    >"$RUN_TMP/orchestration-resume-corrupt.json" || return 70

  jq -n --slurpfile progress "$COMMANDS_ORCHESTRATION_PROGRESS" \
    '{mode:"status",progress:$progress[0]}' \
    >"$RUN_TMP/orchestration-status.json" || return 70

  jq --arg hash "$COMMANDS_ORCHESTRATION_PROGRESS_HASH" '
    . as $previous
    | ($previous
      | .revision += 1
      | .updated_at="2026-07-19T00:01:00Z"
      | .precondition_fingerprints.previous_progress=$hash) as $current
    | {
        mode:"transition",
        previous:$previous,
        current:$current,
        previous_sha256:$hash,
        active_progress_sha256:$hash,
        observed_fingerprints:{
          trace:$current.precondition_fingerprints.trace,
          inputs:$current.precondition_fingerprints.inputs
        }
      }' "$COMMANDS_ORCHESTRATION_PROGRESS" \
      >"$RUN_TMP/orchestration-transition-valid.json" || return 70
  jq '.current.revision += 1' \
    "$RUN_TMP/orchestration-transition-valid.json" \
    >"$RUN_TMP/orchestration-transition-revision.json" || return 70
  jq '.current.phase="F4" | .current.status="running"' \
    "$RUN_TMP/orchestration-transition-valid.json" \
    >"$RUN_TMP/orchestration-transition-hard-gate.json" || return 70
}

commands_orchestration_check_recipe() {
  COMMANDS_ORCHESTRATION_RECIPE="$SOURCE_ROOT/output/recipes/progress.jq"
  if test -f "$COMMANDS_ORCHESTRATION_RECIPE" && \
     ! test -L "$COMMANDS_ORCHESTRATION_RECIPE" && \
     rg -q --no-config '[가-힣]' "$COMMANDS_ORCHESTRATION_RECIPE" && \
     rg -F -q --no-config 'progress.resume.stale_hash' "$COMMANDS_ORCHESTRATION_RECIPE" && \
     rg -F -q --no-config 'progress.resume.double_resume' "$COMMANDS_ORCHESTRATION_RECIPE"; then
    assert_record commands-orchestration.progress_recipe_surface 0 'progress recipe 표면과 한국어 주석이 있다' || true
  else
    assert_record commands-orchestration.progress_recipe_surface 1 'progress recipe 표면이 불완전하다' || true
  fi

  COMMANDS_ORCHESTRATION_VALID_OUT="$RUN_TMP/orchestration-validate.out"
  COMMANDS_ORCHESTRATION_VALID_ERR="$RUN_TMP/orchestration-validate.err"
  if commands_orchestration_recipe "$RUN_TMP/orchestration-validate.json" \
      "$COMMANDS_ORCHESTRATION_VALID_OUT" "$COMMANDS_ORCHESTRATION_VALID_ERR" && \
     jq -e '. == true' "$COMMANDS_ORCHESTRATION_VALID_OUT" >/dev/null 2>&1; then
    assert_record commands-orchestration.progress_valid 0 'valid progress를 승인한다' || true
  else
    assert_record commands-orchestration.progress_valid 1 'valid progress를 거부했다' || true
  fi

  COMMANDS_ORCHESTRATION_RESUME_OUT="$RUN_TMP/orchestration-resume-valid.out"
  COMMANDS_ORCHESTRATION_RESUME_ERR="$RUN_TMP/orchestration-resume-valid.err"
  if commands_orchestration_recipe "$RUN_TMP/orchestration-resume-valid.json" \
      "$COMMANDS_ORCHESTRATION_RESUME_OUT" "$COMMANDS_ORCHESTRATION_RESUME_ERR" && \
     jq -e '
       .mission_id == "fixture-mission" and .phase == "F3" and .revision == 3
       and (.todo | length == 1)
       and all(.todo[]; (.status | IN("pending","in_progress","completed")))
       and ([.todo[].status] | index("blocked") == null)
       and .pointers.progress == "docs/analysis/missions/fixture-mission/progress.json"
     ' "$COMMANDS_ORCHESTRATION_RESUME_OUT" >/dev/null 2>&1; then
    assert_record commands-orchestration.todo_restore 0 'resume projection이 todo와 포인터를 복원한다' || true
  else
    assert_record commands-orchestration.todo_restore 1 'resume projection이 잘못됐다' || true
  fi

  commands_orchestration_expect_failure \
    commands-orchestration.stale_resume_hash_rejected \
    "$RUN_TMP/orchestration-resume-stale.json" progress.resume.stale_hash
  commands_orchestration_expect_failure \
    commands-orchestration.stale_resume_revision_rejected \
    "$RUN_TMP/orchestration-resume-revision.json" progress.resume.stale_revision
  commands_orchestration_expect_failure \
    commands-orchestration.double_resume_rejected \
    "$RUN_TMP/orchestration-resume-double.json" progress.resume.double_resume
  commands_orchestration_expect_failure \
    commands-orchestration.concurrent_resume_rejected \
    "$RUN_TMP/orchestration-resume-concurrent.json" progress.resume.concurrent
  commands_orchestration_expect_failure \
    commands-orchestration.corrupt_resume_rejected \
    "$RUN_TMP/orchestration-resume-corrupt.json" progress.phase

  COMMANDS_ORCHESTRATION_TRANSITION_OUT="$RUN_TMP/orchestration-transition-valid.out"
  COMMANDS_ORCHESTRATION_TRANSITION_ERR="$RUN_TMP/orchestration-transition-valid.err"
  if commands_orchestration_recipe "$RUN_TMP/orchestration-transition-valid.json" \
      "$COMMANDS_ORCHESTRATION_TRANSITION_OUT" "$COMMANDS_ORCHESTRATION_TRANSITION_ERR" && \
     jq -e '. == true' "$COMMANDS_ORCHESTRATION_TRANSITION_OUT" >/dev/null 2>&1; then
    assert_record commands-orchestration.transition_valid 0 '동일 phase resume checkpoint 전이가 유효하다' || true
  else
    assert_record commands-orchestration.transition_valid 1 '유효 전이를 거부했다' || true
  fi
  commands_orchestration_expect_failure \
    commands-orchestration.transition_revision_rejected \
    "$RUN_TMP/orchestration-transition-revision.json" progress.transition.revision
  commands_orchestration_expect_failure \
    commands-orchestration.transition_hard_gate_rejected \
    "$RUN_TMP/orchestration-transition-hard-gate.json" progress.transition.hard_gate

  COMMANDS_ORCHESTRATION_STATUS_ONE="$RUN_TMP/orchestration-status-one.txt"
  COMMANDS_ORCHESTRATION_STATUS_TWO="$RUN_TMP/orchestration-status-two.txt"
  COMMANDS_ORCHESTRATION_STATUS_ERR="$RUN_TMP/orchestration-status.err"
  if commands_orchestration_recipe "$RUN_TMP/orchestration-status.json" \
      "$COMMANDS_ORCHESTRATION_STATUS_ONE" "$COMMANDS_ORCHESTRATION_STATUS_ERR" && \
     commands_orchestration_recipe "$RUN_TMP/orchestration-status.json" \
      "$COMMANDS_ORCHESTRATION_STATUS_TWO" "$COMMANDS_ORCHESTRATION_STATUS_ERR" && \
     cmp -s "$COMMANDS_ORCHESTRATION_STATUS_ONE" "$COMMANDS_ORCHESTRATION_STATUS_TWO" && \
     rg -F -q --no-config '# 미션 상태: fixture-mission' "$COMMANDS_ORCHESTRATION_STATUS_ONE" && \
     rg -F -q --no-config -- '- human_approval:F3' "$COMMANDS_ORCHESTRATION_STATUS_ONE" && \
     rg -F -q --no-config -- '- record F3 approval receipt' "$COMMANDS_ORCHESTRATION_STATUS_ONE"; then
    assert_record commands-orchestration.status_deterministic 0 'status가 progress에서 결정적으로 파생된다' || true
  else
    assert_record commands-orchestration.status_deterministic 1 'status 파생이 비결정적이거나 필드가 누락됐다' || true
  fi
}

commands_orchestration_clone_source() {
  COMMANDS_ORCHESTRATION_CLONE_ROOT=$1
  mkdir -p "$COMMANDS_ORCHESTRATION_CLONE_ROOT/output" \
    "$COMMANDS_ORCHESTRATION_CLONE_ROOT/fixtures/expected" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$COMMANDS_ORCHESTRATION_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$COMMANDS_ORCHESTRATION_CLONE_ROOT/tests" || return 70
  cp -R "$SOURCE_ROOT/output/commands" "$COMMANDS_ORCHESTRATION_CLONE_ROOT/output/commands" || return 70
  cp -R "$SOURCE_ROOT/output/recipes" "$COMMANDS_ORCHESTRATION_CLONE_ROOT/output/recipes" || return 70
  cp -R "$SOURCE_ROOT/output/schemas" "$COMMANDS_ORCHESTRATION_CLONE_ROOT/output/schemas" || return 70
  cp "$SOURCE_ROOT/fixtures/expected/progress.json" \
    "$COMMANDS_ORCHESTRATION_CLONE_ROOT/fixtures/expected/progress.json" || return 70
}

case_commands_orchestration() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  commands_orchestration_check_inventory || return 70
  commands_orchestration_check_frontmatter || return 70
  commands_orchestration_check_command_contracts || return 70
  commands_orchestration_make_envelopes || return 70
  commands_orchestration_check_recipe || return 70
}

run_expected_stale_resume_hash() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_ORCHESTRATION_ROOT="$RUN_TMP/expect-stale-resume-source"
  EXPECT_ORCHESTRATION_EVIDENCE="$EVIDENCE_DIR/inner-stale-resume"
  commands_orchestration_clone_source "$EXPECT_ORCHESTRATION_ROOT" || return 70
  EXPECT_ORCHESTRATION_RECIPE="$EXPECT_ORCHESTRATION_ROOT/output/recipes/progress.jq"
  perl -0pi -e 's/(issue\("progress\.resume\.stale_hash";\s*)\$envelope\.active_progress_sha256 == \$envelope\.progress_sha256/${1}true/' \
    "$EXPECT_ORCHESTRATION_RECIPE" || return 70
  if cmp -s "$SOURCE_ROOT/output/recipes/progress.jq" "$EXPECT_ORCHESTRATION_RECIPE"; then
    return 70
  fi

  set +e
  env SENSAI_TEST_SOURCE_ROOT="$EXPECT_ORCHESTRATION_ROOT" \
    "$TEST_RUNNER" commands-orchestration --evidence "$EXPECT_ORCHESTRATION_EVIDENCE" \
    >"$RUN_TMP/expect-stale-resume.out" 2>&1
  EXPECT_ORCHESTRATION_RC=$?
  evidence_log_command expected-stale-resume-hash \
    "$TEST_RUNNER commands-orchestration <isolated-stale-resume-check-disabled>" \
    "$EXPECT_ORCHESTRATION_RC"

  case "$EXPECT_ORCHESTRATION_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_ORCHESTRATION_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.stale_resume_hash_exit 1 "$EXPECT_ORCHESTRATION_RC" || true
  if test -f "$EXPECT_ORCHESTRATION_EVIDENCE/receipt.json"; then
    assert_jq expect.stale_resume_hash_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_ORCHESTRATION_EVIDENCE/receipt.json" || true
    assert_jq expect.stale_resume_hash_named_failure \
      '.failed_assertion_ids == ["commands-orchestration.stale_resume_hash_rejected"]' \
      "$EXPECT_ORCHESTRATION_EVIDENCE/receipt.json" || true
  else
    assert_record expect.stale_resume_hash_receipt 1 'missing expected-failure receipt' || true
  fi
}
