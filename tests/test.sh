#!/bin/sh

set -u

EX_USAGE=64
EX_INFRA=70
SELECTOR=''
EXPECTED_CASE=''
EVIDENCE_REQUEST=''
CASE_TOTAL=0
RUNNER_INFRA_REASON=''
RUNNER_PREFLIGHT_REASON=''

usage() {
  cat <<'EOF'
usage: ./tests/test.sh <selector> [--evidence <dir>]
       ./tests/test.sh expect-fail <case> [--evidence <dir>]

selectors:
  all
  self
  docs
  fixtures
  catalog-oracle
  schema-trace
  schema-progress
  recipe-trace
  provenance
  validators
  config
  agents
  permissions
  skills-core
  skills-analysis
  skills-delivery
  commands-asis
  commands-delivery
  commands-analysis
  commands-orchestration
  doctor
  packaging
  packaging-adversarial
  e2e-asis
  e2e-tobe
  continuity
  opencode-load
  core-readiness
  expect-fail fixture-without-golden
  expect-fail stale-catalog-doc
  expect-fail extra-skill
  expect-fail trace-dangling-id
  expect-fail mission-path-traversal
  expect-fail evidence-free-glossary
  expect-fail mismatched-mermaid-source
  expect-fail validator-noop
  expect-fail config-claims-live-admission
  expect-fail peer-edit-enabled
  expect-fail forbidden-mcp-config
  expect-fail skill-without-evidence-contract
  expect-fail unsupported-forced-to-known
  expect-fail design-without-binding
  expect-fail document-before-analysis
  expect-fail command-output-outside-mission
  expect-fail tobe-before-asis-accept
  expect-fail command-design-without-binding
  expect-fail stale-resume-hash
  expect-fail wrong-yq-product
  expect-fail existing-install-target
  expect-fail staged-byte-drift
  expect-fail asis-golden-drift
  expect-fail conflict-hidden-by-deliverable
  expect-fail concurrent-mission-writer
  expect-fail inherited-config-sentinel
  expect-fail misleading-success-output
  expect-fail core-not-ready
EOF
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd -P) || exit "$EX_INFRA"
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." 2>/dev/null && pwd -P) || exit "$EX_INFRA"
TEST_RUNNER="$SCRIPT_DIR/test.sh"

for TEST_LIB in assert evidence tooling receipt; do
  TEST_LIB_PATH="$SCRIPT_DIR/lib/$TEST_LIB.sh"
  if ! test -f "$TEST_LIB_PATH"; then
    printf 'INFRA_ERROR missing_test_library path=%s\n' "$TEST_LIB_PATH" >&2
    exit "$EX_INFRA"
  fi
  . "$TEST_LIB_PATH"
done

for TEST_CASE_FILE in self docs fixtures catalog-oracle schema-trace schema-progress recipe-trace provenance validators config agents permissions skills-core skills-analysis skills-delivery commands-asis commands-delivery commands-orchestration doctor packaging packaging-adversarial e2e-asis e2e-tobe continuity opencode-load release-preflight core-readiness; do
  TEST_CASE_PATH="$SCRIPT_DIR/cases/$TEST_CASE_FILE.sh"
  if ! test -f "$TEST_CASE_PATH"; then
    printf 'INFRA_ERROR missing_test_case path=%s\n' "$TEST_CASE_PATH" >&2
    exit "$EX_INFRA"
  fi
  . "$TEST_CASE_PATH"
done

if test "$#" -eq 0; then
  usage >&2
  exit "$EX_USAGE"
fi

case "$1" in
  -h|--help|help)
    test "$#" -eq 1 || { usage >&2; exit "$EX_USAGE"; }
    usage
    exit 0
    ;;
esac

SELECTOR=$1
shift
if test "$SELECTOR" = expect-fail; then
  test "$#" -gt 0 || { usage >&2; exit "$EX_USAGE"; }
  EXPECTED_CASE=$1
  shift
fi

while test "$#" -gt 0; do
  case "$1" in
    --evidence)
      test -z "$EVIDENCE_REQUEST" || { usage >&2; exit "$EX_USAGE"; }
      test "$#" -ge 2 && test -n "$2" || { usage >&2; exit "$EX_USAGE"; }
      EVIDENCE_REQUEST=$2
      shift 2
      ;;
    *) usage >&2; exit "$EX_USAGE" ;;
  esac
done

case "$SELECTOR" in
  all|self|docs|fixtures|catalog-oracle|schema-trace|schema-progress|recipe-trace|provenance|validators|config|agents|permissions|skills-core|skills-analysis|skills-delivery|commands-asis|commands-analysis|commands-delivery|commands-orchestration|doctor|packaging|packaging-adversarial|e2e-asis|e2e-tobe|continuity|opencode-load|core-readiness|expect-fail) ;;
  __assertion-probe|__pass-probe|__misleading-probe|__fingerprint-probe|__empty-probe)
    test "${SENSAI_TEST_INTERNAL:-0}" = 1 || { usage >&2; exit "$EX_USAGE"; }
    ;;
  *) usage >&2; exit "$EX_USAGE" ;;
esac

for REQUIRED_TOOL in jq yq shasum git find sort awk sed wc mktemp mkfifo rg cp cmp mv rm perl ln chmod; do
  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test "${SENSAI_TEST_MISSING_TOOL:-}" = "$REQUIRED_TOOL"; then
    REQUIRED_TOOL_AVAILABLE=0
  elif command -v "$REQUIRED_TOOL" >/dev/null 2>&1; then
    REQUIRED_TOOL_AVAILABLE=1
  else
    REQUIRED_TOOL_AVAILABLE=0
  fi
  if test "$REQUIRED_TOOL_AVAILABLE" -eq 0; then
    case "$REQUIRED_TOOL" in
      rg|cmp|find)
        RUNNER_PREFLIGHT_REASON="MISSING_COMMAND_$REQUIRED_TOOL"
        ;;
      *)
        printf 'INFRA_ERROR missing_command command=%s\n' "$REQUIRED_TOOL" >&2
        exit "$EX_INFRA"
        ;;
    esac
  fi
done

if test -z "$RUNNER_PREFLIGHT_REASON"; then
  find "$REPO_ROOT" -maxdepth 0 -type d -print >/dev/null 2>&1
  RUNNER_FIND_PROBE_RC=$?
  case "$RUNNER_FIND_PROBE_RC" in
    0) ;;
    *) RUNNER_PREFLIGHT_REASON=FIND_COMMAND_FAILED ;;
  esac
fi

if ! evidence_prepare "$EVIDENCE_REQUEST"; then
  evidence_cleanup
  exit "$EX_INFRA"
fi
evidence_install_traps

SOURCE_ROOT_REQUEST=${SENSAI_TEST_SOURCE_ROOT:-$REPO_ROOT}
if ! tooling_resolve_source_root "$SOURCE_ROOT_REQUEST"; then
  RUNNER_INFRA_REASON=SOURCE_ROOT_INVALID
  SOURCE_FINGERPRINT=0000000000000000000000000000000000000000000000000000000000000000
fi

if test -n "$RUNNER_PREFLIGHT_REASON" && test -z "$RUNNER_INFRA_REASON"; then
  RUNNER_INFRA_REASON=$RUNNER_PREFLIGHT_REASON
  SOURCE_FINGERPRINT=0000000000000000000000000000000000000000000000000000000000000000
  SOURCE_FILE_COUNT=0
  GIT_STATE=UNVERIFIED
  UNTRACKED_FILE="$RUN_TMP/untracked.txt"
  : >"$UNTRACKED_FILE" || exit "$EX_INFRA"
fi

AGENTS_SHA256='ABSENT'
if test -z "$RUNNER_INFRA_REASON" && test -f "$SOURCE_ROOT/AGENTS.md"; then
  if tooling_sha256_file "$SOURCE_ROOT/AGENTS.md"; then
    AGENTS_SHA256=$TOOLING_SHA256
  else
    RUNNER_INFRA_REASON=AGENTS_HASH_FAILED
  fi
fi

if test -z "$RUNNER_INFRA_REASON"; then
  if ! tooling_fingerprint_source; then
    RUNNER_INFRA_REASON=SOURCE_FINGERPRINT_FAILED
    SOURCE_FINGERPRINT=0000000000000000000000000000000000000000000000000000000000000000
    SOURCE_FILE_COUNT=0
    test -n "$UNTRACKED_FILE" || UNTRACKED_FILE="$RUN_TMP/untracked.txt"
    test -f "$UNTRACKED_FILE" || : >"$UNTRACKED_FILE"
  fi
fi

case "${SENSAI_TEST_FAULT:-}" in
  '') ;;
  infra) RUNNER_INFRA_REASON=SIMULATED_INFRASTRUCTURE_FAULT ;;
  missing-command)
    tooling_require_command __sensai_intentionally_missing_command__ || RUNNER_INFRA_REASON=MISSING_COMMAND
    ;;
  *) RUNNER_INFRA_REASON=UNKNOWN_FAULT_INJECTION ;;
