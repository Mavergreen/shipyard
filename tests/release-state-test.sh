#!/bin/sh
# platform: host-agnostic
# spec: SKILL.md "A release is a declared state, not an event" -- the rendering is a WIRE FORMAT;
#       every published release records a digest computed from it, so a change here invalidates
#       all of them. A format bump means recompute, never republish. The golden values below are
#       the guard.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/release-state.sh"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/release-state-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
GOLD='v1:sha256:8c5fc85c689b60ccc9a3ed0120fa949e2bd9c0f9a121ac572fa11ba148312be7'

mk() {   # $1 = dir; a minimal product: upstream 1.2.3, one ingredient pin at 4.4.3
  mkdir -p "$1"
  printf '1.2.3\n' > "$1/UPSTREAM_VERSION"
  printf 'CMAKE_VERSION=4.4.3\nOTHER=ignored\n' > "$1/pins.env"
  printf '%s\n' '# Build ingredients' '' '## Declared state' '' \
    '- upstream: UPSTREAM_VERSION' '- cmake: pins.env:CMAKE_VERSION' > "$1/INGREDIENTS.md"
}

mk "$w/a"
got="$(sh "$S" --root "$w/a")"
[ "$got" = "$GOLD" ] || { echo "FAIL: the golden digest is sha256 of the rendering sorted by NAME, not by declaration order or path: got '$got', want '$GOLD'"; exit 1; }

got="$(sh "$S" --root "$w/a" --render)"
want="$(printf 'cmake=4.4.3\nupstream=1.2.3')"
[ "$got" = "$want" ] || { echo "FAIL: --render must show the rendering, which is what makes a digest mismatch debuggable at all: got '$got'"; exit 1; }

echo 'int main(void){return 0;}' > "$w/a/main.c"
got="$(sh "$S" --root "$w/a")"
[ "$got" = "$GOLD" ] || { echo "FAIL: a SOURCE change must not move the digest -- a push that only changes code has nothing to realise: $got"; exit 1; }

mk "$w/b"; printf 'CMAKE_VERSION=4.4.4\nOTHER=ignored\n' > "$w/b/pins.env"
got="$(sh "$S" --root "$w/b")"
want='v1:sha256:405b7fdda86a03f4ef636aceb3c7c819fe5d93208118cd365a0b962cb37c8004'
[ "$got" = "$want" ] || { echo "FAIL: an INGREDIENT change must move the digest: got '$got', want '$want'"; exit 1; }

mk "$w/c"
printf '%s\n' '# Build ingredients' '' '## Declared state' '' \
  '- cmake: pins.env:CMAKE_VERSION' '- upstream: UPSTREAM_VERSION' > "$w/c/INGREDIENTS.md"
got="$(sh "$S" --root "$w/c")"
[ "$got" = "$GOLD" ] || { echo "FAIL: declaration ORDER must not matter, the canonical name is the key: $got"; exit 1; }

mk "$w/d"; mv "$w/d/pins.env" "$w/d/versions.env"
printf '%s\n' '# Build ingredients' '' '## Declared state' '' \
  '- upstream: UPSTREAM_VERSION' '- cmake: versions.env:CMAKE_VERSION' > "$w/d/INGREDIENTS.md"
got="$(sh "$S" --root "$w/d")"
[ "$got" = "$GOLD" ] || { echo "FAIL: renaming the pin FILE must not change the digest -- that is why the name is the key: $got"; exit 1; }

mk "$w/k"; printf '  1.2.3  \n\n' > "$w/k/UPSTREAM_VERSION"
got="$(sh "$S" --root "$w/k")"
[ "$got" = "$GOLD" ] || { echo "FAIL: surrounding whitespace in a pin file must not be part of the value: $got"; exit 1; }

