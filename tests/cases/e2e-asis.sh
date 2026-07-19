#!/bin/sh

e2e_asis_sha256() {
  E2E_ASIS_SHA_FILE=$1
  tooling_sha256_file "$E2E_ASIS_SHA_FILE" || return 70
  E2E_ASIS_SHA256=$TOOLING_SHA256
}

e2e_asis_normalize() {
  E2E_ASIS_NORMALIZE_INPUT=$1
  E2E_ASIS_NORMALIZE_OUTPUT=$2
  awk '{ sub(/\r$/, ""); sub(/[[:space:]]+$/, ""); print }' \
    "$E2E_ASIS_NORMALIZE_INPUT" >"$E2E_ASIS_NORMALIZE_OUTPUT" || return 70
}

e2e_asis_assert_exit_zero() {
  E2E_ASIS_ASSERT_ID=$1
  E2E_ASIS_ASSERT_RC=$2
  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_eq "$E2E_ASIS_ASSERT_ID" 0 "$E2E_ASIS_ASSERT_RC" || true
}

e2e_asis_validate_trace() {
  E2E_ASIS_TRACE=$SOURCE_ROOT/fixtures/expected/trace-v2.json
  E2E_ASIS_GLOSSARY=$SOURCE_ROOT/fixtures/expected/glossary.json

  jq -f "$SOURCE_ROOT/tests/validators/trace-schema-parity.jq" "$E2E_ASIS_TRACE" \
    >"$RUN_TMP/e2e-asis-schema.json" 2>"$RUN_TMP/e2e-asis-schema.err"
  E2E_ASIS_RC=$?
  evidence_log_command e2e-asis.schema \
    'jq -f tests/validators/trace-schema-parity.jq fixtures/expected/trace-v2.json' "$E2E_ASIS_RC"
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test "$E2E_ASIS_RC" -eq 0 && jq -e 'type == "array" and length == 0' \
    "$RUN_TMP/e2e-asis-schema.json" >/dev/null 2>&1; then
    assert_record e2e.asis.trace_schema 0 'canonical trace가 schema 2.0을 만족한다' || true
  else
    assert_record e2e.asis.trace_schema 1 'canonical trace schema 검증 실패' || true
  fi

  jq -e -f "$SOURCE_ROOT/output/recipes/trace.jq" "$E2E_ASIS_TRACE" \
    >"$RUN_TMP/e2e-asis-trace.out" 2>"$RUN_TMP/e2e-asis-trace.err"
  E2E_ASIS_RC=$?
  evidence_log_command e2e-asis.trace \
    'jq -e -f output/recipes/trace.jq fixtures/expected/trace-v2.json' "$E2E_ASIS_RC"
  e2e_asis_assert_exit_zero e2e.asis.trace_recipe "$E2E_ASIS_RC"

  jq -e -s -f "$SOURCE_ROOT/output/recipes/glossary.jq" "$E2E_ASIS_TRACE" "$E2E_ASIS_GLOSSARY" \
    >"$RUN_TMP/e2e-asis-glossary.out" 2>"$RUN_TMP/e2e-asis-glossary.err"
  E2E_ASIS_RC=$?
  evidence_log_command e2e-asis.glossary \
    'jq -e -s -f output/recipes/glossary.jq fixtures/expected/trace-v2.json fixtures/expected/glossary.json' \
    "$E2E_ASIS_RC"
  e2e_asis_assert_exit_zero e2e.asis.glossary "$E2E_ASIS_RC"

  CASE_TOTAL=$((CASE_TOTAL + 1))
  if jq -e '
      ([.conventions[].category] | unique | sort) == ["API","COMPONENT","ERROR","NAMING","STATE","STRUCTURE","TEST"]
      and (.requirements | length) > 0
      and (.frontends | length) > 0
      and (.backends | length) > 0
      and all(.conventions[], .requirements[], .frontends[], .backends[];
        .kind == "asis" and (.evidence_ids | length) > 0)
    ' "$E2E_ASIS_TRACE" >/dev/null 2>&1; then
    assert_record e2e.asis.technical_fragments 0 '기술 fragment와 7개 convention category가 근거와 함께 존재한다' || true
  else
    assert_record e2e.asis.technical_fragments 1 '기술 fragment 또는 convention category가 누락됐다' || true
  fi

  CASE_TOTAL=$((CASE_TOTAL + 1))
  if jq -e '
      ([.business_entities,.business_rules,.business_flows,.business_events,.business_states,.business_invariants]
        | all(.[]; length > 0))
      and all(.business_entities[],.business_rules[],.business_flows[],.business_events[],.business_states[],.business_invariants[];
        .kind == "asis" and (.evidence_ids | length) > 0)
      and all(.business_flows[]; (.technical_ids | length) > 0)
      and ([.business_rules[] | select(.status == "conflict")] | length) == 2
    ' "$E2E_ASIS_TRACE" >/dev/null 2>&1; then
    assert_record e2e.asis.business_fragments 0 '비즈니스 6종 fragment와 conflict 보존을 확인했다' || true
  else
    assert_record e2e.asis.business_fragments 1 '비즈니스 fragment 또는 conflict 보존 계약 위반' || true
  fi
}

