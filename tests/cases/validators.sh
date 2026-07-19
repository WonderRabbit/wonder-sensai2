#!/bin/sh

validators_clone_source() {
  VALIDATORS_CLONE_ROOT=$1
  mkdir -p "$VALIDATORS_CLONE_ROOT/output" "$VALIDATORS_CLONE_ROOT/fixtures" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$VALIDATORS_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$VALIDATORS_CLONE_ROOT/tests" || return 70
  cp -R "$SOURCE_ROOT/output/schemas" "$VALIDATORS_CLONE_ROOT/output/schemas" || return 70
  cp -R "$SOURCE_ROOT/output/recipes" "$VALIDATORS_CLONE_ROOT/output/recipes" || return 70
  cp -R "$SOURCE_ROOT/fixtures/." "$VALIDATORS_CLONE_ROOT/fixtures/" || return 70
}

validators_bypass_issue() {
  VALIDATORS_BYPASS_FILE=$1
  VALIDATORS_BYPASS_ID=$2
  VALIDATORS_BYPASS_TMP="$VALIDATORS_BYPASS_FILE.tmp"
  awk -v target="$VALIDATORS_BYPASS_ID" '
    BEGIN { found = 0; skip = 0 }
    skip > 0 { skip -= 1; next }
    $0 == "def issue($id; f):" || $0 == "def issue($id; condition):" {
      print "def issue($id; f):"
      print "  if $id == \"" target "\" then []"
      print "  elif (try f catch false) then [] else [$id] end;"
      found = 1
      skip = 1
      next
    }
    { print }
    END { if (found != 1) exit 2 }
  ' "$VALIDATORS_BYPASS_FILE" >"$VALIDATORS_BYPASS_TMP" || {
    rm -f "$VALIDATORS_BYPASS_TMP"
    return 70
  }
  mv "$VALIDATORS_BYPASS_TMP" "$VALIDATORS_BYPASS_FILE" || return 70
}

validators_slug() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g; s/[.]/_/g'
}

validators_run_nested() {
  VALIDATORS_NESTED_NAME=$1
  VALIDATORS_NESTED_SELECTOR=$2
  VALIDATORS_NESTED_SOURCE=$3
  VALIDATORS_NESTED_EVIDENCE=$4
  VALIDATORS_NESTED_OUTPUT="$RUN_TMP/$VALIDATORS_NESTED_NAME.out"
  set +e
  env SENSAI_TEST_SOURCE_ROOT="$VALIDATORS_NESTED_SOURCE" \
    "$TEST_RUNNER" "$VALIDATORS_NESTED_SELECTOR" --evidence "$VALIDATORS_NESTED_EVIDENCE" \
    >"$VALIDATORS_NESTED_OUTPUT" 2>&1
  VALIDATORS_NESTED_RC=$?
  evidence_log_command "$VALIDATORS_NESTED_NAME" \
    "$TEST_RUNNER $VALIDATORS_NESTED_SELECTOR <external-mutant-source>" "$VALIDATORS_NESTED_RC"
}

validators_receipt_has_failure() {
  VALIDATORS_RECEIPT=$1
  VALIDATORS_FAILURE=$2
  test -f "$VALIDATORS_RECEIPT" && jq -e --arg id "$VALIDATORS_FAILURE" \
    '(.failed_assertion_ids | index($id)) != null' "$VALIDATORS_RECEIPT" >/dev/null 2>&1
}