mk "$w/e"; rm "$w/e/pins.env"
if sh "$S" --root "$w/e" >"$w/e.out" 2>&1; then echo "FAIL: a missing pin file is a HARD error, never a silently different digest -- an unrenderable state must not look like a new one and publish -- missing pin file was accepted"; exit 1; fi
grep -q 'pins.env' "$w/e.out" || { echo "FAIL missing-file error does not name the file"; exit 1; }

mk "$w/f"; printf 'OTHER=only\n' > "$w/f/pins.env"
if sh "$S" --root "$w/f" >"$w/f.out" 2>&1; then echo "FAIL: a missing KEY inside an existing file is the same kind of error -- missing key was accepted"; exit 1; fi
grep -q 'CMAKE_VERSION' "$w/f.out" || { echo "FAIL missing-key error does not name the key"; exit 1; }

mk "$w/l"; : > "$w/l/UPSTREAM_VERSION"
if sh "$S" --root "$w/l" >"$w/l.out" 2>&1; then echo "FAIL: an empty pin file is an error too, not an empty value silently folded into the digest -- empty pin file was accepted"; exit 1; fi

mkdir -p "$w/g"; printf '%s\n' '# Build ingredients' '' 'prose only' > "$w/g/INGREDIENTS.md"
rc=0; sh "$S" --root "$w/g" >"$w/g.out" 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: no declared state at all must exit 2 naming the section, never a digest -- a repo that has not migrated must get a usage error, the parser's silence is not a green light here: got $rc"; exit 1; }
grep -q 'Declared state' "$w/g.out" || { echo "FAIL error does not name the section"; exit 1; }

mk "$w/h"
printf '%s\n' '# Build ingredients' '' '## Declared state' '' '- upstream:' > "$w/h/INGREDIENTS.md"
rc=0; sh "$S" --root "$w/h" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: a malformed declaration must propagate as a failure, not a partial digest -- like every other usage-or-declaration error this script detects, that failure is exit 2, not whatever declared-state.sh itself uses (1): got $rc"; exit 1; }

mk "$w/m"; printf 'CMAKE_VERSION= 4.4.3 \nOTHER=ignored\n' > "$w/m/pins.env"
got="$(sh "$S" --root "$w/m")"
[ "$got" = "$GOLD" ] || { echo "FAIL: whitespace around a KEYED pin's value must not be part of the value either -- the whole-file path already trims, and a cosmetic reformat of a pins.env line must not move the digest: $got"; exit 1; }

# spec: SKILL.md "A release is a declared state, not an event" -- --ref answers ruling 16:
#       version.sh's `auto` mode returns the EXISTING tag's N whenever the upstream already has
#       one, so it maps every declared state of one upstream to ONE version. An earlier design
#       read a version match as "already released" and backfilled the current digest onto that
#       release, cementing an unreleased ingredient bump as released with no later reconcile ever
#       looking again. --ref removes the guess: the digest of a released state comes from the
#       tree that was released.
GIT="git -c user.name=T -c user.email=t@example.com -c commit.gpgsign=false -c init.defaultBranch=main"
r="$w/r"
$GIT init -q "$r"
printf '1.2.3\n' > "$r/UPSTREAM_VERSION"
printf 'CMAKE_VERSION=4.4.3\nOTHER=ignored\n' > "$r/pins.env"
# spec: INGREDIENTS.md -- the pre-migration past, faithfully: at the tag there is no
#       "## Declared state" section AT ALL.
printf '%s\n' '# Build ingredients' '' 'prose only' > "$r/INGREDIENTS.md"
$GIT -C "$r" add -A
$GIT -C "$r" commit -q -m 'the release that predates this design'
$GIT -C "$r" tag 1.2.3-mavericks.1
printf 'CMAKE_VERSION=4.4.4\nOTHER=ignored\n' > "$r/pins.env"
printf '%s\n' '# Build ingredients' '' '## Declared state' '' \
  '- upstream: UPSTREAM_VERSION' '- cmake: pins.env:CMAKE_VERSION' > "$r/INGREDIENTS.md"