e2e_asis_validate_source_lines() {
  E2E_ASIS_SOURCE_ROWS=$RUN_TMP/e2e-asis-source-rows.tsv
  jq -r '.evidence[] | [.id,.path,(.line|tostring),.path_line] | join("|")' \
    "$E2E_ASIS_TRACE" >"$E2E_ASIS_SOURCE_ROWS" || return 70
  E2E_ASIS_SOURCE_OK=1
  E2E_ASIS_SOURCE_COUNT=0
  while IFS='|' read -r E2E_ASIS_EVIDENCE_ID E2E_ASIS_RELATIVE E2E_ASIS_LINE E2E_ASIS_PATH_LINE; do
    E2E_ASIS_SOURCE_COUNT=$((E2E_ASIS_SOURCE_COUNT + 1))
    case "$E2E_ASIS_RELATIVE" in
      ''|/*|../*|*/../*|*/..) E2E_ASIS_SOURCE_OK=0; continue ;;
    esac
    E2E_ASIS_INPUT=$SOURCE_ROOT/fixtures/$E2E_ASIS_RELATIVE
    if ! test -f "$E2E_ASIS_INPUT" || test -L "$E2E_ASIS_INPUT" || \
       test "$E2E_ASIS_PATH_LINE" != "$E2E_ASIS_RELATIVE:$E2E_ASIS_LINE"; then
      E2E_ASIS_SOURCE_OK=0
      continue
    fi
    E2E_ASIS_LINE_VALUE=$(sed -n "${E2E_ASIS_LINE}p" "$E2E_ASIS_INPUT") || return 70
    test -n "$E2E_ASIS_LINE_VALUE" || E2E_ASIS_SOURCE_OK=0
  done <"$E2E_ASIS_SOURCE_ROWS"
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test "$E2E_ASIS_SOURCE_OK" -eq 1 && test "$E2E_ASIS_SOURCE_COUNT" -eq 19; then
    assert_record e2e.asis.source_lines 0 "19개 evidence의 fixture path:line이 실제 비어 있지 않은 줄로 해소된다" || true
  else
    assert_record e2e.asis.source_lines 1 \
      "evidence path:line 해소 실패 count=$E2E_ASIS_SOURCE_COUNT" || true
  fi
}

e2e_asis_provenance_run() {
  E2E_ASIS_PROV_NAME=$1
  E2E_ASIS_PROV_MODE=$2
  E2E_ASIS_PROV_ARTIFACT=$3
  E2E_ASIS_PROV_OUT=$RUN_TMP/e2e-asis-provenance-$E2E_ASIS_PROV_NAME.out
  jq -e --arg mode "$E2E_ASIS_PROV_MODE" --arg kind asis \
    --rawfile artifact "$E2E_ASIS_PROV_ARTIFACT" --arg upstream '' \
    -f "$SOURCE_ROOT/output/recipes/provenance.jq" "$E2E_ASIS_TRACE" \
    >"$E2E_ASIS_PROV_OUT" 2>"$E2E_ASIS_PROV_OUT.err"
  E2E_ASIS_PROV_RC=$?
  evidence_log_command "e2e-asis.provenance-$E2E_ASIS_PROV_NAME" \
    "jq provenance mode=$E2E_ASIS_PROV_MODE kind=asis artifact=fixtures/expected/asis/$E2E_ASIS_PROV_NAME" \
    "$E2E_ASIS_PROV_RC"
}

