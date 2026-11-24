#!/bin/sh
# platform: host-agnostic
set -eu
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
here="$(cd "$(dirname "$0")" && pwd)"
SIF="$here/../scripts/set_install_floor.sh"
BCP="$here/../scripts/build_component_pkg.sh"
FX="$here/fixtures/macho"
w="$(mktemp -d "${TMPDIR:-/tmp}/floor-arch.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $1"; exit 1; }
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || fail "fetch_stevedore.sh failed -- the pkg block is the only gate for this seam, so it cannot be skipped"
skipped=0
MAVERGREEN_REPO_ROOT="$w/repo"; export MAVERGREEN_REPO_ROOT
P="$w/repo/.mavergreen/products/w"
mkdir -p "$P"; printf 'W\n' > "$P/noun"

readers() {
  ( SELF="$here/../scripts"
    . "$SELF/mavergreen-meta.sh"; . "$SELF/lib/name-rules.sh"; . "$SELF/lib/macho-tools.sh"
    mach_tool LIPO >/dev/null 2>&1 && mach_tool OTOOL >/dev/null 2>&1 )
}
need_readers() {
  readers && return 0
  echo "SKIP $1: no LLVM Mach-O readers here"; skipped=$((skipped + 1)); return 1
}

n=0
build() {
  n=$((n + 1)); _l="$1"; shift
  rm -rf "$w/root-$n"; mkdir -p "$w/root-$n/opt/mavergreen/w"
  for _f in "$@"; do
    _d="${_f%%=*}"; _s="${_f#*=}"
    mkdir -p "$w/root-$n/$(dirname "$_d")"
    case "$_f" in
      *=*) cp "$FX/$_s" "$w/root-$n/$_d";;
      *) printf '#!/bin/sh\nexit 0\n' > "$w/root-$n/$_d";;
    esac
  done
  mkdir -p "$w/c"
  "$SD" component --root "$w/root-$n" --identifier dev.mavergreen.w --version 1.0 --install-location / \
    --mtime "$SOURCE_DATE_EPOCH" --out "$w/c/$n.pkg" >/dev/null
  rc=0; out="$(sh "$SIF" --short w --version 1.0 --component "$w/c/$n.pkg" --dist "$w/d$n" --base-version 1.0.9 2>"$w/err$n")" || rc=$?
  err="$(cat "$w/err$n")"
  [ "$rc" -ne 0 ] || { "$SD" expand "$out" "$w/x$n" >/dev/null; D="$w/x$n/Distribution"; }
}
built() { [ "$rc" -eq 0 ] || fail "$1 must build: rc $rc: $err"; }
refused1() { [ "$rc" -eq 1 ] || fail "$1 exits 1: got $rc: $err"; printf '%s\n' "$err" | grep -qF -- "$2" || fail "$1 says '$2': $err"; }
has() { grep -qF -- "$2" "$D" || fail "$1: the Distribution has '$2': $(cat "$D")"; }
hasnt() { grep -qF -- "$2" "$D" && fail "$1: the Distribution has no '$2'" || :; }
installs_check() { has "$1" '<installation-check script="mavergreen_arch()"/>'; }
no_check() { hasnt "$1" 'installation-check'; hasnt "$1" '<script>'; }
has_options() {
  has "$1" 'hostArchitectures="x86_64,arm64"'
  _o="$(sed 's/^[[:space:]]*//' "$D" | awk '/^<(allowed-os-versions|options|installation-check|script)[ >\/]/ { t = $1; sub(/^</, "", t); sub(/[>\/].*/, "", t); printf "%s ", t }')"
  case "$_o" in
    "allowed-os-versions options installation-check script "|"allowed-os-versions options ") ;;
    *) fail "$1: the Distribution orders allowed-os-versions, options, then the installation-check and script: got '$_o'";;
  esac
  case "$(cat "$D")" in *installation-check*) [ "$_o" = "allowed-os-versions options installation-check script " ] || fail "$1: a rule has its installation-check and script";; esac
}
newer() { mkdir -p "$w/repo/.mavergreen/deviations/newer-macos/t"
  printf 'w\n' > "$w/repo/.mavergreen/deviations/newer-macos/t/scope"
  printf 'w serves newer macOS\n' > "$w/repo/.mavergreen/deviations/newer-macos/t/reason"
  printf 'w stops serving newer macOS\n' > "$w/repo/.mavergreen/deviations/newer-macos/t/revisit"; }
no_newer() { rm -rf "$w/repo/.mavergreen/deviations"; }

mkdir -p "$w/stubs"
printf '#!/bin/sh\necho called >> "%s/marker"\nexit 1\n' "$w" > "$w/stubs/reader"
printf '#!/bin/sh\nexit 1\n' > "$w/stubs/xcrun"
chmod +x "$w/stubs/reader" "$w/stubs/xcrun"
{
  SAVED_PATH="$PATH"
  PATH="$w/stubs:$PATH"; LIPO="$w/stubs/reader"; OTOOL="$w/stubs/reader"; SHIPYARD_MACHO_DIRS=; export PATH LIPO OTOOL SHIPYARD_MACHO_DIRS
  build neutral opt/mavergreen/w/bin/sh-tool
  built neutral
  [ ! -e "$w/marker" ] || fail "a payload with no Mach-O file never calls a reader"
  has neutral 'min="10.9.5" before="10.11"'; no_check neutral; has_options neutral
  grep -q 'productbuild_floor: .* built: neutral, ' "$w/err$n" || fail "the last line names the class and range: $(cat "$w/err$n")"
  [ "$(tail -1 "$w/err$n")" = "productbuild_floor: $out built: neutral, Mac OS X 10.9.5 through 10.10" ] || fail "neutral's last line: $(tail -1 "$w/err$n")"
  PATH="$SAVED_PATH"; unset LIPO OTOOL SHIPYARD_MACHO_DIRS
}

