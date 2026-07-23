#!/bin/sh

DOCS_EXPECTED_AGENTS_SHA256=181488a68f11484c8a06b2c2e24d7ff942307961e395316dd350b73e2624e2a3

docs_assert_contains() {
  DOCS_ASSERT_ID=$1
  DOCS_ASSERT_PATTERN=$2
  DOCS_ASSERT_FILE=$3
  rg -q --no-config "$DOCS_ASSERT_PATTERN" "$DOCS_ASSERT_FILE"
  DOCS_ASSERT_RC=$?
  case "$DOCS_ASSERT_RC" in
    0) assert_record "$DOCS_ASSERT_ID" 0 "pattern_present file=${DOCS_ASSERT_FILE#"$SOURCE_ROOT"/}" || true ;;
    1) assert_record "$DOCS_ASSERT_ID" 1 "pattern_missing file=${DOCS_ASSERT_FILE#"$SOURCE_ROOT"/}" || true ;;
    *) return 70 ;;
  esac
}

docs_compare_exact() {
  DOCS_COMPARE_ID=$1
  DOCS_COMPARE_EXPECTED=$2
  DOCS_COMPARE_ACTUAL=$3
  DOCS_COMPARE_PASS_DETAIL=$4
  DOCS_COMPARE_FAIL_DETAIL=$5
  cmp -s "$DOCS_COMPARE_EXPECTED" "$DOCS_COMPARE_ACTUAL"
  DOCS_COMPARE_RC=$?
  case "$DOCS_COMPARE_RC" in
    0) assert_record "$DOCS_COMPARE_ID" 0 "$DOCS_COMPARE_PASS_DETAIL" || true ;;
    1) assert_record "$DOCS_COMPARE_ID" 1 "$DOCS_COMPARE_FAIL_DETAIL" || true ;;
    *) return 70 ;;
  esac
}

docs_assert_absent() {
  DOCS_ASSERT_ID=$1
  DOCS_ASSERT_PATTERN=$2
  shift 2
  if rg -n --no-config "$DOCS_ASSERT_PATTERN" "$@" >"$RUN_TMP/$DOCS_ASSERT_ID.out" 2>&1; then
    assert_record "$DOCS_ASSERT_ID" 1 "forbidden_pattern_found" || true
  else
    DOCS_ASSERT_RC=$?
    if test "$DOCS_ASSERT_RC" -eq 1; then
      assert_record "$DOCS_ASSERT_ID" 0 "forbidden_pattern_absent" || true
    else
      return 70
    fi
  fi
}