esac

finish_runner() {
  FINISH_EXIT=$1
  FINISH_RESULT=$2
  if test "$FINISH_RESULT" = INFRASTRUCTURE_ERROR; then
    test "$CASE_TOTAL" -gt 0 || CASE_TOTAL=1
    if test "$ASSERT_TOTAL" -eq 0; then
      assert_record runner.infrastructure 1 "reason=$RUNNER_INFRA_REASON" >/dev/null 2>&1 || true
    fi
  fi
  if ! receipt_write "$SELECTOR${EXPECTED_CASE:+:$EXPECTED_CASE}" "$FINISH_EXIT" "$FINISH_RESULT"; then
    printf 'INFRA_ERROR receipt_write_failed selector=%s\n' "$SELECTOR" >&2
    exit "$EX_INFRA"
  fi
  printf 'TEST_SUMMARY selector=%s result=%s cases=%s assertions=%s failed=%s receipt=%s\n' \
    "$SELECTOR${EXPECTED_CASE:+:$EXPECTED_CASE}" "$FINISH_RESULT" "$CASE_TOTAL" "$ASSERT_TOTAL" "$ASSERT_FAILED" "$EVIDENCE_DIR/receipt.json"
  exit "$FINISH_EXIT"
}

if test -n "$RUNNER_INFRA_REASON"; then
  evidence_add_reason "$RUNNER_INFRA_REASON"
  printf 'INFRA_ERROR reason=%s\n' "$RUNNER_INFRA_REASON" >&2
  finish_runner "$EX_INFRA" INFRASTRUCTURE_ERROR
fi

run_expected_core_not_ready() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_CORE_ROOT="$RUN_TMP/expect-core-not-ready-source"
  EXPECT_INNER="$EVIDENCE_DIR/inner-core-not-ready"
  core_clone_without_manifest "$EXPECT_CORE_ROOT" || return 70
  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test -n "${SENSAI_TEST_EXPECT_FORCED_EXIT:-}"; then
    case "$SENSAI_TEST_EXPECT_FORCED_EXIT" in
      64|70|127) EXPECT_RC=$SENSAI_TEST_EXPECT_FORCED_EXIT ;;
      *) EXPECT_RC=70 ;;
    esac
    printf 'forced inner exit=%s\n' "$EXPECT_RC" >"$RUN_TMP/expect-core.out"
  else
    set +e
    env SENSAI_TEST_SOURCE_ROOT="$EXPECT_CORE_ROOT" \
      "$TEST_RUNNER" core-readiness --evidence "$EXPECT_INNER" >"$RUN_TMP/expect-core.out" 2>&1
    EXPECT_RC=$?
  fi
  evidence_log_command expected-core-not-ready \
    "$TEST_RUNNER core-readiness <isolated-missing-manifest>" "$EXPECT_RC"

  case "$EXPECT_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.core_exit 1 "$EXPECT_RC" || true
  if test -f "$EXPECT_INNER/receipt.json"; then
    assert_jq expect.core_result '.result == "ASSERTION_FAILURE" and .exit == 1' "$EXPECT_INNER/receipt.json" || true
    assert_jq expect.core_reason '(.reason_codes | index("CORE_NOT_READY")) != null' "$EXPECT_INNER/receipt.json" || true
    assert_jq expect.core_named_surfaces '.failed_assertion_ids == ["core.manifest"]' "$EXPECT_INNER/receipt.json" || true
  else
    assert_record expect.core_receipt 1 "missing=$EXPECT_INNER/receipt.json" || true
  fi
}

run_expected_stale_catalog_doc() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_DOC_ROOT="$RUN_TMP/expect-stale-catalog-source"
  EXPECT_DOC_EVIDENCE="$EVIDENCE_DIR/inner-stale-catalog"
  docs_clone_contract_source "$EXPECT_DOC_ROOT" || return 70
  printf '\nretired-alias-canary.md\n' >>"$EXPECT_DOC_ROOT/README.md" || return 70

  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test -n "${SENSAI_TEST_EXPECT_DOCS_FORCED_EXIT:-}"; then
    case "$SENSAI_TEST_EXPECT_DOCS_FORCED_EXIT" in
      64|70|127) EXPECT_DOC_RC=$SENSAI_TEST_EXPECT_DOCS_FORCED_EXIT ;;
      *) EXPECT_DOC_RC=70 ;;
    esac
    printf 'forced docs inner exit=%s\n' "$EXPECT_DOC_RC" >"$RUN_TMP/expect-stale-catalog.out"
  else
    set +e
    env SENSAI_TEST_DOCS_INNER=1 SENSAI_TEST_SOURCE_ROOT="$EXPECT_DOC_ROOT" "$TEST_RUNNER" docs --evidence "$EXPECT_DOC_EVIDENCE" >"$RUN_TMP/expect-stale-catalog.out" 2>&1
    EXPECT_DOC_RC=$?
  fi
  evidence_log_command expected-stale-catalog "$TEST_RUNNER docs <isolated-stale-catalog>" "$EXPECT_DOC_RC"

  case "$EXPECT_DOC_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_DOC_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.stale_catalog_exit 1 "$EXPECT_DOC_RC" || true
  if test -f "$EXPECT_DOC_EVIDENCE/receipt.json"; then
    assert_jq expect.stale_catalog_result '.result == "ASSERTION_FAILURE" and .exit == 1' "$EXPECT_DOC_EVIDENCE/receipt.json" || true
    assert_jq expect.stale_catalog_named_failure '(.failed_assertion_ids | index("docs.stale_tokens")) != null' "$EXPECT_DOC_EVIDENCE/receipt.json" || true
  else
    assert_record expect.stale_catalog_receipt 1 "missing=$EXPECT_DOC_EVIDENCE/receipt.json" || true
  fi
}

run_expected_fixture_without_golden() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_FIXTURE_ROOT="$RUN_TMP/expect-fixture-without-golden-source"
  EXPECT_FIXTURE_EVIDENCE="$EVIDENCE_DIR/inner-fixture-without-golden"
  fixtures_clone_source "$EXPECT_FIXTURE_ROOT" || return 70
  rm "$EXPECT_FIXTURE_ROOT/fixtures/expected/tobe/test.md" || return 70
  fixtures_remove_inventory_path "$EXPECT_FIXTURE_ROOT" expected/tobe/test.md || return 70
  fixtures_refresh_metadata "$EXPECT_FIXTURE_ROOT" || return 70

  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test -n "${SENSAI_TEST_EXPECT_FIXTURE_FORCED_EXIT:-}"; then
    case "$SENSAI_TEST_EXPECT_FIXTURE_FORCED_EXIT" in
      64|70|127) EXPECT_FIXTURE_RC=$SENSAI_TEST_EXPECT_FIXTURE_FORCED_EXIT ;;
      *) EXPECT_FIXTURE_RC=70 ;;
    esac
    printf 'forced fixture inner exit=%s\n' "$EXPECT_FIXTURE_RC" >"$RUN_TMP/expect-fixture.out"
  else
    set +e
    env SENSAI_TEST_FIXTURES_INNER=1 SENSAI_TEST_SOURCE_ROOT="$EXPECT_FIXTURE_ROOT" \
      "$TEST_RUNNER" fixtures --evidence "$EXPECT_FIXTURE_EVIDENCE" >"$RUN_TMP/expect-fixture.out" 2>&1
    EXPECT_FIXTURE_RC=$?
  fi
  evidence_log_command expected-fixture-without-golden "$TEST_RUNNER fixtures <isolated-missing-golden>" "$EXPECT_FIXTURE_RC"

  case "$EXPECT_FIXTURE_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_FIXTURE_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.fixture_without_golden_exit 1 "$EXPECT_FIXTURE_RC" || true
  if test -f "$EXPECT_FIXTURE_EVIDENCE/receipt.json"; then
    assert_jq expect.fixture_without_golden_result '.result == "ASSERTION_FAILURE" and .exit == 1' "$EXPECT_FIXTURE_EVIDENCE/receipt.json" || true
    assert_jq expect.fixture_without_golden_named_failure '.failed_assertion_ids == ["fixtures.happy_golden_files"]' "$EXPECT_FIXTURE_EVIDENCE/receipt.json" || true
  else
    assert_record expect.fixture_without_golden_receipt 1 "missing=$EXPECT_FIXTURE_EVIDENCE/receipt.json" || true
  fi
}

