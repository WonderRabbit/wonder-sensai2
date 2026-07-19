#!/bin/sh

receipt_write() {
  RECEIPT_SELECTOR=$1
  RECEIPT_EXIT=$2
  RECEIPT_RESULT=$3
  test "$EVIDENCE_READY" -eq 1 || return 70

  jq -s '.' "$EVIDENCE_DIR/assertions.jsonl" >"$RUN_TMP/assertions.json" || return 70
  jq -s '.' "$EVIDENCE_DIR/commands.jsonl" >"$RUN_TMP/commands.json" || return 70
  jq -Rsc 'split("\n") | map(select(length > 0))' "$EVIDENCE_DIR/reasons.txt" >"$RUN_TMP/reasons.json" || return 70
  if test -s "$UNTRACKED_FILE"; then
    jq -Rsc 'split("\n") | map(select(length > 0))' "$UNTRACKED_FILE" >"$RUN_TMP/untracked.json" || return 70
  else
    printf '[]\n' >"$RUN_TMP/untracked.json"
  fi
  if test -n "$ASSERT_FAILED_IDS"; then
    printf '%s\n' "$ASSERT_FAILED_IDS" | jq -Rsc 'split("\n") | map(select(length > 0))' >"$RUN_TMP/failed.json" || return 70
  else
    printf '[]\n' >"$RUN_TMP/failed.json"
  fi

  jq -n \
    --arg schema_version '1.0' \
    --arg selector "$RECEIPT_SELECTOR" \
    --arg result "$RECEIPT_RESULT" \
    --argjson exit "$RECEIPT_EXIT" \
    --arg source_root "$SOURCE_ROOT" \
    --arg digest "$SOURCE_FINGERPRINT" \
    --arg git_state "$GIT_STATE" \
    --argjson source_file_count "$SOURCE_FILE_COUNT" \
    --argjson untracked_count "$UNTRACKED_COUNT" \
    --argjson case_count "$CASE_TOTAL" \
    --argjson assertion_count "$ASSERT_TOTAL" \
    --argjson failed_assertion_count "$ASSERT_FAILED" \
    --arg agents_sha256 "$AGENTS_SHA256" \
    --slurpfile assertions "$RUN_TMP/assertions.json" \
    --slurpfile commands "$RUN_TMP/commands.json" \
    --slurpfile reasons "$RUN_TMP/reasons.json" \
    --slurpfile untracked "$RUN_TMP/untracked.json" \
    --slurpfile failed "$RUN_TMP/failed.json" \
    '{
      schema_version:$schema_version,
      selector:$selector,
      result:$result,
      exit:$exit,
      case_count:$case_count,
      assertion_count:$assertion_count,
      failed_assertion_count:$failed_assertion_count,
      failed_assertion_ids:$failed[0],
      assertions:$assertions[0],
      command_exits:$commands[0],
      reason_codes:$reasons[0],
      source:{root:$source_root,fingerprint_algorithm:"sha256-path-and-content",fingerprint:$digest,file_count:$source_file_count,git_state:$git_state,untracked_count:$untracked_count,untracked_inventory:$untracked[0]},
      invariants:{agents_sha256:$agents_sha256,commit:"N - prohibited by approved scope"}
    }' >"$EVIDENCE_DIR/receipt.json" || return 70

  jq -e \
    '.case_count >= 1 and .assertion_count >= 1 and (.command_exits | type == "array") and (.source.fingerprint | length == 64) and (.source.untracked_inventory | type == "array")' \
    "$EVIDENCE_DIR/receipt.json" >/dev/null || return 70
  return 0
}
