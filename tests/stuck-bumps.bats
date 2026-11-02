#!/usr/bin/env bats
# platform: host-agnostic

ago() {
  python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=float(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"
}

setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/stuck-bumps.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/stuck-bumps-test.XXXXXX")"
  export STUB="$WORK/stub" GITHUB_STEP_SUMMARY="$WORK/summary"
  mkdir -p "$WORK/bin" "$STUB"
  cat > "$WORK/bin/gh" <<'SH'
#!/bin/sh
echo "$*" >> "$STUB/log"
case "$1 $2" in
  "repo list") cat "$STUB/repos"; exit 0 ;;
  "pr list") r="$4"; [ "$3" = -R ] && [ -f "$STUB/prs-${r#*/}" ] || exit 1; cat "$STUB/prs-${r#*/}"; exit 0 ;;
esac
echo "stub gh: unexpected $*" >&2; exit 1
SH
  chmod +x "$WORK/bin/gh"
  PATH="$WORK/bin:$PATH"
  printf '[{"nameWithOwner":"Mavergreen/cmake"},{"nameWithOwner":"Mavergreen/swift"}]\n' > "$STUB/repos"
  cat > "$STUB/prs-cmake" <<JSON
[{"number":4,"title":"chore(deps): update dependency mavergreen/clang-22 to v22.1.8-mavericks.11","createdAt":"$(ago 10.5)","headRefName":"renovate/mavergreen-clang-22-22.x"},
 {"number":5,"title":"chore(deps): update dependency mavergreen/stevedore to v20261027.1","createdAt":"$(ago 2)","headRefName":"renovate/mavergreen-stevedore-20261027.x"},
 {"number":6,"title":"Update dependency Mavergreen/recaulk by hand","createdAt":"$(ago 30)","headRefName":"bump-recaulk"},
 {"number":7,"title":"chore(deps): update dependency kitware/cmake to v4.5.0","createdAt":"$(ago 40)","headRefName":"renovate/kitware-cmake-4.x"}]
JSON
  cat > "$STUB/prs-swift" <<JSON
[{"number":20,"title":"chore(deps): update mavergreen ingredients","createdAt":"$(ago 20.2)","headRefName":"renovate/mavergreen-ingredients"},
 {"number":21,"title":"Update dependency Mavergreen/golang-127 to v1.27.3-mavericks.6","createdAt":"$(ago 8)","headRefName":"renovate/mavergreen-golang-127-1.x"}]
JSON
}
teardown() { rm -rf "$WORK"; }

@test "lists each family bump open longer than 7 days, oldest first, to stdout and the summary" {
  run sh "$HELPER"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Mavergreen/swift#20 20 chore(deps): update mavergreen ingredients" ]
  [ "${lines[1]}" = "Mavergreen/cmake#4 10 chore(deps): update dependency mavergreen/clang-22 to v22.1.8-mavericks.11" ]
  [ "${lines[2]}" = "Mavergreen/swift#21 8 Update dependency Mavergreen/golang-127 to v1.27.3-mavericks.6" ]
  [ "${#lines[@]}" -eq 3 ]
  grep -qxF "Mavergreen/swift#20 20 chore(deps): update mavergreen ingredients" "$GITHUB_STEP_SUMMARY"
  grep -qxF "Mavergreen/cmake#4 10 chore(deps): update dependency mavergreen/clang-22 to v22.1.8-mavericks.11" "$GITHUB_STEP_SUMMARY"
  grep -qxF "Mavergreen/swift#21 8 Update dependency Mavergreen/golang-127 to v1.27.3-mavericks.6" "$GITHUB_STEP_SUMMARY"
  ! grep -q '#5 \|#6 \|#7 ' "$GITHUB_STEP_SUMMARY" || false
}

@test "STUCK_DAYS sets the threshold" {
  STUCK_DAYS=1 run sh "$HELPER"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "${lines[3]}" = "Mavergreen/cmake#5 2 chore(deps): update dependency mavergreen/stevedore to v20261027.1" ]
  STUCK_DAYS=30 run sh "$HELPER"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "nothing stuck prints nothing and says so in the summary" {
  STUCK_DAYS=100 run sh "$HELPER"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q 'No family bump has been open longer than 100 days' "$GITHUB_STEP_SUMMARY"
}

@test "reads every unarchived repo in the org and opens no issue" {
  run sh "$HELPER"
  [ "$status" -eq 0 ]
  grep -q '^repo list Mavergreen .*--no-archived' "$STUB/log"
  grep -q '^pr list -R Mavergreen/cmake .*--state open' "$STUB/log"
  grep -q '^pr list -R Mavergreen/swift .*--state open' "$STUB/log"
  ! grep -v '^repo list \|^pr list ' "$STUB/log" || false
}

@test "with no GITHUB_STEP_SUMMARY it prints to stdout alone" {
  unset GITHUB_STEP_SUMMARY
  run sh "$HELPER"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "a STUCK_DAYS that is not a whole number is refused" {
  STUCK_DAYS=seven run sh "$HELPER"
  [ "$status" -eq 2 ]
  printf "%s\n" "$output" | grep -q STUCK_DAYS
}

@test "a gh failure fails the run" {
  rm "$STUB/prs-swift"
  run sh "$HELPER"
  [ "$status" -ne 0 ]
}
