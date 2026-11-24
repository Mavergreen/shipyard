#!/bin/sh
# platform: host-agnostic
#   usage: [PURE_GO_ARM64=<a Go darwin/arm64 executable>] macho-pure-go-test.sh
#          Reads tests/pure-go-fixtures.py's synthetic slices everywhere; a real Go darwin/arm64
#          executable too, cross-built when go is on PATH, else PURE_GO_ARM64's (one built with -trimpath);
#          and artifact-facts.sh's
#          pure-go facts when this host can read Mach-O (LIPO and OTOOL, or lipo and otool).
set -eu
unset GITHUB_REPOSITORY
here="$(cd "$(dirname "$0")" && pwd)"
P="$here/../scripts/macho-pure-go.py"
FX="$here/pure-go-fixtures.py"
w="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/pure-go.XXXXXX")" && pwd)"; trap 'rm -rf "$w"' EXIT   # template: 10.9 BSD mktemp requires one
fail() { echo "FAIL: $*"; exit 1; }
reads() {  # $1 = label, $2 = the line macho-pure-go.py must print, then fixture options
  _l="$1"; _want="$2"; shift 2
  python3 -I "$FX" "$w/f" "$@" || fail "$_l: the fixture could not be built"
  _got="$(python3 -I "$P" "$w/f")" || fail "$_l: macho-pure-go.py failed: $_got"
  [ "$_got" = "$_want" ] || fail "$_l: want '$_want', got '$_got'"
}
SYS=/usr/lib/libSystem.B.dylib

reads "a pure-Go slice" "arm64 0 internal $SYS 1 11.0 ok"
reads "a thin pure-Go slice" "arm64 0 internal $SYS 1 11.0 ok" --thin
reads "a cgo slice" "arm64 1 internal $SYS 1 11.0 ok" --cgo 1
reads "build info with no CGO_ENABLED" "arm64 none internal $SYS 1 11.0 ok" --cgo absent
reads "no Go build info" "arm64 not-go internal $SYS 1 11.0 ok" --no-buildinfo
reads "-linkmode=external" "arm64 0 external $SYS 1 11.0 ok" --ldflags=-linkmode=external
reads "a linker that lists itself as a tool" "arm64 0 external $SYS 1 11.0 ok" --ntools 1
reads "every load, in order" "arm64 0 internal $SYS,/opt/x%20y/libfoo.dylib 1 11.0 ok" --load "$SYS" --load "/opt/x y/libfoo.dylib"
reads "another platform" "arm64 0 internal $SYS 2 11.0 ok" --platform 2
reads "no LC_BUILD_VERSION" "arm64 0 internal $SYS none - ok" --platform none
reads "a minos above the floor" "arm64 0 internal $SYS 1 13.0 ok" --minos 13.0
reads "an unsigned slice" "arm64 0 internal $SYS 1 11.0 unsigned" --unsigned
reads "a corrupted first page" "arm64 0 internal $SYS 1 11.0 page-0-hash-mismatch" --corrupt-page 0
reads "a corrupted middle page" "arm64 0 internal $SYS 1 11.0 page-2-hash-mismatch" --corrupt-page 2
# spec: SKILL.md "Artifact conformance" -- every Go binary records -trimpath=true, whatever its arch.
trim() {  # $1 = label, $2 = the lines --go-trimpath must print, then fixture options
  _l="$1"; _want="$2"; shift 2
  python3 -I "$FX" "$w/f" "$@" || fail "$_l: the fixture could not be built"
  _got="$(python3 -I "$P" --go-trimpath "$w/f")" || fail "$_l: --go-trimpath failed: $_got"
  [ "$_got" = "$_want" ] || fail "$_l: want '$_want', got '$_got'"
}
trim "build info with -trimpath=true" "arm64 yes" --trimpath
trim "build info without -trimpath" "arm64 no"
trim "no Go build info prints nothing" "" --no-buildinfo
printf 'not a Mach-O\n' > "$w/text"
python3 -I "$P" "$w/text" >/dev/null 2>&1 && fail "a file that is not Mach-O exits non-zero"
_rc=0; python3 -I "$P" >/dev/null 2>&1 || _rc=$?
[ "$_rc" -eq 2 ] || fail "no FILE is a usage error"

# spec: SKILL.md "Family conventions" check 37 -- the proof is only as good as its reading of what Go's
#       own linker writes, so a real CGO_ENABLED=0 darwin/arm64 executable must read clean, and one byte
#       changed in it must fail its page hash.
real="${PURE_GO_ARM64:-}"
if [ -z "$real" ] && command -v go >/dev/null 2>&1; then
  mkdir -p "$w/gosrc"
  printf 'module fixture\n\ngo 1.21\n' > "$w/gosrc/go.mod"
  printf 'package main\n\nimport (\n\t"crypto/x509"\n\t"fmt"\n\t"net"\n)\n\nfunc main() {\n\tp, _ := x509.SystemCertPool()\n\t_, _ = net.LookupHost("localhost")\n\tfmt.Println(p != nil)\n}\n' > "$w/gosrc/main.go"
  (cd "$w/gosrc" && CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 GOFLAGS= go build -o "$w/real" .) || fail "go cannot cross-build darwin/arm64"
  real="$w/real"
