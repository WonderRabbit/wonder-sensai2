#!/bin/sh

doctor_assert_command_binding() {
  DOCTOR_COMMAND_BINDINGS=$DOCTOR_BASE/command-bindings.txt
  DOCTOR_EXPECTED_BINDINGS=$DOCTOR_BASE/expected-command-bindings.txt
  rg -o --no-filename --no-config '`[^`]*sensai[^`]* mission (init|checkpoint|resume|status)[^`]*`' \
    "$SOURCE_ROOT/output/commands/sensai/run.md" \
    "$SOURCE_ROOT/output/commands/sensai/resume.md" \
    "$SOURCE_ROOT/output/commands/sensai/status.md" | LC_ALL=C sort \
    >"$DOCTOR_COMMAND_BINDINGS" || return 70
  printf '%s\n' \
    '`"$HOME/.local/bin/sensai" mission checkpoint <mission-id> <candidate-progress.json> <expected-revision> <expected-sha256>`' \
    '`"$HOME/.local/bin/sensai" mission init <mission-id> <target-relative-path> <goal>`' \
    '`"$HOME/.local/bin/sensai" mission resume <mission-id> [<expected-revision> <expected-sha256>]`' \
    '`"$HOME/.local/bin/sensai" mission status <mission-id>`' \
    >"$DOCTOR_EXPECTED_BINDINGS" || return 70
  if cmp -s "$DOCTOR_EXPECTED_BINDINGS" "$DOCTOR_COMMAND_BINDINGS" && \
     ! rg -q --no-config '\$OPENCODE_CONFIG_DIR[^[:space:]]*sensai|(^|[^A-Z_])\./bin/sensai mission' "$SOURCE_ROOT/output/commands/sensai" && \
     ! rg -q --no-config 'output/(schemas|recipes)(/|$)' \
       "$SOURCE_ROOT/output/commands/sensai/run.md" \
       "$SOURCE_ROOT/output/commands/sensai/resume.md" \
       "$SOURCE_ROOT/output/commands/sensai/status.md"; then
    assert_record doctor.command_binding 0 'run/resume/status command가 설치된 결정적 mission helper에 결합되고 runtime asset 경로를 직접 조립하지 않는다' || true
  else
    assert_record doctor.command_binding 1 'command의 mission helper 결합 또는 runtime asset 해석 경계가 잘못됐다' || true
  fi
}
