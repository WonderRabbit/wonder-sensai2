#!/bin/sh

permissions_resolve_rules() {
  PERMISSIONS_RULE_FILE=$1
  PERMISSIONS_RULE_FILTER=$2
  PERMISSIONS_RULE_SUBJECT=$3
  PERMISSIONS_RULE_ROWS="$RUN_TMP/permission-rule-rows.tsv"
  PERMISSIONS_RESOLVED=ask

  jq -r "$PERMISSIONS_RULE_FILTER | to_entries[] | [.key, .value] | @tsv" \
    "$PERMISSIONS_RULE_FILE" >"$PERMISSIONS_RULE_ROWS" || return 70
  while IFS="$(printf '\t')" read -r PERMISSIONS_PATTERN PERMISSIONS_DECISION; do
    case "$PERMISSIONS_RULE_SUBJECT" in
      $PERMISSIONS_PATTERN) PERMISSIONS_RESOLVED=$PERMISSIONS_DECISION ;;
    esac
  done <"$PERMISSIONS_RULE_ROWS"
  return 0
}

permissions_record_probe() {
  PERMISSIONS_PROBE_GROUP=$1
  PERMISSIONS_PROBE_DOMAIN=$2
  PERMISSIONS_PROBE_FILE=$3
  PERMISSIONS_PROBE_FILTER=$4
  PERMISSIONS_PROBE_SUBJECT=$5
  PERMISSIONS_PROBE_EXPECTED=$6
  PERMISSIONS_PROBE_INDEX=$((PERMISSIONS_PROBE_INDEX + 1))

  permissions_resolve_rules "$PERMISSIONS_PROBE_FILE" "$PERMISSIONS_PROBE_FILTER" \
    "$PERMISSIONS_PROBE_SUBJECT" || return 70
  jq -cn \
    --arg group "$PERMISSIONS_PROBE_GROUP" \
    --arg domain "$PERMISSIONS_PROBE_DOMAIN" \
    --arg subject "$PERMISSIONS_PROBE_SUBJECT" \
    --arg expected "$PERMISSIONS_PROBE_EXPECTED" \
    --arg resolved "$PERMISSIONS_RESOLVED" \
    '{group:$group,domain:$domain,subject:$subject,expected:$expected,resolved:$resolved,pass:($expected == $resolved)}' \
    >>"$PERMISSIONS_PROBE_JSONL" || return 70
  assert_eq "permissions.probe_$PERMISSIONS_PROBE_INDEX" \
    "$PERMISSIONS_PROBE_EXPECTED" "$PERMISSIONS_RESOLVED" || true
}

permissions_extract_agents() {
  PERMISSIONS_LEAD_SOURCE="$SOURCE_ROOT/output/agents/sensai-analysis-lead.md"
  PERMISSIONS_PEER_SOURCE="$SOURCE_ROOT/output/agents/sensai-evidence-peer.md"
  PERMISSIONS_LEAD_JSON="$RUN_TMP/permission-lead.json"
  PERMISSIONS_PEER_JSON="$RUN_TMP/permission-peer.json"
  yq --front-matter=extract -o=json '.' "$PERMISSIONS_LEAD_SOURCE" \
    >"$PERMISSIONS_LEAD_JSON" || return 70
  yq --front-matter=extract -o=json '.' "$PERMISSIONS_PEER_SOURCE" \
    >"$PERMISSIONS_PEER_JSON" || return 70
}

