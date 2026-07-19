#!/bin/sh

fixtures_clone_source() {
  FIXTURES_CLONE_ROOT=$1
  mkdir -p "$FIXTURES_CLONE_ROOT" || return 70
  cp -R "$SOURCE_ROOT/fixtures" "$FIXTURES_CLONE_ROOT/fixtures" || return 70
}

fixtures_refresh_metadata() {
  FIXTURES_REFRESH_ROOT=$1
  FIXTURES_REFRESH_TMP="$FIXTURES_REFRESH_ROOT/fixtures/SHA256SUMS.tmp"
  (
    cd "$FIXTURES_REFRESH_ROOT/fixtures" || exit 70
    while IFS= read -r FIXTURES_REFRESH_PATH; do
      shasum -a 256 "$FIXTURES_REFRESH_PATH" || exit 70
    done <FILES.txt
    shasum -a 256 FILES.txt || exit 70
  ) | LC_ALL=C sort >"$FIXTURES_REFRESH_TMP" || return 70
  mv "$FIXTURES_REFRESH_TMP" "$FIXTURES_REFRESH_ROOT/fixtures/SHA256SUMS" || return 70
}

fixtures_remove_inventory_path() {
  FIXTURES_REMOVE_ROOT=$1
  FIXTURES_REMOVE_PATH=$2
  awk -v removed="$FIXTURES_REMOVE_PATH" '$0 != removed' \
    "$FIXTURES_REMOVE_ROOT/fixtures/FILES.txt" >"$FIXTURES_REMOVE_ROOT/fixtures/FILES.txt.tmp" || return 70
  mv "$FIXTURES_REMOVE_ROOT/fixtures/FILES.txt.tmp" "$FIXTURES_REMOVE_ROOT/fixtures/FILES.txt" || return 70
}

fixtures_add_inventory_path() {
  FIXTURES_ADD_ROOT=$1
  FIXTURES_ADD_PATH=$2
  printf '%s\n' "$FIXTURES_ADD_PATH" >>"$FIXTURES_ADD_ROOT/fixtures/FILES.txt" || return 70
  LC_ALL=C sort -u "$FIXTURES_ADD_ROOT/fixtures/FILES.txt" >"$FIXTURES_ADD_ROOT/fixtures/FILES.txt.tmp" || return 70
  mv "$FIXTURES_ADD_ROOT/fixtures/FILES.txt.tmp" "$FIXTURES_ADD_ROOT/fixtures/FILES.txt" || return 70
}

fixtures_write_expected_registry() {
  FIXTURES_EXPECTED_REGISTRY=$1
  printf '%s\n' \
    'adversarial-convention-violation|adversarial|1|CONVENTION_VIOLATION' \
    'adversarial-dangling-reference|adversarial|1|DANGLING_REFERENCE' \
    'adversarial-duplicate-id|adversarial|1|DUPLICATE_ID' \
    'adversarial-duplicate-route|adversarial|1|DUPLICATE_ROUTE' \
    'adversarial-dynamic-route|adversarial|1|DYNAMIC_ROUTE_UNRESOLVED' \
    'adversarial-dynamic-url|adversarial|1|DYNAMIC_URL_AMBIGUOUS' \
    'adversarial-fake-secret|adversarial|1|SYNTHETIC_SECRET_INPUT' \
    'adversarial-hidden-conflict|adversarial|1|HIDDEN_CONFLICT' \
    'adversarial-invented-glossary|adversarial|1|INVENTED_GLOSSARY' \
    'adversarial-malformed-json|adversarial|1|MALFORMED_JSON' \
    'adversarial-missing-golden|adversarial|1|MISSING_GOLDEN' \
    'adversarial-output-path-escape|adversarial|1|OUTPUT_PATH_ESCAPE' \
    'adversarial-provenance-mismatch|adversarial|1|PROVENANCE_MISMATCH' \
    'adversarial-stale-progress|adversarial|1|STALE_PROGRESS' \
    'happy-asis-projections|happy|0|PASS' \
    'happy-business-rules|happy|0|PASS' \
    'happy-business-state-event|happy|0|PASS' \
    'happy-change-request-valid|happy|0|PASS' \
    'happy-glossary|happy|0|PASS' \
    'happy-openapi-get|happy|0|PASS' \
    'happy-openapi-post|happy|0|PASS' \
    'happy-progress|happy|0|PASS' \
    'happy-react-source|happy|0|PASS' \
    'happy-rfc-requirement|happy|0|PASS' \
    'happy-tobe-projections|happy|0|PASS' \
    'happy-trace-v1|happy|0|PASS' \
    'happy-trace-v2|happy|0|PASS' \
    'happy-vertx-source|happy|0|PASS' \
    >"$FIXTURES_EXPECTED_REGISTRY" || return 70
}

fixtures_check_inventory() {
  FIXTURES_ROOT=$1
  FIXTURES_SORTED="$RUN_TMP/fixtures-inventory-sorted.txt"
  FIXTURES_PHYSICAL="$RUN_TMP/fixtures-physical.txt"
  FIXTURES_EXPECTED_PHYSICAL="$RUN_TMP/fixtures-physical-expected.txt"

  LC_ALL=C sort "$FIXTURES_ROOT/FILES.txt" >"$FIXTURES_SORTED" || return 70
  if cmp -s "$FIXTURES_ROOT/FILES.txt" "$FIXTURES_SORTED" && \
     awk 'NF == 0 || previous == $0 {invalid=1} {previous=$0} END {exit invalid+0}' "$FIXTURES_ROOT/FILES.txt"; then
    assert_record fixtures.inventory_sorted_unique 0 'FILES.txt is sorted and unique' || true
  else
    assert_record fixtures.inventory_sorted_unique 1 'FILES.txt is not sorted and unique' || true
  fi

  if awk '$0 == "" || $0 ~ /^\// || $0 ~ /(^|\/)\.\.($|\/)/ || $0 ~ /(^|\/)\.($|\/)/ || $0 ~ /[[:cntrl:]]/ {invalid=1} END {exit invalid+0}' "$FIXTURES_ROOT/FILES.txt"; then
    assert_record fixtures.inventory_safe_paths 0 'inventory paths are normalized relative paths' || true
  else
    assert_record fixtures.inventory_safe_paths 1 'inventory contains unsafe path' || true
  fi

  find "$FIXTURES_ROOT" -mindepth 1 ! -type d -print \
    | sed "s#^$FIXTURES_ROOT/##" | LC_ALL=C sort >"$FIXTURES_PHYSICAL" || return 70
  {
    sed -n 'p' "$FIXTURES_ROOT/FILES.txt"
    printf '%s\n' FILES.txt SHA256SUMS
  } | LC_ALL=C sort >"$FIXTURES_EXPECTED_PHYSICAL" || return 70
  if cmp -s "$FIXTURES_EXPECTED_PHYSICAL" "$FIXTURES_PHYSICAL"; then
    assert_record fixtures.physical_exact_set 0 'physical leaf set equals inventory plus metadata' || true
  else
    assert_record fixtures.physical_exact_set 1 'physical leaf set differs from inventory contract' || true
  fi

  FIXTURES_REGULAR_OK=1
  if test -n "$(find "$FIXTURES_ROOT" -type l -print -quit 2>/dev/null)"; then
    FIXTURES_REGULAR_OK=0
  fi
  while IFS= read -r FIXTURES_PHYSICAL_PATH; do
    test -n "$FIXTURES_PHYSICAL_PATH" || continue
    if ! test -f "$FIXTURES_ROOT/$FIXTURES_PHYSICAL_PATH" || test -L "$FIXTURES_ROOT/$FIXTURES_PHYSICAL_PATH"; then
      FIXTURES_REGULAR_OK=0
    fi
  done <"$FIXTURES_PHYSICAL"
  if test "$FIXTURES_REGULAR_OK" -eq 1; then
    assert_record fixtures.regular_leaf 0 'all immutable leaves and ancestors are regular and non-symlink' || true
  else
    assert_record fixtures.regular_leaf 1 'non-regular or symlink fixture surface detected' || true
  fi
}

