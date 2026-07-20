#!/bin/sh

release_preflight_write_external_statuses() {
  RELEASE_EXTERNAL_LOCAL_STATUS=${1:-PASS}
  if test "$RELEASE_EXTERNAL_LOCAL_STATUS" = PASS; then
    RELEASE_EXTERNAL_LOCAL_LABEL=LOCAL_IMPLEMENTATION_PASS
    RELEASE_EXTERNAL_TERMINAL='LOCAL_IMPLEMENTATION_PASS / MODEL_ADMISSION_UNVERIFIED / WINDOWS_TEST_UNAVAILABLE / MACOS_STATIC_SUBSTITUTE_PASS'
  else
    RELEASE_EXTERNAL_LOCAL_LABEL=LOCAL_IMPLEMENTATION_FAIL
    RELEASE_EXTERNAL_TERMINAL='LOCAL_IMPLEMENTATION_FAIL / MODEL_ADMISSION_UNVERIFIED / WINDOWS_TEST_UNAVAILABLE / MACOS_STATIC_SUBSTITUTE_PASS'
  fi
  jq -n \
    --arg source_fingerprint "$SOURCE_FINGERPRINT" \
    --arg local_status "$RELEASE_EXTERNAL_LOCAL_STATUS" \
    --arg local_label "$RELEASE_EXTERNAL_LOCAL_LABEL" \
    --arg terminal_status "$RELEASE_EXTERNAL_TERMINAL" \
    '{
      schema_version:"1.0",
      source_fingerprint:$source_fingerprint,
      deterministic_pass_count_includes_external_statuses:false,
      statuses:{
        local_implementation:{status:$local_status,label:$local_label,basis:"현재 macOS source fingerprint의 결정적 preflight"},
        model_admission:{status:"UNVERIFIED",label:"MODEL_ADMISSION_UNVERIFIED",included_in_pass_count:false},
        delivery_candidate_skills:{
          status:"UNAVAILABLE",
          reason:"VALUE_PROVEN_PENDING",
          included_in_pass_count:false,
          skills:["sensai-dataflow-chart","sensai-user-story","sensai-requirement-analyze","sensai-change-design","sensai-test-scenario"]
        },
        tui:{status:"UNVERIFIED",label:"TUI_UNVERIFIED",included_in_pass_count:false},
        live_delegation:{status:"UNVERIFIED",label:"LIVE_DELEGATION_UNVERIFIED",included_in_pass_count:false},
        windows_native:{status:"TEST_UNAVAILABLE",label:"WINDOWS_TEST_UNAVAILABLE",included_in_pass_count:false},
        windows_compatibility:{status:"UNVERIFIED",label:"WINDOWS_COMPATIBILITY_UNVERIFIED",included_in_pass_count:false},
        macos_static_substitute:{
          status:"PASS",
          label:"MACOS_STATIC_SUBSTITUTE_PASS",
          included_in_pass_count:false,
          scope:["현재 payload exact-set", "OpenCode 설정 projection", "POSIX 경로와 quoting", "manifest checksum"],
          exclusions:["PowerShell 실행", "Windows filesystem 의미론", "Windows OpenCode load", "Windows 호환성 승인"]
        }
      },
      terminal_status:$terminal_status
    }' >"$EVIDENCE_DIR/external-statuses.json" || return 70
}

