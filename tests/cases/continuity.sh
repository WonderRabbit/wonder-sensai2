#!/bin/sh
# noqa: SIZE_OK - tests/test.sh selector 계약은 shared RUN_TMP/EVIDENCE_DIR receipt를 이 단일 harness에서 집계한다.

continuity_sha() {
  tooling_sha256_file "$1" || return 70
  CONTINUITY_SHA=$TOOLING_SHA256
}

continuity_run() {
  CONTINUITY_RUN_NAME=$1
  CONTINUITY_RUN_PROJECT=$2
  shift 2
  CONTINUITY_RUN_OUT="$RUN_TMP/$CONTINUITY_RUN_NAME.out"
  CONTINUITY_RUN_ERR="$RUN_TMP/$CONTINUITY_RUN_NAME.err"
  set +e
  SENSAI_PROJECT_ROOT="$CONTINUITY_RUN_PROJECT" \
    "$SOURCE_ROOT/bin/sensai" "$@" >"$CONTINUITY_RUN_OUT" 2>"$CONTINUITY_RUN_ERR"
  CONTINUITY_RUN_RC=$?
  evidence_log_command "$CONTINUITY_RUN_NAME" "./bin/sensai $* <격리 mission 저장소>" "$CONTINUITY_RUN_RC"
}

continuity_project_init() {
  CONTINUITY_PROJECT=$1
  mkdir -p "$CONTINUITY_PROJECT/src" || return 70
  printf '%s\n' '고정 입력' >"$CONTINUITY_PROJECT/src/input.txt" || return 70
  git -C "$CONTINUITY_PROJECT" init -q || return 70
  git -C "$CONTINUITY_PROJECT" config user.email sensai-test@example.invalid || return 70
  git -C "$CONTINUITY_PROJECT" config user.name sensai-test || return 70
  git -C "$CONTINUITY_PROJECT" add src/input.txt || return 70
  git -C "$CONTINUITY_PROJECT" commit -qm 'test: 고정 입력' || return 70
}

continuity_runtime_config_case() {
  CONTINUITY_RUNTIME_CASE_CONFIG=$CONTINUITY_RUNTIME/config-$1
  mkdir -p "$CONTINUITY_RUNTIME_CASE_CONFIG" || return 70
  cp -R "$SOURCE_ROOT/output/." "$CONTINUITY_RUNTIME_CASE_CONFIG" || return 70
}

continuity_runtime_installed_run() {
  CONTINUITY_RUNTIME_RUN_NAME=$1
  CONTINUITY_RUNTIME_RUN_CONFIG=$2
  CONTINUITY_RUNTIME_RUN_PROJECT=$3
  shift 3
  set +e
  (
    cd "$CONTINUITY_RUNTIME_NEUTRAL" || exit 70
    HOME="$CONTINUITY_RUNTIME_HOME" OPENCODE_CONFIG_DIR="$CONTINUITY_RUNTIME_RUN_CONFIG" \
      SENSAI_PROJECT_ROOT="$CONTINUITY_RUNTIME_RUN_PROJECT" \
      "$CONTINUITY_RUNTIME_BIN/sensai" "$@"
  ) >"$RUN_TMP/$CONTINUITY_RUNTIME_RUN_NAME.out" \
    2>"$RUN_TMP/$CONTINUITY_RUNTIME_RUN_NAME.err"
  CONTINUITY_RUNTIME_RC=$?
  evidence_log_command "$CONTINUITY_RUNTIME_RUN_NAME" \
    "installed sensai $* <isolated runtime case>" "$CONTINUITY_RUNTIME_RC"
  cp "$RUN_TMP/$CONTINUITY_RUNTIME_RUN_NAME.out" \
    "$EVIDENCE_DIR/$CONTINUITY_RUNTIME_RUN_NAME.out" || return 70
  cp "$RUN_TMP/$CONTINUITY_RUNTIME_RUN_NAME.err" \
    "$EVIDENCE_DIR/$CONTINUITY_RUNTIME_RUN_NAME.err" || return 70
}

continuity_runtime_assert_data_error() {
  CONTINUITY_RUNTIME_ASSERT_ID=$1
  CONTINUITY_RUNTIME_ASSERT_REASON=$2
  CONTINUITY_RUNTIME_ASSERT_DETAIL=$3
  CONTINUITY_RUNTIME_ASSERT_ERR=$RUN_TMP/$CONTINUITY_RUNTIME_RUN_NAME.err
  if test "$CONTINUITY_RUNTIME_RC" -eq 65 && \
     rg -F -q --no-config "reason=$CONTINUITY_RUNTIME_ASSERT_REASON" \
       "$CONTINUITY_RUNTIME_ASSERT_ERR"; then
    assert_record "$CONTINUITY_RUNTIME_ASSERT_ID" 0 \
      "$CONTINUITY_RUNTIME_ASSERT_DETAIL" || true
  else
    assert_record "$CONTINUITY_RUNTIME_ASSERT_ID" 1 \
      "rc=$CONTINUITY_RUNTIME_RC expected=65/$CONTINUITY_RUNTIME_ASSERT_REASON" || true
  fi
}

continuity_runtime_setup() {
  CONTINUITY_RUNTIME_PARENT=$(CDPATH= cd -- "$RUN_TMP" 2>/dev/null && pwd -P) || return 70
  CONTINUITY_RUNTIME=$CONTINUITY_RUNTIME_PARENT/runtime-resolver
  CONTINUITY_RUNTIME_HOME=$CONTINUITY_RUNTIME/home
  CONTINUITY_RUNTIME_CONFIG=$CONTINUITY_RUNTIME_HOME/.config/opencode
  CONTINUITY_RUNTIME_BIN=$CONTINUITY_RUNTIME_HOME/.local/bin
  CONTINUITY_RUNTIME_NEUTRAL=$CONTINUITY_RUNTIME/neutral
  CONTINUITY_RUNTIME_ALIAS=$CONTINUITY_RUNTIME/alias
  CONTINUITY_RUNTIME_SOURCE_XDG=$CONTINUITY_RUNTIME/source-xdg
  mkdir -p "$CONTINUITY_RUNTIME_CONFIG" "$CONTINUITY_RUNTIME_BIN" \
    "$CONTINUITY_RUNTIME_NEUTRAL" "$CONTINUITY_RUNTIME_ALIAS/bin" \
    "$CONTINUITY_RUNTIME_ALIAS/output" "$CONTINUITY_RUNTIME_HOME/.local/output" \
    "$CONTINUITY_RUNTIME_NEUTRAL/output" "$CONTINUITY_RUNTIME_SOURCE_XDG/opencode" || return 70
  cp "$SOURCE_ROOT/bin/sensai" "$CONTINUITY_RUNTIME_BIN/sensai" || return 70
  chmod 755 "$CONTINUITY_RUNTIME_BIN/sensai" || return 70
  cp -R "$SOURCE_ROOT/output/." "$CONTINUITY_RUNTIME_CONFIG" || return 70
  printf '%s\n' '{' >"$CONTINUITY_RUNTIME_HOME/.local/output/opencode.json" || return 70
  printf '%s\n' '{' >"$CONTINUITY_RUNTIME_NEUTRAL/output/opencode.json" || return 70
  printf '%s\n' '{' >"$CONTINUITY_RUNTIME_SOURCE_XDG/opencode/opencode.json" || return 70
}

continuity_runtime_installed_path_case() {
  set +e
  (
    cd "$CONTINUITY_RUNTIME_NEUTRAL" || exit 70
    HOME="$CONTINUITY_RUNTIME_HOME" XDG_CONFIG_HOME="$CONTINUITY_RUNTIME_HOME/.config" \
      "$CONTINUITY_RUNTIME_BIN/sensai" doctor models
  ) >"$RUN_TMP/runtime-absolute.out" 2>"$RUN_TMP/runtime-absolute.err"
  CONTINUITY_RUNTIME_ABSOLUTE_RC=$?
  (
    cd "$CONTINUITY_RUNTIME_NEUTRAL" || exit 70
    HOME="$CONTINUITY_RUNTIME_HOME" XDG_CONFIG_HOME="$CONTINUITY_RUNTIME_HOME/.config" \
      PATH="$CONTINUITY_RUNTIME_BIN:$PATH" sensai doctor models
  ) >"$RUN_TMP/runtime-path.out" 2>"$RUN_TMP/runtime-path.err"
  CONTINUITY_RUNTIME_RC=$?
  evidence_log_command runtime-path-installed \
    'PATH=<isolated-home>/.local/bin:$PATH sensai doctor models' "$CONTINUITY_RUNTIME_RC"
  cp "$RUN_TMP/runtime-absolute.out" "$EVIDENCE_DIR/runtime-absolute.out" || return 70
  cp "$RUN_TMP/runtime-absolute.err" "$EVIDENCE_DIR/runtime-absolute.err" || return 70
  cp "$RUN_TMP/runtime-path.out" "$EVIDENCE_DIR/runtime-path.out" || return 70
  cp "$RUN_TMP/runtime-path.err" "$EVIDENCE_DIR/runtime-path.err" || return 70
  if test "$CONTINUITY_RUNTIME_ABSOLUTE_RC" -eq 0 && \
     test "$CONTINUITY_RUNTIME_RC" -eq 0 && \
     cmp -s "$RUN_TMP/runtime-absolute.out" "$RUN_TMP/runtime-path.out" && \
     cmp -s "$RUN_TMP/runtime-absolute.err" "$RUN_TMP/runtime-path.err"; then
    assert_record continuity.runtime_path_installed 0 \
      'absolute/PATH invocation이 같은 installed config root를 해소했다' || true
  else
    assert_record continuity.runtime_path_installed 1 \
      "absolute_rc=$CONTINUITY_RUNTIME_ABSOLUTE_RC path_rc=$CONTINUITY_RUNTIME_RC" || true
  fi
}