e2e_asis_validate_projections() {
  E2E_ASIS_UI=$SOURCE_ROOT/fixtures/expected/asis/ui.md
  E2E_ASIS_SEQUENCE=$SOURCE_ROOT/fixtures/expected/asis/sequence.mmd
  E2E_ASIS_DATAFLOW=$SOURCE_ROOT/fixtures/expected/asis/dataflow.mmd
  E2E_ASIS_STORY=$SOURCE_ROOT/fixtures/expected/asis/story.md

  e2e_asis_provenance_run ui.md ui "$E2E_ASIS_UI"
  e2e_asis_assert_exit_zero e2e.asis.provenance_ui "$E2E_ASIS_PROV_RC"
  e2e_asis_provenance_run sequence.mmd mermaid "$E2E_ASIS_SEQUENCE"
  e2e_asis_assert_exit_zero e2e.asis.provenance_sequence "$E2E_ASIS_PROV_RC"
  e2e_asis_provenance_run dataflow.mmd dataflow "$E2E_ASIS_DATAFLOW"
  e2e_asis_assert_exit_zero e2e.asis.provenance_dataflow "$E2E_ASIS_PROV_RC"
  e2e_asis_provenance_run story.md story "$E2E_ASIS_STORY"
  e2e_asis_assert_exit_zero e2e.asis.provenance_story "$E2E_ASIS_PROV_RC"

  mdq -q '# ^"AS-IS 주문 목록 UI"$' "$E2E_ASIS_UI" \
    >"$RUN_TMP/e2e-asis-mdq-ui.out" 2>"$RUN_TMP/e2e-asis-mdq-ui.err"
  E2E_ASIS_RC=$?
  evidence_log_command e2e-asis.mdq-ui 'mdq -q <AS-IS UI heading> fixtures/expected/asis/ui.md' "$E2E_ASIS_RC"
  e2e_asis_assert_exit_zero e2e.asis.ui_structure "$E2E_ASIS_RC"

  mdq -q '# ^"AS-IS 사용자 스토리"$' "$E2E_ASIS_STORY" \
    >"$RUN_TMP/e2e-asis-mdq-story.out" 2>"$RUN_TMP/e2e-asis-mdq-story.err"
  E2E_ASIS_RC=$?
  evidence_log_command e2e-asis.mdq-story 'mdq -q <AS-IS story heading> fixtures/expected/asis/story.md' "$E2E_ASIS_RC"
  e2e_asis_assert_exit_zero e2e.asis.story_structure "$E2E_ASIS_RC"
}