docs_check_local_links() {
  DOCS_LINK_FILES="$RUN_TMP/markdown-files.txt"
  DOCS_LINK_FILES_UNSORTED="$RUN_TMP/markdown-files-unsorted.txt"
  printf '%s\n' "$SOURCE_ROOT/README.md" "$SOURCE_ROOT/risk.md" >"$DOCS_LINK_FILES_UNSORTED" || return 70
  find "$SOURCE_ROOT/docs" -type f -name '*.md' -print >>"$DOCS_LINK_FILES_UNSORTED" || return 70
  LC_ALL=C sort -u "$DOCS_LINK_FILES_UNSORTED" >"$DOCS_LINK_FILES" || return 70

  DOCS_LINK_PARSER="$RUN_TMP/markdown-links.pl"
  cat >"$DOCS_LINK_PARSER" <<'PERL'
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;

my $root = shift @ARGV;
$root =~ s{/+$}{};

sub lexical_path {
    my ($path) = @_;
    my @out;
    for my $part (split m{/+}, $path) {
        next if $part eq q{} || $part eq q{.};
        if ($part eq q{..}) {
            pop @out if @out;
            next;
        }
        push @out, $part;
    }
    return q{/} . join q{/}, @out;
}

sub has_symlink_component {
    my ($path) = @_;
    my $relative = substr $path, length $root;
    $relative =~ s{^/}{};
    my $current = $root;
    for my $part (split m{/}, $relative) {
        next if $part eq q{};
        $current .= q{/} . $part;
        next unless lstat $current;
        return 1 if -l _;
    }
    return 0;
}

while (my $source = <STDIN>) {
    chomp $source;
    next unless length $source;
    open my $fh, q{<}, $source or exit 70;
    local $/;
    my $text = <$fh>;
    close $fh or exit 70;

    pos($text) = 0;
    while ($text =~ /\]\(/g) {
        my $index = pos $text;
        my $depth = 1;
        my $escaped = 0;
        my $token = q{};
        my $closed = 0;
        for (; $index < length $text; $index++) {
            my $char = substr $text, $index, 1;
            if ($escaped) {
                $token .= q{\\} . $char;
                $escaped = 0;
                next;
            }
            if ($char eq q{\\}) {
                $escaped = 1;
                next;
            }
            if ($char eq q{(}) {
                $depth++;
                $token .= $char;
                next;
            }
            if ($char eq q{)}) {
                $depth--;
                if ($depth == 0) {
                    $closed = 1;
                    pos($text) = $index + 1;
                    last;
                }
                $token .= $char;
                next;
            }
            $token .= $char;
        }
        next unless $closed;

        $token =~ s/^\s+|\s+$//g;
        $token = substr($token, 1, -1) if $token =~ /^<.*>$/s;
        $token =~ s/\\([\\!"#\$%&'()*+,\-.\/:;<=>?@\[\]^_`{|}~])/$1/g;
        next if $token =~ m{^(?:https?|mailto):}i || $token =~ /^#/;

        $token =~ s/#.*$//;
        next unless length $token;
        my $status = q{OK};
        my $absolute;
        if (File::Spec->file_name_is_absolute($token) || $token =~ m{^[A-Za-z]:[\\/]}) {
            $status = q{ABSOLUTE};
        } elsif ($token =~ /^file:/i) {
            $status = q{ABSOLUTE};
        } else {
            $absolute = lexical_path(File::Spec->rel2abs($token, dirname($source)));
            if (!($absolute eq $root || index($absolute, $root . q{/}) == 0)) {
                $status = q{OUTSIDE};
            } elsif (has_symlink_component($absolute)) {
                $status = q{SYMLINK};
            } elsif (!-f $absolute) {
                $status = q{NONREGULAR};
            }
        }
        print join("\t", $source, $status, $token), "\n";
    }
}
PERL

  perl -Mstrict -Mwarnings -MFile::Spec -MFile::Basename -e 'exit 0' || return 70
  DOCS_LINK_RESULTS="$RUN_TMP/local-link-results.txt"
  perl "$DOCS_LINK_PARSER" "$SOURCE_ROOT" <"$DOCS_LINK_FILES" >"$DOCS_LINK_RESULTS" || return 70

  DOCS_LINK_TOTAL=0
  DOCS_LINK_FAILED=0
  DOCS_LINK_TAB=$(printf '\t')
  while IFS="$DOCS_LINK_TAB" read -r DOCS_LINK_SOURCE DOCS_LINK_STATUS DOCS_LINK_TARGET; do
    test -n "$DOCS_LINK_SOURCE" || continue
    DOCS_LINK_TOTAL=$((DOCS_LINK_TOTAL + 1))
    if test "$DOCS_LINK_STATUS" = OK; then
      assert_record "docs.local_link_$DOCS_LINK_TOTAL" 0 "source=${DOCS_LINK_SOURCE#"$SOURCE_ROOT"/} target=$DOCS_LINK_TARGET" || true
    else
      DOCS_LINK_FAILED=$((DOCS_LINK_FAILED + 1))
      assert_record "docs.local_link_$DOCS_LINK_TOTAL" 1 "source=${DOCS_LINK_SOURCE#"$SOURCE_ROOT"/} status=$DOCS_LINK_STATUS target=$DOCS_LINK_TARGET" || true
    fi
  done <"$DOCS_LINK_RESULTS"
  if test "$DOCS_LINK_TOTAL" -gt 0 && test "$DOCS_LINK_FAILED" -eq 0; then
    assert_record docs.local_links 0 "checked=$DOCS_LINK_TOTAL" || true
  else
    assert_record docs.local_links 1 "checked=$DOCS_LINK_TOTAL failed=$DOCS_LINK_FAILED" || true
  fi
}

docs_check_command_catalog() {
  DOCS_COMMAND_EXPECTED="$RUN_TMP/command-expected.txt"
  cat >"$DOCS_COMMAND_EXPECTED" <<'EOF'
/sensai/analyze
/sensai/analyze-business
/sensai/change-design
/sensai/deliver
/sensai/document-asis
/sensai/resume
/sensai/run
/sensai/status
/sensai/verify
EOF
  DOCS_COMMAND_README="$RUN_TMP/command-readme.txt"
  docs_collect_rg_sorted_unique '/sensai/[a-z][a-z-]*' "$DOCS_COMMAND_README" "$SOURCE_ROOT/README.md" || return 70
  docs_compare_exact docs.command_readme_exact_set "$DOCS_COMMAND_EXPECTED" "$DOCS_COMMAND_README" \
    'README exact nine nested command names' 'README command catalog missing, extra, or stale' || return 70
}

docs_check_skill_catalog() {
  DOCS_SKILL_EXPECTED="$RUN_TMP/skill-expected.txt"
  DOCS_SKILL_SECTION="$RUN_TMP/skill-section.txt"
  DOCS_SKILL_README="$RUN_TMP/skill-readme.txt"
  cat >"$DOCS_SKILL_EXPECTED" <<'EOF'
sensai-business-trace
sensai-change-design
sensai-checklist
sensai-convention-extract
sensai-dataflow-chart
sensai-evidence-first
sensai-mermaid-sequence
sensai-react-trace
sensai-requirement-analyze
sensai-spec-evidence
sensai-stack-discovery
sensai-test-scenario
sensai-ui-definition
sensai-user-story
sensai-vertx-trace
EOF
  awk '/^## Skill catalog 목표/{inside=1; next} inside && /^## /{exit} inside{print}' "$SOURCE_ROOT/README.md" >"$DOCS_SKILL_SECTION" || return 70
  docs_collect_rg_sorted_unique 'sensai-[a-z][a-z-]*' "$DOCS_SKILL_README" "$DOCS_SKILL_SECTION" || return 70
  docs_compare_exact docs.skill_readme_exact_set "$DOCS_SKILL_EXPECTED" "$DOCS_SKILL_README" \
    'README exact fifteen skill names' 'README skill catalog missing, extra, or stale' || return 70
}

docs_collect_rg_sorted_unique() {
  DOCS_COLLECT_PATTERN=$1
  DOCS_COLLECT_OUTPUT=$2
  shift 2
  DOCS_COLLECT_RAW="$DOCS_COLLECT_OUTPUT.raw"
  rg -o --no-filename --no-config "$DOCS_COLLECT_PATTERN" "$@" >"$DOCS_COLLECT_RAW" 2>/dev/null
  DOCS_COLLECT_RC=$?
  case "$DOCS_COLLECT_RC" in
    0) LC_ALL=C sort -u "$DOCS_COLLECT_RAW" >"$DOCS_COLLECT_OUTPUT" || return 70 ;;
    1) : >"$DOCS_COLLECT_OUTPUT" || return 70 ;;
    *) return 70 ;;
  esac
}

