#!/bin/sh

schema_trace_run_validator() {
  SCHEMA_TRACE_INPUT=$1
  SCHEMA_TRACE_OUTPUT=$2
  set +e
  jq -f "$SOURCE_ROOT/tests/validators/trace-schema-parity.jq" "$SCHEMA_TRACE_INPUT" >"$SCHEMA_TRACE_OUTPUT" 2>"$SCHEMA_TRACE_OUTPUT.err"
  SCHEMA_TRACE_RC=$?
  evidence_log_command trace-schema-parity "jq -f tests/validators/trace-schema-parity.jq <trace>" "$SCHEMA_TRACE_RC"
  test "$SCHEMA_TRACE_RC" -eq 0 || return 70
  jq -e 'type == "array" and all(.[]; type == "string")' "$SCHEMA_TRACE_OUTPUT" >/dev/null 2>&1 || return 70
  return 0
}

schema_trace_assert_valid() {
  SCHEMA_TRACE_VALID_ID=$1
  SCHEMA_TRACE_VALID_FILE=$2
  CASE_TOTAL=$((CASE_TOTAL + 1))
  SCHEMA_TRACE_VALID_ERRORS="$RUN_TMP/$SCHEMA_TRACE_VALID_ID-errors.json"
  schema_trace_run_validator "$SCHEMA_TRACE_VALID_FILE" "$SCHEMA_TRACE_VALID_ERRORS" || return 70
  assert_jq "$SCHEMA_TRACE_VALID_ID" 'length == 0' "$SCHEMA_TRACE_VALID_ERRORS" || true
}

schema_trace_assert_mutation() {
  SCHEMA_TRACE_MUTATION_ID=$1
  SCHEMA_TRACE_MUTATION_FILTER=$2
  SCHEMA_TRACE_EXPECTED_ID=$3
  SCHEMA_TRACE_MUTATED="$RUN_TMP/$SCHEMA_TRACE_MUTATION_ID.json"
  SCHEMA_TRACE_ERRORS="$RUN_TMP/$SCHEMA_TRACE_MUTATION_ID-errors.json"
  CASE_TOTAL=$((CASE_TOTAL + 1))
  jq "$SCHEMA_TRACE_MUTATION_FILTER" "$SOURCE_ROOT/fixtures/expected/trace-v2.json" >"$SCHEMA_TRACE_MUTATED" || return 70
  schema_trace_run_validator "$SCHEMA_TRACE_MUTATED" "$SCHEMA_TRACE_ERRORS" || return 70
  assert_jq "$SCHEMA_TRACE_MUTATION_ID" ". | index(\"$SCHEMA_TRACE_EXPECTED_ID\") != null" "$SCHEMA_TRACE_ERRORS" || true
}

schema_trace_check_schema_contract() {
  SCHEMA_TRACE_SCHEMA="$SOURCE_ROOT/output/schemas/trace.schema.json"
  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_file schema.trace_file "$SCHEMA_TRACE_SCHEMA" || true
  assert_file schema.trace_parity_validator "$SOURCE_ROOT/tests/validators/trace-schema-parity.jq" || true
  if ! jq empty "$SCHEMA_TRACE_SCHEMA" >/dev/null 2>&1; then
    assert_record schema.trace_json 1 'trace schema JSON syntax invalid' || true
    return 0
  fi
  assert_record schema.trace_json 0 'trace schema JSON syntax valid' || true
  assert_jq schema.trace_draft '.["$schema"] == "https://json-schema.org/draft/2020-12/schema"' "$SCHEMA_TRACE_SCHEMA" || true
  assert_jq schema.trace_root_closed '.additionalProperties == false' "$SCHEMA_TRACE_SCHEMA" || true
  assert_jq schema.trace_defs_closed '
    ([.["$defs"] | to_entries[] | select(.value.type == "object") | .value.additionalProperties] | all(. == false)) and
    ([.["$defs"] | to_entries[] | select(.value.type == "object")] | length) == 19
  ' "$SCHEMA_TRACE_SCHEMA" || true
  assert_jq schema.trace_statuses '.["$defs"].status.enum == ["exact","unresolved","ambiguous","many_to_many","conflict"]' "$SCHEMA_TRACE_SCHEMA" || true
  assert_jq schema.trace_kinds '.["$defs"].kind.enum == ["asis","tobe"]' "$SCHEMA_TRACE_SCHEMA" || true
  assert_jq schema.trace_categories '.["$defs"].convention.properties.category.enum == ["COMPONENT","STRUCTURE","NAMING","API","STATE","ERROR","TEST"]' "$SCHEMA_TRACE_SCHEMA" || true
  assert_jq schema.trace_bindings '
    (.["$defs"].binding.oneOf | length) == 2 and
    (.["$defs"].binding.properties.gate.enum == ["pass","violation"])
  ' "$SCHEMA_TRACE_SCHEMA" || true
  assert_jq schema.trace_korean_metadata '
    (.title | test("[가-힣]")) and (.description | test("[가-힣]")) and (.["$comment"] | test("[가-힣]"))
  ' "$SCHEMA_TRACE_SCHEMA" || true
}

