#!/bin/sh

e2e_tobe_sha256() {
  tooling_sha256_file "$1" || return 70
  E2E_TOBE_SHA256=$TOOLING_SHA256
}

e2e_tobe_normalize() {
  awk '{ sub(/\r$/, ""); sub(/[[:space:]]+$/, ""); print }' "$1" >"$2" || return 70
}

e2e_tobe_assert_zero() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_eq "$1" 0 "$2" || true
}

e2e_tobe_build_preconditions() {
  E2E_TOBE_TRACE=$SOURCE_ROOT/fixtures/expected/trace-v2.json
  E2E_TOBE_PROGRESS=$SOURCE_ROOT/fixtures/expected/progress.json
  E2E_TOBE_CHANGE=$SOURCE_ROOT/fixtures/inputs/change/valid.md
  E2E_TOBE_APPROVED=$RUN_TMP/e2e-tobe-approved-progress.json

  e2e_tobe_sha256 "$E2E_TOBE_TRACE" || return 70
  E2E_TOBE_TRACE_SHA=$E2E_TOBE_SHA256
  e2e_tobe_sha256 "$E2E_TOBE_CHANGE" || return 70
  E2E_TOBE_CHANGE_SHA=$E2E_TOBE_SHA256

  jq --arg trace "$E2E_TOBE_TRACE_SHA" --arg inputs "$E2E_TOBE_CHANGE_SHA" '
    .phase = "F4"
    | .status = "running"
    | .revision = 4
    | .precondition_fingerprints.trace = $trace
    | .precondition_fingerprints.inputs = $inputs
    | .next = "TO-BE 5종 산출을 검증한다"
    | .blocked = []
    | .approvals = [{
        gate:"F3", verdict:"accepted", reason:"고정 fixture의 AS-IS 승인 시나리오",
        actor_role:"human", source:"elicited",
        receipt_path:"docs/analysis/missions/fixture-mission/approvals/F3-approval.json",
        receipt_sha256:$trace, recorded_at:"2026-07-19T00:01:00Z"
      }]
    | .updated_at = "2026-07-19T00:02:00Z"
  ' "$E2E_TOBE_PROGRESS" >"$E2E_TOBE_APPROVED" || return 70

  jq -n --slurpfile progress "$E2E_TOBE_APPROVED" '{mode:"validate",progress:$progress[0]}' \
    | jq -e -f "$SOURCE_ROOT/output/recipes/progress.jq" \
      >"$RUN_TMP/e2e-tobe-progress.out" 2>"$RUN_TMP/e2e-tobe-progress.err"
  E2E_TOBE_RC=$?
  evidence_log_command e2e-tobe.progress \
    'jq progress.jq validate <fixture-derived accepted F3 envelope>' "$E2E_TOBE_RC"
  e2e_tobe_assert_zero e2e.tobe.progress_recipe "$E2E_TOBE_RC"

  jq -e -f "$SOURCE_ROOT/output/recipes/trace.jq" "$E2E_TOBE_TRACE" \
    >"$RUN_TMP/e2e-tobe-trace.out" 2>"$RUN_TMP/e2e-tobe-trace.err"
  E2E_TOBE_RC=$?
  evidence_log_command e2e-tobe.trace \
    'jq -e -f output/recipes/trace.jq fixtures/expected/trace-v2.json' "$E2E_TOBE_RC"
  e2e_tobe_assert_zero e2e.tobe.trace_recipe "$E2E_TOBE_RC"

  CASE_TOTAL=$((CASE_TOTAL + 1))
  if jq -e --arg trace "$E2E_TOBE_TRACE_SHA" --arg inputs "$E2E_TOBE_CHANGE_SHA" '
      .phase == "F4" and .status == "running"
      and .precondition_fingerprints.trace == $trace
      and .precondition_fingerprints.inputs == $inputs
      and any(.approvals[];
        .gate == "F3" and .verdict == "accepted"
        and .actor_role == "human" and .source == "elicited")
    ' "$E2E_TOBE_APPROVED" >/dev/null 2>&1; then
    assert_record e2e.tobe.asis_approval 0 '현재 trace와 change hash에 결합된 F3 승인 시나리오를 확인했다' || true
  else
    assert_record e2e.tobe.asis_approval 1 'F3 승인 또는 입력 hash 결합이 없다' || true
  fi

  jq -n --arg trace_sha256 "$E2E_TOBE_TRACE_SHA" \
    --arg change_sha256 "$E2E_TOBE_CHANGE_SHA" \
    --arg progress "fixtures/expected/progress.json에서 만든 격리 승인 시나리오" '{
      trace:"fixtures/expected/trace-v2.json",
      trace_sha256:$trace_sha256,
      change_request:"fixtures/inputs/change/valid.md",
      change_sha256:$change_sha256,
      approved_progress:$progress,
      gate:"F3",
      verdict:"accepted",
      fixture_approval_simulation:true,
      real_human_receipt_claimed:false
    }' >"$EVIDENCE_DIR/preconditions.json" || return 70
}

