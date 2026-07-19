#!/bin/sh

SKILLS_CORE_PATHS='skills/sensai-evidence-first/SKILL.md
skills/sensai-mermaid-sequence/SKILL.md
skills/sensai-react-trace/SKILL.md
skills/sensai-spec-evidence/SKILL.md
skills/sensai-ui-definition/SKILL.md
skills/sensai-vertx-trace/SKILL.md'

skills_core_clone_source() {
  SKILLS_CORE_CLONE_ROOT=$1
  mkdir -p "$SKILLS_CORE_CLONE_ROOT/output" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$SKILLS_CORE_CLONE_ROOT/AGENTS.md" || return 70
  cp -R "$SOURCE_ROOT/tests" "$SKILLS_CORE_CLONE_ROOT/tests" || return 70
  cp "$SOURCE_ROOT/output/AGENTS.md" "$SOURCE_ROOT/output/opencode.json" \
    "$SOURCE_ROOT/output/toolchain.lock.json" "$SKILLS_CORE_CLONE_ROOT/output/" || return 70
  cp -R "$SOURCE_ROOT/output/agents" "$SKILLS_CORE_CLONE_ROOT/output/agents" || return 70
  cp -R "$SOURCE_ROOT/output/skills" "$SKILLS_CORE_CLONE_ROOT/output/skills" || return 70
}