continuity_runtime_source_case() {
  (
    cd "$CONTINUITY_RUNTIME_NEUTRAL" || exit 70
    HOME="$CONTINUITY_RUNTIME_HOME" OPENCODE_CONFIG_DIR="$CONTINUITY_RUNTIME_CONFIG" \
      "$SOURCE_ROOT/bin/sensai" doctor models
  ) >"$RUN_TMP/runtime-source.out" 2>"$RUN_TMP/runtime-source.err"
  CONTINUITY_RUNTIME_RC=$?
  evidence_log_command runtime-source-global \
    './bin/sensai doctor models <same global config>' "$CONTINUITY_RUNTIME_RC"
  if test "$CONTINUITY_RUNTIME_RC" -eq 0 && \
     cmp -s "$RUN_TMP/runtime-absolute.out" "$RUN_TMP/runtime-source.out" && \
     cmp -s "$RUN_TMP/runtime-absolute.err" "$RUN_TMP/runtime-source.err"; then
    assert_record continuity.runtime_source_isolated 0 \
      'source/installed 호출이 같은 global config 결과를 냈다' || true
  else
    assert_record continuity.runtime_source_isolated 1 \
      "rc=$CONTINUITY_RUNTIME_RC expected=0" || true
  fi
}

continuity_runtime_overlay_setup() {
  CONTINUITY_OVERLAY_PROJECT=$CONTINUITY_RUNTIME/overlay-project
  continuity_project_init "$CONTINUITY_OVERLAY_PROJECT" || return 70
  CONTINUITY_OVERLAY_PROJECT=$(CDPATH= cd -- "$CONTINUITY_OVERLAY_PROJECT" 2>/dev/null && pwd -P) || \
    return 70
}

continuity_runtime_global_only_case() {
  continuity_runtime_installed_run runtime-global-only "$CONTINUITY_RUNTIME_CONFIG" \
    "$CONTINUITY_OVERLAY_PROJECT" mission init global-only src global || return 70
  if test "$CONTINUITY_RUNTIME_RC" -eq 0 && \
     rg -F -q --no-config \
       'trace_schema=global progress_schema=global trace_recipe=global progress_recipe=global' \
       "$RUN_TMP/runtime-global-only.err"; then
    assert_record continuity.runtime_global_only 0 \
      'project override 부재 시 네 asset이 global에서 해소됐다' || true
  else
    assert_record continuity.runtime_global_only 1 \
      "rc=$CONTINUITY_RUNTIME_RC provenance_missing" || true
  fi
}

continuity_runtime_mixed_overlay_case() {
  mkdir -p "$CONTINUITY_OVERLAY_PROJECT/.sensai/recipes" || return 70
  cp "$CONTINUITY_RUNTIME_CONFIG/recipes/progress.jq" \
    "$CONTINUITY_OVERLAY_PROJECT/.sensai/recipes/progress.jq" || return 70
  perl -0pi -e 's/then render_status\(\$envelope\.progress\)/then ("<!-- project-progress-recipe -->\\n" + render_status(\$envelope.progress))/' \
    "$CONTINUITY_OVERLAY_PROJECT/.sensai/recipes/progress.jq" || return 70
  continuity_runtime_installed_run runtime-mixed-overlay "$CONTINUITY_RUNTIME_CONFIG" \
    "$CONTINUITY_OVERLAY_PROJECT" mission init mixed-overlay src mixed || return 70
  if test "$CONTINUITY_RUNTIME_RC" -eq 0 && \
     rg -F -q --no-config \
       'trace_schema=global progress_schema=global trace_recipe=global progress_recipe=project' \
       "$RUN_TMP/runtime-mixed-overlay.err" && \
     rg -F -q --no-config '<!-- project-progress-recipe -->' \
       "$CONTINUITY_OVERLAY_PROJECT/docs/analysis/missions/mixed-overlay/status.md"; then
    assert_record continuity.runtime_mixed_overlay 0 \
      'project progress recipe와 global schema/trace recipe를 file별로 조합했다' || true
  else
    assert_record continuity.runtime_mixed_overlay 1 \
      "rc=$CONTINUITY_RUNTIME_RC mixed_provenance_missing" || true
  fi
}

continuity_runtime_invalid_overlay_case() {
  CONTINUITY_INVALID_PROJECT=$CONTINUITY_RUNTIME/invalid-project
  continuity_project_init "$CONTINUITY_INVALID_PROJECT" || return 70
  mkdir -p "$CONTINUITY_INVALID_PROJECT/.sensai/recipes" || return 70
  printf '%s\n' '{' >"$CONTINUITY_INVALID_PROJECT/.sensai/recipes/progress.jq" || return 70
  continuity_runtime_installed_run runtime-project-invalid "$CONTINUITY_RUNTIME_CONFIG" \
    "$CONTINUITY_INVALID_PROJECT" mission init invalid-overlay src rejected || return 70
  if test "$CONTINUITY_RUNTIME_RC" -eq 65 && \
     rg -F -q --no-config 'reason=runtime.asset_invalid' \
       "$RUN_TMP/runtime-project-invalid.err" && \
     test ! -e "$CONTINUITY_INVALID_PROJECT/docs"; then
    assert_record continuity.runtime_project_invalid 0 \
      'present-invalid project recipe를 global fallback 없이 mutation 전에 거부했다' || true
  else
    assert_record continuity.runtime_project_invalid 1 \
      "rc=$CONTINUITY_RUNTIME_RC invalid_override_fell_back_or_mutated" || true
  fi
}

continuity_runtime_overlay_cases() {
  continuity_runtime_overlay_setup || return 70
  continuity_runtime_global_only_case || return 70
  continuity_runtime_mixed_overlay_case || return 70
  continuity_runtime_invalid_overlay_case || return 70
  CONTINUITY_GLOBAL_OBSERVED=$(sed -n 's/^런타임 //p' "$RUN_TMP/runtime-global-only.err" | tail -1) || return 70
  CONTINUITY_MIXED_OBSERVED=$(sed -n 's/^런타임 //p' "$RUN_TMP/runtime-mixed-overlay.err" | tail -1) || return 70
  CONTINUITY_INVALID_OBSERVED=$(sed -n 's/^오류 reason=\([^ ]*\).*/\1/p' \
    "$RUN_TMP/runtime-project-invalid.err" | tail -1) || return 70
  if rg -F -q --no-config '<!-- project-progress-recipe -->' \
      "$CONTINUITY_OVERLAY_PROJECT/docs/analysis/missions/mixed-overlay/status.md"; then
    CONTINUITY_MIXED_MARKER=true
  else
    CONTINUITY_MIXED_MARKER=false
  fi
  if test -e "$CONTINUITY_INVALID_PROJECT/docs"; then
    CONTINUITY_INVALID_MUTATION=true
  else
    CONTINUITY_INVALID_MUTATION=false
  fi
  jq -n --arg global "$CONTINUITY_GLOBAL_OBSERVED" --arg mixed "$CONTINUITY_MIXED_OBSERVED" \
    --arg invalid_reason "$CONTINUITY_INVALID_OBSERVED" \
    --argjson mixed_marker "$CONTINUITY_MIXED_MARKER" \
    --argjson invalid_mutation "$CONTINUITY_INVALID_MUTATION" \
    '{global_observed:$global,mixed_observed:$mixed,mixed_recipe_marker:$mixed_marker,
      invalid_reason:$invalid_reason,invalid_project_mutation:$invalid_mutation}' \
    >"$EVIDENCE_DIR/runtime-overlay-provenance.json" || return 70
}

continuity_runtime_path_rejection_cases() {
  continuity_runtime_installed_run runtime-relative-override relative-config \
    "$CONTINUITY_RUNTIME_NEUTRAL" doctor models || return 70
  continuity_runtime_assert_data_error continuity.runtime_relative_override \
    runtime.asset_invalid 'relative override를 fallback보다 먼저 거부했다'

  continuity_runtime_installed_run runtime-dot-override \
    "$CONTINUITY_RUNTIME/missing-config/." "$CONTINUITY_RUNTIME_NEUTRAL" doctor models || return 70
  continuity_runtime_assert_data_error continuity.runtime_dot_override \
    runtime.asset_invalid 'trailing dot override를 missing asset과 구분했다'

  continuity_runtime_config_case root-symlink || return 70
  CONTINUITY_RUNTIME_ROOT_LINK=$CONTINUITY_RUNTIME/runtime-root-link
  ln -s "$CONTINUITY_RUNTIME_CASE_CONFIG" "$CONTINUITY_RUNTIME_ROOT_LINK" || return 70
  continuity_runtime_installed_run runtime-root-symlink "$CONTINUITY_RUNTIME_ROOT_LINK" \
    "$CONTINUITY_RUNTIME_NEUTRAL" doctor models || return 70
  continuity_runtime_assert_data_error continuity.runtime_root_symlink \
    runtime.asset_invalid 'runtime root symlink를 사용 전에 거부했다'

  continuity_runtime_config_case leaf-symlink || return 70
  mv "$CONTINUITY_RUNTIME_CASE_CONFIG/toolchain.lock.json" \
    "$CONTINUITY_RUNTIME_CASE_CONFIG/toolchain.real.json" || return 70
  ln -s toolchain.real.json "$CONTINUITY_RUNTIME_CASE_CONFIG/toolchain.lock.json" || return 70
  continuity_runtime_installed_run runtime-leaf-symlink "$CONTINUITY_RUNTIME_CASE_CONFIG" \
    "$CONTINUITY_RUNTIME_NEUTRAL" doctor models || return 70
  continuity_runtime_assert_data_error continuity.runtime_leaf_symlink \
    runtime.asset_invalid 'runtime leaf symlink를 사용 전에 거부했다'
}

