#!/bin/sh

packaging_tree_hashes() {
  PACKAGING_HASH_ROOT=$1
  PACKAGING_HASH_DEST=$2
  : >"$PACKAGING_HASH_DEST" || return 70
  while IFS= read -r PACKAGING_HASH_ENTRY; do
    if test "$PACKAGING_HASH_ROOT" = "$SOURCE_ROOT"; then
      case "$PACKAGING_HASH_ENTRY" in
        bin/sensai) PACKAGING_HASH_PATH=$SOURCE_ROOT/bin/sensai ;;
        *) PACKAGING_HASH_PATH=$SOURCE_ROOT/output/$PACKAGING_HASH_ENTRY ;;
      esac
    else
      PACKAGING_HASH_PATH=$PACKAGING_HASH_ROOT/$PACKAGING_HASH_ENTRY
    fi
    test -f "$PACKAGING_HASH_PATH" && ! test -L "$PACKAGING_HASH_PATH" || return 1
    tooling_sha256_file "$PACKAGING_HASH_PATH" || return 70
    printf '%s  %s\n' "$TOOLING_SHA256" "$PACKAGING_HASH_ENTRY" \
      >>"$PACKAGING_HASH_DEST" || return 70
  done <"$SOURCE_ROOT/manifest.txt"
}

packaging_tree_inventory() {
  PACKAGING_INVENTORY_ROOT=$1
  PACKAGING_INVENTORY_DEST=$2
  find "$PACKAGING_INVENTORY_ROOT" -mindepth 1 ! -type d -print | \
    sed "s#^$PACKAGING_INVENTORY_ROOT/##" | LC_ALL=C sort \
      >"$PACKAGING_INVENTORY_DEST"
}

packaging_assert_exact_tree() {
  PACKAGING_ASSERT_PREFIX=$1
  PACKAGING_ASSERT_ROOT=$2
  PACKAGING_ASSERT_INVENTORY=$3
  PACKAGING_ASSERT_HASHES=$4
  packaging_tree_inventory "$PACKAGING_ASSERT_ROOT" "$PACKAGING_ASSERT_INVENTORY" || return 70
  if cmp -s "$SOURCE_ROOT/manifest.txt" "$PACKAGING_ASSERT_INVENTORY"; then
    assert_record "$PACKAGING_ASSERT_PREFIX.exact_set" 0 'manifest와 stage leaf exact-set이 같다' || true
  else
    assert_record "$PACKAGING_ASSERT_PREFIX.exact_set" 1 'manifest와 stage leaf exact-set이 다르다' || true
  fi
  assert_eq "$PACKAGING_ASSERT_PREFIX.leaf_count" 37 \
    "$(wc -l <"$PACKAGING_ASSERT_INVENTORY" | tr -d ' ')" || true
  if packaging_tree_hashes "$PACKAGING_ASSERT_ROOT" "$PACKAGING_ASSERT_HASHES"; then
    if cmp -s "$RUN_TMP/packaging-source.sha256" "$PACKAGING_ASSERT_HASHES"; then
      assert_record "$PACKAGING_ASSERT_PREFIX.hashes" 0 'source와 stage SHA-256이 모두 같다' || true
    else
      assert_record "$PACKAGING_ASSERT_PREFIX.hashes" 1 'source와 stage SHA-256이 다르다' || true
    fi
  else
    PACKAGING_HASH_RC=$?
    test "$PACKAGING_HASH_RC" -ne 70 || return 70
    assert_record "$PACKAGING_ASSERT_PREFIX.hashes" 1 'stage에 regular leaf가 아닌 항목이 있다' || true
  fi
  if test -f "$PACKAGING_ASSERT_ROOT/AGENTS.md" && \
     test ! -e "$PACKAGING_ASSERT_ROOT/output" && \
     test ! -e "$PACKAGING_ASSERT_ROOT/tests" && \
     test ! -e "$PACKAGING_ASSERT_ROOT/fixtures" && \
     test -x "$PACKAGING_ASSERT_ROOT/bin/sensai" && \
     test ! -e "$PACKAGING_ASSERT_ROOT/docs" && \
     test ! -e "$PACKAGING_ASSERT_ROOT/manifest.txt"; then
    assert_record "$PACKAGING_ASSERT_PREFIX.topology" 0 'output 접두사 없이 runtime AGENTS와 설치 CLI를 포함한다' || true
  else
    assert_record "$PACKAGING_ASSERT_PREFIX.topology" 1 'stage topology 또는 repository-side 제외 계약 위반' || true
  fi
}