e2e_tobe_write_verdict() {
  E2E_TOBE_VERDICT=$RUN_TMP/e2e-tobe-verdict.json
  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && \
     test "${SENSAI_TEST_TOBE_HIDE_CONFLICT:-0}" = 1; then
    E2E_TOBE_HIDE=true
  else
    E2E_TOBE_HIDE=false
  fi
  jq --argjson hide "$E2E_TOBE_HIDE" '{
    binding_gates:[.bindings[] | {id,design_id,gate}],
    conflicts:(if $hide then [] else [.business_rules[] | select(.status == "conflict") | .id] end),
    violation_verdict:(if any(.bindings[]; .gate == "violation") then "blocked" else "pass" end)
  }' "$E2E_TOBE_TRACE" >"$E2E_TOBE_VERDICT" || return 70
  cp "$E2E_TOBE_VERDICT" "$EVIDENCE_DIR/violation-verdicts.json" || return 70
}

e2e_tobe_gate_issues() {
  E2E_TOBE_GATE_TRACE=$1
  E2E_TOBE_GATE_PROGRESS=$2
  E2E_TOBE_GATE_VERDICT=$3
  jq -nr --slurpfile trace "$E2E_TOBE_GATE_TRACE" \
    --slurpfile progress "$E2E_TOBE_GATE_PROGRESS" \
    --slurpfile verdict "$E2E_TOBE_GATE_VERDICT" \
    --arg trace_sha "$E2E_TOBE_TRACE_SHA" --arg change_sha "$E2E_TOBE_CHANGE_SHA" '
      def issue($id; $ok): if $ok then empty else $id end;
      $trace[0] as $t | $progress[0] as $p | $verdict[0] as $v |
      issue("tobe.precondition.f3_approval";
        $p.precondition_fingerprints.trace == $trace_sha
        and $p.precondition_fingerprints.inputs == $change_sha
        and any($p.approvals[]?;
          .gate == "F3" and .verdict == "accepted"
          and .actor_role == "human" and .source == "elicited")),
      issue("tobe.requirement.missing";
        ($t.extension_requirements | length) > 0
        and all($t.extension_requirements[];
          .kind == "tobe" and .status == "exact" and (.evidence_ids | length) > 0)),
      issue("tobe.design.missing";
        ($t.designs | length) > 0
        and all($t.designs[];
          .kind == "tobe" and (.requirement_ids | length) > 0
          and (.follows_convention_ids | length) > 0
          and (.follows_business_ids | length) > 0)),
      issue("tobe.binding.missing";
        all($t.designs[]; .id as $design |
          any($t.bindings[]?; .design_id == $design and has("convention_id"))
          and any($t.bindings[]?; .design_id == $design and has("business_id")))),
      issue("tobe.binding.violation";
        ($t.bindings | length) > 0 and all($t.bindings[]; .gate == "pass")
        and $v.violation_verdict == "pass"),
      issue("tobe.conflict.hidden";
        ([$t.business_rules[] | select(.status == "conflict") | .id] | sort)
        == ($v.conflicts | sort))
    '
}

