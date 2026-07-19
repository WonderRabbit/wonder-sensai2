#!/bin/sh

progress_append_error() {
  PROGRESS_APPEND_FILE=$1
  PROGRESS_APPEND_ID=$2
  PROGRESS_APPEND_TMP="$PROGRESS_APPEND_FILE.tmp"
  jq --arg id "$PROGRESS_APPEND_ID" '. + [$id] | unique' \
    "$PROGRESS_APPEND_FILE" >"$PROGRESS_APPEND_TMP" || return 70
  mv "$PROGRESS_APPEND_TMP" "$PROGRESS_APPEND_FILE" || return 70
}

progress_check_filesystem_contract() {
  PROGRESS_FS_INPUT=$1
  PROGRESS_FS_ERRORS=$2
  PROGRESS_FS_ROOT=${3:-}
  PROGRESS_FS_APPROVAL_COUNT=$(jq '.approvals | length' "$PROGRESS_FS_INPUT") || return 70

  if test -z "$PROGRESS_FS_ROOT"; then
    if test "$PROGRESS_FS_APPROVAL_COUNT" -gt 0; then
      progress_append_error "$PROGRESS_FS_ERRORS" progress.approval_receipt || return 70
    fi
    return 0
  fi

  case "$PROGRESS_FS_ROOT" in
    /*) ;;
    *) return 70 ;;
  esac
  if ! test -d "$PROGRESS_FS_ROOT" || test -L "$PROGRESS_FS_ROOT"; then
    return 70
  fi

  PROGRESS_FS_MISSION_ROOT=$(jq -r '.mission_root' "$PROGRESS_FS_INPUT") || return 70
  PROGRESS_FS_MISSION_ID=$(jq -r '.mission_id' "$PROGRESS_FS_INPUT") || return 70
  for PROGRESS_FS_COMPONENT in \
    "$PROGRESS_FS_ROOT/docs" \
    "$PROGRESS_FS_ROOT/docs/analysis" \
    "$PROGRESS_FS_ROOT/docs/analysis/missions" \
    "$PROGRESS_FS_ROOT/docs/analysis/missions/$PROGRESS_FS_MISSION_ID"
  do
    if test -L "$PROGRESS_FS_COMPONENT"; then
      progress_append_error "$PROGRESS_FS_ERRORS" progress.mission_symlink || return 70
      break
    fi
  done

  if ! jq -e --arg root "docs/analysis/missions/$PROGRESS_FS_MISSION_ID/" \
    '.mission_root == $root and all(.approvals[]?; .receipt_path | startswith($root + "approvals/"))' \
    "$PROGRESS_FS_INPUT" >/dev/null 2>&1; then
    return 0
  fi

  while IFS="$(printf '\t')" read -r PROGRESS_FS_RECEIPT PROGRESS_FS_EXPECTED_HASH; do
    test -n "$PROGRESS_FS_RECEIPT" || continue
    PROGRESS_FS_RECEIPT_ABS="$PROGRESS_FS_ROOT/$PROGRESS_FS_RECEIPT"
    PROGRESS_FS_RECEIPT_DIR=${PROGRESS_FS_RECEIPT_ABS%/*}
    if ! test -f "$PROGRESS_FS_RECEIPT_ABS" || test -L "$PROGRESS_FS_RECEIPT_ABS" || test -L "$PROGRESS_FS_RECEIPT_DIR"; then
      progress_append_error "$PROGRESS_FS_ERRORS" progress.approval_receipt || return 70
      continue
    fi
    tooling_sha256_file "$PROGRESS_FS_RECEIPT_ABS" || return 70
    if test "$TOOLING_SHA256" != "$PROGRESS_FS_EXPECTED_HASH"; then
      progress_append_error "$PROGRESS_FS_ERRORS" progress.approval_receipt || return 70
    fi
  done <<EOF
$(jq -r '.approvals[]? | [.receipt_path, .receipt_sha256] | @tsv' "$PROGRESS_FS_INPUT")
EOF
}

progress_run_validator() {
  PROGRESS_CURRENT=$1
  PROGRESS_OUTPUT=$2
  PROGRESS_PREVIOUS=${3:-}
  PROGRESS_VALIDATOR_PROJECT_ROOT=${4:-}
  PROGRESS_VALIDATOR="$SOURCE_ROOT/tests/validators/progress-schema-parity.jq"

  set +e
  if test -n "$PROGRESS_PREVIOUS"; then
    tooling_sha256_file "$PROGRESS_PREVIOUS" || return 70
    PROGRESS_PREVIOUS_HASH=$TOOLING_SHA256
    jq -n \
      --slurpfile previous "$PROGRESS_PREVIOUS" \
      --slurpfile current "$PROGRESS_CURRENT" \
      --arg previous_sha256 "$PROGRESS_PREVIOUS_HASH" \
      '{previous:$previous[0],current:$current[0],previous_sha256:$previous_sha256}' |
      jq -f "$PROGRESS_VALIDATOR" >"$PROGRESS_OUTPUT" 2>"$PROGRESS_OUTPUT.err"
  else
    jq -f "$PROGRESS_VALIDATOR" "$PROGRESS_CURRENT" >"$PROGRESS_OUTPUT" 2>"$PROGRESS_OUTPUT.err"
  fi
  PROGRESS_RC=$?
  evidence_log_command progress-schema-parity "jq -f tests/validators/progress-schema-parity.jq <progress-or-transition>" "$PROGRESS_RC"
  test "$PROGRESS_RC" -eq 0 || return 70
  jq -e 'type == "array" and all(.[]; type == "string")' "$PROGRESS_OUTPUT" >/dev/null 2>&1 || return 70

  progress_check_filesystem_contract "$PROGRESS_CURRENT" "$PROGRESS_OUTPUT" "$PROGRESS_VALIDATOR_PROJECT_ROOT" || return 70
  return 0
}

progress_assert_valid() {
  PROGRESS_VALID_ID=$1
  PROGRESS_VALID_FILE=$2
  PROGRESS_VALID_ROOT=${3:-}
  CASE_TOTAL=$((CASE_TOTAL + 1))
  PROGRESS_VALID_ERRORS="$RUN_TMP/$PROGRESS_VALID_ID-errors.json"
  progress_run_validator "$PROGRESS_VALID_FILE" "$PROGRESS_VALID_ERRORS" '' "$PROGRESS_VALID_ROOT" || return 70
  assert_jq "$PROGRESS_VALID_ID" 'length == 0' "$PROGRESS_VALID_ERRORS" || true
}

progress_assert_invalid() {
  PROGRESS_INVALID_ID=$1
  PROGRESS_INVALID_FILE=$2
  PROGRESS_EXPECTED_ID=$3
  PROGRESS_INVALID_ROOT=${4:-}
  CASE_TOTAL=$((CASE_TOTAL + 1))
  PROGRESS_INVALID_ERRORS="$RUN_TMP/$PROGRESS_INVALID_ID-errors.json"
  progress_run_validator "$PROGRESS_INVALID_FILE" "$PROGRESS_INVALID_ERRORS" '' "$PROGRESS_INVALID_ROOT" || return 70
  assert_jq "$PROGRESS_INVALID_ID" ". | index(\"$PROGRESS_EXPECTED_ID\") != null" "$PROGRESS_INVALID_ERRORS" || true
}

progress_assert_transition_valid() {
  PROGRESS_TRANSITION_ID=$1
  PROGRESS_TRANSITION_PREVIOUS=$2
  PROGRESS_TRANSITION_CURRENT=$3
  PROGRESS_TRANSITION_ROOT=${4:-}
  CASE_TOTAL=$((CASE_TOTAL + 1))
  PROGRESS_TRANSITION_ERRORS="$RUN_TMP/$PROGRESS_TRANSITION_ID-errors.json"
  progress_run_validator "$PROGRESS_TRANSITION_CURRENT" "$PROGRESS_TRANSITION_ERRORS" \
    "$PROGRESS_TRANSITION_PREVIOUS" "$PROGRESS_TRANSITION_ROOT" || return 70
  assert_jq "$PROGRESS_TRANSITION_ID" 'length == 0' "$PROGRESS_TRANSITION_ERRORS" || true
}

progress_assert_transition_invalid() {
  PROGRESS_TRANSITION_INVALID_ID=$1
  PROGRESS_TRANSITION_INVALID_PREVIOUS=$2
  PROGRESS_TRANSITION_INVALID_CURRENT=$3
  PROGRESS_TRANSITION_EXPECTED_ID=$4
  PROGRESS_TRANSITION_INVALID_ROOT=${5:-}
  CASE_TOTAL=$((CASE_TOTAL + 1))
  PROGRESS_TRANSITION_INVALID_ERRORS="$RUN_TMP/$PROGRESS_TRANSITION_INVALID_ID-errors.json"
  progress_run_validator "$PROGRESS_TRANSITION_INVALID_CURRENT" "$PROGRESS_TRANSITION_INVALID_ERRORS" \
    "$PROGRESS_TRANSITION_INVALID_PREVIOUS" "$PROGRESS_TRANSITION_INVALID_ROOT" || return 70
  assert_jq "$PROGRESS_TRANSITION_INVALID_ID" ". | index(\"$PROGRESS_TRANSITION_EXPECTED_ID\") != null" \
    "$PROGRESS_TRANSITION_INVALID_ERRORS" || true
}

progress_make_transition() {
  PROGRESS_MAKE_PREVIOUS=$1
  PROGRESS_MAKE_CURRENT=$2
  PROGRESS_MAKE_PHASE=$3
  PROGRESS_MAKE_STATUS=$4
  PROGRESS_MAKE_REVISION=$5
  PROGRESS_MAKE_UPDATED_AT=$6
  tooling_sha256_file "$PROGRESS_MAKE_PREVIOUS" || return 70
  jq \
    --arg phase "$PROGRESS_MAKE_PHASE" \
    --arg status "$PROGRESS_MAKE_STATUS" \
    --argjson revision "$PROGRESS_MAKE_REVISION" \
    --arg updated_at "$PROGRESS_MAKE_UPDATED_AT" \
    --arg previous_progress "$TOOLING_SHA256" \
    '.phase = $phase |
     .status = $status |
     .revision = $revision |
     .updated_at = $updated_at |
     .precondition_fingerprints.previous_progress = $previous_progress' \
    "$PROGRESS_MAKE_PREVIOUS" >"$PROGRESS_MAKE_CURRENT" || return 70
}

progress_add_approval() {
  PROGRESS_APPROVAL_FILE=$1
  PROGRESS_APPROVAL_ROOT=$2
  PROGRESS_APPROVAL_GATE=$3
  PROGRESS_APPROVAL_RECORDED_AT=$4
  PROGRESS_APPROVAL_RELATIVE="docs/analysis/missions/fixture-mission/approvals/$PROGRESS_APPROVAL_GATE-approval.json"
  PROGRESS_APPROVAL_ABSOLUTE="$PROGRESS_APPROVAL_ROOT/$PROGRESS_APPROVAL_RELATIVE"
  mkdir -p "${PROGRESS_APPROVAL_ABSOLUTE%/*}" || return 70
  printf '{"gate":"%s","verdict":"accepted","source":"elicited"}\n' "$PROGRESS_APPROVAL_GATE" \
    >"$PROGRESS_APPROVAL_ABSOLUTE" || return 70
  tooling_sha256_file "$PROGRESS_APPROVAL_ABSOLUTE" || return 70
  PROGRESS_APPROVAL_HASH=$TOOLING_SHA256
  PROGRESS_APPROVAL_TMP="$PROGRESS_APPROVAL_FILE.tmp"
  jq \
    --arg gate "$PROGRESS_APPROVAL_GATE" \
    --arg receipt_path "$PROGRESS_APPROVAL_RELATIVE" \
    --arg receipt_sha256 "$PROGRESS_APPROVAL_HASH" \
    --arg recorded_at "$PROGRESS_APPROVAL_RECORDED_AT" \
    '.approvals += [{
      gate:$gate,
      verdict:"accepted",
      reason:"사용자 명시 승인",
      actor_role:"human",
      source:"elicited",
      receipt_path:$receipt_path,
      receipt_sha256:$receipt_sha256,
      recorded_at:$recorded_at
    }]' "$PROGRESS_APPROVAL_FILE" >"$PROGRESS_APPROVAL_TMP" || return 70
  mv "$PROGRESS_APPROVAL_TMP" "$PROGRESS_APPROVAL_FILE" || return 70
}

progress_check_schema_contract() {
  PROGRESS_SCHEMA="$SOURCE_ROOT/output/schemas/progress.schema.json"
  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_file schema.progress_file "$PROGRESS_SCHEMA" || true
  assert_file schema.progress_parity_validator "$SOURCE_ROOT/tests/validators/progress-schema-parity.jq" || true
  if ! jq empty "$PROGRESS_SCHEMA" >/dev/null 2>&1; then
    assert_record schema.progress_json 1 'progress schema JSON syntax invalid' || true
    return 0
  fi
  assert_record schema.progress_json 0 'progress schema JSON syntax valid' || true
  assert_jq schema.progress_draft '.["$schema"] == "https://json-schema.org/draft/2020-12/schema"' "$PROGRESS_SCHEMA" || true
  assert_jq schema.progress_closed '
    .additionalProperties == false and
    ([.["$defs"] | to_entries[] | select(.value.type == "object") | .value.additionalProperties] | all(. == false))
  ' "$PROGRESS_SCHEMA" || true
  assert_jq schema.progress_phases '.["$defs"].phase.enum == ["F0","F1","F2","F3","F4","F5"]' "$PROGRESS_SCHEMA" || true
  assert_jq schema.progress_statuses '.["$defs"].status.enum == ["planned","running","blocked","awaiting_human_approval","completed"]' "$PROGRESS_SCHEMA" || true
  assert_jq schema.progress_truth_priority '.["x-truth-priority"] == ["trace","progress","status","todo"]' "$PROGRESS_SCHEMA" || true
  assert_jq schema.progress_korean_metadata '
    (.title | test("[가-힣]")) and (.description | test("[가-힣]")) and (.["$comment"] | test("[가-힣]"))
  ' "$PROGRESS_SCHEMA" || true
}

case_schema_progress() {
  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test -n "${SENSAI_TEST_INTERNAL_PROGRESS_INPUT:-}"; then
    PROGRESS_INTERNAL_ERRORS="$RUN_TMP/progress-internal-errors.json"
    progress_run_validator "$SENSAI_TEST_INTERNAL_PROGRESS_INPUT" "$PROGRESS_INTERNAL_ERRORS" '' \
      "${SENSAI_TEST_INTERNAL_PROJECT_ROOT:-}" || return 70
    CASE_TOTAL=$((CASE_TOTAL + 1))
    if jq -e 'length == 0' "$PROGRESS_INTERNAL_ERRORS" >/dev/null 2>&1; then
      assert_record progress.document_valid 0 'progress document satisfies schema parity constraints' || true
      return 0
    fi
    while IFS= read -r PROGRESS_INTERNAL_ERROR_ID; do
      test -n "$PROGRESS_INTERNAL_ERROR_ID" || continue
      assert_record "$PROGRESS_INTERNAL_ERROR_ID" 1 'progress document violates schema parity constraint' || true
    done <<EOF
$(jq -r '.[]' "$PROGRESS_INTERNAL_ERRORS")
EOF
    return 0
  fi

  progress_check_schema_contract || return 70

  PROGRESS_GOLDEN="$SOURCE_ROOT/fixtures/expected/progress.json"
  progress_assert_valid schema.progress_valid_golden "$PROGRESS_GOLDEN" || return 70

  for PROGRESS_PHASE_STATUS in F0:planned F0:running F1:running F2:blocked F3:awaiting_human_approval F4:running F5:running; do
    PROGRESS_PHASE=${PROGRESS_PHASE_STATUS%%:*}
    PROGRESS_STATUS=${PROGRESS_PHASE_STATUS#*:}
    PROGRESS_STATE_FILE="$RUN_TMP/valid-$PROGRESS_PHASE-$PROGRESS_STATUS.json"
    jq --arg phase "$PROGRESS_PHASE" --arg status "$PROGRESS_STATUS" \
      '.phase = $phase | .status = $status | .approvals = []' "$PROGRESS_GOLDEN" >"$PROGRESS_STATE_FILE" || return 70
    progress_assert_valid "schema.progress_valid_${PROGRESS_PHASE}_${PROGRESS_STATUS}" "$PROGRESS_STATE_FILE" || return 70
  done

  PROGRESS_CASE_PROJECT_ROOT="$RUN_TMP/progress-project"
  mkdir -p "$PROGRESS_CASE_PROJECT_ROOT/docs/analysis/missions/fixture-mission" || return 70

  PROGRESS_T0="$RUN_TMP/transition-F0.json"
  jq '.phase="F0" | .status="awaiting_human_approval" | .revision=1 | .updated_at="2026-07-19T00:00:00Z" | .approvals=[] | del(.precondition_fingerprints.previous_progress)' \
    "$PROGRESS_GOLDEN" >"$PROGRESS_T0" || return 70
  PROGRESS_T1="$RUN_TMP/transition-F1.json"
  progress_make_transition "$PROGRESS_T0" "$PROGRESS_T1" F1 running 2 2026-07-19T00:01:00Z || return 70
  progress_add_approval "$PROGRESS_T1" "$PROGRESS_CASE_PROJECT_ROOT" F0 2026-07-19T00:00:30Z || return 70
  progress_assert_transition_valid schema.progress_transition_F0_F1 "$PROGRESS_T0" "$PROGRESS_T1" "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_T2="$RUN_TMP/transition-F2.json"
  progress_make_transition "$PROGRESS_T1" "$PROGRESS_T2" F2 running 3 2026-07-19T00:02:00Z || return 70
  progress_assert_transition_valid schema.progress_transition_F1_F2 "$PROGRESS_T1" "$PROGRESS_T2" "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_T3="$RUN_TMP/transition-F3.json"
  progress_make_transition "$PROGRESS_T2" "$PROGRESS_T3" F3 awaiting_human_approval 4 2026-07-19T00:03:00Z || return 70
  progress_assert_transition_valid schema.progress_transition_F2_F3 "$PROGRESS_T2" "$PROGRESS_T3" "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_T4="$RUN_TMP/transition-F4.json"
  progress_make_transition "$PROGRESS_T3" "$PROGRESS_T4" F4 running 5 2026-07-19T00:04:00Z || return 70
  progress_add_approval "$PROGRESS_T4" "$PROGRESS_CASE_PROJECT_ROOT" F3 2026-07-19T00:03:30Z || return 70
  progress_assert_transition_valid schema.progress_transition_F3_F4 "$PROGRESS_T3" "$PROGRESS_T4" "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_T5="$RUN_TMP/transition-F5.json"
  progress_make_transition "$PROGRESS_T4" "$PROGRESS_T5" F5 running 6 2026-07-19T00:05:00Z || return 70
  progress_assert_transition_valid schema.progress_transition_F4_F5 "$PROGRESS_T4" "$PROGRESS_T5" "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_T5_DONE="$RUN_TMP/transition-F5-completed.json"
  progress_make_transition "$PROGRESS_T5" "$PROGRESS_T5_DONE" F5 completed 7 2026-07-19T00:06:00Z || return 70
  progress_add_approval "$PROGRESS_T5_DONE" "$PROGRESS_CASE_PROJECT_ROOT" F5 2026-07-19T00:05:30Z || return 70
  progress_assert_transition_valid schema.progress_transition_F5_completed "$PROGRESS_T5" "$PROGRESS_T5_DONE" "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_RESUMED="$RUN_TMP/transition-resumed.json"
  progress_make_transition "$PROGRESS_T5_DONE" "$PROGRESS_RESUMED" F5 running 8 2026-07-19T00:07:00Z || return 70
  progress_assert_transition_invalid schema.progress_terminal_immutable "$PROGRESS_T5_DONE" "$PROGRESS_RESUMED" progress.transition "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_MUTATION_PHASE="$RUN_TMP/mutation-phase.json"
  jq '.phase="F6"' "$PROGRESS_GOLDEN" >"$PROGRESS_MUTATION_PHASE" || return 70
  progress_assert_invalid schema.progress_invalid_phase "$PROGRESS_MUTATION_PHASE" progress.phase || return 70

  PROGRESS_MUTATION_STATUS="$RUN_TMP/mutation-status.json"
  jq '.status="guessed"' "$PROGRESS_GOLDEN" >"$PROGRESS_MUTATION_STATUS" || return 70
  progress_assert_invalid schema.progress_invalid_status "$PROGRESS_MUTATION_STATUS" progress.status || return 70

  PROGRESS_MUTATION_HASH="$RUN_TMP/mutation-hash.json"
  jq '.precondition_fingerprints.trace=("A" * 64)' "$PROGRESS_GOLDEN" >"$PROGRESS_MUTATION_HASH" || return 70
  progress_assert_invalid schema.progress_invalid_hash "$PROGRESS_MUTATION_HASH" progress.hash || return 70

  PROGRESS_MUTATION_PATH="$RUN_TMP/mutation-path.json"
  jq '.mission_root="docs/analysis/missions/../escape/"' "$PROGRESS_GOLDEN" >"$PROGRESS_MUTATION_PATH" || return 70
  progress_assert_invalid schema.progress_invalid_path "$PROGRESS_MUTATION_PATH" progress.path || return 70

  PROGRESS_MUTATION_GLOBAL="$RUN_TMP/mutation-global.json"
  jq '.mission_root="docs/analysis/progress.json"' "$PROGRESS_GOLDEN" >"$PROGRESS_MUTATION_GLOBAL" || return 70
  progress_assert_invalid schema.progress_global_singleton "$PROGRESS_MUTATION_GLOBAL" progress.path || return 70

  PROGRESS_MUTATION_REVISION="$RUN_TMP/mutation-revision.json"
  jq '.revision=9' "$PROGRESS_T2" >"$PROGRESS_MUTATION_REVISION" || return 70
  progress_assert_transition_invalid schema.progress_invalid_revision "$PROGRESS_T1" "$PROGRESS_MUTATION_REVISION" progress.revision "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_MUTATION_PRECONDITION="$RUN_TMP/mutation-precondition.json"
  jq '.precondition_fingerprints.previous_progress=("0" * 64)' "$PROGRESS_T2" >"$PROGRESS_MUTATION_PRECONDITION" || return 70
  progress_assert_transition_invalid schema.progress_invalid_precondition "$PROGRESS_T1" "$PROGRESS_MUTATION_PRECONDITION" progress.precondition "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_MUTATION_JUMP="$RUN_TMP/mutation-jump.json"
  progress_make_transition "$PROGRESS_T1" "$PROGRESS_MUTATION_JUMP" F4 running 3 2026-07-19T00:02:00Z || return 70
  progress_assert_transition_invalid schema.progress_invalid_transition "$PROGRESS_T1" "$PROGRESS_MUTATION_JUMP" progress.transition "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_MUTATION_HARD_GATE="$RUN_TMP/mutation-hard-gate.json"
  progress_make_transition "$PROGRESS_T3" "$PROGRESS_MUTATION_HARD_GATE" F4 running 5 2026-07-19T00:04:00Z || return 70
  progress_assert_transition_invalid schema.progress_missing_hard_gate "$PROGRESS_T3" "$PROGRESS_MUTATION_HARD_GATE" progress.hard_gate "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_MUTATION_PROVENANCE="$RUN_TMP/mutation-approval-provenance.json"
  cp "$PROGRESS_T4" "$PROGRESS_MUTATION_PROVENANCE" || return 70
  jq '.approvals[0].source="model"' "$PROGRESS_MUTATION_PROVENANCE" >"$PROGRESS_MUTATION_PROVENANCE.tmp" || return 70
  mv "$PROGRESS_MUTATION_PROVENANCE.tmp" "$PROGRESS_MUTATION_PROVENANCE" || return 70
  progress_assert_invalid schema.progress_fabricated_verdict "$PROGRESS_MUTATION_PROVENANCE" progress.approval_provenance "$PROGRESS_CASE_PROJECT_ROOT" || return 70

  PROGRESS_MISSING_RECEIPT_ROOT="$RUN_TMP/missing-receipt-project"
  mkdir -p "$PROGRESS_MISSING_RECEIPT_ROOT" || return 70
  progress_assert_invalid schema.progress_missing_receipt "$PROGRESS_T4" progress.approval_receipt "$PROGRESS_MISSING_RECEIPT_ROOT" || return 70

  PROGRESS_SYMLINK_ROOT="$RUN_TMP/symlink-project"
  PROGRESS_SYMLINK_TARGET="$RUN_TMP/symlink-target"
  mkdir -p "$PROGRESS_SYMLINK_ROOT/docs/analysis/missions" "$PROGRESS_SYMLINK_TARGET" || return 70
  ln -s "$PROGRESS_SYMLINK_TARGET" "$PROGRESS_SYMLINK_ROOT/docs/analysis/missions/fixture-mission" || return 70
  progress_assert_invalid schema.progress_symlink_mission_root "$PROGRESS_GOLDEN" progress.mission_symlink "$PROGRESS_SYMLINK_ROOT" || return 70
}

schema_progress_clone_source() {
  SCHEMA_PROGRESS_CLONE_ROOT=$1
  mkdir -p "$SCHEMA_PROGRESS_CLONE_ROOT/output/schemas" "$SCHEMA_PROGRESS_CLONE_ROOT/fixtures/expected" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$SCHEMA_PROGRESS_CLONE_ROOT/AGENTS.md" || return 70
  cp "$SOURCE_ROOT/output/schemas/progress.schema.json" "$SCHEMA_PROGRESS_CLONE_ROOT/output/schemas/progress.schema.json" || return 70
  cp -R "$SOURCE_ROOT/tests" "$SCHEMA_PROGRESS_CLONE_ROOT/tests" || return 70
  cp "$SOURCE_ROOT/fixtures/expected/progress.json" "$SCHEMA_PROGRESS_CLONE_ROOT/fixtures/expected/progress.json" || return 70
}
