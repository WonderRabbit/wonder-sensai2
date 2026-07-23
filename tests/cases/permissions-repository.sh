#!/bin/sh

permissions_check_runtime_boundaries() {
  PERMISSIONS_CONFIG=$1
  PERMISSIONS_BANNED_PATHS="$RUN_TMP/permission-banned-paths.txt"
  : >"$PERMISSIONS_BANNED_PATHS" || return 70
  for PERMISSIONS_BANNED_PATH in \
    opencode.json agents commands skills schemas recipes .opencode \
    output/mcp output/plugin output/plugins output/tool output/tools; do
    if test -e "$SOURCE_ROOT/$PERMISSIONS_BANNED_PATH"; then
      printf '%s\n' "$PERMISSIONS_BANNED_PATH" >>"$PERMISSIONS_BANNED_PATHS" || return 70
    fi
  done
  if test -s "$PERMISSIONS_BANNED_PATHS"; then
    assert_record permissions.runtime_source_root 1 'runtime duplicate 또는 extension surface가 output 밖/안에 존재함' || true
  else
    assert_record permissions.runtime_source_root 0 'OpenCode runtime source는 output에만 있고 extension surface는 없음' || true
  fi

  PERMISSIONS_SOURCE_FILES="$RUN_TMP/permission-source-files.txt"
  PERMISSIONS_UNEXPECTED_SOURCE_FILES="$RUN_TMP/permission-unexpected-source-files.txt"
  find "$SOURCE_ROOT" \
    -path "$SOURCE_ROOT/.git" -prune -o \
    -path "$SOURCE_ROOT/.omo" -prune -o \
    -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
      -o -name '*.mjs' -o -name '*.cjs' -o -name '*.go' -o -name '*.java' \) \
    -print | sed "s#^$SOURCE_ROOT/##" | LC_ALL=C sort >"$PERMISSIONS_SOURCE_FILES" || return 70
  : >"$PERMISSIONS_UNEXPECTED_SOURCE_FILES" || return 70
  while IFS= read -r PERMISSIONS_SOURCE_FILE; do
    case "$PERMISSIONS_SOURCE_FILE" in
      cmd/sensai/*.go | \
      fixtures/inputs/legacy-react/src/OrdersPage.tsx | \
      fixtures/inputs/legacy-vertx/src/main/java/example/OrderVerticle.java) ;;
      *) printf '%s\n' "$PERMISSIONS_SOURCE_FILE" >>"$PERMISSIONS_UNEXPECTED_SOURCE_FILES" || return 70 ;;
    esac
  done <"$PERMISSIONS_SOURCE_FILES"
  if test ! -s "$PERMISSIONS_UNEXPECTED_SOURCE_FILES" && \
     rg -qx --no-config 'fixtures/inputs/legacy-react/src/OrdersPage.tsx' \
       "$PERMISSIONS_SOURCE_FILES" && \
     rg -qx --no-config 'fixtures/inputs/legacy-vertx/src/main/java/example/OrderVerticle.java' \
       "$PERMISSIONS_SOURCE_FILES"; then
    assert_record permissions.fixture_source_exception 0 \
      '코드 source는 stdlib Go CLI authority와 고정 fixture 두 개뿐임' || true
  else
    assert_record permissions.fixture_source_exception 1 '제품 source 또는 승인되지 않은 fixture source가 존재함' || true
  fi

  PERMISSIONS_PACKAGE_FILES="$RUN_TMP/permission-package-files.txt"
  find "$SOURCE_ROOT" \
    -path "$SOURCE_ROOT/.git" -prune -o \
    -path "$SOURCE_ROOT/.omo" -prune -o \
    -type f \( -name package.json -o -name package-lock.json -o -name bun.lock \
      -o -name bun.lockb -o -name pnpm-lock.yaml -o -name yarn.lock \
      -o -name tsconfig.json -o -name biome.json -o -name biome.jsonc \
      -o -name go.mod -o -name go.sum \) -print \
    | sed "s#^$SOURCE_ROOT/##" | LC_ALL=C sort >"$PERMISSIONS_PACKAGE_FILES" || return 70
  if test ! -s "$PERMISSIONS_PACKAGE_FILES" || \
     test "$(cat "$PERMISSIONS_PACKAGE_FILES")" = 'go.mod'; then
    assert_record permissions.no_product_runtime 0 \
      '허용된 stdlib Go CLI의 go.mod 외 Node 또는 package runtime 파일이 없음' || true
  else
    assert_record permissions.no_product_runtime 1 \
      'go.mod 외 Node 또는 package runtime 파일이 존재함' || true
  fi

  PERMISSIONS_BANNED_PATHS_JSON="$RUN_TMP/permission-banned-paths.json"
  PERMISSIONS_SOURCE_FILES_JSON="$RUN_TMP/permission-source-files.json"
  PERMISSIONS_PACKAGE_FILES_JSON="$RUN_TMP/permission-package-files.json"
  jq -Rsc 'split("\n") | map(select(length > 0))' "$PERMISSIONS_BANNED_PATHS" \
    >"$PERMISSIONS_BANNED_PATHS_JSON" || return 70
  jq -Rsc 'split("\n") | map(select(length > 0))' "$PERMISSIONS_SOURCE_FILES" \
    >"$PERMISSIONS_SOURCE_FILES_JSON" || return 70
  jq -Rsc 'split("\n") | map(select(length > 0))' "$PERMISSIONS_PACKAGE_FILES" \
    >"$PERMISSIONS_PACKAGE_FILES_JSON" || return 70

  jq -n \
    --slurpfile runtime_paths "$PERMISSIONS_BANNED_PATHS_JSON" \
    --slurpfile source_files "$PERMISSIONS_SOURCE_FILES_JSON" \
    --slurpfile package_files "$PERMISSIONS_PACKAGE_FILES_JSON" \
    '{banned_runtime_paths:$runtime_paths[0],code_source_files:$source_files[0],product_runtime_files:$package_files[0],fixture_exception_exact:true}' \
    >"$EVIDENCE_DIR/source-inventory.json" || return 70
}

permissions_check_secrets() {
  PERMISSIONS_SECRET_TARGETS="$RUN_TMP/permission-secret-targets.txt"
  : >"$PERMISSIONS_SECRET_TARGETS" || return 70
  for PERMISSIONS_SECRET_TARGET in "$SOURCE_ROOT/output" "$SOURCE_ROOT/docs/analysis" "$SOURCE_ROOT/.omo/evidence"; do
    test -d "$PERMISSIONS_SECRET_TARGET" && printf '%s\n' "$PERMISSIONS_SECRET_TARGET" \
      >>"$PERMISSIONS_SECRET_TARGETS"
  done

  PERMISSIONS_SECRET_HITS="$RUN_TMP/permission-secret-hits.txt"
  PERMISSIONS_CANARY_HITS="$RUN_TMP/permission-canary-hits.txt"
  : >"$PERMISSIONS_SECRET_HITS" || return 70
  : >"$PERMISSIONS_CANARY_HITS" || return 70
  while IFS= read -r PERMISSIONS_SECRET_TARGET; do
    rg -l --hidden --no-config \
      'AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}' \
      "$PERMISSIONS_SECRET_TARGET" >>"$PERMISSIONS_SECRET_HITS" 2>/dev/null
    PERMISSIONS_SCAN_RC=$?
    case "$PERMISSIONS_SCAN_RC" in 0|1) ;; *) return 70 ;; esac
    rg -l --hidden --no-config --fixed-strings \
      'FAKE_SENSAI_SECRET_CANARY_7B4C2A1E_NOT_A_CREDENTIAL' \
      "$PERMISSIONS_SECRET_TARGET" >>"$PERMISSIONS_CANARY_HITS" 2>/dev/null
    PERMISSIONS_SCAN_RC=$?
    case "$PERMISSIONS_SCAN_RC" in 0|1) ;; *) return 70 ;; esac
  done <"$PERMISSIONS_SECRET_TARGETS"

  LC_ALL=C sort -u "$PERMISSIONS_SECRET_HITS" -o "$PERMISSIONS_SECRET_HITS" || return 70
  LC_ALL=C sort -u "$PERMISSIONS_CANARY_HITS" -o "$PERMISSIONS_CANARY_HITS" || return 70
  if test ! -s "$PERMISSIONS_SECRET_HITS" && test ! -s "$PERMISSIONS_CANARY_HITS" && \
     test -f "$SOURCE_ROOT/fixtures/inputs/secrets/fake-secret.txt"; then
    assert_record permissions.secret_scan 0 'artifact와 evidence에 실제 secret 패턴 및 fixture canary 전파가 없음' || true
  else
    assert_record permissions.secret_scan 1 'artifact 또는 evidence에서 secret 패턴이나 fixture canary 전파를 찾음' || true
  fi
  PERMISSIONS_SECRET_HITS_JSON="$RUN_TMP/permission-secret-hits.json"
  PERMISSIONS_CANARY_HITS_JSON="$RUN_TMP/permission-canary-hits.json"
  jq -Rsc 'split("\n") | map(select(length > 0))' "$PERMISSIONS_SECRET_HITS" \
    >"$PERMISSIONS_SECRET_HITS_JSON" || return 70
  jq -Rsc 'split("\n") | map(select(length > 0))' "$PERMISSIONS_CANARY_HITS" \
    >"$PERMISSIONS_CANARY_HITS_JSON" || return 70
  jq -n \
    --slurpfile secret_hits "$PERMISSIONS_SECRET_HITS_JSON" \
    --slurpfile canary_hits "$PERMISSIONS_CANARY_HITS_JSON" \
    '{secret_hits:$secret_hits[0],fixture_canary_hits:$canary_hits[0],fixture_source_present:true}' \
    >"$EVIDENCE_DIR/secret-scan.json" || return 70
}

permissions_write_hashes() {
  PERMISSIONS_HASH_LINES="$RUN_TMP/permission-hashes.tsv"
  : >"$PERMISSIONS_HASH_LINES" || return 70
  for PERMISSIONS_HASH_PATH in \
    output/AGENTS.md output/opencode.json \
    output/agents/sensai-analysis-lead.md output/agents/sensai-evidence-peer.md \
    tests/cases/permissions.sh tests/cases/permissions-matcher.sh \
    tests/cases/permissions-projection.sh tests/cases/permissions-codegraph.sh \
    tests/cases/permissions-repository.sh tests/test.sh; do
    tooling_sha256_file "$SOURCE_ROOT/$PERMISSIONS_HASH_PATH" || return 70
    printf '%s\t%s\n' "$PERMISSIONS_HASH_PATH" "$TOOLING_SHA256" \
      >>"$PERMISSIONS_HASH_LINES" || return 70
  done
  jq -Rn '[inputs | split("\t") | {path:.[0],sha256:.[1]}]' \
    <"$PERMISSIONS_HASH_LINES" >"$EVIDENCE_DIR/current-hashes.json" || return 70
}

permissions_clone_source() {
  PERMISSIONS_CLONE_ROOT=$1
  mkdir -p "$PERMISSIONS_CLONE_ROOT/output/agents" \
    "$PERMISSIONS_CLONE_ROOT/tests/contracts" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$PERMISSIONS_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$PERMISSIONS_CLONE_ROOT/" || return 70
  cp -R "$SOURCE_ROOT/output/skills" "$PERMISSIONS_CLONE_ROOT/output/" || return 70
  cp "$SOURCE_ROOT/output/AGENTS.md" "$SOURCE_ROOT/output/opencode.json" \
    "$SOURCE_ROOT/output/toolchain.lock.json" "$PERMISSIONS_CLONE_ROOT/output/" || return 70
  cp "$SOURCE_ROOT/output/agents/sensai-analysis-lead.md" \
    "$SOURCE_ROOT/output/agents/sensai-evidence-peer.md" \
    "$PERMISSIONS_CLONE_ROOT/output/agents/" || return 70
}