fixtures_check_sha256() {
  FIXTURES_ROOT=$1
  FIXTURES_SHA_ACTUAL="$RUN_TMP/fixtures-sha-paths.txt"
  FIXTURES_SHA_EXPECTED="$RUN_TMP/fixtures-sha-expected.txt"
  {
    sed -n 'p' "$FIXTURES_ROOT/FILES.txt"
    printf '%s\n' FILES.txt
  } | LC_ALL=C sort >"$FIXTURES_SHA_EXPECTED" || return 70

  FIXTURES_SHA_FORMAT_OK=1
  FIXTURES_SHA_INVENTORY_OK=1
  if ! awk '
      {
        digest=substr($0,1,64)
        separator=substr($0,65,2)
        path=substr($0,67)
        if (length($0) < 67 || length(digest) != 64 || digest !~ /^[0-9a-f]+$/ || separator != "  ") invalid=1
        if (path == "" || substr(path,1,1) == "/" || path ~ /(^|\/)\.\.?($|\/)/ || path ~ /[[:cntrl:]]/) invalid=1
        if (seen[path]++) invalid=1
      }
      END {exit invalid+0}
    ' "$FIXTURES_ROOT/SHA256SUMS"; then
    FIXTURES_SHA_FORMAT_OK=0
  fi
  awk '{print substr($0,67)}' "$FIXTURES_ROOT/SHA256SUMS" | LC_ALL=C sort >"$FIXTURES_SHA_ACTUAL" || return 70
  cmp -s "$FIXTURES_SHA_EXPECTED" "$FIXTURES_SHA_ACTUAL" || FIXTURES_SHA_INVENTORY_OK=0
  test "$(wc -l <"$FIXTURES_ROOT/SHA256SUMS" | tr -d ' ')" -eq "$(wc -l <"$FIXTURES_SHA_EXPECTED" | tr -d ' ')" || FIXTURES_SHA_INVENTORY_OK=0
  if test "$FIXTURES_SHA_FORMAT_OK" -eq 1 && test "$FIXTURES_SHA_INVENTORY_OK" -eq 1; then
    assert_record fixtures.sha256_format 0 'every checksum has lowercase hex, two spaces, and an exact safe unique inventory path' || true
  else
    assert_record fixtures.sha256_format 1 'checksum format, path safety, uniqueness, or exact inventory set invalid' || true
  fi
  if test "$FIXTURES_SHA_INVENTORY_OK" -eq 1; then
    assert_record fixtures.sha256_inventory 0 'SHA256SUMS paths equal FILES entries plus FILES.txt' || true
  else
    assert_record fixtures.sha256_inventory 1 'SHA256SUMS path set or cardinality differs' || true
  fi

  if test "$FIXTURES_SHA_FORMAT_OK" -eq 1 && test "$FIXTURES_SHA_INVENTORY_OK" -eq 1; then
    set +e
    (cd "$FIXTURES_ROOT" && shasum -a 256 -c SHA256SUMS) >"$RUN_TMP/fixtures-sha-check.out" 2>&1
    FIXTURES_SHA_RC=$?
    evidence_log_command fixtures-sha256 'shasum -a 256 -c fixtures/SHA256SUMS' "$FIXTURES_SHA_RC"
    assert_eq fixtures.sha256 0 "$FIXTURES_SHA_RC" || true
  else
    evidence_log_command fixtures-sha256 'shasum skipped because checksum format validation failed' 1
    assert_record fixtures.sha256 1 'checksum verification not invoked on malformed metadata' || true
  fi
}

fixtures_check_registry() {
  FIXTURES_ROOT=$1
  FIXTURES_REGISTRY="$FIXTURES_ROOT/CASES.json"
  FIXTURES_EXPECTED_REGISTRY="$RUN_TMP/fixtures-registry-expected.txt"
  FIXTURES_ACTUAL_REGISTRY="$RUN_TMP/fixtures-registry-actual.txt"
  fixtures_write_expected_registry "$FIXTURES_EXPECTED_REGISTRY" || return 70
  jq -r '.cases[] | [.id,.mode,(.expected_exit|tostring),.expected_reason] | join("|")' "$FIXTURES_REGISTRY" \
    | LC_ALL=C sort >"$FIXTURES_ACTUAL_REGISTRY" || return 70
  if cmp -s "$FIXTURES_EXPECTED_REGISTRY" "$FIXTURES_ACTUAL_REGISTRY" && \
     jq -e '.schema_version == "1.0" and (.cases|length)==28 and ([.cases[].id]|unique|length)==28 and ([.cases[]|select(.mode=="happy")]|length)==14 and ([.cases[]|select(.mode=="adversarial")]|length)==14 and .declared_malformed_json == ["adversarial/malformed.json"]' "$FIXTURES_REGISTRY" >/dev/null 2>&1; then
    assert_record fixtures.registry_exact 0 'registry has exact 14 happy and 14 adversarial exit/reason cases' || true
  else
    assert_record fixtures.registry_exact 1 'registry case, exit, reason, or symmetry drift' || true
  fi

  FIXTURES_ADV_FILES_OK=1
  while IFS= read -r FIXTURES_ADV_PATH; do
    test -n "$FIXTURES_ADV_PATH" || continue
    if ! test -f "$FIXTURES_ROOT/$FIXTURES_ADV_PATH" || test -L "$FIXTURES_ROOT/$FIXTURES_ADV_PATH"; then
      FIXTURES_ADV_FILES_OK=0
    fi
  done <<EOF
$(jq -r '.cases[] | select(.mode=="adversarial" and has("fixture")) | .fixture' "$FIXTURES_REGISTRY")
EOF
  if test "$FIXTURES_ADV_FILES_OK" -eq 1; then
    assert_record fixtures.adversarial_files 0 'all declared adversarial fixture paths exist' || true
  else
    assert_record fixtures.adversarial_files 1 'declared adversarial fixture missing or non-regular' || true
  fi
}

