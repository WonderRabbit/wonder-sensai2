#!/bin/sh

packaging_run_global_install_probe() {
  PACKAGING_GLOBAL_HOME=$1
  PACKAGING_GLOBAL_OUT=$2
  PACKAGING_GLOBAL_ERR=$3
  PACKAGING_GLOBAL_CONFIG=$PACKAGING_GLOBAL_HOME/.config/opencode
  PACKAGING_GLOBAL_CLI=$PACKAGING_GLOBAL_HOME/.local/bin/sensai
  mkdir -p "$PACKAGING_GLOBAL_CONFIG" "$PACKAGING_GLOBAL_HOME/.local/bin" || return 70
  printf '%s\n' '보존해야 하는 비관리 파일' >"$PACKAGING_GLOBAL_CONFIG/unmanaged.txt" || return 70
  cp "$SOURCE_ROOT/output/AGENTS.md" "$PACKAGING_GLOBAL_CONFIG/AGENTS.md" || return 70
  tooling_sha256_file "$PACKAGING_GLOBAL_CONFIG/unmanaged.txt" || return 70
  PACKAGING_GLOBAL_SENTINEL_BEFORE=$TOOLING_SHA256
  tooling_sha256_file "$PACKAGING_GLOBAL_CONFIG/AGENTS.md" || return 70
  PACKAGING_GLOBAL_EQUAL_BEFORE=$TOOLING_SHA256
  set +e
  env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$PACKAGING_GLOBAL_HOME" \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    "$SOURCE_ROOT/bin/sensai" install >"$PACKAGING_GLOBAL_OUT" 2>"$PACKAGING_GLOBAL_ERR"
  PACKAGING_GLOBAL_RC=$?
  tooling_sha256_file "$PACKAGING_GLOBAL_CONFIG/unmanaged.txt" || return 70
  PACKAGING_GLOBAL_SENTINEL_AFTER=$TOOLING_SHA256
  tooling_sha256_file "$PACKAGING_GLOBAL_CONFIG/AGENTS.md" || return 70
  PACKAGING_GLOBAL_EQUAL_AFTER=$TOOLING_SHA256
}

