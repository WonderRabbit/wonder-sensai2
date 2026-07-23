#!/bin/sh

catalog_write_expected() {
  CATALOG_KIND=$1
  CATALOG_DEST=$2
  case "$CATALOG_KIND" in
    agents) printf '%s\n' agents/sensai-analysis-lead.md agents/sensai-evidence-peer.md ;;
    commands) printf '%s\n' \
      commands/sensai/analyze-business.md commands/sensai/analyze.md \
      commands/sensai/change-design.md commands/sensai/deliver.md \
      commands/sensai/document-asis.md commands/sensai/resume.md \
      commands/sensai/run.md commands/sensai/status.md commands/sensai/verify.md ;;
    skills) printf '%s\n' \
      skills/sensai-business-trace/SKILL.md skills/sensai-change-design/SKILL.md \
      skills/sensai-checklist/SKILL.md skills/sensai-convention-extract/SKILL.md \
      skills/sensai-dataflow-chart/SKILL.md skills/sensai-evidence-first/SKILL.md \
      skills/sensai-mermaid-sequence/SKILL.md skills/sensai-react-trace/SKILL.md \
      skills/sensai-requirement-analyze/SKILL.md skills/sensai-spec-evidence/SKILL.md \
      skills/sensai-stack-discovery/SKILL.md skills/sensai-test-scenario/SKILL.md \
      skills/sensai-ui-definition/SKILL.md skills/sensai-user-story/SKILL.md \
      skills/sensai-vertx-trace/SKILL.md ;;
    schemas) printf '%s\n' schemas/progress.schema.json schemas/trace.schema.json ;;
    recipes) printf '%s\n' recipes/glossary.jq recipes/migrate-trace-v1-to-v2.jq \
      recipes/progress.jq recipes/provenance.jq recipes/trace.jq ;;
    *) return 70 ;;
  esac >"$CATALOG_DEST" || return 70
}

