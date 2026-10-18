#!/usr/bin/env bats
# platform: host-agnostic

setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/setup-family-repo.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/setup-family-repo-test.XXXXXX")" && pwd)"
  export STUB="$WORK/stub"
  mkdir -p "$WORK/bin" "$STUB"
  cat > "$WORK/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "repo view") [ -e "$STUB/exists" ]; exit ;;
  "repo create") echo "create $*" >> "$STUB/log"; : > "$STUB/exists"; exit 0 ;;
  "run list") cat "$STUB/run" 2>/dev/null; exit 0 ;;
  "run view") cat "$STUB/jobs"; exit 0 ;;
esac
case "$1 $2" in
  "pr list") cat "$STUB/prs" 2>/dev/null; exit 0 ;;
  "pr edit") echo "pr edit $*" >> "$STUB/log"; exit 0 ;;
esac
if [ "$1 $2" = "api repos/Mavergreen/newthing" ]; then cat "$STUB/default" 2>/dev/null || echo main; exit 0; fi
if [ "$1" = api ] && [ "$2" = -X ]; then
  printf '%s %s ' "$3" "$4" >> "$STUB/log"; cat >> "$STUB/log"; exit 0
fi
case "$2" in */branches/main) [ -e "$STUB/main" ]; exit ;; esac
echo "stub gh: unexpected $*" >&2; exit 1
EOF
  chmod +x "$WORK/bin/gh"
  export PATH="$WORK/bin:$PATH"
}
teardown() { rm -rf "$WORK"; }

@test "create makes an empty public repo, wiki off, and settles it without protecting a main it lacks" {
  run sh "$HELPER" create newthing "GNU Thing for Mavericks"
  [ "$status" -eq 0 ]
  grep -qx 'create repo create Mavergreen/newthing --public --description GNU Thing for Mavericks --disable-wiki' "$STUB/log"
  grep -q '^PATCH repos/Mavergreen/newthing {"visibility":"public","has_issues":true,"has_projects":true,"has_wiki":false,"allow_squash_merge":true,"allow_merge_commit":true,"allow_rebase_merge":true,"allow_auto_merge":true,"delete_branch_on_merge":false}$' "$STUB/log"
  grep -q '^PUT repos/Mavergreen/newthing/actions/permissions/workflow {"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}$' "$STUB/log"
  ! grep -q 'protection' "$STUB/log" || false
  [[ "$output" == *"has no main yet"* ]] || false
  [[ "$output" == *"mavericks-vm-images"* ]] || false
}

@test "create refuses a repo that already exists, and writes nothing" {
  : > "$STUB/exists"
  run sh "$HELPER" create newthing "desc"
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists; settle it instead"* ]] || false
  [ ! -e "$STUB/log" ]
}

@test "settle requires every job of the newest green run off main, names with spaces and quotes intact" {
  : > "$STUB/exists"; : > "$STUB/main"
  echo 4242 > "$STUB/run"
  printf 'ver\nbuild\nCross-build + compat gate (macos-26)\nsay "hi"\n' > "$STUB/jobs"
  run sh "$HELPER" settle newthing
  [ "$status" -eq 0 ]
  grep -q '"delete_branch_on_merge":false,"default_branch":"main"}$' "$STUB/log"
  grep -q '^PUT repos/Mavergreen/newthing/branches/main/protection {"required_status_checks":{"strict":false,"contexts":\["ver","build","Cross-build + compat gate (macos-26)","say \\"hi\\""\]},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":false,"allow_deletions":false}$' "$STUB/log"
  [[ "$output" == *"main requires: ver; build; Cross-build + compat gate (macos-26); say \"hi\""* ]] || false
}

@test "settle moves open PRs off the old default branch before main takes over" {
  : > "$STUB/exists"; : > "$STUB/main"
  echo ci > "$STUB/default"; printf '1\n4\n' > "$STUB/prs"
  run sh "$HELPER" settle newthing build
  [ "$status" -eq 0 ]
  grep -qx 'pr edit pr edit 1 -R Mavergreen/newthing --base main' "$STUB/log"
  grep -qx 'pr edit pr edit 4 -R Mavergreen/newthing --base main' "$STUB/log"
  [ "$(grep -n 'pr edit pr edit 1' "$STUB/log" | cut -d: -f1)" -lt "$(grep -n '"default_branch":"main"' "$STUB/log" | cut -d: -f1)" ]
  [[ "$output" == *"moved 2 open PRs from ci to main"* ]] || false
}

@test "settle leaves PRs alone when main is already the default" {
  : > "$STUB/exists"; : > "$STUB/main"
  echo main > "$STUB/default"; printf '7\n' > "$STUB/prs"
  run sh "$HELPER" settle newthing build
  [ "$status" -eq 0 ]
  ! grep -q 'pr edit' "$STUB/log" || false
}

@test "settle's named checks replace the run's" {
  : > "$STUB/exists"; : > "$STUB/main"
  echo 4242 > "$STUB/run"; printf 'ver\n' > "$STUB/jobs"
  run sh "$HELPER" settle newthing build vm-test
  [ "$status" -eq 0 ]
  grep -q '"contexts":\["build","vm-test"\]' "$STUB/log"
}

@test "settle with main but no green run off main leaves main unprotected and says so" {
  : > "$STUB/exists"; : > "$STUB/main"
  run sh "$HELPER" settle newthing
  [ "$status" -eq 0 ]
  ! grep -q 'protection' "$STUB/log" || false
  [[ "$output" == *"main is NOT protected"* ]] || false
}

@test "a name with a slash or a missing description is a usage error" {
  run sh "$HELPER" create Mavergreen/x "desc"
  [ "$status" -eq 1 ]
  run sh "$HELPER" create newthing
  [ "$status" -eq 2 ]
  run sh "$HELPER" frobnicate newthing
  [ "$status" -eq 2 ]
}