{
  SAVED_PATH="$PATH"; SAVED_FX="$FX"
  mkdir -p "$w/fx"; printf '\317\372\355\376' > "$w/fx/thin"
  FX="$w/fx"
  PATH="$w/stubs:$PATH"; LIPO="$w/stubs/reader"; OTOOL="$w/stubs/reader"; SHIPYARD_MACHO_DIRS=; export PATH LIPO OTOOL SHIPYARD_MACHO_DIRS
  build strict-rejected opt/mavergreen/w/bin/thin=thin
  refused1 strict-rejected "opt/mavergreen/w/bin/thin has a Mach-O magic that macho-slices.sh rejects"
  PATH="$SAVED_PATH"; FX="$SAVED_FX"; unset LIPO OTOOL SHIPYARD_MACHO_DIRS
}

if need_readers x86_64; then
  no_newer
  build x86_64 opt/mavergreen/w/bin/clean=clean; built x86_64
  has x86_64 'min="10.9.5" before="10.11"'; installs_check x86_64; has x86_64 'Built for Intel Macs'
  has x86_64 'running Mac OS X 10.9 or 10.10'; has_options x86_64
  build archive opt/mavergreen/w/lib/libm.a=libm.a; built archive
  has archive 'Built for Intel Macs'; installs_check archive; has_options archive
  newer
  build intel-newer opt/mavergreen/w/bin/clean=clean; built intel-newer
  has intel-newer 'min="10.9.5"/>'; hasnt intel-newer before; installs_check intel-newer
  hasnt intel-newer 'running Mac OS X 10.9 or 10.10'
fi

if need_readers universal; then
  newer
  build universal opt/mavergreen/w/bin/fat130=fat130; built universal
  has universal 'min="10.9.5"/>'; hasnt universal before; has universal 'Needs a newer macOS'
  has universal "compareVersions(system.version.ProductVersion, '13.0') &lt; 0"; has_options universal
  [ "$(tail -1 "$w/err$n")" = "productbuild_floor: $out built: universal, Mac OS X 10.9.5 or later; on Apple Silicon, macOS 13.0 or later" ] || fail "universal's last line: $(tail -1 "$w/err$n")"
  build universal-max opt/mavergreen/w/bin/fat130=fat130 opt/mavergreen/w/libexec/fat280=fat280; built universal-max
  has universal-max "'28.0') &lt; 0"
  no_newer
  build universal-no opt/mavergreen/w/bin/fat130=fat130
  refused1 universal-no "w ships an arm64 slice (opt/mavergreen/w/bin/fat130), which serves only macOS 11 or later; declare .mavergreen/deviations/newer-macos/<label>/ with scope w"
  [ ! -e "$w/d$n" ] || [ -z "$(ls "$w/d$n")" ] || fail "a refused build writes no pkg"
  newer
  printf '10.9.4\n' > "$P/floor"
  build floor opt/mavergreen/w/bin/fat130=fat130; built floor
  has floor 'min="10.9.4"'; rm -f "$P/floor"
  build a130 opt/mavergreen/w/bin/a130=a130 opt/mavergreen/w/bin/clean=clean
  refused1 a130 'bin/a130 is arm64 only'
  build a00 opt/mavergreen/w/bin/a00=a00 opt/mavergreen/w/bin/clean=clean
  refused1 a00 'bin/a00: arm64 slice records no minimum OS'
  no_newer
  printf 'lib/x/*\n' > "$P/target"
  build target opt/mavergreen/w/lib/x/a130=a130 opt/mavergreen/w/bin/clean=clean; built target
  has target 'before="10.11"'; installs_check target; has target 'Built for Intel Macs'
  rm -f "$P/target"
  build exempt "Library/Application Support/Mavergreen/w-helper.app/a130=a130" opt/mavergreen/w/bin/clean=clean
  refused1 exempt 'w-helper.app/a130 is arm64 only'
fi

for flag in "--host-arch x86_64" "--min-os 10.9.5"; do
  rc=0; err="$(sh "$SIF" --short w --version 1.0 --component "$w/c/1.pkg" --dist "$w/dr" $flag 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -eq 2 ] || fail "${flag%% *} is refused with exit 2: got $rc"
  printf '%s\n' "$err" | grep -qF -- "productbuild_floor: ${flag%% *} is refused; " || fail "${flag%% *}'s refusal: $err"
done
printf '%s\n' "$err" | grep -qF 'the floor is .mavergreen/products/<short>/floor' || fail "--min-os names its fix: $err"
rc=0; err="$(sh "$SIF" --short w --version 1.0 --component "$w/c/1.pkg" --dist "$w/dr" --host-arch x86_64 2>&1 >/dev/null)" || rc=$?
printf '%s\n' "$err" | grep -qF 'every pkg declares hostArchitectures="x86_64,arm64"' || fail "--host-arch names its fix: $err"

[ "$skipped" -eq 0 ] || exit 77
echo "PASS: set-install-floor-arch"
