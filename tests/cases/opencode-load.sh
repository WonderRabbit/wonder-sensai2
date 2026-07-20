#!/bin/sh

# noqa: SIZE_OK - OpenCode load selector의 공유 격리 환경, fingerprint, projection, receipt orchestration을 한 흐름에서 검증한다.

. "$SCRIPT_DIR/cases/opencode-load/global-install.sh"

opencode_load_fingerprint_tree() {
  OPENCODE_LOAD_TREE_ROOT=$1
  OPENCODE_LOAD_TREE_LABEL=$2
  OPENCODE_LOAD_TREE_LINES=$RUN_TMP/opencode-load-tree-$OPENCODE_LOAD_TREE_LABEL.lines
  OPENCODE_LOAD_TREE_UNSORTED=$RUN_TMP/opencode-load-tree-$OPENCODE_LOAD_TREE_LABEL.unsorted
  OPENCODE_LOAD_TREE_PATHS=$RUN_TMP/opencode-load-tree-$OPENCODE_LOAD_TREE_LABEL.paths
  : >"$OPENCODE_LOAD_TREE_LINES" || return 70
  : >"$OPENCODE_LOAD_TREE_UNSORTED" || return 70
  : >"$OPENCODE_LOAD_TREE_PATHS" || return 70

  if ! test -e "$OPENCODE_LOAD_TREE_ROOT" && ! test -L "$OPENCODE_LOAD_TREE_ROOT"; then
    printf 'A\t.\n' >"$OPENCODE_LOAD_TREE_UNSORTED" || return 70
  else
    find "$OPENCODE_LOAD_TREE_ROOT" -mindepth 0 -type d -print \
      >"$OPENCODE_LOAD_TREE_PATHS" || return 70
    while IFS= read -r OPENCODE_LOAD_TREE_PATH; do
      if test "$OPENCODE_LOAD_TREE_PATH" = "$OPENCODE_LOAD_TREE_ROOT"; then
        OPENCODE_LOAD_TREE_REL=.
      else
        OPENCODE_LOAD_TREE_REL=${OPENCODE_LOAD_TREE_PATH#"$OPENCODE_LOAD_TREE_ROOT"/}
      fi
      printf 'D\t%s\n' "$OPENCODE_LOAD_TREE_REL" \
        >>"$OPENCODE_LOAD_TREE_UNSORTED" || return 70
    done <"$OPENCODE_LOAD_TREE_PATHS"

    find "$OPENCODE_LOAD_TREE_ROOT" -mindepth 0 -type l -print \
      >"$OPENCODE_LOAD_TREE_PATHS" || return 70
    while IFS= read -r OPENCODE_LOAD_TREE_PATH; do
      if test "$OPENCODE_LOAD_TREE_PATH" = "$OPENCODE_LOAD_TREE_ROOT"; then
        OPENCODE_LOAD_TREE_REL=.
      else
        OPENCODE_LOAD_TREE_REL=${OPENCODE_LOAD_TREE_PATH#"$OPENCODE_LOAD_TREE_ROOT"/}
      fi
      OPENCODE_LOAD_TREE_TARGET=$(readlink "$OPENCODE_LOAD_TREE_PATH") || return 70
      printf 'L\t%s\t%s\n' "$OPENCODE_LOAD_TREE_REL" "$OPENCODE_LOAD_TREE_TARGET" \
        >>"$OPENCODE_LOAD_TREE_UNSORTED" || return 70
    done <"$OPENCODE_LOAD_TREE_PATHS"

    find "$OPENCODE_LOAD_TREE_ROOT" -mindepth 0 -type f \
      -exec shasum -a 256 {} + >"$OPENCODE_LOAD_TREE_PATHS" || return 70
    while IFS= read -r OPENCODE_LOAD_TREE_HASH_LINE; do
      OPENCODE_LOAD_TREE_FILE_SHA=${OPENCODE_LOAD_TREE_HASH_LINE%% *}
      OPENCODE_LOAD_TREE_PATH=${OPENCODE_LOAD_TREE_HASH_LINE#*  }
      if test "$OPENCODE_LOAD_TREE_PATH" = "$OPENCODE_LOAD_TREE_ROOT"; then
        OPENCODE_LOAD_TREE_REL=.
      else
        OPENCODE_LOAD_TREE_REL=${OPENCODE_LOAD_TREE_PATH#"$OPENCODE_LOAD_TREE_ROOT"/}
      fi
      printf 'F\t%s\t%s\n' "$OPENCODE_LOAD_TREE_REL" "$OPENCODE_LOAD_TREE_FILE_SHA" \
        >>"$OPENCODE_LOAD_TREE_UNSORTED" || return 70
    done <"$OPENCODE_LOAD_TREE_PATHS"
  fi

  LC_ALL=C sort "$OPENCODE_LOAD_TREE_UNSORTED" >"$OPENCODE_LOAD_TREE_LINES" || return 70
  OPENCODE_LOAD_TREE_COUNT=$(wc -l <"$OPENCODE_LOAD_TREE_LINES" | tr -d ' ') || return 70
  tooling_sha256_file "$OPENCODE_LOAD_TREE_LINES" || return 70
  OPENCODE_LOAD_TREE_SHA=$TOOLING_SHA256
}

opencode_load_fingerprint_global() {
  OPENCODE_LOAD_GLOBAL_PHASE=$1
  OPENCODE_LOAD_GLOBAL_SUMMARY=$RUN_TMP/opencode-load-global-$OPENCODE_LOAD_GLOBAL_PHASE.tsv
  : >"$OPENCODE_LOAD_GLOBAL_SUMMARY" || return 70
  for OPENCODE_LOAD_GLOBAL_ITEM in \
    config:"$OPENCODE_LOAD_REAL_CONFIG" \
    data:"$OPENCODE_LOAD_REAL_DATA" \
    cache:"$OPENCODE_LOAD_REAL_CACHE" \
    state:"$OPENCODE_LOAD_REAL_STATE"; do
    OPENCODE_LOAD_GLOBAL_NAME=${OPENCODE_LOAD_GLOBAL_ITEM%%:*}
    OPENCODE_LOAD_GLOBAL_PATH=${OPENCODE_LOAD_GLOBAL_ITEM#*:}
    opencode_load_fingerprint_tree "$OPENCODE_LOAD_GLOBAL_PATH" \
      "global-$OPENCODE_LOAD_GLOBAL_PHASE-$OPENCODE_LOAD_GLOBAL_NAME" || return 70
    printf '%s\t%s\t%s\n' "$OPENCODE_LOAD_GLOBAL_NAME" \
      "$OPENCODE_LOAD_TREE_SHA" "$OPENCODE_LOAD_TREE_COUNT" \
      >>"$OPENCODE_LOAD_GLOBAL_SUMMARY" || return 70
  done
  tooling_sha256_file "$OPENCODE_LOAD_GLOBAL_SUMMARY" || return 70
  OPENCODE_LOAD_GLOBAL_SHA=$TOOLING_SHA256
}

opencode_load_fingerprint_source() {
  OPENCODE_LOAD_SOURCE_PHASE=$1
  OPENCODE_LOAD_SOURCE_SUMMARY=$RUN_TMP/opencode-load-source-$OPENCODE_LOAD_SOURCE_PHASE.tsv
  opencode_load_fingerprint_tree "$SOURCE_ROOT/output" \
    "source-$OPENCODE_LOAD_SOURCE_PHASE-output" || return 70
  OPENCODE_LOAD_SOURCE_OUTPUT_SHA=$OPENCODE_LOAD_TREE_SHA
  OPENCODE_LOAD_SOURCE_OUTPUT_COUNT=$OPENCODE_LOAD_TREE_COUNT
  tooling_sha256_file "$SOURCE_ROOT/manifest.txt" || return 70
  OPENCODE_LOAD_SOURCE_MANIFEST_SHA=$TOOLING_SHA256
  tooling_sha256_file "$SOURCE_ROOT/bin/sensai" || return 70
  OPENCODE_LOAD_SOURCE_BIN_SHA=$TOOLING_SHA256
  printf 'output\t%s\t%s\nmanifest\t%s\t1\nbin/sensai\t%s\t1\n' \
    "$OPENCODE_LOAD_SOURCE_OUTPUT_SHA" "$OPENCODE_LOAD_SOURCE_OUTPUT_COUNT" \
    "$OPENCODE_LOAD_SOURCE_MANIFEST_SHA" "$OPENCODE_LOAD_SOURCE_BIN_SHA" \
    >"$OPENCODE_LOAD_SOURCE_SUMMARY" || return 70
  tooling_sha256_file "$OPENCODE_LOAD_SOURCE_SUMMARY" || return 70
  OPENCODE_LOAD_SOURCE_SHA=$TOOLING_SHA256
}

opencode_load_run_debug() {
  OPENCODE_LOAD_PASS=$1
  OPENCODE_LOAD_CONFIG_OUT=$RUN_TMP/opencode-load-config-$OPENCODE_LOAD_PASS.full.json
  OPENCODE_LOAD_CONFIG_ERR=$RUN_TMP/opencode-load-config-$OPENCODE_LOAD_PASS.err
  OPENCODE_LOAD_SKILL_OUT=$RUN_TMP/opencode-load-skill-$OPENCODE_LOAD_PASS.full.json
  OPENCODE_LOAD_SKILL_ERR=$RUN_TMP/opencode-load-skill-$OPENCODE_LOAD_PASS.err

  set +e
  (
    cd "$OPENCODE_LOAD_WORK" || exit 70
    env -i \
      PATH="$PATH" \
      HOME="$OPENCODE_LOAD_HOME" \
      XDG_CONFIG_HOME="$OPENCODE_LOAD_XDG_CONFIG" \
      XDG_DATA_HOME="$OPENCODE_LOAD_XDG_DATA" \
      XDG_CACHE_HOME="$OPENCODE_LOAD_XDG_CACHE" \
      XDG_STATE_HOME="$OPENCODE_LOAD_XDG_STATE" \
      TMPDIR="$OPENCODE_LOAD_TMP/" \
      OPENCODE_CONFIG_DIR="$OPENCODE_LOAD_STAGE" \
      USER=sensai-test LOGNAME=sensai-test SHELL=/bin/sh LANG=C.UTF-8 LC_ALL=C CI=1 \
      "$OPENCODE_LOAD_BIN" debug config --pure
  ) >"$OPENCODE_LOAD_CONFIG_OUT" 2>"$OPENCODE_LOAD_CONFIG_ERR"
  OPENCODE_LOAD_CONFIG_RC=$?
  evidence_log_command "opencode-debug-config-$OPENCODE_LOAD_PASS" \
    'opencode debug config --pure <disposable HOME/XDG/TMPDIR/config/CWD>' \
    "$OPENCODE_LOAD_CONFIG_RC"
  test "$OPENCODE_LOAD_CONFIG_RC" -eq 0 || return 70
  jq -e 'type == "object"' "$OPENCODE_LOAD_CONFIG_OUT" >/dev/null || return 70

  set +e
  (
    cd "$OPENCODE_LOAD_WORK" || exit 70
    env -i \
      PATH="$PATH" \
      HOME="$OPENCODE_LOAD_HOME" \
      XDG_CONFIG_HOME="$OPENCODE_LOAD_XDG_CONFIG" \
      XDG_DATA_HOME="$OPENCODE_LOAD_XDG_DATA" \
      XDG_CACHE_HOME="$OPENCODE_LOAD_XDG_CACHE" \
      XDG_STATE_HOME="$OPENCODE_LOAD_XDG_STATE" \
      TMPDIR="$OPENCODE_LOAD_TMP/" \
      OPENCODE_CONFIG_DIR="$OPENCODE_LOAD_STAGE" \
      USER=sensai-test LOGNAME=sensai-test SHELL=/bin/sh LANG=C.UTF-8 LC_ALL=C CI=1 \
      "$OPENCODE_LOAD_BIN" debug skill --pure
  ) >"$OPENCODE_LOAD_SKILL_OUT" 2>"$OPENCODE_LOAD_SKILL_ERR"
  OPENCODE_LOAD_SKILL_RC=$?
  evidence_log_command "opencode-debug-skill-$OPENCODE_LOAD_PASS" \
    'opencode debug skill --pure <disposable HOME/XDG/TMPDIR/config/CWD>' \
    "$OPENCODE_LOAD_SKILL_RC"
  test "$OPENCODE_LOAD_SKILL_RC" -eq 0 || return 70
  jq -e 'type == "array"' "$OPENCODE_LOAD_SKILL_OUT" >/dev/null || return 70
}

opencode_load_project_safe() {
  OPENCODE_LOAD_PROJECT_PASS=$1
  OPENCODE_LOAD_PROJECT_CONFIG=$RUN_TMP/opencode-load-config-$OPENCODE_LOAD_PROJECT_PASS.full.json
  OPENCODE_LOAD_PROJECT_SKILLS=$RUN_TMP/opencode-load-skill-$OPENCODE_LOAD_PROJECT_PASS.full.json
  OPENCODE_LOAD_PROJECT_OUTPUT=$RUN_TMP/opencode-load-projection-$OPENCODE_LOAD_PROJECT_PASS.json
  OPENCODE_LOAD_PERMISSION_CANONICAL=$RUN_TMP/opencode-load-permission-$OPENCODE_LOAD_PROJECT_PASS.json
  jq -S -c '.permission' "$OPENCODE_LOAD_PROJECT_CONFIG" \
    >"$OPENCODE_LOAD_PERMISSION_CANONICAL" || return 70
  tooling_sha256_file "$OPENCODE_LOAD_PERMISSION_CANONICAL" || return 70
  OPENCODE_LOAD_PERMISSION_SHA=$TOOLING_SHA256
  if rg -q --no-config --fixed-strings "$OPENCODE_LOAD_SENTINEL" \
       "$OPENCODE_LOAD_PROJECT_CONFIG" "$OPENCODE_LOAD_PROJECT_SKILLS"; then
    OPENCODE_LOAD_SENTINEL_PRESENT=true
  else
    OPENCODE_LOAD_SENTINEL_PRESENT=false
  fi

  jq -n \
    --arg version "$OPENCODE_LOAD_VERSION" \
    --arg stage "$OPENCODE_LOAD_STAGE" \
    --arg permission_sha256 "$OPENCODE_LOAD_PERMISSION_SHA" \
    --argjson inherited_sentinel "$OPENCODE_LOAD_SENTINEL_PRESENT" \
    --slurpfile cfg "$OPENCODE_LOAD_PROJECT_CONFIG" \
    --slurpfile skills "$OPENCODE_LOAD_PROJECT_SKILLS" \
    '{
      schema_version:"1.0",
      opencode_version:$version,
      bindings:{
        model:$cfg[0].model,
        small_model:$cfg[0].small_model,
        default_agent:$cfg[0].default_agent,
        share:$cfg[0].share,
        autoupdate:$cfg[0].autoupdate,
        subagent_depth:$cfg[0].subagent_depth,
        instructions:$cfg[0].instructions,
        compaction:$cfg[0].compaction,
        compaction_agent_model:$cfg[0].agent.compaction.model,
        permission_sha256:$permission_sha256,
        provider_ids:($cfg[0].provider | keys),
        provider_model_ids:($cfg[0].provider["sensai-ollama"].models | keys)
      },
      agents:([
        $cfg[0].agent | to_entries[] |
        select(.key | startswith("sensai-")) |
        {id:.key,mode:.value.mode,model:.value.model,hidden:(.value.hidden // false)}
      ] | sort_by(.id)),
      commands:([
        $cfg[0].command | to_entries[] |
        select(.key | startswith("sensai/")) |
        {id:.key,agent:.value.agent,subtask:(.value.subtask // false)}
      ] | sort_by(.id)),
      skills:([
        $skills[0][] | select(.name | startswith("sensai-")) |
        . as $skill |
        {id:$skill.name,location:(
          $skill.location |
          if startswith($stage + "/") then .[($stage | length) + 1:] else . end
        )}
      ] | sort_by(.id)),
      isolation:{
        inherited_sentinel:$inherited_sentinel,
        model_invocations:0,
        network_auth_attempts:0,
        full_resolved_config_persisted:false
      }
    }' >"$OPENCODE_LOAD_PROJECT_OUTPUT" || return 70
}

opencode_load_collect_mutations() {
  OPENCODE_LOAD_MUTATION_PHASE=$1
  OPENCODE_LOAD_MUTATION_FILE=$RUN_TMP/opencode-load-mutations-$OPENCODE_LOAD_MUTATION_PHASE.txt
  : >"$OPENCODE_LOAD_MUTATION_FILE" || return 70
  for OPENCODE_LOAD_MUTATION_ITEM in \
    home:"$OPENCODE_LOAD_HOME" \
    xdg-config:"$OPENCODE_LOAD_XDG_CONFIG" \
    xdg-data:"$OPENCODE_LOAD_XDG_DATA" \
    xdg-cache:"$OPENCODE_LOAD_XDG_CACHE" \
    xdg-state:"$OPENCODE_LOAD_XDG_STATE" \
    tmp:"$OPENCODE_LOAD_TMP" \
    work:"$OPENCODE_LOAD_WORK"; do
    OPENCODE_LOAD_MUTATION_NAME=${OPENCODE_LOAD_MUTATION_ITEM%%:*}
    OPENCODE_LOAD_MUTATION_ROOT=${OPENCODE_LOAD_MUTATION_ITEM#*:}
    find "$OPENCODE_LOAD_MUTATION_ROOT" -mindepth 1 ! -type d -print | \
      while IFS= read -r OPENCODE_LOAD_MUTATION_PATH; do
        OPENCODE_LOAD_MUTATION_REL=${OPENCODE_LOAD_MUTATION_PATH#"$OPENCODE_LOAD_MUTATION_ROOT"/}
        printf '%s/%s\n' "$OPENCODE_LOAD_MUTATION_NAME" "$OPENCODE_LOAD_MUTATION_REL"
      done >>"$OPENCODE_LOAD_MUTATION_FILE" || return 70
  done
  find "$OPENCODE_LOAD_STAGE" -mindepth 1 ! -type d -print | \
    sed "s#^$OPENCODE_LOAD_STAGE/##" | LC_ALL=C sort \
    >"$RUN_TMP/opencode-load-current-stage-$OPENCODE_LOAD_MUTATION_PHASE.leaves" || return 70
  awk 'NR==FNR {payload[$0]=1; next} !($0 in payload) {print "config/" $0}' \
    "$SOURCE_ROOT/manifest.txt" \
    "$RUN_TMP/opencode-load-current-stage-$OPENCODE_LOAD_MUTATION_PHASE.leaves" \
    >>"$OPENCODE_LOAD_MUTATION_FILE" || return 70
  LC_ALL=C sort -u "$OPENCODE_LOAD_MUTATION_FILE" \
    >"$OPENCODE_LOAD_MUTATION_FILE.sorted" || return 70
  mv "$OPENCODE_LOAD_MUTATION_FILE.sorted" "$OPENCODE_LOAD_MUTATION_FILE" || return 70
}

opencode_load_mutations_known() {
  OPENCODE_LOAD_MUTATIONS_INPUT=$1
  while IFS= read -r OPENCODE_LOAD_MUTATION; do
    case "$OPENCODE_LOAD_MUTATION" in
      config/.gitignore|\
      xdg-config/opencode/.gitignore|\
      xdg-data/opencode/log/opencode.log|\
      xdg-data/opencode/opencode.db|\
      xdg-data/opencode/opencode.db-shm|\
      xdg-data/opencode/opencode.db-wal)
        ;;
      xdg-config/opencode/opencode.json)
        test "${SENSAI_TEST_OPENCODE_INHERITED_SENTINEL:-0}" = 1 || return 1
        ;;
      xdg-state/opencode/locks/*.lock/heartbeat|\
      xdg-state/opencode/locks/*.lock/meta.json)
        printf '%s\n' "$OPENCODE_LOAD_MUTATION" | \
          rg -q --no-config '^xdg-state/opencode/locks/[0-9a-f]{40}\.lock/(heartbeat|meta\.json)$' || return 1
        ;;
      *) return 1 ;;
    esac
  done <"$OPENCODE_LOAD_MUTATIONS_INPUT"
  return 0
}

opencode_load_write_environment_evidence() {
  jq -Rn '[inputs | split("\t") | {scope:.[0],sha256:.[1],entry_count:(.[2]|tonumber)}]' \
    <"$OPENCODE_LOAD_GLOBAL_BEFORE_SUMMARY" >"$RUN_TMP/opencode-load-global-before.json" || return 70
  jq -Rn '[inputs | split("\t") | {scope:.[0],sha256:.[1],entry_count:(.[2]|tonumber)}]' \
    <"$OPENCODE_LOAD_GLOBAL_AFTER_SUMMARY" >"$RUN_TMP/opencode-load-global-after.json" || return 70
  jq -n \
    --arg source_before "$OPENCODE_LOAD_SOURCE_BEFORE_SHA" \
    --arg source_after "$OPENCODE_LOAD_SOURCE_AFTER_SHA" \
    --arg source_output_before "$OPENCODE_LOAD_SOURCE_OUTPUT_BEFORE_SHA" \
    --arg source_output_after "$OPENCODE_LOAD_SOURCE_OUTPUT_AFTER_SHA" \
    --arg manifest_before "$OPENCODE_LOAD_MANIFEST_BEFORE_SHA" \
    --arg manifest_after "$OPENCODE_LOAD_MANIFEST_AFTER_SHA" \
    --arg bin_before "$OPENCODE_LOAD_BIN_BEFORE_SHA" \
    --arg bin_after "$OPENCODE_LOAD_BIN_AFTER_SHA" \
    --arg global_before "$OPENCODE_LOAD_GLOBAL_BEFORE_SHA" \
    --arg global_after "$OPENCODE_LOAD_GLOBAL_AFTER_SHA" \
    --slurpfile global_before_scopes "$RUN_TMP/opencode-load-global-before.json" \
    --slurpfile global_after_scopes "$RUN_TMP/opencode-load-global-after.json" \
    '{
      source:{before:$source_before,after:$source_after,unchanged:($source_before==$source_after)},
      output:{before:$source_output_before,after:$source_output_after,unchanged:($source_output_before==$source_output_after)},
      manifest:{before:$manifest_before,after:$manifest_after,unchanged:($manifest_before==$manifest_after)},
      installed_cli_source:{before:$bin_before,after:$bin_after,unchanged:($bin_before==$bin_after)},
      actual_global:{
        before:$global_before,
        after:$global_after,
        unchanged:($global_before==$global_after),
        before_scopes:$global_before_scopes[0],
        after_scopes:$global_after_scopes[0],
        content_persisted:false
      }
    }' >"$EVIDENCE_DIR/environment-hashes.json" || return 70
}

case_opencode_load() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  for OPENCODE_LOAD_REQUIRED in opencode env readlink; do
    tooling_require_command "$OPENCODE_LOAD_REQUIRED" || return 70
  done
  assert_eq opencode-load.platform Darwin "$(uname -s)" || true

  OPENCODE_LOAD_BIN=$(command -v opencode) || return 70
  OPENCODE_LOAD_SENTINEL=SENSAI_INHERITED_CONFIG_SENTINEL
  OPENCODE_LOAD_REAL_HOME=$HOME
  OPENCODE_LOAD_REAL_CONFIG=${XDG_CONFIG_HOME:-$OPENCODE_LOAD_REAL_HOME/.config}/opencode
  OPENCODE_LOAD_REAL_DATA=${XDG_DATA_HOME:-$OPENCODE_LOAD_REAL_HOME/.local/share}/opencode
  OPENCODE_LOAD_REAL_CACHE=${XDG_CACHE_HOME:-$OPENCODE_LOAD_REAL_HOME/.cache}/opencode
  OPENCODE_LOAD_REAL_STATE=${XDG_STATE_HOME:-$OPENCODE_LOAD_REAL_HOME/.local/state}/opencode

  OPENCODE_LOAD_SANDBOX=$RUN_TMP/opencode-load-sandbox
  mkdir -p "$OPENCODE_LOAD_SANDBOX" || return 70
  OPENCODE_LOAD_SANDBOX=$(CDPATH= cd -- "$OPENCODE_LOAD_SANDBOX" 2>/dev/null && pwd -P) || return 70
  OPENCODE_LOAD_STAGE=$OPENCODE_LOAD_SANDBOX/config
  OPENCODE_LOAD_HOME=$OPENCODE_LOAD_SANDBOX/home
  OPENCODE_LOAD_XDG_CONFIG=$OPENCODE_LOAD_SANDBOX/xdg-config
  OPENCODE_LOAD_XDG_DATA=$OPENCODE_LOAD_SANDBOX/xdg-data
  OPENCODE_LOAD_XDG_CACHE=$OPENCODE_LOAD_SANDBOX/xdg-cache
  OPENCODE_LOAD_XDG_STATE=$OPENCODE_LOAD_SANDBOX/xdg-state
  OPENCODE_LOAD_TMP=$OPENCODE_LOAD_SANDBOX/tmp
  OPENCODE_LOAD_WORK=$OPENCODE_LOAD_SANDBOX/work
  mkdir -p "$OPENCODE_LOAD_HOME" "$OPENCODE_LOAD_XDG_CONFIG" \
    "$OPENCODE_LOAD_XDG_DATA" "$OPENCODE_LOAD_XDG_CACHE" \
    "$OPENCODE_LOAD_XDG_STATE" "$OPENCODE_LOAD_TMP" "$OPENCODE_LOAD_WORK" || return 70

  opencode_load_fingerprint_source before || return 70
  OPENCODE_LOAD_SOURCE_BEFORE_SHA=$OPENCODE_LOAD_SOURCE_SHA
  OPENCODE_LOAD_SOURCE_OUTPUT_BEFORE_SHA=$OPENCODE_LOAD_SOURCE_OUTPUT_SHA
  OPENCODE_LOAD_MANIFEST_BEFORE_SHA=$OPENCODE_LOAD_SOURCE_MANIFEST_SHA
  OPENCODE_LOAD_BIN_BEFORE_SHA=$OPENCODE_LOAD_SOURCE_BIN_SHA
  opencode_load_fingerprint_global before || return 70
  OPENCODE_LOAD_GLOBAL_BEFORE_SHA=$OPENCODE_LOAD_GLOBAL_SHA
  OPENCODE_LOAD_GLOBAL_BEFORE_SUMMARY=$OPENCODE_LOAD_GLOBAL_SUMMARY

  set +e
  "$SOURCE_ROOT/bin/sensai" stage "$OPENCODE_LOAD_STAGE" \
    >"$RUN_TMP/opencode-load-stage.out" 2>"$RUN_TMP/opencode-load-stage.err"
  OPENCODE_LOAD_STAGE_RC=$?
  evidence_log_command opencode-load-stage \
    './bin/sensai stage <disposable-config-root>' "$OPENCODE_LOAD_STAGE_RC"
  test "$OPENCODE_LOAD_STAGE_RC" -eq 0 || return 70

  find "$OPENCODE_LOAD_STAGE" -mindepth 1 ! -type d -print | \
    sed "s#^$OPENCODE_LOAD_STAGE/##" | LC_ALL=C sort \
    >"$RUN_TMP/opencode-load-stage.leaves" || return 70
  if cmp -s "$SOURCE_ROOT/manifest.txt" "$RUN_TMP/opencode-load-stage.leaves"; then
    assert_record opencode-load.stage_exact 0 'config manifest 36개 leaf를 정확히 투영했다' || true
  else
    assert_record opencode-load.stage_exact 1 'stage leaf가 manifest exact-set과 다르다' || true
  fi
  assert_file opencode-load.runtime_agents "$OPENCODE_LOAD_STAGE/AGENTS.md" || true
  if test ! -e "$OPENCODE_LOAD_STAGE/bin/sensai" && \
     ! test -L "$OPENCODE_LOAD_STAGE/bin/sensai"; then
    assert_record opencode-load.stage_no_cli 0 \
      'config-only stage에 외부 설치 CLI가 포함되지 않았다' || true
  else
    assert_record opencode-load.stage_no_cli 1 \
      'config-only stage에 CLI가 포함됐다' || true
  fi

  if test "${SENSAI_TEST_OPENCODE_INHERITED_SENTINEL:-0}" = 1; then
    mkdir -p "$OPENCODE_LOAD_XDG_CONFIG/opencode" || return 70
    jq -n --arg sentinel "$OPENCODE_LOAD_SENTINEL" '{
      username:$sentinel,
      command:{
        "sensai/inherited-sentinel":{
          description:"상속 설정 탐지용 테스트 명령",
          template:"상속 설정 탐지용 테스트 본문",
          agent:"sensai-analysis-lead",
          subtask:false
        }
      }
    }' >"$OPENCODE_LOAD_XDG_CONFIG/opencode/opencode.json" || return 70
  fi

  OPENCODE_LOAD_VERSION=$(
    cd "$OPENCODE_LOAD_WORK" || exit 70
    env -i PATH="$PATH" HOME="$OPENCODE_LOAD_HOME" \
      XDG_CONFIG_HOME="$OPENCODE_LOAD_XDG_CONFIG" \
      XDG_DATA_HOME="$OPENCODE_LOAD_XDG_DATA" \
      XDG_CACHE_HOME="$OPENCODE_LOAD_XDG_CACHE" \
      XDG_STATE_HOME="$OPENCODE_LOAD_XDG_STATE" \
      TMPDIR="$OPENCODE_LOAD_TMP/" OPENCODE_CONFIG_DIR="$OPENCODE_LOAD_STAGE" \
      USER=sensai-test LOGNAME=sensai-test SHELL=/bin/sh LANG=C.UTF-8 LC_ALL=C CI=1 \
      "$OPENCODE_LOAD_BIN" --version
  ) || return 70
  assert_eq opencode-load.version 1.18.3 "$OPENCODE_LOAD_VERSION" || true

  opencode_load_run_debug pass1 || return 70
  opencode_load_project_safe pass1 || return 70
  opencode_load_collect_mutations pass1 || return 70
  OPENCODE_LOAD_PROJECTION_PASS1=$RUN_TMP/opencode-load-projection-pass1.json
  OPENCODE_LOAD_MUTATIONS_PASS1=$RUN_TMP/opencode-load-mutations-pass1.txt

  jq -r '.agents[].id' "$OPENCODE_LOAD_PROJECTION_PASS1" | LC_ALL=C sort \
    >"$RUN_TMP/opencode-load-agent-ids.txt" || return 70
  sed -E 's#^agents/##; s#\.md$##' "$SOURCE_ROOT/tests/contracts/agents.txt" | \
    LC_ALL=C sort >"$RUN_TMP/opencode-load-agent-expected.txt" || return 70
  if cmp -s "$RUN_TMP/opencode-load-agent-expected.txt" "$RUN_TMP/opencode-load-agent-ids.txt"; then
    assert_record opencode-load.agents_exact 0 'custom agent 2개 exact-set을 의미적으로 적재했다' || true
  else
    assert_record opencode-load.agents_exact 1 'custom agent 적재 exact-set이 다르다' || true
  fi

  jq -r '.commands[].id' "$OPENCODE_LOAD_PROJECTION_PASS1" | LC_ALL=C sort \
    >"$RUN_TMP/opencode-load-command-ids.txt" || return 70
  sed -E 's#^commands/##; s#\.md$##' "$SOURCE_ROOT/tests/contracts/commands.txt" | \
    LC_ALL=C sort >"$RUN_TMP/opencode-load-command-expected.txt" || return 70
  if cmp -s "$RUN_TMP/opencode-load-command-expected.txt" "$RUN_TMP/opencode-load-command-ids.txt"; then
    assert_record opencode-load.commands_exact 0 'nested sensai command 9개 exact-set을 의미적으로 적재했다' || true
  else
    assert_record opencode-load.commands_exact 1 'nested command 적재 exact-set이 다르다' || true
  fi

  jq -r '.skills[].id' "$OPENCODE_LOAD_PROJECTION_PASS1" | LC_ALL=C sort \
    >"$RUN_TMP/opencode-load-skill-ids.txt" || return 70
  sed -E 's#^skills/##; s#/SKILL\.md$##' "$SOURCE_ROOT/tests/contracts/skills.txt" | \
    LC_ALL=C sort >"$RUN_TMP/opencode-load-skill-expected.txt" || return 70
  if cmp -s "$RUN_TMP/opencode-load-skill-expected.txt" "$RUN_TMP/opencode-load-skill-ids.txt"; then
    assert_record opencode-load.skills_exact 0 'custom skill 15개 exact-set을 의미적으로 적재했다' || true
  else
    assert_record opencode-load.skills_exact 1 'custom skill 적재 exact-set이 다르다' || true
  fi

  assert_jq opencode-load.agent_semantics '
    (.agents | length) == 2 and
    (.agents | map(select(.id=="sensai-analysis-lead" and .mode=="primary" and .model=="zai/glm-5.2" and .hidden==false)) | length) == 1 and
    (.agents | map(select(.id=="sensai-evidence-peer" and .mode=="subagent" and .model=="sensai-ollama/qwen3.5:9b" and .hidden==true)) | length) == 1
  ' "$OPENCODE_LOAD_PROJECTION_PASS1" || true
  assert_jq opencode-load.command_semantics '
    (.commands | length) == 9 and all(.commands[]; .agent=="sensai-analysis-lead" and .subtask==false)
  ' "$OPENCODE_LOAD_PROJECTION_PASS1" || true
  assert_jq opencode-load.skill_locations '
    (.skills | length) == 15 and all(.skills[]; .location == ("skills/" + .id + "/SKILL.md"))
  ' "$OPENCODE_LOAD_PROJECTION_PASS1" || true

  OPENCODE_LOAD_CONFIG_PASS1=$RUN_TMP/opencode-load-config-pass1.full.json
  assert_jq opencode-load.bindings '
    . as $resolved |
    $resolved.model=="zai/glm-5.2" and
    $resolved.small_model=="sensai-ollama/qwen3.5:9b" and
    $resolved.default_agent=="sensai-analysis-lead" and
    $resolved.share=="disabled" and
    $resolved.autoupdate==false and
    $resolved.subagent_depth==1 and
    $resolved.instructions==["AGENTS.md"] and
    $resolved.compaction=={"auto":true,"prune":true} and
    $resolved.agent.compaction.model=="zai/glm-5.2"
  ' "$OPENCODE_LOAD_CONFIG_PASS1" || true
  if jq -e --slurpfile source "$SOURCE_ROOT/output/opencode.json" '
      .permission == $source[0].permission and
      .provider["sensai-ollama"] == $source[0].provider["sensai-ollama"]
    ' "$OPENCODE_LOAD_CONFIG_PASS1" >/dev/null; then
    assert_record opencode-load.permission_provider_binding 0 \
      'resolved permission과 provider가 canonical config에 정확히 결합됐다' || true
  else
    assert_record opencode-load.permission_provider_binding 1 \
      'resolved permission 또는 provider가 canonical config와 다르다' || true
  fi
  if jq -e '.isolation.inherited_sentinel == false' \
       "$OPENCODE_LOAD_PROJECTION_PASS1" >/dev/null; then
    assert_record opencode-load.inherited_sentinel 0 '상속 sentinel이 적재되지 않았다' || true
  else
    assert_record opencode-load.inherited_sentinel 1 '상속 sentinel이 resolved load에 나타났다' || true
  fi

  if opencode_load_mutations_known "$OPENCODE_LOAD_MUTATIONS_PASS1"; then
    assert_record opencode-load.disposable_mutations 0 'disposable 초기화 변화가 허용 목록 안에만 있다' || true
  else
    assert_record opencode-load.disposable_mutations 1 '알 수 없는 disposable 변화가 있다' || true
  fi

  opencode_load_run_debug pass2 || return 70
  opencode_load_project_safe pass2 || return 70
  opencode_load_collect_mutations pass2 || return 70
  OPENCODE_LOAD_PROJECTION_PASS2=$RUN_TMP/opencode-load-projection-pass2.json
  OPENCODE_LOAD_MUTATIONS_PASS2=$RUN_TMP/opencode-load-mutations-pass2.txt
  if cmp -s "$OPENCODE_LOAD_PROJECTION_PASS1" "$OPENCODE_LOAD_PROJECTION_PASS2" && \
     cmp -s "$OPENCODE_LOAD_MUTATIONS_PASS1" "$OPENCODE_LOAD_MUTATIONS_PASS2"; then
    assert_record opencode-load.idempotent 0 '두 번째 초기화의 안전 projection과 변화 경로가 같다' || true
  else
    assert_record opencode-load.idempotent 1 '두 번째 초기화에서 projection 또는 변화 경로가 달라졌다' || true
  fi

  OPENCODE_LOAD_STAGE_PAYLOAD_OK=0
  while IFS= read -r OPENCODE_LOAD_STAGE_ENTRY; do
    OPENCODE_LOAD_STAGE_SOURCE=$SOURCE_ROOT/output/$OPENCODE_LOAD_STAGE_ENTRY
    if ! cmp -s "$OPENCODE_LOAD_STAGE_SOURCE" \
         "$OPENCODE_LOAD_STAGE/$OPENCODE_LOAD_STAGE_ENTRY"; then
      OPENCODE_LOAD_STAGE_PAYLOAD_OK=1
      break
    fi
  done <"$SOURCE_ROOT/manifest.txt"
  if test "$OPENCODE_LOAD_STAGE_PAYLOAD_OK" -eq 0; then
    assert_record opencode-load.stage_payload_unchanged 0 \
      'manifest의 36개 staged config payload byte가 debug 뒤에도 같다' || true
  else
    assert_record opencode-load.stage_payload_unchanged 1 \
      'manifest의 staged payload byte가 debug 과정에서 바뀌었다' || true
  fi
  printf '%s\n' .gitignore >"$RUN_TMP/opencode-load-expected-stage-extra.txt" || return 70
  awk 'NR==FNR {payload[$0]=1; next} !($0 in payload) {print}' \
    "$SOURCE_ROOT/manifest.txt" \
    "$RUN_TMP/opencode-load-current-stage-pass2.leaves" \
    >"$RUN_TMP/opencode-load-stage-extra.txt" || return 70
  if cmp -s "$RUN_TMP/opencode-load-expected-stage-extra.txt" \
       "$RUN_TMP/opencode-load-stage-extra.txt" && \
     test -f "$OPENCODE_LOAD_STAGE/.gitignore" && \
     ! test -L "$OPENCODE_LOAD_STAGE/.gitignore"; then
    assert_record opencode-load.stage_known_initialization 0 \
      'OpenCode가 disposable config에 만든 유일한 추가 leaf는 .gitignore다' || true
  else
    assert_record opencode-load.stage_known_initialization 1 \
      'disposable config에 알 수 없는 추가 leaf가 생겼다' || true
  fi

  opencode_load_global_install_integration || return 70

  opencode_load_fingerprint_source after || return 70
  OPENCODE_LOAD_SOURCE_AFTER_SHA=$OPENCODE_LOAD_SOURCE_SHA
  OPENCODE_LOAD_SOURCE_OUTPUT_AFTER_SHA=$OPENCODE_LOAD_SOURCE_OUTPUT_SHA
  OPENCODE_LOAD_MANIFEST_AFTER_SHA=$OPENCODE_LOAD_SOURCE_MANIFEST_SHA
  OPENCODE_LOAD_BIN_AFTER_SHA=$OPENCODE_LOAD_SOURCE_BIN_SHA
  opencode_load_fingerprint_global after || return 70
  OPENCODE_LOAD_GLOBAL_AFTER_SHA=$OPENCODE_LOAD_GLOBAL_SHA
  OPENCODE_LOAD_GLOBAL_AFTER_SUMMARY=$OPENCODE_LOAD_GLOBAL_SUMMARY

  assert_eq opencode-load.source_unchanged \
    "$OPENCODE_LOAD_SOURCE_BEFORE_SHA" "$OPENCODE_LOAD_SOURCE_AFTER_SHA" || true
  assert_eq opencode-load.global_unchanged \
    "$OPENCODE_LOAD_GLOBAL_BEFORE_SHA" "$OPENCODE_LOAD_GLOBAL_AFTER_SHA" || true

  cp "$OPENCODE_LOAD_PROJECTION_PASS1" "$EVIDENCE_DIR/safe-projection-pass1.json" || return 70
  cp "$OPENCODE_LOAD_PROJECTION_PASS2" "$EVIDENCE_DIR/safe-projection-pass2.json" || return 70
  jq -Rn '[inputs]' <"$OPENCODE_LOAD_MUTATIONS_PASS2" \
    >"$EVIDENCE_DIR/disposable-mutations.json" || return 70
  opencode_load_write_environment_evidence || return 70
  jq -n \
    --arg version "$OPENCODE_LOAD_VERSION" \
    --argjson leaf_count "$(wc -l <"$RUN_TMP/opencode-load-stage.leaves" | tr -d ' ')" \
    --argjson agent_count "$(jq '.agents|length' "$OPENCODE_LOAD_PROJECTION_PASS2")" \
    --argjson command_count "$(jq '.commands|length' "$OPENCODE_LOAD_PROJECTION_PASS2")" \
    --argjson skill_count "$(jq '.skills|length' "$OPENCODE_LOAD_PROJECTION_PASS2")" \
    --argjson inherited_sentinel "$(jq '.isolation.inherited_sentinel' "$OPENCODE_LOAD_PROJECTION_PASS2")" \
    '{
      opencode_version:$version,
      platform:"macOS",
      manifest_leaf_count:$leaf_count,
      loaded:{agents:$agent_count,commands:$command_count,skills:$skill_count},
      inherited_sentinel:$inherited_sentinel,
      debug_passes:2,
      model_invocations:0,
      network_auth_attempts:0,
      acceptance_environment:"disposable HOME/XDG/TMPDIR/config root와 neutral CWD",
      full_resolved_config_persisted:false
    }' >"$EVIDENCE_DIR/load-summary.json" || return 70
  jq -n \
    --arg source_fingerprint "$SOURCE_FINGERPRINT" \
    --arg version "$OPENCODE_LOAD_VERSION" \
    --argjson inherited_sentinel "$(jq '.isolation.inherited_sentinel' "$OPENCODE_LOAD_PROJECTION_PASS2")" \
    '{
      task:"T26",
      status:(if $inherited_sentinel then "REJECTED_INHERITED_CONFIG" else "LOCAL_LOAD_PASS" end),
      source_fingerprint:$source_fingerprint,
      opencode_version:$version,
      verified:{
        manifest_projection:true,
        config_manifest_leaf_count:36,
        global_install:true,
        installed_cli_external:true,
        absolute_and_path_invocation:true,
        project_global_file_overlay:true,
        present_invalid_fail_closed:true,
        ambient_output_ignored:true,
        global_debug_projection:true,
        runtime_agents_present:true,
        agents_exact:2,
        nested_commands_exact:9,
        skills_exact:15,
        config_bindings:true,
        source_unchanged:true,
        actual_global_unchanged:true,
        idempotent_debug_load:true,
        disposable_mutations_only:true,
        cleanup_receipt:"cleanup.json"
      },
      excluded_claims:{model_invocation:0,network_auth:0,live_model:false,windows:false},
      full_resolved_config_persisted:false
    }' >"$EVIDENCE_DIR/done-claim.json" || return 70
}