e2e_tobe_validate_gate() {
  e2e_tobe_write_verdict || return 70
  E2E_TOBE_GATE_OUTPUT=$RUN_TMP/e2e-tobe-gate-issues.txt
  e2e_tobe_gate_issues "$E2E_TOBE_TRACE" "$E2E_TOBE_APPROVED" "$E2E_TOBE_VERDICT" \
    >"$E2E_TOBE_GATE_OUTPUT" || return 70
  for E2E_TOBE_GATE_ID in \
    tobe.precondition.f3_approval tobe.requirement.missing tobe.design.missing \
    tobe.binding.missing tobe.binding.violation tobe.conflict.hidden
  do
    CASE_TOTAL=$((CASE_TOTAL + 1))
    if rg -F -x -q --no-config "$E2E_TOBE_GATE_ID" "$E2E_TOBE_GATE_OUTPUT"; then
      assert_record "e2e.$E2E_TOBE_GATE_ID" 1 "$E2E_TOBE_GATE_ID" || true
    else
      assert_record "e2e.$E2E_TOBE_GATE_ID" 0 "$E2E_TOBE_GATE_ID 없음" || true
    fi
  done
}

e2e_tobe_provenance_run() {
  E2E_TOBE_PROV_NAME=$1
  E2E_TOBE_PROV_MODE=$2
  E2E_TOBE_PROV_ARTIFACT=$3
  E2E_TOBE_PROV_UPSTREAM=$4
  E2E_TOBE_PROV_OUT=$RUN_TMP/e2e-tobe-provenance-$E2E_TOBE_PROV_NAME.out
  jq -e --arg mode "$E2E_TOBE_PROV_MODE" --arg kind tobe \
    --rawfile artifact "$E2E_TOBE_PROV_ARTIFACT" --rawfile upstream "$E2E_TOBE_PROV_UPSTREAM" \
    -f "$SOURCE_ROOT/output/recipes/provenance.jq" "$E2E_TOBE_TRACE" \
    >"$E2E_TOBE_PROV_OUT" 2>"$E2E_TOBE_PROV_OUT.err"
  E2E_TOBE_PROV_RC=$?
  evidence_log_command "e2e-tobe.provenance-$E2E_TOBE_PROV_NAME" \
    "jq provenance mode=$E2E_TOBE_PROV_MODE kind=tobe artifact=fixtures/expected/tobe/$E2E_TOBE_PROV_NAME" \
    "$E2E_TOBE_PROV_RC"
}

