#!/bin/sh
# platform: host-agnostic
#   usage: mavergreen-slim-test.sh
#          `mavergreen slim` against a temporary --root, with a stub ditto that logs its arguments and
#          Mach-O fixtures built from printf bytes: fat and thin binaries are thinned or removed for the
#          host arch, while archives, files of the host's own arch, Java classes and slim-keep paths are
#          left alone. Exit 0 clean, 1 on failure.
# spec: scripts/mavergreen.sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
MGS="$here/../scripts/mavergreen.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/mavergreen-slim.XXXXXX")"; trap 'rm -rf "$w"' EXIT
w="$(cd -P "$w" && pwd)"
fail() { echo "FAIL: $1"; exit 1; }
if [ ! -x /usr/libexec/PlistBuddy ] && [ -z "${STEVEDORE:-}" ]; then STEVEDORE="$(sh "$here/../scripts/fetch_stevedore.sh")"; export STEVEDORE; fi
V="$w/vol"; T="$V/usr/local/mavergreen"
LOG="$w/ditto.log"
cat > "$w/fx.sh" <<'FX'
hexbytes() {
  _h="$1"
  while [ -n "$_h" ]; do
    _b="${_h%"${_h#??}"}"; _h="${_h#??}"
    printf "\\$(printf %03o "$((0x$_b))")"
  done
}
cpu_sub() { case "$1" in x86_64h) echo 00000008 ;; *) echo 00000000 ;; esac; }
cpu_be() { case "$1" in x86_64|x86_64h) echo 01000007 ;; i386) echo 00000007 ;; arm64) echo 0100000c ;; esac; }
cpu_le() { case "$1" in x86_64) echo 07000001 ;; i386) echo 07000000 ;; arm64) echo 0c000001 ;; esac; }
mkfat_with() {
  _m="$1"; _f="$2"; shift 2
  mkdir -p "$(dirname "$_f")"
  { hexbytes cafebabe; hexbytes "$(printf %08x $#)"
    _i=0
    for _c in "$@"; do
      hexbytes "$(cpu_be "$_c")"; hexbytes "$(cpu_sub "$_c")"
      hexbytes "$(printf %08x $((4096 * (_i + 1))))"; hexbytes 00000008; hexbytes 0000000c
      _i=$((_i + 1))
    done; } > "$_f"
  _i=0
  for _c in "$@"; do
    _pad=$((4096 * (_i + 1) - $(wc -c < "$_f")))
    dd if=/dev/zero bs="$_pad" count=1 2>/dev/null >> "$_f"
    hexbytes "$_m" >> "$_f"
    _i=$((_i + 1))
  done
}
mkfat() { _f="$1"; shift; mkfat_with cffaedfe0000 "$_f" "$@"; }
mkfatar() { _f="$1"; shift; mkfat_with 213c617263683e0a "$_f" "$@"; }
mkthin() { mkdir -p "$(dirname "$1")"; { hexbytes cffaedfe; hexbytes "$(cpu_le "$2")"; hexbytes 0000000000000000; } > "$1"; }
mkthinar() { mkdir -p "$(dirname "$1")"; printf '!<arch>\n' > "$1"; }
FX
. "$w/fx.sh"
cat > "$w/ditto" <<'STUB'
#!/bin/sh
. "$DITTO_FX"
args=""; cpus=""
while [ $# -gt 2 ]; do
  args="$args $1"
  case "$1" in --arch) cpus="$cpus $2"; args="$args $2"; shift ;; esac
  shift