run_expected_extra_skill() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_CATALOG_ROOT="$RUN_TMP/expect-extra-skill-source"
  EXPECT_CATALOG_EVIDENCE="$EVIDENCE_DIR/inner-extra-skill"
  catalog_clone_source "$EXPECT_CATALOG_ROOT" || return 70
  printf '%s\n' skills/sensai-rogue/SKILL.md >>"$EXPECT_CATALOG_ROOT/tests/contracts/skills.txt" || return 70
  LC_ALL=C sort "$EXPECT_CATALOG_ROOT/tests/contracts/skills.txt" >"$EXPECT_CATALOG_ROOT/tests/contracts/skills.tmp" && \
    mv "$EXPECT_CATALOG_ROOT/tests/contracts/skills.tmp" "$EXPECT_CATALOG_ROOT/tests/contracts/skills.txt" || return 70

  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test -n "${SENSAI_TEST_EXPECT_CATALOG_FORCED_EXIT:-}"; then
    case "$SENSAI_TEST_EXPECT_CATALOG_FORCED_EXIT" in
      64|70|127) EXPECT_CATALOG_RC=$SENSAI_TEST_EXPECT_CATALOG_FORCED_EXIT ;;
      *) EXPECT_CATALOG_RC=70 ;;
    esac
    printf 'forced catalog inner exit=%s\n' "$EXPECT_CATALOG_RC" >"$RUN_TMP/expect-extra-skill.out"
  else
    set +e
    env SENSAI_TEST_CATALOG_INNER=1 SENSAI_TEST_SOURCE_ROOT="$EXPECT_CATALOG_ROOT" \
      "$TEST_RUNNER" catalog-oracle --evidence "$EXPECT_CATALOG_EVIDENCE" >"$RUN_TMP/expect-extra-skill.out" 2>&1
    EXPECT_CATALOG_RC=$?
  fi
  evidence_log_command expected-extra-skill "$TEST_RUNNER catalog-oracle <isolated-extra-skill>" "$EXPECT_CATALOG_RC"
  case "$EXPECT_CATALOG_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_CATALOG_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.extra_skill_exit 1 "$EXPECT_CATALOG_RC" || true
  if test -f "$EXPECT_CATALOG_EVIDENCE/receipt.json"; then
    assert_jq expect.extra_skill_result '.result == "ASSERTION_FAILURE" and .exit == 1' "$EXPECT_CATALOG_EVIDENCE/receipt.json" || true
    assert_jq expect.extra_skill_named_failure '.failed_assertion_ids == ["catalog.skills_exact"]' "$EXPECT_CATALOG_EVIDENCE/receipt.json" || true
  else
    assert_record expect.extra_skill_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_trace_dangling_id() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_TRACE_ROOT="$RUN_TMP/expect-trace-dangling-source"
  EXPECT_TRACE_EVIDENCE="$EVIDENCE_DIR/inner-trace-dangling"
  schema_trace_clone_source "$EXPECT_TRACE_ROOT" || return 70
  EXPECT_TRACE_DANGLING_ID=$(jq -r '.requirements[0].evidence_ids[0]' \
    "$SOURCE_ROOT/fixtures/adversarial/dangling-reference.json") || return 70
  test -n "$EXPECT_TRACE_DANGLING_ID" && test "$EXPECT_TRACE_DANGLING_ID" != null || return 70
  jq --arg evidence_id "$EXPECT_TRACE_DANGLING_ID" \
    '.requirements[0].evidence_ids = [$evidence_id]' \
    "$EXPECT_TRACE_ROOT/fixtures/expected/trace-v2.json" >"$EXPECT_TRACE_ROOT/trace-dangling.json" || return 70

  set +e
  env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_INTERNAL_TRACE_INPUT="$EXPECT_TRACE_ROOT/trace-dangling.json" \
    SENSAI_TEST_SOURCE_ROOT="$EXPECT_TRACE_ROOT" \
    "$TEST_RUNNER" schema-trace --evidence "$EXPECT_TRACE_EVIDENCE" >"$RUN_TMP/expect-trace-dangling.out" 2>&1
  EXPECT_TRACE_RC=$?
  evidence_log_command expected-trace-dangling "$TEST_RUNNER schema-trace <isolated-dangling-reference>" "$EXPECT_TRACE_RC"

  case "$EXPECT_TRACE_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_TRACE_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.trace_dangling_exit 1 "$EXPECT_TRACE_RC" || true
  if test -f "$EXPECT_TRACE_EVIDENCE/receipt.json"; then
    assert_jq expect.trace_dangling_result '.result == "ASSERTION_FAILURE" and .exit == 1' "$EXPECT_TRACE_EVIDENCE/receipt.json" || true
    assert_jq expect.trace_dangling_named_failure '.failed_assertion_ids == ["trace.reference_integrity"]' "$EXPECT_TRACE_EVIDENCE/receipt.json" || true
  else
    assert_record expect.trace_dangling_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_mission_path_traversal() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_PROGRESS_ROOT="$RUN_TMP/expect-progress-traversal-source"
  EXPECT_PROGRESS_EVIDENCE="$EVIDENCE_DIR/inner-mission-path-traversal"
  schema_progress_clone_source "$EXPECT_PROGRESS_ROOT" || return 70
  jq '.mission_root="docs/analysis/missions/../escape/"' \
    "$EXPECT_PROGRESS_ROOT/fixtures/expected/progress.json" >"$EXPECT_PROGRESS_ROOT/progress-traversal.json" || return 70

  set +e
  env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_INTERNAL_PROGRESS_INPUT="$EXPECT_PROGRESS_ROOT/progress-traversal.json" \
    SENSAI_TEST_SOURCE_ROOT="$EXPECT_PROGRESS_ROOT" \
    "$TEST_RUNNER" schema-progress --evidence "$EXPECT_PROGRESS_EVIDENCE" >"$RUN_TMP/expect-progress-traversal.out" 2>&1
  EXPECT_PROGRESS_RC=$?
  evidence_log_command expected-mission-path-traversal "$TEST_RUNNER schema-progress <isolated-path-traversal>" "$EXPECT_PROGRESS_RC"

  case "$EXPECT_PROGRESS_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_PROGRESS_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.mission_path_traversal_exit 1 "$EXPECT_PROGRESS_RC" || true
  if test -f "$EXPECT_PROGRESS_EVIDENCE/receipt.json"; then
    assert_jq expect.mission_path_traversal_result '.result == "ASSERTION_FAILURE" and .exit == 1' "$EXPECT_PROGRESS_EVIDENCE/receipt.json" || true
    assert_jq expect.mission_path_traversal_named_failure '.failed_assertion_ids == ["progress.path"]' "$EXPECT_PROGRESS_EVIDENCE/receipt.json" || true
  else
    assert_record expect.mission_path_traversal_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_evidence_free_glossary() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_GLOSSARY_ROOT="$RUN_TMP/expect-evidence-free-glossary-source"
  EXPECT_GLOSSARY_EVIDENCE="$EVIDENCE_DIR/inner-evidence-free-glossary"
  mkdir -p "$EXPECT_GLOSSARY_ROOT/output/recipes" "$EXPECT_GLOSSARY_ROOT/fixtures/expected" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$EXPECT_GLOSSARY_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$EXPECT_GLOSSARY_ROOT/tests" || return 70
  cp "$SOURCE_ROOT/output/recipes/glossary.jq" "$EXPECT_GLOSSARY_ROOT/output/recipes/glossary.jq" || return 70
  cp "$SOURCE_ROOT/fixtures/expected/trace-v2.json" "$EXPECT_GLOSSARY_ROOT/fixtures/expected/trace-v2.json" || return 70
  jq '.terms[0].evidence_ids = []' "$SOURCE_ROOT/fixtures/expected/glossary.json" \
    >"$EXPECT_GLOSSARY_ROOT/glossary-evidence-free.json" || return 70

  env SENSAI_TEST_INTERNAL=1 \
    SENSAI_TEST_INTERNAL_GLOSSARY_INPUT="$EXPECT_GLOSSARY_ROOT/glossary-evidence-free.json" \
    SENSAI_TEST_SOURCE_ROOT="$EXPECT_GLOSSARY_ROOT" \
    "$TEST_RUNNER" recipe-trace --evidence "$EXPECT_GLOSSARY_EVIDENCE" \
    >"$RUN_TMP/expect-evidence-free-glossary.out" 2>&1
  EXPECT_GLOSSARY_RC=$?
  evidence_log_command expected-evidence-free-glossary "$TEST_RUNNER recipe-trace <isolated-evidence-free-glossary>" "$EXPECT_GLOSSARY_RC"

  case "$EXPECT_GLOSSARY_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_GLOSSARY_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.evidence_free_glossary_exit 1 "$EXPECT_GLOSSARY_RC" || true
  if test -f "$EXPECT_GLOSSARY_EVIDENCE/receipt.json"; then
    assert_jq expect.evidence_free_glossary_result '.result == "ASSERTION_FAILURE" and .exit == 1' "$EXPECT_GLOSSARY_EVIDENCE/receipt.json" || true
    assert_jq expect.evidence_free_glossary_named_failure '.failed_assertion_ids == ["glossary.direct_evidence"]' "$EXPECT_GLOSSARY_EVIDENCE/receipt.json" || true
  else
    assert_record expect.evidence_free_glossary_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_mismatched_mermaid_source() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_PROVENANCE_ROOT="$RUN_TMP/expect-mismatched-mermaid-source"
  EXPECT_PROVENANCE_EVIDENCE="$EVIDENCE_DIR/inner-mismatched-mermaid-source"
  mkdir -p "$EXPECT_PROVENANCE_ROOT/output/recipes" \
    "$EXPECT_PROVENANCE_ROOT/fixtures/expected/asis" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$EXPECT_PROVENANCE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$EXPECT_PROVENANCE_ROOT/tests" || return 70
  cp "$SOURCE_ROOT/output/recipes/provenance.jq" \
    "$EXPECT_PROVENANCE_ROOT/output/recipes/provenance.jq" || return 70
  cp "$SOURCE_ROOT/fixtures/expected/trace-v2.json" \
    "$EXPECT_PROVENANCE_ROOT/fixtures/expected/trace-v2.json" || return 70
  sed 's#inputs/legacy-vertx/src/main/java/example/OrderVerticle.java:10#inputs/legacy-react/src/OrdersPage.tsx:3#' \
    "$SOURCE_ROOT/fixtures/expected/asis/sequence.mmd" \
    >"$EXPECT_PROVENANCE_ROOT/mismatched-source.mmd" || return 70

  env SENSAI_TEST_INTERNAL=1 \
    SENSAI_TEST_INTERNAL_PROVENANCE_INPUT="$EXPECT_PROVENANCE_ROOT/mismatched-source.mmd" \
    SENSAI_TEST_INTERNAL_PROVENANCE_MODE=mermaid \
    SENSAI_TEST_INTERNAL_PROVENANCE_KIND=asis \
    SENSAI_TEST_SOURCE_ROOT="$EXPECT_PROVENANCE_ROOT" \
    "$TEST_RUNNER" provenance --evidence "$EXPECT_PROVENANCE_EVIDENCE" \
    >"$RUN_TMP/expect-mismatched-mermaid-source.out" 2>&1
  EXPECT_PROVENANCE_RC=$?
  evidence_log_command expected-mismatched-mermaid-source \
    "$TEST_RUNNER provenance <isolated-mismatched-mermaid-source>" "$EXPECT_PROVENANCE_RC"

  case "$EXPECT_PROVENANCE_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_PROVENANCE_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.mismatched_mermaid_source_exit 1 "$EXPECT_PROVENANCE_RC" || true
  if test -f "$EXPECT_PROVENANCE_EVIDENCE/receipt.json"; then
    assert_jq expect.mismatched_mermaid_source_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_PROVENANCE_EVIDENCE/receipt.json" || true
    assert_jq expect.mismatched_mermaid_source_named_failure \
      '.failed_assertion_ids == ["provenance.source_mismatch"]' \
      "$EXPECT_PROVENANCE_EVIDENCE/receipt.json" || true
  else
    assert_record expect.mismatched_mermaid_source_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_validator_noop() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_VALIDATOR_ROOT="$RUN_TMP/expect-validator-noop-source"
  EXPECT_VALIDATOR_EVIDENCE="$EVIDENCE_DIR/inner-validator-noop"
  validators_clone_source "$EXPECT_VALIDATOR_ROOT" || return 70
  printf '[]\n' >"$EXPECT_VALIDATOR_ROOT/tests/validators/trace-schema-parity.jq" || return 70

  set +e
  env SENSAI_TEST_INTERNAL_VALIDATOR_HEALTH_ONLY=1 \
    SENSAI_TEST_SOURCE_ROOT="$EXPECT_VALIDATOR_ROOT" \
    "$TEST_RUNNER" validators --evidence "$EXPECT_VALIDATOR_EVIDENCE" \
    >"$RUN_TMP/expect-validator-noop.out" 2>&1
  EXPECT_VALIDATOR_RC=$?
  evidence_log_command expected-validator-noop \
    "$TEST_RUNNER validators <isolated-noop-validator>" "$EXPECT_VALIDATOR_RC"

  case "$EXPECT_VALIDATOR_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_VALIDATOR_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.validator_noop_exit 1 "$EXPECT_VALIDATOR_RC" || true
  if test -f "$EXPECT_VALIDATOR_EVIDENCE/receipt.json"; then
    assert_jq expect.validator_noop_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_VALIDATOR_EVIDENCE/receipt.json" || true
    assert_jq expect.validator_noop_named_failure \
      '.failed_assertion_ids == ["validators.noop_detected"]' \
      "$EXPECT_VALIDATOR_EVIDENCE/receipt.json" || true
  else
    assert_record expect.validator_noop_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_config_claims_live_admission() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_CONFIG_ROOT="$RUN_TMP/expect-config-claims-live-admission-source"
  EXPECT_CONFIG_EVIDENCE="$EVIDENCE_DIR/inner-config-claims-live-admission"
  config_clone_source "$EXPECT_CONFIG_ROOT" || return 70
  jq '.model_admission = "VERIFIED"' "$EXPECT_CONFIG_ROOT/output/toolchain.lock.json" \
    >"$EXPECT_CONFIG_ROOT/output/toolchain.lock.json.tmp" && \
    mv "$EXPECT_CONFIG_ROOT/output/toolchain.lock.json.tmp" \
      "$EXPECT_CONFIG_ROOT/output/toolchain.lock.json" || return 70

  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && \
     test -n "${SENSAI_TEST_EXPECT_CONFIG_FORCED_EXIT:-}"; then
    case "$SENSAI_TEST_EXPECT_CONFIG_FORCED_EXIT" in
      64|70|127) EXPECT_CONFIG_RC=$SENSAI_TEST_EXPECT_CONFIG_FORCED_EXIT ;;
      *) EXPECT_CONFIG_RC=70 ;;
    esac
    printf 'forced config inner exit=%s\n' "$EXPECT_CONFIG_RC" >"$RUN_TMP/expect-config.out"
  else
    set +e
    env SENSAI_TEST_CONFIG_INNER=1 SENSAI_TEST_SOURCE_ROOT="$EXPECT_CONFIG_ROOT" \
      "$TEST_RUNNER" config --evidence "$EXPECT_CONFIG_EVIDENCE" \
      >"$RUN_TMP/expect-config.out" 2>&1
    EXPECT_CONFIG_RC=$?
  fi
  evidence_log_command expected-config-claims-live-admission \
    "$TEST_RUNNER config <isolated-live-admission-claim>" "$EXPECT_CONFIG_RC"

  case "$EXPECT_CONFIG_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_CONFIG_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.config_claim_exit 1 "$EXPECT_CONFIG_RC" || true
  if test -f "$EXPECT_CONFIG_EVIDENCE/receipt.json"; then
    assert_jq expect.config_claim_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_CONFIG_EVIDENCE/receipt.json" || true
    assert_jq expect.config_claim_named_failure \
      '.failed_assertion_ids == ["config.model_admission"]' \
      "$EXPECT_CONFIG_EVIDENCE/receipt.json" || true
  else
    assert_record expect.config_claim_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_peer_edit_enabled() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_AGENTS_ROOT="$RUN_TMP/expect-peer-edit-enabled-source"
  EXPECT_AGENTS_EVIDENCE="$EVIDENCE_DIR/inner-peer-edit-enabled"
  agents_clone_source "$EXPECT_AGENTS_ROOT" || return 70
  EXPECT_AGENTS_PEER="$EXPECT_AGENTS_ROOT/output/agents/sensai-evidence-peer.md"
  perl -0pi -e 's/^  edit: deny$/  edit: allow/m' "$EXPECT_AGENTS_PEER" || return 70
  if cmp -s "$SOURCE_ROOT/output/agents/sensai-evidence-peer.md" "$EXPECT_AGENTS_PEER"; then
    return 70
  fi

  set +e
  env SENSAI_TEST_SOURCE_ROOT="$EXPECT_AGENTS_ROOT" \
    "$TEST_RUNNER" agents --evidence "$EXPECT_AGENTS_EVIDENCE" \
    >"$RUN_TMP/expect-peer-edit-enabled.out" 2>&1
  EXPECT_AGENTS_RC=$?
  evidence_log_command expected-peer-edit-enabled \
    "$TEST_RUNNER agents <isolated-peer-edit-enabled>" "$EXPECT_AGENTS_RC"

  case "$EXPECT_AGENTS_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_AGENTS_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.peer_edit_exit 1 "$EXPECT_AGENTS_RC" || true
  if test -f "$EXPECT_AGENTS_EVIDENCE/receipt.json"; then
    assert_jq expect.peer_edit_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_AGENTS_EVIDENCE/receipt.json" || true
    assert_jq expect.peer_edit_named_failure \
      '.failed_assertion_ids == ["agents.peer_permission"]' \
      "$EXPECT_AGENTS_EVIDENCE/receipt.json" || true
  else
    assert_record expect.peer_edit_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_forbidden_mcp_config() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_PERMISSIONS_ROOT="$RUN_TMP/expect-forbidden-mcp-source"
  EXPECT_PERMISSIONS_EVIDENCE="$EVIDENCE_DIR/inner-forbidden-mcp-config"
  permissions_clone_source "$EXPECT_PERMISSIONS_ROOT" || return 70
  jq '.mcp = {"rogue":{"type":"local","command":["rogue-mcp"]}}' \
    "$EXPECT_PERMISSIONS_ROOT/output/opencode.json" \
    >"$EXPECT_PERMISSIONS_ROOT/output/opencode.json.tmp" && \
    mv "$EXPECT_PERMISSIONS_ROOT/output/opencode.json.tmp" \
      "$EXPECT_PERMISSIONS_ROOT/output/opencode.json" || return 70

  set +e
  env SENSAI_TEST_PERMISSIONS_INNER=1 SENSAI_TEST_SOURCE_ROOT="$EXPECT_PERMISSIONS_ROOT" \
    "$TEST_RUNNER" permissions --evidence "$EXPECT_PERMISSIONS_EVIDENCE" \
    >"$RUN_TMP/expect-forbidden-mcp-config.out" 2>&1
  EXPECT_PERMISSIONS_RC=$?
  evidence_log_command expected-forbidden-mcp-config \
    "$TEST_RUNNER permissions <isolated-forbidden-mcp-config>" "$EXPECT_PERMISSIONS_RC"
  case "$EXPECT_PERMISSIONS_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_PERMISSIONS_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.forbidden_mcp_exit 1 "$EXPECT_PERMISSIONS_RC" || true
  if test -f "$EXPECT_PERMISSIONS_EVIDENCE/receipt.json"; then
    assert_jq expect.forbidden_mcp_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_PERMISSIONS_EVIDENCE/receipt.json" || true
    assert_jq expect.forbidden_mcp_named_failure \
      '.failed_assertion_ids == ["permissions.forbidden_extension_config"]' \
      "$EXPECT_PERMISSIONS_EVIDENCE/receipt.json" || true
  else
    assert_record expect.forbidden_mcp_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_skill_without_evidence_contract() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_SKILLS_ROOT="$RUN_TMP/expect-skill-without-evidence-source"
  EXPECT_SKILLS_EVIDENCE="$EVIDENCE_DIR/inner-skill-without-evidence"
  skills_core_clone_source "$EXPECT_SKILLS_ROOT" || return 70
  EXPECT_SKILLS_FILE="$EXPECT_SKILLS_ROOT/output/skills/sensai-evidence-first/SKILL.md"
  perl -0pi -e 's/근거 계약:/검증 근거:/' "$EXPECT_SKILLS_FILE" || return 70
  if cmp -s "$SOURCE_ROOT/output/skills/sensai-evidence-first/SKILL.md" "$EXPECT_SKILLS_FILE"; then
    return 70
  fi

  set +e
  env SENSAI_TEST_SOURCE_ROOT="$EXPECT_SKILLS_ROOT" \
    "$TEST_RUNNER" skills-core --evidence "$EXPECT_SKILLS_EVIDENCE" \
    >"$RUN_TMP/expect-skill-without-evidence.out" 2>&1
  EXPECT_SKILLS_RC=$?
  evidence_log_command expected-skill-without-evidence \
    "$TEST_RUNNER skills-core <isolated-skill-without-evidence>" "$EXPECT_SKILLS_RC"
  case "$EXPECT_SKILLS_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_SKILLS_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.skill_without_evidence_exit 1 "$EXPECT_SKILLS_RC" || true
  if test -f "$EXPECT_SKILLS_EVIDENCE/receipt.json"; then
    assert_jq expect.skill_without_evidence_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_SKILLS_EVIDENCE/receipt.json" || true
    assert_jq expect.skill_without_evidence_named_failure \
      '.failed_assertion_ids == ["skills-core.evidence_contract"]' \
      "$EXPECT_SKILLS_EVIDENCE/receipt.json" || true
  else
    assert_record expect.skill_without_evidence_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_unsupported_forced_to_known() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_ANALYSIS_ROOT="$RUN_TMP/expect-unsupported-forced-to-known-source"
  EXPECT_ANALYSIS_EVIDENCE="$EVIDENCE_DIR/inner-unsupported-forced-to-known"
  skills_analysis_clone_source "$EXPECT_ANALYSIS_ROOT" || return 70
  EXPECT_ANALYSIS_FILE="$EXPECT_ANALYSIS_ROOT/output/skills/sensai-stack-discovery/SKILL.md"
  perl -0pi -e 's/`UNSUPPORTED`/`React 18.2`/g' "$EXPECT_ANALYSIS_FILE" || return 70
  if cmp -s "$SOURCE_ROOT/output/skills/sensai-stack-discovery/SKILL.md" "$EXPECT_ANALYSIS_FILE"; then
    return 70
  fi

  set +e
  env SENSAI_TEST_SOURCE_ROOT="$EXPECT_ANALYSIS_ROOT" \
    "$TEST_RUNNER" skills-analysis --evidence "$EXPECT_ANALYSIS_EVIDENCE" \
    >"$RUN_TMP/expect-unsupported-forced-to-known.out" 2>&1
  EXPECT_ANALYSIS_RC=$?
  evidence_log_command expected-unsupported-forced-to-known \
    "$TEST_RUNNER skills-analysis <isolated-unsupported-forced-to-known>" "$EXPECT_ANALYSIS_RC"
  case "$EXPECT_ANALYSIS_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_ANALYSIS_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.unsupported_forced_exit 1 "$EXPECT_ANALYSIS_RC" || true
  if test -f "$EXPECT_ANALYSIS_EVIDENCE/receipt.json"; then
    assert_jq expect.unsupported_forced_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_ANALYSIS_EVIDENCE/receipt.json" || true
    assert_jq expect.unsupported_forced_named_failure \
      '.failed_assertion_ids == ["skills-analysis.unsupported_preservation"]' \
      "$EXPECT_ANALYSIS_EVIDENCE/receipt.json" || true
  else
    assert_record expect.unsupported_forced_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_design_without_binding() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_DELIVERY_ROOT="$RUN_TMP/expect-design-without-binding-source"
  EXPECT_DELIVERY_EVIDENCE="$EVIDENCE_DIR/inner-design-without-binding"
  skills_delivery_clone_source "$EXPECT_DELIVERY_ROOT" || return 70
  EXPECT_DELIVERY_FILE="$EXPECT_DELIVERY_ROOT/output/skills/sensai-change-design/SKILL.md"
  perl -0pi -e 's/`follows_convention_ids`와 `follows_business_ids`/규약 목록과 비즈니스 목록/' \
    "$EXPECT_DELIVERY_FILE" || return 70
  if cmp -s "$SOURCE_ROOT/output/skills/sensai-change-design/SKILL.md" "$EXPECT_DELIVERY_FILE"; then
    return 70
  fi

  set +e
  env SENSAI_TEST_SOURCE_ROOT="$EXPECT_DELIVERY_ROOT" \
    "$TEST_RUNNER" skills-delivery --evidence "$EXPECT_DELIVERY_EVIDENCE" \
    >"$RUN_TMP/expect-design-without-binding.out" 2>&1
  EXPECT_DELIVERY_RC=$?
  evidence_log_command expected-design-without-binding \
    "$TEST_RUNNER skills-delivery <isolated-design-without-binding>" "$EXPECT_DELIVERY_RC"
  case "$EXPECT_DELIVERY_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_DELIVERY_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac

  assert_eq expect.design_without_binding_exit 1 "$EXPECT_DELIVERY_RC" || true
  if test -f "$EXPECT_DELIVERY_EVIDENCE/receipt.json"; then
    assert_jq expect.design_without_binding_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_DELIVERY_EVIDENCE/receipt.json" || true
    assert_jq expect.design_without_binding_named_failure \
      '.failed_assertion_ids == ["skills-delivery.design_binding"]' \
      "$EXPECT_DELIVERY_EVIDENCE/receipt.json" || true
  else
    assert_record expect.design_without_binding_receipt 1 'missing expected-failure receipt' || true
  fi
}

