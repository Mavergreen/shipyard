#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
w="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-meta-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
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

MAVERGREEN_ROOT="$w"; export MAVERGREEN_ROOT
MAVERICKS_ROOT="$w/other"; export MAVERICKS_ROOT
. "$here/../scripts/mavergreen-meta.sh"

eq mg_dir "$(mg_dir)" "$m"
eq "mg_dir default" "$(MAVERGREEN_ROOT= ; unset MAVERGREEN_ROOT; mg_dir)" "$w/other/.mavergreen"
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

echo "mavergreen-meta-test: ok"