fixtures_check_syntax() {
  FIXTURES_ROOT=$1
  FIXTURES_JSON_OK=1
  FIXTURES_DECLARED_MALFORMED='adversarial/malformed.json'
  while IFS= read -r FIXTURES_JSON_FILE; do
    FIXTURES_JSON_REL=${FIXTURES_JSON_FILE#"$FIXTURES_ROOT"/}
    if test "$FIXTURES_JSON_REL" = "$FIXTURES_DECLARED_MALFORMED"; then
      if jq empty "$FIXTURES_JSON_FILE" >/dev/null 2>&1; then
        FIXTURES_JSON_OK=0
      fi
    elif ! jq empty "$FIXTURES_JSON_FILE" >/dev/null 2>&1; then
      FIXTURES_JSON_OK=0
    fi
  done <<EOF
$(find "$FIXTURES_ROOT" -type f -name '*.json' -print | LC_ALL=C sort)
EOF
  if test "$FIXTURES_JSON_OK" -eq 1; then
    assert_record fixtures.json_syntax 0 'all JSON parses except the single declared malformed case' || true
  else
    assert_record fixtures.json_syntax 1 'undeclared malformed JSON or declared malformed case parsed' || true
  fi

  FIXTURES_YAML_OK=1
  while IFS= read -r FIXTURES_YAML_FILE; do
    test -n "$FIXTURES_YAML_FILE" || continue
    if ! yq eval '.' "$FIXTURES_YAML_FILE" >/dev/null 2>&1; then
      FIXTURES_YAML_OK=0
    fi
  done <<EOF
$(find "$FIXTURES_ROOT" -type f \( -name '*.yaml' -o -name '*.yml' \) -print | LC_ALL=C sort)
EOF
  if test "$FIXTURES_YAML_OK" -eq 1; then
    assert_record fixtures.yaml_syntax 0 'all YAML fixtures parse' || true
  else
    assert_record fixtures.yaml_syntax 1 'YAML parse failure' || true
  fi
}

fixtures_check_happy_mappings() {
  FIXTURES_ROOT=$1
  FIXTURES_REGISTRY="$FIXTURES_ROOT/CASES.json"
  FIXTURES_INPUT_OK=1
  FIXTURES_GOLDEN_OK=1
  FIXTURES_PROVENANCE_OK=1

  jq -e 'all(.cases[] | select(.mode=="happy"); (.inputs|type=="array" and length>0))' "$FIXTURES_REGISTRY" >/dev/null 2>&1 || FIXTURES_INPUT_OK=0
  jq -e 'all(.cases[] | select(.mode=="happy"); (.expected_artifacts|type=="array" and length>0))' "$FIXTURES_REGISTRY" >/dev/null 2>&1 || FIXTURES_GOLDEN_OK=0

  while IFS='|' read -r FIXTURES_CASE_ID FIXTURES_CASE_INPUT; do
    test -n "$FIXTURES_CASE_ID" || continue
    if ! test -f "$FIXTURES_ROOT/$FIXTURES_CASE_INPUT" || test -L "$FIXTURES_ROOT/$FIXTURES_CASE_INPUT"; then
      FIXTURES_INPUT_OK=0
    fi
  done <<EOF
$(jq -r '.cases[] | select(.mode=="happy") | .id as $id | .inputs[] | [$id,.] | join("|")' "$FIXTURES_REGISTRY")
EOF

  while IFS='|' read -r FIXTURES_CASE_ID FIXTURES_CASE_ARTIFACT; do
    test -n "$FIXTURES_CASE_ID" || continue
    if ! test -f "$FIXTURES_ROOT/$FIXTURES_CASE_ARTIFACT" || test -L "$FIXTURES_ROOT/$FIXTURES_CASE_ARTIFACT"; then
      FIXTURES_GOLDEN_OK=0
    fi
  done <<EOF
$(jq -r '.cases[] | select(.mode=="happy") | .id as $id | .expected_artifacts[] | [$id,.] | join("|")' "$FIXTURES_REGISTRY")
EOF

  if ! jq -e 'all(.cases[] | select(.mode=="happy"); . as $case | ($case.inputs|type=="array" and length>0) and ($case.expected_artifacts|type=="array" and length>0) and ($case.provenance|type=="array" and length>0) and (($case.expected_artifacts|unique|sort) == ($case.provenance|map(.artifact)|unique|sort)) and all($case.provenance[]; . as $p | ($p.path_line == ($p.source + ":" + ($p.line|tostring))) and (($p.line|type)=="number") and ($p.line>=1) and (($case.expected_artifacts | index($p.artifact)) != null) and (($case.inputs | index($p.source)) != null)))' "$FIXTURES_REGISTRY" >/dev/null 2>&1; then
    FIXTURES_PROVENANCE_OK=0
  fi

  while IFS='|' read -r FIXTURES_PROV_ARTIFACT FIXTURES_PROV_SOURCE FIXTURES_PROV_LINE FIXTURES_PROV_PATH_LINE; do
    test -n "$FIXTURES_PROV_ARTIFACT" || continue
    if test -f "$FIXTURES_ROOT/$FIXTURES_PROV_SOURCE"; then
      FIXTURES_SOURCE_LINES=$(wc -l <"$FIXTURES_ROOT/$FIXTURES_PROV_SOURCE" | tr -d ' ')
      case "$FIXTURES_PROV_LINE" in
        ''|*[!0-9]*) FIXTURES_PROVENANCE_OK=0 ;;
        *) test "$FIXTURES_PROV_LINE" -le "$FIXTURES_SOURCE_LINES" || FIXTURES_PROVENANCE_OK=0 ;;
      esac
    fi
    if test -f "$FIXTURES_ROOT/$FIXTURES_PROV_ARTIFACT"; then
      rg -F -q -- "$FIXTURES_PROV_PATH_LINE" "$FIXTURES_ROOT/$FIXTURES_PROV_ARTIFACT" || FIXTURES_PROVENANCE_OK=0
    fi
  done <<EOF
$(jq -r '.cases[] | select(.mode=="happy") | .provenance[] | [.artifact,.source,(.line|tostring),.path_line] | join("|")' "$FIXTURES_REGISTRY")
EOF

  if test "$FIXTURES_INPUT_OK" -eq 1; then
    assert_record fixtures.happy_input_files 0 'every happy case maps to regular inputs' || true
  else
    assert_record fixtures.happy_input_files 1 'happy input mapping is missing or non-regular' || true
  fi
  if test "$FIXTURES_GOLDEN_OK" -eq 1; then
    assert_record fixtures.happy_golden_files 0 'every happy case maps to regular golden artifacts' || true
  else
    assert_record fixtures.happy_golden_files 1 'happy golden mapping is missing or non-regular' || true
  fi
  if test "$FIXTURES_PROVENANCE_OK" -eq 1; then
    assert_record fixtures.happy_provenance 0 'every happy artifact has in-range input path:line provenance' || true
  else
    assert_record fixtures.happy_provenance 1 'happy provenance mapping, range, or artifact marker invalid' || true
  fi
}

