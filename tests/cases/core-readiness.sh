#!/bin/sh

core_clone_without_manifest() {
  CORE_CLONE_DEST=$1
  mkdir -p "$CORE_CLONE_DEST/bin" || return 70
  cp "$SOURCE_ROOT/AGENTS.md" "$CORE_CLONE_DEST/AGENTS.md" || return 70
  cp "$SOURCE_ROOT/bin/sensai" "$CORE_CLONE_DEST/bin/sensai" || return 70
  cp -R "$SOURCE_ROOT/output" "$CORE_CLONE_DEST/output" || return 70
  cp -R "$SOURCE_ROOT/fixtures" "$CORE_CLONE_DEST/fixtures" || return 70
  cp -R "$SOURCE_ROOT/tests" "$CORE_CLONE_DEST/tests" || return 70
}

case_core_readiness() {
  CASE_TOTAL=$((CASE_TOTAL + 1))
  CORE_FAILED_BEFORE=$ASSERT_FAILED

  assert_file core.runtime_agents "$SOURCE_ROOT/output/AGENTS.md" || true
  assert_file core.config "$SOURCE_ROOT/output/opencode.json" || true
  assert_file core.toolchain "$SOURCE_ROOT/output/toolchain.lock.json" || true
  assert_dir core.agents "$SOURCE_ROOT/output/agents" || true
  assert_dir core.commands "$SOURCE_ROOT/output/commands" || true
  assert_dir core.skills "$SOURCE_ROOT/output/skills" || true
  assert_dir core.schemas "$SOURCE_ROOT/output/schemas" || true
  assert_dir core.recipes "$SOURCE_ROOT/output/recipes" || true
  assert_dir core.fixtures "$SOURCE_ROOT/fixtures" || true
  assert_file core.manifest "$SOURCE_ROOT/manifest.txt" || true
  assert_file core.bin "$SOURCE_ROOT/bin/sensai" || true

  if test "$ASSERT_FAILED" -gt "$CORE_FAILED_BEFORE"; then
    evidence_add_reason CORE_NOT_READY
  fi
}