schema_trace_check_override() {
  SCHEMA_TRACE_OVERRIDE=$1
  CASE_TOTAL=$((CASE_TOTAL + 1))
  SCHEMA_TRACE_OVERRIDE_ERRORS="$RUN_TMP/trace-override-errors.json"
  if ! test -f "$SCHEMA_TRACE_OVERRIDE" || test -L "$SCHEMA_TRACE_OVERRIDE"; then
    return 70
  fi
  schema_trace_run_validator "$SCHEMA_TRACE_OVERRIDE" "$SCHEMA_TRACE_OVERRIDE_ERRORS" || return 70
  if jq -e 'length == 0' "$SCHEMA_TRACE_OVERRIDE_ERRORS" >/dev/null 2>&1; then
    assert_record trace.document_valid 0 'trace document satisfies schema parity constraints' || true
    return 0
  fi
  while IFS= read -r SCHEMA_TRACE_ERROR_ID; do
    test -n "$SCHEMA_TRACE_ERROR_ID" || continue
    assert_record "$SCHEMA_TRACE_ERROR_ID" 1 'trace document violates schema parity constraint' || true
  done <<EOF
$(jq -r '.[]' "$SCHEMA_TRACE_OVERRIDE_ERRORS")
EOF
}

case_schema_trace() {
  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test -n "${SENSAI_TEST_INTERNAL_TRACE_INPUT:-}"; then
    schema_trace_check_override "$SENSAI_TEST_INTERNAL_TRACE_INPUT"
    return $?
  fi

  schema_trace_check_schema_contract || return 70

  SCHEMA_TRACE_GOLDEN="$SOURCE_ROOT/fixtures/expected/trace-v2.json"
  schema_trace_assert_valid schema.valid_golden "$SCHEMA_TRACE_GOLDEN" || return 70

  if jq -e '
    (.conventions | map(.category) | sort) ==
      (["COMPONENT","STRUCTURE","NAMING","API","STATE","ERROR","TEST"] | sort) and
    ([.evidence[].kind] | unique | sort) == ["asis","tobe"] and
    ([.business_rules[].status] | index("conflict")) != null and
    ([.unknowns[].status] | index("unresolved")) != null and
    (.designs | length) > 0 and (.bindings | length) > 0
  ' "$SCHEMA_TRACE_GOLDEN" >/dev/null 2>&1; then
    assert_record schema.golden_semantic_coverage 0 'golden covers seven categories, both kinds, conflict, unresolved, designs, and bindings' || true
  else
    assert_record schema.golden_semantic_coverage 1 'golden semantic coverage incomplete' || true
  fi

  for SCHEMA_TRACE_STATUS in ambiguous many_to_many; do
    SCHEMA_TRACE_STATUS_FILE="$RUN_TMP/status-$SCHEMA_TRACE_STATUS.json"
    jq --arg status "$SCHEMA_TRACE_STATUS" '.unknowns[0].status = $status' "$SCHEMA_TRACE_GOLDEN" >"$SCHEMA_TRACE_STATUS_FILE" || return 70
    schema_trace_assert_valid "schema.valid_status_$SCHEMA_TRACE_STATUS" "$SCHEMA_TRACE_STATUS_FILE" || return 70
  done

  SCHEMA_TRACE_JOIN_FILE="$RUN_TMP/valid-join.json"
  jq '.joins = [{id:"J-ORDER-001",kind:"asis",frontend_id:"FE-001",backend_id:"BE-001",evidence_ids:["E-REACT-ROUTE"],status:"many_to_many"}]' \
    "$SCHEMA_TRACE_GOLDEN" >"$SCHEMA_TRACE_JOIN_FILE" || return 70
  schema_trace_assert_valid schema.valid_many_to_many_join "$SCHEMA_TRACE_JOIN_FILE" || return 70

  SCHEMA_TRACE_GLOSSARY_FILE="$RUN_TMP/valid-glossary-ref.json"
  jq '.glossary_ref = {path:"docs/analysis/missions/fixture-mission/glossary.json",sha256:("0" * 64)}' \
    "$SCHEMA_TRACE_GOLDEN" >"$SCHEMA_TRACE_GLOSSARY_FILE" || return 70
  schema_trace_assert_valid schema.valid_glossary_ref "$SCHEMA_TRACE_GLOSSARY_FILE" || return 70

  schema_trace_assert_mutation schema.mutation_missing 'del(.conventions[0].kind)' trace.required || return 70
  schema_trace_assert_mutation schema.mutation_type '.conventions = {}' trace.array_type || return 70
  schema_trace_assert_mutation schema.mutation_empty '.conventions[0].evidence_ids = []' trace.nonempty || return 70
  schema_trace_assert_mutation schema.mutation_additional '.conventions[0].rogue = true' trace.additional_properties || return 70
  schema_trace_assert_mutation schema.mutation_id '.business_rules[0].id = "BAD"' trace.id_pattern || return 70
  schema_trace_assert_mutation schema.mutation_status '.conventions[0].status = "guessed"' trace.status || return 70
  schema_trace_assert_mutation schema.mutation_kind '.designs[0].kind = "asis"' trace.kind || return 70
  schema_trace_assert_mutation schema.mutation_dangling '.requirements[0].evidence_ids = ["E-NOT-FOUND"]' trace.reference_integrity || return 70
  schema_trace_assert_mutation schema.mutation_duplicate_id '.business_rules[1].id = .business_rules[0].id' trace.unique_ids || return 70
  schema_trace_assert_mutation schema.mutation_binding '.bindings[0].business_id = "BIZ-INVARIANT-001"' trace.binding || return 70
}

schema_trace_clone_source() {
  SCHEMA_TRACE_CLONE_ROOT=$1
  mkdir -p "$SCHEMA_TRACE_CLONE_ROOT/output/schemas" "$SCHEMA_TRACE_CLONE_ROOT/fixtures/expected" \
    "$SCHEMA_TRACE_CLONE_ROOT/fixtures/adversarial" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$SCHEMA_TRACE_CLONE_ROOT/AGENTS.md" || return 70
  cp "$SOURCE_ROOT/output/schemas/trace.schema.json" "$SCHEMA_TRACE_CLONE_ROOT/output/schemas/trace.schema.json" || return 70
  cp -R "$SOURCE_ROOT/tests" "$SCHEMA_TRACE_CLONE_ROOT/tests" || return 70
  cp "$SOURCE_ROOT/fixtures/expected/trace-v2.json" "$SCHEMA_TRACE_CLONE_ROOT/fixtures/expected/trace-v2.json" || return 70
  cp "$SOURCE_ROOT/fixtures/adversarial/dangling-reference.json" "$SCHEMA_TRACE_CLONE_ROOT/fixtures/adversarial/dangling-reference.json" || return 70
}
