#!/bin/sh

provenance_run() {
  PROVENANCE_RUN_NAME=$1
  PROVENANCE_RUN_MODE=$2
  PROVENANCE_RUN_KIND=$3
  PROVENANCE_RUN_ARTIFACT=$4
  PROVENANCE_RUN_UPSTREAM=$5
  PROVENANCE_RUN_TRACE=$6
  PROVENANCE_RUN_OUTPUT="$RUN_TMP/$PROVENANCE_RUN_NAME.out"
  jq -e --arg mode "$PROVENANCE_RUN_MODE" --arg kind "$PROVENANCE_RUN_KIND" \
    --rawfile artifact "$PROVENANCE_RUN_ARTIFACT" --rawfile upstream "$PROVENANCE_RUN_UPSTREAM" \
    -f "$SOURCE_ROOT/output/recipes/provenance.jq" "$PROVENANCE_RUN_TRACE" \
    >"$PROVENANCE_RUN_OUTPUT" 2>"$PROVENANCE_RUN_OUTPUT.err"
  PROVENANCE_RUN_RC=$?
  evidence_log_command "$PROVENANCE_RUN_NAME" \
    "jq -e --arg mode $PROVENANCE_RUN_MODE --arg kind $PROVENANCE_RUN_KIND --rawfile artifact <artifact> --rawfile upstream <upstream> -f output/recipes/provenance.jq <trace>" \
    "$PROVENANCE_RUN_RC"
  return 0
}

provenance_assert_valid() {
  PROVENANCE_VALID_ID=$1
  shift
  CASE_TOTAL=$((CASE_TOTAL + 1))
  provenance_run "$PROVENANCE_VALID_ID" "$@"
  assert_eq "$PROVENANCE_VALID_ID" 0 "$PROVENANCE_RUN_RC" || true
}

provenance_assert_invalid() {
  PROVENANCE_INVALID_ID=$1
  PROVENANCE_FAILURE_ID=$2
  shift 2
  CASE_TOTAL=$((CASE_TOTAL + 1))
  provenance_run "$PROVENANCE_INVALID_ID" "$@"
  if test "$PROVENANCE_RUN_RC" -ne 0 && rg -F "$PROVENANCE_FAILURE_ID" "$PROVENANCE_RUN_OUTPUT.err" >/dev/null 2>&1; then
    assert_record "$PROVENANCE_FAILURE_ID" 0 "named_failure=$PROVENANCE_FAILURE_ID exit=$PROVENANCE_RUN_RC" || true
  else
    assert_record "$PROVENANCE_FAILURE_ID" 1 "expected_failure=$PROVENANCE_FAILURE_ID exit=$PROVENANCE_RUN_RC" || true
  fi
}

provenance_empty_upstream() {
  PROVENANCE_EMPTY_UPSTREAM="$RUN_TMP/provenance-empty-upstream.txt"
  : >"$PROVENANCE_EMPTY_UPSTREAM" || return 70
}

provenance_check_files() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_file provenance.recipe_file "$SOURCE_ROOT/output/recipes/provenance.jq" || true
  if test ! -e "$SOURCE_ROOT/recipes/provenance.jq"; then
    assert_record provenance.no_root_duplicate 0 'root recipe duplicate absent' || true
  else
    assert_record provenance.no_root_duplicate 1 'root recipe duplicate present' || true
  fi
}

provenance_check_five_modes() {
  PROVENANCE_TRACE="$SOURCE_ROOT/fixtures/expected/trace-v2.json"
  provenance_assert_valid provenance.valid_ui ui asis \
    "$SOURCE_ROOT/fixtures/expected/asis/ui.md" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"
  provenance_assert_valid provenance.valid_mermaid mermaid asis \
    "$SOURCE_ROOT/fixtures/expected/asis/sequence.mmd" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"
  provenance_assert_valid provenance.valid_dataflow dataflow asis \
    "$SOURCE_ROOT/fixtures/expected/asis/dataflow.mmd" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"
  provenance_assert_valid provenance.valid_story story tobe \
    "$SOURCE_ROOT/fixtures/expected/tobe/story.md" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"
  provenance_assert_valid provenance.valid_test test tobe \
    "$SOURCE_ROOT/fixtures/expected/tobe/test.md" "$SOURCE_ROOT/fixtures/expected/tobe/story.md" "$PROVENANCE_TRACE"
}

