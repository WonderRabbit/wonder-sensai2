#!/bin/sh

agents_clone_source() {
  AGENTS_CLONE_ROOT=$1
  mkdir -p "$AGENTS_CLONE_ROOT/output" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$AGENTS_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$AGENTS_CLONE_ROOT/tests" || return 70
  cp "$SOURCE_ROOT/output/AGENTS.md" "$SOURCE_ROOT/output/opencode.json" \
    "$SOURCE_ROOT/output/toolchain.lock.json" "$AGENTS_CLONE_ROOT/output/" || return 70
  cp -R "$SOURCE_ROOT/output/agents" "$AGENTS_CLONE_ROOT/output/agents" || return 70
}

agents_extract_frontmatter() {
  AGENTS_SOURCE_FILE=$1
  AGENTS_JSON_FILE=$2
  yq --front-matter=extract -o=json '.' "$AGENTS_SOURCE_FILE" >"$AGENTS_JSON_FILE"
}

agents_check_runtime() {
  AGENTS_LEAD="$SOURCE_ROOT/output/agents/sensai-analysis-lead.md"
  AGENTS_PEER="$SOURCE_ROOT/output/agents/sensai-evidence-peer.md"
  AGENTS_LEAD_JSON="$RUN_TMP/agents-lead.json"
  AGENTS_PEER_JSON="$RUN_TMP/agents-peer.json"

  assert_file agents.lead_file "$AGENTS_LEAD" || true
  assert_file agents.peer_file "$AGENTS_PEER" || true
  if ! test -f "$AGENTS_LEAD" || test -L "$AGENTS_LEAD" || \
     ! test -f "$AGENTS_PEER" || test -L "$AGENTS_PEER"; then
    assert_record agents.frontmatter_available 1 'agent source missing or symlink' || true
    return 0
  fi
  assert_record agents.frontmatter_available 0 'both agent sources are regular files' || true

  if agents_extract_frontmatter "$AGENTS_LEAD" "$AGENTS_LEAD_JSON" && \
     agents_extract_frontmatter "$AGENTS_PEER" "$AGENTS_PEER_JSON" && \
     jq empty "$AGENTS_LEAD_JSON" "$AGENTS_PEER_JSON" >/dev/null 2>&1; then
    assert_record agents.frontmatter_parse 0 'both frontmatter documents parse as YAML projections' || true
  else
    assert_record agents.frontmatter_parse 1 'agent frontmatter parse failed' || true
    return 0
  fi

  assert_jq agents.lead_fields '
    keys_unsorted == ["description","mode","model","permission"] and
    (.description | type == "string" and length > 0) and
    .mode == "primary" and
    .model == "zai/glm-5.2"
  ' "$AGENTS_LEAD_JSON" || true
  assert_jq agents.lead_permission '
    (.permission | keys_unsorted) == ["edit","task","skill"] and
    (.permission.edit | keys_unsorted) == ["*","docs/analysis/missions/**","**/../**"] and
    .permission.edit == {"*":"deny","docs/analysis/missions/**":"allow","**/../**":"deny"} and
    (.permission.task | keys_unsorted) == ["*","sensai-evidence-peer"] and
    .permission.task == {"*":"deny","sensai-evidence-peer":"allow"} and
    (.permission.skill | keys_unsorted) == ["*","sensai-business-trace","sensai-checklist","sensai-convention-extract","sensai-evidence-first","sensai-mermaid-sequence","sensai-react-trace","sensai-spec-evidence","sensai-stack-discovery","sensai-ui-definition","sensai-vertx-trace"] and
    .permission.skill["*"] == "deny" and
    all(.permission.skill | to_entries[1:][]; .value == "allow")
  ' "$AGENTS_LEAD_JSON" || true

  assert_jq agents.peer_fields '
    keys_unsorted == ["description","mode","model","hidden","permission"] and
    (.description | type == "string" and length > 0) and
    .mode == "subagent" and
    .model == "sensai-ollama/qwen3.5:9b" and
    .hidden == true
  ' "$AGENTS_PEER_JSON" || true
  assert_jq agents.peer_permission '
    (.permission | keys_unsorted) == ["edit","task","todowrite","question","skill"] and
    .permission.edit == "deny" and
    .permission.task == "deny" and
    .permission.todowrite == "deny" and
    .permission.question == "deny" and
    (.permission.skill | keys_unsorted) == [
      "*",
      "sensai-evidence-first",
      "sensai-react-trace",
      "sensai-vertx-trace",
      "sensai-spec-evidence",
      "sensai-stack-discovery",
      "sensai-convention-extract",
      "sensai-business-trace"
    ] and
    .permission.skill == {
      "*":"deny",
      "sensai-evidence-first":"allow",
      "sensai-react-trace":"allow",
      "sensai-vertx-trace":"allow",
      "sensai-spec-evidence":"allow",
      "sensai-stack-discovery":"allow",
      "sensai-convention-extract":"allow",
      "sensai-business-trace":"allow"
    }
  ' "$AGENTS_PEER_JSON" || true

  assert_jq agents.config_routing '
    .default_agent == "sensai-analysis-lead" and
    .model == "zai/glm-5.2" and
    .small_model == "sensai-ollama/qwen3.5:9b" and
    .permission.task == {"*":"deny","sensai-evidence-peer":"allow"}
  ' "$SOURCE_ROOT/output/opencode.json" || true

  AGENTS_EXPECTED_ROOT_HASH=$(awk 'NR == 1 { print $1 }' \
    "$SOURCE_ROOT/tests/contracts/root-agents.sha256.txt") || return 70
  tooling_sha256_file "$SOURCE_ROOT/AGENTS.md" || return 70
  assert_eq agents.root_hash "$AGENTS_EXPECTED_ROOT_HASH" "$TOOLING_SHA256" || true
}

case_agents() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  agents_check_runtime || return 70
}