fixtures_write_expected_evidence_map() {
  FIXTURES_EXPECTED_EVIDENCE_MAP=$1
  printf '%s\n' \
    'E-BIZ-CONFLICT|inputs/business/order-rules.md|4|BIZ-RULE-002|BIZ-RULE-001,BIZ-RULE-002' \
    'E-BIZ-EVENT|inputs/business/order-rules.md|5|BIZ-EVENT-001|BIZ-EVENT-001,BIZ-FLOW-001' \
    'E-BIZ-INVARIANT|inputs/business/order-rules.md|6|BIZ-INVARIANT-001|BIZ-INVARIANT-001' \
    'E-BIZ-RULE|inputs/business/order-rules.md|3|BIZ-RULE-001|BIZ-RULE-001' \
    'E-CHANGE-DETAIL|inputs/change/valid.md|3|REQ-EXT-0001|DESIGN-PAGE-001,REQ-EXT-0001' \
    'E-OPENAPI-GET|inputs/spec/openapi.yaml|6|/orders:|CONV-API-001' \
    'E-OPENAPI-POST|inputs/spec/openapi.yaml|12|post:|BE-002' \
    'E-REACT-COMPONENT|inputs/legacy-react/src/OrdersPage.tsx|1|React|CONV-COMPONENT-001' \
    'E-REACT-PAGE|inputs/legacy-react/src/OrdersPage.tsx|5|OrdersPage|CONV-STRUCTURE-001' \
    'E-REACT-ROUTE|inputs/legacy-react/src/OrdersPage.tsx|3|ORDER_ROUTE|CONV-NAMING-001,FE-001' \
    'E-RFC-REQ|inputs/spec/requirements.md|3|REQ-001|CONV-TEST-001,REQ-001' \
    'E-STATE-INITIAL|inputs/business/order-state.json|3|initial|BIZ-ENT-001' \
    'E-STATE-TRANSITION|inputs/business/order-state.json|5|payment_captured|BIZ-STATE-001,CONV-STATE-001' \
    'E-VERTX-COMPONENT|inputs/legacy-vertx/src/main/java/example/OrderVerticle.java|3|AbstractVerticle|CONV-COMPONENT-001' \
    'E-VERTX-GET|inputs/legacy-vertx/src/main/java/example/OrderVerticle.java|10|router.get("/orders")|BE-001,CONV-API-001,CONV-NAMING-001' \
    'E-VERTX-POST|inputs/legacy-vertx/src/main/java/example/OrderVerticle.java|15|router.post("/orders")|BE-002' \
    'E-VERTX-EVENT|inputs/legacy-vertx/src/main/java/example/OrderVerticle.java|16|order.created|BIZ-EVENT-001,BIZ-FLOW-001' \
    'E-VERTX-STATUS|inputs/legacy-vertx/src/main/java/example/OrderVerticle.java|17|setStatusCode(202)|CONV-ERROR-001' \
    'E-VERTX-STRUCTURE|inputs/legacy-vertx/src/main/java/example/OrderVerticle.java|6|OrderVerticle|CONV-STRUCTURE-001' \
    | LC_ALL=C sort >"$FIXTURES_EXPECTED_EVIDENCE_MAP" || return 70
}