permissions_check_exact_allows() {
  PERMISSIONS_CONFIG=$1
  PERMISSIONS_EXPECTED_SKILLS="$RUN_TMP/permission-expected-skills.txt"
  PERMISSIONS_CONFIG_SKILLS="$RUN_TMP/permission-config-skills.txt"
  PERMISSIONS_LEAD_SKILLS="$RUN_TMP/permission-lead-skills.txt"
  printf '%s\n' \
    sensai-business-trace sensai-checklist sensai-convention-extract \
    sensai-evidence-first sensai-mermaid-sequence sensai-react-trace \
    sensai-spec-evidence sensai-stack-discovery sensai-ui-definition \
    sensai-vertx-trace >"$PERMISSIONS_EXPECTED_SKILLS" || return 70
  jq -r '.permission.skill | keys_unsorted[1:][]' "$PERMISSIONS_CONFIG" \
    >"$PERMISSIONS_CONFIG_SKILLS" || return 70
  jq -r '.permission.skill | keys_unsorted[1:][]' "$PERMISSIONS_LEAD_JSON" \
    >"$PERMISSIONS_LEAD_SKILLS" || return 70

  if cmp -s "$PERMISSIONS_EXPECTED_SKILLS" "$PERMISSIONS_CONFIG_SKILLS" && \
     cmp -s "$PERMISSIONS_EXPECTED_SKILLS" "$PERMISSIONS_LEAD_SKILLS" && \
     jq -e '
       .permission.skill["*"] == "deny" and
       all(.permission.skill | to_entries[1:][]; .value == "allow") and
       .permission.task == {"*":"deny","sensai-evidence-peer":"allow"}
     ' "$PERMISSIONS_CONFIG" >/dev/null 2>&1 && \
     jq -e '
       .permission.skill["*"] == "deny" and
       all(.permission.skill | to_entries[1:][]; .value == "allow") and
       .permission.task == {"*":"deny","sensai-evidence-peer":"allow"}
     ' "$PERMISSIONS_LEAD_JSON" >/dev/null 2>&1; then
    assert_record permissions.exact_allows 0 'config와 lead는 입학된 10개 skill과 peer task 하나만 허용함' || true
  else
    assert_record permissions.exact_allows 1 'config 또는 lead의 skill/task 허용목록이 exact catalog와 다름' || true
  fi

  assert_jq permissions.peer_boundaries '
    .permission.edit == "deny" and
    .permission.task == "deny" and
    .permission.todowrite == "deny" and
    .permission.question == "deny" and
    .mode == "subagent" and .hidden == true
  ' "$PERMISSIONS_PEER_JSON" || true
}

