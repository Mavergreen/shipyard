#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/mg-repo-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $*"; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }
status() { _st=0; "$@" >/dev/null 2>&1 || _st=$?; printf '%s\n' "$_st"; }
command -v git >/dev/null 2>&1 || { echo "no git, skipping"; exit 77; }
. "$here/../scripts/mavergreen-meta.sh"
g="$w/repo"; mkdir -p "$g"; git init -q "$g"
MAVERGREEN_REPO_ROOT="$g"; export MAVERGREEN_REPO_ROOT
unset GITHUB_REPOSITORY || :
eq "mg_repo no origin status" "$(cd "$g" && status mg_repo)" 1
eq "mg_repo no origin output" "$(cd "$g" && mg_repo 2>/dev/null || :)" ""
git -C "$g" remote add origin https://github.com/Mavergreen/y.git
eq "mg_repo https" "$(cd "$g" && mg_repo)" Mavergreen/y
git -C "$g" remote set-url origin git@github.com:Mavergreen/z.git
eq "mg_repo ssh" "$(cd "$g" && mg_repo)" Mavergreen/z
echo "ok mg-repo-test"
