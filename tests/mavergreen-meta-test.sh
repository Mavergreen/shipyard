#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-meta-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
w="$(cd "$w" && pwd)"
m="$w/.mavergreen"
mkdir -p "$m/ingredients/go" "$m/ingredients/zlib" "$m/ingredients/abc" "$m/upstream" "$m/empty"
printf 'mavergreen-go\n' > "$m/identifier"
printf '1.26.5\n# renovate: datasource=github-releases depName=golang/go\n' > "$m/upstream/VERSION"
printf 'refs/tags/v2@0123456789abcdef0123456789abcdef01234567\n' > "$m/ingredients/go/PIN"
printf 'bare' > "$m/nonewline"
printf 'crlf-value\r\nsecond\r\n' > "$m/crlf"
printf 'linked\nshipped\n' > "$m/ingredients/go/role"
printf 'linked\n# renovate: datasource=github-tags depName=madler/zlib\nshipped\n' > "$m/ingredients/zlib/role"
printf 'lone\n' > "$m/ingredients/abc/role"
: > "$m/empty/blank"

fail() { echo "FAIL $*"; exit 1; }
eq() { [ "$2" = "$3" ] || fail "$1: got '$2', want '$3'"; }

MAVERGREEN_REPO_ROOT="$w"; export MAVERGREEN_REPO_ROOT
. "$here/../scripts/mavergreen-meta.sh"

eq mg_dir "$(mg_dir)" "$m"
mkdir -p "$w/other"
eq "mg_dir walks up to the nearest .mavergreen" "$(cd "$w/other" && unset MAVERGREEN_REPO_ROOT; mg_dir)" "$m"
mkdir -p "$w/sub/deep" "$w/nested/.mavergreen/products/inner" "$w/nested/x/y" "$w/nogit" "$w/bare/under"
mkdir -p "$m/products/shipyard"; printf 'Shipyard\n' > "$m/products/shipyard/noun"
printf 'Inner\n' > "$w/nested/.mavergreen/products/inner/noun"
sub="$(cd "$w/sub/deep" && pwd)"
r="$(cd "$w/sub/deep" && env -u MAVERGREEN_REPO_ROOT PATH="$w/nogit" /bin/sh -c '. "$1"; mavergreen_name name shipyard' sh "$here/../scripts/mavergreen-meta.sh")" \
  || fail "mavergreen_name from a subdirectory with no git: $r"
eq "name from a subdirectory with no git" "$r" Shipyard
eq "the nearest ancestor wins" "$(cd "$w/nested/x/y" && env -u MAVERGREEN_REPO_ROOT PATH="$w/nogit" /bin/sh -c '. "$1"; mg_dir' sh "$here/../scripts/mavergreen-meta.sh")" "$w/nested/.mavergreen"
eq "MAVERGREEN_REPO_ROOT still wins" "$(cd "$w/nested/x/y" && MAVERGREEN_REPO_ROOT="$w" PATH="$w/nogit" /bin/sh -c '. "$1"; mg_dir' sh "$here/../scripts/mavergreen-meta.sh")" "$m"
n="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-meta-none.XXXXXX")"; mkdir -p "$n/under"
nbase="$(cd "$n/under" && pwd)"
rc=0; err="$(cd "$n/under" && env -u MAVERGREEN_REPO_ROOT PATH="$w/nogit" /bin/sh -c '. "$1"; mavergreen_name name shipyard' sh "$here/../scripts/mavergreen-meta.sh" 2>&1 >/dev/null)" || rc=$?
rm -rf "$n"
eq "no .mavergreen anywhere fails" "$rc" 1
case "$err" in *"$nbase/.mavergreen/products/shipyard/noun"*) ;; *) fail "the message names the path it looked in: $err" ;; esac
eq value "$(mg_value identifier)" mavergreen-go
eq "value with line 2" "$(mg_value upstream/VERSION)" 1.26.5
eq "no final newline" "$(mg_value nonewline)" bare
eq CRLF "$(mg_value crlf)" crlf-value
eq "empty file" "$(mg_value empty/blank)" ""
if out="$(mg_value absent)"; then fail "mg_value of an absent file must fail"; fi
eq "absent value output" "$out" ""
mg_has identifier || fail "mg_has present"
if mg_has absent; then fail "mg_has absent"; fi
mg_has ingredients || fail "mg_has dir"

eq mg_list "$(mg_list ingredients)" "abc
go
zlib"
eq "mg_list absent" "$(mg_list nowhere)" ""
mg_list nowhere || fail "mg_list of an absent directory must succeed"

eq mg_lines "$(mg_lines ingredients/go/role)" "linked
shipped"
eq "mg_lines drops a Renovate line 2" "$(mg_lines ingredients/zlib/role)" "linked
shipped"
eq "mg_lines keeps a plain line 2" "$(mg_lines ingredients/abc/role)" lone
eq "mg_lines CRLF" "$(mg_lines crlf)" "crlf-value
second"

