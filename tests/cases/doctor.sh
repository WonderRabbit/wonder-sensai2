#!/bin/sh

doctor_run() {
  DOCTOR_CLI=$SOURCE_ROOT/bin/sensai
  DOCTOR_BASE=$RUN_TMP/doctor
  DOCTOR_PROJECT=$DOCTOR_BASE/project
  mkdir -p "$DOCTOR_PROJECT/input" || return 70
  cp "$SOURCE_ROOT/README.md" "$DOCTOR_PROJECT/input/README.md" || return 70

  CASE_TOTAL=$((CASE_TOTAL + 1))
  assert_file doctor.cli_regular "$DOCTOR_CLI" || true
  if test -x "$DOCTOR_CLI"; then
    assert_record doctor.cli_executable 0 'bin/sensai가 실행 가능하다' || true
  else
    assert_record doctor.cli_executable 1 'bin/sensai 실행 비트가 없다' || true
  fi
  if sh -n "$DOCTOR_CLI"; then
    assert_record doctor.posix_syntax 0 'POSIX shell 문법이 유효하다' || true
  else
    assert_record doctor.posix_syntax 1 'POSIX shell 문법이 유효하지 않다' || true
  fi

  set +e
  "$DOCTOR_CLI" help >"$DOCTOR_BASE/help.out" 2>"$DOCTOR_BASE/help.err"
  DOCTOR_HELP_RC=$?
  "$DOCTOR_CLI" unknown >"$DOCTOR_BASE/usage.out" 2>"$DOCTOR_BASE/usage.err"
  DOCTOR_USAGE_RC=$?
  "$DOCTOR_CLI" doctor tools >"$DOCTOR_BASE/tools.out" 2>"$DOCTOR_BASE/tools.err"
  DOCTOR_TOOLS_RC=$?
  "$DOCTOR_CLI" doctor models >"$DOCTOR_BASE/models.out" 2>"$DOCTOR_BASE/models.err"
  DOCTOR_MODELS_RC=$?
  evidence_log_command doctor-help './bin/sensai help' "$DOCTOR_HELP_RC"
  evidence_log_command doctor-usage './bin/sensai unknown' "$DOCTOR_USAGE_RC"
  evidence_log_command doctor-tools './bin/sensai doctor tools' "$DOCTOR_TOOLS_RC"
  evidence_log_command doctor-models './bin/sensai doctor models' "$DOCTOR_MODELS_RC"
  assert_eq doctor.help_exit 0 "$DOCTOR_HELP_RC" || true
  assert_eq doctor.usage_exit 64 "$DOCTOR_USAGE_RC" || true
  assert_eq doctor.tools_exit 0 "$DOCTOR_TOOLS_RC" || true
  assert_eq doctor.models_exit 0 "$DOCTOR_MODELS_RC" || true

  if rg -q --no-config '^사용법:$' "$DOCTOR_BASE/help.out" && \
     rg -q --no-config '^  0   성공$' "$DOCTOR_BASE/help.out" && \
     rg -q --no-config '^  64  사용법 오류$' "$DOCTOR_BASE/help.out" && \
     rg -q --no-config '^  65  입력·설정·제품 식별 오류$' "$DOCTOR_BASE/help.out" && \
     rg -q --no-config '^  69  필수 도구 또는 transport 사용 불가$' "$DOCTOR_BASE/help.out" && \
     rg -q --no-config '^  75  잠금·revision·hash 충돌' "$DOCTOR_BASE/help.out"; then
    assert_record doctor.help_contract 0 '한국어 help와 0/64/65/69/75 계약이 있다' || true
  else
    assert_record doctor.help_contract 1 'help 또는 종료 코드 계약이 빠졌다' || true
  fi

  DOCTOR_EXPECTED_TOOLS=$DOCTOR_BASE/expected-tools.txt
  printf '%s\n' opencode fd rg sg jq yq mdq mmdc >"$DOCTOR_EXPECTED_TOOLS" || return 70
  sed -n 's/^도구 tool=\([^ ]*\) status=READY .*/\1/p' "$DOCTOR_BASE/tools.out" \
    >"$DOCTOR_BASE/actual-tools.txt" || return 70
  if cmp -s "$DOCTOR_EXPECTED_TOOLS" "$DOCTOR_BASE/actual-tools.txt" && \
     rg -q --no-config '^도구 tool=opencode status=READY product=OpenCode version=1\.18\.3$' "$DOCTOR_BASE/tools.out" && \
     rg -q --no-config '^도구 tool=sg status=READY product=ast-grep ' "$DOCTOR_BASE/tools.out" && \
     rg -q --no-config '^도구 tool=yq status=READY product=MikeFarah-yq ' "$DOCTOR_BASE/tools.out"; then
    assert_record doctor.tool_identity 0 '8개 도구와 OpenCode 1.18.3 제품 식별이 정확하다' || true
  else
    assert_record doctor.tool_identity 1 '도구 exact-set 또는 제품 식별이 다르다' || true
  fi

  if test "$(wc -l <"$DOCTOR_BASE/models.out" | tr -d ' ')" = 3 && \
     sed -n '1p' "$DOCTOR_BASE/models.out" | rg -q --no-config '^모델 discovery=READY reason=model\.config_ready$' && \
     sed -n '2p' "$DOCTOR_BASE/models.out" | rg -q --no-config '^모델 alias=zai/glm-5\.2 admission=UNVERIFIED reason=MODEL_ADMISSION_UNVERIFIED$' && \
     sed -n '3p' "$DOCTOR_BASE/models.out" | rg -q --no-config '^모델 alias=sensai-ollama/qwen3\.5:9b admission=UNVERIFIED reason=MODEL_ADMISSION_UNVERIFIED$'; then
    assert_record doctor.model_statuses 0 'discovery와 두 모델 상태가 READY/UNVERIFIED/UNVERIFIED다' || true
  else
    assert_record doctor.model_statuses 1 '모델 상태 projection이 다르다' || true
  fi
  if ! rg -qi --no-config 'token|credential|authorization|bearer|auth\.json|api[_-]?key=' \
       "$DOCTOR_BASE/tools.out" "$DOCTOR_BASE/tools.err" \
       "$DOCTOR_BASE/models.out" "$DOCTOR_BASE/models.err"; then
    assert_record doctor.no_secret_output 0 'doctor 출력에 자격증명 단서가 없다' || true
  else
    assert_record doctor.no_secret_output 1 'doctor 출력에 자격증명 단서가 있다' || true
  fi

  DOCTOR_ALIAS_ROOT=$DOCTOR_BASE/alias-source
  doctor_clone_runtime "$DOCTOR_ALIAS_ROOT" || return 70
  jq '.model_aliases.lead="zai/wrong-model"' \
    "$DOCTOR_ALIAS_ROOT/output/toolchain.lock.json" >"$DOCTOR_ALIAS_ROOT/output/toolchain.next.json" || return 70
  mv "$DOCTOR_ALIAS_ROOT/output/toolchain.next.json" "$DOCTOR_ALIAS_ROOT/output/toolchain.lock.json" || return 70
  set +e
  "$DOCTOR_ALIAS_ROOT/bin/sensai" doctor models \
    >"$DOCTOR_BASE/alias.out" 2>"$DOCTOR_BASE/alias.err"
  DOCTOR_ALIAS_RC=$?
  evidence_log_command doctor-wrong-alias './bin/sensai doctor models <wrong-alias>' "$DOCTOR_ALIAS_RC"
  assert_eq doctor.alias_exit 65 "$DOCTOR_ALIAS_RC" || true
  if rg -q --no-config 'reason=model\.alias_mismatch' "$DOCTOR_BASE/alias.err"; then
    assert_record doctor.alias_reason 0 'alias 불일치를 data error로 구분한다' || true
  else
    assert_record doctor.alias_reason 1 'alias 불일치 reason code가 없다' || true
  fi

  DOCTOR_TRANSPORT_ROOT=$DOCTOR_BASE/transport-source
  doctor_clone_runtime "$DOCTOR_TRANSPORT_ROOT" || return 70
  jq '.provider["sensai-ollama"].options.baseURL="https://remote.example.invalid/v1"' \
    "$DOCTOR_TRANSPORT_ROOT/output/opencode.json" >"$DOCTOR_TRANSPORT_ROOT/output/opencode.next.json" || return 70
  mv "$DOCTOR_TRANSPORT_ROOT/output/opencode.next.json" "$DOCTOR_TRANSPORT_ROOT/output/opencode.json" || return 70
  set +e
  "$DOCTOR_TRANSPORT_ROOT/bin/sensai" doctor models \
    >"$DOCTOR_BASE/transport.out" 2>"$DOCTOR_BASE/transport.err"
  DOCTOR_TRANSPORT_RC=$?
  evidence_log_command doctor-wrong-transport './bin/sensai doctor models <wrong-transport>' "$DOCTOR_TRANSPORT_RC"
  assert_eq doctor.transport_exit 69 "$DOCTOR_TRANSPORT_RC" || true
  if rg -q --no-config 'reason=model\.transport_unavailable' "$DOCTOR_BASE/transport.err"; then
    assert_record doctor.transport_reason 0 'transport 불일치를 unavailable로 구분한다' || true
  else
    assert_record doctor.transport_reason 1 'transport 불일치 reason code가 없다' || true
  fi

  if ! rg -q --no-config 'auth\.json|credentials|curl|/models|cat .*auth' "$DOCTOR_CLI"; then
    assert_record doctor.no_credential_or_model_call 0 'CLI는 자격증명과 model endpoint를 읽거나 호출하지 않는다' || true
  else
    assert_record doctor.no_credential_or_model_call 1 'CLI에 자격증명 또는 model endpoint 접근이 있다' || true
  fi

  CASE_TOTAL=$((CASE_TOTAL + 1))
  set +e
  SENSAI_PROJECT_ROOT=$DOCTOR_PROJECT "$DOCTOR_CLI" mission init fixture-mission input '결정적 테스트 목표' \
    >"$DOCTOR_BASE/init.out" 2>"$DOCTOR_BASE/init.err"
  DOCTOR_INIT_RC=$?
  SENSAI_PROJECT_ROOT=$DOCTOR_PROJECT "$DOCTOR_CLI" mission status fixture-mission \
    >"$DOCTOR_BASE/status.out" 2>"$DOCTOR_BASE/status.err"
  DOCTOR_STATUS_RC=$?
  evidence_log_command mission-init './bin/sensai mission init fixture-mission input <goal>' "$DOCTOR_INIT_RC"
  evidence_log_command mission-status './bin/sensai mission status fixture-mission' "$DOCTOR_STATUS_RC"
  assert_eq doctor.mission_init_exit 0 "$DOCTOR_INIT_RC" || true
  assert_eq doctor.mission_status_exit 0 "$DOCTOR_STATUS_RC" || true
  DOCTOR_MISSION=$DOCTOR_PROJECT/docs/analysis/missions/fixture-mission
  find "$DOCTOR_MISSION" -mindepth 1 -maxdepth 1 -type f -print | \
    sed "s|$DOCTOR_MISSION/||" | LC_ALL=C sort >"$DOCTOR_BASE/mission-leaves.txt" || return 70
  printf '%s\n' progress.json status.md trace.json >"$DOCTOR_BASE/expected-mission-leaves.txt" || return 70
  if cmp -s "$DOCTOR_BASE/expected-mission-leaves.txt" "$DOCTOR_BASE/mission-leaves.txt" && \
     test -z "$(find "$DOCTOR_MISSION" -mindepth 1 -maxdepth 1 -name '.sensai-*' -print -quit)"; then
    assert_record doctor.mission_exact_files 0 'init은 정규 파일 3개만 남긴다' || true
  else
    assert_record doctor.mission_exact_files 1 'init 뒤 임시 파일 또는 파일 누락이 있다' || true
  fi
  if jq -e '
      .mission_id == "fixture-mission" and .mission_root == "docs/analysis/missions/fixture-mission/"
      and .phase == "F0" and .status == "planned" and .revision == 1
      and .writer == "sensai-analysis-lead"
    ' "$DOCTOR_MISSION/progress.json" >/dev/null 2>&1 && \
     rg -q --no-config '^# 미션 상태: fixture-mission$' "$DOCTOR_BASE/status.out"; then
    assert_record doctor.mission_schema_path 0 'mission 경로와 초기 progress가 유효하다' || true
  else
    assert_record doctor.mission_schema_path 1 'mission 경로 또는 초기 progress가 다르다' || true
  fi

  tooling_sha256_file "$DOCTOR_MISSION/progress.json" || return 70
  DOCTOR_REV1_HASH=$TOOLING_SHA256
  set +e
  SENSAI_PROJECT_ROOT=$DOCTOR_PROJECT "$DOCTOR_CLI" mission resume fixture-mission 1 "$DOCTOR_REV1_HASH" \
    >"$DOCTOR_BASE/resume.out" 2>"$DOCTOR_BASE/resume.err"
  DOCTOR_RESUME_RC=$?
  evidence_log_command mission-resume './bin/sensai mission resume fixture-mission 1 <sha256>' "$DOCTOR_RESUME_RC"
  assert_eq doctor.mission_resume_exit 0 "$DOCTOR_RESUME_RC" || true
  if jq -e --arg previous "$DOCTOR_REV1_HASH" '
      .revision == 2 and .phase == "F0"
      and .precondition_fingerprints.previous_progress == $previous
    ' "$DOCTOR_MISSION/progress.json" >/dev/null 2>&1; then
    assert_record doctor.resume_revision_cas 0 'resume이 revision과 previous hash를 원자적으로 갱신한다' || true
  else
    assert_record doctor.resume_revision_cas 1 'resume CAS 결과가 다르다' || true
  fi

  tooling_sha256_file "$DOCTOR_MISSION/progress.json" || return 70
  DOCTOR_REV2_HASH=$TOOLING_SHA256
  set +e
  SENSAI_PROJECT_ROOT=$DOCTOR_PROJECT "$DOCTOR_CLI" mission resume fixture-mission 1 "$DOCTOR_REV1_HASH" \
    >"$DOCTOR_BASE/stale.out" 2>"$DOCTOR_BASE/stale.err"
  DOCTOR_STALE_RC=$?
  evidence_log_command mission-resume-stale './bin/sensai mission resume fixture-mission 1 <stale-sha256>' "$DOCTOR_STALE_RC"
  tooling_sha256_file "$DOCTOR_MISSION/progress.json" || return 70
  assert_eq doctor.stale_exit 75 "$DOCTOR_STALE_RC" || true
  assert_eq doctor.stale_unchanged "$DOCTOR_REV2_HASH" "$TOOLING_SHA256" || true
  if rg -q --no-config 'reason=progress\.resume\.stale_hash' "$DOCTOR_BASE/stale.err"; then
    assert_record doctor.stale_reason 0 'stale hash가 reason code로 구분된다' || true
  else
    assert_record doctor.stale_reason 1 'stale hash reason code가 없다' || true
  fi

  jq --arg previous "$DOCTOR_REV2_HASH" '
    .revision=3
    | .updated_at="2099-01-01T00:00:00Z"
    | .precondition_fingerprints.previous_progress=$previous
    | .next="F0 승인 영수증을 기다린다"
  ' "$DOCTOR_MISSION/progress.json" >"$DOCTOR_PROJECT/checkpoint.json" || return 70
  set +e
  SENSAI_PROJECT_ROOT=$DOCTOR_PROJECT "$DOCTOR_CLI" mission checkpoint fixture-mission checkpoint.json 2 "$DOCTOR_REV2_HASH" \
    >"$DOCTOR_BASE/checkpoint.out" 2>"$DOCTOR_BASE/checkpoint.err"
  DOCTOR_CHECKPOINT_RC=$?
  evidence_log_command mission-checkpoint './bin/sensai mission checkpoint fixture-mission checkpoint.json 2 <sha256>' "$DOCTOR_CHECKPOINT_RC"
  assert_eq doctor.checkpoint_exit 0 "$DOCTOR_CHECKPOINT_RC" || true
  assert_jq doctor.checkpoint_revision '.revision == 3 and .next == "F0 승인 영수증을 기다린다"' \
    "$DOCTOR_MISSION/progress.json" || true
  if test -z "$(find "$DOCTOR_MISSION" -mindepth 1 -maxdepth 1 -name '.sensai-*' -print -quit)"; then
    assert_record doctor.atomic_cleanup 0 '성공·실패 뒤 lock과 원자 write 임시 파일이 없다' || true
  else
    assert_record doctor.atomic_cleanup 1 'lock 또는 원자 write 임시 파일이 남았다' || true
  fi

  set +e
  SENSAI_PROJECT_ROOT=$DOCTOR_PROJECT "$DOCTOR_CLI" mission init '../escape' input '실행되면 안 되는 목표' \
    >"$DOCTOR_BASE/path.out" 2>"$DOCTOR_BASE/path.err"
  DOCTOR_PATH_RC=$?
  evidence_log_command mission-invalid-path './bin/sensai mission init ../escape input <goal>' "$DOCTOR_PATH_RC"
  assert_eq doctor.invalid_path_exit 65 "$DOCTOR_PATH_RC" || true
  if test ! -e "$DOCTOR_PROJECT/escape"; then
    assert_record doctor.invalid_path_no_write 0 '잘못된 mission ID는 외부 파일을 쓰지 않는다' || true
  else
    assert_record doctor.invalid_path_no_write 1 '잘못된 mission ID가 외부 파일을 썼다' || true
  fi

  if rg -F -q --no-config '"$OPENCODE_CONFIG_DIR/bin/sensai" mission init' "$SOURCE_ROOT/output/commands/sensai/run.md" && \
     rg -F -q --no-config '"$OPENCODE_CONFIG_DIR/bin/sensai" mission checkpoint' "$SOURCE_ROOT/output/commands/sensai/run.md" && \
     rg -F -q --no-config '"$OPENCODE_CONFIG_DIR/bin/sensai" mission resume' "$SOURCE_ROOT/output/commands/sensai/resume.md" && \
     rg -F -q --no-config '"$OPENCODE_CONFIG_DIR/bin/sensai" mission status' "$SOURCE_ROOT/output/commands/sensai/status.md" && \
     ! rg -q --no-config '(^|[^A-Z_])\./bin/sensai mission' "$SOURCE_ROOT/output/commands/sensai"; then
    assert_record doctor.command_binding 0 'run/resume/status command가 설치된 결정적 mission helper에 결합됐다' || true
  else
    assert_record doctor.command_binding 1 'command와 mission helper 결합이 빠졌다' || true
  fi
}

doctor_clone_runtime() {
  DOCTOR_CLONE=$1
  mkdir -p "$DOCTOR_CLONE/bin" "$DOCTOR_CLONE/output/recipes" || return 70
  cp "$SOURCE_ROOT/bin/sensai" "$DOCTOR_CLONE/bin/sensai" || return 70
  chmod 755 "$DOCTOR_CLONE/bin/sensai" || return 70
  cp "$SOURCE_ROOT/output/opencode.json" "$DOCTOR_CLONE/output/opencode.json" || return 70
  cp "$SOURCE_ROOT/output/toolchain.lock.json" "$DOCTOR_CLONE/output/toolchain.lock.json" || return 70
  cp "$SOURCE_ROOT/output/recipes/trace.jq" "$DOCTOR_CLONE/output/recipes/trace.jq" || return 70
  cp "$SOURCE_ROOT/output/recipes/progress.jq" "$DOCTOR_CLONE/output/recipes/progress.jq" || return 70
}