commands_asis_clone_source() {
  COMMANDS_ASIS_CLONE_ROOT=$1
  mkdir -p "$COMMANDS_ASIS_CLONE_ROOT/output/commands" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$COMMANDS_ASIS_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$COMMANDS_ASIS_CLONE_ROOT/tests" || return 70
  cp -R "$SOURCE_ROOT/output/commands/sensai" "$COMMANDS_ASIS_CLONE_ROOT/output/commands/sensai" || return 70
}

run_expected_document_before_analysis() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_COMMAND_ROOT="$RUN_TMP/expect-document-before-analysis-source"
  EXPECT_COMMAND_EVIDENCE="$EVIDENCE_DIR/inner-document-before-analysis"
  commands_asis_clone_source "$EXPECT_COMMAND_ROOT" || return 70
  EXPECT_COMMAND_FILE="$EXPECT_COMMAND_ROOT/output/commands/sensai/document-asis.md"
  perl -0pi -e 's/`F1`과 `F2`/선행 분석/g' "$EXPECT_COMMAND_FILE" || return 70
  if cmp -s "$SOURCE_ROOT/output/commands/sensai/document-asis.md" "$EXPECT_COMMAND_FILE"; then
    return 70
  fi

  set +e
  env SENSAI_TEST_SOURCE_ROOT="$EXPECT_COMMAND_ROOT" \
    "$TEST_RUNNER" commands-asis --evidence "$EXPECT_COMMAND_EVIDENCE" \
    >"$RUN_TMP/expect-document-before-analysis.out" 2>&1
  EXPECT_COMMAND_RC=$?
  evidence_log_command expected-document-before-analysis \
    "$TEST_RUNNER commands-asis <isolated-document-before-analysis>" "$EXPECT_COMMAND_RC"
  case "$EXPECT_COMMAND_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_COMMAND_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.document_before_analysis_exit 1 "$EXPECT_COMMAND_RC" || true
  if test -f "$EXPECT_COMMAND_EVIDENCE/receipt.json"; then
    assert_jq expect.document_before_analysis_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_COMMAND_EVIDENCE/receipt.json" || true
    assert_jq expect.document_before_analysis_named_failure \
      '.failed_assertion_ids == ["commands-asis.document_prerequisites"]' \
      "$EXPECT_COMMAND_EVIDENCE/receipt.json" || true
  else
    assert_record expect.document_before_analysis_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_command_output_outside_mission() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_COMMAND_ROOT="$RUN_TMP/expect-command-output-outside-source"
  EXPECT_COMMAND_EVIDENCE="$EVIDENCE_DIR/inner-command-output-outside"
  commands_asis_clone_source "$EXPECT_COMMAND_ROOT" || return 70
  EXPECT_COMMAND_FILE="$EXPECT_COMMAND_ROOT/output/commands/sensai/analyze.md"
  printf '\n금지된 출력 경로: `/tmp/sensai-output`\n' >>"$EXPECT_COMMAND_FILE" || return 70

  set +e
  env SENSAI_TEST_SOURCE_ROOT="$EXPECT_COMMAND_ROOT" \
    "$TEST_RUNNER" commands-asis --evidence "$EXPECT_COMMAND_EVIDENCE" \
    >"$RUN_TMP/expect-command-output-outside.out" 2>&1
  EXPECT_COMMAND_RC=$?
  evidence_log_command expected-command-output-outside \
    "$TEST_RUNNER commands-asis <isolated-outside-output>" "$EXPECT_COMMAND_RC"
  case "$EXPECT_COMMAND_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_COMMAND_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.command_output_outside_exit 1 "$EXPECT_COMMAND_RC" || true
  if test -f "$EXPECT_COMMAND_EVIDENCE/receipt.json"; then
    assert_jq expect.command_output_outside_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_COMMAND_EVIDENCE/receipt.json" || true
    assert_jq expect.command_output_outside_named_failure \
      '(.failed_assertion_ids | index("commands-asis.output_boundary")) != null' \
      "$EXPECT_COMMAND_EVIDENCE/receipt.json" || true
  else
    assert_record expect.command_output_outside_receipt 1 'missing expected-failure receipt' || true
  fi
}