validators_health_check() {
  VALIDATORS_HEALTH_INPUT="$RUN_TMP/validator-noop-canary.json"
  VALIDATORS_HEALTH_OUTPUT="$RUN_TMP/validator-noop-canary-errors.json"
  jq '.requirements[0].evidence_ids = ["E-NOT-FOUND"]' \
    "$SOURCE_ROOT/fixtures/expected/trace-v2.json" >"$VALIDATORS_HEALTH_INPUT" || return 70
  jq -f "$SOURCE_ROOT/tests/validators/trace-schema-parity.jq" \
    "$VALIDATORS_HEALTH_INPUT" >"$VALIDATORS_HEALTH_OUTPUT" 2>"$VALIDATORS_HEALTH_OUTPUT.err"
  VALIDATORS_HEALTH_RC=$?
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test "$VALIDATORS_HEALTH_RC" -eq 0 && jq -e \
    'type == "array" and index("trace.reference_integrity") != null' \
    "$VALIDATORS_HEALTH_OUTPUT" >/dev/null 2>&1; then
    assert_record validators.noop_detected 0 'negative canary was rejected by the canonical validator' || true
  else
    assert_record validators.noop_detected 1 \
      "negative canary was false-green exit=$VALIDATORS_HEALTH_RC" || true
  fi
}

validators_record_hashes() {
  VALIDATORS_HASH_PHASE=$1
  VALIDATORS_HASH_OUTPUT=$2
  : >"$VALIDATORS_HASH_OUTPUT" || return 70
  for VALIDATORS_HASH_PATH in \
    tests/validators/trace-schema-parity.jq \
    tests/validators/progress-schema-parity.jq \
    output/recipes/trace.jq \
    output/recipes/glossary.jq \
    output/recipes/migrate-trace-v1-to-v2.jq \
    output/recipes/provenance.jq
  do
    tooling_sha256_file "$SOURCE_ROOT/$VALIDATORS_HASH_PATH" || return 70
    jq -cn --arg phase "$VALIDATORS_HASH_PHASE" --arg path "$VALIDATORS_HASH_PATH" \
      --arg sha256 "$TOOLING_SHA256" '{phase:$phase,path:$path,sha256:$sha256}' \
      >>"$VALIDATORS_HASH_OUTPUT" || return 70
  done
}