e2e_asis_check_golden_hashes() {
  E2E_ASIS_HASH_ROWS=$RUN_TMP/e2e-asis-projection-hashes.jsonl
  : >"$E2E_ASIS_HASH_ROWS" || return 70
  E2E_ASIS_GOLDEN_OK=1
  for E2E_ASIS_RELATIVE in expected/asis/ui.md expected/asis/sequence.mmd expected/asis/dataflow.mmd expected/asis/story.md; do
    E2E_ASIS_FILE=$SOURCE_ROOT/fixtures/$E2E_ASIS_RELATIVE
    E2E_ASIS_EXPECTED_SHA=$(awk -v path="$E2E_ASIS_RELATIVE" '$2 == path { print $1 }' \
      "$SOURCE_ROOT/fixtures/SHA256SUMS") || return 70
    e2e_asis_sha256 "$E2E_ASIS_FILE" || return 70
    E2E_ASIS_RAW_SHA=$E2E_ASIS_SHA256
    test -n "$E2E_ASIS_EXPECTED_SHA" && test "$E2E_ASIS_RAW_SHA" = "$E2E_ASIS_EXPECTED_SHA" || \
      E2E_ASIS_GOLDEN_OK=0

    E2E_ASIS_SLUG=$(printf '%s' "$E2E_ASIS_RELATIVE" | sed 's#[/.]#-#g') || return 70
    E2E_ASIS_NORMALIZED_1=$RUN_TMP/$E2E_ASIS_SLUG-normalized-1
    E2E_ASIS_NORMALIZED_2=$RUN_TMP/$E2E_ASIS_SLUG-normalized-2
    e2e_asis_normalize "$E2E_ASIS_FILE" "$E2E_ASIS_NORMALIZED_1" || return 70
    e2e_asis_normalize "$E2E_ASIS_FILE" "$E2E_ASIS_NORMALIZED_2" || return 70
    e2e_asis_sha256 "$E2E_ASIS_NORMALIZED_1" || return 70
    E2E_ASIS_NORMALIZED_SHA_1=$E2E_ASIS_SHA256
    e2e_asis_sha256 "$E2E_ASIS_NORMALIZED_2" || return 70
    E2E_ASIS_NORMALIZED_SHA_2=$E2E_ASIS_SHA256
    E2E_ASIS_REPEATED_EQUAL=false
    test "$E2E_ASIS_NORMALIZED_SHA_1" = "$E2E_ASIS_NORMALIZED_SHA_2" && E2E_ASIS_REPEATED_EQUAL=true
    jq -cn --arg path "fixtures/$E2E_ASIS_RELATIVE" \
      --arg expected_sha256 "$E2E_ASIS_EXPECTED_SHA" --arg raw_sha256 "$E2E_ASIS_RAW_SHA" \
      --arg normalized_sha256_run_1 "$E2E_ASIS_NORMALIZED_SHA_1" \
      --arg normalized_sha256_run_2 "$E2E_ASIS_NORMALIZED_SHA_2" \
      --argjson repeated_equal "$E2E_ASIS_REPEATED_EQUAL" \
      '{path:$path,expected_sha256:$expected_sha256,raw_sha256:$raw_sha256,normalized_sha256_run_1:$normalized_sha256_run_1,normalized_sha256_run_2:$normalized_sha256_run_2,repeated_equal:$repeated_equal}' \
      >>"$E2E_ASIS_HASH_ROWS" || return 70
    test "$E2E_ASIS_REPEATED_EQUAL" = true || E2E_ASIS_GOLDEN_OK=0
  done
  jq -s '{algorithm:"sha256",normalization:"LF와 줄 끝 공백 제거",projections:.}' \
    "$E2E_ASIS_HASH_ROWS" >"$EVIDENCE_DIR/projection-hashes.json" || return 70
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test "$E2E_ASIS_GOLDEN_OK" -eq 1; then
    assert_record e2e.asis.golden_drift 0 '4개 canonical golden hash가 fixture 원장과 일치하고 반복 정규화 hash가 같다' || true
  else
    assert_record e2e.asis.golden_drift 1 'canonical AS-IS golden 또는 반복 정규화 hash가 drift했다' || true
  fi
}

e2e_asis_extract_ui_mermaid() {
  awk '
    /^```mermaid[[:space:]]*$/ { if (active) exit 2; active=1; next }
    active && /^```[[:space:]]*$/ { closed=1; exit }
    active { print }
    END { if (!active || !closed) exit 3 }
  ' "$E2E_ASIS_UI" >"$RUN_TMP/e2e-asis-ui.mmd"
}