packaging_run_existing_target_probe() {
  PACKAGING_EXISTING_TARGET=$1
  PACKAGING_EXISTING_OUT=$2
  PACKAGING_EXISTING_ERR=$3
  mkdir "$PACKAGING_EXISTING_TARGET" || return 70
  printf '%s\n' '보존해야 하는 기존 대상' >"$PACKAGING_EXISTING_TARGET/marker.txt" || return 70
  tooling_sha256_file "$PACKAGING_EXISTING_TARGET/marker.txt" || return 70
  PACKAGING_MARKER_BEFORE=$TOOLING_SHA256
  set +e
  "$SOURCE_ROOT/bin/sensai" install "$PACKAGING_EXISTING_TARGET" \
    >"$PACKAGING_EXISTING_OUT" 2>"$PACKAGING_EXISTING_ERR"
  PACKAGING_EXISTING_RC=$?
  tooling_sha256_file "$PACKAGING_EXISTING_TARGET/marker.txt" || return 70
  PACKAGING_MARKER_AFTER=$TOOLING_SHA256
}

case_packaging() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  PACKAGING_ROOT=$RUN_TMP/packaging
  mkdir -p "$PACKAGING_ROOT" || return 70
  PACKAGING_ROOT=$(CDPATH= cd -- "$PACKAGING_ROOT" 2>/dev/null && pwd -P) || return 70

  assert_file packaging.manifest_regular "$SOURCE_ROOT/manifest.txt" || true
  if cmp -s "$SOURCE_ROOT/manifest.txt" "$SOURCE_ROOT/tests/contracts/manifest.txt"; then
    assert_record packaging.manifest_oracle 0 'root manifest가 T05 exact oracle과 같다' || true
  else
    assert_record packaging.manifest_oracle 1 'root manifest가 T05 exact oracle과 다르다' || true
  fi
  assert_eq packaging.manifest_count 37 \
    "$(wc -l <"$SOURCE_ROOT/manifest.txt" | tr -d ' ')" || true

  packaging_tree_hashes "$SOURCE_ROOT" "$RUN_TMP/packaging-source.sha256" || return 70
  tooling_sha256_file "$SOURCE_ROOT/manifest.txt" || return 70
  PACKAGING_MANIFEST_SHA=$TOOLING_SHA256
  tooling_sha256_file "$RUN_TMP/packaging-source.sha256" || return 70
  PACKAGING_SOURCE_SHA=$TOOLING_SHA256
  tooling_sha256_file "$SOURCE_ROOT/bin/sensai" || return 70
  PACKAGING_BIN_BEFORE=$TOOLING_SHA256

  PACKAGING_STAGE=$PACKAGING_ROOT/stage
  set +e
  "$SOURCE_ROOT/bin/sensai" stage "$PACKAGING_STAGE" \
    >"$RUN_TMP/packaging-stage.out" 2>"$RUN_TMP/packaging-stage.err"
  PACKAGING_STAGE_RC=$?
  evidence_log_command packaging-stage './bin/sensai stage <absent-temp-target>' "$PACKAGING_STAGE_RC"
  assert_eq packaging.stage_exit 0 "$PACKAGING_STAGE_RC" || true
  if test "$PACKAGING_STAGE_RC" -eq 0; then
    packaging_assert_exact_tree packaging.stage "$PACKAGING_STAGE" \
      "$RUN_TMP/packaging-stage.leaves" "$RUN_TMP/packaging-stage.sha256" || return 70
    if rg -q --no-config \
      '^패키지 mode=stage status=READY files=37 manifest_sha256=[0-9a-f]{64} payload_sha256=[0-9a-f]{64} stage_sha256=[0-9a-f]{64} target=/' \
      "$RUN_TMP/packaging-stage.out"; then
      assert_record packaging.stage_receipt 0 'stage가 한국어 요약과 hash를 출력한다' || true
    else
      assert_record packaging.stage_receipt 1 'stage 요약 또는 hash가 빠졌다' || true
    fi
  fi

  if test -x "$PACKAGING_STAGE/bin/sensai" && \
     cmp -s "$SOURCE_ROOT/bin/sensai" "$PACKAGING_STAGE/bin/sensai"; then
    assert_record packaging.installed_cli_exact 0 '설치 CLI가 source와 byte-identical이며 실행 가능하다' || true
  else
    assert_record packaging.installed_cli_exact 1 '설치 CLI byte 또는 실행 mode가 다르다' || true
  fi
  PACKAGING_PROJECT=$PACKAGING_ROOT/project
  mkdir -p "$PACKAGING_PROJECT/input" || return 70
  git -C "$PACKAGING_PROJECT" init -q || return 70
  printf '%s\n' '설치 CLI 입력' >"$PACKAGING_PROJECT/input/source.txt" || return 70
  set +e
  SENSAI_PROJECT_ROOT="$PACKAGING_PROJECT" \
    "$PACKAGING_STAGE/bin/sensai" mission init installed-cli input '설치 CLI 검증' \
    >"$RUN_TMP/packaging-installed-init.out" 2>"$RUN_TMP/packaging-installed-init.err"
  PACKAGING_INSTALLED_INIT_RC=$?
  SENSAI_PROJECT_ROOT="$PACKAGING_PROJECT" \
    "$PACKAGING_STAGE/bin/sensai" mission status installed-cli \
    >"$RUN_TMP/packaging-installed-status.out" 2>"$RUN_TMP/packaging-installed-status.err"
  PACKAGING_INSTALLED_STATUS_RC=$?
  evidence_log_command packaging-installed-mission-init \
    '"$OPENCODE_CONFIG_DIR/bin/sensai" mission init <isolated-project>' \
    "$PACKAGING_INSTALLED_INIT_RC"
  evidence_log_command packaging-installed-mission-status \
    '"$OPENCODE_CONFIG_DIR/bin/sensai" mission status <isolated-project>' \
    "$PACKAGING_INSTALLED_STATUS_RC"
  assert_eq packaging.installed_init_exit 0 "$PACKAGING_INSTALLED_INIT_RC" || true
  assert_eq packaging.installed_status_exit 0 "$PACKAGING_INSTALLED_STATUS_RC" || true

  PACKAGING_INSTALL=$PACKAGING_ROOT/install
  set +e
  "$SOURCE_ROOT/bin/sensai" install "$PACKAGING_INSTALL" \
    >"$RUN_TMP/packaging-install.out" 2>"$RUN_TMP/packaging-install.err"
  PACKAGING_INSTALL_RC=$?
  evidence_log_command packaging-install './bin/sensai install <absent-temp-target>' "$PACKAGING_INSTALL_RC"
  assert_eq packaging.install_exit 0 "$PACKAGING_INSTALL_RC" || true
  if test "$PACKAGING_INSTALL_RC" -eq 0; then
    packaging_assert_exact_tree packaging.install "$PACKAGING_INSTALL" \
      "$RUN_TMP/packaging-install.leaves" "$RUN_TMP/packaging-install.sha256" || return 70
  fi

  PACKAGING_EXISTING=$PACKAGING_ROOT/existing
  packaging_run_existing_target_probe "$PACKAGING_EXISTING" \
    "$RUN_TMP/packaging-existing.out" "$RUN_TMP/packaging-existing.err" || return 70
  evidence_log_command packaging-existing-target \
    './bin/sensai install <existing-temp-target>' "$PACKAGING_EXISTING_RC"
  assert_eq packaging.existing_exit 73 "$PACKAGING_EXISTING_RC" || true
  assert_eq packaging.existing_preserved "$PACKAGING_MARKER_BEFORE" "$PACKAGING_MARKER_AFTER" || true
  if rg -q --no-config '^오류 reason=package\.target_exists detail=/' \
       "$RUN_TMP/packaging-existing.err" && \
     test "$(find "$PACKAGING_EXISTING" -mindepth 1 ! -type d | wc -l | tr -d ' ')" -eq 1; then
    assert_record packaging.existing_reason 0 '기존 대상은 exit 73으로 거부되고 그대로 보존된다' || true
  else
    assert_record packaging.existing_reason 1 '기존 대상 reason 또는 exact preservation 위반' || true
  fi

  if ! find "$PACKAGING_ROOT" -maxdepth 1 -name '.sensai-package.*' -print -quit | grep -q .; then
    assert_record packaging.atomic_sibling_cleanup 0 '동일 parent sibling stage가 남지 않았다' || true
  else
    assert_record packaging.atomic_sibling_cleanup 1 '원자 이동용 sibling stage가 남았다' || true
  fi
  tooling_sha256_file "$SOURCE_ROOT/bin/sensai" || return 70
  assert_eq packaging.source_bin_unchanged "$PACKAGING_BIN_BEFORE" "$TOOLING_SHA256" || true
  packaging_tree_hashes "$SOURCE_ROOT" "$RUN_TMP/packaging-source-after.sha256" || return 70
  if cmp -s "$RUN_TMP/packaging-source.sha256" "$RUN_TMP/packaging-source-after.sha256"; then
    assert_record packaging.source_payload_unchanged 0 'source output bytes가 바뀌지 않았다' || true
  else
    assert_record packaging.source_payload_unchanged 1 'source output bytes가 바뀌었다' || true
  fi

  jq -n --arg manifest_sha256 "$PACKAGING_MANIFEST_SHA" \
    --arg payload_sha256 "$PACKAGING_SOURCE_SHA" --argjson count 37 \
    '{manifest_sha256:$manifest_sha256,payload_sha256:$payload_sha256,leaf_count:$count,oracle:"tests/contracts/manifest.txt"}' \
    >"$EVIDENCE_DIR/manifest-hashes.json" || return 70
  jq -n --arg target "$PACKAGING_STAGE" --arg payload_sha256 "$PACKAGING_SOURCE_SHA" \
    --argjson exit "$PACKAGING_STAGE_RC" --argjson count 37 \
    '{target:$target,exit:$exit,leaf_count:$count,payload_sha256:$payload_sha256,output_prefix:false,runtime_agents:true,installed_cli:{path:"bin/sensai",executable:true,byte_exact:true}}' \
    >"$EVIDENCE_DIR/stage-tree.json" || return 70
  jq -n --arg target "$PACKAGING_INSTALL" --argjson exit "$PACKAGING_INSTALL_RC" \
    --arg atomicity 'same-parent atomic rename' --arg payload_sha256 "$PACKAGING_SOURCE_SHA" \
    '{target:$target,exit:$exit,atomicity:$atomicity,payload_sha256:$payload_sha256}' \
    >"$EVIDENCE_DIR/install-target.json" || return 70
  jq -n --arg target "$PACKAGING_EXISTING" --argjson exit "$PACKAGING_EXISTING_RC" \
    --arg before "$PACKAGING_MARKER_BEFORE" --arg after "$PACKAGING_MARKER_AFTER" \
    '{target:$target,exit:$exit,before_sha256:$before,after_sha256:$after,preserved:($before==$after)}' \
    >"$EVIDENCE_DIR/target-preservation.json" || return 70
  jq -n --arg bin_sha256 "$PACKAGING_BIN_BEFORE" \
    --arg manifest_sha256 "$PACKAGING_MANIFEST_SHA" --arg payload_sha256 "$PACKAGING_SOURCE_SHA" \
    '{bin_sha256:$bin_sha256,manifest_sha256:$manifest_sha256,payload_sha256:$payload_sha256,global_config_writes:0}' \
    >"$EVIDENCE_DIR/current-hashes.json" || return 70
}
