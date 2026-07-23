#!/bin/sh

for PERMISSIONS_CASE_COMPONENT in matcher projection codegraph repository; do
  PERMISSIONS_CASE_SOURCE="$SCRIPT_DIR/cases/permissions-$PERMISSIONS_CASE_COMPONENT.sh"
  test -f "$PERMISSIONS_CASE_SOURCE" || {
    printf 'INFRA_ERROR missing_test_case path=%s\n' "$PERMISSIONS_CASE_SOURCE" >&2
    exit "${EX_INFRA:-70}"
  }
  . "$PERMISSIONS_CASE_SOURCE"
done

case_permissions() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  PERMISSIONS_CONFIG="$SOURCE_ROOT/output/opencode.json"
  assert_file permissions.config "$PERMISSIONS_CONFIG" || true
  assert_file permissions.lead "$SOURCE_ROOT/output/agents/sensai-analysis-lead.md" || true
  assert_file permissions.peer "$SOURCE_ROOT/output/agents/sensai-evidence-peer.md" || true
  if ! jq empty "$PERMISSIONS_CONFIG" >/dev/null 2>&1; then
    assert_record permissions.config_json 1 'opencode.json parse 실패' || true
    return 0
  fi
  assert_record permissions.config_json 0 'opencode.json parse 성공' || true
  permissions_extract_agents || return 70
  permissions_check_exact_allows "$PERMISSIONS_CONFIG" || return 70
  permissions_run_projection "$PERMISSIONS_CONFIG" || return 70
  permissions_check_matcher_1183 || return 70
  permissions_run_codegraph_projection "$PERMISSIONS_CONFIG" || return 70
  if rg -q --no-config '현재 대상 저장소.*명시적으로 선택.*읽기 전용' \
       "$SOURCE_ROOT/output/agents/sensai-analysis-lead.md" \
       "$SOURCE_ROOT/output/agents/sensai-evidence-peer.md" && \
     rg -q --no-config '쓰기.*docs/analysis/missions/<mission-id>/' \
       "$SOURCE_ROOT/output/agents/sensai-analysis-lead.md" && \
     test "$(rg -l --no-config '명시적으로 선택된 원본.*읽기 전용' \
       "$SOURCE_ROOT"/output/skills/*/SKILL.md | wc -l | tr -d ' ')" -eq 15; then
    assert_record permissions.target_read_mission_write 0 \
      'target source는 read-only이고 write는 mission root로 제한된다' || true
  else
    assert_record permissions.target_read_mission_write 1 \
      'target read와 mission write 경계가 불완전하다' || true
  fi
  assert_jq permissions.delivery_value_proven_deny '
    .permission.skill["*"] == "deny" and
    .permission.skill["sensai-dataflow-chart"] == null and
    .permission.skill["sensai-user-story"] == null and
    .permission.skill["sensai-requirement-analyze"] == null and
    .permission.skill["sensai-change-design"] == null and
    .permission.skill["sensai-test-scenario"] == null
  ' "$PERMISSIONS_CONFIG" || true

  assert_jq permissions.external_directory '.permission.external_directory == "deny"' \
    "$PERMISSIONS_CONFIG" || true
  assert_jq permissions.forbidden_extension_config '
    . as $root |
    (["mcp","plugin","plugins","tools","customTools","custom_tools"] |
      all(. as $key | $root | has($key) | not))
  ' "$PERMISSIONS_CONFIG" || true
  if rg -q --no-config '운영체제 샌드박스가 아니다' "$SOURCE_ROOT/output/AGENTS.md" && \
     rg -q --no-config '격리를 제공한다고 주장하지 않는다' "$SOURCE_ROOT/output/AGENTS.md"; then
    assert_record permissions.os_sandbox_nonclaim 0 'prompt와 permission의 OS sandbox 비보장을 명시함' || true
  else
    assert_record permissions.os_sandbox_nonclaim 1 'OS sandbox 비보장 문구가 없음' || true
  fi

  if test "${SENSAI_TEST_PERMISSIONS_INNER:-0}" != 1; then
    permissions_check_runtime_boundaries "$PERMISSIONS_CONFIG" || return 70
    permissions_check_secrets || return 70
  else
    jq -n '{skipped:true,reason:"isolated permission mutation"}' \
      >"$EVIDENCE_DIR/source-inventory.json" || return 70
    jq -n '{skipped:true,reason:"isolated permission mutation"}' \
      >"$EVIDENCE_DIR/secret-scan.json" || return 70
  fi
  permissions_write_hashes || return 70
}
