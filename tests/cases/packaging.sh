#!/bin/sh

. "$SCRIPT_DIR/cases/packaging/global-install.sh"

packaging_tree_hashes() {
  PACKAGING_HASH_ROOT=$1
  PACKAGING_HASH_DEST=$2
  : >"$PACKAGING_HASH_DEST" || return 70
  while IFS= read -r PACKAGING_HASH_ENTRY; do
    if test "$PACKAGING_HASH_ROOT" = "$SOURCE_ROOT"; then
      PACKAGING_HASH_PATH=$SOURCE_ROOT/output/$PACKAGING_HASH_ENTRY
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
  assert_eq "$PACKAGING_ASSERT_PREFIX.leaf_count" 36 \
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
     test ! -e "$PACKAGING_ASSERT_ROOT/docs" && \
     test ! -e "$PACKAGING_ASSERT_ROOT/manifest.txt"; then
    assert_record "$PACKAGING_ASSERT_PREFIX.topology" 0 'output 접두사 없이 config payload만 포함한다' || true
  else
    assert_record "$PACKAGING_ASSERT_PREFIX.topology" 1 'stage topology 또는 repository-side 제외 계약 위반' || true
  fi
  if test ! -e "$PACKAGING_ASSERT_ROOT/bin/sensai" && \
     test ! -L "$PACKAGING_ASSERT_ROOT/bin/sensai"; then
    assert_record "$PACKAGING_ASSERT_PREFIX.no_cli" 0 'stage config payload에 bin/sensai가 없다' || true
  else
    assert_record "$PACKAGING_ASSERT_PREFIX.no_cli" 1 'stage config payload에 bin/sensai가 포함됐다' || true
  fi
}

packaging_assert_go_binary_contract() {
  set +e
  "${SENSAI_GO:-go}" version -m "$SOURCE_ROOT/bin/sensai" \
    >"$RUN_TMP/packaging-module.txt" 2>"$RUN_TMP/packaging-module.err"
  PACKAGING_MODULE_RC=$?
  evidence_log_command packaging-module '${SENSAI_GO:-go} version -m ./bin/sensai' "$PACKAGING_MODULE_RC"
  assert_eq packaging.module_metadata_exit 0 "$PACKAGING_MODULE_RC" || true
  if test "$PACKAGING_MODULE_RC" -eq 0 && \
     rg -q --no-config '^[[:space:]]*path[[:space:]]+github\.com/WonderRabbit/wonder-sensai2/cmd/sensai$' \
       "$RUN_TMP/packaging-module.txt"; then
    assert_record packaging.go_module_identity 0 '실행 파일이 sensai Go module artifact다' || true
  else
    assert_record packaging.go_module_identity 1 '실행 파일의 sensai Go module identity가 다르다' || true
  fi
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
  assert_eq packaging.manifest_count 36 \
    "$(wc -l <"$SOURCE_ROOT/manifest.txt" | tr -d ' ')" || true
  packaging_assert_go_binary_contract || return 70

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
      '^패키지 mode=stage status=READY files=36 manifest_sha256=[0-9a-f]{64} payload_sha256=[0-9a-f]{64} stage_sha256=[0-9a-f]{64} target=/' \
      "$RUN_TMP/packaging-stage.out"; then
      assert_record packaging.stage_receipt 0 'stage가 한국어 요약과 hash를 출력한다' || true
    else
      assert_record packaging.stage_receipt 1 'stage 요약 또는 hash가 빠졌다' || true
    fi
  fi

  packaging_assert_global_install || return 70

  PACKAGING_SPECIAL_SOURCE="$PACKAGING_ROOT/source [#&]"
  PACKAGING_SPECIAL_STAGE="$PACKAGING_ROOT/special-stage"
  mkdir -p "$PACKAGING_SPECIAL_SOURCE/bin" "$PACKAGING_SPECIAL_SOURCE/output" || return 70
  cp "$SOURCE_ROOT/bin/sensai" "$PACKAGING_SPECIAL_SOURCE/bin/sensai" || return 70
  cp "$SOURCE_ROOT/manifest.txt" "$PACKAGING_SPECIAL_SOURCE/manifest.txt" || return 70
  cp -R "$SOURCE_ROOT/output/." "$PACKAGING_SPECIAL_SOURCE/output" || return 70
  chmod 755 "$PACKAGING_SPECIAL_SOURCE/bin/sensai" || return 70
  set +e
  "$PACKAGING_SPECIAL_SOURCE/bin/sensai" stage "$PACKAGING_SPECIAL_STAGE" \
    >"$RUN_TMP/packaging-special-source.out" 2>"$RUN_TMP/packaging-special-source.err"
  PACKAGING_SPECIAL_RC=$?
  assert_eq packaging.special_source_path_exit 0 "$PACKAGING_SPECIAL_RC" || true
  if test "$PACKAGING_SPECIAL_RC" -eq 0; then
    packaging_assert_exact_tree packaging.special_source "$PACKAGING_SPECIAL_STAGE" \
      "$RUN_TMP/packaging-special-stage.leaves" \
      "$RUN_TMP/packaging-special-stage.sha256" || return 70
  fi

  if ! find "$PACKAGING_ROOT" \
      \( -name '.sensai-package.*' -o -name '.sensai-install.*' -o -name '.sensai-install-lock' \) \
      -print -quit | grep -q .; then
    assert_record packaging.atomic_sibling_cleanup 0 'stage/install lock과 임시 파일이 남지 않았다' || true
  else
    assert_record packaging.atomic_sibling_cleanup 1 'stage/install lock 또는 임시 파일이 남았다' || true
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
    --arg payload_sha256 "$PACKAGING_SOURCE_SHA" --argjson count 36 \
    '{manifest_sha256:$manifest_sha256,payload_sha256:$payload_sha256,leaf_count:$count,oracle:"tests/contracts/manifest.txt"}' \
    >"$EVIDENCE_DIR/manifest-hashes.json" || return 70
  jq -n --arg target "$PACKAGING_STAGE" --arg payload_sha256 "$PACKAGING_SOURCE_SHA" \
    --argjson exit "$PACKAGING_STAGE_RC" --argjson count 36 \
    '{target:$target,exit:$exit,leaf_count:$count,payload_sha256:$payload_sha256,output_prefix:false,runtime_agents:true,installed_cli:false}' \
    >"$EVIDENCE_DIR/stage-tree.json" || return 70
  jq -n --arg bin_sha256 "$PACKAGING_BIN_BEFORE" \
    --arg manifest_sha256 "$PACKAGING_MANIFEST_SHA" --arg payload_sha256 "$PACKAGING_SOURCE_SHA" \
    '{bin_sha256:$bin_sha256,manifest_sha256:$manifest_sha256,payload_sha256:$payload_sha256}' \
    >"$EVIDENCE_DIR/current-hashes.json" || return 70
}