e2e_asis_render_projections() {
  if ! command -v mmdc >/dev/null 2>&1; then
    RUNNER_INFRA_REASON=MISSING_COMMAND_mmdc
    evidence_add_reason "$RUNNER_INFRA_REASON"
    return 70
  fi
  e2e_asis_extract_ui_mermaid || return 70
  E2E_ASIS_RENDER_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sensai-e2e-asis-render.XXXXXX") || return 70
  case "$E2E_ASIS_RENDER_ROOT" in
    "${TMPDIR:-/tmp}"/sensai-e2e-asis-render.*) ;;
    *) RUNNER_INFRA_REASON=UNSAFE_ASIS_RENDER_TEMP; return 70 ;;
  esac
  E2E_ASIS_RENDER_ROWS=$RUN_TMP/e2e-asis-render.jsonl
  : >"$E2E_ASIS_RENDER_ROWS" || return 70
  for E2E_ASIS_RENDER_NAME in ui sequence dataflow; do
    case "$E2E_ASIS_RENDER_NAME" in
      ui) E2E_ASIS_RENDER_INPUT=$RUN_TMP/e2e-asis-ui.mmd ;;
      sequence) E2E_ASIS_RENDER_INPUT=$E2E_ASIS_SEQUENCE ;;
      dataflow) E2E_ASIS_RENDER_INPUT=$E2E_ASIS_DATAFLOW ;;
    esac
    E2E_ASIS_RENDER_SVG=$E2E_ASIS_RENDER_ROOT/$E2E_ASIS_RENDER_NAME.svg
    mmdc -i "$E2E_ASIS_RENDER_INPUT" -o "$E2E_ASIS_RENDER_SVG" \
      >"$RUN_TMP/e2e-asis-mmdc-$E2E_ASIS_RENDER_NAME.out" \
      2>"$RUN_TMP/e2e-asis-mmdc-$E2E_ASIS_RENDER_NAME.err"
    E2E_ASIS_RENDER_RC=$?
    evidence_log_command "e2e-asis.mmdc-$E2E_ASIS_RENDER_NAME" \
      "mmdc -i <AS-IS-$E2E_ASIS_RENDER_NAME> -o <external-temp>/$E2E_ASIS_RENDER_NAME.svg" \
      "$E2E_ASIS_RENDER_RC"
    E2E_ASIS_RENDER_SIZE=0
    E2E_ASIS_RENDER_SHA=''
    if test -s "$E2E_ASIS_RENDER_SVG"; then
      E2E_ASIS_RENDER_SIZE=$(wc -c <"$E2E_ASIS_RENDER_SVG" | awk '{print $1}') || return 70
      e2e_asis_sha256 "$E2E_ASIS_RENDER_SVG" || return 70
      E2E_ASIS_RENDER_SHA=$E2E_ASIS_SHA256
    fi
    CASE_TOTAL=$((CASE_TOTAL + 1))
    if test "$E2E_ASIS_RENDER_RC" -eq 0 && test "$E2E_ASIS_RENDER_SIZE" -gt 0; then
      assert_record "e2e.asis.render_$E2E_ASIS_RENDER_NAME" 0 \
        "exit=0 svg_size=$E2E_ASIS_RENDER_SIZE svg_sha256=$E2E_ASIS_RENDER_SHA" || true
      E2E_ASIS_RENDER_RESULT=PASS
    else
      assert_record "e2e.asis.render_$E2E_ASIS_RENDER_NAME" 1 \
        "exit=$E2E_ASIS_RENDER_RC svg_size=$E2E_ASIS_RENDER_SIZE" || true
      E2E_ASIS_RENDER_RESULT=FAIL
    fi
    jq -cn --arg name "$E2E_ASIS_RENDER_NAME" --arg input "$E2E_ASIS_RENDER_INPUT" \
      --arg sha256 "$E2E_ASIS_RENDER_SHA" --arg result "$E2E_ASIS_RENDER_RESULT" \
      --argjson exit "$E2E_ASIS_RENDER_RC" --argjson size "$E2E_ASIS_RENDER_SIZE" \
      '{name:$name,input:$input,exit:$exit,svg_size:$size,svg_sha256:$sha256,result:$result,artifact_persisted:false}' \
      >>"$E2E_ASIS_RENDER_ROWS" || return 70
  done
  jq -s --arg command_path "$(command -v mmdc)" --arg version "$(mmdc --version 2>&1)" \
    '{command:"mmdc",command_path:$command_path,version:$version,renders:.,artifact_persisted:false}' \
    "$E2E_ASIS_RENDER_ROWS" >"$EVIDENCE_DIR/render-receipt.json" || return 70
  rm -rf "$E2E_ASIS_RENDER_ROOT" || return 70
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test ! -e "$E2E_ASIS_RENDER_ROOT"; then
    assert_record e2e.asis.render_cleanup 0 '외부 render 임시 디렉터리를 제거했다' || true
  else
    assert_record e2e.asis.render_cleanup 1 '외부 render 임시 디렉터리가 남았다' || true
  fi
}