permissions_run_projection() {
  PERMISSIONS_CONFIG=$1
  PERMISSIONS_PROBE_INDEX=0
  PERMISSIONS_PROBE_JSONL="$RUN_TMP/permission-probes.jsonl"
  : >"$PERMISSIONS_PROBE_JSONL" || return 70

  permissions_record_probe projection read "$PERMISSIONS_CONFIG" '.permission.read' \
    'src/app.ts' allow || return 70
  for PERMISSIONS_SECRET_PATH in \
    '.env' 'service/.env.local' 'server.pem' 'keys/id_rsa_prod' \
    'cloud-credentials.json' 'config/secrets.yaml' 'auth.json' \
    'home/.ssh/config' 'home/.aws/credentials' \
    'home/.config/opencode/opencode.json' 'home/.local/share/opencode/auth.json'; do
    permissions_record_probe projection read "$PERMISSIONS_CONFIG" '.permission.read' \
      "$PERMISSIONS_SECRET_PATH" deny || return 70
  done

  permissions_record_probe projection edit "$PERMISSIONS_CONFIG" '.permission.edit' \
    'docs/analysis/missions/M-001/trace.json' allow || return 70
  permissions_record_probe projection edit "$PERMISSIONS_CONFIG" '.permission.edit' \
    'README.md' deny || return 70
  permissions_record_probe projection edit "$PERMISSIONS_CONFIG" '.permission.edit' \
    'docs/analysis/missions/../escape.json' deny || return 70
  permissions_record_probe projection task "$PERMISSIONS_CONFIG" '.permission.task' \
    'sensai-evidence-peer' allow || return 70
  permissions_record_probe projection task "$PERMISSIONS_CONFIG" '.permission.task' \
    'sensai-analysis-lead' deny || return 70
  permissions_record_probe projection task "$PERMISSIONS_CONFIG" '.permission.task' \
    'rogue-peer' deny || return 70

  while IFS= read -r PERMISSIONS_SKILL_PATH; do
    PERMISSIONS_SKILL_NAME=${PERMISSIONS_SKILL_PATH#skills/}
    PERMISSIONS_SKILL_NAME=${PERMISSIONS_SKILL_NAME%/SKILL.md}
    if rg -q --no-config -x "$PERMISSIONS_SKILL_NAME" "$PERMISSIONS_EXPECTED_SKILLS"; then
      PERMISSIONS_SKILL_EXPECTED=allow
    else
      PERMISSIONS_SKILL_MATCH_RC=$?
      test "$PERMISSIONS_SKILL_MATCH_RC" -eq 1 || return 70
      PERMISSIONS_SKILL_EXPECTED=deny
    fi
    permissions_record_probe projection skill "$PERMISSIONS_CONFIG" '.permission.skill' \
      "$PERMISSIONS_SKILL_NAME" "$PERMISSIONS_SKILL_EXPECTED" || return 70
  done <"$SOURCE_ROOT/tests/contracts/skills.txt"
  permissions_record_probe projection skill "$PERMISSIONS_CONFIG" '.permission.skill' \
    'sensai-rogue' deny || return 70

  for PERMISSIONS_ALLOWED_COMMAND in \
    'fd' 'fd --print0 src' 'rg --json --no-config 주문 src' \
    'sg --json -p call src' 'jq -e . trace.json' 'yq -o=json . openapi.yaml' \
    'mdq #{2} README.md' 'mmdc --input flow.mmd --output docs/analysis/missions/M-001/flow.svg'; do
    permissions_record_probe projection bash "$PERMISSIONS_CONFIG" '.permission.bash' \
      "$PERMISSIONS_ALLOWED_COMMAND" allow || return 70
  done

  PERMISSIONS_PROJECTION_FAILED=$(jq -s 'map(select(.group == "projection" and (.pass | not))) | length' \
    "$PERMISSIONS_PROBE_JSONL") || return 70
  assert_eq permissions.ordered_projection 0 "$PERMISSIONS_PROJECTION_FAILED" || true

  for PERMISSIONS_BYPASS_COMMAND in \
    'grep 주문 src' 'find src -type f' 'cat README.md' 'ls src' \
    'Select-String 주문 src' 'gci src' 'findstr 주문 src' 'exec rg 주문 src' \
    'rg --json 주문 src | jq .' 'rg --json 주문 src > out.json' \
    'rg --json 주문 src < in.txt' 'rg `cat pattern` src' 'rg $(cat pattern) src' \
    'rg 주문 src; cat README.md' 'rg 주문 src && cat README.md' \
    'rg 주문 src || cat README.md' 'fd --exec rm {}' 'fd -x rm {}' \
    'fd -X rm' 'rg --pre cat 주문 src' 'sg --rewrite 새값 -p 패턴 src' \
    'sg -r 새값 -p 패턴 src' 'sg --update-all -p 패턴 src' \
    'yq -i . openapi.yaml' 'yq --inplace . openapi.yaml' \
    'rg --json 값 .env' 'rg --json 값 keys/id_rsa_prod' \
    'rg --json 값 home/.config/opencode/opencode.json'; do
    permissions_record_probe bypass bash "$PERMISSIONS_CONFIG" '.permission.bash' \
      "$PERMISSIONS_BYPASS_COMMAND" deny || return 70
  done
  PERMISSIONS_BYPASS_FAILED=$(jq -s 'map(select(.group == "bypass" and (.pass | not))) | length' \
    "$PERMISSIONS_PROBE_JSONL") || return 70
  assert_eq permissions.bash_bypass_projection 0 "$PERMISSIONS_BYPASS_FAILED" || true

  jq -s 'map(select(.group == "projection"))' "$PERMISSIONS_PROBE_JSONL" \
    >"$EVIDENCE_DIR/permission-projection.json" || return 70
  jq -s 'map(select(.group == "bypass"))' "$PERMISSIONS_PROBE_JSONL" \
    >"$EVIDENCE_DIR/bypass-probes.json" || return 70
}

permissions_check_runtime_boundaries() {
  PERMISSIONS_CONFIG=$1
  PERMISSIONS_BANNED_PATHS="$RUN_TMP/permission-banned-paths.txt"
  : >"$PERMISSIONS_BANNED_PATHS" || return 70
  for PERMISSIONS_BANNED_PATH in \
    opencode.json agents commands skills schemas recipes .opencode \
    output/mcp output/plugin output/plugins output/tool output/tools; do
    if test -e "$SOURCE_ROOT/$PERMISSIONS_BANNED_PATH"; then
      printf '%s\n' "$PERMISSIONS_BANNED_PATH" >>"$PERMISSIONS_BANNED_PATHS" || return 70
    fi
  done
  if test -s "$PERMISSIONS_BANNED_PATHS"; then
    assert_record permissions.runtime_source_root 1 'runtime duplicate 또는 extension surface가 output 밖/안에 존재함' || true
  else
    assert_record permissions.runtime_source_root 0 'OpenCode runtime source는 output에만 있고 extension surface는 없음' || true
  fi

  PERMISSIONS_SOURCE_FILES="$RUN_TMP/permission-source-files.txt"
  PERMISSIONS_EXPECTED_SOURCE_FILES="$RUN_TMP/permission-expected-source-files.txt"
  find "$SOURCE_ROOT" \
    -path "$SOURCE_ROOT/.git" -prune -o \
    -path "$SOURCE_ROOT/.omo" -prune -o \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
      -o -name '*.mjs' -o -name '*.cjs' -o -name '*.go' -o -name '*.java' \) \
    -print | sed "s#^$SOURCE_ROOT/##" | LC_ALL=C sort >"$PERMISSIONS_SOURCE_FILES" || return 70
  printf '%s\n' \
    'fixtures/inputs/legacy-react/src/OrdersPage.tsx' \
    'fixtures/inputs/legacy-vertx/src/main/java/example/OrderVerticle.java' \
    >"$PERMISSIONS_EXPECTED_SOURCE_FILES" || return 70
  if cmp -s "$PERMISSIONS_EXPECTED_SOURCE_FILES" "$PERMISSIONS_SOURCE_FILES"; then
    assert_record permissions.fixture_source_exception 0 '코드 source 예외는 고정 fixture 두 개뿐임' || true
  else
    assert_record permissions.fixture_source_exception 1 '제품 source 또는 승인되지 않은 fixture source가 존재함' || true
  fi

  PERMISSIONS_PACKAGE_FILES="$RUN_TMP/permission-package-files.txt"
  find "$SOURCE_ROOT" \
    -path "$SOURCE_ROOT/.git" -prune -o \
    -path "$SOURCE_ROOT/.omo" -prune -o \
    -type f \( -name package.json -o -name package-lock.json -o -name bun.lock \
      -o -name bun.lockb -o -name pnpm-lock.yaml -o -name yarn.lock \
      -o -name tsconfig.json -o -name biome.json -o -name biome.jsonc \
      -o -name go.mod -o -name go.sum \) -print \
    | sed "s#^$SOURCE_ROOT/##" | LC_ALL=C sort >"$PERMISSIONS_PACKAGE_FILES" || return 70
  if test -s "$PERMISSIONS_PACKAGE_FILES"; then
    assert_record permissions.no_product_runtime 1 'Node TypeScript Go product runtime 파일이 존재함' || true
  else
    assert_record permissions.no_product_runtime 0 'Node TypeScript Go product runtime 파일이 없음' || true
  fi

  PERMISSIONS_BANNED_PATHS_JSON="$RUN_TMP/permission-banned-paths.json"
  PERMISSIONS_SOURCE_FILES_JSON="$RUN_TMP/permission-source-files.json"
  PERMISSIONS_PACKAGE_FILES_JSON="$RUN_TMP/permission-package-files.json"
  jq -Rsc 'split("\n") | map(select(length > 0))' "$PERMISSIONS_BANNED_PATHS" \
    >"$PERMISSIONS_BANNED_PATHS_JSON" || return 70
  jq -Rsc 'split("\n") | map(select(length > 0))' "$PERMISSIONS_SOURCE_FILES" \
    >"$PERMISSIONS_SOURCE_FILES_JSON" || return 70
  jq -Rsc 'split("\n") | map(select(length > 0))' "$PERMISSIONS_PACKAGE_FILES" \
    >"$PERMISSIONS_PACKAGE_FILES_JSON" || return 70

  jq -n \
    --slurpfile runtime_paths "$PERMISSIONS_BANNED_PATHS_JSON" \
    --slurpfile source_files "$PERMISSIONS_SOURCE_FILES_JSON" \
    --slurpfile package_files "$PERMISSIONS_PACKAGE_FILES_JSON" \
    '{banned_runtime_paths:$runtime_paths[0],code_source_files:$source_files[0],product_runtime_files:$package_files[0],fixture_exception_exact:true}' \
    >"$EVIDENCE_DIR/source-inventory.json" || return 70
}