provenance_check_failures() {
  PROVENANCE_TRACE="$SOURCE_ROOT/fixtures/expected/trace-v2.json"
  PROVENANCE_UI="$SOURCE_ROOT/fixtures/expected/tobe/ui.md"
  PROVENANCE_SEQUENCE="$SOURCE_ROOT/fixtures/expected/asis/sequence.mmd"
  PROVENANCE_STORY="$SOURCE_ROOT/fixtures/expected/tobe/story.md"

  sed 's/E-CHANGE-DETAIL/E-NOT-FOUND/' "$PROVENANCE_UI" >"$RUN_TMP/evidence-missing.md" || return 70
  provenance_assert_invalid provenance.invalid_evidence_missing provenance.evidence_missing ui tobe \
    "$RUN_TMP/evidence-missing.md" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  sed 's/evidence_id: `E-CHANGE-DETAIL`/evidence_id: `E-CHANGE-DETAIL` `E-CHANGE-DETAIL`/' \
    "$PROVENANCE_UI" >"$RUN_TMP/evidence-duplicate.md" || return 70
  provenance_assert_invalid provenance.invalid_evidence_duplicate provenance.evidence_duplicate ui tobe \
    "$RUN_TMP/evidence-duplicate.md" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  jq '.evidence += [{id:"E-CHANGE-ALT",kind:"tobe",path:"inputs/change/valid.md",line:4,path_line:"inputs/change/valid.md:4"}] | .provenance += [{path:"inputs/change/valid.md",line:4,path_line:"inputs/change/valid.md:4"}]' \
    "$PROVENANCE_TRACE" >"$RUN_TMP/evidence-mismatch-trace.json" || return 70
  sed 's/E-CHANGE-DETAIL/E-CHANGE-ALT/' "$PROVENANCE_UI" >"$RUN_TMP/evidence-mismatch.md" || return 70
  provenance_assert_invalid provenance.invalid_evidence_mismatch provenance.evidence_mismatch ui tobe \
    "$RUN_TMP/evidence-mismatch.md" "$PROVENANCE_EMPTY_UPSTREAM" "$RUN_TMP/evidence-mismatch-trace.json"

  sed '/^%% provenance:/d' "$PROVENANCE_SEQUENCE" >"$RUN_TMP/source-missing.mmd" || return 70
  provenance_assert_invalid provenance.invalid_source_missing provenance.source_missing mermaid asis \
    "$RUN_TMP/source-missing.mmd" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  sed '/^%% provenance:/p' "$PROVENANCE_SEQUENCE" >"$RUN_TMP/source-duplicate.mmd" || return 70
  provenance_assert_invalid provenance.invalid_source_duplicate provenance.source_duplicate mermaid asis \
    "$RUN_TMP/source-duplicate.mmd" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  sed 's#inputs/legacy-vertx/src/main/java/example/OrderVerticle.java:10#inputs/legacy-react/src/OrdersPage.tsx:3#' \
    "$PROVENANCE_SEQUENCE" >"$RUN_TMP/source-mismatch.mmd" || return 70
  provenance_assert_invalid provenance.invalid_source_mismatch provenance.source_mismatch mermaid asis \
    "$RUN_TMP/source-mismatch.mmd" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  sed 's/kind: asis/kind: tobe/' "$PROVENANCE_SEQUENCE" >"$RUN_TMP/kind-mismatch.mmd" || return 70
  provenance_assert_invalid provenance.invalid_kind_mismatch provenance.kind_mismatch mermaid asis \
    "$RUN_TMP/kind-mismatch.mmd" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  sed '/^sequenceDiagram$/p' "$PROVENANCE_SEQUENCE" >"$RUN_TMP/mermaid-duplicate.mmd" || return 70
  provenance_assert_invalid provenance.invalid_mermaid_duplicate provenance.mermaid_duplicate mermaid asis \
    "$RUN_TMP/mermaid-duplicate.mmd" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  sed 's/ (`REQ-EXT-0001`, `DESIGN-PAGE-001`)//' "$PROVENANCE_STORY" >"$RUN_TMP/id-missing.md" || return 70
  provenance_assert_invalid provenance.invalid_id_missing provenance.id_missing story tobe \
    "$RUN_TMP/id-missing.md" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  jq '.designs += [.designs[0]]' "$PROVENANCE_TRACE" >"$RUN_TMP/id-duplicate-trace.json" || return 70
  provenance_assert_invalid provenance.invalid_id_duplicate provenance.id_duplicate story tobe \
    "$PROVENANCE_STORY" "$PROVENANCE_EMPTY_UPSTREAM" "$RUN_TMP/id-duplicate-trace.json"

  sed 's/DESIGN-PAGE-001/DESIGN-PAGE-999/' "$PROVENANCE_STORY" >"$RUN_TMP/id-mismatch.md" || return 70
  provenance_assert_invalid provenance.invalid_id_mismatch provenance.id_mismatch story tobe \
    "$RUN_TMP/id-mismatch.md" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  sed '/-->/d' "$SOURCE_ROOT/fixtures/expected/asis/dataflow.mmd" >"$RUN_TMP/arrow-missing.mmd" || return 70
  provenance_assert_invalid provenance.invalid_arrow_missing provenance.arrow_missing dataflow asis \
    "$RUN_TMP/arrow-missing.mmd" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  sed '/UI\[OrdersPage\] -->/p' "$SOURCE_ROOT/fixtures/expected/asis/dataflow.mmd" >"$RUN_TMP/arrow-duplicate.mmd" || return 70
  provenance_assert_invalid provenance.invalid_arrow_duplicate provenance.arrow_duplicate dataflow asis \
    "$RUN_TMP/arrow-duplicate.mmd" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"

  sed 's/BIZ-FLOW-001/CONV-NAMING-001/' "$SOURCE_ROOT/fixtures/expected/asis/dataflow.mmd" >"$RUN_TMP/arrow-mismatch.mmd" || return 70
  provenance_assert_invalid provenance.invalid_arrow_mismatch provenance.arrow_mismatch dataflow asis \
    "$RUN_TMP/arrow-mismatch.mmd" "$PROVENANCE_EMPTY_UPSTREAM" "$PROVENANCE_TRACE"
}

