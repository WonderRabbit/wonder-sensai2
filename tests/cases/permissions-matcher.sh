#!/bin/sh

permissions_resolve_rules() {
  PERMISSIONS_RULE_FILE=$1
  PERMISSIONS_RULE_FILTER=$2
  PERMISSIONS_RULE_SUBJECT=$3
  PERMISSIONS_RULE_PLATFORM=${4:-posix}
  PERMISSIONS_RESOLVED=$(jq -r --arg subject "$PERMISSIONS_RULE_SUBJECT" \
    --arg platform "$PERMISSIONS_RULE_PLATFORM" "
    def slash_normalized:
      [explode[] | if . == 92 then 47 else . end] | implode;
    def wildcard_regex:
      slash_normalized |
      [explode[] | . as \$cp |
        if \$cp == 42 then \".*\"
        elif \$cp == 63 then \".\"
        elif [46,43,94,36,123,125,40,41,124,91,93,92] | index(\$cp)
        then \"\\\\\" + ([\$cp] | implode)
        else [\$cp] | implode
        end] |
      join(\"\") |
      if endswith(\" .*\") then .[0:-3] + \"( .*)?\" else . end |
      \"^\" + . + \"$\";
    (\$subject | slash_normalized) as \$normalized_subject |
    [$PERMISSIONS_RULE_FILTER | to_entries[] |
      select(.value | type == \"string\")] |
    [.[] | . as \$rule |
      select(\$normalized_subject |
        test(\$rule.key | wildcard_regex; if \$platform == \"win32\" then \"si\" else \"s\" end)) |
      \$rule.value] |
    last // \"ask\"
  " "$PERMISSIONS_RULE_FILE") || return 70
}

permissions_record_probe() {
  PERMISSIONS_PROBE_GROUP=$1
  PERMISSIONS_PROBE_DOMAIN=$2
  PERMISSIONS_PROBE_FILE=$3
  PERMISSIONS_PROBE_FILTER=$4
  PERMISSIONS_PROBE_SUBJECT=$5
  PERMISSIONS_PROBE_EXPECTED=$6
  PERMISSIONS_PROBE_PLATFORM=${7:-posix}
  PERMISSIONS_PROBE_INDEX=$((PERMISSIONS_PROBE_INDEX + 1))

  permissions_resolve_rules "$PERMISSIONS_PROBE_FILE" "$PERMISSIONS_PROBE_FILTER" "$PERMISSIONS_PROBE_SUBJECT" "$PERMISSIONS_PROBE_PLATFORM" || return 70
  jq -cn --arg group "$PERMISSIONS_PROBE_GROUP" --arg domain "$PERMISSIONS_PROBE_DOMAIN" \
    --arg subject "$PERMISSIONS_PROBE_SUBJECT" --arg expected "$PERMISSIONS_PROBE_EXPECTED" \
    --arg resolved "$PERMISSIONS_RESOLVED" \
    --arg platform "$PERMISSIONS_PROBE_PLATFORM" \
    '{group:$group,domain:$domain,platform:$platform,subject:$subject,expected:$expected,resolved:$resolved,pass:($expected == $resolved)}' \
    >>"$PERMISSIONS_PROBE_JSONL" || return 70
}