catalog_path_chain_is_physical() {
  CATALOG_CHAIN_TARGET=$1
  CATALOG_CHAIN_LEAF_KIND=$2
  CATALOG_CHAIN_REASON=''
  case "$CATALOG_CHAIN_TARGET" in
    "$SOURCE_ROOT"/*) CATALOG_CHAIN_RELATIVE=${CATALOG_CHAIN_TARGET#"$SOURCE_ROOT"/} ;;
    *) CATALOG_CHAIN_REASON=OUTSIDE_SOURCE_ROOT; return 1 ;;
  esac
  if ! test -d "$SOURCE_ROOT" || test -L "$SOURCE_ROOT"; then
    CATALOG_CHAIN_REASON=SOURCE_ROOT_NOT_PHYSICAL_DIRECTORY
    return 1
  fi
  CATALOG_CHAIN_CANONICAL=$(CDPATH= cd -- "$SOURCE_ROOT" 2>/dev/null && pwd -P) || {
    CATALOG_CHAIN_REASON=SOURCE_ROOT_CANONICALIZATION_FAILED
    return 1
  }
  if test "$CATALOG_CHAIN_CANONICAL" != "$SOURCE_ROOT"; then
    CATALOG_CHAIN_REASON=SOURCE_ROOT_CANONICAL_MISMATCH
    return 1
  fi

  CATALOG_CHAIN_OLD_IFS=$IFS
  IFS=/
  set -f
  set -- $CATALOG_CHAIN_RELATIVE
  set +f
  IFS=$CATALOG_CHAIN_OLD_IFS
  CATALOG_CHAIN_CURRENT=$SOURCE_ROOT
  while test "$#" -gt 0; do
    CATALOG_CHAIN_COMPONENT=$1
    shift
    case "$CATALOG_CHAIN_COMPONENT" in
      ''|.|..) CATALOG_CHAIN_REASON=INVALID_COMPONENT; return 1 ;;
    esac
    CATALOG_CHAIN_CURRENT="$CATALOG_CHAIN_CURRENT/$CATALOG_CHAIN_COMPONENT"
    if test -L "$CATALOG_CHAIN_CURRENT"; then
      CATALOG_CHAIN_REASON="SYMLINK_COMPONENT:$CATALOG_CHAIN_CURRENT"
      return 1
    fi
    if test "$#" -gt 0; then
      if ! test -d "$CATALOG_CHAIN_CURRENT"; then
        CATALOG_CHAIN_REASON="NON_DIRECTORY_ANCESTOR:$CATALOG_CHAIN_CURRENT"
        return 1
      fi
      CATALOG_CHAIN_CANONICAL=$(CDPATH= cd -- "$CATALOG_CHAIN_CURRENT" 2>/dev/null && pwd -P) || {
        CATALOG_CHAIN_REASON="ANCESTOR_CANONICALIZATION_FAILED:$CATALOG_CHAIN_CURRENT"
        return 1
      }
      case "$CATALOG_CHAIN_CANONICAL" in
        "$SOURCE_ROOT"/*) ;;
        *) CATALOG_CHAIN_REASON="CANONICAL_ESCAPE:$CATALOG_CHAIN_CURRENT"; return 1 ;;
      esac
      if test "$CATALOG_CHAIN_CANONICAL" != "$CATALOG_CHAIN_CURRENT"; then
        CATALOG_CHAIN_REASON="ANCESTOR_CANONICAL_MISMATCH:$CATALOG_CHAIN_CURRENT"
        return 1
      fi
    else
      case "$CATALOG_CHAIN_LEAF_KIND" in
        file) test -f "$CATALOG_CHAIN_CURRENT" || { CATALOG_CHAIN_REASON="NON_REGULAR_LEAF:$CATALOG_CHAIN_CURRENT"; return 1; } ;;
        dir) test -d "$CATALOG_CHAIN_CURRENT" || { CATALOG_CHAIN_REASON="NON_DIRECTORY_LEAF:$CATALOG_CHAIN_CURRENT"; return 1; } ;;
        *) return 70 ;;
      esac
    fi
  done
  return 0
}

catalog_check_physical_trees() {
  CATALOG_CONTRACT_TREE_OK=1
  for CATALOG_CONTRACT_LEAF in agents.txt commands.txt manifest.txt recipes.txt root-agents.sha256.txt schemas.txt skills.txt; do
    if ! catalog_path_chain_is_physical "$SOURCE_ROOT/tests/contracts/$CATALOG_CONTRACT_LEAF" file; then
      test "$?" -ne 70 || return 70
      CATALOG_CONTRACT_TREE_OK=0
      break
    fi
  done
  if test "$CATALOG_CONTRACT_TREE_OK" -eq 1; then
    assert_record catalog.contracts_physical_tree 0 'tests/contracts and every contract leaf have physical non-symlink components' || true
  else
    assert_record catalog.contracts_physical_tree 1 "reason=$CATALOG_CHAIN_REASON" || true
  fi

  CATALOG_OUTPUT_TREE_OK=1
  for CATALOG_OUTPUT_LEAF in AGENTS.md opencode.json toolchain.lock.json; do
    if ! catalog_path_chain_is_physical "$SOURCE_ROOT/output/$CATALOG_OUTPUT_LEAF" file; then
      test "$?" -ne 70 || return 70
      CATALOG_OUTPUT_TREE_OK=0
      break
    fi
  done
  if test "$CATALOG_OUTPUT_TREE_OK" -eq 1; then
    assert_record catalog.output_physical_tree 0 'output config leaves have physical non-symlink components' || true
  else
    assert_record catalog.output_physical_tree 1 "reason=$CATALOG_CHAIN_REASON" || true
  fi
}

catalog_assert_contract() {
  CATALOG_KIND=$1
  CATALOG_FILE="$SOURCE_ROOT/tests/contracts/$CATALOG_KIND.txt"
  CATALOG_EXPECTED="$RUN_TMP/catalog-$CATALOG_KIND-expected.txt"
  CATALOG_SORTED="$RUN_TMP/catalog-$CATALOG_KIND-sorted.txt"
  assert_file "catalog.${CATALOG_KIND}_contract" "$CATALOG_FILE" || true
  if ! test -f "$CATALOG_FILE" || test -L "$CATALOG_FILE"; then
    assert_record "catalog.${CATALOG_KIND}_regular" 1 'contract missing or symlink' || true
    return 0
  fi
  assert_record "catalog.${CATALOG_KIND}_regular" 0 'regular contract file' || true
  LC_ALL=C sort "$CATALOG_FILE" >"$CATALOG_SORTED" || return 70
  if cmp -s "$CATALOG_FILE" "$CATALOG_SORTED" && awk 'NF==0 || seen[$0]++ {bad=1} END {exit bad+0}' "$CATALOG_FILE"; then
    assert_record "catalog.${CATALOG_KIND}_sorted_unique" 0 'sorted unique nonempty catalog' || true
  else
    assert_record "catalog.${CATALOG_KIND}_sorted_unique" 1 'catalog is unsorted, duplicate, or empty' || true
  fi
  if awk '$0=="" || $0~/^\// || $0~/(^|\/)\.\.?($|\/)/ || $0~/[[:cntrl:]]/ {bad=1} END {exit bad+0}' "$CATALOG_FILE"; then
    assert_record "catalog.${CATALOG_KIND}_safe_paths" 0 'safe normalized output-relative paths' || true
  else
    assert_record "catalog.${CATALOG_KIND}_safe_paths" 1 'absolute, dot, parent, empty, or control path' || true
  fi
  catalog_write_expected "$CATALOG_KIND" "$CATALOG_EXPECTED" || return 70
  if cmp -s "$CATALOG_EXPECTED" "$CATALOG_FILE"; then
    assert_record "catalog.${CATALOG_KIND}_exact" 0 'literal exact-set matches oracle' || true
  else
    assert_record "catalog.${CATALOG_KIND}_exact" 1 'literal target missing, extra, wrong-root, or reordered' || true
  fi
}

catalog_check_manifest() {
  CATALOG_MANIFEST="$SOURCE_ROOT/tests/contracts/manifest.txt"
  CATALOG_MANIFEST_EXPECTED="$RUN_TMP/catalog-manifest-expected.txt"
  CATALOG_MANIFEST_SORTED="$RUN_TMP/catalog-manifest-sorted.txt"
  assert_file catalog.manifest_contract "$CATALOG_MANIFEST" || true
  if ! test -f "$CATALOG_MANIFEST" || test -L "$CATALOG_MANIFEST"; then
    assert_record catalog.manifest_regular 1 'manifest contract missing or symlink' || true
    return 0
  fi
  assert_record catalog.manifest_regular 0 'regular manifest target contract' || true
  LC_ALL=C sort "$CATALOG_MANIFEST" >"$CATALOG_MANIFEST_SORTED" || return 70
  if cmp -s "$CATALOG_MANIFEST" "$CATALOG_MANIFEST_SORTED" && awk 'NF==0 || seen[$0]++ {bad=1} END {exit bad+0}' "$CATALOG_MANIFEST"; then
    assert_record catalog.manifest_sorted_unique 0 'manifest sorted unique' || true
  else
    assert_record catalog.manifest_sorted_unique 1 'manifest unsorted, duplicate, or empty' || true
  fi
  if awk '$0=="" || $0~/^\// || $0~/(^|\/)\.\.?($|\/)/ || $0~/[[:cntrl:]]/ {bad=1} END {exit bad+0}' "$CATALOG_MANIFEST"; then
    assert_record catalog.manifest_safe_paths 0 'safe normalized output-relative manifest paths' || true
  else
    assert_record catalog.manifest_safe_paths 1 'unsafe manifest path' || true
  fi
  {
    printf '%s\n' AGENTS.md opencode.json toolchain.lock.json
    for CATALOG_MANIFEST_KIND in agents commands skills schemas recipes; do
      catalog_write_expected "$CATALOG_MANIFEST_KIND" "$RUN_TMP/catalog-manifest-$CATALOG_MANIFEST_KIND.txt" || exit 70
      sed -n 'p' "$RUN_TMP/catalog-manifest-$CATALOG_MANIFEST_KIND.txt"
    done
  } | LC_ALL=C sort >"$CATALOG_MANIFEST_EXPECTED" || return 70
  if cmp -s "$CATALOG_MANIFEST_EXPECTED" "$CATALOG_MANIFEST"; then
    assert_record catalog.manifest_union 0 'manifest equals core plus all literal catalogs' || true
  else
    assert_record catalog.manifest_union 1 'manifest/catalog union drift' || true
  fi
  assert_eq catalog.manifest_count 36 "$(wc -l <"$CATALOG_MANIFEST" | tr -d ' ')" || true
  if awk '
      $0 ~ /^(bin|fixtures|tests|docs|manifest\.txt)(\/|$)/ {bad=1}
      END {exit bad ? 0 : 1}
    ' "$CATALOG_MANIFEST"; then
    assert_record catalog.manifest_repo_separation 1 'repository-side asset included in runtime manifest' || true
  else
    CATALOG_REPO_RC=$?
    case "$CATALOG_REPO_RC" in
      1) assert_record catalog.manifest_repo_separation 0 'repository-side assets excluded' || true ;;
      *) return 70 ;;
    esac
  fi
}

catalog_check_topology() {
  if test "$CATALOG_OUTPUT_TREE_OK" -eq 1 && test -f "$SOURCE_ROOT/output/AGENTS.md" && ! test -L "$SOURCE_ROOT/output/AGENTS.md"; then
    assert_record catalog.output_agents 0 'output/AGENTS.md present and regular' || true
  else
    assert_record catalog.output_agents 1 'output/AGENTS.md missing or symlink' || true
  fi
  if test "$CATALOG_OUTPUT_TREE_OK" -eq 1 && test -f "$SOURCE_ROOT/output/opencode.json" && ! test -L "$SOURCE_ROOT/output/opencode.json"; then
    assert_record catalog.output_config 0 'output/opencode.json present and regular' || true
  else
    assert_record catalog.output_config 1 'output/opencode.json missing or symlink' || true
  fi
  if test "$CATALOG_OUTPUT_TREE_OK" -eq 1 && test -f "$SOURCE_ROOT/output/toolchain.lock.json" && ! test -L "$SOURCE_ROOT/output/toolchain.lock.json"; then
    assert_record catalog.output_toolchain 0 'output/toolchain.lock.json present and regular' || true
  else
    assert_record catalog.output_toolchain 1 'output/toolchain.lock.json missing or symlink' || true
  fi
  if test -e "$SOURCE_ROOT/opencode.json"; then
    assert_record catalog.no_root_config 1 'root opencode.json duplicate exists' || true
  else
    assert_record catalog.no_root_config 0 'root opencode.json absent' || true
  fi
  CATALOG_ROOT_RUNTIME=''
  for CATALOG_ROOT_DIR in agents commands skills schemas recipes; do
    test ! -e "$SOURCE_ROOT/$CATALOG_ROOT_DIR" || CATALOG_ROOT_RUNTIME="$CATALOG_ROOT_RUNTIME $CATALOG_ROOT_DIR"
  done
  if test -z "$CATALOG_ROOT_RUNTIME"; then
    assert_record catalog.no_root_runtime_dirs 0 'no root runtime directories' || true
  else
    assert_record catalog.no_root_runtime_dirs 1 "unexpected=$CATALOG_ROOT_RUNTIME" || true
  fi
  if test -e "$SOURCE_ROOT/.opencode"; then
    assert_record catalog.no_dot_opencode 1 '.opencode duplicate exists' || true
  else
    assert_record catalog.no_dot_opencode 0 '.opencode absent' || true
  fi
  if test "$CATALOG_OUTPUT_TREE_OK" -eq 1 && test -f "$SOURCE_ROOT/output/AGENTS.md"; then
    if rg -q --no-config '자동으로[[:space:]]+로드된다|항상[[:space:]]+로드된다|implicit[[:space:]]+load[[:space:]]+guaranteed' "$SOURCE_ROOT/output/AGENTS.md"; then
      assert_record catalog.runtime_agents_no_implicit_claim 1 'implicit auto-load claim found' || true
    else
      CATALOG_IMPLICIT_RC=$?
      case "$CATALOG_IMPLICIT_RC" in
        1) assert_record catalog.runtime_agents_no_implicit_claim 0 'no implicit auto-load claim' || true ;;
        *) return 70 ;;
      esac
    fi
  else
    assert_record catalog.runtime_agents_no_implicit_claim 0 'implicit-load scan skipped because missing-file assertion already failed' || true
  fi
  if test "$CATALOG_OUTPUT_TREE_OK" -eq 1 && test "$CATALOG_CONTRACT_TREE_OK" -eq 1; then
    CATALOG_EXISTING_OUTPUT="$RUN_TMP/catalog-existing-output.txt"
    find "$SOURCE_ROOT/output" -mindepth 1 ! -type d -print | sed "s#^$SOURCE_ROOT/output/##" | LC_ALL=C sort >"$CATALOG_EXISTING_OUTPUT" || return 70
    if awk 'NR==FNR {allowed[$0]=1; next} !allowed[$0] {bad=1} END {exit bad+0}' "$SOURCE_ROOT/tests/contracts/manifest.txt" "$CATALOG_EXISTING_OUTPUT"; then
      assert_record catalog.output_existing_managed 0 'every current output leaf is manifest-declared' || true
    else
      assert_record catalog.output_existing_managed 1 'unmanaged current output leaf' || true
    fi
  else
    assert_record catalog.output_existing_managed 0 'managed-leaf scan skipped after physical-tree failure' || true
  fi
}

catalog_check_root_agents_hash() {
  CATALOG_HASH_FILE="$SOURCE_ROOT/tests/contracts/root-agents.sha256.txt"
  assert_file catalog.root_agents_hash_contract "$CATALOG_HASH_FILE" || true
  if ! test -f "$CATALOG_HASH_FILE" || test -L "$CATALOG_HASH_FILE"; then
    assert_record catalog.root_agents_hash_format 1 'hash contract missing or symlink' || true
    return 0
  fi
  if awk 'NR!=1 || $0 !~ /^[0-9a-f]{64}  AGENTS\.md$/ {bad=1} END {exit bad+0}' "$CATALOG_HASH_FILE"; then
    assert_record catalog.root_agents_hash_format 0 'strict one-line root AGENTS hash contract' || true
  else
    assert_record catalog.root_agents_hash_format 1 'invalid root AGENTS hash grammar' || true
  fi
  CATALOG_EXPECTED_HASH=$(awk '{print $1}' "$CATALOG_HASH_FILE") || return 70
  tooling_sha256_file "$SOURCE_ROOT/AGENTS.md" || return 70
  assert_eq catalog.root_agents_hash "$CATALOG_EXPECTED_HASH" "$TOOLING_SHA256" || true
}

catalog_check_output_language() {
  if test "$CATALOG_OUTPUT_TREE_OK" -ne 1; then
    assert_record catalog.output_human_language 0 'language scan skipped after physical-tree failure' || true
    return 0
  fi
  CATALOG_LANGUAGE_OK=1
  CATALOG_LANGUAGE_REPORT="$RUN_TMP/catalog-output-language.txt"
  : >"$CATALOG_LANGUAGE_REPORT" || return 70
  while IFS= read -r CATALOG_LANGUAGE_MD; do
    test -n "$CATALOG_LANGUAGE_MD" || continue
    perl -Mstrict -Mwarnings -CSDA -e '
      use utf8;
      sub has_english_natural_text {
        my ($text) = @_;
        $text =~ s/`[^`]*`//g;
        $text =~ s{https?://\S+}{}g;
        $text =~ s/\b(?:OpenCode|macOS|Windows|CLI)\b//g;
        $text =~ s/\b(?:AS-IS|TO-BE)\b//g;
        my @words = ($text =~ /[A-Za-z]+(?:[\x27-][A-Za-z]+)*/g);
        return 0 unless @words;
        return 1 if $text !~ /[가-힣]/;
        return @words >= 2 ? 1 : 0;
      }
      my $fence = 0;
      my $frontmatter = 0;
      my $first_line = 1;
      my $human_block_indent = -1;
      while (my $line = <>) {
        if ($first_line && $line =~ /^\s*---\s*$/) {
          $frontmatter = 1;
          $first_line = 0;
          next;
        }
        $first_line = 0;
        if ($frontmatter) {
          my ($indent_text) = ($line =~ /^(\s*)/);
          my $indent = length($indent_text // q{});
          if ($human_block_indent >= 0) {
            if ($line =~ /^\s*$/) { next; }
            if ($indent > $human_block_indent) {
              print $. . q{:} . $line if has_english_natural_text($line);
              next;
            }
            $human_block_indent = -1;
          }
          if ($line =~ /^\s*---\s*$/) { $frontmatter = 0; next; }
          next if $line =~ /^\s*$/;
          if ($line =~ /^(\s*)(?:description|title|summary|label)\s*:\s*(.*?)\s*$/i) {
            my $field_indent = length($1);
            my $value = $2;
            if ($value =~ /^(?:[>|][+-]?)\s*(?:#.*)?$/) {
              $human_block_indent = $field_indent;
            } elsif (has_english_natural_text($value)) {
              print $. . q{:} . $line;
            }
          }
          next;
        }
        if ($line =~ /^\s*```/) { $fence = !$fence; next; }
        next if $fence || $line =~ /^\s*$/;
        $line =~ s/^\s*(?:#{1,6}\s*|[-*+]\s+|\d+\.\s+|>\s*)//;
        next if $line =~ /^\s*(?:---+|\|?[\s:|-]+\|?)\s*$/;
        if (has_english_natural_text($line)) { print $. . q{:} . $line; }
      }
    ' "$CATALOG_LANGUAGE_MD" >>"$CATALOG_LANGUAGE_REPORT" || return 70
  done <<EOF
$(find "$SOURCE_ROOT/output" -type f -name '*.md' -print | LC_ALL=C sort)
EOF
  test ! -s "$CATALOG_LANGUAGE_REPORT" || CATALOG_LANGUAGE_OK=0
  jq -e 'all(.provider[]; (.name|type=="string" and test("[가-힣]")) and all(.models[]; .name|type=="string" and test("[가-힣]")))' "$SOURCE_ROOT/output/opencode.json" >/dev/null 2>&1 || CATALOG_LANGUAGE_OK=0
  if test "$CATALOG_LANGUAGE_OK" -eq 1; then
    assert_record catalog.output_human_language 0 'output human-readable prose and display labels are Korean' || true
  else
    assert_record catalog.output_human_language 1 'English human-facing prose or non-Korean display label found' || true
  fi
}

catalog_check_output_config_contract() {
  if test "$CATALOG_OUTPUT_TREE_OK" -ne 1; then
    assert_record catalog.output_config_exact 0 'config contract scan skipped after physical-tree failure' || true
    return 0
  fi
  if jq -e '
    (keys | sort) == (["$schema","agent","autoupdate","compaction","default_agent","instructions","model","permission","provider","share","small_model","subagent_depth","watcher"] | sort) and
    .["$schema"] == "https://opencode.ai/config.json" and
    (.provider | keys) == ["sensai-ollama"] and
    (.provider["sensai-ollama"] | keys | sort) == ["models","name","npm","options"] and
    .provider["sensai-ollama"].npm == "@ai-sdk/openai-compatible" and
    .provider["sensai-ollama"].name == "Sensai Ollama 근거 피어" and
    (.provider["sensai-ollama"].options | keys | sort) == ["apiKey","baseURL"] and
    .provider["sensai-ollama"].options.baseURL == "http://localhost:11434/v1" and
    .provider["sensai-ollama"].options.apiKey == "ollama" and
    (.provider["sensai-ollama"].models | keys) == ["qwen3.5:9b"] and
    (.provider["sensai-ollama"].models["qwen3.5:9b"] | keys) == ["name"] and
    .provider["sensai-ollama"].models["qwen3.5:9b"].name == "Qwen3.5-9B Ollama 로컬 모델" and
    .model == "zai/glm-5.2" and
    .small_model == "sensai-ollama/qwen3.5:9b" and
    .default_agent == "sensai-analysis-lead" and
    .share == "disabled" and
    .autoupdate == false and
    .instructions == ["AGENTS.md"] and
    .subagent_depth == 1 and
    .watcher.ignore == [".git/**",".omo/**","docs/analysis/missions/**/.sensai-tmp/**"] and
    .compaction == {"auto":true,"prune":true} and
    .agent == {"compaction":{"model":"zai/glm-5.2"}} and
    (.permission | type == "object")
  ' "$SOURCE_ROOT/output/opencode.json" >/dev/null 2>&1; then
    assert_record catalog.output_config_exact 0 'localhost provider, placeholder key, model IDs, and display names match the frozen contract' || true
  else
    assert_record catalog.output_config_exact 1 'runtime config differs from the exact non-secret localhost baseline' || true
  fi
  CATALOG_PLACEHOLDER_OK=1
  rg -q --no-config '`apiKey` 값 `ollama`.*비밀 아닌 고정 자리표시자.*실제 자격 증명이 아니다' "$SOURCE_ROOT/output/AGENTS.md" || CATALOG_PLACEHOLDER_OK=0
  rg -q --no-config '`apiKey`는 `ollama`로 고정.*비밀 아닌 자리표시자.*실제 자격 증명이 아니다' "$SOURCE_ROOT/docs/harness/runtime-contract.md" || CATALOG_PLACEHOLDER_OK=0
  if test "$CATALOG_PLACEHOLDER_OK" -eq 1; then
    assert_record catalog.ollama_placeholder_contract 0 'runtime and source contracts classify the localhost key as a fixed non-secret placeholder' || true
  else
    assert_record catalog.ollama_placeholder_contract 1 'localhost placeholder contract missing or ambiguous' || true
  fi
}

catalog_check_docs_parity() {
  CATALOG_DOCS="$SOURCE_ROOT/README.md $SOURCE_ROOT/risk.md $SOURCE_ROOT/docs/PROD.md $SOURCE_ROOT/docs/r4-mapping.md"
  CATALOG_DOCS_OK=1
  for CATALOG_DOC in $CATALOG_DOCS "$SOURCE_ROOT"/docs/harness/*.md; do
    rg -q --no-config 'output/' "$CATALOG_DOC" || CATALOG_DOCS_OK=0
  done
  if test "$CATALOG_DOCS_OK" -eq 1; then
    assert_record catalog.docs_topology_parity 0 'source-owned docs name output topology' || true
  else
    assert_record catalog.docs_topology_parity 1 'source-owned doc lacks output topology' || true
  fi
  CATALOG_OBSOLETE_INPUTS="$SOURCE_ROOT/README.md $SOURCE_ROOT/risk.md $SOURCE_ROOT/docs"
  if rg -n --no-config '루트 payload|root payload|canonical 결정은 루트 단일 payload|저장소 루트의 `opencode\.json`' \
    $CATALOG_OBSOLETE_INPUTS >"$RUN_TMP/catalog-obsolete-topology.txt" 2>&1; then
    assert_record catalog.no_obsolete_root_payload_claim 1 'obsolete root runtime source claim found' || true
  else
    CATALOG_OBSOLETE_RC=$?
    case "$CATALOG_OBSOLETE_RC" in
      1) assert_record catalog.no_obsolete_root_payload_claim 0 'obsolete root source claims absent' || true ;;
      *) return 70 ;;
    esac
  fi
}

catalog_clone_source() {
  CATALOG_CLONE=$1
  mkdir -p "$CATALOG_CLONE/tests/contracts" "$CATALOG_CLONE/docs/harness" "$CATALOG_CLONE/output" "$CATALOG_CLONE/bin" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$SOURCE_ROOT/README.md" "$SOURCE_ROOT/risk.md" "$CATALOG_CLONE/" || return 70
  cp "$SOURCE_ROOT/docs/PROD.md" "$SOURCE_ROOT/docs/r4-mapping.md" "$CATALOG_CLONE/docs/" || return 70
  cp "$SOURCE_ROOT"/docs/harness/*.md "$CATALOG_CLONE/docs/harness/" || return 70
  cp "$SOURCE_ROOT"/tests/contracts/*.txt "$CATALOG_CLONE/tests/contracts/" || return 70
  cp "$SOURCE_ROOT/output/AGENTS.md" "$SOURCE_ROOT/output/opencode.json" \
    "$SOURCE_ROOT/output/toolchain.lock.json" "$CATALOG_CLONE/output/" || return 70
  cp "$SOURCE_ROOT/bin/sensai" "$CATALOG_CLONE/bin/sensai" || return 70
}

catalog_run_mutation() {
  CATALOG_MUTATION=$1
  CATALOG_EXPECTED_ID=$2
  CATALOG_MUTATION_ROOT=$3
  CATALOG_MUTATION_EVIDENCE="$EVIDENCE_DIR/adversarial-$CATALOG_MUTATION"
  set +e
  env SENSAI_TEST_CATALOG_INNER=1 SENSAI_TEST_SOURCE_ROOT="$CATALOG_MUTATION_ROOT" \
    "$TEST_RUNNER" catalog-oracle --evidence "$CATALOG_MUTATION_EVIDENCE" >"$RUN_TMP/catalog-$CATALOG_MUTATION.out" 2>&1
  CATALOG_MUTATION_RC=$?
  evidence_log_command "catalog-adversarial-$CATALOG_MUTATION" "$TEST_RUNNER catalog-oracle <isolated-$CATALOG_MUTATION>" "$CATALOG_MUTATION_RC"
  assert_eq "catalog.adversarial_${CATALOG_MUTATION}_exit" 1 "$CATALOG_MUTATION_RC" || true
  if test -f "$CATALOG_MUTATION_EVIDENCE/receipt.json"; then
    assert_jq "catalog.adversarial_${CATALOG_MUTATION}_semantic" ".result == \"ASSERTION_FAILURE\" and .exit == 1 and (.failed_assertion_ids | index(\"$CATALOG_EXPECTED_ID\")) != null" "$CATALOG_MUTATION_EVIDENCE/receipt.json" || true
  else
    assert_record "catalog.adversarial_${CATALOG_MUTATION}_receipt" 1 'missing nested receipt' || true
  fi
}

catalog_run_valid_control() {
  CATALOG_CONTROL=$1
  CATALOG_CONTROL_ROOT=$2
  CATALOG_CONTROL_EVIDENCE="$EVIDENCE_DIR/adversarial-$CATALOG_CONTROL"
  set +e
  env SENSAI_TEST_CATALOG_INNER=1 SENSAI_TEST_SOURCE_ROOT="$CATALOG_CONTROL_ROOT" \
    "$TEST_RUNNER" catalog-oracle --evidence "$CATALOG_CONTROL_EVIDENCE" >"$RUN_TMP/catalog-$CATALOG_CONTROL.out" 2>&1
  CATALOG_CONTROL_RC=$?
  evidence_log_command "catalog-control-$CATALOG_CONTROL" "$TEST_RUNNER catalog-oracle <isolated-$CATALOG_CONTROL>" "$CATALOG_CONTROL_RC"
  assert_eq "catalog.control_${CATALOG_CONTROL}_exit" 0 "$CATALOG_CONTROL_RC" || true
  if test -f "$CATALOG_CONTROL_EVIDENCE/receipt.json"; then
    assert_jq "catalog.control_${CATALOG_CONTROL}_semantic" '.result == "PASS" and .exit == 0 and .failed_assertion_count == 0' "$CATALOG_CONTROL_EVIDENCE/receipt.json" || true
  else
    assert_record "catalog.control_${CATALOG_CONTROL}_receipt" 1 'missing nested control receipt' || true
  fi
}

catalog_run_adversarial_matrix() {
  CATALOG_ADV="$RUN_TMP/catalog-adversarial"
  mkdir -p "$CATALOG_ADV" || return 70

  CATALOG_ROOT="$CATALOG_ADV/missing-agent"; catalog_clone_source "$CATALOG_ROOT" || return 70
  sed -n '2,$p' "$CATALOG_ROOT/tests/contracts/agents.txt" >"$CATALOG_ROOT/tests/contracts/agents.tmp" && mv "$CATALOG_ROOT/tests/contracts/agents.tmp" "$CATALOG_ROOT/tests/contracts/agents.txt" || return 70
  catalog_run_mutation missing_agent catalog.agents_exact "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/extra-skill"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '%s\n' skills/sensai-rogue/SKILL.md >>"$CATALOG_ROOT/tests/contracts/skills.txt" || return 70
  LC_ALL=C sort "$CATALOG_ROOT/tests/contracts/skills.txt" >"$CATALOG_ROOT/tests/contracts/skills.tmp" && mv "$CATALOG_ROOT/tests/contracts/skills.tmp" "$CATALOG_ROOT/tests/contracts/skills.txt" || return 70
  catalog_run_mutation extra_skill catalog.skills_exact "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/duplicate-command"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '%s\n' commands/sensai/verify.md >>"$CATALOG_ROOT/tests/contracts/commands.txt" || return 70
  catalog_run_mutation duplicate_command catalog.commands_sorted_unique "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/absolute"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '%s\n' /tmp/escape >>"$CATALOG_ROOT/tests/contracts/recipes.txt" || return 70
  catalog_run_mutation absolute catalog.recipes_safe_paths "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/parent"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '%s\n' ../escape >>"$CATALOG_ROOT/tests/contracts/schemas.txt" || return 70
  catalog_run_mutation parent catalog.schemas_safe_paths "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/normalized-duplicate"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '%s\n' skills/rogue/../sensai-checklist/SKILL.md >>"$CATALOG_ROOT/tests/contracts/skills.txt" || return 70
  catalog_run_mutation normalized_duplicate catalog.skills_safe_paths "$CATALOG_ROOT"

  for CATALOG_KIND in agents commands skills schemas recipes; do
    CATALOG_ROOT="$CATALOG_ADV/wrong-$CATALOG_KIND"; catalog_clone_source "$CATALOG_ROOT" || return 70
    sed '1s#^#output/#' "$CATALOG_ROOT/tests/contracts/$CATALOG_KIND.txt" >"$CATALOG_ROOT/tests/contracts/$CATALOG_KIND.tmp" && mv "$CATALOG_ROOT/tests/contracts/$CATALOG_KIND.tmp" "$CATALOG_ROOT/tests/contracts/$CATALOG_KIND.txt" || return 70
    catalog_run_mutation "wrong_$CATALOG_KIND" "catalog.${CATALOG_KIND}_exact" "$CATALOG_ROOT"
  done

  CATALOG_ROOT="$CATALOG_ADV/root-config"; catalog_clone_source "$CATALOG_ROOT" || return 70
  cp "$CATALOG_ROOT/output/opencode.json" "$CATALOG_ROOT/opencode.json" || return 70
  catalog_run_mutation root_config catalog.no_root_config "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/root-runtime"; catalog_clone_source "$CATALOG_ROOT" || return 70
  mkdir "$CATALOG_ROOT/agents" || return 70
  catalog_run_mutation root_runtime catalog.no_root_runtime_dirs "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/missing-output-agents"; catalog_clone_source "$CATALOG_ROOT" || return 70
  rm "$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation missing_output_agents catalog.output_agents "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/missing-output-config"; catalog_clone_source "$CATALOG_ROOT" || return 70
  rm "$CATALOG_ROOT/output/opencode.json" || return 70
  catalog_run_mutation missing_output_config catalog.output_config "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/implicit-load"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '\n이 파일은 항상 로드된다.\n' >>"$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation implicit_load catalog.runtime_agents_no_implicit_claim "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-human-text"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '\nThis human-facing description must be rejected.\n' >>"$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_human_text catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-one-word"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '\nRun.\n' >>"$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_one_word catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-two-words"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '\nUse tools.\n' >>"$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_two_words catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-short-sentence"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '\nRun now.\n' >>"$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_short_sentence catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-heading"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '\n## Run now\n' >>"$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_heading catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-list"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '\n- Use tools.\n' >>"$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_list catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-frontmatter-description"; catalog_clone_source "$CATALOG_ROOT" || return 70
  {
    printf '%s\n' '---' 'name: sensai-runtime-contract' 'description: Run now.' '---'
    sed -n 'p' "$CATALOG_ROOT/output/AGENTS.md"
  } >"$CATALOG_ROOT/output/AGENTS.md.tmp" && mv "$CATALOG_ROOT/output/AGENTS.md.tmp" "$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_frontmatter_description catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-block-folded"; catalog_clone_source "$CATALOG_ROOT" || return 70
  {
    printf '%s\n' '---' 'name: sensai-runtime-contract' 'description: >-' '  Run now.' '---'
    sed -n 'p' "$CATALOG_ROOT/output/AGENTS.md"
  } >"$CATALOG_ROOT/output/AGENTS.md.tmp" && mv "$CATALOG_ROOT/output/AGENTS.md.tmp" "$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_block_folded catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-block-literal"; catalog_clone_source "$CATALOG_ROOT" || return 70
  {
    printf '%s\n' '---' 'name: sensai-runtime-contract' 'description: |' '  Run now.' '---'
    sed -n 'p' "$CATALOG_ROOT/output/AGENTS.md"
  } >"$CATALOG_ROOT/output/AGENTS.md.tmp" && mv "$CATALOG_ROOT/output/AGENTS.md.tmp" "$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_block_literal catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-mixed-body"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '\n한국어 설명. Run now.\n' >>"$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_mixed_body catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-mixed-frontmatter"; catalog_clone_source "$CATALOG_ROOT" || return 70
  {
    printf '%s\n' '---' 'name: sensai-runtime-contract' 'description: 한국어 Run now.' '---'
    sed -n 'p' "$CATALOG_ROOT/output/AGENTS.md"
  } >"$CATALOG_ROOT/output/AGENTS.md.tmp" && mv "$CATALOG_ROOT/output/AGENTS.md.tmp" "$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_mutation english_mixed_frontmatter catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/english-provider-label"; catalog_clone_source "$CATALOG_ROOT" || return 70
  jq '.provider["sensai-ollama"].name = "Run now."' "$CATALOG_ROOT/output/opencode.json" >"$CATALOG_ROOT/output/opencode.json.tmp" && mv "$CATALOG_ROOT/output/opencode.json.tmp" "$CATALOG_ROOT/output/opencode.json" || return 70
  catalog_run_mutation english_provider_label catalog.output_human_language "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/machine-token-control"; catalog_clone_source "$CATALOG_ROOT" || return 70
  {
    printf '%s\n' '---' 'name: sensai-runtime-contract' 'agent: sensai-analysis-lead' 'model: zai/glm-5.2' 'permission:' '  edit: deny' 'description: >-' '  한국어 OpenCode CLI 실행 계약입니다.' '---'
    sed -n 'p' "$CATALOG_ROOT/output/AGENTS.md"
    printf '%s\n' '' '한국어 설명과 `MODEL_ADMISSION_UNVERIFIED`, `output/AGENTS.md`, `jq -e`를 함께 둔다.' '`MODEL_ADMISSION_UNVERIFIED`' '`output/AGENTS.md`' '`jq -e`' '```json' '{"provider":"sensai-ollama","model":"qwen3.5:9b"}' '```'
  } >"$CATALOG_ROOT/output/AGENTS.md.tmp" && mv "$CATALOG_ROOT/output/AGENTS.md.tmp" "$CATALOG_ROOT/output/AGENTS.md" || return 70
  catalog_run_valid_control machine_token_control "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/contracts-ancestor-symlink"; catalog_clone_source "$CATALOG_ROOT" || return 70
  mv "$CATALOG_ROOT/tests/contracts" "$CATALOG_ROOT/tests/contracts.real" || return 70
  ln -s contracts.real "$CATALOG_ROOT/tests/contracts" || return 70
  catalog_run_mutation contracts_ancestor_symlink catalog.contracts_physical_tree "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/contracts-nondirectory-ancestor"; catalog_clone_source "$CATALOG_ROOT" || return 70
  mv "$CATALOG_ROOT/tests/contracts" "$CATALOG_ROOT/tests/contracts.real" || return 70
  printf '%s\n' 'not a directory' >"$CATALOG_ROOT/tests/contracts" || return 70
  catalog_run_mutation contracts_nondirectory_ancestor catalog.contracts_physical_tree "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/output-ancestor-symlink"; catalog_clone_source "$CATALOG_ROOT" || return 70
  mv "$CATALOG_ROOT/output" "$CATALOG_ROOT/output.real" || return 70
  ln -s output.real "$CATALOG_ROOT/output" || return 70
  catalog_run_mutation output_ancestor_symlink catalog.output_physical_tree "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/output-canonical-escape"; catalog_clone_source "$CATALOG_ROOT" || return 70
  mv "$CATALOG_ROOT/output" "$CATALOG_ADV/output-canonical-escape-target" || return 70
  ln -s ../output-canonical-escape-target "$CATALOG_ROOT/output" || return 70
  catalog_run_mutation output_canonical_escape catalog.output_physical_tree "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/config-api-key-drift"; catalog_clone_source "$CATALOG_ROOT" || return 70
  jq '.provider["sensai-ollama"].options.apiKey = "${OLLAMA_API_KEY}"' "$CATALOG_ROOT/output/opencode.json" >"$CATALOG_ROOT/output/opencode.json.tmp" && mv "$CATALOG_ROOT/output/opencode.json.tmp" "$CATALOG_ROOT/output/opencode.json" || return 70
  catalog_run_mutation config_api_key_drift catalog.output_config_exact "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/config-base-url-drift"; catalog_clone_source "$CATALOG_ROOT" || return 70
  jq '.provider["sensai-ollama"].options.baseURL = "https://remote.example/v1"' "$CATALOG_ROOT/output/opencode.json" >"$CATALOG_ROOT/output/opencode.json.tmp" && mv "$CATALOG_ROOT/output/opencode.json.tmp" "$CATALOG_ROOT/output/opencode.json" || return 70
  catalog_run_mutation config_base_url_drift catalog.output_config_exact "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/config-provider-drift"; catalog_clone_source "$CATALOG_ROOT" || return 70
  jq '.provider = {"remote-provider": .provider["sensai-ollama"]}' "$CATALOG_ROOT/output/opencode.json" >"$CATALOG_ROOT/output/opencode.json.tmp" && mv "$CATALOG_ROOT/output/opencode.json.tmp" "$CATALOG_ROOT/output/opencode.json" || return 70
  catalog_run_mutation config_provider_drift catalog.output_config_exact "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/repo-asset"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '%s\n' fixtures/CASES.json >>"$CATALOG_ROOT/tests/contracts/manifest.txt" || return 70
  LC_ALL=C sort -u "$CATALOG_ROOT/tests/contracts/manifest.txt" >"$CATALOG_ROOT/tests/contracts/manifest.tmp" && mv "$CATALOG_ROOT/tests/contracts/manifest.tmp" "$CATALOG_ROOT/tests/contracts/manifest.txt" || return 70
  catalog_run_mutation repo_asset catalog.manifest_repo_separation "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/cli-in-manifest"; catalog_clone_source "$CATALOG_ROOT" || return 70
  printf '%s\n' bin/sensai >>"$CATALOG_ROOT/tests/contracts/manifest.txt" || return 70
  LC_ALL=C sort -u "$CATALOG_ROOT/tests/contracts/manifest.txt" >"$CATALOG_ROOT/tests/contracts/manifest.tmp" && mv "$CATALOG_ROOT/tests/contracts/manifest.tmp" "$CATALOG_ROOT/tests/contracts/manifest.txt" || return 70
  catalog_run_mutation cli_in_manifest catalog.manifest_repo_separation "$CATALOG_ROOT"

  CATALOG_ROOT="$CATALOG_ADV/union-drift"; catalog_clone_source "$CATALOG_ROOT" || return 70
  sed '/^toolchain\.lock\.json$/d' "$CATALOG_ROOT/tests/contracts/manifest.txt" >"$CATALOG_ROOT/tests/contracts/manifest.tmp" && mv "$CATALOG_ROOT/tests/contracts/manifest.tmp" "$CATALOG_ROOT/tests/contracts/manifest.txt" || return 70
  catalog_run_mutation union_drift catalog.manifest_union "$CATALOG_ROOT"
}

case_catalog_oracle() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  catalog_check_physical_trees || return 70
  if test "$CATALOG_CONTRACT_TREE_OK" -eq 1; then
    for CATALOG_KIND in agents commands skills schemas recipes; do
      catalog_assert_contract "$CATALOG_KIND" || return 70
    done
    catalog_check_manifest || return 70
    catalog_check_root_agents_hash || return 70
  else
    assert_record catalog.contract_validation_skipped 0 'contract parsing skipped after physical-tree failure' || true
  fi
  catalog_check_topology || return 70
  catalog_check_output_language || return 70
  catalog_check_output_config_contract || return 70
  catalog_check_docs_parity || return 70
  if test "${SENSAI_TEST_CATALOG_INNER:-0}" != 1; then
    catalog_run_adversarial_matrix || return 70
  fi
}
