#!/bin/sh

ASSERT_TOTAL=0
ASSERT_FAILED=0
ASSERT_FAILED_IDS=''

assert_record() {
  ASSERT_RECORD_ID=$1
  ASSERT_RECORD_OK=$2
  ASSERT_RECORD_DETAIL=$3
  ASSERT_TOTAL=$((ASSERT_TOTAL + 1))

  if test "$ASSERT_RECORD_OK" -eq 0; then
    printf 'ASSERT_PASS id=%s detail=%s\n' "$ASSERT_RECORD_ID" "$ASSERT_RECORD_DETAIL"
    evidence_log_assertion "$ASSERT_RECORD_ID" PASS "$ASSERT_RECORD_DETAIL"
    return 0
  fi

  ASSERT_FAILED=$((ASSERT_FAILED + 1))
  if test -z "$ASSERT_FAILED_IDS"; then
    ASSERT_FAILED_IDS=$ASSERT_RECORD_ID
  else
    ASSERT_FAILED_IDS="${ASSERT_FAILED_IDS}
${ASSERT_RECORD_ID}"
  fi
  printf 'ASSERT_FAIL id=%s detail=%s\n' "$ASSERT_RECORD_ID" "$ASSERT_RECORD_DETAIL" >&2
  evidence_log_assertion "$ASSERT_RECORD_ID" FAIL "$ASSERT_RECORD_DETAIL"
  return 1
}
assert_eq() {
  ASSERT_EQ_ID=$1
  ASSERT_EQ_EXPECTED=$2
  ASSERT_EQ_ACTUAL=$3
  if test "$ASSERT_EQ_EXPECTED" = "$ASSERT_EQ_ACTUAL"; then
    assert_record "$ASSERT_EQ_ID" 0 "expected=$ASSERT_EQ_EXPECTED actual=$ASSERT_EQ_ACTUAL"
  else
    assert_record "$ASSERT_EQ_ID" 1 "expected=$ASSERT_EQ_EXPECTED actual=$ASSERT_EQ_ACTUAL"
  fi
}

assert_file() {
  ASSERT_FILE_ID=$1
  ASSERT_FILE_PATH=$2
  if test -f "$ASSERT_FILE_PATH" && ! test -L "$ASSERT_FILE_PATH"; then
    assert_record "$ASSERT_FILE_ID" 0 "regular_file=$ASSERT_FILE_PATH"
  else
    assert_record "$ASSERT_FILE_ID" 1 "missing_regular_file=$ASSERT_FILE_PATH"
  fi
}

assert_dir() {
  ASSERT_DIR_ID=$1
  ASSERT_DIR_PATH=$2
  if test -d "$ASSERT_DIR_PATH" && ! test -L "$ASSERT_DIR_PATH"; then
    assert_record "$ASSERT_DIR_ID" 0 "directory=$ASSERT_DIR_PATH"
  else
    assert_record "$ASSERT_DIR_ID" 1 "missing_directory=$ASSERT_DIR_PATH"
  fi
}

assert_jq() {
  ASSERT_JQ_ID=$1
  ASSERT_JQ_FILTER=$2
  ASSERT_JQ_FILE=$3
  if jq -e "$ASSERT_JQ_FILTER" "$ASSERT_JQ_FILE" >/dev/null 2>&1; then
    assert_record "$ASSERT_JQ_ID" 0 "jq=$ASSERT_JQ_FILTER file=$ASSERT_JQ_FILE"
  else
    assert_record "$ASSERT_JQ_ID" 1 "jq=$ASSERT_JQ_FILTER file=$ASSERT_JQ_FILE"
  fi
}
