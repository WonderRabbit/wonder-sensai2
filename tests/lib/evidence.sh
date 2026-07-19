#!/bin/sh

EVIDENCE_DIR=''
EVIDENCE_EXPLICIT=0
RUN_TMP=''
EVIDENCE_READY=0
CLEANUP_DONE=0
ACTIVE_CHILD_PID=''
SIGNAL_NAME=''
SIGNAL_CHILD_PID=''
SIGNAL_CHILD_REAPED=false

evidence_validate_path() {
  EVIDENCE_PATH=$1
  EVIDENCE_PHYSICAL_PWD=$(pwd -P) || return 70
  EVIDENCE_RAW_PWD=${PWD:-$EVIDENCE_PHYSICAL_PWD}
  EVIDENCE_RAW_PWD=${EVIDENCE_RAW_PWD%/}
  EVIDENCE_RAW_TMP=${TMPDIR:-/tmp}
  EVIDENCE_RAW_TMP=${EVIDENCE_RAW_TMP%/}
  EVIDENCE_PHYSICAL_TMP=$(cd "$EVIDENCE_RAW_TMP" 2>/dev/null && pwd -P) || return 70

  case "$EVIDENCE_PATH" in
    "$EVIDENCE_RAW_PWD")
      EVIDENCE_ANCHOR=$EVIDENCE_PHYSICAL_PWD
      EVIDENCE_REST=''
      ;;
    "$EVIDENCE_RAW_PWD"/*)
      EVIDENCE_ANCHOR=$EVIDENCE_PHYSICAL_PWD
      EVIDENCE_REST=${EVIDENCE_PATH#"$EVIDENCE_RAW_PWD"/}
      ;;
    "$EVIDENCE_PHYSICAL_PWD")
      EVIDENCE_ANCHOR=$EVIDENCE_PHYSICAL_PWD
      EVIDENCE_REST=''
      ;;
    "$EVIDENCE_PHYSICAL_PWD"/*)
      EVIDENCE_ANCHOR=$EVIDENCE_PHYSICAL_PWD
      EVIDENCE_REST=${EVIDENCE_PATH#"$EVIDENCE_PHYSICAL_PWD"/}
      ;;
    "$EVIDENCE_RAW_TMP")
      EVIDENCE_ANCHOR=$EVIDENCE_PHYSICAL_TMP
      EVIDENCE_REST=''
      ;;
    "$EVIDENCE_RAW_TMP"/*)
      EVIDENCE_ANCHOR=$EVIDENCE_PHYSICAL_TMP
      EVIDENCE_REST=${EVIDENCE_PATH#"$EVIDENCE_RAW_TMP"/}
      ;;
    "$EVIDENCE_PHYSICAL_TMP")
      EVIDENCE_ANCHOR=$EVIDENCE_PHYSICAL_TMP
      EVIDENCE_REST=''
      ;;
    "$EVIDENCE_PHYSICAL_TMP"/*)
      EVIDENCE_ANCHOR=$EVIDENCE_PHYSICAL_TMP
      EVIDENCE_REST=${EVIDENCE_PATH#"$EVIDENCE_PHYSICAL_TMP"/}
      ;;
    /*)
      EVIDENCE_ANCHOR=/
      EVIDENCE_REST=${EVIDENCE_PATH#/}
      ;;
    *)
      EVIDENCE_ANCHOR=$EVIDENCE_PHYSICAL_PWD
      EVIDENCE_REST=$EVIDENCE_PATH
      ;;
  esac

  EVIDENCE_OLD_IFS=$IFS
  IFS=/
  set -f
  set -- $EVIDENCE_REST
  set +f
  IFS=$EVIDENCE_OLD_IFS
  EVIDENCE_INVALID=0
  for EVIDENCE_COMPONENT do
    case "$EVIDENCE_COMPONENT" in
      ''|.) continue ;;
      ..)
        printf 'INFRA_ERROR evidence_parent_traversal path=%s\n' "$EVIDENCE_PATH" >&2
        EVIDENCE_INVALID=1
        break
        ;;
    esac
    if test "$EVIDENCE_ANCHOR" = /; then
      EVIDENCE_CANDIDATE="/$EVIDENCE_COMPONENT"
    else
      EVIDENCE_CANDIDATE="$EVIDENCE_ANCHOR/$EVIDENCE_COMPONENT"
    fi
    if test -L "$EVIDENCE_CANDIDATE"; then
      printf 'INFRA_ERROR evidence_symlink_component path=%s\n' "$EVIDENCE_CANDIDATE" >&2
      EVIDENCE_INVALID=1
      break
    fi
    if test -e "$EVIDENCE_CANDIDATE" && ! test -d "$EVIDENCE_CANDIDATE"; then
      printf 'INFRA_ERROR evidence_nondirectory_component path=%s\n' "$EVIDENCE_CANDIDATE" >&2
      EVIDENCE_INVALID=1
      break
    fi
    EVIDENCE_ANCHOR=$EVIDENCE_CANDIDATE
  done
  test "$EVIDENCE_INVALID" -eq 0 || return 70
  printf '%s\n' "$EVIDENCE_ANCHOR"
}

evidence_prepare() {
  EVIDENCE_REQUESTED=$1
  RUN_TMP=$(mktemp -d "${TMPDIR:-/tmp}/sensai-test.XXXXXX") || return 70
  case "$RUN_TMP" in
    "${TMPDIR:-/tmp}"/sensai-test.*) ;;
    *) printf 'INFRA_ERROR unsafe_temp_root path=%s\n' "$RUN_TMP" >&2; return 70 ;;
  esac

  if test -n "$EVIDENCE_REQUESTED"; then
    EVIDENCE_EXPLICIT=1
    EVIDENCE_EXPECTED=$(evidence_validate_path "$EVIDENCE_REQUESTED") || return 70
    if test -d "$EVIDENCE_EXPECTED" && test -n "$(find "$EVIDENCE_EXPECTED" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)"; then
      printf 'INFRA_ERROR stale_evidence path=%s\n' "$EVIDENCE_EXPECTED" >&2
      return 70
    fi
    mkdir -p "$EVIDENCE_EXPECTED" || return 70
    EVIDENCE_POST_CREATE=$(evidence_validate_path "$EVIDENCE_EXPECTED") || return 70
    EVIDENCE_CANONICAL=$(cd "$EVIDENCE_EXPECTED" 2>/dev/null && pwd -P) || return 70
    if test "$EVIDENCE_POST_CREATE" != "$EVIDENCE_EXPECTED" || test "$EVIDENCE_CANONICAL" != "$EVIDENCE_EXPECTED"; then
      printf 'INFRA_ERROR evidence_canonical_mismatch expected=%s actual=%s\n' "$EVIDENCE_EXPECTED" "$EVIDENCE_CANONICAL" >&2
      return 70
    fi
    EVIDENCE_DIR=$EVIDENCE_EXPECTED
  else
    EVIDENCE_DIR="$RUN_TMP/evidence"
    mkdir "$EVIDENCE_DIR" || return 70
  fi

  : >"$EVIDENCE_DIR/assertions.jsonl" || return 70
  : >"$EVIDENCE_DIR/commands.jsonl" || return 70
  : >"$EVIDENCE_DIR/reasons.txt" || return 70
  EVIDENCE_READY=1
  return 0
}

evidence_log_assertion() {
  test "$EVIDENCE_READY" -eq 1 || return 0
  jq -cn --arg id "$1" --arg result "$2" --arg detail "$3" \
    '{id:$id,result:$result,detail:$detail}' >>"$EVIDENCE_DIR/assertions.jsonl"
}

evidence_log_command() {
  test "$EVIDENCE_READY" -eq 1 || return 0
  jq -cn --arg name "$1" --arg command "$2" --argjson exit "$3" \
    '{name:$name,command:$command,exit:$exit}' >>"$EVIDENCE_DIR/commands.jsonl"
}

evidence_add_reason() {
  test "$EVIDENCE_READY" -eq 1 || return 0
  printf '%s\n' "$1" >>"$EVIDENCE_DIR/reasons.txt"
}

evidence_cleanup() {
  CLEANUP_EXIT=$?
  test "$CLEANUP_DONE" -eq 0 || return "$CLEANUP_EXIT"
  CLEANUP_DONE=1

  if test -n "$RUN_TMP"; then
    case "$RUN_TMP" in
      "${TMPDIR:-/tmp}"/sensai-test.*)
        rm -rf "$RUN_TMP"
        CLEANUP_REMOVED=true
        ;;
      *)
        CLEANUP_REMOVED=false
        ;;
    esac
  else
    CLEANUP_REMOVED=true
  fi

  if test "$EVIDENCE_EXPLICIT" -eq 1 && test -d "$EVIDENCE_DIR"; then
    jq -n \
      --arg status "$(test "$CLEANUP_REMOVED" = true && printf PASS || printf FAIL)" \
      --arg temp_root "$RUN_TMP" \
      --argjson temp_removed "$CLEANUP_REMOVED" \
      --argjson exit "$CLEANUP_EXIT" \
      --arg signal "$SIGNAL_NAME" \
      --arg signal_child_pid "$SIGNAL_CHILD_PID" \
      --argjson signal_child_reaped "$SIGNAL_CHILD_REAPED" \
      '{status:$status,temp_root:$temp_root,temp_removed:$temp_removed,processes_started:[],ports_opened:[],exit:$exit,signal:$signal,signal_child_pid:$signal_child_pid,signal_child_reaped:$signal_child_reaped}' \
      >"$EVIDENCE_DIR/cleanup.json"
  fi
  return "$CLEANUP_EXIT"
}

evidence_handle_signal() {
  SIGNAL_NAME=$1
  SIGNAL_CHILD_PID=${ACTIVE_CHILD_PID:-}
  if test -n "$SIGNAL_CHILD_PID"; then
    kill -TERM "$SIGNAL_CHILD_PID" 2>/dev/null || true
    wait "$SIGNAL_CHILD_PID" 2>/dev/null || true
    ACTIVE_CHILD_PID=''
    SIGNAL_CHILD_REAPED=true
  fi
  exit 130
}

evidence_install_traps() {
  trap 'evidence_handle_signal HUP' HUP
  trap 'evidence_handle_signal INT' INT
  trap 'evidence_handle_signal TERM' TERM
  trap 'evidence_cleanup' EXIT
}
