#!/bin/sh

recipe_trace_run() {
  RECIPE_TRACE_NAME=$1
  RECIPE_TRACE_RECIPE=$2
  RECIPE_TRACE_OUTPUT=$3
  shift 3
  jq -e -f "$RECIPE_TRACE_RECIPE" "$@" >"$RECIPE_TRACE_OUTPUT" 2>"$RECIPE_TRACE_OUTPUT.err"
  RECIPE_TRACE_RC=$?
  evidence_log_command "$RECIPE_TRACE_NAME" "jq -e -f ${RECIPE_TRACE_RECIPE#"$SOURCE_ROOT"/} <input>" "$RECIPE_TRACE_RC"
  return 0
}

recipe_trace_run_slurp() {
  RECIPE_TRACE_NAME=$1
  RECIPE_TRACE_RECIPE=$2
  RECIPE_TRACE_OUTPUT=$3
  shift 3
  jq -s -e -f "$RECIPE_TRACE_RECIPE" "$@" >"$RECIPE_TRACE_OUTPUT" 2>"$RECIPE_TRACE_OUTPUT.err"
  RECIPE_TRACE_RC=$?
  evidence_log_command "$RECIPE_TRACE_NAME" "jq -s -e -f ${RECIPE_TRACE_RECIPE#"$SOURCE_ROOT"/} <trace> <glossary>" "$RECIPE_TRACE_RC"
  return 0
}

recipe_trace_assert_valid_trace() {
  RECIPE_TRACE_ID=$1
  RECIPE_TRACE_INPUT=$2
  CASE_TOTAL=$((CASE_TOTAL + 1))
  RECIPE_TRACE_RESULT="$RUN_TMP/$RECIPE_TRACE_ID.out"
  recipe_trace_run "$RECIPE_TRACE_ID" "$SOURCE_ROOT/output/recipes/trace.jq" "$RECIPE_TRACE_RESULT" "$RECIPE_TRACE_INPUT"
  assert_eq "$RECIPE_TRACE_ID" 0 "$RECIPE_TRACE_RC" || true
}

recipe_trace_assert_invalid_trace() {
  RECIPE_TRACE_ID=$1
  RECIPE_TRACE_INPUT=$2
  RECIPE_TRACE_FAILURE_ID=$3
  CASE_TOTAL=$((CASE_TOTAL + 1))
  RECIPE_TRACE_RESULT="$RUN_TMP/$RECIPE_TRACE_ID.out"
  recipe_trace_run "$RECIPE_TRACE_ID" "$SOURCE_ROOT/output/recipes/trace.jq" "$RECIPE_TRACE_RESULT" "$RECIPE_TRACE_INPUT"
  if test "$RECIPE_TRACE_RC" -ne 0 && rg -F "$RECIPE_TRACE_FAILURE_ID" "$RECIPE_TRACE_RESULT.err" >/dev/null 2>&1; then
    assert_record "$RECIPE_TRACE_ID" 0 "named_failure=$RECIPE_TRACE_FAILURE_ID exit=$RECIPE_TRACE_RC" || true
  else
    assert_record "$RECIPE_TRACE_ID" 1 "expected_failure=$RECIPE_TRACE_FAILURE_ID exit=$RECIPE_TRACE_RC" || true
  fi
}

recipe_trace_assert_valid_glossary() {
  RECIPE_TRACE_ID=$1
  RECIPE_TRACE_TRACE=$2
  RECIPE_TRACE_GLOSSARY=$3
  CASE_TOTAL=$((CASE_TOTAL + 1))
  RECIPE_TRACE_RESULT="$RUN_TMP/$RECIPE_TRACE_ID.out"
  recipe_trace_run_slurp "$RECIPE_TRACE_ID" "$SOURCE_ROOT/output/recipes/glossary.jq" "$RECIPE_TRACE_RESULT" \
    "$RECIPE_TRACE_TRACE" "$RECIPE_TRACE_GLOSSARY"
  assert_eq "$RECIPE_TRACE_ID" 0 "$RECIPE_TRACE_RC" || true
}