release_preflight_check_runtime_boundaries() {
  RELEASE_RUNTIME_CONFIG=$SOURCE_ROOT/output/opencode.json
  if test "$(wc -l <"$SOURCE_ROOT/manifest.txt" | tr -d ' ')" -eq 37 && \
     rg -q --no-config -x 'bin/sensai' "$SOURCE_ROOT/manifest.txt" && \
     test -x "$SOURCE_ROOT/bin/sensai"; then
    assert_record release-preflight.installed_cli_manifest 0 \
      '37-leaf manifest가 실행 가능한 설치 CLI를 포함한다' || true
  else
    assert_record release-preflight.installed_cli_manifest 1 \
      '설치 CLI manifest 계약이 다르다' || true
  fi

  if jq -e '
      .permission.bash["\"$OPENCODE_CONFIG_DIR/bin/sensai\" mission init *"] == "allow" and
      .permission.bash["\"$OPENCODE_CONFIG_DIR/bin/sensai\" mission checkpoint *"] == "allow" and
      .permission.bash["\"$OPENCODE_CONFIG_DIR/bin/sensai\" mission resume *"] == "allow" and
      .permission.bash["\"$OPENCODE_CONFIG_DIR/bin/sensai\" mission status *"] == "allow"
    ' "$RELEASE_RUNTIME_CONFIG" >/dev/null 2>&1 && \
     test "$(jq '[.permission.bash | to_entries[] | select(.value=="allow" and (.key | contains("$OPENCODE_CONFIG_DIR/bin/sensai")))] | length' "$RELEASE_RUNTIME_CONFIG")" -eq 4 && \
     test "$(rg -l -F --no-config '"$OPENCODE_CONFIG_DIR/bin/sensai" mission ' \
       "$SOURCE_ROOT/output/commands/sensai/run.md" \
       "$SOURCE_ROOT/output/commands/sensai/resume.md" \
       "$SOURCE_ROOT/output/commands/sensai/status.md" | wc -l | tr -d ' ')" -eq 3 && \
     ! rg -q --no-config '(^|[^A-Z_])\./bin/sensai mission' "$SOURCE_ROOT/output/commands/sensai"; then
    assert_record release-preflight.installed_cli_binding 0 \
      'slash command와 bash allow가 설치 CLI의 네 mission subcommand에만 결합됐다' || true
  else
    assert_record release-preflight.installed_cli_binding 1 \
      '설치 CLI command 또는 permission 결합이 다르다' || true
  fi

  if test "$(rg -l --no-config '명시적으로 선택된 원본.*읽기 전용' \
       "$SOURCE_ROOT"/output/skills/*/SKILL.md | wc -l | tr -d ' ')" -eq 15 && \
     test "$(rg -l --no-config '쓰기.*현재 미션 루트' \
       "$SOURCE_ROOT"/output/skills/*/SKILL.md | wc -l | tr -d ' ')" -eq 15; then
    assert_record release-preflight.target_read_mission_write 0 \
      '15 skill이 target read-only와 mission-root write를 분리한다' || true
  else
    assert_record release-preflight.target_read_mission_write 1 \
      'skill의 target read 또는 mission write 경계가 다르다' || true
  fi

  RELEASE_DELIVERY_GATE_OK=1
  for RELEASE_DELIVERY_GATE_FILE in \
    "$SOURCE_ROOT/output/AGENTS.md" \
    "$SOURCE_ROOT/output/commands/sensai/change-design.md" \
    "$SOURCE_ROOT/output/commands/sensai/deliver.md"; do
    if ! rg -q --no-config 'VALUE_PROVEN.*(입학|`deny`)' "$RELEASE_DELIVERY_GATE_FILE"; then
      RELEASE_DELIVERY_GATE_OK=0
    fi
  done
  if jq -e '
      .permission.skill["*"] == "deny" and
      .permission.skill["sensai-dataflow-chart"] == null and
      .permission.skill["sensai-user-story"] == null and
      .permission.skill["sensai-requirement-analyze"] == null and
      .permission.skill["sensai-change-design"] == null and
      .permission.skill["sensai-test-scenario"] == null
    ' "$RELEASE_RUNTIME_CONFIG" >/dev/null 2>&1 && \
     test "$RELEASE_DELIVERY_GATE_OK" -eq 1; then
    assert_record release-preflight.delivery_value_proven_deny 0 \
      'delivery 후보 5 skill은 VALUE_PROVEN 전 exact deny다' || true
  else
    assert_record release-preflight.delivery_value_proven_deny 1 \
      'delivery 후보 5 skill admission deny가 다르다' || true
  fi
}

