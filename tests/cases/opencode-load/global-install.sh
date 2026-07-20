#!/bin/sh

opencode_load_installed_mission() {
  OPENCODE_LOAD_INSTALLED_NAME=$1
  OPENCODE_LOAD_INSTALLED_MODE=$2
  OPENCODE_LOAD_INSTALLED_PROJECT=$3
  shift 3
  OPENCODE_LOAD_INSTALLED_OUT=$RUN_TMP/opencode-load-$OPENCODE_LOAD_INSTALLED_NAME.out
  OPENCODE_LOAD_INSTALLED_ERR=$RUN_TMP/opencode-load-$OPENCODE_LOAD_INSTALLED_NAME.err
  set +e
  if test "$OPENCODE_LOAD_INSTALLED_MODE" = absolute; then
    (
      cd "$OPENCODE_LOAD_WORK" || exit 70
      env -i PATH="$PATH" HOME="$OPENCODE_LOAD_HOME" \
        XDG_CONFIG_HOME="$OPENCODE_LOAD_XDG_CONFIG" \
        TMPDIR="$OPENCODE_LOAD_TMP" SENSAI_PROJECT_ROOT="$OPENCODE_LOAD_INSTALLED_PROJECT" \
        "$OPENCODE_LOAD_HOME/.local/bin/sensai" "$@"
    ) >"$OPENCODE_LOAD_INSTALLED_OUT" 2>"$OPENCODE_LOAD_INSTALLED_ERR"
  else
    (
      cd "$OPENCODE_LOAD_WORK" || exit 70
      env -i PATH="$OPENCODE_LOAD_HOME/.local/bin:$PATH" HOME="$OPENCODE_LOAD_HOME" \
        XDG_CONFIG_HOME="$OPENCODE_LOAD_XDG_CONFIG" \
        TMPDIR="$OPENCODE_LOAD_TMP" SENSAI_PROJECT_ROOT="$OPENCODE_LOAD_INSTALLED_PROJECT" \
        sensai "$@"
    ) >"$OPENCODE_LOAD_INSTALLED_OUT" 2>"$OPENCODE_LOAD_INSTALLED_ERR"
  fi
  OPENCODE_LOAD_INSTALLED_RC=$?
  evidence_log_command "opencode-load-$OPENCODE_LOAD_INSTALLED_NAME" \
    "$OPENCODE_LOAD_INSTALLED_MODE installed sensai $* <neutral CWD/isolated HOME/project>" \
    "$OPENCODE_LOAD_INSTALLED_RC"
  cp "$OPENCODE_LOAD_INSTALLED_OUT" "$EVIDENCE_DIR/$OPENCODE_LOAD_INSTALLED_NAME.out" || return 70
  cp "$OPENCODE_LOAD_INSTALLED_ERR" "$EVIDENCE_DIR/$OPENCODE_LOAD_INSTALLED_NAME.err" || return 70
}

