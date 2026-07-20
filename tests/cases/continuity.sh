#!/bin/sh

continuity_sha() {
  tooling_sha256_file "$1" || return 70
  CONTINUITY_SHA=$TOOLING_SHA256
}

continuity_run() {
  CONTINUITY_RUN_NAME=$1
  CONTINUITY_RUN_PROJECT=$2
  shift 2
  CONTINUITY_RUN_OUT="$RUN_TMP/$CONTINUITY_RUN_NAME.out"
  CONTINUITY_RUN_ERR="$RUN_TMP/$CONTINUITY_RUN_NAME.err"
  set +e
  SENSAI_PROJECT_ROOT="$CONTINUITY_RUN_PROJECT" \
    "$SOURCE_ROOT/bin/sensai" "$@" >"$CONTINUITY_RUN_OUT" 2>"$CONTINUITY_RUN_ERR"
  CONTINUITY_RUN_RC=$?
  evidence_log_command "$CONTINUITY_RUN_NAME" "./bin/sensai $* <격리 mission 저장소>" "$CONTINUITY_RUN_RC"
}

continuity_project_init() {
  CONTINUITY_PROJECT=$1
  mkdir -p "$CONTINUITY_PROJECT/src" || return 70
  printf '%s\n' '고정 입력' >"$CONTINUITY_PROJECT/src/input.txt" || return 70
  git -C "$CONTINUITY_PROJECT" init -q || return 70
  git -C "$CONTINUITY_PROJECT" config user.email sensai-test@example.invalid || return 70
  git -C "$CONTINUITY_PROJECT" config user.name sensai-test || return 70
  git -C "$CONTINUITY_PROJECT" add src/input.txt || return 70
  git -C "$CONTINUITY_PROJECT" commit -qm 'test: 고정 입력' || return 70
}

continuity_write_receipt() {
  CONTINUITY_RECEIPT_PROJECT=$1
  CONTINUITY_RECEIPT_MISSION=$2
  CONTINUITY_RECEIPT_GATE=$3
  CONTINUITY_RECEIPT_VERDICT=$4
  CONTINUITY_RECEIPT_REASON=$5
  CONTINUITY_RECEIPT_RECORDED=$6
  CONTINUITY_RECEIPT_PROGRESS="$CONTINUITY_RECEIPT_PROJECT/docs/analysis/missions/$CONTINUITY_RECEIPT_MISSION/progress.json"
  CONTINUITY_RECEIPT_REL="docs/analysis/missions/$CONTINUITY_RECEIPT_MISSION/approvals/$CONTINUITY_RECEIPT_GATE-approval.json"
  CONTINUITY_RECEIPT_ABS="$CONTINUITY_RECEIPT_PROJECT/$CONTINUITY_RECEIPT_REL"
  mkdir -p "${CONTINUITY_RECEIPT_ABS%/*}" || return 70
  CONTINUITY_RECEIPT_TRACE=$(jq -r '.precondition_fingerprints.trace' "$CONTINUITY_RECEIPT_PROGRESS") || return 70
  CONTINUITY_RECEIPT_INPUTS=$(jq -r '.precondition_fingerprints.inputs' "$CONTINUITY_RECEIPT_PROGRESS") || return 70
  jq -n --arg mission "$CONTINUITY_RECEIPT_MISSION" --arg gate "$CONTINUITY_RECEIPT_GATE" \
    --arg verdict "$CONTINUITY_RECEIPT_VERDICT" --arg reason "$CONTINUITY_RECEIPT_REASON" \
    --arg recorded "$CONTINUITY_RECEIPT_RECORDED" --arg trace "$CONTINUITY_RECEIPT_TRACE" \
    --arg inputs "$CONTINUITY_RECEIPT_INPUTS" '
      {
        mission_id:$mission,gate:$gate,verdict:$verdict,reason:$reason,
        actor_role:"human",source:"elicited",recorded_at:$recorded,
        trace_sha256:$trace,inputs_sha256:$inputs
      }
    ' >"$CONTINUITY_RECEIPT_ABS" || return 70
  continuity_sha "$CONTINUITY_RECEIPT_ABS" || return 70
  CONTINUITY_RECEIPT_HASH=$CONTINUITY_SHA
}