done
printf '%s %s\n' "${args# }" "$1" >> "$DITTO_LOG"
case "${DITTO_MODE:-ok}" in
  empty) : > "$2" ;;
  garbage) printf 'junk' > "$2" ;;
  wrong) cp "$1" "$2" ;;
  *) src="$1"; dst="$2"; set -- $cpus
     if [ $# -eq 1 ]; then mkthin "$dst" "$1"; else mkfat "$dst" "$@"; fi ;;
esac
STUB
chmod +x "$w/ditto"
MAVERGREEN_DITTO="$w/ditto"; DITTO_LOG="$LOG"; DITTO_FX="$w/fx.sh"; export MAVERGREEN_DITTO DITTO_LOG DITTO_FX

mg() { sh "$MGS" --root "$V" "$@"; }
mkproduct() {
  _p="$1"; shift
  mkdir -p "$T/$_p"
  { echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<plist version="1.0"><dict>'
    echo "<key>product</key><string>$_p</string><key>group</key><string>$_p</string>"
    echo "<key>identifier</key><string>dev.mavergreen.$_p</string><key>version</key><string>1.0</string>"
    if [ $# -gt 0 ]; then echo '<key>slim-keep</key><array>'; for _g in "$@"; do echo "<string>$_g</string>"; done; echo '</array>'; fi
    echo '</dict></plist>'; } > "$T/$_p/mavergreen.plist"
}
fresh() { rm -rf "$V"; : > "$LOG"; mkdir -p "$T/var"; }
logged() { grep -Fxq -- "$1" "$LOG"; }

fresh
[ "$(MAVERGREEN_HOST_ARCH=x86_64 mg slim status)" = "slim: on, the default on an x86_64 Mac" ] || fail "x86_64 default status"
[ "$(MAVERGREEN_HOST_ARCH=arm64 mg slim status)" = "slim: off, the default on an arm64 Mac" ] || fail "arm64 default status"
MAVERGREEN_HOST_ARCH=bogus mg slim status 2>/dev/null && fail "a bad MAVERGREEN_HOST_ARCH must fail slim, not act as some arch"

fresh; mkproduct p
mkfat "$T/p/bin/tool" x86_64 arm64
mkfat "$T/p/libexec/a b" i386 x86_64 arm64
mkthin "$T/p/pkg/tool/darwin_arm64/x" arm64
out="$(MAVERGREEN_HOST_ARCH=x86_64 mg slim apply p)" || fail "apply must succeed"
logged "--arch x86_64 $T/p/bin/tool" || fail "the fat binary is thinned to x86_64"
logged "--arch x86_64 --arch i386 $T/p/libexec/a b" || fail "a name with a space is thinned to x86_64 and i386"
[ ! -e "$T/p/pkg/tool/darwin_arm64/x" ] || fail "a thin arm64 file is removed on an x86_64 host"
[ "$(cat "$T/var/mavergreen/slimmed/p")" = x86_64 ] || fail "slimmed/p records the arch"
case "$out" in *"slimmed 3 files in p to x86_64"*) ;; *) fail "stdout was: $out" ;; esac

fresh; mkproduct p
mkfatar "$T/p/lib/libc++.a" x86_64 arm64
mkthinar "$T/p/lib/darwin/libclang_rt.osx.a"
mkthin "$T/p/lib/x86only" x86_64
MAVERGREEN_HOST_ARCH=x86_64 mg slim apply p >/dev/null || fail "apply must succeed"
[ ! -s "$LOG" ] || fail "no ditto call for archives or x86_64-only files: $(cat "$LOG")"
for f in lib/libc++.a lib/darwin/libclang_rt.osx.a lib/x86only; do [ -f "$T/p/$f" ] || fail "$f must still exist"; done
[ ! -e "$T/var/mavergreen/slimmed/p" ] || fail "nothing changed, so no marker"

fresh; mkproduct p
mkdir -p "$T/p/share"; hexbytes cafebabe00000034 > "$T/p/share/A.class"
MAVERGREEN_HOST_ARCH=x86_64 mg slim apply p >/dev/null || fail "apply must succeed"
[ ! -s "$LOG" ] || fail "a Java class is not a fat binary"
[ -f "$T/p/share/A.class" ] || fail "the class file stays"

