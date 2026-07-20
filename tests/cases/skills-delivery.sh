#!/bin/sh

SKILLS_DELIVERY_PATHS='skills/sensai-change-design/SKILL.md
skills/sensai-dataflow-chart/SKILL.md
skills/sensai-requirement-analyze/SKILL.md
skills/sensai-test-scenario/SKILL.md
skills/sensai-user-story/SKILL.md'

skills_delivery_clone_source() {
  SKILLS_DELIVERY_CLONE_ROOT=$1
  mkdir -p "$SKILLS_DELIVERY_CLONE_ROOT/output" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$SKILLS_DELIVERY_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$SKILLS_DELIVERY_CLONE_ROOT/tests" || return 70
  cp -R "$SOURCE_ROOT/fixtures" "$SKILLS_DELIVERY_CLONE_ROOT/fixtures" || return 70
  cp -R "$SOURCE_ROOT/output/commands" "$SKILLS_DELIVERY_CLONE_ROOT/output/" || return 70
  cp -R "$SOURCE_ROOT/output/skills" "$SKILLS_DELIVERY_CLONE_ROOT/output/skills" || return 70
  cp "$SOURCE_ROOT/output/opencode.json" "$SKILLS_DELIVERY_CLONE_ROOT/output/" || return 70
}

skills_delivery_check_runtime() {
  SKILLS_DELIVERY_COUNT=0
  SKILLS_DELIVERY_FRONTMATTER_OK=1
  SKILLS_DELIVERY_BODY_OK=1
  SKILLS_DELIVERY_EVIDENCE_OK=1
  SKILLS_DELIVERY_PERMISSION_OK=1
  SKILLS_DELIVERY_ADMISSION_OK=1
  SKILLS_DELIVERY_FAILURE_OK=1
  SKILLS_DELIVERY_FIVE_MODES_OK=1
  SKILLS_DELIVERY_DIRECTORY_OK=1

  while IFS= read -r SKILLS_DELIVERY_RELATIVE; do
    test -n "$SKILLS_DELIVERY_RELATIVE" || continue
    SKILLS_DELIVERY_COUNT=$((SKILLS_DELIVERY_COUNT + 1))
    SKILLS_DELIVERY_FILE="$SOURCE_ROOT/output/$SKILLS_DELIVERY_RELATIVE"
    SKILLS_DELIVERY_NAME=${SKILLS_DELIVERY_RELATIVE#skills/}
    SKILLS_DELIVERY_NAME=${SKILLS_DELIVERY_NAME%/SKILL.md}
    SKILLS_DELIVERY_JSON="$RUN_TMP/skills-delivery-$SKILLS_DELIVERY_COUNT.json"
    SKILLS_DELIVERY_BODY="$RUN_TMP/skills-delivery-$SKILLS_DELIVERY_COUNT.md"

    if ! test -f "$SKILLS_DELIVERY_FILE" || test -L "$SKILLS_DELIVERY_FILE"; then
      SKILLS_DELIVERY_FRONTMATTER_OK=0
      SKILLS_DELIVERY_BODY_OK=0
      SKILLS_DELIVERY_EVIDENCE_OK=0
      SKILLS_DELIVERY_PERMISSION_OK=0
      SKILLS_DELIVERY_ADMISSION_OK=0
      SKILLS_DELIVERY_FAILURE_OK=0
      SKILLS_DELIVERY_FIVE_MODES_OK=0
      SKILLS_DELIVERY_DIRECTORY_OK=0
      continue
    fi

    if ! yq --front-matter=extract -o=json '.' "$SKILLS_DELIVERY_FILE" >"$SKILLS_DELIVERY_JSON" 2>/dev/null || \
       ! jq -e --arg name "$SKILLS_DELIVERY_NAME" '
         keys_unsorted == ["name","description"] and
         .name == $name and
         (.name | test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
         (.description | type == "string" and length >= 1 and length <= 1024) and
         (.description | test("[가-힣]"))
       ' "$SKILLS_DELIVERY_JSON" >/dev/null 2>&1; then
      SKILLS_DELIVERY_FRONTMATTER_OK=0
    fi

    awk 'BEGIN { marks=0 } /^---[[:space:]]*$/ { marks++; next } marks >= 2 { print }' \
      "$SKILLS_DELIVERY_FILE" >"$SKILLS_DELIVERY_BODY" || return 70
    for SKILLS_DELIVERY_HEADING in '적용 조건' 입력 '작업 순서' 출력 '근거 계약' '허용 도구와 권한' '입학 상태' '실패 처리'; do
      if ! rg -q --no-config "^## $SKILLS_DELIVERY_HEADING$" "$SKILLS_DELIVERY_BODY"; then
        SKILLS_DELIVERY_BODY_OK=0
      fi
    done
    if ! rg -q --no-config '근거 계약:.*`path:line`.*`evidence_ids`' "$SKILLS_DELIVERY_BODY" || \
       ! rg -q --no-config '`UNKNOWN`' "$SKILLS_DELIVERY_BODY" || \
       ! rg -q --no-config '`unresolved`' "$SKILLS_DELIVERY_BODY" || \
       ! rg -q --no-config '`ambiguous`' "$SKILLS_DELIVERY_BODY" || \
       ! rg -q --no-config '`conflict`' "$SKILLS_DELIVERY_BODY"; then
      SKILLS_DELIVERY_EVIDENCE_OK=0
    fi
    if ! rg -q --no-config '스킬 로드는 권한을 추가하지 않는다' "$SKILLS_DELIVERY_BODY" || \
       ! rg -q --no-config '현재 대상 저장소.*명시적으로 선택된 원본.*읽기 전용' "$SKILLS_DELIVERY_BODY" || \
       ! rg -q --no-config '대상 저장소 밖.*읽지' "$SKILLS_DELIVERY_BODY" || \
       ! rg -q --no-config '쓰기.*현재 미션 루트' "$SKILLS_DELIVERY_BODY"; then
      SKILLS_DELIVERY_PERMISSION_OK=0
    fi
    for SKILLS_DELIVERY_STATE in REQUIRED_TO_EVALUATE NOT_ADMITTED ADMITTED_NO_VALUE VALUE_PROVEN; do
      if ! rg -F -q --no-config "$SKILLS_DELIVERY_STATE" "$SKILLS_DELIVERY_BODY"; then
        SKILLS_DELIVERY_ADMISSION_OK=0
      fi
    done
    if ! rg -q --no-config '에이전트 허용 목록.*설정.*자동으로 활성화·승격하지 마라' "$SKILLS_DELIVERY_BODY"; then
      SKILLS_DELIVERY_ADMISSION_OK=0
    fi
    if ! rg -q --no-config '부분 산출물을 완료로 표시하지 않는다' "$SKILLS_DELIVERY_BODY"; then
      SKILLS_DELIVERY_FAILURE_OK=0
    fi
    for SKILLS_DELIVERY_MODE in ui mermaid dataflow story test; do
      if ! rg -F -q --no-config "\`$SKILLS_DELIVERY_MODE\`" "$SKILLS_DELIVERY_BODY"; then
        SKILLS_DELIVERY_FIVE_MODES_OK=0
      fi
    done
    SKILLS_DELIVERY_LINES=$(wc -l <"$SKILLS_DELIVERY_FILE" | awk '{print $1}') || return 70
    if test "$SKILLS_DELIVERY_LINES" -ge 500 || \
       rg -n --no-config '(^|[^a-z])(sudo|curl|wget|eval)([^a-z]|$)|rm[[:space:]]+-rf|git[[:space:]]+push|BEGIN (RSA|OPENSSH) PRIVATE KEY' \
         "$SKILLS_DELIVERY_FILE" >/dev/null 2>&1; then
      SKILLS_DELIVERY_BODY_OK=0
    else
      SKILLS_DELIVERY_SAFE_RC=$?
      test "$SKILLS_DELIVERY_SAFE_RC" -eq 1 || return 70
    fi
    SKILLS_DELIVERY_DIR=${SKILLS_DELIVERY_FILE%/SKILL.md}
    SKILLS_DELIVERY_LEAF_COUNT=$(find "$SKILLS_DELIVERY_DIR" -mindepth 1 -maxdepth 1 -type f -print | wc -l | awk '{print $1}') || return 70
    SKILLS_DELIVERY_OTHER_COUNT=$(find "$SKILLS_DELIVERY_DIR" -mindepth 1 -maxdepth 1 ! -type f -print | wc -l | awk '{print $1}') || return 70
    if test "$SKILLS_DELIVERY_LEAF_COUNT" -ne 1 || test "$SKILLS_DELIVERY_OTHER_COUNT" -ne 0; then
      SKILLS_DELIVERY_DIRECTORY_OK=0
    fi
  done <<EOF
$SKILLS_DELIVERY_PATHS
EOF

  assert_eq skills-delivery.count 5 "$SKILLS_DELIVERY_COUNT" || true
  assert_eq skills-delivery.frontmatter 1 "$SKILLS_DELIVERY_FRONTMATTER_OK" || true
  assert_eq skills-delivery.body_contract 1 "$SKILLS_DELIVERY_BODY_OK" || true
  assert_eq skills-delivery.evidence_contract 1 "$SKILLS_DELIVERY_EVIDENCE_OK" || true
  assert_eq skills-delivery.permission_boundary 1 "$SKILLS_DELIVERY_PERMISSION_OK" || true
  assert_eq skills-delivery.admission_state 1 "$SKILLS_DELIVERY_ADMISSION_OK" || true
  assert_eq skills-delivery.failure_behavior 1 "$SKILLS_DELIVERY_FAILURE_OK" || true
  assert_eq skills-delivery.five_modes 1 "$SKILLS_DELIVERY_FIVE_MODES_OK" || true
  assert_eq skills-delivery.directory_exact 1 "$SKILLS_DELIVERY_DIRECTORY_OK" || true

  SKILLS_DELIVERY_ACTUAL="$RUN_TMP/skills-delivery-actual.txt"
  (cd "$SOURCE_ROOT/output" && find skills -mindepth 2 -maxdepth 2 -type f -print | LC_ALL=C sort) >"$SKILLS_DELIVERY_ACTUAL" || return 70
  SKILLS_DELIVERY_TOTAL=$(wc -l <"$SKILLS_DELIVERY_ACTUAL" | awk '{print $1}') || return 70
  assert_eq skills-delivery.total_inventory 15 "$SKILLS_DELIVERY_TOTAL" || true
  if cmp -s "$SOURCE_ROOT/tests/contracts/skills.txt" "$SKILLS_DELIVERY_ACTUAL"; then
    assert_record skills-delivery.catalog_exact 0 '15-skill catalog matches physical inventory' || true
  else
    assert_record skills-delivery.catalog_exact 1 'skill catalog differs from physical inventory' || true
  fi

  if test -d "$SOURCE_ROOT/skills"; then
    assert_record skills-delivery.no_root_copy 1 'root skills directory exists' || true
  else
    assert_record skills-delivery.no_root_copy 0 'root skills directory absent' || true
  fi

  SKILLS_DELIVERY_DATAFLOW="$SOURCE_ROOT/output/skills/sensai-dataflow-chart/SKILL.md"
  SKILLS_DELIVERY_STORY="$SOURCE_ROOT/output/skills/sensai-user-story/SKILL.md"
  SKILLS_DELIVERY_TEST="$SOURCE_ROOT/output/skills/sensai-test-scenario/SKILL.md"
  SKILLS_DELIVERY_REQUIREMENT="$SOURCE_ROOT/output/skills/sensai-requirement-analyze/SKILL.md"
  SKILLS_DELIVERY_DESIGN="$SOURCE_ROOT/output/skills/sensai-change-design/SKILL.md"

  if rg -q --no-config '`DATA-ASIS-<NNN>`.*`DATA-TOBE-<NNN>`' "$SKILLS_DELIVERY_DATAFLOW" && \
     rg -q --no-config '`STORY-ASIS-<NNN>`.*`STORY-TOBE-<NNN>`' "$SKILLS_DELIVERY_STORY" && \
     rg -q --no-config '`TEST-ASIS-<NNN>`.*`TEST-TOBE-<NNN>`' "$SKILLS_DELIVERY_TEST" && \
     rg -q --no-config '`REQ-EXT-<NNNN>`' "$SKILLS_DELIVERY_REQUIREMENT" && \
     rg -q --no-config '`DESIGN-PAGE|SERVICE|API|ENTITY-<NNN>`' "$SKILLS_DELIVERY_DESIGN"; then
    assert_record skills-delivery.stable_ids 0 'DATA STORY TEST REQ DESIGN stable ID families are explicit' || true
  else
    assert_record skills-delivery.stable_ids 1 'stable ID family missing' || true
  fi

  if rg -q --no-config '`follows_convention_ids`.*`follows_business_ids`' "$SKILLS_DELIVERY_DESIGN" && \
     rg -q --no-config '`bindings\[\]`' "$SKILLS_DELIVERY_DESIGN" && \
     rg -q --no-config '`gate: violation`' "$SKILLS_DELIVERY_DESIGN"; then
    assert_record skills-delivery.design_binding 0 'design binds convention and business with explicit violation gate' || true
  else
    assert_record skills-delivery.design_binding 1 'design binding or violation gate missing' || true
  fi

  if rg -q --no-config '`user`, `elicited`, `inferred`' "$SKILLS_DELIVERY_REQUIREMENT" && \
     rg -q --no-config '`MUST`, `SHOULD`, `MAY`' "$SKILLS_DELIVERY_REQUIREMENT" && \
     rg -q --no-config '`GIVEN`, `WHEN`, `THEN`' "$SKILLS_DELIVERY_TEST" && \
     rg -q --no-config 'per-run.*사람' "$SKILLS_DELIVERY_TEST"; then
    assert_record skills-delivery.workflow_binding 0 'requirement sources and manual test trigger are explicit' || true
  else
    assert_record skills-delivery.workflow_binding 1 'source, scenario, or manual trigger contract missing' || true
  fi

  if rg -q --no-config 'D4/F3.*사람.*승인' "$SKILLS_DELIVERY_DESIGN" && \
     rg -q --no-config '컨벤션 위반' "$SKILLS_DELIVERY_DATAFLOW" "$SKILLS_DELIVERY_STORY" "$SKILLS_DELIVERY_TEST" "$SKILLS_DELIVERY_REQUIREMENT" "$SKILLS_DELIVERY_DESIGN"; then
    assert_record skills-delivery.human_gate 0 'violation and human approval gates are preserved' || true
  else
    assert_record skills-delivery.human_gate 1 'human violation gate missing' || true
  fi

  SKILLS_DELIVERY_PROMOTED=0
  while IFS= read -r SKILLS_DELIVERY_RELATIVE; do
    test -n "$SKILLS_DELIVERY_RELATIVE" || continue
    SKILLS_DELIVERY_NAME=${SKILLS_DELIVERY_RELATIVE#skills/}
    SKILLS_DELIVERY_NAME=${SKILLS_DELIVERY_NAME%/SKILL.md}
    if rg -F -q --no-config "$SKILLS_DELIVERY_NAME" "$SOURCE_ROOT/output/agents" "$SOURCE_ROOT/output/opencode.json"; then
      SKILLS_DELIVERY_PROMOTED=1
    fi
  done <<EOF
$SKILLS_DELIVERY_PATHS
EOF
  assert_eq skills-delivery.not_promoted 0 "$SKILLS_DELIVERY_PROMOTED" || true
  SKILLS_DELIVERY_VALUE_GATE_OK=1
  for SKILLS_DELIVERY_VALUE_GATE_FILE in \
    "$SOURCE_ROOT/output/commands/sensai/change-design.md" \
    "$SOURCE_ROOT/output/commands/sensai/deliver.md"; do
    if ! rg -q --no-config 'VALUE_PROVEN.*입학.*permission\.skill.*허용' \
      "$SKILLS_DELIVERY_VALUE_GATE_FILE"; then
      SKILLS_DELIVERY_VALUE_GATE_OK=0
    fi
  done
  if jq -e '
      .permission.skill["sensai-dataflow-chart"] == null and
      .permission.skill["sensai-user-story"] == null and
      .permission.skill["sensai-requirement-analyze"] == null and
      .permission.skill["sensai-change-design"] == null and
      .permission.skill["sensai-test-scenario"] == null
    ' "$SOURCE_ROOT/output/opencode.json" >/dev/null 2>&1 && \
     test "$SKILLS_DELIVERY_VALUE_GATE_OK" -eq 1; then
    assert_record skills-delivery.value_proven_gate 0 \
      'delivery 후보 5 skill은 VALUE_PROVEN 전 exact deny다' || true
  else
    assert_record skills-delivery.value_proven_gate 1 \
      'delivery 후보 5 skill의 admission deny 계약이 다르다' || true
  fi

  for SKILLS_DELIVERY_FIXTURE in \
    fixtures/inputs/change/valid.md \
    fixtures/expected/trace-v2.json \
    fixtures/expected/asis/dataflow.mmd \
    fixtures/expected/tobe/story.md \
    fixtures/expected/tobe/test.md; do
    if ! test -f "$SOURCE_ROOT/$SKILLS_DELIVERY_FIXTURE" || test -L "$SOURCE_ROOT/$SKILLS_DELIVERY_FIXTURE"; then
      SKILLS_DELIVERY_FIXTURE_OK=0
      break
    fi
    SKILLS_DELIVERY_FIXTURE_OK=1
  done
  assert_eq skills-delivery.fixture_links 1 "${SKILLS_DELIVERY_FIXTURE_OK:-0}" || true
}

case_skills_delivery() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  skills_delivery_check_runtime || return 70
}