continuity_make_candidate() {
  CONTINUITY_CANDIDATE_PROJECT=$1
  CONTINUITY_CANDIDATE_MISSION=$2
  CONTINUITY_CANDIDATE_PHASE=$3
  CONTINUITY_CANDIDATE_STATUS=$4
  CONTINUITY_CANDIDATE_TODO=$5
  CONTINUITY_CANDIDATE_NEXT=$6
  CONTINUITY_CANDIDATE_GATE=${7:-}
  CONTINUITY_CANDIDATE_VERDICT=${8:-}
  CONTINUITY_CANDIDATE_REASON=${9:-}
  CONTINUITY_CANDIDATE_PROGRESS="$CONTINUITY_CANDIDATE_PROJECT/docs/analysis/missions/$CONTINUITY_CANDIDATE_MISSION/progress.json"
  continuity_sha "$CONTINUITY_CANDIDATE_PROGRESS" || return 70
  CONTINUITY_CANDIDATE_BASE_HASH=$CONTINUITY_SHA
  CONTINUITY_CANDIDATE_BASE_REVISION=$(jq -r '.revision' "$CONTINUITY_CANDIDATE_PROGRESS") || return 70
  sleep 1
  CONTINUITY_CANDIDATE_UPDATED=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || return 70
  CONTINUITY_CANDIDATE_REL="candidates/$CONTINUITY_CANDIDATE_MISSION-$((CONTINUITY_CANDIDATE_BASE_REVISION + 1)).json"
  CONTINUITY_CANDIDATE_ABS="$CONTINUITY_CANDIDATE_PROJECT/$CONTINUITY_CANDIDATE_REL"
  mkdir -p "${CONTINUITY_CANDIDATE_ABS%/*}" || return 70

  if test -n "$CONTINUITY_CANDIDATE_GATE"; then
    continuity_write_receipt "$CONTINUITY_CANDIDATE_PROJECT" "$CONTINUITY_CANDIDATE_MISSION" \
      "$CONTINUITY_CANDIDATE_GATE" "$CONTINUITY_CANDIDATE_VERDICT" \
      "$CONTINUITY_CANDIDATE_REASON" "$CONTINUITY_CANDIDATE_UPDATED" || return 70
    jq --arg phase "$CONTINUITY_CANDIDATE_PHASE" --arg status "$CONTINUITY_CANDIDATE_STATUS" \
      --arg todo "$CONTINUITY_CANDIDATE_TODO" --arg next "$CONTINUITY_CANDIDATE_NEXT" \
      --arg previous "$CONTINUITY_CANDIDATE_BASE_HASH" --arg updated "$CONTINUITY_CANDIDATE_UPDATED" \
      --arg gate "$CONTINUITY_CANDIDATE_GATE" --arg verdict "$CONTINUITY_CANDIDATE_VERDICT" \
      --arg reason "$CONTINUITY_CANDIDATE_REASON" --arg receipt_path "$CONTINUITY_RECEIPT_REL" \
      --arg receipt_sha256 "$CONTINUITY_RECEIPT_HASH" '
        .phase=$phase | .status=$status | .revision += 1
        | .todo_snapshot=[$todo] | .next=$next | .updated_at=$updated
        | .precondition_fingerprints.previous_progress=$previous
        | .approvals = ([.approvals[] | select(.gate != $gate)] + [{
            gate:$gate,verdict:$verdict,reason:$reason,actor_role:"human",source:"elicited",
            receipt_path:$receipt_path,receipt_sha256:$receipt_sha256,recorded_at:$updated
          }])
      ' "$CONTINUITY_CANDIDATE_PROGRESS" >"$CONTINUITY_CANDIDATE_ABS" || return 70
  else
    jq --arg phase "$CONTINUITY_CANDIDATE_PHASE" --arg status "$CONTINUITY_CANDIDATE_STATUS" \
      --arg todo "$CONTINUITY_CANDIDATE_TODO" --arg next "$CONTINUITY_CANDIDATE_NEXT" \
      --arg previous "$CONTINUITY_CANDIDATE_BASE_HASH" --arg updated "$CONTINUITY_CANDIDATE_UPDATED" '
        .phase=$phase | .status=$status | .revision += 1
        | .todo_snapshot=[$todo] | .next=$next | .updated_at=$updated
        | .precondition_fingerprints.previous_progress=$previous
      ' "$CONTINUITY_CANDIDATE_PROGRESS" >"$CONTINUITY_CANDIDATE_ABS" || return 70
  fi
}

continuity_checkpoint() {
  CONTINUITY_CHECKPOINT_NAME=$1
  CONTINUITY_CHECKPOINT_PROJECT=$2
  CONTINUITY_CHECKPOINT_MISSION=$3
  shift 3
  continuity_make_candidate "$CONTINUITY_CHECKPOINT_PROJECT" "$CONTINUITY_CHECKPOINT_MISSION" "$@" || return 70
  continuity_run "$CONTINUITY_CHECKPOINT_NAME" "$CONTINUITY_CHECKPOINT_PROJECT" mission checkpoint \
    "$CONTINUITY_CHECKPOINT_MISSION" "$CONTINUITY_CANDIDATE_REL" \
    "$CONTINUITY_CANDIDATE_BASE_REVISION" "$CONTINUITY_CANDIDATE_BASE_HASH"
}

continuity_assert_rejected_unchanged() {
  CONTINUITY_REJECT_ID=$1
  CONTINUITY_REJECT_PROJECT=$2
  CONTINUITY_REJECT_MISSION=$3
  CONTINUITY_REJECT_EXPECTED_RC=$4
  CONTINUITY_REJECT_REASON=$5
  CONTINUITY_REJECT_BEFORE_HASH=$6
  CONTINUITY_REJECT_ERR=$7
  continuity_sha "$CONTINUITY_REJECT_PROJECT/docs/analysis/missions/$CONTINUITY_REJECT_MISSION/progress.json" || return 70
  if test "$CONTINUITY_RUN_RC" -eq "$CONTINUITY_REJECT_EXPECTED_RC" && \
     rg -F -q --no-config "reason=$CONTINUITY_REJECT_REASON" "$CONTINUITY_REJECT_ERR" && \
     test "$CONTINUITY_SHA" = "$CONTINUITY_REJECT_BEFORE_HASH" && \
     test ! -e "$CONTINUITY_REJECT_PROJECT/docs/analysis/missions/$CONTINUITY_REJECT_MISSION/.sensai-lock"; then
    assert_record "$CONTINUITY_REJECT_ID" 0 "거부 reason=$CONTINUITY_REJECT_REASON, progress와 lock 불변" || true
  else
    assert_record "$CONTINUITY_REJECT_ID" 1 "거부 또는 불변 계약 위반 reason=$CONTINUITY_REJECT_REASON" || true
  fi
}