permissions_check_secrets() {
  PERMISSIONS_SECRET_TARGETS="$RUN_TMP/permission-secret-targets.txt"
  : >"$PERMISSIONS_SECRET_TARGETS" || return 70
  for PERMISSIONS_SECRET_TARGET in "$SOURCE_ROOT/output" "$SOURCE_ROOT/docs/analysis" "$SOURCE_ROOT/.omo/evidence"; do
    test -d "$PERMISSIONS_SECRET_TARGET" && printf '%s\n' "$PERMISSIONS_SECRET_TARGET" \
      >>"$PERMISSIONS_SECRET_TARGETS"
  done

  PERMISSIONS_SECRET_HITS="$RUN_TMP/permission-secret-hits.txt"
  PERMISSIONS_CANARY_HITS="$RUN_TMP/permission-canary-hits.txt"
  : >"$PERMISSIONS_SECRET_HITS" || return 70
  : >"$PERMISSIONS_CANARY_HITS" || return 70
  while IFS= read -r PERMISSIONS_SECRET_TARGET; do
    rg -l --hidden --no-config \
      'AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}' \
      "$PERMISSIONS_SECRET_TARGET" >>"$PERMISSIONS_SECRET_HITS" 2>/dev/null
    PERMISSIONS_SCAN_RC=$?
    case "$PERMISSIONS_SCAN_RC" in 0|1) ;; *) return 70 ;; esac
    rg -l --hidden --no-config --fixed-strings \
      'FAKE_SENSAI_SECRET_CANARY_7B4C2A1E_NOT_A_CREDENTIAL' \
      "$PERMISSIONS_SECRET_TARGET" >>"$PERMISSIONS_CANARY_HITS" 2>/dev/null
    PERMISSIONS_SCAN_RC=$?
    case "$PERMISSIONS_SCAN_RC" in 0|1) ;; *) return 70 ;; esac
  done <"$PERMISSIONS_SECRET_TARGETS"

  LC_ALL=C sort -u "$PERMISSIONS_SECRET_HITS" -o "$PERMISSIONS_SECRET_HITS" || return 70
  LC_ALL=C sort -u "$PERMISSIONS_CANARY_HITS" -o "$PERMISSIONS_CANARY_HITS" || return 70
  if test ! -s "$PERMISSIONS_SECRET_HITS" && test ! -s "$PERMISSIONS_CANARY_HITS" && \
     test -f "$SOURCE_ROOT/fixtures/inputs/secrets/fake-secret.txt"; then
    assert_record permissions.secret_scan 0 'artifact와 evidence에 실제 secret 패턴 및 fixture canary 전파가 없음' || true
  else
    assert_record permissions.secret_scan 1 'artifact 또는 evidence에서 secret 패턴이나 fixture canary 전파를 찾음' || true
  fi
  PERMISSIONS_SECRET_HITS_JSON="$RUN_TMP/permission-secret-hits.json"
  PERMISSIONS_CANARY_HITS_JSON="$RUN_TMP/permission-canary-hits.json"
  jq -Rsc 'split("\n") | map(select(length > 0))' "$PERMISSIONS_SECRET_HITS" \
    >"$PERMISSIONS_SECRET_HITS_JSON" || return 70
  jq -Rsc 'split("\n") | map(select(length > 0))' "$PERMISSIONS_CANARY_HITS" \
    >"$PERMISSIONS_CANARY_HITS_JSON" || return 70
  jq -n \
    --slurpfile secret_hits "$PERMISSIONS_SECRET_HITS_JSON" \
    --slurpfile canary_hits "$PERMISSIONS_CANARY_HITS_JSON" \
    '{secret_hits:$secret_hits[0],fixture_canary_hits:$canary_hits[0],fixture_source_present:true}' \
    >"$EVIDENCE_DIR/secret-scan.json" || return 70
}

