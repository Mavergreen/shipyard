#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MG="$here/../scripts/mavergreen.sh"
PB=/usr/libexec/PlistBuddy
[ -x "$PB" ] || { echo "no PlistBuddy -- skipping"; exit 77; }
w="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-helper.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
V="$w/vol"; T="$V/usr/local/mavergreen"
mg() { sh "$MG" --root "$V" "$@"; }
mkproduct() {  # $1 product  $2 group  $3 line  $4.. files under the tree
  _p="$1"; _g="$2"; _l="$3"; shift 3
  mkdir -p "$T/$_p"
  for _f in "$@"; do mkdir -p "$T/$_p/$(dirname "$_f")"; echo "$_p" > "$T/$_p/$_f"; done
  rm -f "$T/$_p/mavergreen.plist"
  "$PB" -c "Add :product string $_p" -c "Add :group string $_g" -c "Add :line string $_l" \
        -c "Add :identifier string dev.mavergreen.$_p" -c "Add :version string 1.0" "$T/$_p/mavergreen.plist" >/dev/null
}
target() { readlink "$T/$1"; }

mkproduct openssh openssh "" bin/ssh "bin/ssh add" share/man/man1/ssh.1
mg link openssh || fail "linking a single-line product must succeed"
[ "$(target bin/ssh)" = ../openssh/bin/ssh ] || fail "a single-line product exports its bare names, relatively"
[ "$(target "bin/ssh add")" = "../openssh/bin/ssh add" ] || fail "a name with a space must be linked intact"
[ "$(target share/man/man1/ssh.1)" = ../../../openssh/share/man/man1/ssh.1 ] || fail "manpages are exported"
[ ! -e "$T/bin/ssh-" ] || fail "a product with no line exports no versioned names"
mg link openssh || fail "link must be idempotent"

mkproduct go126 go 126 bin/go bin/gofmt share/man/man1/go.1.gz
mkproduct go127 go 127 bin/go bin/gofmt
mg link go126
[ "$(target bin/go)" = ../go126/bin/go ] || fail "the first member of a group is selected automatically"
[ "$(target bin/go-126)" = ../go126/bin/go ] || fail "a line product always exports <cmd>-<line>"
[ "$(target share/man/man1/go-126.1.gz)" = ../../../go126/share/man/man1/go.1.gz ] \
  || fail "a manpage's line goes before its section suffix: go-126.1.gz"
mg link go127
[ "$(target bin/go)" = ../go126/bin/go ] || fail "installing another line must never take the selection"
[ "$(target bin/go-127)" = ../go127/bin/go ] || fail "the second line still exports its versioned names"

mg unlink go126; mg link go126
[ "$(target bin/go)" = ../go126/bin/go ] \
  || fail "an upgrade (unlink then link) of the selected line must keep the selection"

mg select go go127
[ "$(target bin/go)" = ../go127/bin/go ] || fail "select moves the bare names"
[ "$(target bin/gofmt)" = ../go127/bin/gofmt ] || fail "select moves every bare name of the group"
[ "$(target bin/go-126)" = ../go126/bin/go ] || fail "select leaves versioned names alone"
[ "$(mg select go)" = go127 ] || fail "select with no product prints the selection"

mkproduct rogue rogue "" bin/ssh
mg link rogue 2>"$w/err" && fail "a bare name owned by another group must be refused"
grep -q openssh "$w/err" || fail "the refusal must name the owner"
[ "$(target bin/ssh)" = ../openssh/bin/ssh ] || fail "a refused link must change nothing"
rm -rf "$T/rogue"

mkproduct shipyard shipyard "" bin/cmake bin/shipyard-cmake
"$PB" -c "Add :exports-exclude array" -c "Add :exports-exclude:0 string bin/cmake" "$T/shipyard/mavergreen.plist"
mg link shipyard
[ ! -e "$T/bin/cmake" ] && [ ! -L "$T/bin/cmake" ] || fail "exports-exclude must keep a name out of the farm"
[ -L "$T/bin/shipyard-cmake" ] || fail "names not excluded are still exported"

mg unlink openssh
[ ! -L "$T/bin/ssh" ] && [ ! -L "$T/share/man/man1/ssh.1" ] || fail "unlink removes every link the product owns"
[ -L "$T/bin/go" ] || fail "unlink removes only its own product's links"

mg list | grep -q '^go127 go 127 1.0 selected$' || fail "list shows product group line version and selection: $(mg list)"
mg link no-such 2>/dev/null && fail "linking a product that is not installed must fail"
rc=0; mg link '../x' 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a malformed product name is a usage error (exit 2), got $rc"
echo "PASS: mavergreen-helper"