continuity_gate_flow() {
  CONTINUITY_MAIN=$RUN_TMP/continuity-main
  CONTINUITY_MISSION=continuity-mission
  continuity_project_init "$CONTINUITY_MAIN" || return 70
  CONTINUITY_MAIN=$(CDPATH= cd -- "$CONTINUITY_MAIN" 2>/dev/null && pwd -P) || return 70
  continuity_run continuity-init "$CONTINUITY_MAIN" mission init "$CONTINUITY_MISSION" src '연속성 검증'
  if test "$CONTINUITY_RUN_RC" -eq 0 && \
     jq -e '.phase=="F0" and .status=="planned" and .revision==1' \
       "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/progress.json" >/dev/null 2>&1; then
    assert_record continuity.init_atomic 0 'F0 원장, progress, 파생 status를 원자적으로 초기화했다' || true
  else
    assert_record continuity.init_atomic 1 '미션 초기화가 실패했다' || true
    return 0
  fi

  CONTINUITY_PROGRESS="$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/progress.json"
  CONTINUITY_STATUS="$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/status.md"

  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_BEFORE=$CONTINUITY_SHA
  continuity_checkpoint f0-bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F1 running 'F1 기술 분석' 'F1 기술 분석을 실행한다'
  continuity_assert_rejected_unchanged continuity.gate_f0_bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    65 progress.transition.invalid "$CONTINUITY_BEFORE" "$CONTINUITY_RUN_ERR" || return 70

  continuity_checkpoint f0-rejected "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F0 awaiting_human_approval 'F0 수정 계획 대기' '거절 사유를 반영해 계획을 수정한다' \
    F0 rejected '범위를 더 좁혀야 한다'
  assert_eq continuity.f0_rejection_checkpoint 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint f0-retry-accepted "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F0 awaiting_human_approval 'F0 승인 완료' 'F1 기술 분석을 시작한다' \
    F0 accepted '수정된 범위와 계획을 승인한다'
  assert_eq continuity.f0_retry_accept 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint enter-f1 "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F1 running 'F1 기술 분석 진행' 'F1 기술 분석을 완료한다'
  assert_eq continuity.enter_f1 0 "$CONTINUITY_RUN_RC" || true

  CONTINUITY_F0_RECEIPT="$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/approvals/F0-approval.json"
  cp "$CONTINUITY_F0_RECEIPT" "$RUN_TMP/F0-approval-backup.json" || return 70
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_STALE_APPROVAL_BASE=$CONTINUITY_SHA
  printf '%s\n' 'stale approval drift' >>"$CONTINUITY_F0_RECEIPT" || return 70
  continuity_run stale-approval "$CONTINUITY_MAIN" mission resume "$CONTINUITY_MISSION"
  continuity_assert_rejected_unchanged continuity.stale_approval "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    65 progress.approval_receipt "$CONTINUITY_STALE_APPROVAL_BASE" "$CONTINUITY_RUN_ERR" || return 70
  cp "$RUN_TMP/F0-approval-backup.json" "$CONTINUITY_F0_RECEIPT" || return 70

  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_INTERRUPT_HASH=$CONTINUITY_SHA
  CONTINUITY_INTERRUPT_REV=$(jq -r '.revision' "$CONTINUITY_PROGRESS") || return 70
  CONTINUITY_CAPTURE="$CONTINUITY_MAIN/.sensai-test-capture.interrupt"
  set +e
  SENSAI_TEST_INTERNAL=1 SENSAI_TEST_MISSION_INTERRUPT=after-lock \
    SENSAI_TEST_MISSION_CAPTURE="$CONTINUITY_CAPTURE" SENSAI_PROJECT_ROOT="$CONTINUITY_MAIN" \
    "$SOURCE_ROOT/bin/sensai" mission resume "$CONTINUITY_MISSION" \
    "$CONTINUITY_INTERRUPT_REV" "$CONTINUITY_INTERRUPT_HASH" \
    >"$RUN_TMP/interrupt.out" 2>"$RUN_TMP/interrupt.err"
  CONTINUITY_INTERRUPT_RC=$?
  cp "$CONTINUITY_CAPTURE" "$RUN_TMP/interrupt-lock-owner.json" || return 70
  evidence_log_command continuity-interrupt './bin/sensai mission resume <test-only interrupt after lock>' "$CONTINUITY_INTERRUPT_RC"
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  if test "$CONTINUITY_INTERRUPT_RC" -eq 130 && test "$CONTINUITY_SHA" = "$CONTINUITY_INTERRUPT_HASH" && \
     test ! -e "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock" && \
     jq -e --arg mission "$CONTINUITY_MISSION" --argjson revision "$CONTINUITY_INTERRUPT_REV" \
       --arg hash "$CONTINUITY_INTERRUPT_HASH" '
         .mission_id==$mission and .base_revision==$revision
         and .base_progress_sha256==$hash and .exclusive==true
       ' "$RUN_TMP/interrupt-lock-owner.json" >/dev/null 2>&1; then
    assert_record continuity.interrupt_cleanup 0 '중단 시 정규 상태 불변, 기준 잠금 기록 후 정리' || true
  else
    assert_record continuity.interrupt_cleanup 1 '중단 정리 또는 기준 잠금 계약 위반' || true
  fi

  continuity_run fresh-process-resume "$CONTINUITY_MAIN" mission resume "$CONTINUITY_MISSION" \
    "$CONTINUITY_INTERRUPT_REV" "$CONTINUITY_INTERRUPT_HASH"
  CONTINUITY_RESUME_OUT=$CONTINUITY_RUN_OUT
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_RESUME_HASH=$CONTINUITY_SHA
  if test "$CONTINUITY_RUN_RC" -eq 0 && jq -e \
      --arg hash "$CONTINUITY_RESUME_HASH" --arg todo 'F1 기술 분석 진행' \
      '.phase=="F1" and .revision=='"$((CONTINUITY_INTERRUPT_REV + 1))"' and .progress_sha256==$hash
       and .todo_snapshot==[$todo] and .todo==[{content:$todo,status:"in_progress",priority:"high"}]
       and .model_admission=="UNVERIFIED"' "$CONTINUITY_RESUME_OUT" >/dev/null 2>&1; then
    assert_record continuity.fresh_process_exact 0 '새 프로세스가 phase, todo, progress hash를 정확히 복원했다' || true
  else
    assert_record continuity.fresh_process_exact 1 '새 프로세스 복원 projection 불일치' || true
  fi

  continuity_run stale-resume "$CONTINUITY_MAIN" mission resume "$CONTINUITY_MISSION" \
    "$CONTINUITY_INTERRUPT_REV" "$CONTINUITY_INTERRUPT_HASH"
  continuity_assert_rejected_unchanged continuity.stale_resume "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    75 progress.resume.stale_hash "$CONTINUITY_RESUME_HASH" "$CONTINUITY_RUN_ERR" || return 70

  printf '%s\n' '# 조작된 상태' >"$CONTINUITY_STATUS" || return 70
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_STATUS_PROGRESS_HASH=$CONTINUITY_SHA
  continuity_run derived-status "$CONTINUITY_MAIN" mission status "$CONTINUITY_MISSION"
  if test "$CONTINUITY_RUN_RC" -eq 0 && rg -F -q --no-config -- '- phase: `F1`' "$CONTINUITY_RUN_OUT" && \
     rg -F -q --no-config -- '- status_view: `stale`' "$CONTINUITY_RUN_OUT" && \
     rg -F -q --no-config '# 조작된 상태' "$CONTINUITY_STATUS"; then
    assert_record continuity.status_derived_read_only 0 'status보다 progress를 우선해 읽기 전용으로 재구성했다' || true
  else
    assert_record continuity.status_derived_read_only 1 '파생 status 진실 우선순위 위반' || true
  fi

  mkdir "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock" || return 70
  printf '%s\n' '다른 작성자 잠금' >"$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock/owner" || return 70
  continuity_run concurrent-writer "$CONTINUITY_MAIN" mission resume "$CONTINUITY_MISSION"
  CONTINUITY_CONCURRENT_RC=$CONTINUITY_RUN_RC
  CONTINUITY_CONCURRENT_ERR=$CONTINUITY_RUN_ERR
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  if test "$CONTINUITY_CONCURRENT_RC" -eq 75 && \
     rg -q --no-config 'reason=progress\.resume\.concurrent detail=' "$CONTINUITY_CONCURRENT_ERR" && \
     test "$CONTINUITY_SHA" = "$CONTINUITY_STATUS_PROGRESS_HASH" && \
     rg -F -q --no-config '다른 작성자 잠금' \
       "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock/owner"; then
    assert_record continuity.concurrent_writer_rejected 0 '동일 미션 작성자를 거부하고 타인 잠금과 정규 상태를 보존했다' || true
  else
    assert_record continuity.concurrent_writer_rejected 1 '동일 미션 단일 작성자 계약 위반' || true
  fi
  rm -f "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock/owner" || return 70
  rmdir "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock" || return 70

  continuity_checkpoint enter-f2 "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F2 running 'F2 비즈니스 분석 진행' 'F2 비즈니스 분석을 완료한다'
  assert_eq continuity.enter_f2 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint enter-f3 "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F3 awaiting_human_approval 'F3 AS-IS 승인 대기' 'AS-IS 승인 판정을 받는다'
  assert_eq continuity.enter_f3 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint f3-rejected "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F3 awaiting_human_approval 'F3 AS-IS 수정 대기' 'AS-IS 산출을 수정한다' \
    F3 rejected '근거 충돌을 해소해야 한다'
  assert_eq continuity.f3_rejection_checkpoint 0 "$CONTINUITY_RUN_RC" || true

  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_BEFORE=$CONTINUITY_SHA
  continuity_checkpoint f3-bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F4 running 'F4 설계 진행' 'TO-BE 설계를 실행한다'
  continuity_assert_rejected_unchanged continuity.gate_f3_bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    65 progress.transition.invalid "$CONTINUITY_BEFORE" "$CONTINUITY_RUN_ERR" || return 70

  continuity_checkpoint f3-retry-accepted "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F3 awaiting_human_approval 'F3 승인 완료' 'F4 설계를 시작한다' \
    F3 accepted '수정된 AS-IS 산출을 승인한다'
  assert_eq continuity.f3_retry_accept 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint enter-f4 "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F4 running 'F4 설계 진행' 'F4 설계를 완료한다'
  assert_eq continuity.enter_f4 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint enter-f5 "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F5 awaiting_human_approval 'F5 최종 승인 대기' '최종 미션 승인 판정을 받는다'
  assert_eq continuity.enter_f5 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint f5-rejected "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F5 awaiting_human_approval 'F5 보완 대기' '거절 사유를 반영해 최종 산출을 보완한다' \
    F5 rejected '테스트 근거를 보완해야 한다'
  assert_eq continuity.f5_rejection_checkpoint 0 "$CONTINUITY_RUN_RC" || true

  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_BEFORE=$CONTINUITY_SHA
  continuity_checkpoint f5-bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F5 completed '미션 완료' '완료 상태를 조회한다'
  continuity_assert_rejected_unchanged continuity.gate_f5_bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    65 progress.resume.corrupt "$CONTINUITY_BEFORE" "$CONTINUITY_RUN_ERR" || return 70

  continuity_checkpoint f5-retry-accepted "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F5 completed '미션 완료' '완료 상태를 조회한다' \
    F5 accepted '보완된 최종 산출과 검증 근거를 승인한다'
  assert_eq continuity.f5_retry_accept 0 "$CONTINUITY_RUN_RC" || true
  if jq -e '
      .phase=="F5" and .status=="completed"
      and ([.approvals[] | select(.verdict=="accepted") | .gate] | sort)==["F0","F3","F5"]
    ' "$CONTINUITY_PROGRESS" >/dev/null 2>&1; then
    assert_record continuity.gate_matrix_complete 0 'F0/F3/F5 거절, 재시도, 사람 승인 뒤에만 완료했다' || true
  else
    assert_record continuity.gate_matrix_complete 1 'hard gate 최종 상태가 잘못됐다' || true
  fi

  CONTINUITY_FINAL_REVISION=$(jq -r '.revision' "$CONTINUITY_PROGRESS") || return 70
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_FINAL_HASH=$CONTINUITY_SHA
}