docs_check_agent_catalog() {
  DOCS_AGENT_EXPECTED="$RUN_TMP/agent-expected.txt"
  DOCS_AGENT_README="$RUN_TMP/agent-readme.txt"
  DOCS_AGENT_CANONICAL="$RUN_TMP/agent-canonical.txt"
  cat >"$DOCS_AGENT_EXPECTED" <<'EOF'
sensai-analysis-lead
sensai-evidence-peer
EOF
  docs_collect_rg_sorted_unique 'sensai-(analysis-lead|evidence-peer)' "$DOCS_AGENT_README" "$SOURCE_ROOT/README.md" || return 70
  docs_collect_rg_sorted_unique 'sensai-(analysis-lead|evidence-peer)' "$DOCS_AGENT_CANONICAL" "$SOURCE_ROOT/docs/r4-mapping.md" || return 70
  docs_compare_exact docs.agent_readme_exact_set "$DOCS_AGENT_EXPECTED" "$DOCS_AGENT_README" \
    'README exact two agent names' 'README agent catalog missing, extra, or stale' || return 70
  docs_compare_exact docs.agent_canonical_exact_set "$DOCS_AGENT_EXPECTED" "$DOCS_AGENT_CANONICAL" \
    'source-owned mapping exact two agent names' 'source-owned agent catalog missing, extra, or stale' || return 70
}

