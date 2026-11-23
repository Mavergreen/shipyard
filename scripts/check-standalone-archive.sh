#!/bin/sh
# platform: host-agnostic -- Mach-O is read with the pinned clang22's llvm tools; --run starts programs only on a Mac of the archive's arch
#   usage: check-standalone-archive.sh [--run] ARCHIVE
#          Judges a standalone archive, SHORT-VERSION-macos-ARCH.tar.gz (ARCH universal, x86_64 or
#          arm64; SHORT runs to the first hyphen before a digit). Findings, each on its own line:
#          an entry outside the one top directory SHORT-VERSION/; the pkg's manifest
#          (mavergreen.plist), an updater (*-updater.app), a launchd job, or pkg install scripts or
#          metadata at the top; an AppleDouble entry; a symlink into /usr/local/mavergreen; a script
#          (#!) naming /usr/local/mavergreen; a Mach-O whose loads, rpaths or install name are not
#          under /usr/lib, /System, @rpath, @loader_path or @executable_path. Mach-O is read by
#          scripts/lib/mach-interface.sh; with no OTOOL, LIPO or NM set and no installed clang22, the
#          pinned one comes from fetch_clang22.sh. --run, on a Mac that runs ARCH natively, unpacks
#          under a directory with a space and starts every bin/ entry with --version, finding any that
#          dyld cannot start; elsewhere it says it did not run them.
#          Exit 0 with no findings, 1 with any, 2 on a usage or naming error or a reader that cannot
#          read a Mach-O.
# spec: tests/check-standalone-archive-test.sh
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
usage='usage: check-standalone-archive.sh [--run] ARCHIVE'
run=no
if [ "${1:-}" = --run ]; then run=yes; shift; fi
[ $# -eq 1 ] || { echo "$usage" >&2; exit 2; }
archive="$1"
[ -f "$archive" ] || { echo "check-standalone-archive: no archive at $archive" >&2; exit 2; }
b="${archive##*/}"
case "$b" in
  *-macos-universal.tar.gz) arch=universal ;;
  *-macos-x86_64.tar.gz) arch=x86_64 ;;
  *-macos-arm64.tar.gz) arch=arm64 ;;
  *) echo "check-standalone-archive: $b is not named <short>-<version>-macos-<universal|x86_64|arm64>.tar.gz" >&2; exit 2 ;;
esac
top="${b%-macos-$arch.tar.gz}"
short="$(printf '%s\n' "$top" | sed 's/-[0-9].*//')"
ver="${top#"$short"-}"
case "$short" in ''|-*|*[!a-z0-9-]*) short="" ;; esac
[ -n "$short" ] && [ "$short" != "$top" ] && [ -n "$ver" ] \
  || { echo "check-standalone-archive: $b does not read as <short>-<version>: the short name is lowercase, and the version follows the first hyphen before a digit" >&2; exit 2; }

t="$(mktemp -d "${TMPDIR:-/tmp}/check-standalone.XXXXXX")"
trap 'chmod -R u+w "$t" 2>/dev/null; rm -rf "$t"' EXIT
: > "$t/findings"
finding() { printf '%s\n' "$*" >> "$t/findings"; }
report() {
  nf="$(wc -l < "$t/findings" | tr -d ' ')"
  if [ "$nf" -gt 0 ]; then
    head -50 "$t/findings" | sed "s|^|check-standalone-archive: $b: |" >&2
    [ "$nf" -le 50 ] || echo "check-standalone-archive: $b: ... and $((nf - 50)) more" >&2
    echo "check-standalone-archive: $b: $nf finding(s); a standalone archive is the product's tree alone, and runs from wherever it is unpacked" >&2
    exit 1
  fi
}

tar -tzf "$archive" > "$t/list" 2> "$t/err" || { finding "tar cannot list it: $(head -1 "$t/err")"; report; }
awk -v top="$top" '
  { e = $0; sub(/\/$/, "", e) }
  e != top && index(e, top "/") != 1 { print "it holds " e ", outside " top "/"; next }
  { r = substr(e, length(top) + 2); n = split(r, c, "/"); base = c[n] }
  base ~ /^\._/ { print "it holds an AppleDouble entry: " e }
  base == "mavergreen.plist" { print "it holds the pkg manifest " e ": the archive is the tree without it" }
  {
    for (i = 1; i <= n; i++) if (c[i] ~ /-updater\.app$/) {
      u = top; for (j = 1; j <= i; j++) u = u "/" c[j]
      if (!(u in seen)) { seen[u] = 1; print "it holds an updater, " u ": the standalone form has no updater" }
    }
  }
  r ~ /(^|\/)Library\/Launch(Agents|Daemons)\// { print "it holds a launchd job, " e ": LaunchAgents and LaunchDaemons are the pkg'"'"'s" }
  n == 1 && (base == "preinstall" || base == "postinstall" || base == "Scripts" || base == "PackageInfo" || base == "Bom" || base == "Payload" || base == "Distribution") {
    print "it holds a pkg install script or package metadata at its top: " e
  }' "$t/list" >> "$t/findings"
entries="$(wc -l < "$t/list" | tr -d ' ')"
[ -n "$(awk -v top="$top" '{ e = $0; sub(/\/$/, "", e) } e == top || index(e, top "/") == 1 { print; exit }' "$t/list")" ] \
  || finding "it has no top directory $top/"

