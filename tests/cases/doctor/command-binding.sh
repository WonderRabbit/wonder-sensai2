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
  if cmp -s "$DOCTOR_EXPECTED_BINDINGS" "$DOCTOR_COMMAND_BINDINGS"; then
    assert_record doctor.command_binding 0 'run/resume/status command가 설치된 결정적 mission helper에 결합됐다' || true
  else
    assert_record doctor.command_binding 1 'command와 mission helper 결합이 빠졌다' || true
  fi
}