validators_run_issue_mutation() {
  VALIDATORS_MUTATION_NAME=$1
  VALIDATORS_MUTATION_TARGET=$2
  VALIDATORS_MUTATION_ID=$3
  VALIDATORS_MUTATION_SELECTOR=$4
  VALIDATORS_MUTATION_FAILURE=$5
  VALIDATORS_MUTATION_SLUG=$(validators_slug "$VALIDATORS_MUTATION_NAME") || return 70
  VALIDATORS_MUTATION_FILE="$VALIDATORS_EXTERNAL_ROOT/$VALIDATORS_MUTATION_TARGET"
  VALIDATORS_MUTANT_EVIDENCE="$EVIDENCE_DIR/mutant-$VALIDATORS_MUTATION_SLUG"
  VALIDATORS_RESTORED_EVIDENCE="$EVIDENCE_DIR/restored-$VALIDATORS_MUTATION_SLUG"

  cp "$SOURCE_ROOT/$VALIDATORS_MUTATION_TARGET" "$VALIDATORS_MUTATION_FILE" || return 70
  validators_bypass_issue "$VALIDATORS_MUTATION_FILE" "$VALIDATORS_MUTATION_ID" || return 70
  validators_run_nested "mutant-$VALIDATORS_MUTATION_SLUG" "$VALIDATORS_MUTATION_SELECTOR" \
    "$VALIDATORS_EXTERNAL_ROOT" "$VALIDATORS_MUTANT_EVIDENCE"
  VALIDATORS_MUTANT_RC=$VALIDATORS_NESTED_RC
  VALIDATORS_MUTANT_MATCH=false
  if test "$VALIDATORS_MUTANT_RC" -eq 1 && validators_receipt_has_failure \
    "$VALIDATORS_MUTANT_EVIDENCE/receipt.json" "$VALIDATORS_MUTATION_FAILURE"; then
    VALIDATORS_MUTANT_MATCH=true
  fi

  cp "$SOURCE_ROOT/$VALIDATORS_MUTATION_TARGET" "$VALIDATORS_MUTATION_FILE" || return 70
  validators_run_nested "restored-$VALIDATORS_MUTATION_SLUG" "$VALIDATORS_MUTATION_SELECTOR" \
    "$VALIDATORS_EXTERNAL_ROOT" "$VALIDATORS_RESTORED_EVIDENCE"
  VALIDATORS_RESTORED_RC=$VALIDATORS_NESTED_RC

  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test "$VALIDATORS_MUTANT_MATCH" = true && test "$VALIDATORS_RESTORED_RC" -eq 0 && \
    cmp -s "$SOURCE_ROOT/$VALIDATORS_MUTATION_TARGET" "$VALIDATORS_MUTATION_FILE"; then
    assert_record "validators.mutation.$VALIDATORS_MUTATION_SLUG" 0 \
      "target=$VALIDATORS_MUTATION_ID false_green_detected=true restored_rejection=true" || true
    VALIDATORS_MUTATION_RESULT=PASS
  else
    assert_record "validators.mutation.$VALIDATORS_MUTATION_SLUG" 1 \
      "target=$VALIDATORS_MUTATION_ID mutant_exit=$VALIDATORS_MUTANT_RC target_test_failed=$VALIDATORS_MUTANT_MATCH restored_exit=$VALIDATORS_RESTORED_RC" || true
    VALIDATORS_MUTATION_RESULT=FAIL
  fi

  jq -cn \
    --arg name "$VALIDATORS_MUTATION_NAME" \
    --arg target "$VALIDATORS_MUTATION_TARGET" \
    --arg invariant "$VALIDATORS_MUTATION_ID" \
    --arg selector "$VALIDATORS_MUTATION_SELECTOR" \
    --arg expected_failed_assertion "$VALIDATORS_MUTATION_FAILURE" \
    --arg result "$VALIDATORS_MUTATION_RESULT" \
    --argjson mutant_exit "$VALIDATORS_MUTANT_RC" \
    --argjson restored_exit "$VALIDATORS_RESTORED_RC" \
    '{name:$name,target:$target,invariant:$invariant,selector:$selector,expected_failed_assertion:$expected_failed_assertion,mutant_exit:$mutant_exit,restored_exit:$restored_exit,result:$result}' \
    >>"$VALIDATORS_MUTATION_LIST" || return 70
}

validators_apply_special_mutation() {
  VALIDATORS_SPECIAL_KIND=$1
  VALIDATORS_SPECIAL_FILE=$2
  case "$VALIDATORS_SPECIAL_KIND" in
    migration-invalid)
      perl -0pi -e 's/elif valid_v1 then/elif true then/' "$VALIDATORS_SPECIAL_FILE" || return 70
      ;;
    migration-preservation)
      perl -0pi -e 's/\n  \| \.requirements \|= add_asis_kind//' "$VALIDATORS_SPECIAL_FILE" || return 70
      ;;
    migration-idempotence)
      perl -0pi -e 's/if \.schema_version == "2\.0" then\n  \./if .schema_version == "2.0" then\n  . + {mutation_counter: ((.mutation_counter \/\/ 0) + 1)}/' \
        "$VALIDATORS_SPECIAL_FILE" || return 70
      ;;
    *) return 70 ;;
  esac
}