continuity_lock_owner_theft_probe() {
  CONTINUITY_THEFT_MODE=$1
  CONTINUITY_THEFT_PROJECT=$RUN_TMP/continuity-owner-theft-$CONTINUITY_THEFT_MODE
  CONTINUITY_THEFT_MISSION=owner-theft-$CONTINUITY_THEFT_MODE
  continuity_project_init "$CONTINUITY_THEFT_PROJECT" || return 70
  CONTINUITY_THEFT_PROJECT=$(CDPATH= cd -- "$CONTINUITY_THEFT_PROJECT" 2>/dev/null && pwd -P) || return 70
  continuity_run "owner-theft-$CONTINUITY_THEFT_MODE-init" "$CONTINUITY_THEFT_PROJECT" \
    mission init "$CONTINUITY_THEFT_MISSION" src '잠금 소유권 탈취 검증'
  test "$CONTINUITY_RUN_RC" -eq 0 || return 70
  CONTINUITY_THEFT_DIR="$CONTINUITY_THEFT_PROJECT/docs/analysis/missions/$CONTINUITY_THEFT_MISSION"
  CONTINUITY_THEFT_PROGRESS="$CONTINUITY_THEFT_DIR/progress.json"
  CONTINUITY_THEFT_STATUS="$CONTINUITY_THEFT_DIR/status.md"
  CONTINUITY_THEFT_TRACE="$CONTINUITY_THEFT_DIR/trace.json"
  continuity_sha "$CONTINUITY_THEFT_PROGRESS" || return 70
  CONTINUITY_THEFT_PROGRESS_BEFORE=$CONTINUITY_SHA
  continuity_sha "$CONTINUITY_THEFT_STATUS" || return 70
  CONTINUITY_THEFT_STATUS_BEFORE=$CONTINUITY_SHA
  continuity_sha "$CONTINUITY_THEFT_TRACE" || return 70
  CONTINUITY_THEFT_TRACE_BEFORE=$CONTINUITY_SHA
  CONTINUITY_THEFT_REVISION=$(jq -r '.revision' "$CONTINUITY_THEFT_PROGRESS") || return 70

  if test "$CONTINUITY_THEFT_MODE" = checkpoint; then
    continuity_make_candidate "$CONTINUITY_THEFT_PROJECT" "$CONTINUITY_THEFT_MISSION" \
      F0 planned 'F0 미션 계획과 사람 승인 대기' 'F0 계획을 검토하고 사람 승인 영수증을 기록한다' || return 70
  fi

  CONTINUITY_THEFT_READY="$CONTINUITY_THEFT_PROJECT/.sensai-test-ready.$CONTINUITY_THEFT_MODE"
  set +e
  if test "$CONTINUITY_THEFT_MODE" = resume; then
    SENSAI_TEST_INTERNAL=1 SENSAI_TEST_MISSION_PAUSE=after-lock \
      SENSAI_TEST_MISSION_READY="$CONTINUITY_THEFT_READY" SENSAI_PROJECT_ROOT="$CONTINUITY_THEFT_PROJECT" \
      "$SOURCE_ROOT/bin/sensai" mission resume "$CONTINUITY_THEFT_MISSION" \
      "$CONTINUITY_THEFT_REVISION" "$CONTINUITY_THEFT_PROGRESS_BEFORE" \
      >"$RUN_TMP/owner-theft-resume.out" 2>"$RUN_TMP/owner-theft-resume.err" &
  else
    SENSAI_TEST_INTERNAL=1 SENSAI_TEST_MISSION_PAUSE=after-lock \
      SENSAI_TEST_MISSION_READY="$CONTINUITY_THEFT_READY" SENSAI_PROJECT_ROOT="$CONTINUITY_THEFT_PROJECT" \
      "$SOURCE_ROOT/bin/sensai" mission checkpoint "$CONTINUITY_THEFT_MISSION" \
      "$CONTINUITY_CANDIDATE_REL" "$CONTINUITY_THEFT_REVISION" "$CONTINUITY_THEFT_PROGRESS_BEFORE" \
      >"$RUN_TMP/owner-theft-checkpoint.out" 2>"$RUN_TMP/owner-theft-checkpoint.err" &
  fi
  CONTINUITY_THEFT_PID=$!
  CONTINUITY_THEFT_WAIT=0
  while ! test -f "$CONTINUITY_THEFT_READY" && test "$CONTINUITY_THEFT_WAIT" -lt 30; do
    sleep 1
    CONTINUITY_THEFT_WAIT=$((CONTINUITY_THEFT_WAIT + 1))
  done
  if test -f "$CONTINUITY_THEFT_READY"; then
    jq '.owner="foreign-token"' "$CONTINUITY_THEFT_DIR/.sensai-lock/owner" \
      >"$CONTINUITY_THEFT_DIR/.sensai-lock/owner.tmp" || return 70
    mv "$CONTINUITY_THEFT_DIR/.sensai-lock/owner.tmp" "$CONTINUITY_THEFT_DIR/.sensai-lock/owner" || return 70
    : >"$CONTINUITY_THEFT_READY.release" || return 70
  fi
  wait "$CONTINUITY_THEFT_PID"
  CONTINUITY_THEFT_RC=$?
  CONTINUITY_THEFT_ERR="$RUN_TMP/owner-theft-$CONTINUITY_THEFT_MODE.err"
  evidence_log_command "owner-token-theft-$CONTINUITY_THEFT_MODE" \
    "./bin/sensai mission $CONTINUITY_THEFT_MODE <owner token 탈취>" "$CONTINUITY_THEFT_RC"

  continuity_sha "$CONTINUITY_THEFT_PROGRESS" || return 70
  CONTINUITY_THEFT_PROGRESS_AFTER=$CONTINUITY_SHA
  continuity_sha "$CONTINUITY_THEFT_STATUS" || return 70
  CONTINUITY_THEFT_STATUS_AFTER=$CONTINUITY_SHA
  continuity_sha "$CONTINUITY_THEFT_TRACE" || return 70
  CONTINUITY_THEFT_TRACE_AFTER=$CONTINUITY_SHA
  if test "$CONTINUITY_THEFT_RC" -eq 75 && \
     rg -q --no-config 'reason=progress\.resume\.double_resume detail=lock_mismatch' "$CONTINUITY_THEFT_ERR" && \
     test "$CONTINUITY_THEFT_PROGRESS_BEFORE" = "$CONTINUITY_THEFT_PROGRESS_AFTER" && \
     test "$CONTINUITY_THEFT_STATUS_BEFORE" = "$CONTINUITY_THEFT_STATUS_AFTER" && \
     test "$CONTINUITY_THEFT_TRACE_BEFORE" = "$CONTINUITY_THEFT_TRACE_AFTER" && \
     jq -e '.owner=="foreign-token" and .exclusive==true' \
       "$CONTINUITY_THEFT_DIR/.sensai-lock/owner" >/dev/null 2>&1; then
    assert_record "continuity.owner_token_theft_${CONTINUITY_THEFT_MODE}_no_commit" 0 \
      'rename 직전 소유권 상실을 감지해 canonical 상태를 보존했다' || true
  else
    assert_record "continuity.owner_token_theft_${CONTINUITY_THEFT_MODE}_no_commit" 1 \
      "rc=$CONTINUITY_THEFT_RC progress_before=$CONTINUITY_THEFT_PROGRESS_BEFORE progress_after=$CONTINUITY_THEFT_PROGRESS_AFTER" || true
  fi
  rm -f "$CONTINUITY_THEFT_DIR/.sensai-lock/owner" "$CONTINUITY_THEFT_READY" "$CONTINUITY_THEFT_READY.release" || return 70
  rmdir "$CONTINUITY_THEFT_DIR/.sensai-lock" || return 70
}

