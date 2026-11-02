#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/ingredients-table.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/ingredients-table-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $*"; exit 1; }
i="$w/.mavergreen/ingredients"

out="$(cd "$w" && MAVERGREEN_ROOT="$w" sh "$S")"
[ -z "$out" ] || fail "no ingredients prints nothing: '$out'"

mkdir -p "$i/cmake" "$i/gha" "$i/libgit" "$i/child" "$i/pipe" "$i/frozen" "$i/self-child"
printf '4.4.5-mavericks.2\n# renovate: datasource=github-releases depName=Mavergreen/cmake\n' > "$i/cmake/VERSION"
printf 'shipped\n' > "$i/cmake/role"
printf 'The Mavergreen cmake product\n' > "$i/cmake/description"
printf 'build-only\r\ntest\r\n' > "$i/gha/role"
printf 'GitHub Actions' > "$i/gha/description"
printf "Renovate's github-actions manager, in .github/workflows/*.yml\n" > "$i/gha/tracked-by"
printf 'v1.1@0123456789abcdef0123456789abcdef01234567\n' > "$i/libgit/PIN"
printf 'linked\n' > "$i/libgit/role"
printf 'libgit2\n' > "$i/libgit/description"
printf 'no manager reads it,\nand a bump is a port decision\n' > "$i/libgit/untracked"
printf 'cmake\n' > "$i/child/from"
printf 'shipped\n' > "$i/child/role"
printf 'part of cmake\n' > "$i/child/description"
printf 'self\n' > "$i/self-child/from"
printf 'shipped\n' > "$i/self-child/role"
printf 'part of the upstream\n' > "$i/self-child/description"
printf '1.0\n' > "$i/pipe/VERSION"
printf 'test\n' > "$i/pipe/role"
printf 'reads a | b\n' > "$i/pipe/description"
printf 'pinned | by hand\n' > "$i/pipe/untracked"
printf '0123456789abcdef0123456789abcdef01234567\n' > "$i/frozen/COMMIT"
printf 'reference\n' > "$i/frozen/role"
printf 'a commit, for want of tags\n' > "$i/frozen/description"
printf 'upstream has no tags\n' > "$i/frozen/untracked"

out="$(cd / && MAVERGREEN_ROOT="$w" sh "$S")"
cat > "$w/want" <<'EOF'
| Ingredient | Role | Description | Value | Tracking |
| --- | --- | --- | --- | --- |
| child | shipped | part of cmake |  | tracked with cmake |
| cmake | shipped | The Mavergreen cmake product | 4.4.5-mavericks.2 | tracked (github-releases Mavergreen/cmake) |
| frozen | reference | a commit, for want of tags | 0123456789ab | untracked: upstream has no tags |
| gha | build-only, test | GitHub Actions |  | tracked by Renovate's github-actions manager, in .github/workflows/*.yml |
| libgit | linked | libgit2 | v1.1 | untracked: no manager reads it, and a bump is a port decision |
| pipe | test | reads a \| b | 1.0 | untracked: pinned \| by hand |
| self-child | shipped | part of the upstream |  | tracked with the upstream |
EOF
want="$(cat "$w/want")"
[ "$out" = "$want" ] || { echo "FAIL table: got:"; printf '%s\n' "$out"; echo "want:"; printf '%s\n' "$want"; exit 1; }

echo "PASS: ingredients-table"