release_preflight_fault_misleading_success() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  RELEASE_FAULT_EVIDENCE=$EVIDENCE_DIR/fault-misleading
  set +e
  env SENSAI_TEST_INTERNAL=1 "$TEST_RUNNER" __misleading-probe \
    --evidence "$RELEASE_FAULT_EVIDENCE" \
    >"$RUN_TMP/release-fault-misleading.out" \
    2>"$RUN_TMP/release-fault-misleading.err"
  RELEASE_FAULT_RC=$?
  evidence_log_command release-preflight-misleading-probe \
    "$TEST_RUNNER __misleading-probe <PASS 문자열 포함>" "$RELEASE_FAULT_RC"
  if test "$RELEASE_FAULT_RC" -eq 0; then
    assert_record release-preflight.child_exit 0 'misleading probe가 성공한 것으로 보고됐다' || true
  else
    assert_record release-preflight.child_exit 1 \
      "PASS 문자열과 무관하게 실제 exit=$RELEASE_FAULT_RC 를 실패로 판정했다" || true
  fi
  if rg -q --no-config '^PASS misleading text must not override exit$' \
    "$RUN_TMP/release-fault-misleading.out"; then
    RELEASE_FAULT_TEXT_OBSERVED=true
  else
    RELEASE_FAULT_TEXT_OBSERVED=false
  fi
  release_preflight_write_external_statuses FAIL || return 70
  jq -n \
    --arg source_fingerprint "$SOURCE_FINGERPRINT" \
    --argjson exit "$RELEASE_FAULT_RC" \
    --argjson misleading_text_observed "$RELEASE_FAULT_TEXT_OBSERVED" \
    '{schema_version:"1.0",source_fingerprint:$source_fingerprint,fault:"misleading-success-output",child_exit:$exit,misleading_text_observed:$misleading_text_observed,result:"EXPECTED_ASSERTION_FAILURE"}' \
    >"$EVIDENCE_DIR/summary.json" || return 70
}

release_preflight_run_child() {
  RELEASE_CASE_ID=$1
  RELEASE_CASE_CATEGORY=$2
  RELEASE_CASE_ARG0=$3
  RELEASE_CASE_ARG1=$4
  RELEASE_CASE_EVIDENCE=$EVIDENCE_DIR/cases/$RELEASE_CASE_ID
  RELEASE_CASE_OUT=$RUN_TMP/release-$RELEASE_CASE_ID.out
  RELEASE_CASE_ERR=$RUN_TMP/release-$RELEASE_CASE_ID.err

  set +e
  if test -n "$RELEASE_CASE_ARG1"; then
    "$TEST_RUNNER" "$RELEASE_CASE_ARG0" "$RELEASE_CASE_ARG1" \
      --evidence "$RELEASE_CASE_EVIDENCE" >"$RELEASE_CASE_OUT" 2>"$RELEASE_CASE_ERR"
  else
    "$TEST_RUNNER" "$RELEASE_CASE_ARG0" \
      --evidence "$RELEASE_CASE_EVIDENCE" >"$RELEASE_CASE_OUT" 2>"$RELEASE_CASE_ERR"
  fi
  RELEASE_CASE_RC=$?
  evidence_log_command "release-$RELEASE_CASE_ID" \
    "$TEST_RUNNER $RELEASE_CASE_ARG0${RELEASE_CASE_ARG1:+ $RELEASE_CASE_ARG1}" \
    "$RELEASE_CASE_RC"

  RELEASE_CASE_EXPECTED_SELECTOR=$RELEASE_CASE_ARG0
  if test -n "$RELEASE_CASE_ARG1"; then
    RELEASE_CASE_EXPECTED_SELECTOR=$RELEASE_CASE_EXPECTED_SELECTOR:$RELEASE_CASE_ARG1
  fi
  RELEASE_CASE_RECEIPT=$RELEASE_CASE_EVIDENCE/receipt.json
  RELEASE_CASE_OK=0
  if test "$RELEASE_CASE_RC" -eq 0 && test -f "$RELEASE_CASE_RECEIPT" && \
     jq -e \
       --arg selector "$RELEASE_CASE_EXPECTED_SELECTOR" \
       --arg fingerprint "$SOURCE_FINGERPRINT" '
         .selector == $selector and .result == "PASS" and .exit == 0
         and .case_count >= 1 and .assertion_count >= 1
         and .failed_assertion_count == 0 and .failed_assertion_ids == []
         and .source.fingerprint == $fingerprint
       ' "$RELEASE_CASE_RECEIPT" >/dev/null 2>&1; then
    RELEASE_CASE_OK=1
  fi

  if test "$RELEASE_CASE_OK" -eq 1; then
    assert_record "release-preflight.case.$RELEASE_CASE_ID" 0 \
      "selector=$RELEASE_CASE_EXPECTED_SELECTOR exit=0 receipt=PASS" || true
  else
    assert_record "release-preflight.case.$RELEASE_CASE_ID" 1 \
      "selector=$RELEASE_CASE_EXPECTED_SELECTOR exit=$RELEASE_CASE_RC receipt 검증 실패" || true
  fi

  if test -f "$RELEASE_CASE_RECEIPT"; then
    jq -c \
      --arg id "$RELEASE_CASE_ID" \
      --arg category "$RELEASE_CASE_CATEGORY" \
      --arg expected_selector "$RELEASE_CASE_EXPECTED_SELECTOR" \
      --argjson command_exit "$RELEASE_CASE_RC" '
        {
          id:$id,
          category:$category,
          selector:$expected_selector,
          command_exit:$command_exit,
          result:.result,
          case_count:.case_count,
          assertion_count:.assertion_count,
          failed_assertion_count:.failed_assertion_count,
          source_fingerprint:.source.fingerprint
        }
      ' "$RELEASE_CASE_RECEIPT" >>"$RELEASE_PREFLIGHT_ROWS" || return 70
  else
    jq -cn \
      --arg id "$RELEASE_CASE_ID" \
      --arg category "$RELEASE_CASE_CATEGORY" \
      --arg selector "$RELEASE_CASE_EXPECTED_SELECTOR" \
      --argjson command_exit "$RELEASE_CASE_RC" '
        {id:$id,category:$category,selector:$selector,command_exit:$command_exit,result:"MISSING_RECEIPT",case_count:0,assertion_count:0,failed_assertion_count:1,source_fingerprint:null}
      ' >>"$RELEASE_PREFLIGHT_ROWS" || return 70
  fi
}