fixtures_check_trace_contracts() {
  FIXTURES_ROOT=$1
  FIXTURES_TRACE_V1="$FIXTURES_ROOT/expected/trace-v1.json"
  FIXTURES_TRACE_V2="$FIXTURES_ROOT/expected/trace-v2.json"
  FIXTURES_REGISTRY="$FIXTURES_ROOT/CASES.json"

  if jq -s -e '
      def preserved($old; $new): all($old | keys[]; . as $key | $new[$key] == $old[$key]);
      .[0] as $v1 | .[1] as $v2 |
      $v2.schema_version == "2.0" and
      all(["requirements","frontends","backends"][];
        . as $section |
        all($v1[$section][];
          . as $old |
          any($v2[$section][];
            . as $new |
            $new.id == $old.id and preserved($old; $new) and $new.kind == "asis" and ($new.evidence_ids | type == "array" and length > 0)))) and
      (["REQ-001","FE-001","BE-001"] - ([ $v2.requirements[].id, $v2.frontends[].id, $v2.backends[].id ] | flatten)) == []
    ' "$FIXTURES_TRACE_V1" "$FIXTURES_TRACE_V2" >/dev/null 2>&1; then
    assert_record fixtures.trace_migration 0 'v2 additively preserves v1 facts and tags migrated facts as asis' || true
  else
    assert_record fixtures.trace_migration 1 'v2 does not additively preserve v1 facts, values, IDs, kind, and evidence IDs' || true
  fi

  FIXTURES_EXPECTED_EVIDENCE="$RUN_TMP/fixtures-evidence-expected.txt"
  FIXTURES_REGISTRY_EVIDENCE="$RUN_TMP/fixtures-evidence-registry.txt"
  FIXTURES_TRACE_EVIDENCE="$RUN_TMP/fixtures-evidence-trace.txt"
  FIXTURES_TRACE_USAGE="$RUN_TMP/fixtures-evidence-usage.txt"
  fixtures_write_expected_evidence_map "$FIXTURES_EXPECTED_EVIDENCE" || return 70
  jq -r '.evidence_expectations[] | [.id,.path,(.line|tostring),.required_token,(.fact_ids|sort|join(","))] | join("|")' "$FIXTURES_REGISTRY" \
    | LC_ALL=C sort >"$FIXTURES_REGISTRY_EVIDENCE" || return 70
  jq -r '.evidence[] | [.id,.path,(.line|tostring)] | join("|")' "$FIXTURES_TRACE_V2" \
    | LC_ALL=C sort >"$FIXTURES_TRACE_EVIDENCE" || return 70
  jq -r '
      [.conventions[],.requirements[],.frontends[],.backends[],.business_entities[],.business_rules[],.business_flows[],.business_events[],.business_states[],.business_invariants[],.extension_requirements[],.designs[]] as $facts |
      .evidence[] as $e |
      [$e.id, ($facts | map(select((.evidence_ids // []) | index($e.id))) | map(.id) | sort | join(","))] | join("|")
    ' "$FIXTURES_TRACE_V2" | LC_ALL=C sort >"$FIXTURES_TRACE_USAGE" || return 70

  FIXTURES_EVIDENCE_MAP_OK=1
  cmp -s "$FIXTURES_EXPECTED_EVIDENCE" "$FIXTURES_REGISTRY_EVIDENCE" || FIXTURES_EVIDENCE_MAP_OK=0
  sed 's/|[^|]*|[^|]*$//' "$FIXTURES_EXPECTED_EVIDENCE" >"$RUN_TMP/fixtures-evidence-expected-trace.txt" || return 70
  cmp -s "$RUN_TMP/fixtures-evidence-expected-trace.txt" "$FIXTURES_TRACE_EVIDENCE" || FIXTURES_EVIDENCE_MAP_OK=0
  while IFS='|' read -r FIXTURES_EVIDENCE_ID FIXTURES_EVIDENCE_PATH FIXTURES_EVIDENCE_LINE FIXTURES_EVIDENCE_TOKEN FIXTURES_EVIDENCE_FACTS; do
    FIXTURES_EVIDENCE_TEXT=$(sed -n "${FIXTURES_EVIDENCE_LINE}p" "$FIXTURES_ROOT/$FIXTURES_EVIDENCE_PATH") || return 70
    printf '%s\n' "$FIXTURES_EVIDENCE_TEXT" | rg -F -q -- "$FIXTURES_EVIDENCE_TOKEN" || FIXTURES_EVIDENCE_MAP_OK=0
  done <"$FIXTURES_EXPECTED_EVIDENCE"
  if test "$FIXTURES_EVIDENCE_MAP_OK" -eq 1; then
    assert_record fixtures.evidence_expectations 0 'evidence map, trace path:line, and required source token are exact' || true
  else
    assert_record fixtures.evidence_expectations 1 'evidence map, trace path:line, or required source token mismatch' || true
  fi

  FIXTURES_EVIDENCE_USAGE_OK=1
  sed 's/^\([^|]*\)|[^|]*|[^|]*|[^|]*|/\1|/' "$FIXTURES_EXPECTED_EVIDENCE" >"$RUN_TMP/fixtures-evidence-expected-usage.txt" || return 70
  cmp -s "$RUN_TMP/fixtures-evidence-expected-usage.txt" "$FIXTURES_TRACE_USAGE" || FIXTURES_EVIDENCE_USAGE_OK=0
  jq -e '
      [.evidence[].id] as $ids |
      all([.conventions[],.requirements[],.frontends[],.backends[],.business_entities[],.business_rules[],.business_flows[],.business_events[],.business_states[],.business_invariants[],.extension_requirements[],.designs[]][];
        (.evidence_ids | type == "array" and length > 0) and all(.evidence_ids[]; . as $id | ($ids | index($id)) != null))
    ' "$FIXTURES_TRACE_V2" >/dev/null 2>&1 || FIXTURES_EVIDENCE_USAGE_OK=0
  if test "$FIXTURES_EVIDENCE_USAGE_OK" -eq 1; then
    assert_record fixtures.trace_evidence_usage 0 'every trace fact uses only its exact declared supporting evidence IDs' || true
  else
    assert_record fixtures.trace_evidence_usage 1 'trace fact evidence usage is dangling, missing, or unrelated to expectation map' || true
  fi

  if rg -F -q 'DESIGN-PAGE-001' "$FIXTURES_ROOT/expected/tobe/ui.md" && \
     rg -F -q 'REQ-EXT-0001' "$FIXTURES_ROOT/expected/tobe/ui.md" && \
     rg -F -q 'E-CHANGE-DETAIL' "$FIXTURES_ROOT/expected/tobe/ui.md" && \
     rg -F -q 'inputs/change/valid.md:3' "$FIXTURES_ROOT/expected/tobe/ui.md"; then
    assert_record fixtures.tobe_ui_bindings 0 'TO-BE UI carries design, requirement, evidence, and path:line bindings' || true
  else
    assert_record fixtures.tobe_ui_bindings 1 'TO-BE UI reverse-check bindings are incomplete' || true
  fi
}

fixtures_check_derived_evidence_ids() {
  FIXTURES_ROOT=$1
  FIXTURES_TRACE_V2="$FIXTURES_ROOT/expected/trace-v2.json"
  FIXTURES_KNOWN_EVIDENCE="$RUN_TMP/fixtures-known-evidence-ids.txt"
  FIXTURES_DERIVED_EVIDENCE="$RUN_TMP/fixtures-derived-evidence-ids.txt"
  FIXTURES_DERIVED_EVIDENCE_RAW="$RUN_TMP/fixtures-derived-evidence-ids-raw.txt"
  : >"$FIXTURES_DERIVED_EVIDENCE_RAW" || return 70
  jq -r '.evidence[].id' "$FIXTURES_TRACE_V2" | LC_ALL=C sort -u >"$FIXTURES_KNOWN_EVIDENCE" || return 70
  while IFS= read -r FIXTURES_DERIVED_ARTIFACT; do
    test -n "$FIXTURES_DERIVED_ARTIFACT" || continue
    rg --pcre2 -o --no-filename '(?<![A-Z0-9-])E-[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+(?![A-Z0-9-])' "$FIXTURES_DERIVED_ARTIFACT" >>"$FIXTURES_DERIVED_EVIDENCE_RAW"
    FIXTURES_DERIVED_RG_RC=$?
    case "$FIXTURES_DERIVED_RG_RC" in
      0|1) ;;
      *) return 70 ;;
    esac
  done <<EOF
$(find "$FIXTURES_ROOT/expected" -type f \( -name '*.json' -o -name '*.md' -o -name '*.mmd' \) -print | LC_ALL=C sort)
EOF
  LC_ALL=C sort -u "$FIXTURES_DERIVED_EVIDENCE_RAW" >"$FIXTURES_DERIVED_EVIDENCE" || return 70
  if awk 'NR==FNR {known[$0]=1; next} !($0 in known) {invalid=1} END {exit invalid+0}' \
      "$FIXTURES_KNOWN_EVIDENCE" "$FIXTURES_DERIVED_EVIDENCE"; then
    assert_record fixtures.derived_evidence_ids 0 'every evidence ID in derived expected artifacts resolves in trace-v2' || true
  else
    assert_record fixtures.derived_evidence_ids 1 'derived expected artifact contains dangling evidence ID' || true
  fi
}

fixtures_check_artifacts_and_boundaries() {
  FIXTURES_ROOT=$1
  FIXTURES_MERMAID_OK=1
  while IFS= read -r FIXTURES_MERMAID; do
    test -n "$FIXTURES_MERMAID" || continue
    if ! test -s "$FIXTURES_MERMAID" || ! rg -q '^(sequenceDiagram|flowchart[[:space:]])' "$FIXTURES_MERMAID"; then
      FIXTURES_MERMAID_OK=0
    fi
  done <<EOF
$(find "$FIXTURES_ROOT/expected" -type f -name '*.mmd' -print | LC_ALL=C sort)
EOF
  for FIXTURES_UI in "$FIXTURES_ROOT/expected/asis/ui.md" "$FIXTURES_ROOT/expected/tobe/ui.md"; do
    if ! test -s "$FIXTURES_UI" || ! rg -q '^```mermaid$|^flowchart[[:space:]]' "$FIXTURES_UI"; then
      FIXTURES_MERMAID_OK=0
    fi
  done
  if test "$FIXTURES_MERMAID_OK" -eq 1; then
    assert_record fixtures.mermaid_structure 0 'all Mermaid goldens are nonempty with diagram structure' || true
  else
    assert_record fixtures.mermaid_structure 1 'empty or structurally invalid Mermaid golden' || true
  fi

  FIXTURES_OUTPUT_OK=1
  if ! jq -e '.cases[] | select(.id=="adversarial-output-path-escape") | .expected_exit==1 and .expected_reason=="OUTPUT_PATH_ESCAPE"' "$FIXTURES_ROOT/CASES.json" >/dev/null 2>&1; then
    FIXTURES_OUTPUT_OK=0
  fi
  if ! jq -e '[.cases[] | select(.mode=="happy" and has("output_path")) | .output_path] | all(.[]; (startswith("/")|not) and (contains("..")|not))' "$FIXTURES_ROOT/CASES.json" >/dev/null 2>&1; then
    FIXTURES_OUTPUT_OK=0
  fi
  if test "$FIXTURES_OUTPUT_OK" -eq 1; then
    assert_record fixtures.output_paths 0 'happy output paths are bounded and escape case is explicit' || true
  else
    assert_record fixtures.output_paths 1 'unsafe happy output path or missing escape contract' || true
  fi

  FIXTURES_CODE_OUTSIDE=$(find "$SOURCE_ROOT" \
    -path "$SOURCE_ROOT/fixtures" -prune -o \
    -path "$SOURCE_ROOT/.git" -prune -o \
    -type f \( -name '*.tsx' -o -name '*.java' \) -print -quit 2>/dev/null)
  if test -z "$FIXTURES_CODE_OUTSIDE"; then
    assert_record fixtures.code_extensions 0 '.tsx and .java are confined to fixtures' || true
  else
    assert_record fixtures.code_extensions 1 'fixture-only code extension exists outside fixtures' || true
  fi

  FIXTURES_RUNTIME_OK=1
  if test -n "$(find "$FIXTURES_ROOT" -type f \( -name package.json -o -name package-lock.json -o -name yarn.lock -o -name pnpm-lock.yaml -o -name bun.lock -o -name go.mod -o -name Cargo.toml -o -name pom.xml \) -print -quit 2>/dev/null)"; then
    FIXTURES_RUNTIME_OK=0
  fi
  while IFS= read -r FIXTURES_RUNTIME_FILE; do
    test -n "$FIXTURES_RUNTIME_FILE" || continue
    test -x "$FIXTURES_RUNTIME_FILE" && FIXTURES_RUNTIME_OK=0
  done <<EOF
$(find "$FIXTURES_ROOT" -type f -print)
EOF
  if test "$FIXTURES_RUNTIME_OK" -eq 1; then
    assert_record fixtures.no_runtime_surface 0 'no package manifest, lockfile, or executable fixture runtime' || true
  else
    assert_record fixtures.no_runtime_surface 1 'package/runtime surface detected in fixtures' || true
  fi
}

fixtures_check_fake_secret() {
  FIXTURES_ROOT=$1
  FIXTURES_SECRET_FILE="$FIXTURES_ROOT/inputs/secrets/fake-secret.txt"
  FIXTURES_SECRET_OK=1
  FIXTURES_CANARY=''
  if ! jq -e '.fake_secret.path=="inputs/secrets/fake-secret.txt" and .fake_secret.classification=="synthetic-only" and .fake_secret.policy=="must-not-appear-in-emitted-artifacts-or-evidence"' "$FIXTURES_ROOT/CASES.json" >/dev/null 2>&1; then
    FIXTURES_SECRET_OK=0
  fi
  if test -f "$FIXTURES_SECRET_FILE"; then
    FIXTURES_CANARY=$(sed -n '2p' "$FIXTURES_SECRET_FILE")
    case "$FIXTURES_CANARY" in
      FAKE_*_NOT_A_CREDENTIAL) ;;
      *) FIXTURES_SECRET_OK=0 ;;
    esac
  else
    FIXTURES_SECRET_OK=0
  fi
  if test "$FIXTURES_SECRET_OK" -eq 1; then
    assert_record fixtures.fake_secret_classification 0 'fake secret is explicitly synthetic-only' || true
  else
    assert_record fixtures.fake_secret_classification 1 'fake secret classification contract invalid' || true
  fi

  FIXTURES_SECRET_LEAK=0
  if test -n "$FIXTURES_CANARY"; then
    rg -F -q -- "$FIXTURES_CANARY" "$FIXTURES_ROOT/expected" "$EVIDENCE_DIR" 2>/dev/null
    FIXTURES_SECRET_RG_RC=$?
    case "$FIXTURES_SECRET_RG_RC" in
      0) FIXTURES_SECRET_LEAK=1 ;;
      1) ;;
      *) return 70 ;;
    esac
  fi
  if test "$FIXTURES_SECRET_LEAK" -eq 0; then
    assert_record fixtures.fake_secret_non_leak 0 'synthetic canary absent from emitted artifacts and current evidence' || true
  else
    assert_record fixtures.fake_secret_non_leak 1 'synthetic canary leaked to emitted artifact or evidence' || true
  fi
}