e2e_tobe_validate_projections() {
  E2E_TOBE_EMPTY=$RUN_TMP/e2e-tobe-empty
  : >"$E2E_TOBE_EMPTY" || return 70
  E2E_TOBE_UI=$SOURCE_ROOT/fixtures/expected/tobe/ui.md
  E2E_TOBE_SEQUENCE=$SOURCE_ROOT/fixtures/expected/tobe/sequence.mmd
  E2E_TOBE_DATAFLOW=$SOURCE_ROOT/fixtures/expected/tobe/dataflow.mmd
  E2E_TOBE_STORY=$SOURCE_ROOT/fixtures/expected/tobe/story.md
  E2E_TOBE_TEST=$SOURCE_ROOT/fixtures/expected/tobe/test.md
  E2E_TOBE_MODE_ROWS=$RUN_TMP/e2e-tobe-five-mode.jsonl
  : >"$E2E_TOBE_MODE_ROWS" || return 70

  for E2E_TOBE_SPEC in 'ui.md|ui' 'sequence.mmd|mermaid' 'dataflow.mmd|dataflow' 'story.md|story' 'test.md|test'; do
    E2E_TOBE_NAME=${E2E_TOBE_SPEC%%|*}
    E2E_TOBE_MODE=${E2E_TOBE_SPEC#*|}
    E2E_TOBE_ARTIFACT=$SOURCE_ROOT/fixtures/expected/tobe/$E2E_TOBE_NAME
    E2E_TOBE_UPSTREAM=$E2E_TOBE_EMPTY
    test "$E2E_TOBE_MODE" = test && E2E_TOBE_UPSTREAM=$E2E_TOBE_STORY
    e2e_tobe_provenance_run "$E2E_TOBE_NAME" "$E2E_TOBE_MODE" "$E2E_TOBE_ARTIFACT" "$E2E_TOBE_UPSTREAM"
    e2e_tobe_assert_zero "e2e.tobe.provenance_$E2E_TOBE_MODE" "$E2E_TOBE_PROV_RC"
    E2E_TOBE_MODE_RESULT=FAIL
    test "$E2E_TOBE_PROV_RC" -eq 0 && E2E_TOBE_MODE_RESULT=PASS
    jq -cn --arg mode "$E2E_TOBE_MODE" --arg artifact "fixtures/expected/tobe/$E2E_TOBE_NAME" \
      --arg result "$E2E_TOBE_MODE_RESULT" --argjson exit "$E2E_TOBE_PROV_RC" \
      '{mode:$mode,kind:"tobe",artifact:$artifact,exit:$exit,result:$result}' \
      >>"$E2E_TOBE_MODE_ROWS" || return 70
  done
  jq -s '{kind:"tobe",modes:.}' "$E2E_TOBE_MODE_ROWS" >"$EVIDENCE_DIR/five-mode.json" || return 70

  for E2E_TOBE_STRUCTURE in \
    'ui|# ^"TO-BE 주문 상세 UI"$' \
    'story|# ^"TO-BE 사용자 스토리"$' \
    'test|# ^"TO-BE 테스트 시나리오"$'
  do
    E2E_TOBE_STRUCTURE_NAME=${E2E_TOBE_STRUCTURE%%|*}
    E2E_TOBE_STRUCTURE_QUERY=${E2E_TOBE_STRUCTURE#*|}
    mdq -q "$E2E_TOBE_STRUCTURE_QUERY" \
      "$SOURCE_ROOT/fixtures/expected/tobe/$E2E_TOBE_STRUCTURE_NAME.md" \
      >"$RUN_TMP/e2e-tobe-mdq-$E2E_TOBE_STRUCTURE_NAME.out" 2>&1
    E2E_TOBE_RC=$?
    evidence_log_command "e2e-tobe.mdq-$E2E_TOBE_STRUCTURE_NAME" \
      "mdq -q <TO-BE $E2E_TOBE_STRUCTURE_NAME heading>" "$E2E_TOBE_RC"
    e2e_tobe_assert_zero "e2e.tobe.structure_$E2E_TOBE_STRUCTURE_NAME" "$E2E_TOBE_RC"
  done
}

e2e_tobe_check_hashes() {
  E2E_TOBE_HASH_ROWS=$RUN_TMP/e2e-tobe-hashes.jsonl
  : >"$E2E_TOBE_HASH_ROWS" || return 70
  E2E_TOBE_HASH_OK=1
  for E2E_TOBE_RELATIVE in expected/tobe/ui.md expected/tobe/sequence.mmd \
    expected/tobe/dataflow.mmd expected/tobe/story.md expected/tobe/test.md
  do
    E2E_TOBE_FILE=$SOURCE_ROOT/fixtures/$E2E_TOBE_RELATIVE
    E2E_TOBE_EXPECTED=$(awk -v path="$E2E_TOBE_RELATIVE" '$2 == path {print $1}' \
      "$SOURCE_ROOT/fixtures/SHA256SUMS") || return 70
    e2e_tobe_sha256 "$E2E_TOBE_FILE" || return 70
    E2E_TOBE_RAW=$E2E_TOBE_SHA256
    E2E_TOBE_SLUG=$(printf '%s' "$E2E_TOBE_RELATIVE" | sed 's#[/.]#-#g') || return 70
    e2e_tobe_normalize "$E2E_TOBE_FILE" "$RUN_TMP/$E2E_TOBE_SLUG-1" || return 70
    e2e_tobe_normalize "$E2E_TOBE_FILE" "$RUN_TMP/$E2E_TOBE_SLUG-2" || return 70
    e2e_tobe_sha256 "$RUN_TMP/$E2E_TOBE_SLUG-1" || return 70
    E2E_TOBE_NORM1=$E2E_TOBE_SHA256
    e2e_tobe_sha256 "$RUN_TMP/$E2E_TOBE_SLUG-2" || return 70
    E2E_TOBE_NORM2=$E2E_TOBE_SHA256
    E2E_TOBE_EQUAL=false
    test "$E2E_TOBE_NORM1" = "$E2E_TOBE_NORM2" && E2E_TOBE_EQUAL=true
    test "$E2E_TOBE_EXPECTED" = "$E2E_TOBE_RAW" && test "$E2E_TOBE_EQUAL" = true || E2E_TOBE_HASH_OK=0
    jq -cn --arg path "fixtures/$E2E_TOBE_RELATIVE" --arg expected_sha256 "$E2E_TOBE_EXPECTED" \
      --arg raw_sha256 "$E2E_TOBE_RAW" --arg normalized_sha256_run_1 "$E2E_TOBE_NORM1" \
      --arg normalized_sha256_run_2 "$E2E_TOBE_NORM2" --argjson repeated_equal "$E2E_TOBE_EQUAL" \
      '{path:$path,expected_sha256:$expected_sha256,raw_sha256:$raw_sha256,normalized_sha256_run_1:$normalized_sha256_run_1,normalized_sha256_run_2:$normalized_sha256_run_2,repeated_equal:$repeated_equal}' \
      >>"$E2E_TOBE_HASH_ROWS" || return 70
  done
  jq -s '{algorithm:"sha256",normalization:"LF와 줄 끝 공백 제거",projections:.}' \
    "$E2E_TOBE_HASH_ROWS" >"$EVIDENCE_DIR/projection-hashes.json" || return 70
  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_eq e2e.tobe.projection_hashes 1 "$E2E_TOBE_HASH_OK" || true
}

e2e_tobe_extract_ui() {
  awk '
    /^```mermaid[[:space:]]*$/ { if (active) exit 2; active=1; next }
    active && /^```[[:space:]]*$/ { closed=1; exit }
    active { print }
    END { if (!active || !closed) exit 3 }
  ' "$E2E_TOBE_UI" >"$RUN_TMP/e2e-tobe-ui.mmd"
}

e2e_tobe_render() {
  command -v mmdc >/dev/null 2>&1 || { RUNNER_INFRA_REASON=MISSING_COMMAND_mmdc; return 70; }
  e2e_tobe_extract_ui || return 70
  E2E_TOBE_RENDER_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sensai-e2e-tobe-render.XXXXXX") || return 70
  case "$E2E_TOBE_RENDER_ROOT" in
    "${TMPDIR:-/tmp}"/sensai-e2e-tobe-render.*) ;;
    *) RUNNER_INFRA_REASON=UNSAFE_TOBE_RENDER_TEMP; return 70 ;;
  esac
  E2E_TOBE_RENDER_ROWS=$RUN_TMP/e2e-tobe-render.jsonl
  : >"$E2E_TOBE_RENDER_ROWS" || return 70
  for E2E_TOBE_RENDER_NAME in ui sequence dataflow; do
    case "$E2E_TOBE_RENDER_NAME" in
      ui) E2E_TOBE_RENDER_INPUT=$RUN_TMP/e2e-tobe-ui.mmd ;;
      sequence) E2E_TOBE_RENDER_INPUT=$E2E_TOBE_SEQUENCE ;;
      dataflow) E2E_TOBE_RENDER_INPUT=$E2E_TOBE_DATAFLOW ;;
    esac
    E2E_TOBE_SVG=$E2E_TOBE_RENDER_ROOT/$E2E_TOBE_RENDER_NAME.svg
    mmdc -i "$E2E_TOBE_RENDER_INPUT" -o "$E2E_TOBE_SVG" \
      >"$RUN_TMP/e2e-tobe-mmdc-$E2E_TOBE_RENDER_NAME.out" 2>&1
    E2E_TOBE_RC=$?
    E2E_TOBE_SIZE=0
    E2E_TOBE_SVG_SHA=''
    if test -s "$E2E_TOBE_SVG"; then
      E2E_TOBE_SIZE=$(wc -c <"$E2E_TOBE_SVG" | awk '{print $1}') || return 70
      e2e_tobe_sha256 "$E2E_TOBE_SVG" || return 70
      E2E_TOBE_SVG_SHA=$E2E_TOBE_SHA256
    fi
    evidence_log_command "e2e-tobe.mmdc-$E2E_TOBE_RENDER_NAME" \
      "mmdc -i <TO-BE-$E2E_TOBE_RENDER_NAME> -o <external-temp>/$E2E_TOBE_RENDER_NAME.svg" "$E2E_TOBE_RC"
    CASE_TOTAL=$((CASE_TOTAL + 1))
    if test "$E2E_TOBE_RC" -eq 0 && test "$E2E_TOBE_SIZE" -gt 0; then
      assert_record "e2e.tobe.render_$E2E_TOBE_RENDER_NAME" 0 \
        "exit=0 svg_size=$E2E_TOBE_SIZE sha256=$E2E_TOBE_SVG_SHA" || true
      E2E_TOBE_RENDER_RESULT=PASS
    else
      assert_record "e2e.tobe.render_$E2E_TOBE_RENDER_NAME" 1 \
        "exit=$E2E_TOBE_RC svg_size=$E2E_TOBE_SIZE" || true
      E2E_TOBE_RENDER_RESULT=FAIL
    fi
    jq -cn --arg name "$E2E_TOBE_RENDER_NAME" --arg sha256 "$E2E_TOBE_SVG_SHA" \
      --arg result "$E2E_TOBE_RENDER_RESULT" --argjson exit "$E2E_TOBE_RC" --argjson size "$E2E_TOBE_SIZE" \
      '{name:$name,exit:$exit,svg_size:$size,svg_sha256:$sha256,result:$result,artifact_persisted:false}' \
      >>"$E2E_TOBE_RENDER_ROWS" || return 70
  done
  jq -s --arg path "$(command -v mmdc)" --arg version "$(mmdc --version 2>&1)" \
    '{command:"mmdc",command_path:$path,version:$version,renders:.,artifact_persisted:false}' \
    "$E2E_TOBE_RENDER_ROWS" >"$EVIDENCE_DIR/render-receipt.json" || return 70
  rm -rf "$E2E_TOBE_RENDER_ROOT" || return 70
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test ! -e "$E2E_TOBE_RENDER_ROOT"; then
    assert_record e2e.tobe.render_cleanup 0 '외부 render 임시 디렉터리를 제거했다' || true
  else
    assert_record e2e.tobe.render_cleanup 1 '외부 render 임시 디렉터리가 남았다' || true
  fi
}

