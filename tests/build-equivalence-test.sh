#!/bin/sh
# platform: host-agnostic
#   usage: build-equivalence-test.sh
#          build-equivalence.sh over plain-file fixtures: pairing, the non-Mach-O levels, entries, output and
#          exit codes. Mach-O interface comparison is tested separately.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; S="$here/../scripts/build-equivalence.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/be-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
T="$(printf '\t')"
entries() {
  r="$1"; shift; mkdir -p "$w/$r"; printf '# x\n## Conformance deviations\n' > "$w/$r/INGREDIENTS.md"
  for e in "$@"; do printf -- '- %s\n' "$e" >> "$w/$r/INGREDIENTS.md"; done
}
run() {
  rc=0; sh "$S" "$@" > "$w/out" 2> "$w/err" || rc=$?
  out="$(cat "$w/out")"; err="$(cat "$w/err")"
}
want() {
  [ "$rc" -eq "$2" ] || fail "$1: exit $rc, want $2 (out: $out; err: $err)"
  [ "$out" = "$3" ] || fail "$1: stdout '$out', want '$3'"
}
fresh() { rm -rf "$w/A" "$w/B"; mkdir -p "$w/A" "$w/B"; entries none; }
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
entries none
entries r-text 'build-equivalence:etc/*: text differs, revisit: never'

fresh; put "$w/A/etc/a.txt" one; put "$w/B/etc/a.txt" one
run --repo "$w/none" "$w/A" "$w/B"; want "identical dirs" 0 ""
echo "ok: identical dirs"

entries r-unused 'build-equivalence:etc/*: nothing to excuse, revisit: now'
run --repo "$w/r-unused" "$w/A" "$w/B"; want "an entry excusing nothing" 1 "unused${T}-${T}etc/*"
[ "$err" = "build-equivalence: 0 differences, 0 excused, 1 unused" ] || fail "unused summary: $err"
echo "ok: unused entry fails"

put "$w/B/etc/a.txt" two
run --repo "$w/none" "$w/A" "$w/B"; want "text differs" 1 "bytes${T}etc/a.txt${T}-"
[ "$err" = "build-equivalence: 1 differences, 0 excused, 0 unused" ] || fail "summary: $err"
run --repo "$w/r-text" "$w/A" "$w/B"; want "text excused" 0 "bytes${T}etc/a.txt${T}etc/*"
[ "$err" = "build-equivalence: 1 differences, 1 excused, 0 unused" ] || fail "excused summary: '$err'"
echo "ok: bytes differ, excused by entry"

fresh; put "$w/A/f" 1; put "$w/B/f" 1
(cd "$w/none" && sh "$S" "$w/A" "$w/B" >/dev/null 2>&1) || fail "default --repo . with no INGREDIENTS.md there means zero entries, so identical dirs exit 0"
echo "ok: default repo"

fresh; put "$w/A/lib/libfoo-0123456789abcdef.rlib" same; put "$w/B/lib/libfoo-fedcba9876543210.rlib" same
run --repo "$w/none" "$w/A" "$w/B"; want "crate hash, same bytes" 0 ""
put "$w/B/lib/libfoo-fedcba9876543210.rlib" other
run --repo "$w/none" "$w/A" "$w/B"; want "crate hash, other bytes" 1 "bytes${T}lib/libfoo-H.rlib${T}-"
fresh; put "$w/A/d-0123456789abcdef/f-0123456789abcdef.x-0123456789abcdef.y" s; put "$w/B/d-0123456789abcdef/f-fedcba9876543210.x-fedcba9876543210.y" s
run --repo "$w/none" "$w/A" "$w/B"; want "every hash in the file name folds" 0 ""
fresh; put "$w/A/d-0123456789abcdef/f" s; put "$w/B/d-fedcba9876543210/f" s
run --repo "$w/none" "$w/A" "$w/B"; want "a hash in a directory name does not fold" 1 "only-a${T}d-0123456789abcdef/f${T}-
only-b${T}d-fedcba9876543210/f${T}-"
fresh; put "$w/A/lib/x-0123456789abcdef.a" 1; put "$w/A/lib/x-fedcba9876543210.a" 2; put "$w/B/lib/x-0123456789abcdef.a" 1
run --repo "$w/none" "$w/A" "$w/B"; [ "$rc" -eq 2 ] || fail "two names in A normalising alike: exit $rc, want 2"
run --repo "$w/none" "$w/B" "$w/A"; [ "$rc" -eq 2 ] || fail "two names in B normalising alike: exit $rc, want 2"
echo "ok: crate-hash normalisation"