commands_delivery_clone_source() {
  COMMANDS_DELIVERY_CLONE_ROOT=$1
  mkdir -p "$COMMANDS_DELIVERY_CLONE_ROOT/output/commands" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$COMMANDS_DELIVERY_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$COMMANDS_DELIVERY_CLONE_ROOT/tests" || return 70
  cp -R "$SOURCE_ROOT/output/commands/sensai" "$COMMANDS_DELIVERY_CLONE_ROOT/output/commands/sensai" || return 70
}

run_expected_tobe_before_asis_accept() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_COMMAND_ROOT="$RUN_TMP/expect-tobe-before-asis-accept-source"
  EXPECT_COMMAND_EVIDENCE="$EVIDENCE_DIR/inner-tobe-before-asis-accept"
  commands_delivery_clone_source "$EXPECT_COMMAND_ROOT" || return 70
  EXPECT_COMMAND_FILE="$EXPECT_COMMAND_ROOT/output/commands/sensai/change-design.md"
  perl -0pi -e 's/현재 `source fingerprint`에 결합된 `F3` 사람 승인 상태가 `accepted`여야 한다\./선행 상태를 확인한다./g' \
    "$EXPECT_COMMAND_FILE" || return 70
  if cmp -s "$SOURCE_ROOT/output/commands/sensai/change-design.md" "$EXPECT_COMMAND_FILE"; then
    return 70
  fi

  set +e
  env SENSAI_TEST_SOURCE_ROOT="$EXPECT_COMMAND_ROOT" \
    "$TEST_RUNNER" commands-delivery --evidence "$EXPECT_COMMAND_EVIDENCE" \
    >"$RUN_TMP/expect-tobe-before-asis-accept.out" 2>&1
  EXPECT_COMMAND_RC=$?
  evidence_log_command expected-tobe-before-asis-accept \
    "$TEST_RUNNER commands-delivery <isolated-tobe-before-asis-accept>" "$EXPECT_COMMAND_RC"
  case "$EXPECT_COMMAND_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_COMMAND_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.tobe_before_asis_accept_exit 1 "$EXPECT_COMMAND_RC" || true
  if test -f "$EXPECT_COMMAND_EVIDENCE/receipt.json"; then
    assert_jq expect.tobe_before_asis_accept_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_COMMAND_EVIDENCE/receipt.json" || true
    assert_jq expect.tobe_before_asis_accept_named_failure \
      '.failed_assertion_ids == ["commands-delivery.f3_accepted_precondition"]' \
      "$EXPECT_COMMAND_EVIDENCE/receipt.json" || true
  else
    assert_record expect.tobe_before_asis_accept_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_command_design_without_binding() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_COMMAND_ROOT="$RUN_TMP/expect-command-design-without-binding-source"
  EXPECT_COMMAND_EVIDENCE="$EVIDENCE_DIR/inner-command-design-without-binding"
  commands_delivery_clone_source "$EXPECT_COMMAND_ROOT" || return 70
  EXPECT_COMMAND_FILE="$EXPECT_COMMAND_ROOT/output/commands/sensai/change-design.md"
  perl -0pi -e 's/`follows_convention_ids`와 `follows_business_ids`/양쪽 AS-IS 참조 목록/g' \
    "$EXPECT_COMMAND_FILE" || return 70
  if cmp -s "$SOURCE_ROOT/output/commands/sensai/change-design.md" "$EXPECT_COMMAND_FILE"; then
    return 70
  fi

  set +e
  env SENSAI_TEST_SOURCE_ROOT="$EXPECT_COMMAND_ROOT" \
    "$TEST_RUNNER" commands-delivery --evidence "$EXPECT_COMMAND_EVIDENCE" \
    >"$RUN_TMP/expect-command-design-without-binding.out" 2>&1
  EXPECT_COMMAND_RC=$?
  evidence_log_command expected-command-design-without-binding \
    "$TEST_RUNNER commands-delivery <isolated-command-design-without-binding>" "$EXPECT_COMMAND_RC"
  case "$EXPECT_COMMAND_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_COMMAND_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.command_design_without_binding_exit 1 "$EXPECT_COMMAND_RC" || true
  if test -f "$EXPECT_COMMAND_EVIDENCE/receipt.json"; then
    assert_jq expect.command_design_without_binding_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_COMMAND_EVIDENCE/receipt.json" || true
    assert_jq expect.command_design_without_binding_named_failure \
      '.failed_assertion_ids == ["commands-delivery.design_binding"]' \
      "$EXPECT_COMMAND_EVIDENCE/receipt.json" || true
  else
    assert_record expect.command_design_without_binding_receipt 1 'missing expected-failure receipt' || true
  fi
}

