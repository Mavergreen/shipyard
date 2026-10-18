#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
hook="$here/../claude-plugins/mavergreen/hooks/work-items-go-in-the-queue.sh"
t="$(mktemp -d "${TMPDIR:-/tmp}/work-items-hook-test.XXXXXX")"
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL $*"; exit 1; }
git init -q "$t/mavergreen-foo"
git init -q "$t/renamed"; git -C "$t/renamed" remote add origin git@github.com:Mavergreen/foo.git
git init -q "$t/elsewhere"; git -C "$t/elsewhere" remote add origin https://github.com/someone/else.git
mkdir -p "$t/mavergreen-foo/sub"

call() {  # call CWD TOOL_NAME TOOL_INPUT_JSON
  printf '{"session_id":"s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "$2" "$3" \
    | sh "$hook"
}
asks() {
  out="$(call "$@")" || fail "the hook exited non-zero for $2 in $1"
  printf '%s' "$out" | grep -q '"permissionDecision": *"ask"' || fail "no ask for $2 $3 in $1: $out"
  printf '%s' "$out" | grep -q 'QUEUE.md' || fail "the ask does not say where work items go: $out"
}
quiet() {
  out="$(call "$@")" || fail "the hook exited non-zero for $2 in $1"
  [ -z "$out" ] || fail "the hook spoke for $2 $3 in $1: $out"
}

asks "$t/mavergreen-foo" Bash '{"command":"gh issue create --title x --body y"}'
asks "$t/mavergreen-foo/sub" Bash '{"command":"cd .. && gh pr create --fill"}'
asks "$t/renamed" Bash '{"command":"gh  issue  create -t x"}'
asks "$t/elsewhere" Bash '{"command":"gh issue create -R Mavergreen/rust -t x"}'
asks "$t/mavergreen-foo" mcp__github__create_issue '{"owner":"someone","repo":"x","title":"t"}'
asks "$t/elsewhere" mcp__github__create_pull_request '{"owner":"Mavergreen","repo":"rust","title":"t"}'
quiet "$t/mavergreen-foo" Bash '{"command":"gh issue list"}'
quiet "$t/mavergreen-foo" Bash '{"command":"gh pr view 3"}'
quiet "$t/elsewhere" Bash '{"command":"gh issue create -t x"}'
quiet "$t/elsewhere" mcp__github__create_issue '{"owner":"someone","repo":"x","title":"t"}'
quiet "$t/elsewhere" Bash '{"command":"ls"}'
echo "PASS: work-items hook asks before an agent opens an issue or pull request on a Mavergreen repo, and is quiet otherwise"