validators_run_special_mutation() {
  VALIDATORS_SPECIAL_NAME=$1
  VALIDATORS_SPECIAL_KIND=$2
  VALIDATORS_SPECIAL_FAILURE=$3
  VALIDATORS_SPECIAL_TARGET=output/recipes/migrate-trace-v1-to-v2.jq
  VALIDATORS_SPECIAL_FILE="$VALIDATORS_EXTERNAL_ROOT/$VALIDATORS_SPECIAL_TARGET"
  VALIDATORS_SPECIAL_SLUG=$(validators_slug "$VALIDATORS_SPECIAL_NAME") || return 70
  VALIDATORS_SPECIAL_MUTANT_EVIDENCE="$EVIDENCE_DIR/mutant-$VALIDATORS_SPECIAL_SLUG"
  VALIDATORS_SPECIAL_RESTORED_EVIDENCE="$EVIDENCE_DIR/restored-$VALIDATORS_SPECIAL_SLUG"

  cp "$SOURCE_ROOT/$VALIDATORS_SPECIAL_TARGET" "$VALIDATORS_SPECIAL_FILE" || return 70
  validators_apply_special_mutation "$VALIDATORS_SPECIAL_KIND" "$VALIDATORS_SPECIAL_FILE" || return 70
  if cmp -s "$SOURCE_ROOT/$VALIDATORS_SPECIAL_TARGET" "$VALIDATORS_SPECIAL_FILE"; then
    return 70
  fi
  validators_run_nested "mutant-$VALIDATORS_SPECIAL_SLUG" recipe-trace \
    "$VALIDATORS_EXTERNAL_ROOT" "$VALIDATORS_SPECIAL_MUTANT_EVIDENCE"
  VALIDATORS_SPECIAL_MUTANT_RC=$VALIDATORS_NESTED_RC
  VALIDATORS_SPECIAL_MUTANT_MATCH=false
  if test "$VALIDATORS_SPECIAL_MUTANT_RC" -eq 1 && validators_receipt_has_failure \
    "$VALIDATORS_SPECIAL_MUTANT_EVIDENCE/receipt.json" "$VALIDATORS_SPECIAL_FAILURE"; then
    VALIDATORS_SPECIAL_MUTANT_MATCH=true
  fi

  cp "$SOURCE_ROOT/$VALIDATORS_SPECIAL_TARGET" "$VALIDATORS_SPECIAL_FILE" || return 70
  validators_run_nested "restored-$VALIDATORS_SPECIAL_SLUG" recipe-trace \
    "$VALIDATORS_EXTERNAL_ROOT" "$VALIDATORS_SPECIAL_RESTORED_EVIDENCE"
  VALIDATORS_SPECIAL_RESTORED_RC=$VALIDATORS_NESTED_RC

  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test "$VALIDATORS_SPECIAL_MUTANT_MATCH" = true && test "$VALIDATORS_SPECIAL_RESTORED_RC" -eq 0 && \
    cmp -s "$SOURCE_ROOT/$VALIDATORS_SPECIAL_TARGET" "$VALIDATORS_SPECIAL_FILE"; then
    assert_record "validators.mutation.$VALIDATORS_SPECIAL_SLUG" 0 \
      "target=$VALIDATORS_SPECIAL_KIND weakened_behavior_detected=true restored=true" || true
    VALIDATORS_SPECIAL_RESULT=PASS
  else
    assert_record "validators.mutation.$VALIDATORS_SPECIAL_SLUG" 1 \
      "target=$VALIDATORS_SPECIAL_KIND mutant_exit=$VALIDATORS_SPECIAL_MUTANT_RC target_test_failed=$VALIDATORS_SPECIAL_MUTANT_MATCH restored_exit=$VALIDATORS_SPECIAL_RESTORED_RC" || true
    VALIDATORS_SPECIAL_RESULT=FAIL
  fi
  jq -cn \
    --arg name "$VALIDATORS_SPECIAL_NAME" --arg target "$VALIDATORS_SPECIAL_TARGET" \
    --arg invariant "$VALIDATORS_SPECIAL_KIND" --arg selector recipe-trace \
    --arg expected_failed_assertion "$VALIDATORS_SPECIAL_FAILURE" \
    --arg result "$VALIDATORS_SPECIAL_RESULT" \
    --argjson mutant_exit "$VALIDATORS_SPECIAL_MUTANT_RC" \
    --argjson restored_exit "$VALIDATORS_SPECIAL_RESTORED_RC" \
    '{name:$name,target:$target,invariant:$invariant,selector:$selector,expected_failed_assertion:$expected_failed_assertion,mutant_exit:$mutant_exit,restored_exit:$restored_exit,result:$result}' \
    >>"$VALIDATORS_MUTATION_LIST" || return 70
}

