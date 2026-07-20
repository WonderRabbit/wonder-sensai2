#!/bin/sh

config_clone_source() {
  CONFIG_CLONE_ROOT=$1
  mkdir -p "$CONFIG_CLONE_ROOT/output" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$CONFIG_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$CONFIG_CLONE_ROOT/tests" || return 70
  cp "$SOURCE_ROOT/output/AGENTS.md" "$SOURCE_ROOT/output/opencode.json" \
    "$SOURCE_ROOT/output/toolchain.lock.json" "$CONFIG_CLONE_ROOT/output/" || return 70
}

config_run_mutation() {
  CONFIG_MUTATION_NAME=$1
  CONFIG_EXPECTED_ID=$2
  CONFIG_MUTATION_ROOT=$3
  CONFIG_MUTATION_EVIDENCE="$EVIDENCE_DIR/adversarial-$CONFIG_MUTATION_NAME"
  set +e
  env SENSAI_TEST_CONFIG_INNER=1 SENSAI_TEST_SOURCE_ROOT="$CONFIG_MUTATION_ROOT" \
    "$TEST_RUNNER" config --evidence "$CONFIG_MUTATION_EVIDENCE" \
    >"$RUN_TMP/config-$CONFIG_MUTATION_NAME.out" 2>&1
  CONFIG_MUTATION_RC=$?
  evidence_log_command "config-adversarial-$CONFIG_MUTATION_NAME" \
    "$TEST_RUNNER config <isolated-$CONFIG_MUTATION_NAME>" "$CONFIG_MUTATION_RC"
  assert_eq "config.adversarial_${CONFIG_MUTATION_NAME}_exit" 1 "$CONFIG_MUTATION_RC" || true
  if test -f "$CONFIG_MUTATION_EVIDENCE/receipt.json"; then
    assert_jq "config.adversarial_${CONFIG_MUTATION_NAME}_semantic" \
      ".result == \"ASSERTION_FAILURE\" and .exit == 1 and (.failed_assertion_ids | index(\"$CONFIG_EXPECTED_ID\")) != null" \
      "$CONFIG_MUTATION_EVIDENCE/receipt.json" || true
  else
    assert_record "config.adversarial_${CONFIG_MUTATION_NAME}_receipt" 1 'missing nested receipt' || true
  fi
}

config_run_adversarial_matrix() {
  CONFIG_ADV_ROOT="$RUN_TMP/config-adversarial"
  mkdir -p "$CONFIG_ADV_ROOT" || return 70

  CONFIG_ROOT="$CONFIG_ADV_ROOT/permission-order"
  config_clone_source "$CONFIG_ROOT" || return 70
  jq '.permission.edit = {"docs/analysis/missions/**":"allow","*":"deny"}' \
    "$CONFIG_ROOT/output/opencode.json" >"$CONFIG_ROOT/output/opencode.json.tmp" && \
    mv "$CONFIG_ROOT/output/opencode.json.tmp" "$CONFIG_ROOT/output/opencode.json" || return 70
  config_run_mutation permission_order config.permission_order "$CONFIG_ROOT"

  CONFIG_ROOT="$CONFIG_ADV_ROOT/forbidden-mcp"
  config_clone_source "$CONFIG_ROOT" || return 70
  jq '.mcp = {}' "$CONFIG_ROOT/output/opencode.json" >"$CONFIG_ROOT/output/opencode.json.tmp" && \
    mv "$CONFIG_ROOT/output/opencode.json.tmp" "$CONFIG_ROOT/output/opencode.json" || return 70
  config_run_mutation forbidden_mcp config.forbidden_sections "$CONFIG_ROOT"

  CONFIG_ROOT="$CONFIG_ADV_ROOT/instructions-missing"
  config_clone_source "$CONFIG_ROOT" || return 70
  jq '.instructions = []' "$CONFIG_ROOT/output/opencode.json" >"$CONFIG_ROOT/output/opencode.json.tmp" && \
    mv "$CONFIG_ROOT/output/opencode.json.tmp" "$CONFIG_ROOT/output/opencode.json" || return 70
  config_run_mutation instructions_missing config.instructions "$CONFIG_ROOT"

  CONFIG_ROOT="$CONFIG_ADV_ROOT/compaction-model-wrong-level"
  config_clone_source "$CONFIG_ROOT" || return 70
  jq '.compaction.model = "zai/glm-5.2"' \
    "$CONFIG_ROOT/output/opencode.json" >"$CONFIG_ROOT/output/opencode.json.tmp" && \
    mv "$CONFIG_ROOT/output/opencode.json.tmp" "$CONFIG_ROOT/output/opencode.json" || return 70
  config_run_mutation compaction_model_wrong_level config.compaction "$CONFIG_ROOT"

  CONFIG_ROOT="$CONFIG_ADV_ROOT/subagent-unbounded"
  config_clone_source "$CONFIG_ROOT" || return 70
  jq '.subagent_depth = 2' "$CONFIG_ROOT/output/opencode.json" >"$CONFIG_ROOT/output/opencode.json.tmp" && \
    mv "$CONFIG_ROOT/output/opencode.json.tmp" "$CONFIG_ROOT/output/opencode.json" || return 70
  config_run_mutation subagent_unbounded config.subagent_depth "$CONFIG_ROOT"

  CONFIG_ROOT="$CONFIG_ADV_ROOT/watcher-drift"
  config_clone_source "$CONFIG_ROOT" || return 70
  jq '.watcher.ignore = []' "$CONFIG_ROOT/output/opencode.json" >"$CONFIG_ROOT/output/opencode.json.tmp" && \
    mv "$CONFIG_ROOT/output/opencode.json.tmp" "$CONFIG_ROOT/output/opencode.json" || return 70
  config_run_mutation watcher_drift config.watcher "$CONFIG_ROOT"
}