permissions_write_hashes() {
  PERMISSIONS_HASH_LINES="$RUN_TMP/permission-hashes.tsv"
  : >"$PERMISSIONS_HASH_LINES" || return 70
  for PERMISSIONS_HASH_PATH in \
    output/AGENTS.md output/opencode.json \
    output/agents/sensai-analysis-lead.md output/agents/sensai-evidence-peer.md \
    tests/cases/permissions.sh tests/test.sh; do
    tooling_sha256_file "$SOURCE_ROOT/$PERMISSIONS_HASH_PATH" || return 70
    printf '%s\t%s\n' "$PERMISSIONS_HASH_PATH" "$TOOLING_SHA256" \
      >>"$PERMISSIONS_HASH_LINES" || return 70
  done
  jq -Rn '[inputs | split("\t") | {path:.[0],sha256:.[1]}]' \
    <"$PERMISSIONS_HASH_LINES" >"$EVIDENCE_DIR/current-hashes.json" || return 70
}

permissions_clone_source() {
  PERMISSIONS_CLONE_ROOT=$1
  mkdir -p "$PERMISSIONS_CLONE_ROOT/output/agents" "$PERMISSIONS_CLONE_ROOT/tests/contracts" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$PERMISSIONS_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$PERMISSIONS_CLONE_ROOT/" || return 70
  cp "$SOURCE_ROOT/output/AGENTS.md" "$SOURCE_ROOT/output/opencode.json" \
    "$SOURCE_ROOT/output/toolchain.lock.json" "$PERMISSIONS_CLONE_ROOT/output/" || return 70
  cp "$SOURCE_ROOT/output/agents/sensai-analysis-lead.md" \
    "$SOURCE_ROOT/output/agents/sensai-evidence-peer.md" \
    "$PERMISSIONS_CLONE_ROOT/output/agents/" || return 70
}