run_expected_wrong_yq_product() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_YQ_ROOT=$RUN_TMP/expect-wrong-yq-source
  EXPECT_YQ_BIN=$RUN_TMP/expect-wrong-yq-bin
  doctor_clone_runtime "$EXPECT_YQ_ROOT" || return 70
  mkdir -p "$EXPECT_YQ_BIN" || return 70
  printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "yq 3.4.3 (Python wrapper)"' \
    >"$EXPECT_YQ_BIN/yq" || return 70
  chmod 755 "$EXPECT_YQ_BIN/yq" || return 70
  tooling_sha256_file "$EXPECT_YQ_ROOT/output/opencode.json" || return 70
  EXPECT_YQ_CONFIG_HASH=$TOOLING_SHA256

  set +e
  PATH="$EXPECT_YQ_BIN:$PATH" SENSAI_PROJECT_ROOT="$EXPECT_YQ_ROOT" \
    "$EXPECT_YQ_ROOT/bin/sensai" doctor tools \
    >"$RUN_TMP/expect-wrong-yq.out" 2>"$RUN_TMP/expect-wrong-yq.err"
  EXPECT_YQ_RC=$?
  evidence_log_command expected-wrong-yq-product \
    './bin/sensai doctor tools <isolated-wrong-yq-product>' "$EXPECT_YQ_RC"
  assert_eq expect.wrong_yq_exit 65 "$EXPECT_YQ_RC" || true
  if rg -q --no-config '^도구 tool=yq status=INVALID reason=tool\.identity_mismatch$' \
       "$RUN_TMP/expect-wrong-yq.err"; then
    assert_record expect.wrong_yq_reason 0 'Mike Farah가 아닌 yq를 제품 식별 오류로 거부한다' || true
  else
    assert_record expect.wrong_yq_reason 1 '잘못된 yq 제품 reason code가 없다' || true
  fi
  tooling_sha256_file "$EXPECT_YQ_ROOT/output/opencode.json" || return 70
  assert_eq expect.wrong_yq_no_config_write "$EXPECT_YQ_CONFIG_HASH" "$TOOLING_SHA256" || true
}