recipe_trace_assert_invalid_glossary() {
  RECIPE_TRACE_ID=$1
  RECIPE_TRACE_TRACE=$2
  RECIPE_TRACE_GLOSSARY=$3
  RECIPE_TRACE_FAILURE_ID=$4
  CASE_TOTAL=$((CASE_TOTAL + 1))
  RECIPE_TRACE_RESULT="$RUN_TMP/$RECIPE_TRACE_ID.out"
  recipe_trace_run_slurp "$RECIPE_TRACE_ID" "$SOURCE_ROOT/output/recipes/glossary.jq" "$RECIPE_TRACE_RESULT" \
    "$RECIPE_TRACE_TRACE" "$RECIPE_TRACE_GLOSSARY"
  if test "$RECIPE_TRACE_RC" -ne 0 && rg -F "$RECIPE_TRACE_FAILURE_ID" "$RECIPE_TRACE_RESULT.err" >/dev/null 2>&1; then
    assert_record "$RECIPE_TRACE_ID" 0 "named_failure=$RECIPE_TRACE_FAILURE_ID exit=$RECIPE_TRACE_RC" || true
  else
    assert_record "$RECIPE_TRACE_ID" 1 "expected_failure=$RECIPE_TRACE_FAILURE_ID exit=$RECIPE_TRACE_RC" || true
  fi
}

recipe_trace_check_internal_glossary() {
  RECIPE_TRACE_INTERNAL_GLOSSARY=$1
  CASE_TOTAL=$((CASE_TOTAL + 1))
  RECIPE_TRACE_RESULT="$RUN_TMP/internal-glossary.out"
  recipe_trace_run_slurp internal-glossary "$SOURCE_ROOT/output/recipes/glossary.jq" "$RECIPE_TRACE_RESULT" \
    "$SOURCE_ROOT/fixtures/expected/trace-v2.json" "$RECIPE_TRACE_INTERNAL_GLOSSARY"
  if test "$RECIPE_TRACE_RC" -eq 0; then
    assert_record glossary.document_valid 0 'glossary document satisfies recipe constraints' || true
    return 0
  fi
  for RECIPE_TRACE_FAILURE_ID in glossary.input glossary.shape glossary.unique_ids glossary.direct_evidence glossary.mapping; do
    if rg -F "$RECIPE_TRACE_FAILURE_ID" "$RECIPE_TRACE_RESULT.err" >/dev/null 2>&1; then
      assert_record "$RECIPE_TRACE_FAILURE_ID" 1 'glossary document violates recipe constraint' || true
    fi
  done
}

recipe_trace_check_files() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_file recipe.trace_file "$SOURCE_ROOT/output/recipes/trace.jq" || true
  assert_file recipe.glossary_file "$SOURCE_ROOT/output/recipes/glossary.jq" || true
  assert_file recipe.migration_file "$SOURCE_ROOT/output/recipes/migrate-trace-v1-to-v2.jq" || true
  for RECIPE_TRACE_ROOT_DUPLICATE in trace.jq glossary.jq migrate-trace-v1-to-v2.jq; do
    if test ! -e "$SOURCE_ROOT/recipes/$RECIPE_TRACE_ROOT_DUPLICATE"; then
      assert_record "recipe.no_root_duplicate_$RECIPE_TRACE_ROOT_DUPLICATE" 0 'root recipe duplicate absent' || true
    else
      assert_record "recipe.no_root_duplicate_$RECIPE_TRACE_ROOT_DUPLICATE" 1 'root recipe duplicate present' || true
    fi
  done
}