$GIT -C "$r" add -A
$GIT -C "$r" commit -q -m 'declare state, and bump cmake'

got="$(sh "$S" --root "$r")"
want='v1:sha256:405b7fdda86a03f4ef636aceb3c7c819fe5d93208118cd365a0b962cb37c8004'
[ "$got" = "$want" ] || { echo "FAIL: the working tree must render the CURRENT state: got '$got'"; exit 1; }

got="$(sh "$S" --root "$r" --ref 1.2.3-mavericks.1)"
[ "$got" = "$GOLD" ] \
  || { echo "FAIL: --ref must render what the TAG contained -- same rendering, same wire format, same golden digest, only the source of the values changes; the two must DIFFER, since that difference is the unreleased bump the version match could not see: --ref did not render the tag's own tree: got '$got'"; exit 1; }

got="$(sh "$S" --root "$r" --ref 1.2.3-mavericks.1 --render)"
want="$(printf 'cmake=4.4.3\nupstream=1.2.3')"
[ "$got" = "$want" ] \
  || { echo "FAIL: the DECLARATION comes from the working tree on purpose -- the tag's tree has no \"## Declared state\" section, because every pre-migration release predates it, and the question --ref answers is \"what were TODAY's declared inputs worth at that revision?\": got '$got'"; exit 1; }

rc=0; sh "$S" --root "$r" --ref no-such-tag >"$w/r17" 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: a revision that does not exist must exit 2, never a digest -- a shallow clone is the realistic way to get here, and a wrong digest recorded onto a release cannot be un-recorded (exit 3 forever): a bogus --ref should exit 2, got $rc"; exit 1; }
grep -q 'no-such-tag' "$w/r17" || { echo "FAIL the bogus-ref error does not name it"; exit 1; }
grep -q 'not a revision' "$w/r17" \
  || { echo "FAIL: it must say the REVISION is the problem, not blame the first declared file -- \"UPSTREAM_VERSION is not in no-such-tag's tree\" sends the reader to the wrong question entirely: a bogus --ref is not reported as a bad revision: $(cat "$w/r17")"; exit 1; }

printf '%s\n' '# Build ingredients' '' '## Declared state' '' \
  '- upstream: UPSTREAM_VERSION' '- cmake: pins.env:CMAKE_VERSION' '- later: later.pin' \
  > "$r/INGREDIENTS.md"
printf '7\n' > "$r/later.pin"
rc=0; sh "$S" --root "$r" --ref 1.2.3-mavericks.1 >"$w/r18" 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL: a declared path the revision's tree does not have must exit 2 too, naming the ref -- at an older tag a pin file may simply not exist yet, and \"absent\" must not render as a new state: a path absent at the ref should exit 2, got $rc"; exit 1; }
grep -q 'later.pin' "$w/r18" || { echo "FAIL the absent-at-ref error does not name the file"; exit 1; }
grep -q '1.2.3-mavericks.1' "$w/r18" || { echo "FAIL the absent-at-ref error does not name the ref"; exit 1; }
sh "$S" --root "$r" >/dev/null || { echo "FAIL: that same declaration must render fine from the working tree, so the failure is about the ref -- the working tree stopped rendering"; exit 1; }