fixtures_run_mutation() {
  FIXTURES_MUTATION_NAME=$1
  FIXTURES_MUTATION_ASSERTION=$2
  FIXTURES_MUTATION_ROOT=$3
  FIXTURES_MUTATION_EVIDENCE="$EVIDENCE_DIR/adversarial-$FIXTURES_MUTATION_NAME"
  set +e
  env SENSAI_TEST_FIXTURES_INNER=1 SENSAI_TEST_SOURCE_ROOT="$FIXTURES_MUTATION_ROOT" \
    "$TEST_RUNNER" fixtures --evidence "$FIXTURES_MUTATION_EVIDENCE" >"$RUN_TMP/adversarial-$FIXTURES_MUTATION_NAME.out" 2>&1
  FIXTURES_MUTATION_RC=$?
  evidence_log_command "fixtures-adversarial-$FIXTURES_MUTATION_NAME" "$TEST_RUNNER fixtures <isolated-$FIXTURES_MUTATION_NAME>" "$FIXTURES_MUTATION_RC"
  assert_eq "fixtures.adversarial_${FIXTURES_MUTATION_NAME}_exit" 1 "$FIXTURES_MUTATION_RC" || true
  if test -f "$FIXTURES_MUTATION_EVIDENCE/receipt.json"; then
    assert_jq "fixtures.adversarial_${FIXTURES_MUTATION_NAME}_receipt" ".result==\"ASSERTION_FAILURE\" and .exit==1 and (.failed_assertion_ids|index(\"$FIXTURES_MUTATION_ASSERTION\"))!=null" "$FIXTURES_MUTATION_EVIDENCE/receipt.json" || true
  else
    assert_record "fixtures.adversarial_${FIXTURES_MUTATION_NAME}_receipt" 1 'missing isolated mutation receipt' || true
  fi
}