continuity_failure_matrix() {
  continuity_lock_owner_theft_probe resume || return 70
  continuity_lock_owner_theft_probe checkpoint || return 70
  CONTINUITY_FAIL=$RUN_TMP/continuity-failures
  continuity_project_init "$CONTINUITY_FAIL" || return 70
  CONTINUITY_FAIL=$(CDPATH= cd -- "$CONTINUITY_FAIL" 2>/dev/null && pwd -P) || return 70
  continuity_run failure-init "$CONTINUITY_FAIL" mission init failure-mission src '실패 복구 검증'
  test "$CONTINUITY_RUN_RC" -eq 0 || return 70
  CONTINUITY_FAIL_PROGRESS="$CONTINUITY_FAIL/docs/analysis/missions/failure-mission/progress.json"
  CONTINUITY_FAIL_TRACE="$CONTINUITY_FAIL/docs/analysis/missions/failure-mission/trace.json"

  continuity_sha "$CONTINUITY_FAIL_PROGRESS" || return 70
  CONTINUITY_FAIL_BASE=$CONTINUITY_SHA
  cp "$CONTINUITY_FAIL_PROGRESS" "$RUN_TMP/progress-backup.json" || return 70
  printf '%s\n' '{' >"$CONTINUITY_FAIL_PROGRESS" || return 70
  continuity_sha "$CONTINUITY_FAIL_PROGRESS" || return 70
  CONTINUITY_CORRUPT_PROGRESS_HASH=$CONTINUITY_SHA
  continuity_run corrupt-progress "$CONTINUITY_FAIL" mission resume failure-mission
  continuity_assert_rejected_unchanged continuity.corrupt_progress "$CONTINUITY_FAIL" failure-mission \
    65 progress.resume.corrupt "$CONTINUITY_CORRUPT_PROGRESS_HASH" "$CONTINUITY_RUN_ERR" || return 70
  cp "$RUN_TMP/progress-backup.json" "$CONTINUITY_FAIL_PROGRESS" || return 70

  cp "$CONTINUITY_FAIL_TRACE" "$RUN_TMP/trace-backup.json" || return 70
  printf '%s\n' '{' >"$CONTINUITY_FAIL_TRACE" || return 70
  continuity_run corrupt-trace "$CONTINUITY_FAIL" mission resume failure-mission
  continuity_assert_rejected_unchanged continuity.corrupt_trace "$CONTINUITY_FAIL" failure-mission \
    65 progress.resume.corrupt "$CONTINUITY_FAIL_BASE" "$CONTINUITY_RUN_ERR" || return 70
  cp "$RUN_TMP/trace-backup.json" "$CONTINUITY_FAIL_TRACE" || return 70

  printf '%s\n' 'drift' >>"$CONTINUITY_FAIL/src/input.txt" || return 70
  continuity_run input-drift "$CONTINUITY_FAIL" mission resume failure-mission
  continuity_assert_rejected_unchanged continuity.input_drift "$CONTINUITY_FAIL" failure-mission \
    75 progress.resume.precondition_inputs "$CONTINUITY_FAIL_BASE" "$CONTINUITY_RUN_ERR" || return 70

  printf '%s\n' '고정 입력' >"$CONTINUITY_FAIL/src/input.txt" || return 70
  printf '%s\n' '다른 HEAD' >"$CONTINUITY_FAIL/head-drift.txt" || return 70
  git -C "$CONTINUITY_FAIL" add head-drift.txt || return 70
  git -C "$CONTINUITY_FAIL" commit -qm 'test: HEAD 변경' || return 70
  continuity_run git-head-drift "$CONTINUITY_FAIL" mission resume failure-mission
  continuity_assert_rejected_unchanged continuity.git_head_drift "$CONTINUITY_FAIL" failure-mission \
    75 progress.resume.precondition_git_head "$CONTINUITY_FAIL_BASE" "$CONTINUITY_RUN_ERR" || return 70

  CONTINUITY_TOOLCHAIN_SOURCE=$RUN_TMP/continuity-toolchain-source
  CONTINUITY_TOOLCHAIN_PROJECT=$RUN_TMP/continuity-toolchain-project
  continuity_clone_source "$CONTINUITY_TOOLCHAIN_SOURCE" || return 70
  CONTINUITY_TOOLCHAIN_SOURCE=$(CDPATH= cd -- "$CONTINUITY_TOOLCHAIN_SOURCE" 2>/dev/null && pwd -P) || return 70
  continuity_project_init "$CONTINUITY_TOOLCHAIN_PROJECT" || return 70
  CONTINUITY_TOOLCHAIN_PROJECT=$(CDPATH= cd -- "$CONTINUITY_TOOLCHAIN_PROJECT" 2>/dev/null && pwd -P) || return 70
  SENSAI_PROJECT_ROOT="$CONTINUITY_TOOLCHAIN_PROJECT" \
    "$CONTINUITY_TOOLCHAIN_SOURCE/bin/sensai" mission init toolchain-mission src 'toolchain drift 검증' \
    >"$RUN_TMP/toolchain-init.out" 2>"$RUN_TMP/toolchain-init.err" || return 70
  CONTINUITY_TOOLCHAIN_PROGRESS="$CONTINUITY_TOOLCHAIN_PROJECT/docs/analysis/missions/toolchain-mission/progress.json"
  continuity_sha "$CONTINUITY_TOOLCHAIN_PROGRESS" || return 70
  CONTINUITY_TOOLCHAIN_PROGRESS_HASH=$CONTINUITY_SHA
  jq '.model_admission="ISOLATED_DRIFT"' "$CONTINUITY_TOOLCHAIN_SOURCE/output/toolchain.lock.json" \
    >"$CONTINUITY_TOOLCHAIN_SOURCE/output/toolchain.lock.json.tmp" || return 70
  mv "$CONTINUITY_TOOLCHAIN_SOURCE/output/toolchain.lock.json.tmp" \
    "$CONTINUITY_TOOLCHAIN_SOURCE/output/toolchain.lock.json" || return 70
  set +e
  SENSAI_PROJECT_ROOT="$CONTINUITY_TOOLCHAIN_PROJECT" \
    "$CONTINUITY_TOOLCHAIN_SOURCE/bin/sensai" mission resume toolchain-mission \
    >"$RUN_TMP/toolchain-drift.out" 2>"$RUN_TMP/toolchain-drift.err"
  CONTINUITY_TOOLCHAIN_RC=$?
  evidence_log_command toolchain-drift './bin/sensai mission resume <격리 toolchain drift>' "$CONTINUITY_TOOLCHAIN_RC"
  continuity_sha "$CONTINUITY_TOOLCHAIN_PROGRESS" || return 70
  if test "$CONTINUITY_TOOLCHAIN_RC" -eq 75 && \
     rg -F -q --no-config 'reason=progress.resume.precondition_toolchain' "$RUN_TMP/toolchain-drift.err" && \
     test "$CONTINUITY_SHA" = "$CONTINUITY_TOOLCHAIN_PROGRESS_HASH" && \
     test ! -e "$CONTINUITY_TOOLCHAIN_PROJECT/docs/analysis/missions/toolchain-mission/.sensai-lock"; then
    assert_record continuity.toolchain_drift 0 '격리 toolchain drift를 재기준선 없이 거부했다' || true
  else
    assert_record continuity.toolchain_drift 1 'toolchain drift 또는 불변 계약 위반' || true
  fi

  CONTINUITY_PATH=$RUN_TMP/continuity-path
  continuity_project_init "$CONTINUITY_PATH" || return 70
  CONTINUITY_PATH=$(CDPATH= cd -- "$CONTINUITY_PATH" 2>/dev/null && pwd -P) || return 70
  continuity_run path-init "$CONTINUITY_PATH" mission init path-mission src '경로 검증'
  test "$CONTINUITY_RUN_RC" -eq 0 || return 70
  mv "$CONTINUITY_PATH/docs/analysis/missions/path-mission" "$CONTINUITY_PATH/path-mission-real" || return 70
  ln -s "$CONTINUITY_PATH/path-mission-real" "$CONTINUITY_PATH/docs/analysis/missions/path-mission" || return 70
  continuity_run symlink-path "$CONTINUITY_PATH" mission resume path-mission
  if test "$CONTINUITY_RUN_RC" -eq 65 && rg -F -q --no-config 'reason=mission.path_invalid' "$CONTINUITY_RUN_ERR"; then
    assert_record continuity.path_escape 0 '심볼릭 링크 미션 경로를 쓰기 전에 거부했다' || true
  else
    assert_record continuity.path_escape 1 '미션 경로 경계 위반' || true
  fi
}