run_expected_existing_install_target() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_INSTALL_ROOT=$RUN_TMP/expect-existing-install
  mkdir -p "$EXPECT_INSTALL_ROOT" || return 70
  EXPECT_INSTALL_ROOT=$(CDPATH= cd -- "$EXPECT_INSTALL_ROOT" 2>/dev/null && pwd -P) || return 70
  EXPECT_INSTALL_TARGET=$EXPECT_INSTALL_ROOT/target
  packaging_run_existing_target_probe "$EXPECT_INSTALL_TARGET" \
    "$RUN_TMP/expect-existing-install.out" "$RUN_TMP/expect-existing-install.err" || return 70
  evidence_log_command expected-existing-install-target \
    './bin/sensai install <existing-temp-target>' "$PACKAGING_EXISTING_RC"
  assert_eq expect.existing_install_exit 73 "$PACKAGING_EXISTING_RC" || true
  assert_eq expect.existing_install_preserved "$PACKAGING_MARKER_BEFORE" "$PACKAGING_MARKER_AFTER" || true
  if rg -q --no-config '^오류 reason=package\.target_exists detail=/' \
       "$RUN_TMP/expect-existing-install.err" && \
     test "$(find "$EXPECT_INSTALL_TARGET" -mindepth 1 ! -type d | wc -l | tr -d ' ')" -eq 1; then
    assert_record expect.existing_install_reason 0 '기존 설치 대상의 semantic failure만 인정했다' || true
  else
    assert_record expect.existing_install_reason 1 '기존 설치 대상 reason 또는 보존 계약 위반' || true
  fi
}

run_expected_staged_byte_drift() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_DRIFT_ROOT=$RUN_TMP/expect-staged-byte-drift-source
  EXPECT_DRIFT_PARENT=$(CDPATH= cd -- "$RUN_TMP" 2>/dev/null && pwd -P) || return 70
  EXPECT_DRIFT_TARGET=$EXPECT_DRIFT_PARENT/expect-staged-byte-drift-target
  packaging_adversarial_clone_source "$EXPECT_DRIFT_ROOT" || return 70
  packaging_adversarial_surface_hash "$EXPECT_DRIFT_ROOT" "$RUN_TMP/expect-drift-before.sha256" || return 70
  read -r EXPECT_DRIFT_BEFORE <"$RUN_TMP/expect-drift-before.sha256" || return 70
  set +e
  env SENSAI_TEST_INTERNAL=1 SENSAI_TEST_PACKAGE_FAULT=staged-byte-drift \
    "$EXPECT_DRIFT_ROOT/bin/sensai" stage "$EXPECT_DRIFT_TARGET" \
    >"$RUN_TMP/expect-staged-byte-drift.out" 2>"$RUN_TMP/expect-staged-byte-drift.err"
  EXPECT_DRIFT_RC=$?
  EXPECT_DRIFT_REASON=$(packaging_adversarial_reason "$RUN_TMP/expect-staged-byte-drift.err") || return 70
  evidence_log_command expected-staged-byte-drift \
    './bin/sensai stage <isolated-staged-byte-drift>' "$EXPECT_DRIFT_RC"
  assert_eq expect.staged_byte_drift_exit 65 "$EXPECT_DRIFT_RC" || true
  assert_eq expect.staged_byte_drift_reason package.stage_hash_mismatch "$EXPECT_DRIFT_REASON" || true
  if ! test -e "$EXPECT_DRIFT_TARGET" && ! test -L "$EXPECT_DRIFT_TARGET"; then
    assert_record expect.staged_byte_drift_target_absent 0 'drift가 있는 stage를 공개하지 않았다' || true
  else
    assert_record expect.staged_byte_drift_target_absent 1 'drift가 있는 부분 target이 공개됐다' || true
  fi
  if packaging_adversarial_no_transaction_artifacts "$RUN_TMP"; then
    assert_record expect.staged_byte_drift_cleanup 0 'drift 실패 뒤 lock과 임시 stage가 정리됐다' || true
  else
    assert_record expect.staged_byte_drift_cleanup 1 'drift 실패 뒤 transaction artifact가 남았다' || true
  fi
  packaging_adversarial_surface_hash "$EXPECT_DRIFT_ROOT" "$RUN_TMP/expect-drift-after.sha256" || return 70
  read -r EXPECT_DRIFT_AFTER <"$RUN_TMP/expect-drift-after.sha256" || return 70
  assert_eq expect.staged_byte_drift_source_unchanged "$EXPECT_DRIFT_BEFORE" "$EXPECT_DRIFT_AFTER" || true
}

run_expected_inherited_config_sentinel() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_OPENCODE_LOAD_EVIDENCE=$EVIDENCE_DIR/inner-inherited-config-sentinel
  set +e
  env SENSAI_TEST_OPENCODE_INHERITED_SENTINEL=1 \
    SENSAI_TEST_SOURCE_ROOT="$SOURCE_ROOT" \
    "$TEST_RUNNER" opencode-load --evidence "$EXPECT_OPENCODE_LOAD_EVIDENCE" \
    >"$RUN_TMP/expect-inherited-config-sentinel.out" \
    2>"$RUN_TMP/expect-inherited-config-sentinel.err"
  EXPECT_OPENCODE_LOAD_RC=$?
  evidence_log_command expected-inherited-config-sentinel \
    "$TEST_RUNNER opencode-load <disposable-inherited-sentinel>" \
    "$EXPECT_OPENCODE_LOAD_RC"
  case "$EXPECT_OPENCODE_LOAD_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_OPENCODE_LOAD_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.inherited_config_sentinel_exit 1 "$EXPECT_OPENCODE_LOAD_RC" || true
  if test -f "$EXPECT_OPENCODE_LOAD_EVIDENCE/receipt.json"; then
    assert_jq expect.inherited_config_sentinel_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_OPENCODE_LOAD_EVIDENCE/receipt.json" || true
    assert_jq expect.inherited_config_sentinel_named_failure \
      '(.failed_assertion_ids | index("opencode-load.inherited_sentinel")) != null' \
      "$EXPECT_OPENCODE_LOAD_EVIDENCE/receipt.json" || true
    assert_jq expect.inherited_config_sentinel_projection \
      '.isolation.inherited_sentinel == true' \
      "$EXPECT_OPENCODE_LOAD_EVIDENCE/safe-projection-pass1.json" || true
  else
    assert_record expect.inherited_config_sentinel_receipt 1 \
      '상속 sentinel expected-failure 영수증이 없다' || true
  fi
}