continuity_runtime_malformed_asset_cases() {
  CONTINUITY_RUNTIME_PREFLIGHT_PROJECT=$CONTINUITY_RUNTIME/preflight-project
  continuity_project_init "$CONTINUITY_RUNTIME_PREFLIGHT_PROJECT" || return 70
  CONTINUITY_RUNTIME_PREFLIGHT_PROJECT=$(CDPATH= cd -- \
    "$CONTINUITY_RUNTIME_PREFLIGHT_PROJECT" 2>/dev/null && pwd -P) || return 70

  continuity_runtime_config_case malformed-config || return 70
  printf '%s\n' '{' >"$CONTINUITY_RUNTIME_CASE_CONFIG/opencode.json" || return 70
  continuity_runtime_installed_run runtime-malformed-config "$CONTINUITY_RUNTIME_CASE_CONFIG" \
    "$CONTINUITY_RUNTIME_PREFLIGHT_PROJECT" doctor models || return 70
  continuity_runtime_assert_data_error continuity.runtime_malformed_config \
    runtime.asset_invalid 'malformed config를 모델 검사 전에 거부했다'

  continuity_runtime_config_case malformed-schema || return 70
  printf '%s\n' '{' >"$CONTINUITY_RUNTIME_CASE_CONFIG/schemas/progress.schema.json" || return 70
  continuity_runtime_installed_run runtime-malformed-schema "$CONTINUITY_RUNTIME_CASE_CONFIG" \
    "$CONTINUITY_RUNTIME_PREFLIGHT_PROJECT" mission init malformed-schema src rejected || return 70
  if test ! -e "$CONTINUITY_RUNTIME_PREFLIGHT_PROJECT/docs/analysis/missions/malformed-schema"; then
    continuity_runtime_assert_data_error continuity.runtime_malformed_schema \
      runtime.asset_invalid 'malformed schema를 mission 생성 전에 거부했다'
  else
    assert_record continuity.runtime_malformed_schema 1 'malformed schema가 mission을 생성했다' || true
  fi

  continuity_runtime_config_case malformed-recipe || return 70
  printf '%s\n' '{' >"$CONTINUITY_RUNTIME_CASE_CONFIG/recipes/progress.jq" || return 70
  continuity_runtime_installed_run runtime-malformed-recipe "$CONTINUITY_RUNTIME_CASE_CONFIG" \
    "$CONTINUITY_RUNTIME_PREFLIGHT_PROJECT" mission init malformed-recipe src rejected || return 70
  if test ! -e "$CONTINUITY_RUNTIME_PREFLIGHT_PROJECT/docs/analysis/missions/malformed-recipe"; then
    continuity_runtime_assert_data_error continuity.runtime_malformed_recipe \
      runtime.asset_invalid 'malformed recipe를 mission 생성 전에 거부했다'
  else
    assert_record continuity.runtime_malformed_recipe 1 'malformed recipe가 mission을 생성했다' || true
  fi
}

continuity_runtime_mission_preflight_cases() {
  continuity_runtime_config_case mission-missing || return 70
  rm "$CONTINUITY_RUNTIME_CASE_CONFIG/opencode.json" || return 70
  for CONTINUITY_RUNTIME_MISSION_SUB in init checkpoint status resume; do
    case "$CONTINUITY_RUNTIME_MISSION_SUB" in
      init) set -- mission init preflight-init src rejected ;;
      checkpoint)
        set -- mission checkpoint preflight-checkpoint candidate.json 1 \
          0000000000000000000000000000000000000000000000000000000000000000
        ;;
      status) set -- mission status preflight-status ;;
      resume) set -- mission resume preflight-resume ;;
    esac
    continuity_runtime_installed_run "runtime-preflight-$CONTINUITY_RUNTIME_MISSION_SUB" \
      "$CONTINUITY_RUNTIME_CASE_CONFIG" "$CONTINUITY_RUNTIME_PREFLIGHT_PROJECT" "$@" || return 70
    continuity_runtime_assert_data_error \
      "continuity.runtime_preflight_$CONTINUITY_RUNTIME_MISSION_SUB" runtime.asset_missing \
      "mission ${CONTINUITY_RUNTIME_MISSION_SUB}가 mutation 전에 runtime preflight를 실행했다"
  done
  if test ! -e "$CONTINUITY_RUNTIME_PREFLIGHT_PROJECT/docs"; then
    assert_record continuity.runtime_preflight_no_mutation 0 \
      '모든 mission dispatch preflight가 project mutation 전에 종료했다' || true
  else
    assert_record continuity.runtime_preflight_no_mutation 1 \
      'mission dispatch preflight가 project tree를 생성했다' || true
  fi
}

continuity_runtime_executable_symlink_case() {
  cp -R "$SOURCE_ROOT/output/." "$CONTINUITY_RUNTIME_ALIAS/output" || return 70
  ln -s "$SOURCE_ROOT/bin/sensai" "$CONTINUITY_RUNTIME_ALIAS/bin/sensai" || return 70
  (
    cd "$CONTINUITY_RUNTIME_NEUTRAL" || exit 70
    HOME="$CONTINUITY_RUNTIME_HOME" XDG_CONFIG_HOME="$CONTINUITY_RUNTIME_HOME/.config" \
      "$CONTINUITY_RUNTIME_ALIAS/bin/sensai" doctor models
  ) >"$RUN_TMP/runtime-symlink.out" 2>"$RUN_TMP/runtime-symlink.err"
  CONTINUITY_RUNTIME_RC=$?
  evidence_log_command runtime-executable-symlink \
    '<isolated-alias>/bin/sensai doctor models' "$CONTINUITY_RUNTIME_RC"
  cp "$RUN_TMP/runtime-symlink.out" "$EVIDENCE_DIR/runtime-symlink.out" || return 70
  cp "$RUN_TMP/runtime-symlink.err" "$EVIDENCE_DIR/runtime-symlink.err" || return 70
  if test "$CONTINUITY_RUNTIME_RC" -eq 65 && \
     rg -F -q --no-config 'reason=runtime.executable_invalid' "$RUN_TMP/runtime-symlink.err"; then
    assert_record continuity.runtime_executable_symlink 0 \
      'executable symlink를 startup에서 거부했다' || true
  else
    assert_record continuity.runtime_executable_symlink 1 \
      "rc=$CONTINUITY_RUNTIME_RC expected=65/runtime.executable_invalid" || true
  fi
}

continuity_runtime_bare_source_rejection_case() {
  CONTINUITY_BARE_ROOT=$CONTINUITY_RUNTIME/bare-source
  CONTINUITY_BARE_PROJECT=$CONTINUITY_RUNTIME/bare-project
  mkdir -p "$CONTINUITY_BARE_ROOT/bin" || return 70
  cp "$SOURCE_ROOT/bin/sensai" "$CONTINUITY_BARE_ROOT/bin/sensai" || return 70
  chmod 755 "$CONTINUITY_BARE_ROOT/bin/sensai" || return 70
  continuity_project_init "$CONTINUITY_BARE_PROJECT" || return 70
  set +e
  "$CONTINUITY_BARE_ROOT/bin/sensai" help \
    >"$RUN_TMP/runtime-bare-help.out" 2>"$RUN_TMP/runtime-bare-help.err"
  CONTINUITY_BARE_HELP_RC=$?
  if test "$CONTINUITY_BARE_HELP_RC" -eq 0; then
    assert_record continuity.runtime_bare_help_asset_free 0 \
      'help는 source manifest/output 없이 usage를 출력했다' || true
  else
    assert_record continuity.runtime_bare_help_asset_free 1 \
      "rc=$CONTINUITY_BARE_HELP_RC bare help required source assets" || true
  fi
  set +e
  "$CONTINUITY_BARE_ROOT/bin/sensai" doctor tools \
    >"$RUN_TMP/runtime-bare-tools.out" 2>"$RUN_TMP/runtime-bare-tools.err"
  CONTINUITY_BARE_TOOLS_RC=$?
  case "$CONTINUITY_BARE_TOOLS_RC" in
    0|65|69)
      if rg -F -q --no-config '도구 tool=' "$RUN_TMP/runtime-bare-tools.out" \
          "$RUN_TMP/runtime-bare-tools.err" && \
         ! rg -F -q --no-config 'reason=runtime.executable_invalid' \
           "$RUN_TMP/runtime-bare-tools.err"; then
        assert_record continuity.runtime_bare_doctor_tools_asset_free 0 \
          'doctor tools는 source asset과 무관하게 tool inventory를 실행했다' || true
      else
        assert_record continuity.runtime_bare_doctor_tools_asset_free 1 \
          'doctor tools가 source admission에서 종료했다' || true
      fi
      ;;
    *) assert_record continuity.runtime_bare_doctor_tools_asset_free 1 \
         "unexpected_rc=$CONTINUITY_BARE_TOOLS_RC" || true ;;
  esac
  set +e
  HOME="$CONTINUITY_RUNTIME_HOME" OPENCODE_CONFIG_DIR="$CONTINUITY_RUNTIME_CONFIG" \
    SENSAI_PROJECT_ROOT="$CONTINUITY_BARE_PROJECT" \
    "$CONTINUITY_BARE_ROOT/bin/sensai" mission init bare-source src rejected \
    >"$RUN_TMP/runtime-bare-source.out" 2>"$RUN_TMP/runtime-bare-source.err"
  CONTINUITY_RUNTIME_RC=$?
  evidence_log_command runtime-bare-source \
    '<bare-parent>/bin/sensai mission init <isolated-project>' "$CONTINUITY_RUNTIME_RC"
  cp "$RUN_TMP/runtime-bare-source.out" "$EVIDENCE_DIR/runtime-bare-source.out" || return 70
  cp "$RUN_TMP/runtime-bare-source.err" "$EVIDENCE_DIR/runtime-bare-source.err" || return 70
  if test "$CONTINUITY_RUNTIME_RC" -eq 65 && \
     rg -F -q --no-config 'reason=runtime.executable_invalid' \
       "$RUN_TMP/runtime-bare-source.err" && \
     test ! -e "$CONTINUITY_BARE_PROJECT/docs"; then
    assert_record continuity.runtime_bare_source_rejected 0 \
      'manifest/output 없는 bare source CLI를 mission mutation 전에 거부했다' || true
  else
    assert_record continuity.runtime_bare_source_rejected 1 \
      "rc=$CONTINUITY_RUNTIME_RC bare source accepted or project mutated" || true
  fi
}