# platform: BYTE order, pinned by names that GENUINELY DISAGREE about it. The golden fixture's
#           two names are plain alphabetic, so an edit dropping LC_ALL=C from the sort passed
#           every assertion above. The obvious repair -- `a-b`, `a_b`, `ab` -- does NOT close it:
#           measured on real glibc 2.39 (ubuntu 24.04, locale-gen en_US.UTF-8), those three sort
#           into byte order under BOTH C and en_US.UTF-8, so the fixture still could not fail on
#           either host. A DIGIT-BEARING name is what separates them, because glibc orders digits
#           before letters at the primary level while ignoring `-` and `_` there. Measured, both
#           hosts: LC_ALL=C sorts a-b, a1, a_b, ab, upstream (0x2D < 0x31 < 0x5F < 0x62);
#           en_US.UTF-8 (glibc only) sorts a1, a-b, a_b, ab, upstream instead -- macOS BSD sort is
#           byte order in every locale it has, all 203 of them. So this case fails on the
#           reconcile's ubuntu host the moment LC_ALL=C goes, which is the hazard: the digest is
#           computed on macOS at build time and on glibc in the nightly reconcile, and two hosts
#           disagreeing about one state is a dispatch loop -- one says the state is unreleased,
#           the other publishes it.
mk "$w/n"
printf '%s\n' '# Build ingredients' '' '## Declared state' '' '- upstream: UPSTREAM_VERSION' \
  '- ab: pins.env:AB' '- a_b: pins.env:A_UNDER_B' '- a-b: pins.env:A_DASH_B' '- a1: pins.env:A_ONE' \
  > "$w/n/INGREDIENTS.md"
printf 'AB=3\nA_UNDER_B=2\nA_DASH_B=1\nA_ONE=0\n' > "$w/n/pins.env"
got="$(sh "$S" --root "$w/n" --render)"
want="$(printf 'a-b=1\na1=0\na_b=2\nab=3\nupstream=1.2.3')"
[ "$got" = "$want" ] || { echo "FAIL: the rendering must be in byte order -- the bytes ARE the wire format, and a hash mismatch only ever says \"differs\": got '$got'"; exit 1; }
# platform: the expected value above is a hand-written literal, so prove independently that it
#           IS byte order rather than merely what the script happens to print: sort the same
#           lines, C locale, and compare.
byte="$(printf '%s\n' 'ab=3' 'a_b=2' 'a-b=1' 'a1=0' 'upstream=1.2.3' | LC_ALL=C sort)"
[ "$want" = "$byte" ] || { echo "FAIL the expected rendering is not byte order: '$want' vs '$byte'"; exit 1; }

# spec: the declared `upstream` must name the very file version.sh reads. Nothing else ties them
#       together: declared-state.sh accepts any path, and lib.sh reads
#       ${MAVERICKS_UPSTREAM_FILE:-UPSTREAM_VERSION}. A product tracking one file for its digest
#       while the version came from another would publish N+1 of the PREVIOUS upstream carrying
#       the NEW upstream's contents, and nothing anywhere would say so.
mk "$w/p"; mkdir -p "$w/p/components/foo"; printf '1.2.3\n' > "$w/p/components/foo/version"
printf '%s\n' '# Build ingredients' '' '## Declared state' '' \
  '- upstream: components/foo/version' '- cmake: pins.env:CMAKE_VERSION' > "$w/p/INGREDIENTS.md"
rc=0; sh "$S" --root "$w/p" >"$w/p.out" 2>&1 || rc=$?
[ "$rc" = 2 ] || { echo "FAIL an upstream version.sh does not read should exit 2, got $rc"; exit 1; }
grep -q 'components/foo/version' "$w/p.out" || { echo "FAIL the error does not name the declared path"; exit 1; }
grep -q 'UPSTREAM_VERSION' "$w/p.out" || { echo "FAIL the error does not name the path version.sh reads"; exit 1; }

got="$(MAVERICKS_UPSTREAM_FILE=components/foo/version sh "$S" --root "$w/p")"
[ "$got" = "$GOLD" ] || { echo "FAIL: it is the same coupling version.sh has, so the same override must satisfy both (which FILE the upstream lives in is not part of the rendering -- the NAME is) -- MAVERICKS_UPSTREAM_FILE did not reconcile the two: got '$got'"; exit 1; }
got="$(MAVERICKS_UPSTREAM_FILE="$w/p/components/foo/version" sh "$S" --root "$w/p")"
[ "$got" = "$GOLD" ] || { echo "FAIL: an absolute override rooted at the repo is the same path, and must be accepted as one -- was read as a different file: got '$got'"; exit 1; }

echo "PASS: release-state"