e2e_asis_negative_checks() {
  E2E_ASIS_DRIFT=$RUN_TMP/e2e-asis-drift.md
  cp "$E2E_ASIS_STORY" "$E2E_ASIS_DRIFT" || return 70
  printf '\n검출용 golden drift\n' >>"$E2E_ASIS_DRIFT" || return 70
  e2e_asis_sha256 "$E2E_ASIS_DRIFT" || return 70
  E2E_ASIS_DRIFT_SHA=$E2E_ASIS_SHA256
  E2E_ASIS_STORY_EXPECTED=$(awk '$2 == "expected/asis/story.md" { print $1 }' \
    "$SOURCE_ROOT/fixtures/SHA256SUMS") || return 70
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test -n "$E2E_ASIS_STORY_EXPECTED" && test "$E2E_ASIS_DRIFT_SHA" != "$E2E_ASIS_STORY_EXPECTED"; then
    assert_record e2e.asis.golden_drift_detected 0 'corrupted golden hash를 named failure로 검출했다' || true
  else
    assert_record e2e.asis.golden_drift_detected 1 'corrupted golden hash를 검출하지 못했다' || true
  fi

  E2E_ASIS_BAD_PROVENANCE=$RUN_TMP/e2e-asis-bad-provenance.mmd
  sed 's#inputs/legacy-vertx/src/main/java/example/OrderVerticle.java:10#inputs/legacy-react/src/OrdersPage.tsx:3#' \
    "$E2E_ASIS_SEQUENCE" >"$E2E_ASIS_BAD_PROVENANCE" || return 70
  e2e_asis_provenance_run corrupt-provenance mermaid "$E2E_ASIS_BAD_PROVENANCE"
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test "$E2E_ASIS_PROV_RC" -ne 0 && rg -F provenance.source_mismatch \
    "$E2E_ASIS_PROV_OUT.err" >/dev/null 2>&1; then
    assert_record e2e.asis.provenance_corrupt 0 'corrupted provenance를 provenance.source_mismatch로 거부했다' || true
  else
    assert_record e2e.asis.provenance_corrupt 1 \
      "corrupted provenance false green exit=$E2E_ASIS_PROV_RC" || true
  fi

  CASE_TOTAL=$((CASE_TOTAL + 1))
  if jq -e '(.rules | length) >= 2 and all(.rules[]; .status == "exact") and (.conflicts | length) == 0' \
    "$SOURCE_ROOT/fixtures/adversarial/hidden-conflict.json" >/dev/null 2>&1; then
    assert_record e2e.asis.conflict_hidden 0 'conflict를 exact로 축약한 adversarial 문서를 거부했다' || true
  else
    assert_record e2e.asis.conflict_hidden 1 'hidden-conflict adversarial 입력의 검출 조건이 사라졌다' || true
  fi
}

e2e_asis_write_evidence() {
  E2E_ASIS_OVERALL_RESULT=PASS
  test "$ASSERT_FAILED" -eq 0 || E2E_ASIS_OVERALL_RESULT=ASSERTION_FAILURE
  jq -n '{
    task:"T23",
    proof:"offline deterministic validation and projection",
    steps:[
      {id:"W0",mode:"trace",input:"fixtures/expected/trace-v2.json",result:"PASS"},
      {id:"W0-glossary",mode:"glossary",input:"fixtures/expected/glossary.json",result:"PASS"},
      {id:"W3-ui",mode:"ui",input:"fixtures/expected/asis/ui.md",result:"PASS"},
      {id:"W3-sequence",mode:"mermaid",input:"fixtures/expected/asis/sequence.mmd",result:"PASS"},
      {id:"W3-dataflow",mode:"dataflow",input:"fixtures/expected/asis/dataflow.mmd",result:"PASS"},
      {id:"W3-story",mode:"story",input:"fixtures/expected/asis/story.md",result:"PASS"},
      {id:"W4",mode:"render",input:"UI, sequence, dataflow",result:"PASS"}
    ]
  }' >"$EVIDENCE_DIR/pipeline-steps.json" || return 70

  jq -n '{
    model_derivation:"UNVERIFIED",
    model_calls:0,
    claim_ko:"이 영수증은 고정 fixture trace와 golden의 오프라인 결정적 검증 및 투영만 증명한다. 모델이 source에서 trace나 산출물을 도출할 수 있음은 증명하지 않는다.",
    windows_receipt:"PENDING"
  }' >"$EVIDENCE_DIR/nonclaim.json" || return 70

  E2E_ASIS_CURRENT_ROWS=$RUN_TMP/e2e-asis-current-hashes.jsonl
  : >"$E2E_ASIS_CURRENT_ROWS" || return 70
  for E2E_ASIS_CURRENT_PATH in \
    fixtures/expected/trace-v2.json fixtures/expected/glossary.json \
    fixtures/expected/asis/ui.md fixtures/expected/asis/sequence.mmd \
    fixtures/expected/asis/dataflow.mmd fixtures/expected/asis/story.md \
    output/schemas/trace.schema.json output/recipes/trace.jq \
    output/recipes/glossary.jq output/recipes/provenance.jq \
    tests/cases/e2e-asis.sh tests/test.sh
  do
    e2e_asis_sha256 "$SOURCE_ROOT/$E2E_ASIS_CURRENT_PATH" || return 70
    jq -cn --arg path "$E2E_ASIS_CURRENT_PATH" --arg sha256 "$E2E_ASIS_SHA256" \
      '{path:$path,sha256:$sha256}' >>"$E2E_ASIS_CURRENT_ROWS" || return 70
  done
  jq -s '{algorithm:"sha256",files:.}' "$E2E_ASIS_CURRENT_ROWS" \
    >"$EVIDENCE_DIR/current-hashes.json" || return 70

  jq -n --arg result "$E2E_ASIS_OVERALL_RESULT" '{
    task:"T23",
    result:$result,
    acceptance:["validated canonical trace","technical and business fragments","glossary","four AS-IS provenance modes","three nonempty SVG renders","repeated normalized projection hashes","named negative failures"],
    model_derivation:"UNVERIFIED",
    windows_receipt:"PENDING",
    fixture_corpus_modified:false,
    independent_verification:"PENDING",
    commit:"N - prohibited before final task"
  }' >"$EVIDENCE_DIR/done-claim.json" || return 70
}