u="$t/with space"
mkdir "$u"
tar -xzf "$archive" -C "$u" 2> "$t/err" || { finding "tar cannot unpack it: $(head -1 "$t/err")"; report; }
X="$u/$top"
if [ -d "$X" ]; then
  (cd "$X" && find . -type l | LC_ALL=C sort) > "$t/links"
  while IFS= read -r l; do
    tg="$(readlink "$X/$l")" || continue
    case "$tg" in /usr/local/mavergreen|/usr/local/mavergreen/*) finding "${l#./} links to $tg, which only the pkg installs" ;; esac
  done < "$t/links"
  (cd "$X" && find . -type f | LC_ALL=C sort) > "$t/files"
else
  : > "$t/files"
fi

. "$SELF/lib/mach-nm.sh"
. "$SELF/lib/mach-interface.sh"
: > "$t/machos"
while IFS= read -r f; do
  r="${f#./}"
  case "$(shipyard_mach_kind "$X/$r")" in
    thin|fat) printf '%s\n' "$r" >> "$t/machos"; continue ;;
    archive) continue ;;
  esac
  [ "$(dd if="$X/$r" bs=2 count=1 2>/dev/null)" = '#!' ] || continue
  hit="$(grep -n '/usr/local/mavergreen' "$X/$r" 2>/dev/null | head -1)" || hit=""
  [ -z "$hit" ] || finding "$r is a script naming /usr/local/mavergreen, which only the pkg installs (line ${hit%%:*}: $(printf '%s' "${hit#*:}" | cut -c1-120))"
done < "$t/files"

nmacho="$(wc -l < "$t/machos" | tr -d ' ')"
if [ "$nmacho" -gt 0 ] && [ -z "${OTOOL:-}${LIPO:-}${NM:-}" ] \
  && [ ! -x "${SHIPYARD_MG_PREFIX:-/usr/local/mavergreen}/clang22/bin/llvm-otool" ] \
  && [ ! -x "${SHIPYARD_MG_PREFIX:-/usr/local/mavergreen}/clang22-cross/bin/llvm-otool" ]; then
  cl="$(sh "$SELF/fetch_clang22.sh" "$SELF/../components/clang22" 2> "$t/err")" \
    || { sed 's/^/  /' "$t/err" >&2; echo "check-standalone-archive: no Mach-O reader: no OTOOL, no installed clang22, and fetch_clang22.sh could not fetch the pinned one" >&2; exit 2; }
  OTOOL="$cl/bin/llvm-otool"; LIPO="$cl/bin/llvm-lipo"; NM="$cl/bin/llvm-nm"; export OTOOL LIPO NM
fi
while IFS= read -r r; do
  rc=0; shipyard_mach_interface "$X/$r" > "$t/mi" 2> "$t/err" || rc=$?
  case "$rc" in
    0) ;;
    1) continue ;;
    *) sed 's/^/  /' "$t/err" >&2; echo "check-standalone-archive: cannot read the Mach-O $r" >&2; exit 2 ;;
  esac
  awk -v r="$r" '
    function ok(p) { return p ~ /^(\/usr\/lib\/|\/System\/|@rpath\/|@loader_path(\/|$)|@executable_path(\/|$))/ }
    function rest(k,   s, i) { s = ""; for (i = k; i <= NF; i++) s = s (s == "" ? "" : " ") $i; return s }
    $2 == "dylib" { p = rest(5); w = "loads " p }
    $2 == "id" { p = rest(3); w = "has the install name " p }
    $2 == "rpath" { p = rest(4); w = "has the rpath " p }
    ($2 == "dylib" || $2 == "id" || $2 == "rpath") && !ok(p) {
      if (!(w in a)) { o[++m] = w; a[w] = $1 } else if (index(" " a[w] " ", " " $1 " ") == 0) a[w] = a[w] "," $1
    }
    END { for (i = 1; i <= m; i++) print r " (" a[o[i]] ") " o[i] ", outside /usr/lib, /System, @rpath, @loader_path and @executable_path" }' "$t/mi" >> "$t/findings"
done < "$t/machos"

ran=""
if [ "$run" = yes ]; then
  host=""
  if [ "$(uname -s)" = Darwin ]; then
    case "$(uname -m):$arch" in x86_64:universal|x86_64:x86_64|arm64:universal|arm64:arm64) host=yes ;; esac
  fi
  if [ -z "$host" ]; then
    echo "check-standalone-archive: $b: --run: bin/ entries not run: this host ($(uname -s) $(uname -m)) does not run $arch macOS programs natively"
  elif [ -d "$X/bin" ]; then
    mkdir "$t/cwd"
    nran=0
    for f in "$X"/bin/*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      r="bin/${f##*/}"
      rm -f "$t/timeout"
      (cd "$t/cwd" && exec env -i HOME="$t" PATH=/usr/bin:/bin "$f" --version) < /dev/null > "$t/o" 2>&1 &
      pid=$!
      (i=0; while kill -0 "$pid" 2>/dev/null; do i=$((i + 1)); if [ "$i" -gt 20 ]; then : > "$t/timeout"; kill -KILL "$pid" 2>/dev/null; exit 0; fi; sleep 1; done) &
      wd=$!
      rc=0; wait "$pid" || rc=$?
      kill "$wd" 2>/dev/null || :; wait "$wd" 2>/dev/null || :
      nran=$((nran + 1))
      if [ -f "$t/timeout" ]; then
        echo "check-standalone-archive: $b: --run: $r was still running after 20s and was stopped; it started"
      elif grep -q -E 'dyld|Library not loaded|image not found|Symbol not found' "$t/o" || [ "$rc" -eq 133 ] || [ "$rc" -eq 134 ]; then
        finding "$r did not start from $u (exit $rc): $(grep -m 1 -E 'dyld|Library not loaded|image not found|Symbol not found' "$t/o" || head -1 "$t/o")"
      else
        echo "check-standalone-archive: $b: --run: $r --version started (exit $rc)"
      fi
    done
    ran=", $nran bin/ entries started"
  fi
fi

report
echo "check-standalone-archive: ok — $b: $short $ver ($arch), $entries entries, $nmacho Mach-O files read$ran"