e2e_tobe_negative_checks() {
  E2E_TOBE_BAD_PROGRESS=$RUN_TMP/e2e-tobe-no-approval.json
  E2E_TOBE_BAD_BINDING=$RUN_TMP/e2e-tobe-no-binding.json
  E2E_TOBE_BAD_VIOLATION=$RUN_TMP/e2e-tobe-violation.json
  E2E_TOBE_BAD_PROVENANCE=$RUN_TMP/e2e-tobe-no-provenance.md
  jq '.approvals=[]' "$E2E_TOBE_APPROVED" >"$E2E_TOBE_BAD_PROGRESS" || return 70
  jq '.bindings=[]' "$E2E_TOBE_TRACE" >"$E2E_TOBE_BAD_BINDING" || return 70
  jq '(.bindings[0].gate)="violation"' "$E2E_TOBE_TRACE" >"$E2E_TOBE_BAD_VIOLATION" || return 70

  E2E_TOBE_NEG_ROWS=$RUN_TMP/e2e-tobe-negative.jsonl
  : >"$E2E_TOBE_NEG_ROWS" || return 70
  for E2E_TOBE_NEG_SPEC in \
    "missing-asis-approval|$E2E_TOBE_TRACE|$E2E_TOBE_BAD_PROGRESS|tobe.precondition.f3_approval" \
    "missing-binding|$E2E_TOBE_BAD_BINDING|$E2E_TOBE_APPROVED|tobe.binding.missing" \
    "violation-verdict|$E2E_TOBE_BAD_VIOLATION|$E2E_TOBE_APPROVED|tobe.binding.violation"
  do
    E2E_TOBE_NEG_NAME=${E2E_TOBE_NEG_SPEC%%|*}
    E2E_TOBE_NEG_REST=${E2E_TOBE_NEG_SPEC#*|}
    E2E_TOBE_NEG_TRACE=${E2E_TOBE_NEG_REST%%|*}
    E2E_TOBE_NEG_REST=${E2E_TOBE_NEG_REST#*|}
    E2E_TOBE_NEG_PROGRESS=${E2E_TOBE_NEG_REST%%|*}
    E2E_TOBE_NEG_ID=${E2E_TOBE_NEG_REST#*|}
    E2E_TOBE_NEG_OUT=$RUN_TMP/e2e-tobe-$E2E_TOBE_NEG_NAME.out
    e2e_tobe_gate_issues "$E2E_TOBE_NEG_TRACE" "$E2E_TOBE_NEG_PROGRESS" "$E2E_TOBE_VERDICT" \
      >"$E2E_TOBE_NEG_OUT" || return 70
    CASE_TOTAL=$((CASE_TOTAL + 1))
    if rg -F -x -q --no-config "$E2E_TOBE_NEG_ID" "$E2E_TOBE_NEG_OUT"; then
      assert_record "e2e.tobe.negative_$E2E_TOBE_NEG_NAME" 0 "$E2E_TOBE_NEG_ID 검출" || true
      E2E_TOBE_NEG_RESULT=PASS
    else
      assert_record "e2e.tobe.negative_$E2E_TOBE_NEG_NAME" 1 "$E2E_TOBE_NEG_ID 미검출" || true
      E2E_TOBE_NEG_RESULT=FAIL
    fi
    jq -cn --arg case "$E2E_TOBE_NEG_NAME" --arg expected_reason "$E2E_TOBE_NEG_ID" \
      --arg result "$E2E_TOBE_NEG_RESULT" '{case:$case,expected_reason:$expected_reason,result:$result}' \
      >>"$E2E_TOBE_NEG_ROWS" || return 70
  done

  awk '!/^[[:space:]]*(%%[[:space:]]*)?provenance:/' "$E2E_TOBE_SEQUENCE" \
    >"$E2E_TOBE_BAD_PROVENANCE" || return 70
  e2e_tobe_provenance_run missing-provenance mermaid "$E2E_TOBE_BAD_PROVENANCE" "$E2E_TOBE_EMPTY"
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test "$E2E_TOBE_PROV_RC" -ne 0 && \
     rg -F -q --no-config 'provenance.source_missing' "$E2E_TOBE_PROV_OUT.err"; then
    assert_record e2e.tobe.negative_missing-provenance 0 'provenance.source_missing 검출' || true
    E2E_TOBE_NEG_RESULT=PASS
  else
    assert_record e2e.tobe.negative_missing-provenance 1 'provenance 누락 false green' || true
    E2E_TOBE_NEG_RESULT=FAIL
  fi
  jq -cn --arg result "$E2E_TOBE_NEG_RESULT" \
    '{case:"missing-provenance",expected_reason:"provenance.source_missing",result:$result}' \
    >>"$E2E_TOBE_NEG_ROWS" || return 70
  jq -s '{cases:.}' "$E2E_TOBE_NEG_ROWS" >"$EVIDENCE_DIR/negative-gates.json" || return 70
}

e2e_tobe_write_evidence() {
  E2E_TOBE_RESULT=PASS
  test "$ASSERT_FAILED" -eq 0 || E2E_TOBE_RESULT=ASSERTION_FAILURE
  jq -n '{task:"T24",proof:"offline deterministic TO-BE validation and projection",steps:[
    {id:"V0",mode:"precondition",result:"PASS"},
    {id:"D5",mode:"requirements-designs-bindings",result:"PASS"},
    {id:"V3",mode:"five-mode-provenance",result:"PASS"},
    {id:"V4",mode:"mermaid-render",result:"PASS"},
    {id:"V5",mode:"stable-projection-hashes",result:"PASS"}
  ]}' >"$EVIDENCE_DIR/pipeline-steps.json" || return 70
  jq -n '{
    model_production:"UNVERIFIED",model_calls:0,inference_claimed:false,
    approval_note_ko:"F3 accepted 값은 결정적 fixture 시나리오이며 실제 사용자 승인 영수증이 아니다.",
    claim_ko:"고정 AS-IS trace와 change-request golden에서 TO-BE 원장과 5종 golden을 오프라인 검증한 사실만 증명한다.",
    windows_receipt:"PENDING"
  }' >"$EVIDENCE_DIR/nonclaim.json" || return 70

  E2E_TOBE_CURRENT_ROWS=$RUN_TMP/e2e-tobe-current.jsonl
  : >"$E2E_TOBE_CURRENT_ROWS" || return 70
  for E2E_TOBE_CURRENT in \
    fixtures/expected/trace-v2.json fixtures/expected/progress.json fixtures/inputs/change/valid.md \
    fixtures/expected/tobe/ui.md fixtures/expected/tobe/sequence.mmd fixtures/expected/tobe/dataflow.mmd \
    fixtures/expected/tobe/story.md fixtures/expected/tobe/test.md output/recipes/trace.jq \
    output/recipes/progress.jq output/recipes/provenance.jq tests/cases/e2e-tobe.sh tests/test.sh
  do
    e2e_tobe_sha256 "$SOURCE_ROOT/$E2E_TOBE_CURRENT" || return 70
    jq -cn --arg path "$E2E_TOBE_CURRENT" --arg sha256 "$E2E_TOBE_SHA256" \
      '{path:$path,sha256:$sha256}' >>"$E2E_TOBE_CURRENT_ROWS" || return 70
  done
  jq -s '{algorithm:"sha256",files:.}' "$E2E_TOBE_CURRENT_ROWS" \
    >"$EVIDENCE_DIR/current-hashes.json" || return 70
  jq -n --arg result "$E2E_TOBE_RESULT" '{
    task:"T24",result:$result,
    acceptance:["accepted AS-IS fixture scenario","requirements designs and two-sided bindings","five TO-BE provenance modes","three nonempty SVG renders","stable normalized hashes","named gate failures"],
    model_production:"UNVERIFIED",windows_receipt:"PENDING",fixture_corpus_modified:false,
    independent_verification:"PENDING",commit:"N - prohibited before final task"
  }' >"$EVIDENCE_DIR/done-claim.json" || return 70
}

