#!/bin/sh

permissions_check_matcher_1183() {
  # OpenCode v1.18.3 wildcard.ts와 permission/index.ts의 관찰 가능한 경계만 고정한다.
  PERMISSIONS_MATCHER_FILE="$RUN_TMP/opencode-1.18.3-matcher.json"
  jq -n '{
    slash:{"*":"deny","codegraph query --path . --json '\''*'\''":"allow"},
    optional:{"*":"deny","rg *":"allow"},
    ordered:{"a*":"allow","*b":"deny"},
    case:{"*":"deny","RG *":"allow"}
  }' >"$PERMISSIONS_MATCHER_FILE" || return 70

  permissions_record_probe matcher slash "$PERMISSIONS_MATCHER_FILE" '.slash' \
    "codegraph query --path . --json 'src/orders/OrderService'" allow || return 70
  permissions_record_probe matcher slash "$PERMISSIONS_MATCHER_FILE" '.slash' \
    "codegraph query --path . --json 'src\\orders\\OrderService'" allow || return 70
  permissions_record_probe matcher optional "$PERMISSIONS_MATCHER_FILE" '.optional' \
    'rg' allow || return 70
  permissions_record_probe matcher ordered "$PERMISSIONS_MATCHER_FILE" '.ordered' \
    'ab' deny || return 70
  permissions_record_probe matcher case "$PERMISSIONS_MATCHER_FILE" '.case' \
    'rg value' deny posix || return 70
  permissions_record_probe matcher case "$PERMISSIONS_MATCHER_FILE" '.case' \
    'rg value' allow win32 || return 70

  PERMISSIONS_MATCHER_FAILED=$(jq -s \
    'map(select(.group == "matcher" and (.pass | not))) | length' \
    "$PERMISSIONS_PROBE_JSONL") || return 70
  assert_eq permissions.opencode_1_18_3_matcher 0 "$PERMISSIONS_MATCHER_FAILED" || true
  jq -s 'map(select(.group == "matcher"))' "$PERMISSIONS_PROBE_JSONL" \
    >"$EVIDENCE_DIR/opencode-1.18.3-matcher.json" || return 70
}