fixtures_new_mutation_root() {
  FIXTURES_NEW_NAME=$1
  FIXTURES_NEW_ROOT="$RUN_TMP/fixtures-mutations/$FIXTURES_NEW_NAME"
  fixtures_clone_source "$FIXTURES_NEW_ROOT" || return 70
}

fixtures_check_expected_failure_rejections() {
  for FIXTURES_REJECTED_EXIT in 64 70 127; do
    FIXTURES_REJECT_EVIDENCE="$EVIDENCE_DIR/adversarial-expected-reject-$FIXTURES_REJECTED_EXIT"
    set +e
    env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_EXPECT_FIXTURE_FORCED_EXIT="$FIXTURES_REJECTED_EXIT" \
      "$TEST_RUNNER" expect-fail fixture-without-golden --evidence "$FIXTURES_REJECT_EVIDENCE" \
      >"$RUN_TMP/expected-reject-$FIXTURES_REJECTED_EXIT.out" 2>&1
    FIXTURES_REJECT_RC=$?
    evidence_log_command "fixtures-expected-reject-$FIXTURES_REJECTED_EXIT" "$TEST_RUNNER expect-fail fixture-without-golden <forced-$FIXTURES_REJECTED_EXIT>" "$FIXTURES_REJECT_RC"
    assert_eq "fixtures.expected_reject_${FIXTURES_REJECTED_EXIT}_exit" 70 "$FIXTURES_REJECT_RC" || true
    if test -f "$FIXTURES_REJECT_EVIDENCE/receipt.json"; then
      assert_jq "fixtures.expected_reject_${FIXTURES_REJECTED_EXIT}_receipt" ".result==\"INFRASTRUCTURE_ERROR\" and .exit==70 and (.reason_codes|index(\"EXPECTED_FAILURE_INNER_EXIT_$FIXTURES_REJECTED_EXIT\"))!=null" "$FIXTURES_REJECT_EVIDENCE/receipt.json" || true
    else
      assert_record "fixtures.expected_reject_${FIXTURES_REJECTED_EXIT}_receipt" 1 'missing forced-exit rejection receipt' || true
    fi
  done
}