run_expected_misleading_success_output() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  EXPECT_RELEASE_EVIDENCE=$EVIDENCE_DIR/inner-misleading-success-output
  set +e
  env SENSAI_TEST_PREFLIGHT_FAULT=misleading-success \
    SENSAI_TEST_SOURCE_ROOT="$SOURCE_ROOT" \
    "$TEST_RUNNER" all --evidence "$EXPECT_RELEASE_EVIDENCE" \
    >"$RUN_TMP/expect-misleading-success.out" \
    2>"$RUN_TMP/expect-misleading-success.err"
  EXPECT_RELEASE_RC=$?
  evidence_log_command expected-misleading-success-output \
    "$TEST_RUNNER all <misleading-PASS-output>" "$EXPECT_RELEASE_RC"
  case "$EXPECT_RELEASE_RC" in
    64|70|127)
      RUNNER_INFRA_REASON="EXPECTED_FAILURE_INNER_EXIT_$EXPECT_RELEASE_RC"
      evidence_add_reason "$RUNNER_INFRA_REASON"
      return 70
      ;;
  esac
  assert_eq expect.misleading_success_exit 1 "$EXPECT_RELEASE_RC" || true
  if test -f "$EXPECT_RELEASE_EVIDENCE/receipt.json"; then
    assert_jq expect.misleading_success_result \
      '.result == "ASSERTION_FAILURE" and .exit == 1' \
      "$EXPECT_RELEASE_EVIDENCE/receipt.json" || true
    assert_jq expect.misleading_success_named_failure \
      '.failed_assertion_ids == ["release-preflight.child_exit"]' \
      "$EXPECT_RELEASE_EVIDENCE/receipt.json" || true
    if jq -e '
         .child_exit == 1 and .misleading_text_observed == true
         and .result == "EXPECTED_ASSERTION_FAILURE"
       ' \
         "$EXPECT_RELEASE_EVIDENCE/summary.json" >/dev/null 2>&1; then
      assert_record expect.misleading_success_text_ignored 0 \
        'PASS 문자열보다 exit와 assertion receipt를 우선했다' || true
    else
      assert_record expect.misleading_success_text_ignored 1 \
        'misleading PASS 대립 입력 증거가 불완전하다' || true
    fi
  else
    assert_record expect.misleading_success_receipt 1 \
      'misleading-success expected-failure 영수증이 없다' || true
  fi
}

case "$SELECTOR" in
  all) case_release_preflight || RUNNER_INFRA_REASON=RELEASE_PREFLIGHT_CASE_INFRA ;;
  self) case_self || RUNNER_INFRA_REASON=SELF_CASE_INFRA ;;
  docs) case_docs || RUNNER_INFRA_REASON=DOCS_CASE_INFRA ;;
  fixtures) case_fixtures || RUNNER_INFRA_REASON=FIXTURES_CASE_INFRA ;;
  catalog-oracle) case_catalog_oracle || RUNNER_INFRA_REASON=CATALOG_CASE_INFRA ;;
  schema-trace) case_schema_trace || RUNNER_INFRA_REASON=TRACE_SCHEMA_CASE_INFRA ;;
  schema-progress) case_schema_progress || RUNNER_INFRA_REASON=PROGRESS_SCHEMA_CASE_INFRA ;;
  recipe-trace) case_recipe_trace || RUNNER_INFRA_REASON=TRACE_RECIPE_CASE_INFRA ;;
  provenance) case_provenance || RUNNER_INFRA_REASON=PROVENANCE_CASE_INFRA ;;
  validators) case_validators || RUNNER_INFRA_REASON=VALIDATORS_CASE_INFRA ;;
  config) case_config || RUNNER_INFRA_REASON=CONFIG_CASE_INFRA ;;
  agents) case_agents || RUNNER_INFRA_REASON=AGENTS_CASE_INFRA ;;
  permissions) case_permissions || RUNNER_INFRA_REASON=PERMISSIONS_CASE_INFRA ;;
  skills-core) case_skills_core || RUNNER_INFRA_REASON=SKILLS_CORE_CASE_INFRA ;;
  skills-analysis) case_skills_analysis || RUNNER_INFRA_REASON=SKILLS_ANALYSIS_CASE_INFRA ;;
  skills-delivery) case_skills_delivery || RUNNER_INFRA_REASON=SKILLS_DELIVERY_CASE_INFRA ;;
  commands-asis|commands-analysis) case_commands_asis || RUNNER_INFRA_REASON=COMMANDS_ASIS_CASE_INFRA ;;
  commands-delivery) case_commands_delivery || RUNNER_INFRA_REASON=COMMANDS_DELIVERY_CASE_INFRA ;;
  commands-orchestration) case_commands_orchestration || RUNNER_INFRA_REASON=COMMANDS_ORCHESTRATION_CASE_INFRA ;;
  doctor) doctor_run || RUNNER_INFRA_REASON=DOCTOR_CASE_INFRA ;;
  packaging) case_packaging || RUNNER_INFRA_REASON=PACKAGING_CASE_INFRA ;;
  packaging-adversarial) case_packaging_adversarial || RUNNER_INFRA_REASON=PACKAGING_ADVERSARIAL_CASE_INFRA ;;
  e2e-asis) case_e2e_asis || RUNNER_INFRA_REASON=E2E_ASIS_CASE_INFRA ;;
  e2e-tobe) case_e2e_tobe || RUNNER_INFRA_REASON=E2E_TOBE_CASE_INFRA ;;
  continuity) case_continuity || RUNNER_INFRA_REASON=CONTINUITY_CASE_INFRA ;;
  opencode-load) case_opencode_load || RUNNER_INFRA_REASON=OPENCODE_LOAD_CASE_INFRA ;;
  core-readiness) case_core_readiness ;;
  expect-fail)
    case "$EXPECTED_CASE" in
      core-not-ready) run_expected_core_not_ready; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      fixture-without-golden) run_expected_fixture_without_golden; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      extra-skill) run_expected_extra_skill; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      trace-dangling-id) run_expected_trace_dangling_id; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      mission-path-traversal) run_expected_mission_path_traversal; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      evidence-free-glossary) run_expected_evidence_free_glossary; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      mismatched-mermaid-source) run_expected_mismatched_mermaid_source; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      validator-noop) run_expected_validator_noop; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      config-claims-live-admission) run_expected_config_claims_live_admission; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      peer-edit-enabled) run_expected_peer_edit_enabled; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      forbidden-mcp-config) run_expected_forbidden_mcp_config; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      skill-without-evidence-contract) run_expected_skill_without_evidence_contract; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      unsupported-forced-to-known) run_expected_unsupported_forced_to_known; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      design-without-binding) run_expected_design_without_binding; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      document-before-analysis) run_expected_document_before_analysis; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      command-output-outside-mission) run_expected_command_output_outside_mission; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      tobe-before-asis-accept) run_expected_tobe_before_asis_accept; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      command-design-without-binding) run_expected_command_design_without_binding; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      stale-resume-hash) run_expected_stale_resume_hash; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      wrong-yq-product) run_expected_wrong_yq_product; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      existing-install-target) run_expected_existing_install_target; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      staged-byte-drift) run_expected_staged_byte_drift; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      asis-golden-drift) run_expected_asis_golden_drift; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      conflict-hidden-by-deliverable) run_expected_conflict_hidden_by_deliverable; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      concurrent-mission-writer) run_expected_concurrent_mission_writer; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      inherited-config-sentinel) run_expected_inherited_config_sentinel; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      misleading-success-output) run_expected_misleading_success_output; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      stale-catalog-doc) run_expected_stale_catalog_doc; EXPECT_DISPATCH_RC=$?; test "$EXPECT_DISPATCH_RC" -eq 70 && RUNNER_INFRA_REASON=EXPECTED_FAILURE_INFRA ;;
      *) usage >&2; exit "$EX_USAGE" ;;
    esac
    ;;
  __assertion-probe)
    CASE_TOTAL=$((CASE_TOTAL + 1))
    assert_eq self.intentional 0 1 || true
    ;;
  __pass-probe|__fingerprint-probe)
    CASE_TOTAL=$((CASE_TOTAL + 1))
    assert_dir self.source_root "$SOURCE_ROOT" || true
    ;;
  __misleading-probe)
    CASE_TOTAL=$((CASE_TOTAL + 1))
    printf 'PASS misleading text must not override exit\n'
    assert_eq self.misleading 0 1 || true
    ;;
  __empty-probe)
    :
    ;;
esac

if test -n "$RUNNER_INFRA_REASON"; then
  evidence_add_reason "$RUNNER_INFRA_REASON"
  finish_runner "$EX_INFRA" INFRASTRUCTURE_ERROR
fi
if test "$CASE_TOTAL" -eq 0; then
  RUNNER_INFRA_REASON=ZERO_CASE_DISCOVERY
  evidence_add_reason "$RUNNER_INFRA_REASON"
  finish_runner "$EX_INFRA" INFRASTRUCTURE_ERROR
fi
if test "$ASSERT_TOTAL" -eq 0; then
  RUNNER_INFRA_REASON=ZERO_ASSERTION_DISCOVERY
  evidence_add_reason "$RUNNER_INFRA_REASON"
  finish_runner "$EX_INFRA" INFRASTRUCTURE_ERROR
fi
if test "$ASSERT_FAILED" -gt 0; then
  finish_runner 1 ASSERTION_FAILURE
fi
finish_runner 0 PASS