permissions_run_codegraph_projection() {
  PERMISSIONS_CONFIG=$1
  for PERMISSIONS_CODEGRAPH_ALLOWED in \
    'codegraph --version' \
    'codegraph status . --json' \
    "codegraph query --path . --limit 1 --json 'src/orders/OrderService'" \
    "codegraph query --path . --limit 10 --json 'src/orders/OrderService'" \
    "codegraph query --path . --limit 10 --json 'src\\orders\\OrderService'" \
    "codegraph explore --path . --max-files 1 'order service handler'" \
    "codegraph explore --path . --max-files 8 'order service handler'" \
    "codegraph node --path . 'example.OrderService.handle'" \
    "codegraph callers --path . --limit 1 --json 'example.OrderService.handle'" \
    "codegraph callers --path . --limit 20 --json 'example.OrderService.handle'" \
    "codegraph impact --path . --depth 1 --json 'example.OrderService.handle'" \
    "codegraph impact --path . --depth 3 --json 'example.OrderService.handle'"; do
    permissions_record_probe codegraph-happy bash "$PERMISSIONS_CONFIG" '.permission.bash' \
      "$PERMISSIONS_CODEGRAPH_ALLOWED" allow || return 70
  done

  for PERMISSIONS_CODEGRAPH_DENIED in \
    'codegraph' 'codegraph status' 'codegraph status .. --json' \
    "codegraph query --path . --limit 0 --json 'orders'" \
    "codegraph query --path . --limit 11 --json 'orders'" \
    "codegraph query --path /tmp/repo --limit 10 --json 'orders'" \
    "codegraph query --path . --limit 10 --json 'orders' extra" \
    "codegraph explore --path . --max-files 0 'orders'" \
    "codegraph explore --path . --max-files 9 'orders'" \
    "codegraph node --path . 'example.OrderService.handle' extra" \
    "codegraph callers --path . --limit 21 --json 'example.OrderService.handle'" \
    "codegraph impact --path . --depth 4 --json 'example.OrderService.handle'" \
    'codegraph serve --mcp' 'codegraph init .' 'codegraph index .' 'codegraph sync .' \
    'codegraph uninit .' 'codegraph install' 'codegraph upgrade' \
    "codegraph query --path . --limit 10 --json '.env'" \
    "codegraph query --path . --limit 10 --json 'keys/id_rsa_prod'" \
    "codegraph query --path . --limit 10 --json 'orders' > out.json" \
    'codegraph query --path . --limit 10 --json $(cat .env)' \
    'codegraph query --path . --limit 10 --json `cat .env`' \
    "codegraph query --path . --limit 10 --json 'orders'''" \
    "codegraph query --path . --limit 10 --json 'orders\"suffix'"; do
    permissions_record_probe codegraph-adversarial bash "$PERMISSIONS_CONFIG" '.permission.bash' \
      "$PERMISSIONS_CODEGRAPH_DENIED" deny || return 70
  done

  PERMISSIONS_CODEGRAPH_TAB=$(printf "codegraph query --path . --limit 10 --json 'orders'\t--path\t'/tmp/repo'") || return 70
  PERMISSIONS_CODEGRAPH_CR=$(printf "codegraph query --path . --limit 10 --json 'orders'\r--path\r'/tmp/repo'") || return 70
  PERMISSIONS_CODEGRAPH_NEWLINE="codegraph query --path . --limit 10 --json 'orders
secrets'"
  for PERMISSIONS_CODEGRAPH_CONTROL in \
    "$PERMISSIONS_CODEGRAPH_TAB" "$PERMISSIONS_CODEGRAPH_CR" "$PERMISSIONS_CODEGRAPH_NEWLINE"; do
    permissions_record_probe codegraph-adversarial bash "$PERMISSIONS_CONFIG" '.permission.bash' \
      "$PERMISSIONS_CODEGRAPH_CONTROL" deny || return 70
  done

  PERMISSIONS_CODEGRAPH_HAPPY_FAILED=$(jq -s \
    'map(select(.group == "codegraph-happy" and (.pass | not))) | length' \
    "$PERMISSIONS_PROBE_JSONL") || return 70
  assert_eq permissions.codegraph_exact_allowlist 0 \
    "$PERMISSIONS_CODEGRAPH_HAPPY_FAILED" || true
  PERMISSIONS_CODEGRAPH_ADVERSARIAL_FAILED=$(jq -s \
    'map(select(.group == "codegraph-adversarial" and (.pass | not))) | length' \
    "$PERMISSIONS_PROBE_JSONL") || return 70
  assert_eq permissions.codegraph_negative_oracle 0 \
    "$PERMISSIONS_CODEGRAPH_ADVERSARIAL_FAILED" || true
  assert_jq permissions.codegraph_exact_cli_order '
    def expected_codegraph_cli:
      ["codegraph --version","codegraph status . --json"] +
      [range(1;11) | "codegraph query --path . --limit \(.) --json '\''*'\''"] +
      [range(1;9) | "codegraph explore --path . --max-files \(.) '\''*'\''"] +
      ["codegraph node --path . '\''*'\''"] +
      [range(1;21) | "codegraph callers --path . --limit \(.) --json '\''*'\''"] +
      [range(1;4) | "codegraph impact --path . --depth \(.) --json '\''*'\''"];
    (.permission.bash | to_entries) as $rules |
    ($rules | map(.key) | index("codegraph --version")) as $first |
    ($rules | map(.key) | index("codegraph *'\'' *'\''*")) as $after |
    ($first != null and $after != null and $first < $after) and
    (($rules[$first:$after] | map({key:.key,value:.value})) ==
      (expected_codegraph_cli | map({key:.,value:"allow"}))) and
    (.permission.bash | has("codegraph *\\*")) == false
  ' "$PERMISSIONS_CONFIG" || true

  jq -s 'map(select(.group == "codegraph-happy"))' "$PERMISSIONS_PROBE_JSONL" \
    >"$EVIDENCE_DIR/happy.json" || return 70
  jq -s 'map(select(.group == "codegraph-adversarial"))' "$PERMISSIONS_PROBE_JSONL" \
    >"$EVIDENCE_DIR/adversarial.json" || return 70
}