fi
if [ -n "$real" ]; then
  _got="$(python3 -I "$P" "$real")" || fail "a real Go darwin/arm64 executable is read: $_got"
  set -f; set -- $_got; set +f
  [ "$1 $2 $3 $5" = "arm64 0 internal 1" ] || fail "a real CGO_ENABLED=0 darwin/arm64 executable reads as pure Go on macOS: $_got"
  [ "$7" = ok ] || fail "a real Go darwin/arm64 executable's ad-hoc signature verifies: $_got"
  for _l in $(printf '%s' "$4" | tr ',' ' '); do
    case "$_l" in
      /usr/lib/libSystem.B.dylib|/usr/lib/libresolv.9.dylib|/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation|/System/Library/Frameworks/Security.framework/Versions/A/Security) ;;
      *) fail "a real pure-Go executable loads only what check-artifact-conformance.sh allows, not $_l: $_got" ;;
    esac
  done
  [ "$(python3 -I "$P" --go-trimpath "$real")" = "arm64 $([ -n "${PURE_GO_ARM64:-}" ] && echo yes || echo no)" ] \
    || fail "a real Go executable's -trimpath setting is read: $(python3 -I "$P" --go-trimpath "$real")"
  if [ -z "${PURE_GO_ARM64:-}" ]; then
    (cd "$w/gosrc" && CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 GOFLAGS= go build -trimpath -o "$w/realtrim" .) || fail "go cannot cross-build darwin/arm64 with -trimpath"
    [ "$(python3 -I "$P" --go-trimpath "$w/realtrim")" = "arm64 yes" ] || fail "a real go build -trimpath reads yes: $(python3 -I "$P" --go-trimpath "$w/realtrim")"
  fi
  cp "$real" "$w/bad"
  python3 -I - "$w/bad" <<'PY'
import sys
with open(sys.argv[1], "r+b") as f:
    f.seek(5000)
    b = f.read(1)
    f.seek(5000)
    f.write(bytes([b[0] ^ 0xFF]))
PY
  python3 -I "$P" "$w/bad" | grep -q ' page-1-hash-mismatch$' || fail "a real executable with one changed byte fails page 1: $(python3 -I "$P" "$w/bad")"
else
  echo "macho-pure-go: skip: no go on PATH and no PURE_GO_ARM64, so no real Go darwin/arm64 executable"
fi

# spec: scripts/artifact-facts.sh -- a pure-go fact for exactly the arm64 slices an arm64-pure-go
#       deviation covers.
if command -v "${LIPO:-lipo}" >/dev/null 2>&1 && command -v "${OTOOL:-otool}" >/dev/null 2>&1; then
  mkdir -p "$w/repo" "$w/src/bin" "$w/dist"
  python3 -I "$FX" "$w/src/bin/tool"
  python3 -I "$FX" "$w/src/bin/other"
  printf '# x\n## Conformance deviations\n- arm64-pure-go:bin/tool: maintainers run it on Apple Silicon\n' > "$w/repo/INGREDIENTS.md"
  (cd "$w/src" && tar -czf "$w/dist/t-1.0.0-mavericks.1.tgz" bin) || exit 1
  facts="$(sh "$here/../scripts/artifact-facts.sh" "$w/dist" 1.0.0-mavericks.1 "$w/repo" 2>"$w/err")" || fail "artifact-facts failed: $(cat "$w/err")"
  printf '%s\n' "$facts" | grep -qxF "pure-go t-1.0.0-mavericks.1.tgz bin/tool arm64 0 internal $SYS 1 11.0 ok" \
    || fail "a covered slice gets its pure-go fact: $facts"
  printf '%s\n' "$facts" | grep -q '^pure-go .* bin/other ' && fail "an uncovered slice gets none: $facts"
  printf '%s\n' "$facts" | grep -qxF "go-trimpath t-1.0.0-mavericks.1.tgz bin/other arm64 no" \
    || fail "every Go binary gets a go-trimpath fact, covered or not: $facts"
  rm -f "$w/repo/INGREDIENTS.md"
  facts="$(sh "$here/../scripts/artifact-facts.sh" "$w/dist" 1.0.0-mavericks.1 "$w/repo" 2>"$w/err")" || fail "artifact-facts failed: $(cat "$w/err")"
  printf '%s\n' "$facts" | grep -q '^pure-go ' && fail "no declaration, no pure-go fact: $facts"
  printf '%s\n' "$facts" | grep -qxF "go-trimpath t-1.0.0-mavericks.1.tgz bin/tool arm64 no" \
    || fail "a go-trimpath fact needs no declaration: $facts"
else
  echo "macho-pure-go: skip: artifact-facts.sh needs ${LIPO:-lipo} and ${OTOOL:-otool} to read Mach-O"
fi
echo "PASS: macho-pure-go"