provenance_check_render() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if ! command -v mmdc >/dev/null 2>&1; then
    RUNNER_INFRA_REASON=MISSING_COMMAND_mmdc
    evidence_add_reason "$RUNNER_INFRA_REASON"
    return 70
  fi
  PROVENANCE_RENDER_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sensai-provenance-render.XXXXXX") || return 70
  case "$PROVENANCE_RENDER_ROOT" in
    "${TMPDIR:-/tmp}"/sensai-provenance-render.*) ;;
    *) RUNNER_INFRA_REASON=UNSAFE_RENDER_TEMP; return 70 ;;
  esac
  PROVENANCE_RENDER_SVG="$PROVENANCE_RENDER_ROOT/sequence.svg"
  mmdc -i "$SOURCE_ROOT/fixtures/expected/asis/sequence.mmd" -o "$PROVENANCE_RENDER_SVG" \
    >"$RUN_TMP/mmdc.out" 2>"$RUN_TMP/mmdc.err"
  PROVENANCE_RENDER_RC=$?
  evidence_log_command provenance.mmdc_render 'mmdc -i fixtures/expected/asis/sequence.mmd -o <external-temp>/sequence.svg' "$PROVENANCE_RENDER_RC"
  if test "$PROVENANCE_RENDER_RC" -eq 0 && test -s "$PROVENANCE_RENDER_SVG"; then
    PROVENANCE_RENDER_SHA=$(shasum -a 256 "$PROVENANCE_RENDER_SVG" | awk '{print $1}') || return 70
    PROVENANCE_RENDER_SIZE=$(wc -c <"$PROVENANCE_RENDER_SVG" | awk '{print $1}') || return 70
    jq -n --arg command_path "$(command -v mmdc)" --arg version "$(mmdc --version 2>&1)" \
      --arg sha256 "$PROVENANCE_RENDER_SHA" --argjson size "$PROVENANCE_RENDER_SIZE" \
      --argjson exit "$PROVENANCE_RENDER_RC" \
      '{command:"mmdc",command_path:$command_path,version:$version,exit:$exit,svg_sha256:$sha256,svg_size:$size,artifact_persisted:false}' \
      >"$EVIDENCE_DIR/render-receipt.json" || return 70
    assert_record provenance.mmdc_render 0 "exit=0 svg_size=$PROVENANCE_RENDER_SIZE svg_sha256=$PROVENANCE_RENDER_SHA" || true
  else
    assert_record provenance.mmdc_render 1 "exit=$PROVENANCE_RENDER_RC nonempty_svg=false" || true
  fi
  rm -rf "$PROVENANCE_RENDER_ROOT" || return 70
  if test ! -e "$PROVENANCE_RENDER_ROOT"; then
    assert_record provenance.render_cleanup 0 'external render temp removed' || true
  else
    assert_record provenance.render_cleanup 1 'external render temp remains' || true
  fi
}