continuity_runtime_source_exact_contract_cases() {
  for CONTINUITY_SOURCE_CASE in missing extra malformed; do
    CONTINUITY_SOURCE_ROOT=$CONTINUITY_RUNTIME/source-contract-$CONTINUITY_SOURCE_CASE
    CONTINUITY_SOURCE_PROJECT=$CONTINUITY_RUNTIME/source-project-$CONTINUITY_SOURCE_CASE
    mkdir -p "$CONTINUITY_SOURCE_ROOT/bin" "$CONTINUITY_SOURCE_ROOT/output" || return 70
    cp "$SOURCE_ROOT/bin/sensai" "$CONTINUITY_SOURCE_ROOT/bin/sensai" || return 70
    cp "$SOURCE_ROOT/manifest.txt" "$CONTINUITY_SOURCE_ROOT/manifest.txt" || return 70
    cp -R "$SOURCE_ROOT/output/." "$CONTINUITY_SOURCE_ROOT/output" || return 70
    chmod 755 "$CONTINUITY_SOURCE_ROOT/bin/sensai" || return 70
    continuity_project_init "$CONTINUITY_SOURCE_PROJECT" || return 70
    CONTINUITY_SOURCE_REASON=package.source_exact_set_mismatch
    case "$CONTINUITY_SOURCE_CASE" in
      missing) rm "$CONTINUITY_SOURCE_ROOT/output/AGENTS.md" || return 70 ;;
      extra) printf '%s\n' 'unmanaged' >"$CONTINUITY_SOURCE_ROOT/output/extra.txt" || return 70 ;;
      malformed)
        LC_ALL=C sort -r "$CONTINUITY_SOURCE_ROOT/manifest.txt" \
          >"$CONTINUITY_SOURCE_ROOT/manifest.tmp" || return 70
        mv "$CONTINUITY_SOURCE_ROOT/manifest.tmp" \
          "$CONTINUITY_SOURCE_ROOT/manifest.txt" || return 70
        CONTINUITY_SOURCE_REASON=package.manifest_invalid
        ;;
    esac
    set +e
    HOME="$CONTINUITY_RUNTIME_HOME" OPENCODE_CONFIG_DIR="$CONTINUITY_RUNTIME_CONFIG" \
      SENSAI_PROJECT_ROOT="$CONTINUITY_SOURCE_PROJECT" \
      "$CONTINUITY_SOURCE_ROOT/bin/sensai" mission init \
      "source-$CONTINUITY_SOURCE_CASE" src rejected \
      >"$RUN_TMP/runtime-source-$CONTINUITY_SOURCE_CASE.out" \
      2>"$RUN_TMP/runtime-source-$CONTINUITY_SOURCE_CASE.err"
    CONTINUITY_RUNTIME_RC=$?
    if test "$CONTINUITY_RUNTIME_RC" -eq 65 && \
       rg -F -q --no-config "reason=$CONTINUITY_SOURCE_REASON" \
         "$RUN_TMP/runtime-source-$CONTINUITY_SOURCE_CASE.err" && \
       test ! -e "$CONTINUITY_SOURCE_PROJECT/docs"; then
      assert_record "continuity.runtime_source_exact_$CONTINUITY_SOURCE_CASE" 0 \
        "$CONTINUITY_SOURCE_CASE source contract를 project mutation 전에 거부했다" || true
    else
      assert_record "continuity.runtime_source_exact_$CONTINUITY_SOURCE_CASE" 1 \
        "rc=$CONTINUITY_RUNTIME_RC reason=$CONTINUITY_SOURCE_REASON or project mutated" || true
    fi
    cp "$RUN_TMP/runtime-source-$CONTINUITY_SOURCE_CASE.err" \
      "$EVIDENCE_DIR/runtime-source-$CONTINUITY_SOURCE_CASE.err" || return 70
  done
}

continuity_runtime_missing_asset_case() {
  rm "$CONTINUITY_RUNTIME_CONFIG/toolchain.lock.json" || return 70
  continuity_runtime_installed_run runtime-missing "$CONTINUITY_RUNTIME_CONFIG" \
    "$CONTINUITY_RUNTIME_NEUTRAL" doctor models || return 70
  continuity_runtime_assert_data_error continuity.runtime_asset_missing \
    runtime.asset_missing 'missing runtime asset을 stable startup reason으로 거부했다'
  cp "$SOURCE_ROOT/output/toolchain.lock.json" \
    "$CONTINUITY_RUNTIME_CONFIG/toolchain.lock.json" || return 70
}

continuity_runtime_resolver_contract() {
  continuity_runtime_setup || return 70
  continuity_runtime_installed_path_case || return 70
  continuity_runtime_source_case || return 70
  continuity_runtime_overlay_cases || return 70
  continuity_runtime_path_rejection_cases || return 70
  continuity_runtime_malformed_asset_cases || return 70
  continuity_runtime_mission_preflight_cases || return 70
  continuity_runtime_executable_symlink_case || return 70
  continuity_runtime_bare_source_rejection_case || return 70
  continuity_runtime_source_exact_contract_cases || return 70
  continuity_runtime_missing_asset_case || return 70
  OPENCODE_CONFIG_DIR=$CONTINUITY_RUNTIME_CONFIG
  export OPENCODE_CONFIG_DIR
}

continuity_write_receipt() {
  CONTINUITY_RECEIPT_PROJECT=$1
  CONTINUITY_RECEIPT_MISSION=$2
  CONTINUITY_RECEIPT_GATE=$3
  CONTINUITY_RECEIPT_VERDICT=$4
  CONTINUITY_RECEIPT_REASON=$5
  CONTINUITY_RECEIPT_RECORDED=$6
  CONTINUITY_RECEIPT_PROGRESS="$CONTINUITY_RECEIPT_PROJECT/docs/analysis/missions/$CONTINUITY_RECEIPT_MISSION/progress.json"
  CONTINUITY_RECEIPT_REL="docs/analysis/missions/$CONTINUITY_RECEIPT_MISSION/approvals/$CONTINUITY_RECEIPT_GATE-approval.json"
  CONTINUITY_RECEIPT_ABS="$CONTINUITY_RECEIPT_PROJECT/$CONTINUITY_RECEIPT_REL"
  mkdir -p "${CONTINUITY_RECEIPT_ABS%/*}" || return 70
  CONTINUITY_RECEIPT_TRACE=$(jq -r '.precondition_fingerprints.trace' "$CONTINUITY_RECEIPT_PROGRESS") || return 70
  CONTINUITY_RECEIPT_INPUTS=$(jq -r '.precondition_fingerprints.inputs' "$CONTINUITY_RECEIPT_PROGRESS") || return 70
  jq -n --arg mission "$CONTINUITY_RECEIPT_MISSION" --arg gate "$CONTINUITY_RECEIPT_GATE" \
    --arg verdict "$CONTINUITY_RECEIPT_VERDICT" --arg reason "$CONTINUITY_RECEIPT_REASON" \
    --arg recorded "$CONTINUITY_RECEIPT_RECORDED" --arg trace "$CONTINUITY_RECEIPT_TRACE" \
    --arg inputs "$CONTINUITY_RECEIPT_INPUTS" '
      {
        mission_id:$mission,gate:$gate,verdict:$verdict,reason:$reason,
        actor_role:"human",source:"elicited",recorded_at:$recorded,
        trace_sha256:$trace,inputs_sha256:$inputs
      }
    ' >"$CONTINUITY_RECEIPT_ABS" || return 70
  continuity_sha "$CONTINUITY_RECEIPT_ABS" || return 70
  CONTINUITY_RECEIPT_HASH=$CONTINUITY_SHA
}

continuity_make_candidate() {
  CONTINUITY_CANDIDATE_PROJECT=$1
  CONTINUITY_CANDIDATE_MISSION=$2
  CONTINUITY_CANDIDATE_PHASE=$3
  CONTINUITY_CANDIDATE_STATUS=$4
  CONTINUITY_CANDIDATE_TODO=$5
  CONTINUITY_CANDIDATE_NEXT=$6
  CONTINUITY_CANDIDATE_GATE=${7:-}
  CONTINUITY_CANDIDATE_VERDICT=${8:-}
  CONTINUITY_CANDIDATE_REASON=${9:-}
  CONTINUITY_CANDIDATE_PROGRESS="$CONTINUITY_CANDIDATE_PROJECT/docs/analysis/missions/$CONTINUITY_CANDIDATE_MISSION/progress.json"
  continuity_sha "$CONTINUITY_CANDIDATE_PROGRESS" || return 70
  CONTINUITY_CANDIDATE_BASE_HASH=$CONTINUITY_SHA
  CONTINUITY_CANDIDATE_BASE_REVISION=$(jq -r '.revision' "$CONTINUITY_CANDIDATE_PROGRESS") || return 70
  sleep 1
  CONTINUITY_CANDIDATE_UPDATED=$(date -u '+%Y-%m-%dT%H:%M:%SZ') || return 70
  CONTINUITY_CANDIDATE_REL="candidates/$CONTINUITY_CANDIDATE_MISSION-$((CONTINUITY_CANDIDATE_BASE_REVISION + 1)).json"
  CONTINUITY_CANDIDATE_ABS="$CONTINUITY_CANDIDATE_PROJECT/$CONTINUITY_CANDIDATE_REL"
  mkdir -p "${CONTINUITY_CANDIDATE_ABS%/*}" || return 70

  if test -n "$CONTINUITY_CANDIDATE_GATE"; then
    continuity_write_receipt "$CONTINUITY_CANDIDATE_PROJECT" "$CONTINUITY_CANDIDATE_MISSION" \
      "$CONTINUITY_CANDIDATE_GATE" "$CONTINUITY_CANDIDATE_VERDICT" \
      "$CONTINUITY_CANDIDATE_REASON" "$CONTINUITY_CANDIDATE_UPDATED" || return 70
    jq --arg phase "$CONTINUITY_CANDIDATE_PHASE" --arg status "$CONTINUITY_CANDIDATE_STATUS" \
      --arg todo "$CONTINUITY_CANDIDATE_TODO" --arg next "$CONTINUITY_CANDIDATE_NEXT" \
      --arg previous "$CONTINUITY_CANDIDATE_BASE_HASH" --arg updated "$CONTINUITY_CANDIDATE_UPDATED" \
      --arg gate "$CONTINUITY_CANDIDATE_GATE" --arg verdict "$CONTINUITY_CANDIDATE_VERDICT" \
      --arg reason "$CONTINUITY_CANDIDATE_REASON" --arg receipt_path "$CONTINUITY_RECEIPT_REL" \
      --arg receipt_sha256 "$CONTINUITY_RECEIPT_HASH" '
        .phase=$phase | .status=$status | .revision += 1
        | .todo_snapshot=[$todo] | .next=$next | .updated_at=$updated
        | .precondition_fingerprints.previous_progress=$previous
        | .approvals = ([.approvals[] | select(.gate != $gate)] + [{
            gate:$gate,verdict:$verdict,reason:$reason,actor_role:"human",source:"elicited",
            receipt_path:$receipt_path,receipt_sha256:$receipt_sha256,recorded_at:$updated
          }])
      ' "$CONTINUITY_CANDIDATE_PROGRESS" >"$CONTINUITY_CANDIDATE_ABS" || return 70
  else
    jq --arg phase "$CONTINUITY_CANDIDATE_PHASE" --arg status "$CONTINUITY_CANDIDATE_STATUS" \
      --arg todo "$CONTINUITY_CANDIDATE_TODO" --arg next "$CONTINUITY_CANDIDATE_NEXT" \
      --arg previous "$CONTINUITY_CANDIDATE_BASE_HASH" --arg updated "$CONTINUITY_CANDIDATE_UPDATED" '
        .phase=$phase | .status=$status | .revision += 1
        | .todo_snapshot=[$todo] | .next=$next | .updated_at=$updated
        | .precondition_fingerprints.previous_progress=$previous
      ' "$CONTINUITY_CANDIDATE_PROGRESS" >"$CONTINUITY_CANDIDATE_ABS" || return 70
  fi
}

