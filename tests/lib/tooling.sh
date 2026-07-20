#!/bin/sh

SOURCE_ROOT=''
SOURCE_FINGERPRINT=''
SOURCE_FILE_COUNT=0
GIT_STATE='NOT_A_REPOSITORY'
UNTRACKED_COUNT=0
UNTRACKED_FILE=''
TOOLING_SHA256=''

tooling_wait_active_child() {
  wait "$ACTIVE_CHILD_PID"
  TOOLING_CHILD_EXIT=$?
  ACTIVE_CHILD_PID=''
  return "$TOOLING_CHILD_EXIT"
}

tooling_require_command() {
  TOOLING_COMMAND=$1
  if command -v "$TOOLING_COMMAND" >/dev/null 2>&1; then
    return 0
  fi
  printf 'INFRA_ERROR missing_command command=%s\n' "$TOOLING_COMMAND" >&2
  return 70
}

tooling_resolve_source_root() {
  TOOLING_ROOT=$1
  case "$TOOLING_ROOT" in
    /*) ;;
    *) printf 'INFRA_ERROR source_root_not_absolute path=%s\n' "$TOOLING_ROOT" >&2; return 70 ;;
  esac
  if ! test -d "$TOOLING_ROOT" || test -L "$TOOLING_ROOT"; then
    printf 'INFRA_ERROR unsafe_source_root path=%s\n' "$TOOLING_ROOT" >&2
    return 70
  fi
  SOURCE_ROOT=$(cd "$TOOLING_ROOT" 2>/dev/null && pwd -P) || return 70
  case "$SOURCE_ROOT" in
    /|'') printf 'INFRA_ERROR unsafe_source_root path=%s\n' "$SOURCE_ROOT" >&2; return 70 ;;
  esac
  return 0
}

tooling_sha256_file() {
  TOOLING_HASH_OUTPUT="$RUN_TMP/hash-output.txt"
  shasum -a 256 "$1" >"$TOOLING_HASH_OUTPUT" &
  ACTIVE_CHILD_PID=$!
  tooling_wait_active_child || return 70
  read -r TOOLING_SHA256 TOOLING_HASH_PATH <"$TOOLING_HASH_OUTPUT" || return 70
  test "${#TOOLING_SHA256}" -eq 64 || return 70
  return 0
}

tooling_source_leaf_regular() {
  TOOLING_SOURCE_RELATIVE=$1
  case "$TOOLING_SOURCE_RELATIVE" in
    ''|/*|*//* ) return 1 ;;
  esac
  TOOLING_SOURCE_CURRENT=$SOURCE_ROOT
  TOOLING_SOURCE_OLD_IFS=$IFS
  IFS=/
  set -f
  set -- $TOOLING_SOURCE_RELATIVE
  set +f
  IFS=$TOOLING_SOURCE_OLD_IFS
  test "$#" -gt 0 || return 1
  while test "$#" -gt 0; do
    TOOLING_SOURCE_COMPONENT=$1
    shift
    case "$TOOLING_SOURCE_COMPONENT" in
      ''|.|..) return 1 ;;
    esac
    TOOLING_SOURCE_CURRENT=$TOOLING_SOURCE_CURRENT/$TOOLING_SOURCE_COMPONENT
    test ! -L "$TOOLING_SOURCE_CURRENT" || return 1
    if test "$#" -gt 0; then
      test -d "$TOOLING_SOURCE_CURRENT" || return 1
    else
      test -f "$TOOLING_SOURCE_CURRENT" || return 1
    fi
  done
  return 0
}

tooling_fingerprint_source() {
  FINGERPRINT_NUL="$RUN_TMP/fingerprint-files.nul"
  FINGERPRINT_UNSORTED="$RUN_TMP/fingerprint-files-unsorted.txt"
  FINGERPRINT_FILES="$RUN_TMP/fingerprint-files.txt"
  FINGERPRINT_LINES="$RUN_TMP/fingerprint-lines.txt"
  UNTRACKED_FILE="$RUN_TMP/untracked.txt"
  : >"$FINGERPRINT_NUL" || return 70
  : >"$FINGERPRINT_UNSORTED" || return 70
  : >"$FINGERPRINT_FILES" || return 70
  : >"$FINGERPRINT_LINES" || return 70
  : >"$UNTRACKED_FILE" || return 70

  if test "${SENSAI_TEST_INTERNAL:-0}" = 1 && test "${SENSAI_TEST_DELAY_FINGERPRINT:-0}" = 1; then
    TOOLING_DELAY_MARKER=${SENSAI_TEST_DELAY_READY:-}
    case "$TOOLING_DELAY_MARKER" in
      /*) ;;
      *) return 70 ;;
    esac
    sleep 30 &
    ACTIVE_CHILD_PID=$!
    printf '%s\n' "$ACTIVE_CHILD_PID" >"$TOOLING_DELAY_MARKER" || return 70
    tooling_wait_active_child || return 70
  fi

  TOOLING_GIT_PROBE="$RUN_TMP/git-probe.txt"
  git -C "$SOURCE_ROOT" rev-parse --is-inside-work-tree >"$TOOLING_GIT_PROBE" 2>/dev/null &
  ACTIVE_CHILD_PID=$!
  tooling_wait_active_child
  TOOLING_GIT_PROBE_EXIT=$?
  if test "$TOOLING_GIT_PROBE_EXIT" -eq 0; then
    git -C "$SOURCE_ROOT" ls-files --cached --others --exclude-standard -z \
      >"$FINGERPRINT_NUL" 2>/dev/null &
    ACTIVE_CHILD_PID=$!
    tooling_wait_active_child || return 70
    perl -0ne '
      chomp;
      exit 1 if $_ eq q{} || m{^/} || m{(?:^|/)\.\.?(/|$)} || /[\x00-\x1f\x7f]/;
      print $_, qq{\n};
    ' "$FINGERPRINT_NUL" >"$FINGERPRINT_UNSORTED" || return 70
  else
    find "$SOURCE_ROOT" -path "$SOURCE_ROOT/.git" -prune -o -type f -print0 \
      >"$FINGERPRINT_NUL" &
    ACTIVE_CHILD_PID=$!
    tooling_wait_active_child || return 70
    TOOLING_SOURCE_ROOT=$SOURCE_ROOT perl -0ne '
      chomp;
      my $root = $ENV{TOOLING_SOURCE_ROOT};
      exit 1 unless defined $root && index($_, $root . q{/}) == 0;
      my $relative = substr($_, length($root) + 1);
      exit 1 if $relative eq q{} || $relative =~ m{^/} ||
        $relative =~ m{(?:^|/)\.\.?(/|$)} || $relative =~ /[\x00-\x1f\x7f]/;
      print $relative, qq{\n};
    ' "$FINGERPRINT_NUL" >"$FINGERPRINT_UNSORTED" || return 70
  fi

  LC_ALL=C sort "$FINGERPRINT_UNSORTED" >"$FINGERPRINT_FILES" &
  ACTIVE_CHILD_PID=$!
  tooling_wait_active_child || return 70

  SOURCE_FILE_COUNT=0
  while IFS= read -r TOOLING_RELATIVE; do
    tooling_source_leaf_regular "$TOOLING_RELATIVE" || return 70
    TOOLING_FILE=$SOURCE_ROOT/$TOOLING_RELATIVE
    tooling_sha256_file "$TOOLING_FILE" || return 70
    printf '%s\t%s\n' "$TOOLING_RELATIVE" "$TOOLING_SHA256" >>"$FINGERPRINT_LINES" || return 70
    SOURCE_FILE_COUNT=$((SOURCE_FILE_COUNT + 1))
  done <"$FINGERPRINT_FILES"

  tooling_sha256_file "$FINGERPRINT_LINES" || return 70
  SOURCE_FINGERPRINT=$TOOLING_SHA256

  if test "$TOOLING_GIT_PROBE_EXIT" -eq 0; then
    git -C "$SOURCE_ROOT" rev-parse --verify HEAD >"$TOOLING_GIT_PROBE" 2>/dev/null &
    ACTIVE_CHILD_PID=$!
    tooling_wait_active_child
    TOOLING_HEAD_EXIT=$?
    if test "$TOOLING_HEAD_EXIT" -eq 0; then
      read -r GIT_STATE <"$TOOLING_GIT_PROBE" || return 70
    else
      GIT_STATE=UNBORN
    fi
    TOOLING_GIT_STATUS_RAW="$RUN_TMP/git-status-raw.txt"
    git -C "$SOURCE_ROOT" status --short --untracked-files=all >"$TOOLING_GIT_STATUS_RAW" 2>/dev/null &
    ACTIVE_CHILD_PID=$!
    tooling_wait_active_child || return 70
    cp "$TOOLING_GIT_STATUS_RAW" "$UNTRACKED_FILE" || return 70
    UNTRACKED_COUNT=0
    while IFS= read -r TOOLING_UNTRACKED_LINE; do
      test -n "$TOOLING_UNTRACKED_LINE" || continue
      UNTRACKED_COUNT=$((UNTRACKED_COUNT + 1))
    done <"$UNTRACKED_FILE"
  else
    GIT_STATE=NOT_A_REPOSITORY
    UNTRACKED_COUNT=0
  fi
  return 0
}