docs_clone_contract_source() {
  DOCS_CLONE_ROOT=$1
  mkdir -p "$DOCS_CLONE_ROOT/docs/harness" || return 70
  for DOCS_CLONE_FILE in AGENTS.md README.md risk.md; do
    cp "$SOURCE_ROOT/$DOCS_CLONE_FILE" "$DOCS_CLONE_ROOT/$DOCS_CLONE_FILE" || return 70
  done
  cp "$SOURCE_ROOT/docs/PROD.md" "$DOCS_CLONE_ROOT/docs/PROD.md" || return 70
  cp "$SOURCE_ROOT/docs/PRD-bin-artifact-delivery.md" "$DOCS_CLONE_ROOT/docs/PRD-bin-artifact-delivery.md" || return 70
  cp "$SOURCE_ROOT/docs/PRD-go-cli-windows.md" "$DOCS_CLONE_ROOT/docs/PRD-go-cli-windows.md" || return 70
  cp "$SOURCE_ROOT/docs/codegraph-analysis-guide.md" "$DOCS_CLONE_ROOT/docs/codegraph-analysis-guide.md" || return 70
  cp "$SOURCE_ROOT/docs/r4-mapping.md" "$DOCS_CLONE_ROOT/docs/r4-mapping.md" || return 70
  for DOCS_CLONE_CONTRACT in "$SOURCE_ROOT"/docs/harness/*.md; do
    cp "$DOCS_CLONE_CONTRACT" "$DOCS_CLONE_ROOT/docs/harness/" || return 70
  done
}

docs_run_mutation() {
  DOCS_MUTATION_NAME=$1
  DOCS_MUTATION_EXPECTED_ID=$2
  DOCS_MUTATION_ROOT=$3
  DOCS_MUTATION_EVIDENCE="$EVIDENCE_DIR/adversarial-$DOCS_MUTATION_NAME"
  set +e
  env SENSAI_TEST_DOCS_INNER=1 SENSAI_TEST_SOURCE_ROOT="$DOCS_MUTATION_ROOT" "$TEST_RUNNER" docs --evidence "$DOCS_MUTATION_EVIDENCE" >"$RUN_TMP/adversarial-$DOCS_MUTATION_NAME.out" 2>&1
  DOCS_MUTATION_RC=$?
  evidence_log_command "docs-adversarial-$DOCS_MUTATION_NAME" "$TEST_RUNNER docs <isolated-$DOCS_MUTATION_NAME>" "$DOCS_MUTATION_RC"
  assert_eq "docs.adversarial_${DOCS_MUTATION_NAME}_exit" 1 "$DOCS_MUTATION_RC" || true
  if test -f "$DOCS_MUTATION_EVIDENCE/receipt.json"; then
    assert_jq "docs.adversarial_${DOCS_MUTATION_NAME}_semantic" ".result == \"ASSERTION_FAILURE\" and .exit == 1 and (.failed_assertion_ids | index(\"$DOCS_MUTATION_EXPECTED_ID\")) != null" "$DOCS_MUTATION_EVIDENCE/receipt.json" || true
  else
    assert_record "docs.adversarial_${DOCS_MUTATION_NAME}_receipt" 1 'missing nested semantic receipt' || true
  fi
}

docs_run_valid_mutation() {
  DOCS_VALID_NAME=$1
  DOCS_VALID_ROOT=$2
  DOCS_VALID_EVIDENCE="$EVIDENCE_DIR/adversarial-$DOCS_VALID_NAME"
  set +e
  env SENSAI_TEST_DOCS_INNER=1 SENSAI_TEST_SOURCE_ROOT="$DOCS_VALID_ROOT" "$TEST_RUNNER" docs --evidence "$DOCS_VALID_EVIDENCE" >"$RUN_TMP/adversarial-$DOCS_VALID_NAME.out" 2>&1
  DOCS_VALID_RC=$?
  evidence_log_command "docs-adversarial-$DOCS_VALID_NAME" "$TEST_RUNNER docs <isolated-$DOCS_VALID_NAME>" "$DOCS_VALID_RC"
  assert_eq "docs.adversarial_${DOCS_VALID_NAME}_exit" 0 "$DOCS_VALID_RC" || true
  if test -f "$DOCS_VALID_EVIDENCE/receipt.json"; then
    assert_jq "docs.adversarial_${DOCS_VALID_NAME}_pass" '.result == "PASS" and .exit == 0 and .failed_assertion_count == 0' "$DOCS_VALID_EVIDENCE/receipt.json" || true
  else
    assert_record "docs.adversarial_${DOCS_VALID_NAME}_receipt" 1 'missing nested PASS receipt' || true
  fi
}

docs_run_infra_wrapper() {
  DOCS_INFRA_NAME=$1
  DOCS_INFRA_TOOL=$2
  DOCS_INFRA_ROOT=$3
  DOCS_INFRA_BIN="$RUN_TMP/wrapper-$DOCS_INFRA_NAME"
  DOCS_INFRA_EVIDENCE="$EVIDENCE_DIR/adversarial-$DOCS_INFRA_NAME"
  mkdir -p "$DOCS_INFRA_BIN" || return 70
  printf '#!/bin/sh\nexit 2\n' >"$DOCS_INFRA_BIN/$DOCS_INFRA_TOOL" || return 70
  chmod +x "$DOCS_INFRA_BIN/$DOCS_INFRA_TOOL" || return 70
  set +e
  env PATH="$DOCS_INFRA_BIN:$PATH" SENSAI_TEST_DOCS_INNER=1 SENSAI_TEST_SOURCE_ROOT="$DOCS_INFRA_ROOT" "$TEST_RUNNER" docs --evidence "$DOCS_INFRA_EVIDENCE" >"$RUN_TMP/adversarial-$DOCS_INFRA_NAME.out" 2>&1
  DOCS_INFRA_RC=$?
  evidence_log_command "docs-adversarial-$DOCS_INFRA_NAME" "$TEST_RUNNER docs <failing-$DOCS_INFRA_TOOL-wrapper>" "$DOCS_INFRA_RC"
  assert_eq "docs.adversarial_${DOCS_INFRA_NAME}_exit" 70 "$DOCS_INFRA_RC" || true
  if test -f "$DOCS_INFRA_EVIDENCE/receipt.json"; then
    assert_jq "docs.adversarial_${DOCS_INFRA_NAME}_receipt" '.result == "INFRASTRUCTURE_ERROR" and .exit == 70' "$DOCS_INFRA_EVIDENCE/receipt.json" || true
  else
    assert_record "docs.adversarial_${DOCS_INFRA_NAME}_receipt" 1 'missing nested infrastructure receipt' || true
  fi
}

docs_run_missing_tool() {
  DOCS_MISSING_TOOL=$1
  DOCS_MISSING_ROOT=$2
  DOCS_MISSING_EVIDENCE="$EVIDENCE_DIR/adversarial-missing-$DOCS_MISSING_TOOL"
  set +e
  env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_MISSING_TOOL="$DOCS_MISSING_TOOL" SENSAI_TEST_DOCS_INNER=1 SENSAI_TEST_SOURCE_ROOT="$DOCS_MISSING_ROOT" "$TEST_RUNNER" docs --evidence "$DOCS_MISSING_EVIDENCE" >"$RUN_TMP/adversarial-missing-$DOCS_MISSING_TOOL.out" 2>&1
  DOCS_MISSING_RC=$?
  evidence_log_command "docs-adversarial-missing-$DOCS_MISSING_TOOL" "$TEST_RUNNER docs <missing-$DOCS_MISSING_TOOL>" "$DOCS_MISSING_RC"
  assert_eq "docs.adversarial_missing_${DOCS_MISSING_TOOL}_exit" 70 "$DOCS_MISSING_RC" || true
  if test -f "$DOCS_MISSING_EVIDENCE/receipt.json"; then
    assert_jq "docs.adversarial_missing_${DOCS_MISSING_TOOL}_receipt" ".result == \"INFRASTRUCTURE_ERROR\" and .exit == 70 and (.reason_codes | index(\"MISSING_COMMAND_$DOCS_MISSING_TOOL\")) != null" "$DOCS_MISSING_EVIDENCE/receipt.json" || true
  else
    assert_record "docs.adversarial_missing_${DOCS_MISSING_TOOL}_receipt" 1 'missing nested infrastructure receipt' || true
  fi
}

docs_run_adversarial_matrix() {
  DOCS_ADV_BASE="$RUN_TMP/docs-adversarial"
  mkdir -p "$DOCS_ADV_BASE" || return 70

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/misleading"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  printf '\nPASS docs are fine\nretired-alias-canary.md\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation misleading docs.stale_tokens "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/stale-command"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  printf '\n- `/sensai/obsolete`\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation stale_command docs.command_readme_exact_set "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/legacy-design"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  printf '\n- `/sensai/design`\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation legacy_design docs.no_legacy_design "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/windows-blocker"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  printf '\nEARLY_WINDOWS_BLOCKER: H1/H2 Windows receipt is required before macOS implementation.\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation windows_blocker docs.no_early_windows_blocker "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/enum-drift"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  sed 's/NAMING, STRUCTURE, COMPONENT, API, STATE, ERROR, TEST/NAMING, STRUCTURE, COMPONENT, API, STATE, ERROR, TEST, DATAFLOW/' "$DOCS_ADV_ROOT/README.md" >"$DOCS_ADV_ROOT/README.md.tmp" || return 70
  mv "$DOCS_ADV_ROOT/README.md.tmp" "$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation enum_drift docs.convention_enum "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/broken-link"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  printf '\n[broken](docs/does-not-exist.md)\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation broken_link docs.local_links "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/false-runtime-pass"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  printf '\nLOCAL_IMPLEMENTATION: PASS\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation false_runtime_pass docs.no_false_runtime_pass "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/missing-ollama-placeholder-contract"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  sed '/비밀 아닌 자리표시자이며 실제 자격 증명이 아니다/d' "$DOCS_ADV_ROOT/docs/harness/runtime-contract.md" >"$DOCS_ADV_ROOT/docs/harness/runtime-contract.md.tmp" || return 70
  mv "$DOCS_ADV_ROOT/docs/harness/runtime-contract.md.tmp" "$DOCS_ADV_ROOT/docs/harness/runtime-contract.md" || return 70
  docs_run_mutation missing_ollama_placeholder_contract docs.ollama_placeholder_contract "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/canonical-agent-drift"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  sed 's/sensai-evidence-peer/sensai-rogue-peer/g' "$DOCS_ADV_ROOT/docs/r4-mapping.md" >"$DOCS_ADV_ROOT/docs/r4-mapping.md.tmp" || return 70
  mv "$DOCS_ADV_ROOT/docs/r4-mapping.md.tmp" "$DOCS_ADV_ROOT/docs/r4-mapping.md" || return 70
  docs_run_mutation canonical_agent_drift docs.agent_canonical_exact_set "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/absolute-link"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  printf '\n[absolute](/etc/passwd)\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation absolute_link docs.local_links "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/outside-link"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  printf '\n[outside](../outside.md)\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation outside_link docs.local_links "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/nonregular-link"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  printf '\n[directory](docs)\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation nonregular_link docs.local_links "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/symlink-target"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  ln -s /etc/passwd "$DOCS_ADV_ROOT/docs/escape-link.md" || return 70
  printf '\n[symlink](docs/escape-link.md)\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation symlink_target docs.local_links "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/symlink-component"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  ln -s "$DOCS_ADV_ROOT/docs/harness" "$DOCS_ADV_ROOT/docs/escape-dir" || return 70
  printf '\n[symlink-component](docs/escape-dir/contract-freeze.md)\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_mutation symlink_component docs.local_links "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/valid-link-forms"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  cp "$DOCS_ADV_ROOT/docs/PROD.md" "$DOCS_ADV_ROOT/docs/link(escaped).md" || return 70
  printf '\n[escaped](docs/link\\(escaped\\).md)\n[external](https://example.com/a_(b))\n[duplicate](docs/PROD.md)\n[duplicate](docs/PROD.md)\n' >>"$DOCS_ADV_ROOT/README.md" || return 70
  docs_run_valid_mutation valid_link_forms "$DOCS_ADV_ROOT"

  DOCS_ADV_ROOT="$DOCS_ADV_BASE/infra-source"
  docs_clone_contract_source "$DOCS_ADV_ROOT" || return 70
  for DOCS_INFRA_TOOL in rg cmp find; do
    docs_run_infra_wrapper "failing_$DOCS_INFRA_TOOL" "$DOCS_INFRA_TOOL" "$DOCS_ADV_ROOT"
    docs_run_missing_tool "$DOCS_INFRA_TOOL" "$DOCS_ADV_ROOT"
  done
}

case_docs() {
  CASE_TOTAL=$((CASE_TOTAL + 1))

  assert_file docs.readme "$SOURCE_ROOT/README.md" || true
  assert_file docs.risk "$SOURCE_ROOT/risk.md" || true
  assert_file docs.product_contract "$SOURCE_ROOT/docs/PROD.md" || true
  assert_file docs.codegraph_guide "$SOURCE_ROOT/docs/codegraph-analysis-guide.md" || true
  assert_file docs.mapping_contract "$SOURCE_ROOT/docs/r4-mapping.md" || true
  tooling_sha256_file "$SOURCE_ROOT/AGENTS.md" || return 70
  if test "$TOOLING_SHA256" = "$DOCS_EXPECTED_AGENTS_SHA256"; then
    assert_record docs.agents_hash 0 "sha256=$TOOLING_SHA256" || true
  else
    assert_record docs.agents_hash 1 "expected=$DOCS_EXPECTED_AGENTS_SHA256 actual=$TOOLING_SHA256" || true
  fi

  docs_check_local_links || return 70

  docs_assert_absent docs.stale_tokens 'retired-alias-canary\.md|02-design\.md|T2-model-stack-research\.md|T3-quality-mitigation\.md|plan/release-plan\.md|plan/todo/' \
    "$SOURCE_ROOT/README.md" "$SOURCE_ROOT/risk.md" || return 70
  docs_assert_absent docs.no_legacy_design '/sensai/design|commands/sensai/design\.md' \
    "$SOURCE_ROOT/README.md" "$SOURCE_ROOT/risk.md" || return 70
  docs_assert_contains docs.alias_t2_program 'T2 program/charter → `T2-research-program\.md`' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.alias_t2_method 'T2 experiment methodology → `T2-methodology\.md`' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.alias_r3_cli 'R3 CLI catalog → `R3-cli-tools\.md`' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.alias_r3_integration 'R3 tool integration → `R3-tool-integration\.md`' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.alias_order '`R3-cli-tools\.md` → `I4-agent-update\.md` → `R3-tool-integration\.md`' "$SOURCE_ROOT/README.md"

  docs_check_command_catalog || return 70
  docs_check_skill_catalog || return 70
  docs_check_agent_catalog || return 70
  docs_assert_contains docs.model_lead '`zai/glm-5\.2`' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.model_peer '`sensai-ollama/qwen3\.5:9b`' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.model_unverified '`MODEL_ADMISSION=UNVERIFIED`' "$SOURCE_ROOT/README.md"
  docs_assert_absent docs.no_false_model_admission 'MODEL_ADMISSION[:=][[:space:]]*(PASS|ADMITTED)|MODEL_TOOL_ADMISSION[:=][[:space:]]*PASS' "$SOURCE_ROOT/README.md" "$SOURCE_ROOT/risk.md" || return 70
  docs_assert_contains docs.opencode_version 'exact `1\.18\.3`' "$SOURCE_ROOT/README.md"
  docs_assert_absent docs.no_old_opencode_version '1\.17\.18' "$SOURCE_ROOT/README.md" "$SOURCE_ROOT/risk.md" || return 70

  docs_assert_contains docs.mission_root '`docs/analysis/missions/<mission-id>/`' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.single_writer 'primary lead 한 명만 canonical mission state를 작성' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.convention_enum '^CONVENTION_CATEGORIES: NAMING, STRUCTURE, COMPONENT, API, STATE, ERROR, TEST$' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.dataflow_deliverable '`DATAFLOW`는 convention category가 아니라 AS-IS/TO-BE deliverable' "$SOURCE_ROOT/README.md"

  docs_assert_contains docs.macos_gate 'macOS가 deterministic 구현과 QA의 현재 gate' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.windows_final '`WINDOWS_COMPATIBILITY_UNVERIFIED`' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.windows_direct_exe '`sensai\.exe`' "$SOURCE_ROOT/README.md"
  docs_assert_absent docs.no_early_windows_blocker 'EARLY_WINDOWS_BLOCKER|Windows receipt is required before macOS|WINDOWS_H1_H2_REQUIRED_BEFORE_MACOS' "$SOURCE_ROOT/README.md" "$SOURCE_ROOT/risk.md" "$SOURCE_ROOT/docs" || return 70
  docs_assert_absent docs.no_false_runtime_pass 'LOCAL_IMPLEMENTATION[:=][[:space:]]*PASS|`LOCAL_IMPLEMENTATION`[[:space:]]*\|[[:space:]]*`PASS`' "$SOURCE_ROOT/README.md" "$SOURCE_ROOT/risk.md" || return 70

  docs_assert_contains docs.root_agents_fixture_contract 'Fixture corpus와 검증 계약' "$SOURCE_ROOT/AGENTS.md"
  docs_assert_contains docs.root_agents_fixture_counts '물리 leaf 35개.*37개' "$SOURCE_ROOT/AGENTS.md"
  docs_assert_contains docs.root_agents_cases 'happy 14개.*adversarial 14개' "$SOURCE_ROOT/AGENTS.md"
  docs_assert_contains docs.output_language 'output language:.*한국어' "$SOURCE_ROOT/README.md"
  docs_assert_contains docs.ollama_placeholder_contract '`apiKey`는 `ollama`로 고정.*비밀 아닌 자리표시자.*실제 자격 증명이 아니다' "$SOURCE_ROOT/docs/harness/runtime-contract.md"

  if test "${SENSAI_TEST_DOCS_INNER:-0}" != 1; then
    docs_run_adversarial_matrix || return 70
  fi
}
