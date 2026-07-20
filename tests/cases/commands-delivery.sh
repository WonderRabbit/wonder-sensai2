#!/bin/sh

commands_delivery_line() {
  COMMANDS_DELIVERY_LINE_FILE=$1
  COMMANDS_DELIVERY_LINE_TOKEN=$2
  awk -v token="$COMMANDS_DELIVERY_LINE_TOKEN" 'index($0, token) { print NR; exit }' \
    "$COMMANDS_DELIVERY_LINE_FILE"
}

commands_delivery_ordered() {
  COMMANDS_DELIVERY_ORDER_FILE=$1
  shift
  COMMANDS_DELIVERY_PREVIOUS=0
  for COMMANDS_DELIVERY_TOKEN do
    COMMANDS_DELIVERY_CURRENT=$(commands_delivery_line "$COMMANDS_DELIVERY_ORDER_FILE" "$COMMANDS_DELIVERY_TOKEN") || return 70
    test -n "$COMMANDS_DELIVERY_CURRENT" || return 1
    test "$COMMANDS_DELIVERY_CURRENT" -gt "$COMMANDS_DELIVERY_PREVIOUS" || return 1
    COMMANDS_DELIVERY_PREVIOUS=$COMMANDS_DELIVERY_CURRENT
  done
}

commands_delivery_check_runtime() {
  COMMANDS_DELIVERY_DIR="$SOURCE_ROOT/output/commands/sensai"
  COMMANDS_DELIVERY_EXPECTED="$RUN_TMP/commands-delivery-expected.txt"
  COMMANDS_DELIVERY_ACTUAL="$RUN_TMP/commands-delivery-actual.txt"
  COMMANDS_DELIVERY_FRONTMATTER_OK=1
  COMMANDS_DELIVERY_COMMON_OK=1
  COMMANDS_DELIVERY_BOUNDARY_OK=1
  COMMANDS_DELIVERY_KOREAN_OK=1

  printf '%s\n' \
    commands/sensai/analyze-business.md \
    commands/sensai/analyze.md \
    commands/sensai/change-design.md \
    commands/sensai/deliver.md \
    commands/sensai/document-asis.md \
    commands/sensai/verify.md >"$COMMANDS_DELIVERY_EXPECTED" || return 70

  if test -d "$COMMANDS_DELIVERY_DIR" && ! test -L "$COMMANDS_DELIVERY_DIR"; then
    (cd "$SOURCE_ROOT/output" && find commands -type f -print | LC_ALL=C sort) \
      >"$COMMANDS_DELIVERY_ACTUAL" || return 70
  else
    : >"$COMMANDS_DELIVERY_ACTUAL" || return 70
  fi

  COMMANDS_DELIVERY_REQUIRED_OK=1
  while IFS= read -r COMMANDS_DELIVERY_REQUIRED; do
    rg -F -x -q --no-config "$COMMANDS_DELIVERY_REQUIRED" \
      "$COMMANDS_DELIVERY_ACTUAL" || COMMANDS_DELIVERY_REQUIRED_OK=0
  done <"$COMMANDS_DELIVERY_EXPECTED"
  if test "$COMMANDS_DELIVERY_REQUIRED_OK" -eq 1 && \
     cmp -s "$SOURCE_ROOT/tests/contracts/commands.txt" "$COMMANDS_DELIVERY_ACTUAL"; then
    assert_record commands-delivery.current_exact_set 0 'delivery 필수 6개를 포함한 현재 command exact-set 9개다' || true
  else
    assert_record commands-delivery.current_exact_set 1 'delivery 필수 command 또는 현재 exact-set이 다르다' || true
  fi

  while IFS= read -r COMMANDS_DELIVERY_RELATIVE; do
    COMMANDS_DELIVERY_FILE="$SOURCE_ROOT/output/$COMMANDS_DELIVERY_RELATIVE"
    COMMANDS_DELIVERY_META="$RUN_TMP/$(basename "$COMMANDS_DELIVERY_RELATIVE").delivery-frontmatter.json"
    if ! test -f "$COMMANDS_DELIVERY_FILE" || test -L "$COMMANDS_DELIVERY_FILE"; then
      COMMANDS_DELIVERY_FRONTMATTER_OK=0
      COMMANDS_DELIVERY_COMMON_OK=0
      COMMANDS_DELIVERY_BOUNDARY_OK=0
      COMMANDS_DELIVERY_KOREAN_OK=0
      continue
    fi
    if ! yq --front-matter=extract -o=json '.' "$COMMANDS_DELIVERY_FILE" >"$COMMANDS_DELIVERY_META" 2>/dev/null || \
       ! jq -e '
         (keys | sort) == (["agent","description","subtask"] | sort) and
         .agent == "sensai-analysis-lead" and
         .subtask == false and
         (.description | type == "string" and length >= 1 and length <= 1024 and test("[가-힣]"))
       ' "$COMMANDS_DELIVERY_META" >/dev/null 2>&1; then
      COMMANDS_DELIVERY_FRONTMATTER_OK=0
    fi
    if ! rg -F -q --no-config '$ARGUMENTS' "$COMMANDS_DELIVERY_FILE" || \
       ! rg -F -q --no-config 'docs/analysis/missions/<mission-id>/' "$COMMANDS_DELIVERY_FILE" || \
       ! rg -F -q --no-config 'sensai-analysis-lead' "$COMMANDS_DELIVERY_FILE" || \
       ! rg -F -q --no-config '단일 작성자' "$COMMANDS_DELIVERY_FILE" || \
       ! rg -F -q --no-config '`UNKNOWN`' "$COMMANDS_DELIVERY_FILE" || \
       ! rg -F -q --no-config '`unresolved`' "$COMMANDS_DELIVERY_FILE" || \
       ! rg -F -q --no-config '`ambiguous`' "$COMMANDS_DELIVERY_FILE" || \
       ! rg -F -q --no-config '`many_to_many`' "$COMMANDS_DELIVERY_FILE" || \
       ! rg -F -q --no-config '`conflict`' "$COMMANDS_DELIVERY_FILE" || \
       ! rg -q --no-config 'path:line.*evidence_ids|evidence_ids.*path:line' "$COMMANDS_DELIVERY_FILE"; then
      COMMANDS_DELIVERY_COMMON_OK=0
    fi
    if ! rg -q --no-config '미션 루트 밖.*쓰지|읽기 전용.*미션 루트 밖.*수정하지' "$COMMANDS_DELIVERY_FILE" || \
       rg -q --no-config '/(tmp|var/tmp)/|(^|[^[:alnum:]_])\.\./' "$COMMANDS_DELIVERY_FILE"; then
      COMMANDS_DELIVERY_BOUNDARY_OK=0
    fi
    if ! rg -q --no-config '[가-힣]' "$COMMANDS_DELIVERY_FILE"; then
      COMMANDS_DELIVERY_KOREAN_OK=0
    fi
  done <"$COMMANDS_DELIVERY_EXPECTED"

  assert_eq commands-delivery.frontmatter 1 "$COMMANDS_DELIVERY_FRONTMATTER_OK" || true
  assert_eq commands-delivery.common_contract 1 "$COMMANDS_DELIVERY_COMMON_OK" || true
  assert_eq commands-delivery.output_boundary 1 "$COMMANDS_DELIVERY_BOUNDARY_OK" || true
  assert_eq commands-delivery.korean_content 1 "$COMMANDS_DELIVERY_KOREAN_OK" || true

  COMMANDS_DELIVERY_CHANGE="$COMMANDS_DELIVERY_DIR/change-design.md"
  COMMANDS_DELIVERY_DELIVER="$COMMANDS_DELIVERY_DIR/deliver.md"
  COMMANDS_DELIVERY_VERIFY="$COMMANDS_DELIVERY_DIR/verify.md"

  if test -f "$COMMANDS_DELIVERY_CHANGE" && \
     rg -q --no-config '`F3`.*(accepted|승인)' "$COMMANDS_DELIVERY_CHANGE" && \
     rg -q --no-config '(사람|사용자).*(accepted|승인).*(fingerprint|지문)' "$COMMANDS_DELIVERY_CHANGE" && \
     rg -q --no-config '(승인|accepted).*(없|전).*(중단|차단|쓰지)' "$COMMANDS_DELIVERY_CHANGE"; then
    assert_record commands-delivery.f3_accepted_precondition 0 '현재 fingerprint에 결합된 F3 사람 승인이 TO-BE 선행조건이다' || true
  else
    assert_record commands-delivery.f3_accepted_precondition 1 'F3 accepted 선행조건이 빠졌다' || true
  fi

  if test -f "$COMMANDS_DELIVERY_CHANGE" && commands_delivery_ordered "$COMMANDS_DELIVERY_CHANGE" \
    '1. `sensai-evidence-first`' '2. `sensai-requirement-analyze`' '3. `sensai-change-design`'; then
    assert_record commands-delivery.change_skill_order 0 '변경 설계 skill 순서가 명시됐다' || true
  else
    assert_record commands-delivery.change_skill_order 1 '변경 설계 skill 순서가 없거나 뒤바뀌었다' || true
  fi

  if test -f "$COMMANDS_DELIVERY_CHANGE" && \
     rg -F -q --no-config '`designs[]`' "$COMMANDS_DELIVERY_CHANGE" && \
     rg -F -q --no-config '`bindings[]`' "$COMMANDS_DELIVERY_CHANGE" && \
     rg -F -q --no-config '`follows_convention_ids`' "$COMMANDS_DELIVERY_CHANGE" && \
     rg -F -q --no-config '`follows_business_ids`' "$COMMANDS_DELIVERY_CHANGE" && \
     rg -q --no-config 'binding.*(없|누락).*(불통과|차단|쓰지)' "$COMMANDS_DELIVERY_CHANGE"; then
    assert_record commands-delivery.design_binding 0 'design과 양쪽 AS-IS binding이 필수다' || true
  else
    assert_record commands-delivery.design_binding 1 '변경 설계 binding 계약이 빠졌다' || true
  fi

  if test -f "$COMMANDS_DELIVERY_CHANGE" && \
     rg -q --no-config '(UI|시퀀스|데이터플로우|사용자 스토리|테스트 시나리오).*(직접|이 명령).*(작성|생성).*(금지|하지)' "$COMMANDS_DELIVERY_CHANGE" && \
     rg -F -q --no-config '`/sensai/deliver`' "$COMMANDS_DELIVERY_CHANGE"; then
    assert_record commands-delivery.change_no_final_expression 0 'change-design은 최종 표현을 직접 작성하지 않는다' || true
  else
    assert_record commands-delivery.change_no_final_expression 1 'change-design 최종 표현 소유권 분리가 빠졌다' || true
  fi

  if test -f "$COMMANDS_DELIVERY_DELIVER" && commands_delivery_ordered "$COMMANDS_DELIVERY_DELIVER" \
    '1. `sensai-evidence-first`' '2. `sensai-ui-definition`' '3. `sensai-mermaid-sequence`' \
    '4. `sensai-dataflow-chart`' '5. `sensai-user-story`' '6. `sensai-test-scenario`'; then
    assert_record commands-delivery.deliver_skill_order 0 'TO-BE 투영 skill 순서가 명시됐다' || true
  else
    assert_record commands-delivery.deliver_skill_order 1 'TO-BE 투영 skill 순서가 없거나 뒤바뀌었다' || true
  fi

  if test -f "$COMMANDS_DELIVERY_DELIVER" && \
     rg -F -q --no-config '`tobe/ui.md`' "$COMMANDS_DELIVERY_DELIVER" && \
     rg -F -q --no-config '`tobe/sequence.mmd`' "$COMMANDS_DELIVERY_DELIVER" && \
     rg -F -q --no-config '`tobe/dataflow.mmd`' "$COMMANDS_DELIVERY_DELIVER" && \
     rg -F -q --no-config '`tobe/story.md`' "$COMMANDS_DELIVERY_DELIVER" && \
     rg -F -q --no-config '`tobe/test.md`' "$COMMANDS_DELIVERY_DELIVER"; then
    assert_record commands-delivery.five_outputs 0 'TO-BE 5종 출력이 명시됐다' || true
  else
    assert_record commands-delivery.five_outputs 1 'TO-BE 5종 출력 계약이 빠졌다' || true
  fi

  if test -f "$COMMANDS_DELIVERY_DELIVER" && \
     rg -q --no-config '`ui`.*`mermaid`.*`dataflow`.*`story`.*`test`' "$COMMANDS_DELIVERY_DELIVER" && \
     rg -q --no-config '`mmdc`.*(exit|종료 코드).*0' "$COMMANDS_DELIVERY_DELIVER" && \
     rg -q --no-config '(validator|검증기).*(영수증|receipt)' "$COMMANDS_DELIVERY_DELIVER" && \
     rg -q --no-config '(앞|선행).*(실패|게이트).*(뒤|후속).*(쓰지|진행하지|완료.*표시하지)' "$COMMANDS_DELIVERY_DELIVER"; then
    assert_record commands-delivery.delivery_gates 0 '5모드 provenance, 렌더 영수증과 순차 게이트가 명시됐다' || true
  else
    assert_record commands-delivery.delivery_gates 1 'deliver 검증 또는 우회 금지 계약이 빠졌다' || true
  fi

  if test -f "$COMMANDS_DELIVERY_DELIVER" && \
     rg -q --no-config '`F5`.*(사람|사용자).*(accepted|승인)' "$COMMANDS_DELIVERY_DELIVER" && \
     rg -q --no-config '(승인|accepted).*(전|없).*(완료|종료).*(표시|선언).*않' "$COMMANDS_DELIVERY_DELIVER"; then
    assert_record commands-delivery.f5_human_acceptance 0 'F5 사람 승인 전 완료 선언이 차단된다' || true
  else
    assert_record commands-delivery.f5_human_acceptance 1 'F5 사람 승인 하드 게이트가 빠졌다' || true
  fi

  if test -f "$COMMANDS_DELIVERY_VERIFY" && \
     rg -q --no-config '(읽기 전용|read-only)' "$COMMANDS_DELIVERY_VERIFY" && \
     rg -q --no-config '(파일|원장|미션 상태).*(쓰거나|작성|수정|삭제).*(않|금지)' "$COMMANDS_DELIVERY_VERIFY" && \
     rg -q --no-config '실제 종료 코드.*해시.*영수증|영수증.*실제 종료 코드.*해시' "$COMMANDS_DELIVERY_VERIFY"; then
    assert_record commands-delivery.verify_read_only 0 'verify는 결정적 읽기 전용 검증이다' || true
  else
    assert_record commands-delivery.verify_read_only 1 'verify 읽기 전용 계약이 빠졌다' || true
  fi

  if ! test -e "$COMMANDS_DELIVERY_DIR/design.md" && \
     ! rg -l --no-config '/sensai/design([^a-z-]|$)' "$SOURCE_ROOT/output" >/dev/null 2>&1; then
    assert_record commands-delivery.legacy_design_absent 0 'legacy /sensai/design runtime 소유권이 없다' || true
  else
    assert_record commands-delivery.legacy_design_absent 1 'legacy /sensai/design runtime 소유권이 남아 있다' || true
  fi

  if test -d "$SOURCE_ROOT/commands"; then
    assert_record commands-delivery.no_root_copy 1 'root commands 복사본이 존재한다' || true
  else
    assert_record commands-delivery.no_root_copy 0 'root commands 복사본이 없다' || true
  fi
}

case_commands_delivery() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  commands_delivery_check_runtime || return 70
}