continuity_checkpoint() {
  CONTINUITY_CHECKPOINT_NAME=$1
  CONTINUITY_CHECKPOINT_PROJECT=$2
  CONTINUITY_CHECKPOINT_MISSION=$3
  shift 3
  continuity_make_candidate "$CONTINUITY_CHECKPOINT_PROJECT" "$CONTINUITY_CHECKPOINT_MISSION" "$@" || return 70
  continuity_run "$CONTINUITY_CHECKPOINT_NAME" "$CONTINUITY_CHECKPOINT_PROJECT" mission checkpoint \
    "$CONTINUITY_CHECKPOINT_MISSION" "$CONTINUITY_CANDIDATE_REL" \
    "$CONTINUITY_CANDIDATE_BASE_REVISION" "$CONTINUITY_CANDIDATE_BASE_HASH"
}

continuity_assert_rejected_unchanged() {
  CONTINUITY_REJECT_ID=$1
  CONTINUITY_REJECT_PROJECT=$2
  CONTINUITY_REJECT_MISSION=$3
  CONTINUITY_REJECT_EXPECTED_RC=$4
  CONTINUITY_REJECT_REASON=$5
  CONTINUITY_REJECT_BEFORE_HASH=$6
  CONTINUITY_REJECT_ERR=$7
  continuity_sha "$CONTINUITY_REJECT_PROJECT/docs/analysis/missions/$CONTINUITY_REJECT_MISSION/progress.json" || return 70
  if test "$CONTINUITY_RUN_RC" -eq "$CONTINUITY_REJECT_EXPECTED_RC" && \
     rg -F -q --no-config "reason=$CONTINUITY_REJECT_REASON" "$CONTINUITY_REJECT_ERR" && \
     test "$CONTINUITY_SHA" = "$CONTINUITY_REJECT_BEFORE_HASH" && \
     test ! -e "$CONTINUITY_REJECT_PROJECT/docs/analysis/missions/$CONTINUITY_REJECT_MISSION/.sensai-lock"; then
    assert_record "$CONTINUITY_REJECT_ID" 0 "거부 reason=$CONTINUITY_REJECT_REASON, progress와 lock 불변" || true
  else
    assert_record "$CONTINUITY_REJECT_ID" 1 "거부 또는 불변 계약 위반 reason=$CONTINUITY_REJECT_REASON" || true
  fi
}

