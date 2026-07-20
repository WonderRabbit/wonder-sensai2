#!/bin/sh

packaging_adversarial_run_target_and_manifest_cases() {
  PA_ROOT=$PA_BASE/relative-target-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  set +e
  (cd "$PA_BASE" && "$PA_ROOT/bin/sensai" stage relative-target) \
    >"$RUN_TMP/pa-relative-target.out" 2>"$RUN_TMP/pa-relative-target.err"
  PA_RC=$?
  PA_REASON=$(packaging_adversarial_reason "$RUN_TMP/pa-relative-target.err") || return 70
  assert_eq packaging-adversarial.relative_target.exit 65 "$PA_RC" || true
  assert_eq packaging-adversarial.relative_target.reason package.target_not_absolute "$PA_REASON" || true
  PA_ABSENT=true; test ! -e "$PA_BASE/relative-target" || PA_ABSENT=false
  PA_CLEAN=true; packaging_adversarial_no_transaction_artifacts "$PA_BASE" || PA_CLEAN=false
  packaging_adversarial_record_matrix relative_target 65 "$PA_RC" package.target_not_absolute "$PA_REASON" "$PA_ABSENT" "$PA_CLEAN" || return 70

  PA_ROOT=$PA_BASE/normalized-target-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  mkdir -p "$PA_BASE/normalized-parent/child" || return 70
  packaging_adversarial_run_failure normalized_target "$PA_ROOT" \
    "$PA_BASE/normalized-parent/child/../target" 65 package.target_not_normalized || return 70

  PA_ROOT=$PA_BASE/parent-symlink-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  mkdir "$PA_BASE/parent-real" || return 70
  ln -s "$PA_BASE/parent-real" "$PA_BASE/parent-link" || return 70
  packaging_adversarial_run_failure parent_symlink "$PA_ROOT" \
    "$PA_BASE/parent-link/target" 73 package.parent_invalid || return 70

  PA_ROOT=$PA_BASE/missing-parent-source
  packaging_adversarial_clone_source "$PA_ROOT" || return 70
  packaging_adversarial_run_failure missing_parent "$PA_ROOT" \
    "$PA_BASE/missing-parent/target" 73 package.parent_invalid || return 70

  for PA_MANIFEST_CASE in absolute traversal normalized_duplicate blank comment duplicate; do
    PA_ROOT=$PA_BASE/manifest-$PA_MANIFEST_CASE-source
    packaging_adversarial_clone_source "$PA_ROOT" || return 70
    case "$PA_MANIFEST_CASE" in
      absolute)
        sed '1s#.*#/tmp/AGENTS.md#' "$PA_ROOT/manifest.txt" | LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
      traversal)
        sed '1s#.*#../AGENTS.md#' "$PA_ROOT/manifest.txt" | LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
      normalized_duplicate)
        sed '2s#.*#./AGENTS.md#' "$PA_ROOT/manifest.txt" | LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
      blank)
        sed '1s#.*##' "$PA_ROOT/manifest.txt" | LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
      comment)
        awk 'NR == 1 {print "# loader metadata"; next} {print}' "$PA_ROOT/manifest.txt" | \
          LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
      duplicate)
        sed '2s#.*#AGENTS.md#' "$PA_ROOT/manifest.txt" | LC_ALL=C sort >"$PA_ROOT/manifest.new" || return 70
        ;;
    esac
    mv "$PA_ROOT/manifest.new" "$PA_ROOT/manifest.txt" || return 70
    packaging_adversarial_run_failure "manifest_$PA_MANIFEST_CASE" "$PA_ROOT" \
      "$PA_BASE/manifest-$PA_MANIFEST_CASE-target" 65 package.manifest_invalid || return 70
  done
}