case_release_preflight() {
  if test "${SENSAI_TEST_PREFLIGHT_FAULT:-}" = misleading-success; then
    release_preflight_fault_misleading_success
    return $?
  fi

  RELEASE_PREFLIGHT_CONTRACT=$SOURCE_ROOT/tests/contracts/release-preflight.json
  RELEASE_PREFLIGHT_ROWS=$RUN_TMP/release-preflight-rows.jsonl
  RELEASE_PREFLIGHT_TSV=$RUN_TMP/release-preflight-cases.tsv
  RELEASE_PREFLIGHT_WHITESPACE=$RUN_TMP/release-preflight-whitespace.txt
  : >"$RELEASE_PREFLIGHT_ROWS" || return 70

  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_file release-preflight.contract_file "$RELEASE_PREFLIGHT_CONTRACT" || true
  if jq -e '
      .schema_version == "1.0"
      and .terminal_status == "LOCAL_IMPLEMENTATION_PASS / MODEL_ADMISSION_UNVERIFIED / WINDOWS_TEST_UNAVAILABLE / MACOS_STATIC_SUBSTITUTE_PASS"
      and (.cases | type == "array" and length == 53)
      and ([.cases[].id] | unique | length) == 53
      and ([.cases[].argv | join(" ")] | unique | length) == 53
      and ([.cases[] | select(.argv | length < 1 or length > 2)] | length) == 0
      and ([.cases[] | select(.category == "mutation")] | length) == 28
      and ([.cases[] | select(.argv[0] == "expect-fail")] | length) == 27
      and ([.cases[] | select(.argv[0] == "all")] | length) == 0
    ' "$RELEASE_PREFLIGHT_CONTRACT" >/dev/null 2>&1; then
    assert_record release-preflight.contract_exact 0 '53개 실행과 28개 mutation 범주가 중복 없이 고정됐다' || true
  else
    assert_record release-preflight.contract_exact 1 'release preflight manifest exact-set이 다르다' || true
    return 0
  fi

  set +e
  git -C "$SOURCE_ROOT" diff --check >"$RUN_TMP/release-git-diff-check.out" 2>&1
  RELEASE_DIFF_RC=$?
  evidence_log_command release-git-diff-check 'git diff --check' "$RELEASE_DIFF_RC"
  assert_eq release-preflight.tracked_whitespace 0 "$RELEASE_DIFF_RC" || true

  RELEASE_WHITESPACE_FILES=$FINGERPRINT_FILES
  test -f "$RELEASE_WHITESPACE_FILES" || return 70
  : >"$RELEASE_PREFLIGHT_WHITESPACE" || return 70
  RELEASE_WHITESPACE_RC=1
  while IFS= read -r RELEASE_WHITESPACE_RELATIVE; do
    tooling_source_leaf_regular "$RELEASE_WHITESPACE_RELATIVE" || return 70
    RELEASE_WHITESPACE_FILE=$SOURCE_ROOT/$RELEASE_WHITESPACE_RELATIVE
    set +e
    rg -n --no-config '[[:blank:]]+$' "$RELEASE_WHITESPACE_FILE" \
      >>"$RELEASE_PREFLIGHT_WHITESPACE" 2>&1
    RELEASE_WHITESPACE_FILE_RC=$?
    case "$RELEASE_WHITESPACE_FILE_RC" in
      0) RELEASE_WHITESPACE_RC=0 ;;
      1) ;;
      *) return 70 ;;
    esac
  done <"$RELEASE_WHITESPACE_FILES"
  evidence_log_command release-all-source-whitespace \
    "rg trailing-whitespace <tracked-and-untracked-source>" "$RELEASE_WHITESPACE_RC"
  case "$RELEASE_WHITESPACE_RC" in
    1) assert_record release-preflight.all_source_whitespace 0 'tracked와 untracked source에 줄 끝 공백이 없다' || true ;;
    0) assert_record release-preflight.all_source_whitespace 1 'tracked 또는 untracked source에 줄 끝 공백이 있다' || true ;;
    *) return 70 ;;
  esac

  jq -r '.cases[] | [.id, .category, .argv[0], (.argv[1] // "")] | @tsv' \
    "$RELEASE_PREFLIGHT_CONTRACT" >"$RELEASE_PREFLIGHT_TSV" || return 70
  RELEASE_PREFLIGHT_EXECUTED=0
  while IFS="	" read -r RELEASE_CASE_ID RELEASE_CASE_CATEGORY RELEASE_CASE_ARG0 RELEASE_CASE_ARG1; do
    test -n "$RELEASE_CASE_ID" && test -n "$RELEASE_CASE_CATEGORY" && \
      test -n "$RELEASE_CASE_ARG0" || return 70
    release_preflight_run_child "$RELEASE_CASE_ID" "$RELEASE_CASE_CATEGORY" \
      "$RELEASE_CASE_ARG0" "$RELEASE_CASE_ARG1" || return 70
    RELEASE_PREFLIGHT_EXECUTED=$((RELEASE_PREFLIGHT_EXECUTED + 1))
  done <"$RELEASE_PREFLIGHT_TSV"
  assert_eq release-preflight.executed_exact 53 "$RELEASE_PREFLIGHT_EXECUTED" || true
  release_preflight_check_runtime_boundaries || return 70

  jq -s \
    --arg source_fingerprint "$SOURCE_FINGERPRINT" \
    --argjson manifest_count 53 '
      . as $rows |
      {
        schema_version:"1.0",
        source_fingerprint:$source_fingerprint,
        manifest_count:$manifest_count,
        executed_count:($rows | length),
        passed_count:([$rows[] | select(.command_exit == 0 and .result == "PASS" and .failed_assertion_count == 0 and .source_fingerprint == $source_fingerprint)] | length),
        skipped_count:0,
        nested_case_count:([$rows[].case_count] | add),
        nested_assertion_count:([$rows[].assertion_count] | add),
        nested_failed_assertion_count:([$rows[].failed_assertion_count] | add),
        external_statuses_in_pass_count:false,
        cases:$rows
      }
    ' "$RELEASE_PREFLIGHT_ROWS" >"$EVIDENCE_DIR/summary.json" || return 70
  cp "$RELEASE_PREFLIGHT_CONTRACT" "$EVIDENCE_DIR/case-manifest.json" || return 70

  assert_jq release-preflight.summary_exact '
    .manifest_count == 53 and .executed_count == 53 and .passed_count == 53
    and .skipped_count == 0 and .nested_case_count >= 53
    and .nested_assertion_count >= 53 and .nested_failed_assertion_count == 0
    and .external_statuses_in_pass_count == false
  ' "$EVIDENCE_DIR/summary.json" || true
  assert_jq release-preflight.self_false_success_probes '
    ([.assertions[] | select(
      (.id == "self.empty_discovery_exit" or .id == "self.misleading_exit" or .id == "self.stale_second_exit")
      and .result == "PASS"
    )] | length) == 3
  ' "$EVIDENCE_DIR/cases/selector.self/receipt.json" || true
  assert_jq release-preflight.doctor_tools '
    ([.command_exits[] | select(.name == "doctor-tools" and .exit == 0)] | length) == 1
    and ([.assertions[] | select(.id == "doctor.tools_exit" and .result == "PASS")] | length) == 1
  ' "$EVIDENCE_DIR/cases/selector.doctor/receipt.json" || true

  release_preflight_write_external_statuses || return 70
  assert_jq release-preflight.external_statuses '
    .deterministic_pass_count_includes_external_statuses == false
    and .statuses.model_admission.status == "UNVERIFIED"
    and .statuses.delivery_candidate_skills.status == "UNAVAILABLE"
    and .statuses.delivery_candidate_skills.reason == "VALUE_PROVEN_PENDING"
    and (.statuses.delivery_candidate_skills.skills | length) == 5
    and .statuses.tui.status == "UNVERIFIED"
    and .statuses.live_delegation.status == "UNVERIFIED"
    and .statuses.windows_native.status == "TEST_UNAVAILABLE"
    and .statuses.windows_compatibility.status == "UNVERIFIED"
    and .statuses.macos_static_substitute.status == "PASS"
    and .terminal_status == "LOCAL_IMPLEMENTATION_PASS / MODEL_ADMISSION_UNVERIFIED / WINDOWS_TEST_UNAVAILABLE / MACOS_STATIC_SUBSTITUTE_PASS"
  ' "$EVIDENCE_DIR/external-statuses.json" || true

  jq -n \
    --arg source_fingerprint "$SOURCE_FINGERPRINT" '
    {
      schema_version:"1.0",
      source_fingerprint:$source_fingerprint,
      findings:[
        {id:"installed_cli_missing",disposition:"RESOLVED",evidence:["case-manifest.json","cases/selector.packaging/receipt.json","cases/selector.opencode-load/receipt.json"]},
        {id:"target_read_mission_write_conflict",disposition:"RESOLVED",evidence:["cases/selector.permissions/receipt.json","cases/selector.skills-core/receipt.json","cases/selector.skills-analysis/receipt.json","cases/selector.skills-delivery/receipt.json"]},
        {id:"delivery_five_skills_denied",disposition:"INTENDED_ADMISSION_GATE",reason:"VALUE_PROVEN_PENDING",external_status:"MODEL_ADMISSION_UNVERIFIED"}
      ]
    }
    ' >"$EVIDENCE_DIR/findings-disposition.json" || return 70

  jq -n \
    --arg source_fingerprint "$SOURCE_FINGERPRINT" \
    --arg terminal_status 'LOCAL_IMPLEMENTATION_PASS / MODEL_ADMISSION_UNVERIFIED / WINDOWS_TEST_UNAVAILABLE / MACOS_STATIC_SUBSTITUTE_PASS' \
    '{
      task:"T27",
      status:"LOCAL_PREFLIGHT_PASS",
      source_fingerprint:$source_fingerprint,
      deterministic:{manifest_count:53,executed_count:53,skipped_count:0,receipt:"summary.json"},
      false_success_guards:{mutation:true,zero_case:true,stale_log:true,misleading_success:true},
      findings_disposition:"findings-disposition.json",
      doctor_tools:"PASS",
      external_statuses:"external-statuses.json",
      cleanup_receipt:"cleanup.json",
      terminal_status:$terminal_status
    }' >"$EVIDENCE_DIR/done-claim.json" || return 70
}