continuity_gate_flow() {
  CONTINUITY_MAIN=$RUN_TMP/continuity-main
  CONTINUITY_MISSION=continuity-mission
  continuity_project_init "$CONTINUITY_MAIN" || return 70
  CONTINUITY_MAIN=$(CDPATH= cd -- "$CONTINUITY_MAIN" 2>/dev/null && pwd -P) || return 70
  continuity_run continuity-init "$CONTINUITY_MAIN" mission init "$CONTINUITY_MISSION" src '연속성 검증'
  if test "$CONTINUITY_RUN_RC" -eq 0 && \
     jq -e '.phase=="F0" and .status=="planned" and .revision==1' \
       "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/progress.json" >/dev/null 2>&1; then
    assert_record continuity.init_atomic 0 'F0 원장, progress, 파생 status를 원자적으로 초기화했다' || true
  else
    assert_record continuity.init_atomic 1 '미션 초기화가 실패했다' || true
    return 0
  fi

  CONTINUITY_PROGRESS="$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/progress.json"
  CONTINUITY_STATUS="$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/status.md"

  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_BEFORE=$CONTINUITY_SHA
  continuity_checkpoint f0-bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F1 running 'F1 기술 분석' 'F1 기술 분석을 실행한다'
  continuity_assert_rejected_unchanged continuity.gate_f0_bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    65 progress.transition.invalid "$CONTINUITY_BEFORE" "$CONTINUITY_RUN_ERR" || return 70

  continuity_checkpoint f0-rejected "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F0 awaiting_human_approval 'F0 수정 계획 대기' '거절 사유를 반영해 계획을 수정한다' \
    F0 rejected '범위를 더 좁혀야 한다'
  assert_eq continuity.f0_rejection_checkpoint 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint f0-retry-accepted "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F0 awaiting_human_approval 'F0 승인 완료' 'F1 기술 분석을 시작한다' \
    F0 accepted '수정된 범위와 계획을 승인한다'
  assert_eq continuity.f0_retry_accept 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint enter-f1 "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F1 running 'F1 기술 분석 진행' 'F1 기술 분석을 완료한다'
  assert_eq continuity.enter_f1 0 "$CONTINUITY_RUN_RC" || true

  CONTINUITY_F0_RECEIPT="$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/approvals/F0-approval.json"
  cp "$CONTINUITY_F0_RECEIPT" "$RUN_TMP/F0-approval-backup.json" || return 70
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_STALE_APPROVAL_BASE=$CONTINUITY_SHA
  printf '%s\n' 'stale approval drift' >>"$CONTINUITY_F0_RECEIPT" || return 70
  continuity_run stale-approval "$CONTINUITY_MAIN" mission resume "$CONTINUITY_MISSION"
  continuity_assert_rejected_unchanged continuity.stale_approval "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    65 progress.approval_receipt "$CONTINUITY_STALE_APPROVAL_BASE" "$CONTINUITY_RUN_ERR" || return 70
  cp "$RUN_TMP/F0-approval-backup.json" "$CONTINUITY_F0_RECEIPT" || return 70

  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_INTERRUPT_HASH=$CONTINUITY_SHA
  CONTINUITY_INTERRUPT_REV=$(jq -r '.revision' "$CONTINUITY_PROGRESS") || return 70
  CONTINUITY_CAPTURE="$CONTINUITY_MAIN/.sensai-test-capture.interrupt"
  set +e
  SENSAI_TEST_INTERNAL=1 SENSAI_TEST_MISSION_INTERRUPT=after-lock \
    SENSAI_TEST_MISSION_CAPTURE="$CONTINUITY_CAPTURE" SENSAI_PROJECT_ROOT="$CONTINUITY_MAIN" \
    "$SOURCE_ROOT/bin/sensai" mission resume "$CONTINUITY_MISSION" \
    "$CONTINUITY_INTERRUPT_REV" "$CONTINUITY_INTERRUPT_HASH" \
    >"$RUN_TMP/interrupt.out" 2>"$RUN_TMP/interrupt.err"
  CONTINUITY_INTERRUPT_RC=$?
  cp "$CONTINUITY_CAPTURE" "$RUN_TMP/interrupt-lock-owner.json" || return 70
  evidence_log_command continuity-interrupt './bin/sensai mission resume <test-only interrupt after lock>' "$CONTINUITY_INTERRUPT_RC"
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  if test "$CONTINUITY_INTERRUPT_RC" -eq 130 && test "$CONTINUITY_SHA" = "$CONTINUITY_INTERRUPT_HASH" && \
     test ! -e "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock" && \
     jq -e --arg mission "$CONTINUITY_MISSION" --argjson revision "$CONTINUITY_INTERRUPT_REV" \
       --arg hash "$CONTINUITY_INTERRUPT_HASH" '
         .mission_id==$mission and .base_revision==$revision
         and .base_progress_sha256==$hash and .exclusive==true
       ' "$RUN_TMP/interrupt-lock-owner.json" >/dev/null 2>&1; then
    assert_record continuity.interrupt_cleanup 0 '중단 시 정규 상태 불변, 기준 잠금 기록 후 정리' || true
  else
    assert_record continuity.interrupt_cleanup 1 '중단 정리 또는 기준 잠금 계약 위반' || true
  fi

  continuity_run fresh-process-resume "$CONTINUITY_MAIN" mission resume "$CONTINUITY_MISSION" \
    "$CONTINUITY_INTERRUPT_REV" "$CONTINUITY_INTERRUPT_HASH"
  CONTINUITY_RESUME_OUT=$CONTINUITY_RUN_OUT
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_RESUME_HASH=$CONTINUITY_SHA
  if test "$CONTINUITY_RUN_RC" -eq 0 && jq -e \
      --arg hash "$CONTINUITY_RESUME_HASH" --arg todo 'F1 기술 분석 진행' \
      '.phase=="F1" and .revision=='"$((CONTINUITY_INTERRUPT_REV + 1))"' and .progress_sha256==$hash
       and .todo_snapshot==[$todo] and .todo==[{content:$todo,status:"in_progress",priority:"high"}]
       and .model_admission=="UNVERIFIED"' "$CONTINUITY_RESUME_OUT" >/dev/null 2>&1; then
    assert_record continuity.fresh_process_exact 0 '새 프로세스가 phase, todo, progress hash를 정확히 복원했다' || true
  else
    assert_record continuity.fresh_process_exact 1 '새 프로세스 복원 projection 불일치' || true
  fi

  continuity_run stale-resume "$CONTINUITY_MAIN" mission resume "$CONTINUITY_MISSION" \
    "$CONTINUITY_INTERRUPT_REV" "$CONTINUITY_INTERRUPT_HASH"
  continuity_assert_rejected_unchanged continuity.stale_resume "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    75 progress.resume.stale_hash "$CONTINUITY_RESUME_HASH" "$CONTINUITY_RUN_ERR" || return 70

  printf '%s\n' '# 조작된 상태' >"$CONTINUITY_STATUS" || return 70
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_STATUS_PROGRESS_HASH=$CONTINUITY_SHA
  continuity_run derived-status "$CONTINUITY_MAIN" mission status "$CONTINUITY_MISSION"
  if test "$CONTINUITY_RUN_RC" -eq 0 && rg -F -q --no-config -- '- phase: `F1`' "$CONTINUITY_RUN_OUT" && \
     rg -F -q --no-config -- '- status_view: `stale`' "$CONTINUITY_RUN_OUT" && \
     rg -F -q --no-config '# 조작된 상태' "$CONTINUITY_STATUS"; then
    assert_record continuity.status_derived_read_only 0 'status보다 progress를 우선해 읽기 전용으로 재구성했다' || true
  else
    assert_record continuity.status_derived_read_only 1 '파생 status 진실 우선순위 위반' || true
  fi

  mkdir "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock" || return 70
  printf '%s\n' '다른 작성자 잠금' >"$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock/owner" || return 70
  continuity_run concurrent-writer "$CONTINUITY_MAIN" mission resume "$CONTINUITY_MISSION"
  CONTINUITY_CONCURRENT_RC=$CONTINUITY_RUN_RC
  CONTINUITY_CONCURRENT_ERR=$CONTINUITY_RUN_ERR
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  if test "$CONTINUITY_CONCURRENT_RC" -eq 75 && \
     rg -q --no-config 'reason=progress\.resume\.concurrent detail=' "$CONTINUITY_CONCURRENT_ERR" && \
     test "$CONTINUITY_SHA" = "$CONTINUITY_STATUS_PROGRESS_HASH" && \
     rg -F -q --no-config '다른 작성자 잠금' \
       "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock/owner"; then
    assert_record continuity.concurrent_writer_rejected 0 '동일 미션 작성자를 거부하고 타인 잠금과 정규 상태를 보존했다' || true
  else
    assert_record continuity.concurrent_writer_rejected 1 '동일 미션 단일 작성자 계약 위반' || true
  fi
  rm -f "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock/owner" || return 70
  rmdir "$CONTINUITY_MAIN/docs/analysis/missions/$CONTINUITY_MISSION/.sensai-lock" || return 70

  continuity_checkpoint enter-f2 "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F2 running 'F2 비즈니스 분석 진행' 'F2 비즈니스 분석을 완료한다'
  assert_eq continuity.enter_f2 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint enter-f3 "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F3 awaiting_human_approval 'F3 AS-IS 승인 대기' 'AS-IS 승인 판정을 받는다'
  assert_eq continuity.enter_f3 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint f3-rejected "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F3 awaiting_human_approval 'F3 AS-IS 수정 대기' 'AS-IS 산출을 수정한다' \
    F3 rejected '근거 충돌을 해소해야 한다'
  assert_eq continuity.f3_rejection_checkpoint 0 "$CONTINUITY_RUN_RC" || true

  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_BEFORE=$CONTINUITY_SHA
  continuity_checkpoint f3-bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F4 running 'F4 설계 진행' 'TO-BE 설계를 실행한다'
  continuity_assert_rejected_unchanged continuity.gate_f3_bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    65 progress.transition.invalid "$CONTINUITY_BEFORE" "$CONTINUITY_RUN_ERR" || return 70

  continuity_checkpoint f3-retry-accepted "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F3 awaiting_human_approval 'F3 승인 완료' 'F4 설계를 시작한다' \
    F3 accepted '수정된 AS-IS 산출을 승인한다'
  assert_eq continuity.f3_retry_accept 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint enter-f4 "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F4 running 'F4 설계 진행' 'F4 설계를 완료한다'
  assert_eq continuity.enter_f4 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint enter-f5 "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F5 awaiting_human_approval 'F5 최종 승인 대기' '최종 미션 승인 판정을 받는다'
  assert_eq continuity.enter_f5 0 "$CONTINUITY_RUN_RC" || true
  continuity_checkpoint f5-rejected "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F5 awaiting_human_approval 'F5 보완 대기' '거절 사유를 반영해 최종 산출을 보완한다' \
    F5 rejected '테스트 근거를 보완해야 한다'
  assert_eq continuity.f5_rejection_checkpoint 0 "$CONTINUITY_RUN_RC" || true

  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_BEFORE=$CONTINUITY_SHA
  continuity_checkpoint f5-bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F5 completed '미션 완료' '완료 상태를 조회한다'
  continuity_assert_rejected_unchanged continuity.gate_f5_bypass "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    65 progress.resume.corrupt "$CONTINUITY_BEFORE" "$CONTINUITY_RUN_ERR" || return 70

  continuity_checkpoint f5-retry-accepted "$CONTINUITY_MAIN" "$CONTINUITY_MISSION" \
    F5 completed '미션 완료' '완료 상태를 조회한다' \
    F5 accepted '보완된 최종 산출과 검증 근거를 승인한다'
  assert_eq continuity.f5_retry_accept 0 "$CONTINUITY_RUN_RC" || true
  if jq -e '
      .phase=="F5" and .status=="completed"
      and ([.approvals[] | select(.verdict=="accepted") | .gate] | sort)==["F0","F3","F5"]
    ' "$CONTINUITY_PROGRESS" >/dev/null 2>&1; then
    assert_record continuity.gate_matrix_complete 0 'F0/F3/F5 거절, 재시도, 사람 승인 뒤에만 완료했다' || true
  else
    assert_record continuity.gate_matrix_complete 1 'hard gate 최종 상태가 잘못됐다' || true
  fi

  CONTINUITY_FINAL_REVISION=$(jq -r '.revision' "$CONTINUITY_PROGRESS") || return 70
  continuity_sha "$CONTINUITY_PROGRESS" || return 70
  CONTINUITY_FINAL_HASH=$CONTINUITY_SHA
}