fresh; mkproduct p 'lib/*.dylib'
mkfat "$T/p/lib/libssl.dylib" x86_64 arm64
mkfat "$T/p/lib/other" x86_64 arm64
MAVERGREEN_HOST_ARCH=x86_64 mg slim apply p >/dev/null || fail "apply must succeed"
logged "--arch x86_64 $T/p/lib/libssl.dylib" && fail "a slim-keep path is not thinned"
logged "--arch x86_64 $T/p/lib/other" || fail "a path outside slim-keep is thinned"

fresh; mkproduct p
mkfat "$T/p/bin/tool" x86_64 arm64
mkthin "$T/p/lib/x86only" x86_64
mkthin "$T/p/lib/armonly" arm64
MAVERGREEN_HOST_ARCH=arm64 mg slim on >/dev/null || fail "slim on must succeed"
logged "--arch arm64 $T/p/bin/tool" || fail "the fat file is thinned to arm64"
[ -f "$T/p/lib/x86only" ] || fail "an arm64 host never removes a thin x86_64 file"
[ -f "$T/p/lib/armonly" ] || fail "an arm64 host keeps its own"
[ "$(cat "$T/var/mavergreen/slim")" = on ] || fail "slim on is recorded"
[ "$(MAVERGREEN_HOST_ARCH=arm64 mg slim status)" = "slim: on, set with mavergreen slim on" ] || fail "status after on"

fresh; mkproduct p; mkproduct q
mkfat "$T/p/bin/tool" x86_64 arm64
out="$(MAVERGREEN_HOST_ARCH=x86_64 mg slim off)" || fail "slim off"
[ "$out" = "mavergreen: slimming is off; nothing installed was slimmed" ] || fail "off with none: $out"
[ "$(MAVERGREEN_HOST_ARCH=x86_64 mg slim status)" = "slim: off, set with mavergreen slim off" ] || fail "status after off"
MAVERGREEN_HOST_ARCH=x86_64 mg slim on >/dev/null || fail "slim on"
[ -f "$T/var/mavergreen/slimmed/p" ] || fail "slim on slims every installed product"
out="$(MAVERGREEN_HOST_ARCH=x86_64 mg slim off)" || fail "slim off"
[ "$out" = "mavergreen: slimming is off; reinstall these to restore their other slices: p" ] || fail "off lists: $out"
MAVERGREEN_HOST_ARCH=x86_64 mg slim apply p || fail "apply while off"
[ ! -e "$T/var/mavergreen/slimmed/p" ] || fail "apply while off clears the marker"

fresh; mkproduct p
mkdir -p "$T/var/mavergreen/slimmed"; echo x86_64 > "$T/var/mavergreen/slimmed/p"
mg uninstall p >/dev/null 2>&1 || fail "uninstall p"
[ ! -e "$T/var/mavergreen/slimmed/p" ] || fail "uninstall removes slimmed/p"

fresh; mkproduct p
mkdir -p "$w/fakebin"; printf '#!/bin/sh\necho Linux\n' > "$w/fakebin/uname"; chmod +x "$w/fakebin/uname"
out="$(env -u MAVERGREEN_HOST_ARCH PATH="$w/fakebin:$PATH" sh "$MGS" --root "$V" slim status 2>&1)" && fail "slim off a Mac must fail"
case "$out" in *"slimming is for a Mac"*) ;; *) fail "refusal was: $out" ;; esac

fresh; mkproduct p
mkdir -p "$T/p/lib"; { hexbytes cafebabe00000002; dd if=/dev/zero bs=200 count=1 2>/dev/null; } > "$T/p/lib/notmacho"
cp "$T/p/lib/notmacho" "$w/notmacho.orig"
MAVERGREEN_HOST_ARCH=x86_64 mg slim apply p >/dev/null || fail "apply must succeed"
cmp -s "$T/p/lib/notmacho" "$w/notmacho.orig" || fail "a cafebabe file whose slices are not Mach-O is left alone"
[ ! -s "$LOG" ] || fail "no ditto call for it"

