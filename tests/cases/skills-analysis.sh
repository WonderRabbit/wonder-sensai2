#!/bin/sh

SKILLS_ANALYSIS_PATHS='skills/sensai-business-trace/SKILL.md
skills/sensai-checklist/SKILL.md
skills/sensai-convention-extract/SKILL.md
skills/sensai-stack-discovery/SKILL.md'

skills_analysis_clone_source() {
  SKILLS_ANALYSIS_CLONE_ROOT=$1
  mkdir -p "$SKILLS_ANALYSIS_CLONE_ROOT/output" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$SKILLS_ANALYSIS_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$SKILLS_ANALYSIS_CLONE_ROOT/tests" || return 70
  cp -R "$SOURCE_ROOT/fixtures" "$SKILLS_ANALYSIS_CLONE_ROOT/fixtures" || return 70
  cp -R "$SOURCE_ROOT/output/skills" "$SKILLS_ANALYSIS_CLONE_ROOT/output/skills" || return 70
  cp -R "$SOURCE_ROOT/output/schemas" "$SKILLS_ANALYSIS_CLONE_ROOT/output/schemas" || return 70
}

skills_analysis_check_runtime() {
  SKILLS_ANALYSIS_COUNT=0
  SKILLS_ANALYSIS_FRONTMATTER_OK=1
  SKILLS_ANALYSIS_BODY_OK=1
  SKILLS_ANALYSIS_EVIDENCE_OK=1
  SKILLS_ANALYSIS_PERMISSION_OK=1
  SKILLS_ANALYSIS_FAILURE_OK=1
  SKILLS_ANALYSIS_ADMISSION_OK=1
  SKILLS_ANALYSIS_DIRECTORY_OK=1

  while IFS= read -r SKILLS_ANALYSIS_RELATIVE; do
    test -n "$SKILLS_ANALYSIS_RELATIVE" || continue
    SKILLS_ANALYSIS_COUNT=$((SKILLS_ANALYSIS_COUNT + 1))
    SKILLS_ANALYSIS_FILE="$SOURCE_ROOT/output/$SKILLS_ANALYSIS_RELATIVE"
    SKILLS_ANALYSIS_NAME=${SKILLS_ANALYSIS_RELATIVE#skills/}
    SKILLS_ANALYSIS_NAME=${SKILLS_ANALYSIS_NAME%/SKILL.md}
    SKILLS_ANALYSIS_JSON="$RUN_TMP/skills-analysis-$SKILLS_ANALYSIS_COUNT.json"
    SKILLS_ANALYSIS_BODY="$RUN_TMP/skills-analysis-$SKILLS_ANALYSIS_COUNT.md"

    if ! test -f "$SKILLS_ANALYSIS_FILE" || test -L "$SKILLS_ANALYSIS_FILE"; then
      SKILLS_ANALYSIS_FRONTMATTER_OK=0
      SKILLS_ANALYSIS_BODY_OK=0
      SKILLS_ANALYSIS_EVIDENCE_OK=0
      SKILLS_ANALYSIS_PERMISSION_OK=0
      SKILLS_ANALYSIS_FAILURE_OK=0
      SKILLS_ANALYSIS_ADMISSION_OK=0
      SKILLS_ANALYSIS_DIRECTORY_OK=0
      continue
    fi

    if ! yq --front-matter=extract -o=json '.' "$SKILLS_ANALYSIS_FILE" >"$SKILLS_ANALYSIS_JSON" 2>/dev/null || \
       ! jq -e --arg name "$SKILLS_ANALYSIS_NAME" '
         keys_unsorted == ["name","description"] and
         .name == $name and
         (.description | type == "string" and length >= 1 and length <= 1024) and
         (.description | test("[가-힣]"))
       ' "$SKILLS_ANALYSIS_JSON" >/dev/null 2>&1; then
      SKILLS_ANALYSIS_FRONTMATTER_OK=0
    fi

    awk 'BEGIN { marks=0 } /^---[[:space:]]*$/ { marks++; next } marks >= 2 { print }' \
      "$SKILLS_ANALYSIS_FILE" >"$SKILLS_ANALYSIS_BODY" || return 70
    for SKILLS_ANALYSIS_HEADING in 입력 '작업 순서' 출력 '근거 계약' '허용 도구와 권한' '입학 상태' '실패 처리'; do
      if ! rg -q --no-config "^## $SKILLS_ANALYSIS_HEADING$" "$SKILLS_ANALYSIS_BODY"; then
        SKILLS_ANALYSIS_BODY_OK=0
      fi
    done
    if ! rg -q --no-config '근거 계약:.*`path:line`.*`evidence_ids`' "$SKILLS_ANALYSIS_BODY" || \
       ! rg -q --no-config '`UNKNOWN`' "$SKILLS_ANALYSIS_BODY" || \
       ! rg -q --no-config '`unresolved`' "$SKILLS_ANALYSIS_BODY" || \
       ! rg -q --no-config '`ambiguous`' "$SKILLS_ANALYSIS_BODY" || \
       ! rg -q --no-config '`conflict`' "$SKILLS_ANALYSIS_BODY"; then
      SKILLS_ANALYSIS_EVIDENCE_OK=0
    fi
    if ! rg -q --no-config '스킬 로드는 권한을 추가하지 않는다' "$SKILLS_ANALYSIS_BODY" || \
       ! rg -q --no-config '현재 미션 루트' "$SKILLS_ANALYSIS_BODY"; then
      SKILLS_ANALYSIS_PERMISSION_OK=0
    fi
    if ! rg -q --no-config '부분 산출물을 완료로 표시하지 않는다' "$SKILLS_ANALYSIS_BODY"; then
      SKILLS_ANALYSIS_FAILURE_OK=0
    fi
    for SKILLS_ANALYSIS_STATE in REQUIRED_TO_EVALUATE NOT_ADMITTED ADMITTED_NO_VALUE VALUE_PROVEN; do
      if ! rg -F -q --no-config "$SKILLS_ANALYSIS_STATE" "$SKILLS_ANALYSIS_BODY"; then
        SKILLS_ANALYSIS_ADMISSION_OK=0
      fi
    done

    SKILLS_ANALYSIS_DIR=${SKILLS_ANALYSIS_FILE%/SKILL.md}
    SKILLS_ANALYSIS_LEAF_COUNT=$(find "$SKILLS_ANALYSIS_DIR" -mindepth 1 -maxdepth 1 -type f -print | wc -l | awk '{print $1}') || return 70
    SKILLS_ANALYSIS_OTHER_COUNT=$(find "$SKILLS_ANALYSIS_DIR" -mindepth 1 -maxdepth 1 ! -type f -print | wc -l | awk '{print $1}') || return 70
    if test "$SKILLS_ANALYSIS_LEAF_COUNT" -ne 1 || test "$SKILLS_ANALYSIS_OTHER_COUNT" -ne 0; then
      SKILLS_ANALYSIS_DIRECTORY_OK=0
    fi
  done <<EOF
$SKILLS_ANALYSIS_PATHS
EOF

  assert_eq skills-analysis.count 4 "$SKILLS_ANALYSIS_COUNT" || true
  assert_eq skills-analysis.frontmatter 1 "$SKILLS_ANALYSIS_FRONTMATTER_OK" || true
  assert_eq skills-analysis.body_contract 1 "$SKILLS_ANALYSIS_BODY_OK" || true
  assert_eq skills-analysis.evidence_contract 1 "$SKILLS_ANALYSIS_EVIDENCE_OK" || true
  assert_eq skills-analysis.permission_boundary 1 "$SKILLS_ANALYSIS_PERMISSION_OK" || true
  assert_eq skills-analysis.failure_behavior 1 "$SKILLS_ANALYSIS_FAILURE_OK" || true
  assert_eq skills-analysis.admission_state 1 "$SKILLS_ANALYSIS_ADMISSION_OK" || true
  assert_eq skills-analysis.directory_exact 1 "$SKILLS_ANALYSIS_DIRECTORY_OK" || true

  SKILLS_ANALYSIS_SCHEMA="$SOURCE_ROOT/output/schemas/trace.schema.json"
  SKILLS_ANALYSIS_CONVENTION="$SOURCE_ROOT/output/skills/sensai-convention-extract/SKILL.md"
  SKILLS_ANALYSIS_BUSINESS="$SOURCE_ROOT/output/skills/sensai-business-trace/SKILL.md"
  SKILLS_ANALYSIS_STACK="$SOURCE_ROOT/output/skills/sensai-stack-discovery/SKILL.md"
  SKILLS_ANALYSIS_CHECKLIST="$SOURCE_ROOT/output/skills/sensai-checklist/SKILL.md"

  SKILLS_ANALYSIS_SCHEMA_CATEGORIES=$(jq -r '."$defs".convention.properties.category.enum | join(", ")' "$SKILLS_ANALYSIS_SCHEMA") || return 70
  assert_eq skills-analysis.convention_schema_enum \
    'COMPONENT, STRUCTURE, NAMING, API, STATE, ERROR, TEST' "$SKILLS_ANALYSIS_SCHEMA_CATEGORIES" || true
  if rg -F -q --no-config '`COMPONENT`, `STRUCTURE`, `NAMING`, `API`, `STATE`, `ERROR`, `TEST`' "$SKILLS_ANALYSIS_CONVENTION"; then
    assert_record skills-analysis.convention_skill_enum 0 'skill contains the exact seven frozen categories' || true
  else
    assert_record skills-analysis.convention_skill_enum 1 'skill category list differs from schema' || true
  fi

  if rg -q --no-config '`business_entity`.*`business_rule`.*`business_flow`.*`business_event`.*`business_state`.*`business_invariant`' "$SKILLS_ANALYSIS_BUSINESS" && \
     rg -q --no-config '`BIZ-ENT-\*`.*`BIZ-RULE-\*`.*`BIZ-FLOW-\*`.*`BIZ-EVT-\*`.*`BIZ-STATE-\*`.*`BIZ-INV-\*`' "$SKILLS_ANALYSIS_BUSINESS"; then
    assert_record skills-analysis.business_classes 0 'six business classes and stable ID families are present' || true
  else
    assert_record skills-analysis.business_classes 1 'business class or stable ID family missing' || true
  fi

  if rg -q --no-config '`UNSUPPORTED`' "$SKILLS_ANALYSIS_STACK" && \
     rg -q --no-config '강제 매핑하지 마라' "$SKILLS_ANALYSIS_STACK" && \
     rg -q --no-config '매니페스트.*직접 근거' "$SKILLS_ANALYSIS_STACK"; then
    assert_record skills-analysis.unsupported_preservation 0 'unknown stack remains unsupported without forced mapping' || true
  else
    assert_record skills-analysis.unsupported_preservation 1 'unsupported preservation contract missing' || true
  fi

  if rg -q --no-config '`DATAFLOW`는 컨벤션 범주가 아닌 산출물' "$SKILLS_ANALYSIS_CONVENTION"; then
    assert_record skills-analysis.dataflow_boundary 0 'DATAFLOW is explicitly outside convention categories' || true
  else
    assert_record skills-analysis.dataflow_boundary 1 'DATAFLOW boundary missing' || true
  fi

  if rg -q --no-config '`fixtures/adversarial/hidden-conflict.json`' "$SKILLS_ANALYSIS_BUSINESS" && \
     rg -q --no-config '`fixtures/adversarial/dangling-reference.json`' "$SKILLS_ANALYSIS_CHECKLIST"; then
    assert_record skills-analysis.adversarial_links 0 'conflict and dangling fixtures are linked' || true
  else
    assert_record skills-analysis.adversarial_links 1 'required adversarial fixture link missing' || true
  fi

  for SKILLS_ANALYSIS_FIXTURE in \
    fixtures/inputs/legacy-react/src/OrdersPage.tsx \
    fixtures/inputs/legacy-vertx/src/main/java/example/OrderVerticle.java \
    fixtures/inputs/business/order-rules.md \
    fixtures/inputs/business/order-state.json \
    fixtures/expected/trace-v2.json \
    fixtures/adversarial/hidden-conflict.json \
    fixtures/adversarial/dangling-reference.json; do
    if ! test -f "$SOURCE_ROOT/$SKILLS_ANALYSIS_FIXTURE" || test -L "$SOURCE_ROOT/$SKILLS_ANALYSIS_FIXTURE"; then
      SKILLS_ANALYSIS_FIXTURE_OK=0
      break
    fi
    SKILLS_ANALYSIS_FIXTURE_OK=1
  done
  assert_eq skills-analysis.fixture_links 1 "${SKILLS_ANALYSIS_FIXTURE_OK:-0}" || true

  if test -d "$SOURCE_ROOT/skills"; then
    assert_record skills-analysis.no_root_copy 1 'root skills directory exists' || true
  else
    assert_record skills-analysis.no_root_copy 0 'root skills directory absent' || true
  fi
}

case_skills_analysis() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  skills_analysis_check_runtime || return 70
}