config_check_runtime() {
  CONFIG_FILE="$SOURCE_ROOT/output/opencode.json"
  CONFIG_LOCK="$SOURCE_ROOT/output/toolchain.lock.json"

  assert_file config.runtime_agents "$SOURCE_ROOT/output/AGENTS.md" || true
  assert_file config.file "$CONFIG_FILE" || true
  assert_file config.toolchain_lock "$CONFIG_LOCK" || true
  if ! test -f "$CONFIG_FILE" || test -L "$CONFIG_FILE" || \
     ! test -f "$CONFIG_LOCK" || test -L "$CONFIG_LOCK"; then
    assert_record config.validation_available 1 'config or toolchain lock missing or symlink' || true
    return 0
  fi
  assert_record config.validation_available 0 'config and toolchain lock are regular files' || true

  if jq empty "$CONFIG_FILE" >/dev/null 2>&1 && jq empty "$CONFIG_LOCK" >/dev/null 2>&1; then
    assert_record config.json_syntax 0 'runtime config and toolchain lock parse as JSON' || true
  else
    assert_record config.json_syntax 1 'runtime config or toolchain lock is invalid JSON' || true
    return 0
  fi

  assert_jq config.top_level_keys '
    (keys | sort) == (["$schema","agent","autoupdate","compaction","default_agent","instructions","model","permission","provider","share","small_model","subagent_depth","watcher"] | sort)
  ' "$CONFIG_FILE" || true
  assert_jq config.schema '.["$schema"] == "https://opencode.ai/config.json"' "$CONFIG_FILE" || true
  assert_jq config.models '
    .model == "zai/glm-5.2" and
    .small_model == "sensai-ollama/qwen3.5:9b" and
    .default_agent == "sensai-analysis-lead"
  ' "$CONFIG_FILE" || true
  assert_jq config.share_update '.share == "disabled" and .autoupdate == false' "$CONFIG_FILE" || true
  assert_jq config.compaction '
    .compaction == {"auto":true,"prune":true} and
    .agent == {"compaction":{"model":"zai/glm-5.2"}}
  ' "$CONFIG_FILE" || true
  assert_jq config.instructions '.instructions == ["AGENTS.md"]' "$CONFIG_FILE" || true
  assert_jq config.watcher '
    .watcher.ignore == [".git/**",".omo/**","docs/analysis/missions/**/.sensai-tmp/**"]
  ' "$CONFIG_FILE" || true
  assert_jq config.subagent_depth '.subagent_depth == 1' "$CONFIG_FILE" || true

  assert_jq config.provider '
    (.provider | keys) == ["sensai-ollama"] and
    .provider["sensai-ollama"].npm == "@ai-sdk/openai-compatible" and
    .provider["sensai-ollama"].name == "Sensai Ollama 근거 피어" and
    .provider["sensai-ollama"].options == {"baseURL":"http://localhost:11434/v1","apiKey":"ollama"} and
    (.provider["sensai-ollama"].models | keys) == ["qwen3.5:9b"] and
    .provider["sensai-ollama"].models["qwen3.5:9b"].name == "Qwen3.5-9B Ollama 로컬 모델"
  ' "$CONFIG_FILE" || true

  assert_jq config.permission_keys '
    (.permission | keys_unsorted) == ["read","edit","bash","task","skill","external_directory","todowrite","question","webfetch","websearch","lsp","doom_loop"]
  ' "$CONFIG_FILE" || true
  assert_jq config.permission_order '
    (.permission.read | keys_unsorted) == ["*","*.env","*.env.*","*.pem","*id_rsa*","*credentials*","*secrets.*","auth.json","**/.env","**/.env.*","**/auth.json","**/.ssh/**","**/.aws/**","**/.config/opencode/**","**/.local/share/opencode/**"] and
    (.permission.edit | keys_unsorted) == ["*","docs/analysis/missions/**","**/../**"] and
    (.permission.bash | keys_unsorted) == ["*","fd","fd *","rg","rg *","sg","sg *","jq","jq *","yq","yq *","mdq","mdq *","mmdc","mmdc *","\"$HOME/.local/bin/sensai\" mission init *","\"$HOME/.local/bin/sensai\" mission checkpoint *","\"$HOME/.local/bin/sensai\" mission resume *","\"$HOME/.local/bin/sensai\" mission status *","*|*","*>*","*<*","*`*","*$(*","*;*","*&&*","*||*","fd *--exec*","fd *-x*","fd *-X*","rg *--pre*","sg *--rewrite*","sg *-r*","sg *--update-all*","yq *-i*","yq *--inplace*","**.env*","**.pem*","**id_rsa*","**credentials*","**secrets.*","**/auth.json*","**/.ssh/**","**/.aws/**","**/.config/opencode/**","**/.local/share/opencode/**"] and
    (.permission.task | keys_unsorted) == ["*","sensai-evidence-peer"] and
    (.permission.skill | keys_unsorted) == ["*","sensai-business-trace","sensai-checklist","sensai-convention-extract","sensai-evidence-first","sensai-mermaid-sequence","sensai-react-trace","sensai-spec-evidence","sensai-stack-discovery","sensai-ui-definition","sensai-vertx-trace"]
  ' "$CONFIG_FILE" || true
  assert_jq config.permission_values '
    .permission.read["*"] == "allow" and
    all(.permission.read | to_entries[1:][]; .value == "deny") and
    .permission.edit == {"*":"deny","docs/analysis/missions/**":"allow","**/../**":"deny"} and
    .permission.task == {"*":"deny","sensai-evidence-peer":"allow"} and
    (.permission.skill["*"] == "deny") and
    all(.permission.skill | to_entries[1:][]; .value == "allow") and
    .permission.external_directory == "deny" and
    .permission.todowrite == "allow" and
    .permission.question == "allow" and
    .permission.webfetch == "deny" and
    .permission.websearch == "deny" and
    .permission.lsp == "deny" and
    .permission.doom_loop == "deny" and
    all(.permission.bash | to_entries[0:1][]; .value == "deny") and
    all(.permission.bash | to_entries[1:19][]; .value == "allow") and
    all(.permission.bash | to_entries[19:][]; .value == "deny") and
    ([.permission.bash | to_entries[] |
      select(.value == "allow" and (.key | startswith("\"$HOME/.local/bin/sensai\" mission ")))] | length) == 4
  ' "$CONFIG_FILE" || true

  assert_jq config.forbidden_sections '
    . as $root |
    (["mcp","plugin","tools","formatter","lsp","experimental","command","skills","mode","autoshare"] |
      all(. as $key | $root | has($key) | not))
  ' "$CONFIG_FILE" || true
  if test -e "$SOURCE_ROOT/opencode.json"; then
    assert_record config.no_root_duplicate 1 'root opencode.json duplicate exists' || true
  else
    assert_record config.no_root_duplicate 0 'root opencode.json duplicate absent' || true
  fi

  assert_jq config.lock_keys '
    (keys | sort) == (["default_agent","lock_version","model_admission","model_aliases","opencode_version","schema_versions"] | sort)
  ' "$CONFIG_LOCK" || true
  assert_jq config.lock_version '.lock_version == "1.0" and .opencode_version == "1.18.3"' "$CONFIG_LOCK" || true
  assert_jq config.lock_models '
    .model_aliases == {"lead":"zai/glm-5.2","small":"sensai-ollama/qwen3.5:9b"} and
    .default_agent == "sensai-analysis-lead"
  ' "$CONFIG_LOCK" || true
  assert_jq config.lock_schemas '.schema_versions == {"trace":"2.0","progress":"1.0"}' "$CONFIG_LOCK" || true
  assert_jq config.model_admission '.model_admission == "UNVERIFIED"' "$CONFIG_LOCK" || true

  if rg -q --no-config '자동으로[[:space:]]+로드된다|항상[[:space:]]+로드된다' "$SOURCE_ROOT/output/AGENTS.md"; then
    assert_record config.no_implicit_agents_claim 1 'runtime AGENTS implicit-load claim found' || true
  else
    CONFIG_IMPLICIT_RC=$?
    case "$CONFIG_IMPLICIT_RC" in
      1) assert_record config.no_implicit_agents_claim 0 'runtime AGENTS requires explicit relationship and duplicated invariants' || true ;;
      *) return 70 ;;
    esac
  fi
  if rg -q --no-config 'MODEL_ADMISSION_UNVERIFIED' "$SOURCE_ROOT/output/AGENTS.md"; then
    assert_record config.runtime_nonclaim 0 'runtime contract preserves live admission nonclaim' || true
  else
    CONFIG_NONCLAIM_RC=$?
    case "$CONFIG_NONCLAIM_RC" in
      1) assert_record config.runtime_nonclaim 1 'runtime contract lacks admission nonclaim' || true ;;
      *) return 70 ;;
    esac
  fi
}

case_config() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  CONFIG_FAILED_BEFORE=$ASSERT_FAILED
  config_check_runtime || return 70
  if test "$ASSERT_FAILED" -eq "$CONFIG_FAILED_BEFORE" && \
     test "${SENSAI_TEST_CONFIG_INNER:-0}" != 1; then
    config_run_adversarial_matrix || return 70
  else
    assert_record config.adversarial_deferred 0 'adversarial matrix deferred for invalid baseline or nested run' || true
  fi
}