eq mg_pin_ref "$(mg_pin_ref ingredients/go)" refs/tags/v2
eq mg_pin_commit "$(mg_pin_commit ingredients/go)" 0123456789abcdef0123456789abcdef01234567
printf 'a@b@c\n' > "$m/ingredients/abc/PIN"
eq "pin ref splits on first @" "$(mg_pin_ref ingredients/abc)" a
eq "pin commit keeps later @" "$(mg_pin_commit ingredients/abc)" b@c
rm "$m/ingredients/abc/PIN"

rm "$m/upstream/VERSION"
if out="$(mg_upstream_kind)"; then fail "zero candidates must fail"; fi
eq "zero candidates output" "$out" ""
printf 'abc\n' > "$m/upstream/COMMIT"
eq "kind COMMIT" "$(mg_upstream_kind)" COMMIT
rm "$m/upstream/COMMIT"
printf '1.0\n' > "$m/upstream/VERSION"
eq "kind VERSION" "$(mg_upstream_kind)" VERSION
rm "$m/upstream/VERSION"
printf 'r@c\n' > "$m/upstream/PIN"
eq "kind PIN" "$(mg_upstream_kind)" PIN
printf '1.26.5\n# renovate: datasource=github-releases depName=golang/go\n' > "$m/upstream/VERSION"
if out="$(mg_upstream_kind)"; then fail "two candidates must fail"; fi
eq "two candidates output" "$out" ""

eq mg_renovate "$(mg_renovate upstream/VERSION)" "datasource=github-releases
depName=golang/go"
if out="$(mg_renovate identifier)"; then fail "mg_renovate with no line 2 must fail"; fi
eq "no line 2 output" "$out" ""

printf 'v\n# renovate:   datasource=x    extractVersion=^v(.*)$  \r\n' > "$m/spaced"
eq "mg_renovate squeezes repeated spaces, never globs" "$(mg_renovate spaced)" "datasource=x
extractVersion=^v(.*)$"
printf 'v\n# renovate:   \n' > "$m/emptyrenovate"
if mg_renovate emptyrenovate >/dev/null; then fail "a renovate line with no words must fail"; fi
printf '1.0\n# renovate: datasource=github-releases depName=a/b' > "$m/eofline2"
eq "mg_renovate with no final newline" "$(mg_renovate eofline2)" "datasource=github-releases
depName=a/b"
mkdir "$m/ingredients/nopin"; printf 'nothing\n' > "$m/ingredients/nopin/PIN"
if out="$(mg_pin_ref ingredients/nopin)"; then fail "pin ref without @ must fail"; fi
eq "pin ref no-@ output" "$out" ""
if out="$(mg_pin_commit ingredients/nopin)"; then fail "pin commit without @ must fail"; fi
eq "pin commit no-@ output" "$out" ""

printf 'patches/a b/x.patch\npatches/ab.patch\nsrc/deep/y.patch\nREADME.md' > "$m/../tracked"
eq "mg_glob_hits: a space is literal" "$(mg_glob_hits 'patches/a b/*' "$m/../tracked")" "patches/a b/x.patch"
eq "mg_glob_hits: * crosses a /, and a last line with no newline is read" "$(mg_glob_hits '*' "$m/../tracked" | sed -n '$p')" README.md
eq "mg_glob_hits: * crosses a /" "$(mg_glob_hits 'src/*.patch' "$m/../tracked")" src/deep/y.patch
eq "mg_glob_hits: no match prints nothing" "$(mg_glob_hits 'nope/*' "$m/../tracked")" ""

k="$w/kind"; mkdir -p "$k/.mavergreen/upstream"
kind() { MAVERGREEN_REPO_ROOT="$k"; mg_port_or_own; }
printf '1.0\n' > "$k/.mavergreen/upstream/VERSION"
eq "a bare upstream value is its own upstream" "$(kind)" own
printf '1.0\n# renovate: datasource=github-releases depName=a/b\n' > "$k/.mavergreen/upstream/VERSION"
eq "a Renovate-tracked upstream value is a port" "$(kind)" port
rm "$k/.mavergreen/upstream/VERSION"
printf '0123456789abcdef0123456789abcdef01234567\n' > "$k/.mavergreen/upstream/COMMIT"
eq "an untracked COMMIT with no derive hook is its own upstream" "$(kind)" own
mkdir -p "$k/.mavergreen/hooks"; printf '#!/bin/sh\necho 20260727\n' > "$k/.mavergreen/hooks/derive-upstream-version"
eq "a derive-upstream-version hook makes a port" "$(kind)" port
rm -r "$k/.mavergreen/upstream" "$k/.mavergreen/hooks"
eq "no upstream at all is its own upstream" "$(kind)" own
MAVERGREEN_REPO_ROOT="$w"

echo "mavergreen-meta-test: ok"