recipe_trace_check_trace_semantics() {
  RECIPE_TRACE_GOLDEN="$SOURCE_ROOT/fixtures/expected/trace-v2.json"
  recipe_trace_assert_valid_trace recipe.valid_trace "$RECIPE_TRACE_GOLDEN"

  RECIPE_TRACE_DANGLING="$RUN_TMP/trace-dangling.json"
  jq '.requirements[0].evidence_ids = ["E-NOT-FOUND"]' "$RECIPE_TRACE_GOLDEN" >"$RECIPE_TRACE_DANGLING" || return 70
  recipe_trace_assert_invalid_trace recipe.invalid_dangling "$RECIPE_TRACE_DANGLING" trace.recipe.reference_integrity

  RECIPE_TRACE_DUPLICATE="$RUN_TMP/trace-duplicate.json"
  jq '.business_rules[1].id = .business_rules[0].id' "$RECIPE_TRACE_GOLDEN" >"$RECIPE_TRACE_DUPLICATE" || return 70
  recipe_trace_assert_invalid_trace recipe.invalid_duplicate "$RECIPE_TRACE_DUPLICATE" trace.recipe.global_ids

  RECIPE_TRACE_NO_PROVENANCE="$RUN_TMP/trace-no-provenance.json"
  jq 'del(.provenance[0])' "$RECIPE_TRACE_GOLDEN" >"$RECIPE_TRACE_NO_PROVENANCE" || return 70
  recipe_trace_assert_invalid_trace recipe.invalid_direct_evidence "$RECIPE_TRACE_NO_PROVENANCE" trace.recipe.direct_evidence

  RECIPE_TRACE_EXACT_JOIN="$RUN_TMP/trace-exact-join.json"
  jq '.joins = [{id:"J-ORDER-001",kind:"asis",frontend_id:"FE-001",backend_id:"BE-001",evidence_ids:["E-REACT-ROUTE","E-VERTX-GET"],status:"exact"}]' \
    "$RECIPE_TRACE_GOLDEN" >"$RECIPE_TRACE_EXACT_JOIN" || return 70
  recipe_trace_assert_valid_trace recipe.valid_exact_join "$RECIPE_TRACE_EXACT_JOIN"

  RECIPE_TRACE_BAD_JOIN="$RUN_TMP/trace-bad-join.json"
  jq '.joins = [{id:"J-ORDER-001",kind:"asis",frontend_id:"FE-001",backend_id:"BE-001",evidence_ids:["E-REACT-ROUTE"],status:"exact"}]' \
    "$RECIPE_TRACE_GOLDEN" >"$RECIPE_TRACE_BAD_JOIN" || return 70
  recipe_trace_assert_invalid_trace recipe.invalid_exact_join "$RECIPE_TRACE_BAD_JOIN" trace.recipe.exact_join

  RECIPE_TRACE_BAD_TECHNICAL="$RUN_TMP/trace-bad-technical-mapping.json"
  jq '.business_flows[0].technical_ids = ["CONV-NAMING-999"]' "$RECIPE_TRACE_GOLDEN" >"$RECIPE_TRACE_BAD_TECHNICAL" || return 70
  recipe_trace_assert_invalid_trace recipe.invalid_technical_mapping "$RECIPE_TRACE_BAD_TECHNICAL" trace.recipe.mapping

  RECIPE_TRACE_BAD_BINDING="$RUN_TMP/trace-bad-binding.json"
  jq '.bindings[0].convention_id = "CONV-STATE-001"' "$RECIPE_TRACE_GOLDEN" >"$RECIPE_TRACE_BAD_BINDING" || return 70
  recipe_trace_assert_invalid_trace recipe.invalid_design_binding "$RECIPE_TRACE_BAD_BINDING" trace.recipe.binding
}

recipe_trace_check_glossary_semantics() {
  RECIPE_TRACE_GOLDEN="$SOURCE_ROOT/fixtures/expected/trace-v2.json"
  RECIPE_GLOSSARY_GOLDEN="$SOURCE_ROOT/fixtures/expected/glossary.json"
  recipe_trace_assert_valid_glossary recipe.valid_glossary "$RECIPE_TRACE_GOLDEN" "$RECIPE_GLOSSARY_GOLDEN"

  RECIPE_GLOSSARY_EVIDENCE_FREE="$RUN_TMP/glossary-evidence-free.json"
  jq '.terms[0].evidence_ids = []' "$RECIPE_GLOSSARY_GOLDEN" >"$RECIPE_GLOSSARY_EVIDENCE_FREE" || return 70
  recipe_trace_assert_invalid_glossary recipe.invalid_evidence_free_glossary "$RECIPE_TRACE_GOLDEN" \
    "$RECIPE_GLOSSARY_EVIDENCE_FREE" glossary.direct_evidence

  RECIPE_GLOSSARY_DUPLICATE="$RUN_TMP/glossary-duplicate.json"
  jq '.terms += [.terms[0]]' "$RECIPE_GLOSSARY_GOLDEN" >"$RECIPE_GLOSSARY_DUPLICATE" || return 70
  recipe_trace_assert_invalid_glossary recipe.invalid_duplicate_glossary "$RECIPE_TRACE_GOLDEN" \
    "$RECIPE_GLOSSARY_DUPLICATE" glossary.unique_ids

  RECIPE_GLOSSARY_BAD_MAPPING="$RUN_TMP/glossary-bad-mapping.json"
  jq '.terms[0].maps_to = ["BIZ-ENT-999"]' "$RECIPE_GLOSSARY_GOLDEN" >"$RECIPE_GLOSSARY_BAD_MAPPING" || return 70
  recipe_trace_assert_invalid_glossary recipe.invalid_glossary_mapping "$RECIPE_TRACE_GOLDEN" \
    "$RECIPE_GLOSSARY_BAD_MAPPING" glossary.mapping
}