fresh; put "$w/A/etc/only.txt" x; put "$w/B/etc/same" y; put "$w/A/etc/same" y; put "$w/B/usr/bonly" z
entries r-only 'build-equivalence-interface:etc/*: x, revisit: y' 'build-equivalence:usr/*: x, revisit: y'
run --repo "$w/r-only" "$w/A" "$w/B"
want "only-a, only-b never excusable" 1 "only-a${T}etc/only.txt${T}-
only-b${T}usr/bonly${T}-
unused${T}-${T}etc/*
unused${T}-${T}usr/*"
echo "ok: only-a and only-b are never excused, and an entry matching only them is unused"

fresh; ln -s one "$w/A/l"; ln -s two "$w/B/l"; put "$w/A/p" x; put "$w/B/p" x; chmod +x "$w/B/p"
put "$w/A/q" x; put "$w/B/q" x; chmod +x "$w/A/q" "$w/B/q"
entries r-meta 'build-equivalence:*l: a' 'build-equivalence-interface:p*: a'
run --repo "$w/r-meta" "$w/A" "$w/B"
want "meta" 1 "meta${T}l${T}-
meta${T}p${T}-
unused${T}-${T}*l
unused${T}-${T}p*"
fresh; ln -s same "$w/A/l"; ln -s same "$w/B/l"
run --repo "$w/none" "$w/A" "$w/B"; want "same symlink target" 0 ""
fresh; ln -s t "$w/A/l"; put "$w/B/l" t
run --repo "$w/none" "$w/A" "$w/B"; want "a link in one, a file in the other" 1 "meta${T}l${T}-"
echo "ok: symlink target and exec bit are meta, never excused"

fresh; put "$w/A/Odd Dir/a * b?.txt" 1; put "$w/B/Odd Dir/a * b?.txt" 2; put "$w/A/Odd Dir/a b.txt" 1; put "$w/B/Odd Dir/a b.txt" 1
run --repo "$w/none" "$w/A" "$w/B"; want "space and star in a name" 1 "bytes${T}Odd Dir/a * b?.txt${T}-"
entries r-space 'build-equivalence:Odd*: spaces'
run --repo "$w/r-space" "$w/A" "$w/B"; want "glob over a path with spaces" 0 "bytes${T}Odd Dir/a * b?.txt${T}Odd*"
echo "ok: odd names"

fresh; printf '\312\376\272\276\000\000\000\064one' > "$w/A/C.class"; printf '\312\376\272\276\000\000\000\064two' > "$w/B/C.class"
run --repo "$w/none" "$w/A" "$w/B"; want "a Java class shares the fat magic" 1 "bytes${T}C.class${T}-"
echo "ok: a Java class file is not Mach-O"

fresh; mkdir -p "$w/A/a" "$w/B/a"; put "$w/A/a/f1" 1; put "$w/B/a/f1" 2; put "$w/A/a/f2" 1; put "$w/B/a/f2" 2
put "$w/A/a/fX" 1; put "$w/B/a/fX" 2; put "$w/A/b[1]" 1; put "$w/B/b[1]" 2
entries r-glob 'build-equivalence:a/f[12]: class' 'build-equivalence:a/f?: any' 'build-equivalence:b[[]1]: bracket'
run --repo "$w/r-glob" "$w/A" "$w/B"
want "glob metacharacters" 0 "bytes${T}a/f1${T}a/f[12]
bytes${T}a/f2${T}a/f[12]
bytes${T}a/fX${T}a/f?
bytes${T}b[1]${T}b[[]1]"
echo "ok: [ and ? globs"

fresh; put "$w/A/etc/a" 1; put "$w/B/etc/a" 2
entries r-both 'build-equivalence:etc/*: bytes' 'build-equivalence-interface:etc/*: interface'
run --repo "$w/r-both" "$w/A" "$w/B"; want "one entry of each kind" 0 "bytes${T}etc/a${T}etc/*"
[ "$err" = "build-equivalence: 1 differences, 1 excused, 0 unused" ] || fail "both kinds used: $err"
entries r-iface 'build-equivalence-interface:etc/*: interface'
run --repo "$w/r-iface" "$w/A" "$w/B"; want "an interface entry excuses a bytes difference and is used" 0 "bytes${T}etc/a${T}etc/*"
echo "ok: both kinds count as used"

fresh
run "$w/A"; [ "$rc" -eq 2 ] || fail "one argument: exit $rc, want 2"
run "$w/A" "$w/nonexistent"; [ "$rc" -eq 2 ] || fail "nonexistent path: exit $rc, want 2"
printf 'not a pkg\n' > "$w/junk.pkg"
run --repo "$w/none" "$w/A" "$w/junk.pkg"; [ "$rc" -eq 2 ] || fail "a file that is no pkg: exit $rc, want 2"
run --repo "$w/nonexistent" "$w/A" "$w/B"; [ "$rc" -eq 2 ] || fail "--repo not a directory: exit $rc, want 2"
run --bogus "$w/A" "$w/B"; [ "$rc" -eq 2 ] || fail "unknown option: exit $rc, want 2"
mkdir -p "$w/empty"
run --repo "$w/empty" "$w/A" "$w/B"; want "--repo without INGREDIENTS.md is zero entries" 0 ""
entries r-bare 'build-equivalence:*: all'
run --repo "$w/r-bare" "$w/A" "$w/B"; [ "$rc" -eq 2 ] || fail "an entry deviations.sh refuses: exit $rc, want 2"
fresh; put "$w/A/new
line" 1
run --repo "$w/none" "$w/A" "$w/B"; [ "$rc" -eq 2 ] || fail "newline in a path: exit $rc, want 2"
fresh; put "$w/A/new
dir/f" 1
run --repo "$w/none" "$w/A" "$w/B"; [ "$rc" -eq 2 ] || fail "newline in a directory name: exit $rc, want 2"
fresh; put "$w/A/tab${T}dir/f" 1
run --repo "$w/none" "$w/A" "$w/B"; [ "$rc" -eq 2 ] || fail "tab in a directory name: exit $rc, want 2"
echo "ok: misuse exits 2"

SD="$(sh "$here/../scripts/fetch_stevedore.sh" 2>/dev/null)" || { echo "SKIP: no stevedore, pkg inputs untested"; echo "PASS: build-equivalence"; exit 0; }
SOURCE_DATE_EPOCH=1700000000; export SOURCE_DATE_EPOCH
mkpkg() {
  rm -rf "$w/pk"; mkdir -p "$w/pk/c1/bin" "$w/pk/c2/share"
  printf 'tool\n' > "$w/pk/c1/bin/tool"; printf '%s\n' "$2" > "$w/pk/c2/share/data"
  if [ -n "${4:-}" ]; then mkdir -p "$w/pk/c2/bin"; printf 'dup\n' > "$w/pk/c2/bin/tool"; fi
  sh "$here/../scripts/build_component_pkg.sh" --root "$w/pk/c1" --identifier t.one --version 1 --install-location /opt/p --out "$w/pk/one.pkg" >/dev/null 2>&1
  sh "$here/../scripts/build_component_pkg.sh" --root "$w/pk/c2" --identifier t.two --version 1 --install-location "$3" --out "$w/pk/two.pkg" >/dev/null 2>&1
  cat > "$w/pk/d.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>t</title>
    <choices-outline><line choice="default"><line choice="t.one"/><line choice="t.two"/></line></choices-outline>
    <choice id="default"/>
    <choice id="t.one" visible="false"><pkg-ref id="t.one"/></choice>
    <choice id="t.two" visible="false"><pkg-ref id="t.two"/></choice>
    <pkg-ref id="t.one" version="0" onConclusion="none">one.pkg</pkg-ref>
    <pkg-ref id="t.two" version="0" onConclusion="none">two.pkg</pkg-ref>
</installer-gui-script>
XML
  "$SD" product --distribution "$w/pk/d.xml" --package "$w/pk/one.pkg" --package "$w/pk/two.pkg" --mtime 1700000000 --out "$1" >/dev/null 2>&1
}
mkpkg "$w/a.pkg" 1 /opt/q || fail "could not build the A fixture pkg"
mkpkg "$w/b.pkg" 2 /opt/q || fail "could not build the B fixture pkg"
run --repo "$w/none" "$w/a.pkg" "$w/b.pkg"
want "two products, two components each" 1 "bytes${T}opt/q/share/data${T}-"
mkdir -p "$w/staged/opt/p/bin" "$w/staged/opt/q/share"; printf 'tool\n' > "$w/staged/opt/p/bin/tool"; printf '1\n' > "$w/staged/opt/q/share/data"
run --repo "$w/none" "$w/a.pkg" "$w/staged"; want "a pkg against a staged tree pairs by install path" 0 ""
mkpkg "$w/c.pkg" 1 /opt/p dup || fail "could not build the colliding fixture pkg"
run --repo "$w/none" "$w/c.pkg" "$w/staged"; [ "$rc" -eq 2 ] || fail "two components installing one path: exit $rc, want 2"
case "$err" in *opt/p/*) ;; *) fail "the collision must name the path: $err" ;; esac
echo "ok: pkg inputs pair relative to the install root"
mkscripts() {
  rm -rf "$w/pk"; mkdir -p "$w/pk/r/bin" "$w/pk/s"; printf 'tool\n' > "$w/pk/r/bin/tool"
  printf '#!/bin/sh\nexit %s\n' "$2" > "$w/pk/s/postinstall"; chmod +x "$w/pk/s/postinstall"
  if [ -n "${3:-}" ]; then printf '#!/bin/sh\nexit 0\n' > "$w/pk/s/preinstall"; chmod +x "$w/pk/s/preinstall"; fi
  sh "$here/../scripts/build_component_pkg.sh" --root "$w/pk/r" --identifier t.s --version 1 --install-location /opt/s --scripts "$w/pk/s" --out "$1" >/dev/null 2>&1
}
mkscripts "$w/sa.pkg" 0 || fail "could not build the A scripts pkg"
mkscripts "$w/sb.pkg" 1 pre || fail "could not build the B scripts pkg"
run --repo "$w/none" "$w/sa.pkg" "$w/sb.pkg"
want "pkgs differing only in their scripts" 1 "bytes${T}.pkg/t.s/scripts/postinstall${T}-
only-b${T}.pkg/t.s/scripts/preinstall${T}-"
mkscripts "$w/sc.pkg" 0 || fail "could not build the C scripts pkg"
run --repo "$w/none" "$w/sa.pkg" "$w/sc.pkg"; want "pkgs with the same scripts" 0 ""
echo "ok: each component's scripts compare under .pkg/<identifier>/scripts/"
echo "PASS: build-equivalence"