permissions_run_overlap_mutation() {
  PERMISSIONS_MUTATION_ROOT="$RUN_TMP/permission-overlap-source"
  PERMISSIONS_MUTATION_EVIDENCE="$EVIDENCE_DIR/adversarial-overlap"
  permissions_clone_source "$PERMISSIONS_MUTATION_ROOT" || return 70
  jq '
    .permission.bash |=
      (to_entries as $rules |
       ([{"key":"*|*","value":"deny"}] + ($rules | map(select(.key != "*|*")))) |
       from_entries)
  ' "$PERMISSIONS_MUTATION_ROOT/output/opencode.json" \
    >"$PERMISSIONS_MUTATION_ROOT/output/opencode.json.tmp" && \
    mv "$PERMISSIONS_MUTATION_ROOT/output/opencode.json.tmp" \
      "$PERMISSIONS_MUTATION_ROOT/output/opencode.json" || return 70

  set +e
  env SENSAI_TEST_PERMISSIONS_INNER=1 SENSAI_TEST_SOURCE_ROOT="$PERMISSIONS_MUTATION_ROOT" \
    "$TEST_RUNNER" permissions --evidence "$PERMISSIONS_MUTATION_EVIDENCE" \
    >"$RUN_TMP/permission-overlap.out" 2>&1
  PERMISSIONS_MUTATION_RC=$?
  evidence_log_command permission-overlap-mutation \
    "$TEST_RUNNER permissions <isolated-reordered-overlap>" "$PERMISSIONS_MUTATION_RC"
  case "$PERMISSIONS_MUTATION_RC" in 64|70|127) return 70 ;; esac
  assert_eq permissions.overlap_mutation_exit 1 "$PERMISSIONS_MUTATION_RC" || true
  if test -f "$PERMISSIONS_MUTATION_EVIDENCE/receipt.json"; then
    assert_jq permissions.overlap_mutation_named_failure '
      .result == "ASSERTION_FAILURE" and .exit == 1 and
      (.failed_assertion_ids | index("permissions.bash_bypass_projection")) != null
    ' "$PERMISSIONS_MUTATION_EVIDENCE/receipt.json" || true
  else
    assert_record permissions.overlap_mutation_receipt 1 'mutation receipt가 없음' || true
  fi
}

