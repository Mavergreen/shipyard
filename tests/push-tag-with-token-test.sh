#!/bin/sh
# platform: host-agnostic
#   usage: push-tag-with-token-test.sh
#          The tag-only-moves-forward guard reads the remote through the same authenticated URL the
#          push uses, never the checkout's origin, and a remote it cannot read stops the push. The
#          github.com URL is redirected to a local bare repository with git's url.<base>.insteadOf.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
S="$here/scripts/push-tag-with-token.sh"
command -v git >/dev/null 2>&1 || { echo "SKIP: no git"; exit 77; }
t="$(mktemp -d "${TMPDIR:-/tmp}/push-tag-test.XXXXXX")"; trap 'rm -rf "$t"' EXIT
GIT_CEILING_DIRECTORIES="$t"; export GIT_CEILING_DIRECTORIES
bad=0
fail() { echo "FAIL $1"; bad=1; }
g() { git -c user.email=t@example.invalid -c user.name=t "$@"; }

git init -q --bare "$t/remote.git"
git init -q "$t/work"
(cd "$t/work" && g commit -q --allow-empty -m A && g commit -q --allow-empty -m B && git push -q "$t/remote.git" HEAD:refs/heads/main) >/dev/null 2>&1
a="$(cd "$t/work" && git rev-parse HEAD~1)"; b="$(cd "$t/work" && git rev-parse HEAD)"
(cd "$t/work" && git remote add origin "$t/no-such-origin.git")
GH_TOKEN=unused; GITHUB_REPOSITORY=Mavergreen/demo; export GH_TOKEN GITHUB_REPOSITORY
redirect() { GIT_CONFIG_COUNT=1; GIT_CONFIG_KEY_0="url.$1.insteadOf"; GIT_CONFIG_VALUE_0=https://x-access-token@github.com/Mavergreen/demo; export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0; }
remote_v1() { git --git-dir="$t/remote.git" rev-parse -q --verify 'refs/tags/v1^{commit}' 2>/dev/null || :; }

redirect "file://$t/remote.git"
(cd "$t/work" && sh "$S" v1 "$b") >/dev/null 2>&1 || fail "M5: the first push of v1 succeeds"
[ "$(remote_v1)" = "$b" ] || fail "M5: v1 is at B on the remote"

(cd "$t/work" && git tag -d v1 >/dev/null 2>&1 || :)
rc=0; (cd "$t/work" && sh "$S" v1 "$a") > "$t/out" 2>&1 || rc=$?
[ "$(remote_v1)" = "$b" ] || fail "M5: a push of an older commit never moves v1 backwards, though origin is unreadable: $(cat "$t/out")"
[ "$rc" = 0 ] && grep -q 'already at or ahead' "$t/out" || fail "M5: it says v1 is already ahead, got $rc: $(cat "$t/out")"

redirect "file://$t/no-such-remote.git"
rc=0; (cd "$t/work" && sh "$S" v1 "$b") > "$t/out" 2>&1 || rc=$?
[ "$rc" = 1 ] && grep -q 'cannot read v1' "$t/out" || fail "M5: an unreadable remote stops the push, naming the tag, got $rc: $(cat "$t/out")"

redirect "file://$t/remote.git"
git --git-dir="$t/remote.git" tag -d v1 >/dev/null 2>&1
(cd "$t/work" && g tag -f -a v1 -m stale "$b") >/dev/null 2>&1
(cd "$t/work" && sh "$S" v1 "$a") > "$t/out" 2>&1 || fail "M5: with no v1 on the remote, a stale local v1 does not block: $(cat "$t/out")"
[ "$(remote_v1)" = "$a" ] || fail "M5: with no v1 on the remote it is pushed where asked"

[ "$bad" -eq 0 ] || exit 1
echo "PASS push-tag-with-token"
