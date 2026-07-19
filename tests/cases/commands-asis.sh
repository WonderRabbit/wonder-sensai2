#!/bin/sh

commands_asis_line() {
  COMMANDS_ASIS_LINE_FILE=$1
  COMMANDS_ASIS_LINE_TOKEN=$2
  awk -v token="$COMMANDS_ASIS_LINE_TOKEN" 'index($0, token) { print NR; exit }' \
    "$COMMANDS_ASIS_LINE_FILE"
}

commands_asis_ordered() {
  COMMANDS_ASIS_ORDER_FILE=$1
  shift
  COMMANDS_ASIS_PREVIOUS=0
  for COMMANDS_ASIS_TOKEN do
    COMMANDS_ASIS_CURRENT=$(commands_asis_line "$COMMANDS_ASIS_ORDER_FILE" "$COMMANDS_ASIS_TOKEN") || return 70
    test -n "$COMMANDS_ASIS_CURRENT" || return 1
    test "$COMMANDS_ASIS_CURRENT" -gt "$COMMANDS_ASIS_PREVIOUS" || return 1
    COMMANDS_ASIS_PREVIOUS=$COMMANDS_ASIS_CURRENT
  done
}

commands_asis_check_runtime() {
  COMMANDS_ASIS_DIR="$SOURCE_ROOT/output/commands/sensai"
  COMMANDS_ASIS_EXPECTED="$RUN_TMP/commands-asis-expected.txt"
  COMMANDS_ASIS_ACTUAL="$RUN_TMP/commands-asis-actual.txt"
  COMMANDS_ASIS_FRONTMATTER_OK=1
  COMMANDS_ASIS_COMMON_OK=1
  COMMANDS_ASIS_BOUNDARY_OK=1
  COMMANDS_ASIS_KOREAN_OK=1

  printf '%s\n' \
    commands/sensai/analyze-business.md \
    commands/sensai/analyze.md \
    commands/sensai/document-asis.md >"$COMMANDS_ASIS_EXPECTED" || return 70

  COMMANDS_ASIS_REQUIRED_OK=1
  while IFS= read -r COMMANDS_ASIS_REQUIRED; do
    test -f "$SOURCE_ROOT/output/$COMMANDS_ASIS_REQUIRED" && \
      ! test -L "$SOURCE_ROOT/output/$COMMANDS_ASIS_REQUIRED" || COMMANDS_ASIS_REQUIRED_OK=0
  done <"$COMMANDS_ASIS_EXPECTED"
  if test "$COMMANDS_ASIS_REQUIRED_OK" -eq 1; then
    assert_record commands-asis.required_set 0 'AS-IS command 3개가 현재 command 집합에 있다' || true
  else
    assert_record commands-asis.required_set 1 'AS-IS command 필수 파일이 누락되거나 심볼릭 링크다' || true
  fi

  while IFS= read -r COMMANDS_ASIS_RELATIVE; do
    COMMANDS_ASIS_FILE="$SOURCE_ROOT/output/$COMMANDS_ASIS_RELATIVE"
    COMMANDS_ASIS_META="$RUN_TMP/$(basename "$COMMANDS_ASIS_RELATIVE").frontmatter.json"
    if ! test -f "$COMMANDS_ASIS_FILE" || test -L "$COMMANDS_ASIS_FILE"; then
      COMMANDS_ASIS_FRONTMATTER_OK=0
      COMMANDS_ASIS_COMMON_OK=0
      COMMANDS_ASIS_BOUNDARY_OK=0
      COMMANDS_ASIS_KOREAN_OK=0
      continue
    fi
    if ! yq --front-matter=extract -o=json '.' "$COMMANDS_ASIS_FILE" >"$COMMANDS_ASIS_META" 2>/dev/null || \
       ! jq -e '
         (keys | sort) == (["agent","description","subtask"] | sort) and
         .agent == "sensai-analysis-lead" and
         .subtask == false and
         (.description | type == "string" and length >= 1 and length <= 1024 and test("[가-힣]"))
       ' "$COMMANDS_ASIS_META" >/dev/null 2>&1; then
      COMMANDS_ASIS_FRONTMATTER_OK=0
    fi
    if ! rg -F -q --no-config '$ARGUMENTS' "$COMMANDS_ASIS_FILE" || \
       ! rg -q --no-config 'sensai-evidence-peer.*subtask: true|subtask: true.*sensai-evidence-peer' "$COMMANDS_ASIS_FILE" || \
       ! rg -q --no-config '읽기 전용.*(path:line|`path:line`).*(evidence_ids|`evidence_ids`)' "$COMMANDS_ASIS_FILE" || \
       ! rg -q --no-config 'sensai-analysis-lead.*(직렬|재확인).*(병합|적재)' "$COMMANDS_ASIS_FILE" || \
       ! rg -F -q --no-config '단일 작성자' "$COMMANDS_ASIS_FILE" || \
       ! rg -F -q --no-config '`UNKNOWN`' "$COMMANDS_ASIS_FILE" || \
       ! rg -F -q --no-config '`unresolved`' "$COMMANDS_ASIS_FILE" || \
       ! rg -F -q --no-config '`ambiguous`' "$COMMANDS_ASIS_FILE" || \
       ! rg -F -q --no-config '`many_to_many`' "$COMMANDS_ASIS_FILE" || \
       ! rg -F -q --no-config '`conflict`' "$COMMANDS_ASIS_FILE"; then
      COMMANDS_ASIS_COMMON_OK=0
    fi
    if ! rg -F -q --no-config 'docs/analysis/missions/<mission-id>/' "$COMMANDS_ASIS_FILE" || \
       ! rg -q --no-config '미션 루트 밖.*쓰지' "$COMMANDS_ASIS_FILE" || \
       rg -q --no-config '/(tmp|var/tmp)/|(^|[^[:alnum:]_])\.\./' "$COMMANDS_ASIS_FILE"; then
      COMMANDS_ASIS_BOUNDARY_OK=0
    fi
    if ! rg -q --no-config '[가-힣]' "$COMMANDS_ASIS_FILE"; then
      COMMANDS_ASIS_KOREAN_OK=0
    fi
  done <"$COMMANDS_ASIS_EXPECTED"

  assert_eq commands-asis.frontmatter 1 "$COMMANDS_ASIS_FRONTMATTER_OK" || true
  assert_eq commands-asis.common_contract 1 "$COMMANDS_ASIS_COMMON_OK" || true
  assert_eq commands-asis.output_boundary 1 "$COMMANDS_ASIS_BOUNDARY_OK" || true
  assert_eq commands-asis.korean_content 1 "$COMMANDS_ASIS_KOREAN_OK" || true

  COMMANDS_ASIS_ANALYZE="$COMMANDS_ASIS_DIR/analyze.md"
  COMMANDS_ASIS_BUSINESS="$COMMANDS_ASIS_DIR/analyze-business.md"
  COMMANDS_ASIS_DOCUMENT="$COMMANDS_ASIS_DIR/document-asis.md"

  if test -f "$COMMANDS_ASIS_ANALYZE" && commands_asis_ordered "$COMMANDS_ASIS_ANALYZE" \
    'sensai-evidence-first' 'sensai-stack-discovery' 'sensai-convention-extract'; then
    assert_record commands-asis.analyze_skill_order 0 '기술 분석 skill 순서가 명시됐다' || true
  else
    assert_record commands-asis.analyze_skill_order 1 '기술 분석 skill 순서가 없거나 뒤바뀌었다' || true
  fi
  if test -f "$COMMANDS_ASIS_BUSINESS" && commands_asis_ordered "$COMMANDS_ASIS_BUSINESS" \
    'sensai-evidence-first' 'sensai-business-trace' 'sensai-spec-evidence'; then
    assert_record commands-asis.business_skill_order 0 '비즈니스 분석 skill 순서가 명시됐다' || true
  else
    assert_record commands-asis.business_skill_order 1 '비즈니스 분석 skill 순서가 없거나 뒤바뀌었다' || true
  fi
  if test -f "$COMMANDS_ASIS_DOCUMENT" && commands_asis_ordered "$COMMANDS_ASIS_DOCUMENT" \
    'sensai-evidence-first' 'sensai-ui-definition' 'sensai-mermaid-sequence' \
    'sensai-dataflow-chart' 'sensai-user-story'; then
    assert_record commands-asis.document_skill_order 0 'AS-IS 투영 skill 순서가 명시됐다' || true
  else
    assert_record commands-asis.document_skill_order 1 'AS-IS 투영 skill 순서가 없거나 뒤바뀌었다' || true
  fi

  if test -f "$COMMANDS_ASIS_ANALYZE" && \
     rg -F -q --no-config '`F1`' "$COMMANDS_ASIS_ANALYZE" && \
     rg -F -q --no-config '`trace.json`' "$COMMANDS_ASIS_ANALYZE" && \
     rg -q --no-config 'COMPONENT.*STRUCTURE.*NAMING.*API.*STATE.*ERROR.*TEST' "$COMMANDS_ASIS_ANALYZE"; then
    assert_record commands-asis.analyze_outputs 0 'F1 기술 trace와 7개 convention 출력이 명시됐다' || true
  else
    assert_record commands-asis.analyze_outputs 1 'F1 기술 분석 출력 계약이 빠졌다' || true
  fi

  if test -f "$COMMANDS_ASIS_BUSINESS" && \
     rg -F -q --no-config '`F2`' "$COMMANDS_ASIS_BUSINESS" && \
     rg -F -q --no-config '`glossary.json`' "$COMMANDS_ASIS_BUSINESS" && \
     rg -F -q --no-config '`glossary.ko.md`' "$COMMANDS_ASIS_BUSINESS" && \
     rg -q --no-config 'business_entities.*business_rules.*business_flows.*business_events.*business_states.*business_invariants' "$COMMANDS_ASIS_BUSINESS"; then
    assert_record commands-asis.business_outputs 0 'F2 비즈니스 사실과 glossary 출력이 명시됐다' || true
  else
    assert_record commands-asis.business_outputs 1 'F2 비즈니스 분석 출력 계약이 빠졌다' || true
  fi

  if test -f "$COMMANDS_ASIS_DOCUMENT" && \
     rg -q --no-config '`F1`.*`F2`|`F2`.*`F1`' "$COMMANDS_ASIS_DOCUMENT" && \
     rg -q --no-config '검증.*`trace.json`' "$COMMANDS_ASIS_DOCUMENT"; then
    assert_record commands-asis.document_prerequisites 0 'F3는 검증된 F1/F2를 전제로 한다' || true
  else
    assert_record commands-asis.document_prerequisites 1 'F3 선행 F1/F2 계약이 빠졌다' || true
  fi

  if test -f "$COMMANDS_ASIS_DOCUMENT" && \
     rg -F -q --no-config '`asis/ui.md`' "$COMMANDS_ASIS_DOCUMENT" && \
     rg -F -q --no-config '`asis/sequence.mmd`' "$COMMANDS_ASIS_DOCUMENT" && \
     rg -F -q --no-config '`asis/dataflow.mmd`' "$COMMANDS_ASIS_DOCUMENT" && \
     rg -F -q --no-config '`asis/story.md`' "$COMMANDS_ASIS_DOCUMENT"; then
    assert_record commands-asis.document_outputs 0 'F3 AS-IS 4종 출력이 명시됐다' || true
  else
    assert_record commands-asis.document_outputs 1 'F3 AS-IS 4종 출력 계약이 빠졌다' || true
  fi

  if test -f "$COMMANDS_ASIS_DOCUMENT" && \
     rg -q --no-config '`F3`.*(hard gate|하드 게이트)' "$COMMANDS_ASIS_DOCUMENT" && \
     rg -q --no-config '사람.*(승인|accept).*(전|없).*(F4|TO-BE).*진입하지' "$COMMANDS_ASIS_DOCUMENT"; then
    assert_record commands-asis.f3_hard_gate 0 'F3 사람 승인 전 TO-BE 차단이 명시됐다' || true
  else
    assert_record commands-asis.f3_hard_gate 1 'F3 사람 승인 hard gate가 빠졌다' || true
  fi

  if test -d "$SOURCE_ROOT/commands"; then
    assert_record commands-asis.no_root_copy 1 'root commands 복사본이 존재한다' || true
  else
    assert_record commands-asis.no_root_copy 0 'root commands 복사본이 없다' || true
  fi
}

case_commands_asis() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  commands_asis_check_runtime || return 70
}