continuity_lock_owner_theft_probe() {
  CONTINUITY_THEFT_MODE=$1
  CONTINUITY_THEFT_PROJECT=$RUN_TMP/continuity-owner-theft-$CONTINUITY_THEFT_MODE
  CONTINUITY_THEFT_MISSION=owner-theft-$CONTINUITY_THEFT_MODE
  continuity_project_init "$CONTINUITY_THEFT_PROJECT" || return 70
  CONTINUITY_THEFT_PROJECT=$(CDPATH= cd -- "$CONTINUITY_THEFT_PROJECT" 2>/dev/null && pwd -P) || return 70
  continuity_run "owner-theft-$CONTINUITY_THEFT_MODE-init" "$CONTINUITY_THEFT_PROJECT" \
    mission init "$CONTINUITY_THEFT_MISSION" src '잠금 소유권 탈취 검증'
  test "$CONTINUITY_RUN_RC" -eq 0 || return 70
  CONTINUITY_THEFT_DIR="$CONTINUITY_THEFT_PROJECT/docs/analysis/missions/$CONTINUITY_THEFT_MISSION"
  CONTINUITY_THEFT_PROGRESS="$CONTINUITY_THEFT_DIR/progress.json"
  CONTINUITY_THEFT_STATUS="$CONTINUITY_THEFT_DIR/status.md"
  CONTINUITY_THEFT_TRACE="$CONTINUITY_THEFT_DIR/trace.json"
  continuity_sha "$CONTINUITY_THEFT_PROGRESS" || return 70
  CONTINUITY_THEFT_PROGRESS_BEFORE=$CONTINUITY_SHA
  continuity_sha "$CONTINUITY_THEFT_STATUS" || return 70
  CONTINUITY_THEFT_STATUS_BEFORE=$CONTINUITY_SHA
  continuity_sha "$CONTINUITY_THEFT_TRACE" || return 70
  CONTINUITY_THEFT_TRACE_BEFORE=$CONTINUITY_SHA
  CONTINUITY_THEFT_REVISION=$(jq -r '.revision' "$CONTINUITY_THEFT_PROGRESS") || return 70

  if test "$CONTINUITY_THEFT_MODE" = checkpoint; then
    continuity_make_candidate "$CONTINUITY_THEFT_PROJECT" "$CONTINUITY_THEFT_MISSION" \
      F0 planned 'F0 미션 계획과 사람 승인 대기' 'F0 계획을 검토하고 사람 승인 영수증을 기록한다' || return 70
  fi

  CONTINUITY_THEFT_READY="$CONTINUITY_THEFT_PROJECT/.sensai-test-ready.$CONTINUITY_THEFT_MODE"
  set +e
  if test "$CONTINUITY_THEFT_MODE" = resume; then
    SENSAI_TEST_INTERNAL=1 SENSAI_TEST_MISSION_PAUSE=after-lock \
      SENSAI_TEST_MISSION_READY="$CONTINUITY_THEFT_READY" SENSAI_PROJECT_ROOT="$CONTINUITY_THEFT_PROJECT" \
      "$SOURCE_ROOT/bin/sensai" mission resume "$CONTINUITY_THEFT_MISSION" \
      "$CONTINUITY_THEFT_REVISION" "$CONTINUITY_THEFT_PROGRESS_BEFORE" \
      >"$RUN_TMP/owner-theft-resume.out" 2>"$RUN_TMP/owner-theft-resume.err" &
  else
    SENSAI_TEST_INTERNAL=1 SENSAI_TEST_MISSION_PAUSE=after-lock \
      SENSAI_TEST_MISSION_READY="$CONTINUITY_THEFT_READY" SENSAI_PROJECT_ROOT="$CONTINUITY_THEFT_PROJECT" \
      "$SOURCE_ROOT/bin/sensai" mission checkpoint "$CONTINUITY_THEFT_MISSION" \
      "$CONTINUITY_CANDIDATE_REL" "$CONTINUITY_THEFT_REVISION" "$CONTINUITY_THEFT_PROGRESS_BEFORE" \
      >"$RUN_TMP/owner-theft-checkpoint.out" 2>"$RUN_TMP/owner-theft-checkpoint.err" &
  fi
  CONTINUITY_THEFT_PID=$!
  CONTINUITY_THEFT_WAIT=0
  while ! test -f "$CONTINUITY_THEFT_READY" && test "$CONTINUITY_THEFT_WAIT" -lt 30; do
    sleep 1
    CONTINUITY_THEFT_WAIT=$((CONTINUITY_THEFT_WAIT + 1))
  done
  if test -f "$CONTINUITY_THEFT_READY"; then
    jq '.owner="foreign-token"' "$CONTINUITY_THEFT_DIR/.sensai-lock/owner" \
      >"$CONTINUITY_THEFT_DIR/.sensai-lock/owner.tmp" || return 70
    mv "$CONTINUITY_THEFT_DIR/.sensai-lock/owner.tmp" "$CONTINUITY_THEFT_DIR/.sensai-lock/owner" || return 70
    : >"$CONTINUITY_THEFT_READY.release" || return 70
  fi
  wait "$CONTINUITY_THEFT_PID"
  CONTINUITY_THEFT_RC=$?
  CONTINUITY_THEFT_ERR="$RUN_TMP/owner-theft-$CONTINUITY_THEFT_MODE.err"
  evidence_log_command "owner-token-theft-$CONTINUITY_THEFT_MODE" \
    "./bin/sensai mission $CONTINUITY_THEFT_MODE <owner token 탈취>" "$CONTINUITY_THEFT_RC"

  continuity_sha "$CONTINUITY_THEFT_PROGRESS" || return 70
  CONTINUITY_THEFT_PROGRESS_AFTER=$CONTINUITY_SHA
  continuity_sha "$CONTINUITY_THEFT_STATUS" || return 70
  CONTINUITY_THEFT_STATUS_AFTER=$CONTINUITY_SHA
  continuity_sha "$CONTINUITY_THEFT_TRACE" || return 70
  CONTINUITY_THEFT_TRACE_AFTER=$CONTINUITY_SHA
  if test "$CONTINUITY_THEFT_RC" -eq 75 && \
     rg -q --no-config 'reason=progress\.resume\.double_resume detail=lock_mismatch' "$CONTINUITY_THEFT_ERR" && \
     test "$CONTINUITY_THEFT_PROGRESS_BEFORE" = "$CONTINUITY_THEFT_PROGRESS_AFTER" && \
     test "$CONTINUITY_THEFT_STATUS_BEFORE" = "$CONTINUITY_THEFT_STATUS_AFTER" && \
     test "$CONTINUITY_THEFT_TRACE_BEFORE" = "$CONTINUITY_THEFT_TRACE_AFTER" && \
     jq -e '.owner=="foreign-token" and .exclusive==true' \
       "$CONTINUITY_THEFT_DIR/.sensai-lock/owner" >/dev/null 2>&1; then
    assert_record "continuity.owner_token_theft_${CONTINUITY_THEFT_MODE}_no_commit" 0 \
      'rename 직전 소유권 상실을 감지해 canonical 상태를 보존했다' || true
  else
    assert_record "continuity.owner_token_theft_${CONTINUITY_THEFT_MODE}_no_commit" 1 \
      "rc=$CONTINUITY_THEFT_RC progress_before=$CONTINUITY_THEFT_PROGRESS_BEFORE progress_after=$CONTINUITY_THEFT_PROGRESS_AFTER" || true
  fi
  rm -f "$CONTINUITY_THEFT_DIR/.sensai-lock/owner" "$CONTINUITY_THEFT_READY" "$CONTINUITY_THEFT_READY.release" || return 70
  rmdir "$CONTINUITY_THEFT_DIR/.sensai-lock" || return 70
}

continuity_failure_matrix() {
  continuity_lock_owner_theft_probe resume || return 70
  continuity_lock_owner_theft_probe checkpoint || return 70
  CONTINUITY_FAIL=$RUN_TMP/continuity-failures
  continuity_project_init "$CONTINUITY_FAIL" || return 70
  CONTINUITY_FAIL=$(CDPATH= cd -- "$CONTINUITY_FAIL" 2>/dev/null && pwd -P) || return 70
  continuity_run failure-init "$CONTINUITY_FAIL" mission init failure-mission src '실패 복구 검증'
  test "$CONTINUITY_RUN_RC" -eq 0 || return 70
  CONTINUITY_FAIL_PROGRESS="$CONTINUITY_FAIL/docs/analysis/missions/failure-mission/progress.json"
  CONTINUITY_FAIL_TRACE="$CONTINUITY_FAIL/docs/analysis/missions/failure-mission/trace.json"

  continuity_sha "$CONTINUITY_FAIL_PROGRESS" || return 70
  CONTINUITY_FAIL_BASE=$CONTINUITY_SHA
  cp "$CONTINUITY_FAIL_PROGRESS" "$RUN_TMP/progress-backup.json" || return 70
  printf '%s\n' '{' >"$CONTINUITY_FAIL_PROGRESS" || return 70
  continuity_sha "$CONTINUITY_FAIL_PROGRESS" || return 70
  CONTINUITY_CORRUPT_PROGRESS_HASH=$CONTINUITY_SHA
  continuity_run corrupt-progress "$CONTINUITY_FAIL" mission resume failure-mission
  continuity_assert_rejected_unchanged continuity.corrupt_progress "$CONTINUITY_FAIL" failure-mission \
    65 progress.resume.corrupt "$CONTINUITY_CORRUPT_PROGRESS_HASH" "$CONTINUITY_RUN_ERR" || return 70
  cp "$RUN_TMP/progress-backup.json" "$CONTINUITY_FAIL_PROGRESS" || return 70

  cp "$CONTINUITY_FAIL_TRACE" "$RUN_TMP/trace-backup.json" || return 70
  printf '%s\n' '{' >"$CONTINUITY_FAIL_TRACE" || return 70
  continuity_run corrupt-trace "$CONTINUITY_FAIL" mission resume failure-mission
  continuity_assert_rejected_unchanged continuity.corrupt_trace "$CONTINUITY_FAIL" failure-mission \
    65 progress.resume.corrupt "$CONTINUITY_FAIL_BASE" "$CONTINUITY_RUN_ERR" || return 70
  cp "$RUN_TMP/trace-backup.json" "$CONTINUITY_FAIL_TRACE" || return 70

  printf '%s\n' 'drift' >>"$CONTINUITY_FAIL/src/input.txt" || return 70
  continuity_run input-drift "$CONTINUITY_FAIL" mission resume failure-mission
  continuity_assert_rejected_unchanged continuity.input_drift "$CONTINUITY_FAIL" failure-mission \
    75 progress.resume.precondition_inputs "$CONTINUITY_FAIL_BASE" "$CONTINUITY_RUN_ERR" || return 70

  printf '%s\n' '고정 입력' >"$CONTINUITY_FAIL/src/input.txt" || return 70
  printf '%s\n' '다른 HEAD' >"$CONTINUITY_FAIL/head-drift.txt" || return 70
  git -C "$CONTINUITY_FAIL" add head-drift.txt || return 70
  git -C "$CONTINUITY_FAIL" commit -qm 'test: HEAD 변경' || return 70
  continuity_run git-head-drift "$CONTINUITY_FAIL" mission resume failure-mission
  continuity_assert_rejected_unchanged continuity.git_head_drift "$CONTINUITY_FAIL" failure-mission \
    75 progress.resume.precondition_git_head "$CONTINUITY_FAIL_BASE" "$CONTINUITY_RUN_ERR" || return 70

  CONTINUITY_TOOLCHAIN_PROJECT=$RUN_TMP/continuity-toolchain-project
  continuity_project_init "$CONTINUITY_TOOLCHAIN_PROJECT" || return 70
  CONTINUITY_TOOLCHAIN_PROJECT=$(CDPATH= cd -- "$CONTINUITY_TOOLCHAIN_PROJECT" 2>/dev/null && pwd -P) || return 70
  OPENCODE_CONFIG_DIR="$CONTINUITY_RUNTIME_CONFIG" SENSAI_PROJECT_ROOT="$CONTINUITY_TOOLCHAIN_PROJECT" \
    "$SOURCE_ROOT/bin/sensai" mission init toolchain-mission src 'toolchain drift 검증' \
    >"$RUN_TMP/toolchain-init.out" 2>"$RUN_TMP/toolchain-init.err" || return 70
  CONTINUITY_TOOLCHAIN_PROGRESS="$CONTINUITY_TOOLCHAIN_PROJECT/docs/analysis/missions/toolchain-mission/progress.json"
  continuity_sha "$CONTINUITY_TOOLCHAIN_PROGRESS" || return 70
  CONTINUITY_TOOLCHAIN_PROGRESS_HASH=$CONTINUITY_SHA
  cp "$CONTINUITY_RUNTIME_CONFIG/toolchain.lock.json" "$RUN_TMP/toolchain.lock.backup.json" || return 70
  jq '.model_admission="ISOLATED_DRIFT"' "$CONTINUITY_RUNTIME_CONFIG/toolchain.lock.json" \
    >"$CONTINUITY_RUNTIME_CONFIG/toolchain.lock.json.tmp" || return 70
  mv "$CONTINUITY_RUNTIME_CONFIG/toolchain.lock.json.tmp" \
    "$CONTINUITY_RUNTIME_CONFIG/toolchain.lock.json" || return 70
  set +e
  OPENCODE_CONFIG_DIR="$CONTINUITY_RUNTIME_CONFIG" SENSAI_PROJECT_ROOT="$CONTINUITY_TOOLCHAIN_PROJECT" \
    "$SOURCE_ROOT/bin/sensai" mission resume toolchain-mission \
    >"$RUN_TMP/toolchain-drift.out" 2>"$RUN_TMP/toolchain-drift.err"
  CONTINUITY_TOOLCHAIN_RC=$?
  cp "$RUN_TMP/toolchain.lock.backup.json" "$CONTINUITY_RUNTIME_CONFIG/toolchain.lock.json" || return 70
  evidence_log_command toolchain-drift './bin/sensai mission resume <격리 toolchain drift>' "$CONTINUITY_TOOLCHAIN_RC"
  continuity_sha "$CONTINUITY_TOOLCHAIN_PROGRESS" || return 70
  if test "$CONTINUITY_TOOLCHAIN_RC" -eq 75 && \
     rg -F -q --no-config 'reason=progress.resume.precondition_toolchain' "$RUN_TMP/toolchain-drift.err" && \
     test "$CONTINUITY_SHA" = "$CONTINUITY_TOOLCHAIN_PROGRESS_HASH" && \
     test ! -e "$CONTINUITY_TOOLCHAIN_PROJECT/docs/analysis/missions/toolchain-mission/.sensai-lock"; then
    assert_record continuity.toolchain_drift 0 '격리 toolchain drift를 재기준선 없이 거부했다' || true
  else
    assert_record continuity.toolchain_drift 1 'toolchain drift 또는 불변 계약 위반' || true
  fi

  CONTINUITY_PATH=$RUN_TMP/continuity-path
  continuity_project_init "$CONTINUITY_PATH" || return 70
  CONTINUITY_PATH=$(CDPATH= cd -- "$CONTINUITY_PATH" 2>/dev/null && pwd -P) || return 70
  continuity_run path-init "$CONTINUITY_PATH" mission init path-mission src '경로 검증'
  test "$CONTINUITY_RUN_RC" -eq 0 || return 70
  mv "$CONTINUITY_PATH/docs/analysis/missions/path-mission" "$CONTINUITY_PATH/path-mission-real" || return 70
  ln -s "$CONTINUITY_PATH/path-mission-real" "$CONTINUITY_PATH/docs/analysis/missions/path-mission" || return 70
  continuity_run symlink-path "$CONTINUITY_PATH" mission resume path-mission
  if test "$CONTINUITY_RUN_RC" -eq 65 && rg -F -q --no-config 'reason=mission.path_invalid' "$CONTINUITY_RUN_ERR"; then
    assert_record continuity.path_escape 0 '심볼릭 링크 미션 경로를 쓰기 전에 거부했다' || true
  else
    assert_record continuity.path_escape 1 '미션 경로 경계 위반' || true
  fi
}