opencode_load_global_install_integration() {
  OPENCODE_LOAD_GLOBAL_ROOT=$OPENCODE_LOAD_SANDBOX/global-install
  OPENCODE_LOAD_HOME=$OPENCODE_LOAD_GLOBAL_ROOT/home
  OPENCODE_LOAD_STAGE=$OPENCODE_LOAD_HOME/.config/opencode
  OPENCODE_LOAD_XDG_CONFIG=$OPENCODE_LOAD_HOME/.config
  OPENCODE_LOAD_XDG_DATA=$OPENCODE_LOAD_GLOBAL_ROOT/xdg-data
  OPENCODE_LOAD_XDG_CACHE=$OPENCODE_LOAD_GLOBAL_ROOT/xdg-cache
  OPENCODE_LOAD_XDG_STATE=$OPENCODE_LOAD_GLOBAL_ROOT/xdg-state
  OPENCODE_LOAD_TMP=$OPENCODE_LOAD_GLOBAL_ROOT/tmp
  OPENCODE_LOAD_WORK=$OPENCODE_LOAD_GLOBAL_ROOT/neutral
  OPENCODE_LOAD_GLOBAL_PROJECT=$OPENCODE_LOAD_GLOBAL_ROOT/project-global
  OPENCODE_LOAD_MIXED_PROJECT=$OPENCODE_LOAD_GLOBAL_ROOT/project-mixed
  OPENCODE_LOAD_INVALID_PROJECT=$OPENCODE_LOAD_GLOBAL_ROOT/project-invalid
  mkdir -p "$OPENCODE_LOAD_STAGE" "$OPENCODE_LOAD_HOME/.local/output/schemas" \
    "$OPENCODE_LOAD_XDG_DATA" "$OPENCODE_LOAD_XDG_CACHE" "$OPENCODE_LOAD_XDG_STATE" \
    "$OPENCODE_LOAD_TMP" "$OPENCODE_LOAD_WORK/output/schemas" \
    "$OPENCODE_LOAD_GLOBAL_PROJECT/src" "$OPENCODE_LOAD_MIXED_PROJECT/src" \
    "$OPENCODE_LOAD_INVALID_PROJECT/src" || return 70

  OPENCODE_LOAD_AMBIENT_SENTINEL=SENSAI_AMBIENT_OUTPUT_MUST_BE_IGNORED
  printf '%s\n' "$OPENCODE_LOAD_AMBIENT_SENTINEL" \
    >"$OPENCODE_LOAD_HOME/.local/output/schemas/trace.schema.json" || return 70
  printf '%s\n' "$OPENCODE_LOAD_AMBIENT_SENTINEL" \
    >"$OPENCODE_LOAD_WORK/output/schemas/trace.schema.json" || return 70
  printf '%s\n' 'preexisting unmanaged config leaf' \
    >"$OPENCODE_LOAD_STAGE/unmanaged-sentinel.txt" || return 70
  printf '%s\n' 'global input' >"$OPENCODE_LOAD_GLOBAL_PROJECT/src/input.txt" || return 70
  printf '%s\n' 'mixed input' >"$OPENCODE_LOAD_MIXED_PROJECT/src/input.txt" || return 70
  printf '%s\n' 'invalid input' >"$OPENCODE_LOAD_INVALID_PROJECT/src/input.txt" || return 70
  tooling_sha256_file "$OPENCODE_LOAD_STAGE/unmanaged-sentinel.txt" || return 70
  OPENCODE_LOAD_UNMANAGED_BEFORE_SHA=$TOOLING_SHA256

  set +e
  env -i PATH="$PATH" HOME="$OPENCODE_LOAD_HOME" \
    XDG_CONFIG_HOME="$OPENCODE_LOAD_XDG_CONFIG" TMPDIR="$OPENCODE_LOAD_TMP" \
    "$SOURCE_ROOT/bin/sensai" install \
    >"$RUN_TMP/opencode-load-global-install.out" \
    2>"$RUN_TMP/opencode-load-global-install.err"
  OPENCODE_LOAD_INSTALL_RC=$?
  evidence_log_command opencode-load-global-install \
    './bin/sensai install <isolated pre-existing HOME config root>' "$OPENCODE_LOAD_INSTALL_RC"
  cp "$RUN_TMP/opencode-load-global-install.out" "$EVIDENCE_DIR/global-install.out" || return 70
  cp "$RUN_TMP/opencode-load-global-install.err" "$EVIDENCE_DIR/global-install.err" || return 70
  test "$OPENCODE_LOAD_INSTALL_RC" -eq 0 || return 70

  find "$OPENCODE_LOAD_STAGE" -mindepth 1 -type f -print | \
    sed "s#^$OPENCODE_LOAD_STAGE/##" | LC_ALL=C sort \
    >"$RUN_TMP/opencode-load-global-installed.leaves" || return 70
  awk '$0 != "unmanaged-sentinel.txt" {print}' \
    "$RUN_TMP/opencode-load-global-installed.leaves" \
    >"$RUN_TMP/opencode-load-global-managed.leaves" || return 70
  tooling_sha256_file "$OPENCODE_LOAD_STAGE/unmanaged-sentinel.txt" || return 70
  OPENCODE_LOAD_UNMANAGED_AFTER_SHA=$TOOLING_SHA256
  if cmp -s "$SOURCE_ROOT/manifest.txt" "$RUN_TMP/opencode-load-global-managed.leaves" && \
     test "$OPENCODE_LOAD_UNMANAGED_BEFORE_SHA" = "$OPENCODE_LOAD_UNMANAGED_AFTER_SHA" && \
     test -x "$OPENCODE_LOAD_HOME/.local/bin/sensai" && \
     cmp -s "$SOURCE_ROOT/bin/sensai" "$OPENCODE_LOAD_HOME/.local/bin/sensai" && \
     test ! -e "$OPENCODE_LOAD_STAGE/bin/sensai" && ! test -L "$OPENCODE_LOAD_STAGE/bin/sensai"; then
    assert_record opencode-load.global_install_topology 0 \
      'pre-existing global root에 config 36 leaf와 외부 CLI를 분리 설치했다' || true
  else
    assert_record opencode-load.global_install_topology 1 \
      'global config exact-set, unmanaged 보존 또는 외부 CLI 계약이 다르다' || true
  fi

  OPENCODE_LOAD_VERSION=$(
    cd "$OPENCODE_LOAD_WORK" || exit 70
    env -i PATH="$PATH" HOME="$OPENCODE_LOAD_HOME" \
      XDG_CONFIG_HOME="$OPENCODE_LOAD_XDG_CONFIG" XDG_DATA_HOME="$OPENCODE_LOAD_XDG_DATA" \
      XDG_CACHE_HOME="$OPENCODE_LOAD_XDG_CACHE" XDG_STATE_HOME="$OPENCODE_LOAD_XDG_STATE" \
      TMPDIR="$OPENCODE_LOAD_TMP/" OPENCODE_CONFIG_DIR="$OPENCODE_LOAD_STAGE" \
      USER=sensai-test LOGNAME=sensai-test SHELL=/bin/sh LANG=C.UTF-8 LC_ALL=C CI=1 \
      "$OPENCODE_LOAD_BIN" --version
  ) || return 70
  assert_eq opencode-load.global_version 1.18.3 "$OPENCODE_LOAD_VERSION" || true
  opencode_load_run_debug global-install || return 70
  opencode_load_project_safe global-install || return 70
  OPENCODE_LOAD_GLOBAL_PROJECTION=$RUN_TMP/opencode-load-projection-global-install.json
  cp "$OPENCODE_LOAD_GLOBAL_PROJECTION" "$EVIDENCE_DIR/global-safe-projection.json" || return 70
  assert_jq opencode-load.global_projection '
    .opencode_version == "1.18.3" and
    (.agents | length) == 2 and (.commands | length) == 9 and (.skills | length) == 15 and
    .isolation.inherited_sentinel == false
  ' "$OPENCODE_LOAD_GLOBAL_PROJECTION" || true

  opencode_load_fingerprint_tree "$OPENCODE_LOAD_STAGE" installed-runtime-before || return 70
  OPENCODE_LOAD_INSTALLED_RUNTIME_BEFORE_SHA=$OPENCODE_LOAD_TREE_SHA

  opencode_load_installed_mission global-absolute absolute \
    "$OPENCODE_LOAD_GLOBAL_PROJECT" mission init global-installed src/input.txt global || return 70
  OPENCODE_LOAD_GLOBAL_ABSOLUTE_RC=$OPENCODE_LOAD_INSTALLED_RC

  mkdir -p "$OPENCODE_LOAD_MIXED_PROJECT/.sensai/schemas" \
    "$OPENCODE_LOAD_MIXED_PROJECT/.sensai/recipes" || return 70
  jq '. + {"$comment":"SENSAI_PROJECT_TRACE_SCHEMA_MARKER"}' \
    "$OPENCODE_LOAD_STAGE/schemas/trace.schema.json" \
    >"$OPENCODE_LOAD_MIXED_PROJECT/.sensai/schemas/trace.schema.json" || return 70
  cp "$OPENCODE_LOAD_STAGE/recipes/progress.jq" \
    "$OPENCODE_LOAD_MIXED_PROJECT/.sensai/recipes/progress.jq" || return 70
  perl -0pi -e 's/then render_status\(\$envelope\.progress\)/then ("<!-- project-progress-recipe -->\\n" + render_status(\$envelope.progress))/' \
    "$OPENCODE_LOAD_MIXED_PROJECT/.sensai/recipes/progress.jq" || return 70
  opencode_load_installed_mission mixed-path path \
    "$OPENCODE_LOAD_MIXED_PROJECT" mission init mixed-overlay src/input.txt mixed || return 70
  OPENCODE_LOAD_MIXED_PATH_RC=$OPENCODE_LOAD_INSTALLED_RC

  mkdir -p "$OPENCODE_LOAD_INVALID_PROJECT/.sensai/schemas" || return 70
  printf '%s\n' '{' >"$OPENCODE_LOAD_INVALID_PROJECT/.sensai/schemas/trace.schema.json" || return 70
  opencode_load_installed_mission present-invalid absolute \
    "$OPENCODE_LOAD_INVALID_PROJECT" mission init invalid-overlay src/input.txt rejected || return 70
  OPENCODE_LOAD_INVALID_RC=$OPENCODE_LOAD_INSTALLED_RC

  if test "$OPENCODE_LOAD_GLOBAL_ABSOLUTE_RC" -eq 0 && \
     rg -F -q --no-config \
       'trace_schema=global progress_schema=global trace_recipe=global progress_recipe=global' \
       "$RUN_TMP/opencode-load-global-absolute.err"; then
    assert_record opencode-load.installed_absolute_global 0 \
      'neutral CWD의 absolute installed CLI가 global-only asset을 사용했다' || true
  else
    assert_record opencode-load.installed_absolute_global 1 \
      "rc=$OPENCODE_LOAD_GLOBAL_ABSOLUTE_RC 또는 global provenance 누락" || true
  fi
  if test "$OPENCODE_LOAD_MIXED_PATH_RC" -eq 0 && \
     rg -F -q --no-config \
       'trace_schema=project progress_schema=global trace_recipe=global progress_recipe=project' \
       "$RUN_TMP/opencode-load-mixed-path.err" && \
     rg -F -q --no-config '<!-- project-progress-recipe -->' \
       "$OPENCODE_LOAD_MIXED_PROJECT/docs/analysis/missions/mixed-overlay/status.md"; then
    assert_record opencode-load.installed_path_overlay 0 \
      'PATH installed CLI가 project schema/recipe와 absent-only global fallback을 조합했다' || true
  else
    assert_record opencode-load.installed_path_overlay 1 \
      "rc=$OPENCODE_LOAD_MIXED_PATH_RC 또는 mixed provenance/marker 누락" || true
  fi
  if test "$OPENCODE_LOAD_INVALID_RC" -eq 65 && \
     rg -F -q --no-config \
       'reason=runtime.asset_invalid detail=schemas/trace.schema.json' \
       "$RUN_TMP/opencode-load-present-invalid.err" && \
     test ! -e "$OPENCODE_LOAD_INVALID_PROJECT/docs"; then
    assert_record opencode-load.present_invalid_fail_closed 0 \
      'present-invalid project schema를 global fallback과 mutation 전에 거부했다' || true
  else
    assert_record opencode-load.present_invalid_fail_closed 1 \
      "rc=$OPENCODE_LOAD_INVALID_RC 또는 failure/mutation 계약 위반" || true
  fi

  if ! rg -q --no-config --fixed-strings "$OPENCODE_LOAD_AMBIENT_SENTINEL" \
       "$RUN_TMP/opencode-load-global-absolute.out" \
       "$RUN_TMP/opencode-load-global-absolute.err" \
       "$RUN_TMP/opencode-load-mixed-path.out" \
       "$RUN_TMP/opencode-load-mixed-path.err" \
       "$OPENCODE_LOAD_GLOBAL_PROJECTION" \
       "$OPENCODE_LOAD_GLOBAL_PROJECT/docs" \
       "$OPENCODE_LOAD_MIXED_PROJECT/docs"; then
    assert_record opencode-load.ambient_output_ignored 0 \
      'CWD와 HOME/.local의 output sentinel이 projection과 mission에 나타나지 않았다' || true
    OPENCODE_LOAD_AMBIENT_IGNORED=true
  else
    assert_record opencode-load.ambient_output_ignored 1 \
      'ambient output sentinel이 runtime 결과에 전파됐다' || true
    OPENCODE_LOAD_AMBIENT_IGNORED=false
  fi

  opencode_load_fingerprint_tree "$OPENCODE_LOAD_STAGE" installed-runtime-after || return 70
  OPENCODE_LOAD_INSTALLED_RUNTIME_AFTER_SHA=$OPENCODE_LOAD_TREE_SHA
  assert_eq opencode-load.installed_config_unchanged \
    "$OPENCODE_LOAD_INSTALLED_RUNTIME_BEFORE_SHA" \
    "$OPENCODE_LOAD_INSTALLED_RUNTIME_AFTER_SHA" || true

  OPENCODE_LOAD_GLOBAL_PROVENANCE=$(sed -n 's/^런타임 //p' \
    "$RUN_TMP/opencode-load-global-absolute.err" | tail -1) || return 70
  OPENCODE_LOAD_MIXED_PROVENANCE=$(sed -n 's/^런타임 //p' \
    "$RUN_TMP/opencode-load-mixed-path.err" | tail -1) || return 70
  jq -n \
    --arg global "$OPENCODE_LOAD_GLOBAL_PROVENANCE" \
    --arg mixed "$OPENCODE_LOAD_MIXED_PROVENANCE" \
    --arg invalid_reason runtime.asset_invalid \
    --argjson absolute_exit "$OPENCODE_LOAD_GLOBAL_ABSOLUTE_RC" \
    --argjson path_exit "$OPENCODE_LOAD_MIXED_PATH_RC" \
    --argjson invalid_exit "$OPENCODE_LOAD_INVALID_RC" \
    --argjson invalid_mutation "$(test -e "$OPENCODE_LOAD_INVALID_PROJECT/docs" && printf true || printf false)" \
    --argjson mixed_marker "$(rg -F -q --no-config '<!-- project-progress-recipe -->' "$OPENCODE_LOAD_MIXED_PROJECT/docs/analysis/missions/mixed-overlay/status.md" && printf true || printf false)" \
    --argjson ambient_output_ignored "$OPENCODE_LOAD_AMBIENT_IGNORED" \
    '{global_observed:$global,mixed_observed:$mixed,absolute_invocation_exit:$absolute_exit,
      path_invocation_exit:$path_exit,mixed_recipe_marker:$mixed_marker,
      invalid_exit:$invalid_exit,invalid_reason:$invalid_reason,
      invalid_project_mutation:$invalid_mutation,ambient_output_ignored:$ambient_output_ignored}' \
    >"$EVIDENCE_DIR/runtime-provenance.json" || return 70
  jq -n \
    --arg version "$OPENCODE_LOAD_VERSION" \
    --arg unmanaged_before "$OPENCODE_LOAD_UNMANAGED_BEFORE_SHA" \
    --arg unmanaged_after "$OPENCODE_LOAD_UNMANAGED_AFTER_SHA" \
    --arg runtime_before "$OPENCODE_LOAD_INSTALLED_RUNTIME_BEFORE_SHA" \
    --arg runtime_after "$OPENCODE_LOAD_INSTALLED_RUNTIME_AFTER_SHA" \
    '{opencode_version:$version,config_manifest_leaf_count:36,
      installed_cli:{location:"$HOME/.local/bin/sensai",external_to_config:true,source_byte_identical:true},
      preexisting_config_root:true,
      unmanaged:{before:$unmanaged_before,after:$unmanaged_after,preserved:($unmanaged_before==$unmanaged_after)},
      runtime_config:{before:$runtime_before,after:$runtime_after,unchanged:($runtime_before==$runtime_after)},
      debug_projections:1,cleanup_receipt:"cleanup.json"}' \
    >"$EVIDENCE_DIR/global-install-summary.json" || return 70
  jq -n --argjson exit "$OPENCODE_LOAD_INVALID_RC" \
    --argjson project_mutation "$(test -e "$OPENCODE_LOAD_INVALID_PROJECT/docs" && printf true || printf false)" \
    '{scenario:"present-invalid project schema",exit:$exit,reason:"runtime.asset_invalid",
      detail:"schemas/trace.schema.json",global_fallback:false,project_mutation:$project_mutation}' \
    >"$EVIDENCE_DIR/present-invalid.json" || return 70
}

