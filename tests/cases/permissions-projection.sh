#!/bin/sh

permissions_extract_agents() {
  PERMISSIONS_LEAD_SOURCE="$SOURCE_ROOT/output/agents/sensai-analysis-lead.md"
  PERMISSIONS_PEER_SOURCE="$SOURCE_ROOT/output/agents/sensai-evidence-peer.md"
  PERMISSIONS_LEAD_JSON="$RUN_TMP/permission-lead.json"
  PERMISSIONS_PEER_JSON="$RUN_TMP/permission-peer.json"
  yq --front-matter=extract -o=json '.' "$PERMISSIONS_LEAD_SOURCE" >"$PERMISSIONS_LEAD_JSON" || return 70
  yq --front-matter=extract -o=json '.' "$PERMISSIONS_PEER_SOURCE" >"$PERMISSIONS_PEER_JSON" || return 70
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

  assert_jq permissions.codegraph_mcp_exact_order '
    (.permission | keys_unsorted) == [
      "read","edit","bash","task","skill",
      "codegraph_*","codegraph_explore",
      "external_directory","todowrite","question","webfetch","websearch",
      "lsp","doom_loop"
    ] and
    .permission["codegraph_*"] == "deny" and
    .permission.codegraph_explore == "ask"
  ' "$PERMISSIONS_CONFIG" || true
}