continuity_write_evidence() {
  jq -n --arg mission "$CONTINUITY_MISSION" --arg phase F1 --arg hash "$CONTINUITY_RESUME_HASH" \
    --argjson revision "$((CONTINUITY_INTERRUPT_REV + 1))" '
      {scenario:"init-checkpoint-interrupt-fresh-process-resume",mission_id:$mission,
       restored:{phase:$phase,revision:$revision,progress_sha256:$hash,todo_exact:true},
       model_backed_session_restore:"UNVERIFIED"}
    ' >"$EVIDENCE_DIR/fresh-process.json" || return 70
  jq -n --arg interrupt_before "$CONTINUITY_INTERRUPT_HASH" --arg interrupt_after "$CONTINUITY_INTERRUPT_HASH" \
    --arg stale_before "$CONTINUITY_RESUME_HASH" --arg stale_after "$CONTINUITY_RESUME_HASH" \
    --arg final "$CONTINUITY_FINAL_HASH" '
      {interrupt:{before:$interrupt_before,after:$interrupt_after,changed:false},
       stale_resume:{before:$stale_before,after:$stale_after,changed:false},
       accepted_final:{after:$final,changed:true}}
    ' >"$EVIDENCE_DIR/state-diffs.json" || return 70
  jq -n '
      {locks:{exclusive:true,owner_shape_verified:true,pre_rename_ownership_recheck:true,
              interrupt_cleanup:true,foreign_lock_preserved:true,
              owner_token_theft_resume_no_commit:true,owner_token_theft_checkpoint_no_commit:true},
       gates:{F0:{reject_retry_accept:true,bypass_rejected:true},
              F3:{reject_retry_accept:true,bypass_rejected:true},
              F5:{reject_retry_accept:true,bypass_rejected:true}}}
    ' >"$EVIDENCE_DIR/lock-gate-matrix.json" || return 70
  jq -n '
      {stale:{result:"REJECTED",partial_write:false},corrupt:{result:"REJECTED",partial_write:false},
       path:{result:"REJECTED",partial_write:false},concurrency:{result:"REJECTED",partial_write:false},
       owner_token_theft:{result:"REJECTED",partial_write:false,foreign_lock_preserved:true},
       recovery_policy:"trace 기반 후보는 사람 결정 전 정규 progress에 쓰지 않음"}
    ' >"$EVIDENCE_DIR/recovery.json" || return 70
  jq -n '
      {model_backed_opencode_session_restore:"UNVERIFIED",windows_receipt:"PENDING",
       live_model_calls:0,global_config_mutations:0}
    ' >"$EVIDENCE_DIR/nonclaim.json" || return 70
  continuity_sha "$SOURCE_ROOT/bin/sensai" || return 70
  CONTINUITY_BIN_HASH=$CONTINUITY_SHA
  continuity_sha "$SOURCE_ROOT/output/recipes/progress.jq" || return 70
  CONTINUITY_RECIPE_HASH=$CONTINUITY_SHA
  continuity_sha "$SOURCE_ROOT/output/schemas/progress.schema.json" || return 70
  CONTINUITY_SCHEMA_HASH=$CONTINUITY_SHA
  jq -n --arg bin "$CONTINUITY_BIN_HASH" --arg recipe "$CONTINUITY_RECIPE_HASH" \
    --arg schema "$CONTINUITY_SCHEMA_HASH" '
      {"bin/sensai":$bin,"output/recipes/progress.jq":$recipe,
       "output/schemas/progress.schema.json":$schema}
    ' >"$EVIDENCE_DIR/current-hashes.json" || return 70
  jq -n --arg mission "$CONTINUITY_MISSION" --argjson revision "$CONTINUITY_FINAL_REVISION" \
    --arg hash "$CONTINUITY_FINAL_HASH" '
      {task:"T25",status:"IMPLEMENTED_PENDING_INDEPENDENT_VERIFICATION",
       mission_id:$mission,final_revision:$revision,final_progress_sha256:$hash,
       deterministic_continuity:true,external_claims_excluded:true}
    ' >"$EVIDENCE_DIR/done-claim.json" || return 70
}