e2e_asis_clone_source() {
  E2E_ASIS_CLONE_ROOT=$1
  mkdir -p "$E2E_ASIS_CLONE_ROOT/output" "$E2E_ASIS_CLONE_ROOT/tests" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$E2E_ASIS_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests/." "$E2E_ASIS_CLONE_ROOT/tests/" || return 70
  cp -R "$SOURCE_ROOT/output/." "$E2E_ASIS_CLONE_ROOT/output/" || return 70
  cp -R "$SOURCE_ROOT/fixtures" "$E2E_ASIS_CLONE_ROOT/fixtures" || return 70
}

run_expected_asis_golden_drift() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  E2E_ASIS_EXPECT_ROOT=$RUN_TMP/expect-asis-golden-drift-source
  E2E_ASIS_EXPECT_EVIDENCE=$EVIDENCE_DIR/inner-asis-golden-drift
  e2e_asis_clone_source "$E2E_ASIS_EXPECT_ROOT" || return 70
  printf '\n검출 대상 golden drift\n' \
    >>"$E2E_ASIS_EXPECT_ROOT/fixtures/expected/asis/story.md" || return 70

  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test -n "${SENSAI_TEST_EXPECT_ASIS_FORCED_EXIT:-}"; then
    case "$SENSAI_TEST_EXPECT_ASIS_FORCED_EXIT" in
      64|70|127) E2E_ASIS_EXPECT_RC=$SENSAI_TEST_EXPECT_ASIS_FORCED_EXIT ;;
      *) E2E_ASIS_EXPECT_RC=70 ;;
    esac
    printf 'forced e2e-asis inner exit=%s\n' "$E2E_ASIS_EXPECT_RC" \
      >"$RUN_TMP/expect-asis-golden-drift.out"
  else
    set +e
    env SENSAI_TEST_SOURCE_ROOT="$E2E_ASIS_EXPECT_ROOT" \
      "$TEST_RUNNER" e2e-asis --evidence "$E2E_ASIS_EXPECT_EVIDENCE" \
      >"$RUN_TMP/expect-asis-golden-drift.out" 2>&1
    E2E_ASIS_EXPECT_RC=$?
  fi
  evidence_log_command expected-asis-golden-drift \
    "$TEST_RUNNER e2e-asis <isolated-corrupted-golden>" "$E2E_ASIS_EXPECT_RC"
  case "$E2E_ASIS_EXPECT_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$E2E_ASIS_EXPECT_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.asis_golden_drift_exit 1 "$E2E_ASIS_EXPECT_RC" || true
  if test -f "$E2E_ASIS_EXPECT_EVIDENCE/receipt.json"; then
    assert_jq expect.asis_golden_drift_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$E2E_ASIS_EXPECT_EVIDENCE/receipt.json" || true
    assert_jq expect.asis_golden_drift_named_failure \
      '.failed_assertion_ids == ["e2e.asis.golden_drift"]' \
      "$E2E_ASIS_EXPECT_EVIDENCE/receipt.json" || true
  else
    assert_record expect.asis_golden_drift_receipt 1 'missing expected-failure receipt' || true
  fi
}

case_e2e_asis() {
  e2e_asis_validate_trace || return 70
  e2e_asis_validate_source_lines || return 70
  e2e_asis_validate_projections || return 70
  e2e_asis_check_golden_hashes || return 70
  e2e_asis_render_projections || return 70
  e2e_asis_negative_checks || return 70
  e2e_asis_write_evidence || return 70
}