permissions_run_projection() {
  PERMISSIONS_CONFIG=$1
  PERMISSIONS_PROBE_INDEX=0
  PERMISSIONS_PROBE_JSONL="$RUN_TMP/permission-probes.jsonl"
  : >"$PERMISSIONS_PROBE_JSONL" || return 70

  permissions_record_probe projection read "$PERMISSIONS_CONFIG" '.permission.read' 'src/app.ts' allow || return 70
  for PERMISSIONS_SECRET_PATH in \
    '.env' 'service/.env.local' 'server.pem' 'keys/id_rsa_prod' \
    'cloud-credentials.json' 'config/secrets.yaml' 'auth.json' \
    'home/.ssh/config' 'home/.aws/credentials' \
    'home/.config/opencode/opencode.json' 'home/.local/share/opencode/auth.json'; do
    permissions_record_probe projection read "$PERMISSIONS_CONFIG" '.permission.read' "$PERMISSIONS_SECRET_PATH" deny || return 70
  done

  permissions_record_probe projection edit "$PERMISSIONS_CONFIG" '.permission.edit' 'docs/analysis/missions/M-001/trace.json' allow || return 70
  permissions_record_probe projection edit "$PERMISSIONS_CONFIG" '.permission.edit' 'README.md' deny || return 70
  permissions_record_probe projection edit "$PERMISSIONS_CONFIG" '.permission.edit' 'docs/analysis/missions/../escape.json' deny || return 70
  permissions_record_probe projection task "$PERMISSIONS_CONFIG" '.permission.task' 'sensai-evidence-peer' allow || return 70
  permissions_record_probe projection task "$PERMISSIONS_CONFIG" '.permission.task' 'sensai-analysis-lead' deny || return 70
  permissions_record_probe projection task "$PERMISSIONS_CONFIG" '.permission.task' 'rogue-peer' deny || return 70
  permissions_record_probe projection mcp "$PERMISSIONS_CONFIG" '.permission' 'codegraph_explore' ask || return 70
  permissions_record_probe projection mcp "$PERMISSIONS_CONFIG" '.permission' 'codegraph_node' deny || return 70
  permissions_record_probe projection mcp "$PERMISSIONS_CONFIG" '.permission' 'codegraph_future_tool' deny || return 70

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
    permissions_record_probe projection skill "$PERMISSIONS_CONFIG" '.permission.skill' "$PERMISSIONS_SKILL_NAME" "$PERMISSIONS_SKILL_EXPECTED" || return 70
  done <"$SOURCE_ROOT/tests/contracts/skills.txt"
  permissions_record_probe projection skill "$PERMISSIONS_CONFIG" '.permission.skill' 'sensai-rogue' deny || return 70

  for PERMISSIONS_ALLOWED_COMMAND in \
    'fd' 'fd --print0 src' 'rg --json --no-config 주문 src' \
    'sg --json -p call src' 'jq -e . trace.json' 'yq -o=json . openapi.yaml' \
    'mdq #{2} README.md' 'mmdc --input flow.mmd --output docs/analysis/missions/M-001/flow.svg' \
    '"$HOME/.local/bin/sensai" mission init mission-001 src 목표' \
    '"$HOME/.local/bin/sensai" mission checkpoint mission-001 candidate.json 1 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' \
    '"$HOME/.local/bin/sensai" mission resume mission-001' \
    '"$HOME/.local/bin/sensai" mission status mission-001'; do
    permissions_record_probe projection bash "$PERMISSIONS_CONFIG" '.permission.bash' "$PERMISSIONS_ALLOWED_COMMAND" allow || return 70
  done

  PERMISSIONS_PROJECTION_FAILED=$(jq -s 'map(select(.group == "projection" and (.pass | not))) | length' \
    "$PERMISSIONS_PROBE_JSONL") || return 70
  assert_eq permissions.ordered_projection 0 "$PERMISSIONS_PROJECTION_FAILED" || true

  PERMISSIONS_OLD_CONFIG_COMMAND='"$OPENCODE_CONFIG_DIR'
  PERMISSIONS_OLD_CONFIG_COMMAND=$PERMISSIONS_OLD_CONFIG_COMMAND'/bin/sensai" mission status mission-001'
  for PERMISSIONS_BYPASS_COMMAND in \
    'grep 주문 src' 'find src -type f' 'cat README.md' 'ls src' \
    'Select-String 주문 src' 'gci src' 'findstr 주문 src' 'exec rg 주문 src' \
    'rg --json 주문 src > out.json' \
    'rg --json 주문 src < in.txt' 'rg `cat pattern` src' 'rg $(cat pattern) src' \
    'fd --exec rm {}' 'fd -x rm {}' \
    'fd -X rm' 'rg --pre cat 주문 src' 'sg --rewrite 새값 -p 패턴 src' \
    'sg -r 새값 -p 패턴 src' 'sg --update-all -p 패턴 src' \
    'yq -i . openapi.yaml' 'yq --inplace . openapi.yaml' \
    'rg --json 값 .env' 'rg --json 값 keys/id_rsa_prod' \
    'rg --json 값 home/.config/opencode/opencode.json' \
    './bin/sensai mission init mission-001 src 목표' \
    'sensai mission init mission-001 src 목표' \
    "$PERMISSIONS_OLD_CONFIG_COMMAND" \
    '"$HOME/.local/bin/sensai" help' \
    '"$HOME/.local/bin/sensai" doctor tools' \
    '"$HOME/.local/bin/sensai" stage /tmp/target' \
    '"$HOME/.local/bin/sensai" install' \
    '"$HOME/.local/bin/sensai" mission status mission-001 > status.md' \
    '"$HOME/.local/bin/sensai" mission status $(cat .env)' \
    '"$HOME/.local/bin/sensai" mission status home/.config/opencode/auth.json' \
    '"$HOME/.local/bin/other" mission status mission-001'; do
    permissions_record_probe bypass bash "$PERMISSIONS_CONFIG" '.permission.bash' "$PERMISSIONS_BYPASS_COMMAND" deny || return 70
  done
  PERMISSIONS_BYPASS_FAILED=$(jq -s 'map(select(.group == "bypass" and (.pass | not))) | length' \
    "$PERMISSIONS_PROBE_JSONL") || return 70
  assert_eq permissions.bash_bypass_projection 0 "$PERMISSIONS_BYPASS_FAILED" || true

  jq -s 'map(select(.group == "projection"))' "$PERMISSIONS_PROBE_JSONL" >"$EVIDENCE_DIR/permission-projection.json" || return 70
  jq -s 'map(select(.group == "bypass"))' "$PERMISSIONS_PROBE_JSONL" >"$EVIDENCE_DIR/bypass-probes.json" || return 70
}