validators_run_noop_mutation() {
  VALIDATORS_NOOP_TARGET=tests/validators/trace-schema-parity.jq
  VALIDATORS_NOOP_FILE="$VALIDATORS_EXTERNAL_ROOT/$VALIDATORS_NOOP_TARGET"
  cp "$SOURCE_ROOT/$VALIDATORS_NOOP_TARGET" "$VALIDATORS_NOOP_FILE" || return 70
  printf '[]\n' >"$VALIDATORS_NOOP_FILE" || return 70
  validators_run_nested mutant-validator-noop schema-trace "$VALIDATORS_EXTERNAL_ROOT" \
    "$EVIDENCE_DIR/mutant-validator-noop"
  VALIDATORS_NOOP_RC=$VALIDATORS_NESTED_RC
  cp "$SOURCE_ROOT/$VALIDATORS_NOOP_TARGET" "$VALIDATORS_NOOP_FILE" || return 70
  validators_run_nested restored-validator-noop schema-trace "$VALIDATORS_EXTERNAL_ROOT" \
    "$EVIDENCE_DIR/restored-validator-noop"
  VALIDATORS_NOOP_RESTORED_RC=$VALIDATORS_NESTED_RC
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if test "$VALIDATORS_NOOP_RC" -eq 1 && test "$VALIDATORS_NOOP_RESTORED_RC" -eq 0 && \
    validators_receipt_has_failure "$EVIDENCE_DIR/mutant-validator-noop/receipt.json" schema.mutation_dangling; then
    assert_record validators.mutation.validator_noop 0 \
      'noop made the negative canary false-green and the suite detected it' || true
    VALIDATORS_NOOP_RESULT=PASS
  else
    assert_record validators.mutation.validator_noop 1 \
      "noop_exit=$VALIDATORS_NOOP_RC restored_exit=$VALIDATORS_NOOP_RESTORED_RC" || true
    VALIDATORS_NOOP_RESULT=FAIL
  fi
  jq -cn --arg name validator-noop --arg target "$VALIDATORS_NOOP_TARGET" \
    --arg invariant noop-validator --arg selector schema-trace \
    --arg expected_failed_assertion schema.mutation_dangling --arg result "$VALIDATORS_NOOP_RESULT" \
    --argjson mutant_exit "$VALIDATORS_NOOP_RC" --argjson restored_exit "$VALIDATORS_NOOP_RESTORED_RC" \
    '{name:$name,target:$target,invariant:$invariant,selector:$selector,expected_failed_assertion:$expected_failed_assertion,mutant_exit:$mutant_exit,restored_exit:$restored_exit,result:$result}' \
    >>"$VALIDATORS_MUTATION_LIST" || return 70
}

case_validators() {
  validators_health_check || return 70
  if test "${SENSAI_TEST_INTERNAL_VALIDATOR_HEALTH_ONLY:-0}" = 1; then
    return 0
  fi

  VALIDATORS_EXTERNAL_ROOT=$(mktemp -d /private/tmp/sensai-validator-mutation.XXXXXX) || return 70
  case "$VALIDATORS_EXTERNAL_ROOT" in
    /private/tmp/sensai-validator-mutation.*) ;;
    *) return 70 ;;
  esac
  VALIDATORS_MUTATION_LIST="$EVIDENCE_DIR/mutation-list.jsonl"
  VALIDATORS_HASH_BEFORE="$RUN_TMP/validators-hashes-before.jsonl"
  VALIDATORS_HASH_AFTER="$RUN_TMP/validators-hashes-after.jsonl"
  : >"$VALIDATORS_MUTATION_LIST" || return 70
  validators_record_hashes before "$VALIDATORS_HASH_BEFORE" || return 70
  validators_clone_source "$VALIDATORS_EXTERNAL_ROOT" || return 70

  while IFS='|' read -r VALIDATORS_NAME VALIDATORS_TARGET VALIDATORS_INVARIANT VALIDATORS_SELECTOR VALIDATORS_FAILURE; do
    test -n "$VALIDATORS_NAME" || continue
    validators_run_issue_mutation "$VALIDATORS_NAME" "$VALIDATORS_TARGET" "$VALIDATORS_INVARIANT" \
      "$VALIDATORS_SELECTOR" "$VALIDATORS_FAILURE" || return 70
  done <<'EOF'
