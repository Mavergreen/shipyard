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

mkproduct oddsections oddsections "" bin/odd share/man/mann/after.n share/man/man9/k.9
mg link oddsections
[ -L "$T/share/man/mann/after.n" ] || fail "a manpage in section n (share/man/mann) is exported"
[ -L "$T/share/man/man9/k.9" ] || fail "a manpage in section 9 (share/man/man9) is exported"
mg unlink oddsections
[ ! -L "$T/share/man/mann/after.n" ] \
  || fail "unlink must remove a link in a man section outside man1-man8 (mann)"
[ ! -L "$T/share/man/man9/k.9" ] \
  || fail "unlink must remove a link in a man section outside man1-man8 (man9)"
rm -rf "$T/oddsections"

mg list | grep -q '^go127 go 127 1.0 selected$' || fail "list shows product group line version and selection: $(mg list)"
mg link no-such 2>/dev/null && fail "linking a product that is not installed must fail"
rc=0; mg link '../x' 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "a malformed product name is a usage error (exit 2), got $rc"

mg link openssh
mg check || fail "a consistent farm must pass check: $(mg check 2>&1)"
rm -rf "$T/go127/bin/gofmt"
mg check 2>"$w/err" && fail "a dangling link must fail check"
grep -q 'bin/gofmt' "$w/err" || fail "check must name the dangling link"
mkproduct go127 go 127 bin/go bin/gofmt

stub="$w/stub"; mkdir -p "$stub"
for c in launchctl pkgutil sudo; do printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$c" "$w" > "$stub/$c"; chmod +x "$stub/$c"; done
mkdir -p "$V/Applications/Go.app/Contents" "$V/Library/LaunchAgents" "$T/var/go127"
touch "$V/Library/LaunchAgents/dev.mavergreen.go127-updatecheck.plist"
"$PB" -c "Add :outside array" -c "Add :outside:0 string Applications/Go.app" \
      -c "Add :outside:1 string Library/LaunchAgents/dev.mavergreen.go127-updatecheck.plist" "$T/go127/mavergreen.plist"
: > "$w/calls"
PATH="$stub:$PATH" mg uninstall go127 || fail "uninstall must succeed"
[ ! -e "$T/go127" ] && [ ! -e "$T/var/go127" ] || fail "uninstall removes the tree and its var/"
[ ! -e "$V/Applications/Go.app" ] && [ ! -e "$V/Library/LaunchAgents/dev.mavergreen.go127-updatecheck.plist" ] \
  || fail "uninstall removes everything the manifest lists outside the tree"
[ "$(target bin/go)" = ../go126/bin/go ] || fail "uninstalling the selected member selects the one member left"
grep -q "pkgutil --volume $V --forget dev.mavergreen.go127" "$w/calls" || fail "uninstall forgets the receipt on the named volume: $(cat "$w/calls")"
grep -q launchctl "$w/calls" && fail "uninstall on a non-boot volume must not touch launchd: $(cat "$w/calls")"
[ "$(sh "$MG" version)" = "@MAVERGREEN_VERSION@" ] || fail "version prints the stamped version (unstamped in the source tree)"

mkproduct widget widget "" bin/widget
mkdir -p "$V/Applications/Widget.app/Contents" "$V/Library/Extensions" "$V/Library/LaunchAgents" "$T/sibling"
touch "$V/Library/Extensions/marker" "$T/sibling/marker"
touch "$V/Library/LaunchAgents/dev.mavergreen.widget-updatecheck.plist"
"$PB" -c "Add :outside array" \
      -c "Add :outside:0 string Applications/Widget.app" \
      -c "Add :outside:1 string Library" \
      -c "Add :outside:2 string usr/local/mavergreen/sibling" \
      -c "Add :outside:3 string Library/Extensions" \
      -c "Add :outside:4 string Library/LaunchAgents/dev.mavergreen.widget-updatecheck.plist" \
      "$T/widget/mavergreen.plist" >/dev/null
rc=0; PATH="$stub:$PATH" mg uninstall widget 2>"$w/err" || rc=$?
[ "$rc" -ne 0 ] || fail "uninstall with a refused outside entry must exit non-zero"
[ ! -e "$T/widget" ] || fail "uninstall always removes the product's own tree, even when an outside entry is refused"
[ ! -e "$V/Applications/Widget.app" ] || fail "an outside .app bundle is removed"
[ -d "$V/Library" ] || fail "a bare top-level directory like Library must be refused, not rm -rf'd whole"
grep -q '^mavergreen: refusing to remove Library -- ' "$w/err" || fail "uninstall must name a refused non-bundle directory on stderr"
[ -d "$T/sibling" ] && [ -f "$T/sibling/marker" ] \
  || fail "an outside path under usr/local/mavergreen must be refused -- it can name a sibling product's tree"
grep -q "unsafe outside path 'usr/local/mavergreen/sibling'" "$w/err" \
  || fail "uninstall must name a refused path under the mavergreen tree on stderr"
[ -d "$V/Library/Extensions" ] && [ -f "$V/Library/Extensions/marker" ] \
  || fail "a plain directory like Library/Extensions must be refused, not rm -rf'd whole"
[ ! -e "$V/Library/LaunchAgents/dev.mavergreen.widget-updatecheck.plist" ] \
  || fail "an outside entry AFTER a refused one must still be removed (best-effort, not abort-on-first-failure)"

echo "PASS: mavergreen-helper"