recipe_trace_check_migration() {
  RECIPE_MIGRATION_SOURCE="$SOURCE_ROOT/fixtures/expected/trace-v1.json"
  RECIPE_MIGRATION_FIRST="$RUN_TMP/migrated-first.json"
  RECIPE_MIGRATION_SECOND="$RUN_TMP/migrated-second.json"
  RECIPE_MIGRATION_RICH="$RUN_TMP/migrated-rich-v2.json"
  RECIPE_MIGRATION_INVALID="$RUN_TMP/migration-invalid-v1.json"
  RECIPE_MIGRATION_SOURCE_COPY="$RUN_TMP/trace-v1-source-copy.json"
  cp "$RECIPE_MIGRATION_SOURCE" "$RECIPE_MIGRATION_SOURCE_COPY" || return 70

  CASE_TOTAL=$((CASE_TOTAL + 1))
  recipe_trace_run migration-first "$SOURCE_ROOT/output/recipes/migrate-trace-v1-to-v2.jq" \
    "$RECIPE_MIGRATION_FIRST" "$RECIPE_MIGRATION_SOURCE"
  assert_eq migration.valid_v1 0 "$RECIPE_TRACE_RC" || true

  CASE_TOTAL=$((CASE_TOTAL + 1))
  if cmp -s "$RECIPE_MIGRATION_SOURCE" "$RECIPE_MIGRATION_SOURCE_COPY"; then
    assert_record migration.source_unchanged 0 'source bytes unchanged' || true
  else
    assert_record migration.source_unchanged 1 'source bytes changed' || true
  fi

  CASE_TOTAL=$((CASE_TOTAL + 1))
  if jq -s -e '
    .[0] as $old | .[1] as $new
    | $new.schema_version == "2.0"
      and all(range(0; $old.requirements|length); $new.requirements[.] == ($old.requirements[.] + {kind:"asis"}))
      and all(range(0; $old.frontends|length); $new.frontends[.] == ($old.frontends[.] + {kind:"asis"}))
      and all(range(0; $old.backends|length); $new.backends[.] == ($old.backends[.] + {kind:"asis"}))
      and $new.provenance == $old.provenance
  ' "$RECIPE_MIGRATION_SOURCE" "$RECIPE_MIGRATION_FIRST" >/dev/null 2>&1; then
    assert_record migration.preservation 0 'legacy values preserved and asis kind added' || true
  else
    assert_record migration.preservation 1 'legacy preservation mismatch' || true
  fi

  CASE_TOTAL=$((CASE_TOTAL + 1))
  recipe_trace_run migration-second "$SOURCE_ROOT/output/recipes/migrate-trace-v1-to-v2.jq" \
    "$RECIPE_MIGRATION_SECOND" "$RECIPE_MIGRATION_FIRST"
  if test "$RECIPE_TRACE_RC" -eq 0 && cmp -s "$RECIPE_MIGRATION_FIRST" "$RECIPE_MIGRATION_SECOND"; then
    assert_record migration.idempotent 0 'second run is byte stable' || true
  else
    assert_record migration.idempotent 1 "second run mismatch exit=$RECIPE_TRACE_RC" || true
  fi

  CASE_TOTAL=$((CASE_TOTAL + 1))
  recipe_trace_run migration-rich-v2 "$SOURCE_ROOT/output/recipes/migrate-trace-v1-to-v2.jq" \
    "$RECIPE_MIGRATION_RICH" "$SOURCE_ROOT/fixtures/expected/trace-v2.json"
  if test "$RECIPE_TRACE_RC" -eq 0 && jq -s -e '.[0] == .[1]' \
    "$RECIPE_MIGRATION_RICH" "$SOURCE_ROOT/fixtures/expected/trace-v2.json" >/dev/null 2>&1; then
    assert_record migration.v2_unchanged 0 'existing v2 value is unchanged' || true
  else
    assert_record migration.v2_unchanged 1 "existing v2 changed exit=$RECIPE_TRACE_RC" || true
  fi

  jq 'del(.frontends[0].evidence)' "$RECIPE_MIGRATION_SOURCE" >"$RECIPE_MIGRATION_INVALID" || return 70
  CASE_TOTAL=$((CASE_TOTAL + 1))
  recipe_trace_run migration-invalid-v1 "$SOURCE_ROOT/output/recipes/migrate-trace-v1-to-v2.jq" \
    "$RUN_TMP/migration-invalid.out" "$RECIPE_MIGRATION_INVALID"
  if test "$RECIPE_TRACE_RC" -ne 0 && rg -F migration.invalid_v1 "$RUN_TMP/migration-invalid.out.err" >/dev/null 2>&1; then
    assert_record migration.invalid_v1 0 "named failure exit=$RECIPE_TRACE_RC" || true
  else
    assert_record migration.invalid_v1 1 "missing named failure exit=$RECIPE_TRACE_RC" || true
  fi
}

case_recipe_trace() {
  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test -n "${SENSAI_TEST_INTERNAL_GLOSSARY_INPUT:-}"; then
    recipe_trace_check_internal_glossary "$SENSAI_TEST_INTERNAL_GLOSSARY_INPUT"
    return $?
  fi

  recipe_trace_check_files || return 70
  recipe_trace_check_trace_semantics || return 70
  recipe_trace_check_glossary_semantics || return 70
  recipe_trace_check_migration || return 70
}