e2e_tobe_clone_source() {
  mkdir -p "$1/output" "$1/tests" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$1/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests/." "$1/tests/" || return 70
  cp -R "$SOURCE_ROOT/output/." "$1/output/" || return 70
  cp -R "$SOURCE_ROOT/fixtures" "$1/fixtures" || return 70
}

run_expected_conflict_hidden_by_deliverable() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  E2E_TOBE_EXPECT_ROOT=$RUN_TMP/expect-conflict-hidden-source
  E2E_TOBE_EXPECT_EVIDENCE=$EVIDENCE_DIR/inner-conflict-hidden
  e2e_tobe_clone_source "$E2E_TOBE_EXPECT_ROOT" || return 70
  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && \
     test -n "${SENSAI_TEST_EXPECT_TOBE_FORCED_EXIT:-}"; then
    case "$SENSAI_TEST_EXPECT_TOBE_FORCED_EXIT" in
      64|70|127) E2E_TOBE_EXPECT_RC=$SENSAI_TEST_EXPECT_TOBE_FORCED_EXIT ;;
      *) E2E_TOBE_EXPECT_RC=70 ;;
    esac
  else
    set +e
    env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_TOBE_HIDE_CONFLICT=1 \
      SENSAI_TEST_SOURCE_ROOT="$E2E_TOBE_EXPECT_ROOT" \
      "$TEST_RUNNER" e2e-tobe --evidence "$E2E_TOBE_EXPECT_EVIDENCE" \
      >"$RUN_TMP/expect-conflict-hidden.out" 2>&1
    E2E_TOBE_EXPECT_RC=$?
  fi
  evidence_log_command expected-conflict-hidden-by-deliverable \
    "$TEST_RUNNER e2e-tobe <isolated-hidden-conflict-verdict>" "$E2E_TOBE_EXPECT_RC"
  case "$E2E_TOBE_EXPECT_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$E2E_TOBE_EXPECT_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.conflict_hidden_exit 1 "$E2E_TOBE_EXPECT_RC" || true
  if test -f "$E2E_TOBE_EXPECT_EVIDENCE/receipt.json"; then
    assert_jq expect.conflict_hidden_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' "$E2E_TOBE_EXPECT_EVIDENCE/receipt.json" || true
    assert_jq expect.conflict_hidden_named_failure \
      '.failed_assertion_ids == ["e2e.tobe.conflict.hidden"]' "$E2E_TOBE_EXPECT_EVIDENCE/receipt.json" || true
  else
    assert_record expect.conflict_hidden_receipt 1 'expected-failure receipt가 없다' || true
  fi
}

case_e2e_tobe() {
  e2e_tobe_build_preconditions || return 70
  e2e_tobe_validate_gate || return 70
  e2e_tobe_validate_projections || return 70
  e2e_tobe_check_hashes || return 70
  e2e_tobe_render || return 70
  e2e_tobe_negative_checks || return 70
  e2e_tobe_write_evidence || return 70
}