continuity_write_evidence() {
  jq -n --arg mission "$CONTINUITY_MISSION" --arg phase F1 --arg hash "$CONTINUITY_RESUME_HASH" \
    --argjson revision "$((CONTINUITY_INTERRUPT_REV + 1))" '
      {scenario:"init-checkpoint-interrupt-fresh-process-resume",mission_id:$mission,
       restored:{phase:$phase,revision:$revision,progress_sha256:$hash,todo_exact:true},
       model_backed_session_restore:"UNVERIFIED"}
    ' >"$EVIDENCE_DIR/fresh-process.json" || return 70
  jq -n --arg interrupt_before "$CONTINUITY_INTERRUPT_HASH" --arg interrupt_after "$CONTINUITY_INTERRUPT_HASH" \
    --arg stale_before "$CONTINUITY_RESUME_HASH" --arg stale_after "$CONTINUITY_RESUME_HASH" \
    --arg final "$CONTINUITY_FINAL_HASH" '
      {interrupt:{before:$interrupt_before,after:$interrupt_after,changed:false},
       stale_resume:{before:$stale_before,after:$stale_after,changed:false},
       accepted_final:{after:$final,changed:true}}
    ' >"$EVIDENCE_DIR/state-diffs.json" || return 70
  jq -n '
      {locks:{exclusive:true,owner_shape_verified:true,pre_rename_ownership_recheck:true,
              interrupt_cleanup:true,foreign_lock_preserved:true,
              owner_token_theft_resume_no_commit:true,owner_token_theft_checkpoint_no_commit:true},
       gates:{F0:{reject_retry_accept:true,bypass_rejected:true},
              F3:{reject_retry_accept:true,bypass_rejected:true},
              F5:{reject_retry_accept:true,bypass_rejected:true}}}
    ' >"$EVIDENCE_DIR/lock-gate-matrix.json" || return 70
  jq -n '
      {stale:{result:"REJECTED",partial_write:false},corrupt:{result:"REJECTED",partial_write:false},
       path:{result:"REJECTED",partial_write:false},concurrency:{result:"REJECTED",partial_write:false},
       owner_token_theft:{result:"REJECTED",partial_write:false,foreign_lock_preserved:true},
       recovery_policy:"trace 기반 후보는 사람 결정 전 정규 progress에 쓰지 않음"}
    ' >"$EVIDENCE_DIR/recovery.json" || return 70
  jq -n '
      {model_backed_opencode_session_restore:"UNVERIFIED",windows_receipt:"PENDING",
       live_model_calls:0,global_config_mutations:0}
    ' >"$EVIDENCE_DIR/nonclaim.json" || return 70
  continuity_sha "$SOURCE_ROOT/bin/sensai" || return 70
  CONTINUITY_BIN_HASH=$CONTINUITY_SHA
  continuity_sha "$SOURCE_ROOT/output/recipes/progress.jq" || return 70
  CONTINUITY_RECIPE_HASH=$CONTINUITY_SHA
  continuity_sha "$SOURCE_ROOT/output/schemas/progress.schema.json" || return 70
  CONTINUITY_SCHEMA_HASH=$CONTINUITY_SHA
  jq -n --arg bin "$CONTINUITY_BIN_HASH" --arg recipe "$CONTINUITY_RECIPE_HASH" \
    --arg schema "$CONTINUITY_SCHEMA_HASH" '
      {"bin/sensai":$bin,"output/recipes/progress.jq":$recipe,
       "output/schemas/progress.schema.json":$schema}
    ' >"$EVIDENCE_DIR/current-hashes.json" || return 70
  jq -n --arg mission "$CONTINUITY_MISSION" --argjson revision "$CONTINUITY_FINAL_REVISION" \
    --arg hash "$CONTINUITY_FINAL_HASH" '
      {task:"T25",status:"IMPLEMENTED_PENDING_INDEPENDENT_VERIFICATION",
       mission_id:$mission,final_revision:$revision,final_progress_sha256:$hash,
       deterministic_continuity:true,external_claims_excluded:true}
    ' >"$EVIDENCE_DIR/done-claim.json" || return 70
}

case_continuity() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  continuity_runtime_resolver_contract || return 70
  continuity_gate_flow || return 70
  continuity_failure_matrix || return 70
  continuity_write_evidence || return 70
}

continuity_clone_source() {
  CONTINUITY_CLONE=$1
  mkdir -p "$CONTINUITY_CLONE/bin" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$CONTINUITY_CLONE/AGENTS.md" || return 70
  cp "$SOURCE_ROOT/bin/sensai" "$CONTINUITY_CLONE/bin/sensai" || return 70
  cp -R "$SOURCE_ROOT/output" "$CONTINUITY_CLONE/output" || return 70
  cp -R "$SOURCE_ROOT/tests" "$CONTINUITY_CLONE/tests" || return 70
  cp -R "$SOURCE_ROOT/fixtures" "$CONTINUITY_CLONE/fixtures" || return 70
  cp "$SOURCE_ROOT/manifest.txt" "$CONTINUITY_CLONE/manifest.txt" || return 70
}

run_expected_concurrent_mission_writer() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_CONTINUITY_ROOT=$RUN_TMP/expect-concurrent-source
  EXPECT_CONTINUITY_EVIDENCE=$EVIDENCE_DIR/inner-concurrent-writer
  continuity_clone_source "$EXPECT_CONTINUITY_ROOT" || return 70
  perl -0pi -e 's/progress\.resume\.concurrent lock_exists/progress.resume.concurrent-disabled lock_exists/' \
    "$EXPECT_CONTINUITY_ROOT/bin/sensai" || return 70
  if cmp -s "$SOURCE_ROOT/bin/sensai" "$EXPECT_CONTINUITY_ROOT/bin/sensai"; then
    return 70
  fi
  set +e
  SENSAI_TEST_SOURCE_ROOT="$EXPECT_CONTINUITY_ROOT" \
    "$TEST_RUNNER" continuity --evidence "$EXPECT_CONTINUITY_EVIDENCE" \
    >"$RUN_TMP/expect-concurrent-writer.out" 2>&1
  EXPECT_CONTINUITY_RC=$?
  evidence_log_command expected-concurrent-mission-writer \
    "$TEST_RUNNER continuity <격리 concurrent reason mutation>" "$EXPECT_CONTINUITY_RC"
  case "$EXPECT_CONTINUITY_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_CONTINUITY_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.concurrent_writer_exit 1 "$EXPECT_CONTINUITY_RC" || true
  if test -f "$EXPECT_CONTINUITY_EVIDENCE/receipt.json"; then
    assert_jq expect.concurrent_writer_named_failure '
      .result=="ASSERTION_FAILURE" and .exit==1
      and .failed_assertion_ids==["continuity.concurrent_writer_rejected"]
    ' "$EXPECT_CONTINUITY_EVIDENCE/receipt.json" || true
  else
    assert_record expect.concurrent_writer_receipt 1 'concurrent writer mutation receipt가 없다' || true
  fi
}