trace-required|tests/validators/trace-schema-parity.jq|trace.required|schema-trace|schema.mutation_missing
trace-array-type|tests/validators/trace-schema-parity.jq|trace.array_type|schema-trace|schema.mutation_type
trace-nonempty|tests/validators/trace-schema-parity.jq|trace.nonempty|schema-trace|schema.mutation_empty
trace-additional-properties|tests/validators/trace-schema-parity.jq|trace.additional_properties|schema-trace|schema.mutation_additional
trace-id-pattern|tests/validators/trace-schema-parity.jq|trace.id_pattern|schema-trace|schema.mutation_id
trace-status|tests/validators/trace-schema-parity.jq|trace.status|schema-trace|schema.mutation_status
progress-phase|tests/validators/progress-schema-parity.jq|progress.phase|schema-progress|schema.progress_invalid_phase
progress-status|tests/validators/progress-schema-parity.jq|progress.status|schema-progress|schema.progress_invalid_status
progress-hash|tests/validators/progress-schema-parity.jq|progress.hash|schema-progress|schema.progress_invalid_hash
progress-path|tests/validators/progress-schema-parity.jq|progress.path|schema-progress|schema.progress_invalid_path
progress-revision|tests/validators/progress-schema-parity.jq|progress.revision|schema-progress|schema.progress_invalid_revision
progress-hard-gate|tests/validators/progress-schema-parity.jq|progress.hard_gate|schema-progress|schema.progress_missing_hard_gate
trace-recipe-reference|output/recipes/trace.jq|trace.recipe.reference_integrity|recipe-trace|recipe.invalid_dangling
trace-recipe-global-ids|output/recipes/trace.jq|trace.recipe.global_ids|recipe-trace|recipe.invalid_duplicate
trace-recipe-direct-evidence|output/recipes/trace.jq|trace.recipe.direct_evidence|recipe-trace|recipe.invalid_direct_evidence
trace-recipe-exact-join|output/recipes/trace.jq|trace.recipe.exact_join|recipe-trace|recipe.invalid_exact_join
trace-recipe-mapping|output/recipes/trace.jq|trace.recipe.mapping|recipe-trace|recipe.invalid_technical_mapping
trace-recipe-binding|output/recipes/trace.jq|trace.recipe.binding|recipe-trace|recipe.invalid_design_binding
glossary-direct-evidence|output/recipes/glossary.jq|glossary.direct_evidence|recipe-trace|recipe.invalid_evidence_free_glossary
glossary-unique-ids|output/recipes/glossary.jq|glossary.unique_ids|recipe-trace|recipe.invalid_duplicate_glossary
glossary-mapping|output/recipes/glossary.jq|glossary.mapping|recipe-trace|recipe.invalid_glossary_mapping
provenance-evidence-missing|output/recipes/provenance.jq|provenance.evidence_missing|provenance|provenance.evidence_missing
provenance-evidence-duplicate|output/recipes/provenance.jq|provenance.evidence_duplicate|provenance|provenance.evidence_duplicate
provenance-evidence-mismatch|output/recipes/provenance.jq|provenance.evidence_mismatch|provenance|provenance.evidence_mismatch
provenance-source-missing|output/recipes/provenance.jq|provenance.source_missing|provenance|provenance.source_missing
provenance-source-duplicate|output/recipes/provenance.jq|provenance.source_duplicate|provenance|provenance.source_duplicate
provenance-source-mismatch|output/recipes/provenance.jq|provenance.source_mismatch|provenance|provenance.source_mismatch
provenance-kind-mismatch|output/recipes/provenance.jq|provenance.kind_mismatch|provenance|provenance.kind_mismatch
provenance-id-missing|output/recipes/provenance.jq|provenance.id_missing|provenance|provenance.id_missing
provenance-id-duplicate|output/recipes/provenance.jq|provenance.id_duplicate|provenance|provenance.id_duplicate
provenance-id-mismatch|output/recipes/provenance.jq|provenance.id_mismatch|provenance|provenance.id_mismatch
provenance-mermaid-duplicate|output/recipes/provenance.jq|provenance.mermaid_duplicate|provenance|provenance.mermaid_duplicate
provenance-arrow-missing|output/recipes/provenance.jq|provenance.arrow_missing|provenance|provenance.arrow_missing
provenance-arrow-duplicate|output/recipes/provenance.jq|provenance.arrow_duplicate|provenance|provenance.arrow_duplicate
provenance-arrow-mismatch|output/recipes/provenance.jq|provenance.arrow_mismatch|provenance|provenance.arrow_mismatch
EOF

  validators_run_special_mutation migration-invalid-v1 migration-invalid migration.invalid_v1 || return 70
  validators_run_special_mutation migration-preservation migration-preservation migration.preservation || return 70
  validators_run_special_mutation migration-idempotence migration-idempotence migration.idempotent || return 70
  validators_run_noop_mutation || return 70

  validators_record_hashes after "$VALIDATORS_HASH_AFTER" || return 70
  jq -n --slurpfile before "$VALIDATORS_HASH_BEFORE" --slurpfile after "$VALIDATORS_HASH_AFTER" \
    '$before as $before_rows | $after as $after_rows |
     {before:$before_rows,after:$after_rows,
      byte_identical: (($before_rows | map({key:.path,value:.sha256}) | from_entries) ==
                       ($after_rows | map({key:.path,value:.sha256}) | from_entries))}' \
    >"$EVIDENCE_DIR/before-after-hashes.json" || return 70
  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_jq validators.source_bytes_unchanged '.byte_identical == true' \
    "$EVIDENCE_DIR/before-after-hashes.json" || true

  VALIDATORS_MUTATION_COUNT=$(wc -l <"$VALIDATORS_MUTATION_LIST" | awk '{print $1}') || return 70
  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_eq validators.mutation_count 39 "$VALIDATORS_MUTATION_COUNT" || true
  CASE_TOTAL=$((CASE_TOTAL + 1))
  if jq -s -e 'length == 39 and all(.[]; .result == "PASS" and .mutant_exit == 1 and .restored_exit == 0)' \
    "$VALIDATORS_MUTATION_LIST" >/dev/null 2>&1; then
    assert_record validators.mutation_matrix 0 'all 39 targeted/noop mutations were killed' || true
  else
    assert_record validators.mutation_matrix 1 'mutation matrix has missing or surviving mutants' || true
  fi

  rm -rf "$VALIDATORS_EXTERNAL_ROOT" || return 70
  if test ! -e "$VALIDATORS_EXTERNAL_ROOT"; then
    jq -n --arg root "$VALIDATORS_EXTERNAL_ROOT" \
      '{status:"PASS",external_root:$root,external_root_removed:true,product_files_mutated:false}' \
      >"$EVIDENCE_DIR/mutation-cleanup.json" || return 70
    CASE_TOTAL=$((CASE_TOTAL + 1))
    assert_record validators.external_cleanup 0 'external mutation root removed' || true
  else
    jq -n --arg root "$VALIDATORS_EXTERNAL_ROOT" \
      '{status:"FAIL",external_root:$root,external_root_removed:false,product_files_mutated:false}' \
      >"$EVIDENCE_DIR/mutation-cleanup.json" || return 70
    assert_record validators.external_cleanup 1 'external mutation root remains' || true
  fi
}