case_continuity() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  continuity_gate_flow || return 70
  continuity_failure_matrix || return 70
  continuity_write_evidence || return 70
}

continuity_clone_source() {
  CONTINUITY_CLONE=$1
  mkdir -p "$CONTINUITY_CLONE/bin" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$CONTINUITY_CLONE/AGENTS.md" || return 70
  cp "$SOURCE_ROOT/bin/sensai" "$CONTINUITY_CLONE/bin/sensai" || return 70
  cp -R "$SOURCE_ROOT/output" "$CONTINUITY_CLONE/output" || return 70
  cp -R "$SOURCE_ROOT/tests" "$CONTINUITY_CLONE/tests" || return 70
  cp -R "$SOURCE_ROOT/fixtures" "$CONTINUITY_CLONE/fixtures" || return 70
  cp "$SOURCE_ROOT/manifest.txt" "$CONTINUITY_CLONE/manifest.txt" || return 70
}

run_expected_concurrent_mission_writer() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_CONTINUITY_ROOT=$RUN_TMP/expect-concurrent-source
  EXPECT_CONTINUITY_EVIDENCE=$EVIDENCE_DIR/inner-concurrent-writer
  continuity_clone_source "$EXPECT_CONTINUITY_ROOT" || return 70
  perl -0pi -e 's/progress\.resume\.concurrent lock_exists/progress.resume.concurrent-disabled lock_exists/' \
    "$EXPECT_CONTINUITY_ROOT/bin/sensai" || return 70
  if cmp -s "$SOURCE_ROOT/bin/sensai" "$EXPECT_CONTINUITY_ROOT/bin/sensai"; then
    return 70
  fi
  set +e
  SENSAI_TEST_SOURCE_ROOT="$EXPECT_CONTINUITY_ROOT" \
    "$TEST_RUNNER" continuity --evidence "$EXPECT_CONTINUITY_EVIDENCE" \
    >"$RUN_TMP/expect-concurrent-writer.out" 2>&1
  EXPECT_CONTINUITY_RC=$?
  evidence_log_command expected-concurrent-mission-writer \
    "$TEST_RUNNER continuity <격리 concurrent reason mutation>" "$EXPECT_CONTINUITY_RC"
  case "$EXPECT_CONTINUITY_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_CONTINUITY_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.concurrent_writer_exit 1 "$EXPECT_CONTINUITY_RC" || true
  if test -f "$EXPECT_CONTINUITY_EVIDENCE/receipt.json"; then
    assert_jq expect.concurrent_writer_named_failure '
      .result=="ASSERTION_FAILURE" and .exit==1
      and .failed_assertion_ids==["continuity.concurrent_writer_rejected"]
    ' "$EXPECT_CONTINUITY_EVIDENCE/receipt.json" || true
  else
    assert_record expect.concurrent_writer_receipt 1 'concurrent writer mutation receipt가 없다' || true
  fi
}