fresh; mkproduct p
mkfat_with cffaedfe0000 "$T/p/lib/unk" arm64 arm64
mkfat_with cffaedfe0000 "$T/p/lib/mixed" arm64 i386
mkfat "$T/p/lib/armonly" arm64 arm64
MAVERGREEN_HOST_ARCH=x86_64 mg slim apply p >/dev/null || fail "apply must succeed"
[ ! -e "$T/p/lib/unk" ] && [ ! -e "$T/p/lib/armonly" ] || fail "a fat file of arm64 slices only is removed on x86_64"
[ -f "$T/p/lib/mixed" ] || fail "a fat file with an i386 slice is thinned, not removed"

fresh; mkproduct p
for mode in empty garbage wrong; do
  fresh; mkproduct p
  mkfat "$T/p/bin/tool" x86_64 arm64; cp "$T/p/bin/tool" "$w/tool.orig"
  env DITTO_MODE=$mode MAVERGREEN_HOST_ARCH=x86_64 sh "$MGS" --root "$V" slim apply p >/dev/null 2>&1 && fail "a bad ditto result ($mode) must fail the apply"
  cmp -s "$T/p/bin/tool" "$w/tool.orig" || fail "a bad ditto result ($mode) must leave the original"
  [ ! -e "$T/p/bin/tool.mavergreen-slim" ] || fail "a bad ditto result ($mode) leaves no temp file"
  [ -f "$T/var/mavergreen/slimmed/p" ] || fail "the marker is written before the first change, so a failure still shows ($mode)"
done

fresh; mkproduct p
mkfat "$T/p/bin/a" x86_64 arm64
ln "$T/p/bin/a" "$T/p/bin/b"
MAVERGREEN_HOST_ARCH=x86_64 mg slim apply p >/dev/null || fail "apply must succeed"
[ ! -s "$LOG" ] || fail "a hard-linked file is left alone: $(cat "$LOG")"

for harch in x86_64 arm64; do
  fresh; mkproduct p
  mkfat "$T/p/X.app/Contents/MacOS/x" x86_64 arm64
  mkthin "$T/p/X.app/Contents/Resources/armonly" arm64
  mkdir -p "$T/p/X.app/Contents/_CodeSignature"; : > "$T/p/X.app/Contents/_CodeSignature/CodeResources"
  mkfat "$T/p/bin/free" x86_64 arm64
  MAVERGREEN_HOST_ARCH=$harch mg slim on >/dev/null || fail "slim on ($harch)"
  [ -f "$T/p/X.app/Contents/Resources/armonly" ] || fail "a signed bundle's files are never removed ($harch)"
  grep -Fq "X.app" "$LOG" && fail "a signed bundle's files are never thinned ($harch)"
  grep -Fq "$T/p/bin/free" "$LOG" || fail "a file outside the bundle is thinned ($harch)"
done
fresh; mkproduct p
mkfat "$T/p/bin/h" x86_64 x86_64h
mkfat "$T/p/bin/h2" x86_64 x86_64h arm64
MAVERGREEN_HOST_ARCH=x86_64 mg slim apply p >/dev/null || fail "two slices of one cputype must not fail the apply"
[ ! -s "$LOG" ] || [ "$(wc -l < "$LOG" | tr -d ' ')" = 1 ] || fail "only the file with an arm64 slice is thinned"
grep -Fq "$T/p/bin/h2" "$LOG" || fail "x86_64, x86_64h and arm64 is thinned"
grep -Fq "$T/p/bin/h " "$LOG" && fail "x86_64 with x86_64h has nothing to drop"

fresh; mkproduct p
mkfat "$T/p/bin/x" x86_64 arm64
mkthin "$T/p/lib/armonly" arm64
mkdir -p "$T/p/_CodeSignature"; : > "$T/p/_CodeSignature/CodeResources"
MAVERGREEN_HOST_ARCH=x86_64 mg slim apply p >/dev/null || fail "apply must succeed"
[ ! -s "$LOG" ] && [ -f "$T/p/lib/armonly" ] || fail "a _CodeSignature at the product root protects the whole product"
echo "PASS: mavergreen-slim"