case_permissions() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  PERMISSIONS_CONFIG="$SOURCE_ROOT/output/opencode.json"
  assert_file permissions.config "$PERMISSIONS_CONFIG" || true
  assert_file permissions.lead "$SOURCE_ROOT/output/agents/sensai-analysis-lead.md" || true
  assert_file permissions.peer "$SOURCE_ROOT/output/agents/sensai-evidence-peer.md" || true
  if ! jq empty "$PERMISSIONS_CONFIG" >/dev/null 2>&1; then
    assert_record permissions.config_json 1 'opencode.json parse 실패' || true
    return 0
  fi
  assert_record permissions.config_json 0 'opencode.json parse 성공' || true
  permissions_extract_agents || return 70
  permissions_check_exact_allows "$PERMISSIONS_CONFIG" || return 70
  permissions_run_projection "$PERMISSIONS_CONFIG" || return 70

  assert_jq permissions.external_directory '.permission.external_directory == "deny"' \
    "$PERMISSIONS_CONFIG" || true
  assert_jq permissions.forbidden_extension_config '
    . as $root |
    (["mcp","plugin","plugins","tools","customTools","custom_tools"] |
      all(. as $key | $root | has($key) | not))
  ' "$PERMISSIONS_CONFIG" || true
  if rg -q --no-config '운영체제 샌드박스가 아니다' "$SOURCE_ROOT/output/AGENTS.md" && \
     rg -q --no-config '격리를 제공한다고 주장하지 않는다' "$SOURCE_ROOT/output/AGENTS.md"; then
    assert_record permissions.os_sandbox_nonclaim 0 'prompt와 permission의 OS sandbox 비보장을 명시함' || true
  else
    assert_record permissions.os_sandbox_nonclaim 1 'OS sandbox 비보장 문구가 없음' || true
  fi

  if test "${SENSAI_TEST_PERMISSIONS_INNER:-0}" != 1; then
    permissions_check_runtime_boundaries "$PERMISSIONS_CONFIG" || return 70
    permissions_check_secrets || return 70
    permissions_run_overlap_mutation || return 70
  else
    jq -n '{skipped:true,reason:"isolated permission mutation"}' \
      >"$EVIDENCE_DIR/source-inventory.json" || return 70
    jq -n '{skipped:true,reason:"isolated permission mutation"}' \
      >"$EVIDENCE_DIR/secret-scan.json" || return 70
  fi
  permissions_write_hashes || return 70
}