provenance_check_internal() {
  provenance_empty_upstream || return 70
  PROVENANCE_INTERNAL_UPSTREAM=${SENSAI_TEST_INTERNAL_PROVENANCE_UPSTREAM:-$PROVENANCE_EMPTY_UPSTREAM}
  provenance_run provenance.internal "${SENSAI_TEST_INTERNAL_PROVENANCE_MODE:-mermaid}" \
    "${SENSAI_TEST_INTERNAL_PROVENANCE_KIND:-asis}" "$SENSAI_TEST_INTERNAL_PROVENANCE_INPUT" \
    "$PROVENANCE_INTERNAL_UPSTREAM" "$SOURCE_ROOT/fixtures/expected/trace-v2.json"
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test "$PROVENANCE_RUN_RC" -eq 0; then
    assert_record provenance.document_valid 0 'provenance document satisfies recipe constraints' || true
    return 0
  fi
  for PROVENANCE_INTERNAL_FAILURE in \
    provenance.mode provenance.kind_mismatch provenance.source_missing provenance.source_duplicate \
    provenance.source_mismatch provenance.evidence_missing provenance.evidence_duplicate \
    provenance.evidence_mismatch provenance.id_missing provenance.id_duplicate provenance.id_mismatch \
    provenance.mermaid_duplicate provenance.arrow_missing provenance.arrow_duplicate provenance.arrow_mismatch
  do
    if rg -F "$PROVENANCE_INTERNAL_FAILURE" "$PROVENANCE_RUN_OUTPUT.err" >/dev/null 2>&1; then
      assert_record "$PROVENANCE_INTERNAL_FAILURE" 1 'provenance document violates exact constraint' || true
    fi
  done
}

case_provenance() {
  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test -n "${SENSAI_TEST_INTERNAL_PROVENANCE_INPUT:-}"; then
    provenance_check_internal
    return $?
  fi
  provenance_empty_upstream || return 70
  provenance_check_files || return 70
  provenance_check_five_modes || return 70
  provenance_check_failures || return 70
  provenance_check_render || return 70
  return 0
}