packaging_assert_global_install() {
  PACKAGING_GLOBAL_HOME=$PACKAGING_ROOT/global-home
  packaging_run_global_install_probe "$PACKAGING_GLOBAL_HOME" \
    "$RUN_TMP/packaging-global-install.out" "$RUN_TMP/packaging-global-install.err" || return 70
  evidence_log_command packaging-global-install \
    'HOME=<isolated-home> ./bin/sensai install' "$PACKAGING_GLOBAL_RC"
  assert_eq packaging.global_install_exit 0 "$PACKAGING_GLOBAL_RC" || true
  assert_eq packaging.global_unmanaged_preserved \
    "$PACKAGING_GLOBAL_SENTINEL_BEFORE" "$PACKAGING_GLOBAL_SENTINEL_AFTER" || true
  assert_eq packaging.global_equal_preserved \
    "$PACKAGING_GLOBAL_EQUAL_BEFORE" "$PACKAGING_GLOBAL_EQUAL_AFTER" || true
  if test "$PACKAGING_GLOBAL_RC" -eq 0; then
    packaging_tree_hashes "$PACKAGING_GLOBAL_CONFIG" \
      "$RUN_TMP/packaging-global-install.sha256" || return 70
    if cmp -s "$RUN_TMP/packaging-source.sha256" "$RUN_TMP/packaging-global-install.sha256"; then
      assert_record packaging.global_hashes 0 '36개 managed leaf가 source와 byte-equal하다' || true
    else
      assert_record packaging.global_hashes 1 'global managed leaf hash가 source와 다르다' || true
    fi
    if test -f "$PACKAGING_GLOBAL_CLI" && ! test -L "$PACKAGING_GLOBAL_CLI" && \
       test -x "$PACKAGING_GLOBAL_CLI" && cmp -s "$SOURCE_ROOT/bin/sensai" "$PACKAGING_GLOBAL_CLI"; then
      assert_record packaging.global_cli 0 '단일 global CLI가 실행 가능하고 source와 byte-equal하다' || true
    else
      assert_record packaging.global_cli 1 'global CLI byte 또는 실행 mode가 다르다' || true
    fi
    tooling_sha256_file "$PACKAGING_GLOBAL_CLI" || return 70
    PACKAGING_GLOBAL_CLI_TARGET_SHA=$TOOLING_SHA256
    PACKAGING_RECEIPT_MANIFEST_SHA=$(sed -n \
      's/.* manifest_sha256=\([0-9a-f][0-9a-f]*\) .*/\1/p' \
      "$RUN_TMP/packaging-global-install.out") || return 70
    PACKAGING_RECEIPT_CONFIG_SHA=$(sed -n \
      's/.* config_sha256=\([0-9a-f][0-9a-f]*\) .*/\1/p' \
      "$RUN_TMP/packaging-global-install.out") || return 70
    PACKAGING_RECEIPT_CLI_SHA=$(sed -n \
      's/.* cli_sha256=\([0-9a-f][0-9a-f]*\) .*/\1/p' \
      "$RUN_TMP/packaging-global-install.out") || return 70
    assert_eq packaging.global_receipt_manifest_hash \
      "$PACKAGING_MANIFEST_SHA" "$PACKAGING_RECEIPT_MANIFEST_SHA" || true
    assert_eq packaging.global_receipt_config_target_hash \
      "$PACKAGING_SOURCE_SHA" "$PACKAGING_RECEIPT_CONFIG_SHA" || true
    assert_eq packaging.global_receipt_cli_target_hash \
      "$PACKAGING_GLOBAL_CLI_TARGET_SHA" "$PACKAGING_RECEIPT_CLI_SHA" || true
    if rg -F -q --no-config "config_target=$PACKAGING_GLOBAL_CONFIG" \
         "$RUN_TMP/packaging-global-install.out" && \
       rg -F -q --no-config "cli_target=$PACKAGING_GLOBAL_CLI" \
         "$RUN_TMP/packaging-global-install.out" && \
       rg -q --no-config 'leaf_count=36([[:space:]]|$)' \
         "$RUN_TMP/packaging-global-install.out" && \
       rg -q --no-config 'manifest_sha256=[0-9a-f]{64}([[:space:]]|$)' \
         "$RUN_TMP/packaging-global-install.out" && \
       rg -q --no-config 'config_sha256=[0-9a-f]{64}([[:space:]]|$)' \
         "$RUN_TMP/packaging-global-install.out" && \
       rg -q --no-config 'cli_sha256=[0-9a-f]{64}([[:space:]]|$)' \
         "$RUN_TMP/packaging-global-install.out" && \
       rg -q --no-config 'config_created=35([[:space:]]|$)' \
         "$RUN_TMP/packaging-global-install.out" && \
       rg -q --no-config 'config_unchanged=1([[:space:]]|$)' \
         "$RUN_TMP/packaging-global-install.out" && \
       rg -q --no-config 'cli_result=created([[:space:]]|$)' \
         "$RUN_TMP/packaging-global-install.out" && \
       rg -q --no-config 'path_contains_local_bin=false([[:space:]]|$)' \
         "$RUN_TMP/packaging-global-install.out"; then
      assert_record packaging.global_receipt_created 0 \
        'install receipt가 target/count/hash/created 상태를 모두 기록했다' || true
    else
      assert_record packaging.global_receipt_created 1 \
        'install receipt의 stable field가 빠지거나 값이 다르다' || true
    fi
    if test "$(grep -Fxc '안내 export PATH="$HOME/.local/bin:$PATH"' \
        "$RUN_TMP/packaging-global-install.out")" -eq 1; then
      assert_record packaging.global_path_guidance_missing_path 0 \
        'PATH에 local bin이 없을 때 export 안내를 한 번 출력했다' || true
    else
      assert_record packaging.global_path_guidance_missing_path 1 \
        'PATH 누락 상태의 export 안내가 정확하지 않다' || true
    fi
  fi

  set +e
  env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$PACKAGING_GLOBAL_HOME" \
    PATH="$PACKAGING_GLOBAL_HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$SOURCE_ROOT/bin/sensai" install \
    >"$RUN_TMP/packaging-global-unchanged.out" \
    2>"$RUN_TMP/packaging-global-unchanged.err"
  PACKAGING_GLOBAL_UNCHANGED_RC=$?
  assert_eq packaging.global_unchanged_exit 0 "$PACKAGING_GLOBAL_UNCHANGED_RC" || true
  if test "$PACKAGING_GLOBAL_UNCHANGED_RC" -eq 0 && \
     rg -q --no-config 'config_created=0([[:space:]]|$)' \
       "$RUN_TMP/packaging-global-unchanged.out" && \
     rg -q --no-config 'config_unchanged=36([[:space:]]|$)' \
       "$RUN_TMP/packaging-global-unchanged.out" && \
     rg -q --no-config 'cli_result=unchanged([[:space:]]|$)' \
       "$RUN_TMP/packaging-global-unchanged.out" && \
     rg -q --no-config 'path_contains_local_bin=true([[:space:]]|$)' \
       "$RUN_TMP/packaging-global-unchanged.out" && \
     ! rg -F -q --no-config 'export PATH="$HOME/.local/bin:$PATH"' \
       "$RUN_TMP/packaging-global-unchanged.out"; then
    assert_record packaging.global_receipt_unchanged 0 \
      'idempotent receipt와 PATH 포함 상태가 정확하다' || true
  else
    assert_record packaging.global_receipt_unchanged 1 \
      'idempotent receipt 또는 PATH 안내 억제가 정확하지 않다' || true
  fi

  chmod 775 "$PACKAGING_GLOBAL_CLI" || return 70
  set +e
  env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$PACKAGING_GLOBAL_HOME" \
    PATH="$PACKAGING_GLOBAL_HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$SOURCE_ROOT/bin/sensai" install \
    >"$RUN_TMP/packaging-global-insecure-mode.out" \
    2>"$RUN_TMP/packaging-global-insecure-mode.err"
  PACKAGING_GLOBAL_MODE_RC=$?
  if test "$PACKAGING_GLOBAL_MODE_RC" -eq 73 && \
     rg -F -q --no-config 'reason=package.managed_conflict' \
       "$RUN_TMP/packaging-global-insecure-mode.err" && \
     test -n "$(find "$PACKAGING_GLOBAL_CLI" -prune -type f -perm 0775 -print)"; then
    assert_record packaging.global_cli_mode_contract 0 \
      'byte-equal CLI의 0755 이외 mode를 mutation 없이 거부했다' || true
  else
    assert_record packaging.global_cli_mode_contract 1 \
      "rc=$PACKAGING_GLOBAL_MODE_RC insecure CLI mode accepted or changed" || true
  fi

  jq -n --arg home "$PACKAGING_GLOBAL_HOME" --arg config_root "$PACKAGING_GLOBAL_CONFIG" \
    --arg cli "$PACKAGING_GLOBAL_CLI" --argjson exit "$PACKAGING_GLOBAL_RC" \
    --arg unmanaged_before "$PACKAGING_GLOBAL_SENTINEL_BEFORE" \
    --arg unmanaged_after "$PACKAGING_GLOBAL_SENTINEL_AFTER" \
    --arg equal_before "$PACKAGING_GLOBAL_EQUAL_BEFORE" --arg equal_after "$PACKAGING_GLOBAL_EQUAL_AFTER" \
    --arg manifest_sha256 "${PACKAGING_RECEIPT_MANIFEST_SHA:-}" \
    --arg config_sha256 "${PACKAGING_RECEIPT_CONFIG_SHA:-}" \
    --arg cli_sha256 "${PACKAGING_RECEIPT_CLI_SHA:-}" \
    --arg installed_cli_sha256 "${PACKAGING_GLOBAL_CLI_TARGET_SHA:-}" \
    '{home:$home,config_root:$config_root,cli:$cli,exit:$exit,managed_leaves:36,unmanaged_preserved:($unmanaged_before==$unmanaged_after),preexisting_equal_preserved:($equal_before==$equal_after),receipt:{manifest_sha256:$manifest_sha256,config_sha256:$config_sha256,cli_sha256:$cli_sha256},installed_cli_sha256:$installed_cli_sha256}' \
    >"$EVIDENCE_DIR/global-install.json" || return 70
}