skills_core_check_runtime() {
  SKILLS_CORE_FRONTMATTER_OK=1
  SKILLS_CORE_BODY_OK=1
  SKILLS_CORE_EVIDENCE_OK=1
  SKILLS_CORE_PERMISSION_OK=1
  SKILLS_CORE_FAILURE_OK=1
  SKILLS_CORE_KOREAN_OK=1
  SKILLS_CORE_SAFE_OK=1
  SKILLS_CORE_EXACT_OK=1
  SKILLS_CORE_COUNT=0

  while IFS= read -r SKILLS_CORE_RELATIVE; do
    test -n "$SKILLS_CORE_RELATIVE" || continue
    SKILLS_CORE_COUNT=$((SKILLS_CORE_COUNT + 1))
    SKILLS_CORE_FILE="$SOURCE_ROOT/output/$SKILLS_CORE_RELATIVE"
    SKILLS_CORE_NAME=${SKILLS_CORE_RELATIVE#skills/}
    SKILLS_CORE_NAME=${SKILLS_CORE_NAME%/SKILL.md}
    SKILLS_CORE_JSON="$RUN_TMP/skills-core-$SKILLS_CORE_COUNT.json"
    SKILLS_CORE_BODY="$RUN_TMP/skills-core-$SKILLS_CORE_COUNT.md"

    assert_file "skills-core.file_${SKILLS_CORE_COUNT}" "$SKILLS_CORE_FILE" || true
    if ! test -f "$SKILLS_CORE_FILE" || test -L "$SKILLS_CORE_FILE"; then
      SKILLS_CORE_FRONTMATTER_OK=0
      SKILLS_CORE_BODY_OK=0
      SKILLS_CORE_EVIDENCE_OK=0
      SKILLS_CORE_PERMISSION_OK=0
      SKILLS_CORE_FAILURE_OK=0
      SKILLS_CORE_KOREAN_OK=0
      SKILLS_CORE_SAFE_OK=0
      SKILLS_CORE_EXACT_OK=0
      continue
    fi

    if ! yq --front-matter=extract -o=json '.' "$SKILLS_CORE_FILE" >"$SKILLS_CORE_JSON" 2>/dev/null || \
       ! jq -e --arg name "$SKILLS_CORE_NAME" '
         keys_unsorted == ["name","description"] and
         .name == $name and
         (.name | test("^[a-z0-9]+(-[a-z0-9]+)*$")) and
         (.description | type == "string" and length >= 1 and length <= 1024) and
         (.description | test("[가-힣]"))
       ' "$SKILLS_CORE_JSON" >/dev/null 2>&1; then
      SKILLS_CORE_FRONTMATTER_OK=0
    fi

    awk 'BEGIN { marks=0 } /^---[[:space:]]*$/ { marks++; next } marks >= 2 { print }' \
      "$SKILLS_CORE_FILE" >"$SKILLS_CORE_BODY" || return 70
    if ! test -s "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '^## 입력$' "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '^## 작업 순서$' "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '^## 출력$' "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '^## 근거 계약$' "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '^## 허용 도구와 권한$' "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '^## 실패 처리$' "$SKILLS_CORE_BODY"; then
      SKILLS_CORE_BODY_OK=0
    fi
    if ! rg -q --no-config '근거 계약:.*`path:line`.*`evidence_ids`' "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '`UNKNOWN`' "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '`unresolved`' "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '`ambiguous`' "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '`conflict`' "$SKILLS_CORE_BODY"; then
      SKILLS_CORE_EVIDENCE_OK=0
    fi
    if ! rg -q --no-config '스킬 로드는 권한을 추가하지 않는다' "$SKILLS_CORE_BODY" || \
       ! rg -q --no-config '현재 미션 루트' "$SKILLS_CORE_BODY"; then
      SKILLS_CORE_PERMISSION_OK=0
    fi
    if ! rg -q --no-config '부분 산출물을 완료로 표시하지 않는다' "$SKILLS_CORE_BODY"; then
      SKILLS_CORE_FAILURE_OK=0
    fi
    if ! rg -q --no-config '[가-힣]' "$SKILLS_CORE_BODY"; then
      SKILLS_CORE_KOREAN_OK=0
    fi
    SKILLS_CORE_LINES=$(wc -l <"$SKILLS_CORE_FILE" | awk '{print $1}') || return 70
    if test "$SKILLS_CORE_LINES" -ge 500; then
      SKILLS_CORE_BODY_OK=0
    fi
    if rg -n --no-config '(^|[^a-z])(sudo|curl|wget|eval)([^a-z]|$)|rm[[:space:]]+-rf|git[[:space:]]+push|BEGIN (RSA|OPENSSH) PRIVATE KEY' \
      "$SKILLS_CORE_FILE" >/dev/null 2>&1; then
      SKILLS_CORE_SAFE_OK=0
    else
      SKILLS_CORE_SAFE_RC=$?
      test "$SKILLS_CORE_SAFE_RC" -eq 1 || return 70
    fi
    SKILLS_CORE_DIR=${SKILLS_CORE_FILE%/SKILL.md}
    SKILLS_CORE_LEAF_COUNT=$(find "$SKILLS_CORE_DIR" -mindepth 1 -maxdepth 1 -type f -print | wc -l | awk '{print $1}') || return 70
    SKILLS_CORE_OTHER_COUNT=$(find "$SKILLS_CORE_DIR" -mindepth 1 -maxdepth 1 ! -type f -print | wc -l | awk '{print $1}') || return 70
    if test "$SKILLS_CORE_LEAF_COUNT" -ne 1 || test "$SKILLS_CORE_OTHER_COUNT" -ne 0; then
      SKILLS_CORE_EXACT_OK=0
    fi
  done <<EOF
$SKILLS_CORE_PATHS
EOF

  assert_eq skills-core.count 6 "$SKILLS_CORE_COUNT" || true
  assert_eq skills-core.frontmatter 1 "$SKILLS_CORE_FRONTMATTER_OK" || true
  assert_eq skills-core.body_contract 1 "$SKILLS_CORE_BODY_OK" || true
  assert_eq skills-core.evidence_contract 1 "$SKILLS_CORE_EVIDENCE_OK" || true
  assert_eq skills-core.permission_boundary 1 "$SKILLS_CORE_PERMISSION_OK" || true
  assert_eq skills-core.failure_behavior 1 "$SKILLS_CORE_FAILURE_OK" || true
  assert_eq skills-core.korean_content 1 "$SKILLS_CORE_KOREAN_OK" || true
  assert_eq skills-core.safe_content 1 "$SKILLS_CORE_SAFE_OK" || true
  assert_eq skills-core.directory_exact 1 "$SKILLS_CORE_EXACT_OK" || true

  if test -d "$SOURCE_ROOT/skills"; then
    assert_record skills-core.no_root_copy 1 'root skills directory exists' || true
  else
    assert_record skills-core.no_root_copy 0 'root skills directory absent' || true
  fi
}

case_skills_core() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  skills_core_check_runtime || return 70
}