fixtures_run_adversarial_matrix() {
  mkdir -p "$RUN_TMP/fixtures-mutations" || return 70

  fixtures_new_mutation_root missing_inventory || return 70
  fixtures_remove_inventory_path "$FIXTURES_NEW_ROOT" README.md || return 70
  fixtures_run_mutation missing_inventory fixtures.physical_exact_set "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root extra_inventory || return 70
  printf '%s\n' 'missing/ghost.txt' >>"$FIXTURES_NEW_ROOT/fixtures/FILES.txt" || return 70
  LC_ALL=C sort "$FIXTURES_NEW_ROOT/fixtures/FILES.txt" >"$FIXTURES_NEW_ROOT/fixtures/FILES.txt.tmp" || return 70
  mv "$FIXTURES_NEW_ROOT/fixtures/FILES.txt.tmp" "$FIXTURES_NEW_ROOT/fixtures/FILES.txt" || return 70
  fixtures_run_mutation extra_inventory fixtures.physical_exact_set "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root duplicate_inventory || return 70
  printf '%s\n' README.md >>"$FIXTURES_NEW_ROOT/fixtures/FILES.txt" || return 70
  fixtures_run_mutation duplicate_inventory fixtures.inventory_sorted_unique "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root hash_drift || return 70
  printf '%s\n' 'drift' >>"$FIXTURES_NEW_ROOT/fixtures/README.md" || return 70
  fixtures_run_mutation hash_drift fixtures.sha256 "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root malformed_checksum_digest || return 70
  sed '1s/./X/' "$FIXTURES_NEW_ROOT/fixtures/SHA256SUMS" >"$FIXTURES_NEW_ROOT/fixtures/SHA256SUMS.tmp" || return 70
  mv "$FIXTURES_NEW_ROOT/fixtures/SHA256SUMS.tmp" "$FIXTURES_NEW_ROOT/fixtures/SHA256SUMS" || return 70
  fixtures_run_mutation malformed_checksum_digest fixtures.sha256_format "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root symlink_leaf || return 70
  rm "$FIXTURES_NEW_ROOT/fixtures/README.md" || return 70
  ln -s CASES.json "$FIXTURES_NEW_ROOT/fixtures/README.md" || return 70
  fixtures_run_mutation symlink_leaf fixtures.regular_leaf "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root symlink_ancestor || return 70
  cp -R "$FIXTURES_NEW_ROOT/fixtures/inputs/business" "$FIXTURES_NEW_ROOT/business-target" || return 70
  rm -rf "$FIXTURES_NEW_ROOT/fixtures/inputs/business" || return 70
  ln -s "$FIXTURES_NEW_ROOT/business-target" "$FIXTURES_NEW_ROOT/fixtures/inputs/business" || return 70
  fixtures_run_mutation symlink_ancestor fixtures.regular_leaf "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root fifo_leaf || return 70
  mkfifo "$FIXTURES_NEW_ROOT/fixtures/adversarial/runtime.fifo" || return 70
  fixtures_run_mutation fifo_leaf fixtures.regular_leaf "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root lock_leaf || return 70
  printf '%s\n' locked >"$FIXTURES_NEW_ROOT/fixtures/.fixture.lock" || return 70
  fixtures_run_mutation lock_leaf fixtures.physical_exact_set "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root weird_name || return 70
  printf '%s\n' odd >"$FIXTURES_NEW_ROOT/fixtures/adversarial/weird name.txt" || return 70
  fixtures_run_mutation weird_name fixtures.physical_exact_set "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root newline_name || return 70
  FIXTURES_NEWLINE_NAME=$(printf 'adversarial/newline\nname.txt')
  printf '%s\n' odd >"$FIXTURES_NEW_ROOT/fixtures/$FIXTURES_NEWLINE_NAME" || return 70
  find "$FIXTURES_NEW_ROOT/fixtures" -mindepth 1 ! -type d -print \
    | sed "s#^$FIXTURES_NEW_ROOT/fixtures/##" | LC_ALL=C sort >"$RUN_TMP/newline-physical.txt" || return 70
  {
    sed -n 'p' "$FIXTURES_NEW_ROOT/fixtures/FILES.txt"
    printf '%s\n' FILES.txt SHA256SUMS
  } | LC_ALL=C sort >"$RUN_TMP/newline-expected.txt" || return 70
  cmp -s "$RUN_TMP/newline-expected.txt" "$RUN_TMP/newline-physical.txt"
  FIXTURES_NEWLINE_RC=$?
  evidence_log_command fixtures-adversarial-newline_name 'physical exact-set probe <isolated-newline-name>' "$FIXTURES_NEWLINE_RC"
  assert_eq fixtures.adversarial_newline_name_exit 1 "$FIXTURES_NEWLINE_RC" || true

  fixtures_new_mutation_root undeclared_malformed || return 70
  printf '%s\n' '{"broken":' >"$FIXTURES_NEW_ROOT/fixtures/adversarial/undeclared.json" || return 70
  fixtures_add_inventory_path "$FIXTURES_NEW_ROOT" adversarial/undeclared.json || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation undeclared_malformed fixtures.json_syntax "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root happy_without_input || return 70
  jq '(.cases[] | select(.id=="happy-react-source") | .inputs)=[]' "$FIXTURES_NEW_ROOT/fixtures/CASES.json" >"$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" || return 70
  mv "$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" "$FIXTURES_NEW_ROOT/fixtures/CASES.json" || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation happy_without_input fixtures.happy_input_files "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root happy_without_provenance || return 70
  jq '(.cases[] | select(.id=="happy-react-source") | .provenance)=[]' "$FIXTURES_NEW_ROOT/fixtures/CASES.json" >"$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" || return 70
  mv "$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" "$FIXTURES_NEW_ROOT/fixtures/CASES.json" || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation happy_without_provenance fixtures.happy_provenance "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root happy_missing_one_of_five_provenance || return 70
  jq '(.cases[] | select(.id=="happy-tobe-projections") | .provenance) |= map(select(.artifact!="expected/tobe/test.md"))' "$FIXTURES_NEW_ROOT/fixtures/CASES.json" >"$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" || return 70
  mv "$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" "$FIXTURES_NEW_ROOT/fixtures/CASES.json" || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation happy_missing_one_of_five_provenance fixtures.happy_provenance "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root dangling_derived_evidence || return 70
  printf '%s\n' 'evidence_id: E-DANGLING-DERIVED' >>"$FIXTURES_NEW_ROOT/fixtures/expected/asis/ui.md" || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation dangling_derived_evidence fixtures.derived_evidence_ids "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root happy_without_golden || return 70
  rm "$FIXTURES_NEW_ROOT/fixtures/expected/tobe/test.md" || return 70
  fixtures_remove_inventory_path "$FIXTURES_NEW_ROOT" expected/tobe/test.md || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation happy_without_golden fixtures.happy_golden_files "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root invalid_exit || return 70
  jq '(.cases[] | select(.id=="adversarial-duplicate-id") | .expected_exit)=0' "$FIXTURES_NEW_ROOT/fixtures/CASES.json" >"$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" || return 70
  mv "$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" "$FIXTURES_NEW_ROOT/fixtures/CASES.json" || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation invalid_exit fixtures.registry_exact "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root invalid_reason || return 70
  jq '(.cases[] | select(.id=="adversarial-duplicate-id") | .expected_reason)=""' "$FIXTURES_NEW_ROOT/fixtures/CASES.json" >"$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" || return 70
  mv "$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" "$FIXTURES_NEW_ROOT/fixtures/CASES.json" || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation invalid_reason fixtures.registry_exact "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root secret_leak || return 70
  sed -n '2p' "$FIXTURES_NEW_ROOT/fixtures/inputs/secrets/fake-secret.txt" >>"$FIXTURES_NEW_ROOT/fixtures/expected/tobe/story.md" || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation secret_leak fixtures.fake_secret_non_leak "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root package_manifest || return 70
  printf '%s\n' '{}' >"$FIXTURES_NEW_ROOT/fixtures/package.json" || return 70
  fixtures_add_inventory_path "$FIXTURES_NEW_ROOT" package.json || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation package_manifest fixtures.no_runtime_surface "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root code_outside_fixture || return 70
  mkdir -p "$FIXTURES_NEW_ROOT/src" || return 70
  printf '%s\n' 'final class Rogue {}' >"$FIXTURES_NEW_ROOT/src/Rogue.java" || return 70
  fixtures_run_mutation code_outside_fixture fixtures.code_extensions "$FIXTURES_NEW_ROOT"

  fixtures_new_mutation_root output_path_traversal || return 70
  jq '(.cases[] | select(.id=="happy-progress") | .output_path)="../escaped.json"' "$FIXTURES_NEW_ROOT/fixtures/CASES.json" >"$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" || return 70
  mv "$FIXTURES_NEW_ROOT/fixtures/CASES.json.tmp" "$FIXTURES_NEW_ROOT/fixtures/CASES.json" || return 70
  fixtures_refresh_metadata "$FIXTURES_NEW_ROOT" || return 70
  fixtures_run_mutation output_path_traversal fixtures.output_paths "$FIXTURES_NEW_ROOT"
}

case_fixtures() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  FIXTURES_ROOT="$SOURCE_ROOT/fixtures"

  if ! assert_dir fixtures.root "$FIXTURES_ROOT"; then
    evidence_add_reason FIXTURE_CORPUS_MISSING
    return 0
  fi
  assert_file fixtures.registry "$FIXTURES_ROOT/CASES.json" || true
  assert_file fixtures.inventory "$FIXTURES_ROOT/FILES.txt" || true
  assert_file fixtures.checksums "$FIXTURES_ROOT/SHA256SUMS" || true
  if ! test -f "$FIXTURES_ROOT/CASES.json" || ! test -f "$FIXTURES_ROOT/FILES.txt" || ! test -f "$FIXTURES_ROOT/SHA256SUMS"; then
    evidence_add_reason FIXTURE_METADATA_MISSING
    return 0
  fi

  fixtures_check_inventory "$FIXTURES_ROOT" || return 70
  fixtures_check_sha256 "$FIXTURES_ROOT" || return 70
  fixtures_check_registry "$FIXTURES_ROOT" || return 70
  fixtures_check_syntax "$FIXTURES_ROOT" || return 70
  fixtures_check_happy_mappings "$FIXTURES_ROOT" || return 70
  fixtures_check_trace_contracts "$FIXTURES_ROOT" || return 70
  fixtures_check_derived_evidence_ids "$FIXTURES_ROOT" || return 70
  fixtures_check_artifacts_and_boundaries "$FIXTURES_ROOT" || return 70
  fixtures_check_fake_secret "$FIXTURES_ROOT" || return 70

  if test "${SENSAI_TEST_FIXTURES_INNER:-0}" != 1; then
    fixtures_run_adversarial_matrix || return 70
    fixtures_check_expected_failure_rejections || return 70
  fi
}
