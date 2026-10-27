#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/conventions_fixture.sh"

REPO=Mavergreen/ed25519
sc="$work/sc"; cp -R "$here/../scripts" "$sc"; rm -f "$sc/conventions-grandfathered"
S2="$sc/check-family-conventions.sh"
grandfather() { printf '%s\n' "$@" | sort > "$sc/conventions-grandfathered"; }
gate() {  # $1 = dir
  (cd "$1" && GITHUB_REPOSITORY="$REPO" sh "$S2" 2>&1)
}
fails() {  # $1 = label, $2 = dir, $3 = phrase
  out="$(gate "$2")" && { echo "FAIL: $1 must fail"; exit 1; }
  printf '%s\n' "$out" | grep -q -- "$3" || { echo "FAIL: $1 should fail with '$3': $out"; exit 1; }
}
passes() {  # $1 = label, $2 = dir
  out="$(gate "$2")" || { echo "FAIL: $1 must pass: $out"; exit 1; }
}
add() { (cd "$1" && git add -A) >/dev/null 2>&1; }

mkrepo7() { mkrepo "$@"; printf '# Build ingredients\n' > "$1/INGREDIENTS.md"; }
conf='      - run: sh "$SHIPYARD_SCRIPTS/artifact-facts.sh" dist "$FULL" | sh "$SHIPYARD_SCRIPTS/check-artifact-conformance.sh"'
stage='sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage stage --product w --name W --version 1 --scripts-out scr'
pkok() {  # $1 = dir, $2 = the build script's packaging line, $3 = its path (default build/package.sh)
  mkrepo7 "$1"; p="${3:-build/package.sh}"; mkdir -p "$1/$(dirname "$p")"
  printf '#!/bin/sh\n%s\n%s\n' "$2" "$stage" > "$1/$p"
  printf '%s\n' "$conf" >> "$1/.github/workflows/release.yml"
  add "$1"
}
PKG='pkgbuild --root stage --identifier dev.mavergreen.w out.pkg'

# spec: SKILL.md "Family conventions" check 35 -- a direct pkgbuild or productbuild call outside
#       tests/ and test/ needs a packager:<path> deviation or a conventions-grandfathered line.
grandfather
pkok "$work/pk-plain" "$PKG"
fails "check 35: a direct pkgbuild call" "$work/pk-plain" 'packager build/package.sh'
pkok "$work/pk-product" 'productbuild --package w.pkg out.pkg'
fails "check 35: a direct productbuild call" "$work/pk-product" 'packager build/package.sh'

pkok "$work/pk-dev" "$PKG"
printf '\n## Conformance deviations\n\n- packager:build/package.sh: the oracle compares against the system tool, exit when stevedore is the oracle\n' >> "$work/pk-dev/INGREDIENTS.md"
add "$work/pk-dev"
passes "check 35: a packager deviation" "$work/pk-dev"

pkok "$work/pk-gf" "$PKG"
grandfather "packager ed25519 build/package.sh"
passes "check 35: a grandfathered path" "$work/pk-gf"
grandfather "packager other-repo build/package.sh"
fails "check 35: another repo's grandfathered line" "$work/pk-gf" 'packager build/package.sh'
grandfather "packager ed25519 build/other.sh"
fails "check 35: another path's grandfathered line" "$work/pk-gf" 'packager build/package.sh'
grandfather "macos-runner ed25519 build/package.sh"
fails "check 35: another check's grandfathered line" "$work/pk-gf" 'packager build/package.sh'
grandfather

mkrepo7 "$work/pk-tests"
printf '#!/bin/sh\n%s\n' "$PKG" > "$work/pk-tests/tests/fixture.sh"; add "$work/pk-tests"
passes "check 35: tests/ builds throwaway pkgs on purpose" "$work/pk-tests"

pkok "$work/pk-comment" '# pkgbuild --root stage out.pkg'
passes "check 35: a comment is not a call" "$work/pk-comment"

# spec: SKILL.md "Family conventions" check 21 -- stevedore's component and product commands, and
#       build_component_pkg.sh and set_install_floor.sh, also build a pkg; the path is grandfatherable.
stv() {  # $1 = label, $2 = line
  d="$work/stv-$1"; mkrepo7 "$d"; printf '#!/bin/sh\n%s\n' "$2" > "$d/build/pkg.sh"; add "$d"
}
stv component 'stevedore component --root stage out.pkg'
fails "check 21: stevedore component" "$work/stv-component" 'builds a .pkg (build/pkg.sh via stevedore)'
fails "check 21: stevedore component" "$work/stv-component" 'check-artifact-conformance.sh'
stv product '"$SD" product --distribution d.xml out.pkg'
passes "check 21: a product subcommand on a variable is invisible" "$work/stv-product"
stv product2 'stevedore product --distribution d.xml out.pkg'
fails "check 21: stevedore product" "$work/stv-product2" 'via stevedore'
stv bcp 'sh "$SHIPYARD_SCRIPTS/build_component_pkg.sh" --root stage out.pkg'
fails "check 21: build_component_pkg.sh" "$work/stv-bcp" 'builds a .pkg (build/pkg.sh via stevedore)'
stv sif 'sh "$SHIPYARD_SCRIPTS/set_install_floor.sh" out.pkg 10.9'
fails "check 21: set_install_floor.sh" "$work/stv-sif" 'builds a .pkg (build/pkg.sh via stevedore)'
stv other 'stevedore version'
passes "check 21: other stevedore commands build nothing" "$work/stv-other"
stv comment '# stevedore component --root stage out.pkg'
passes "check 21: a comment is not a call" "$work/stv-comment"

mkrepo7 "$work/stv-tests"
printf '#!/bin/sh\nstevedore component --root stage out.pkg\n' > "$work/stv-tests/tests/fixture.sh"; add "$work/stv-tests"
passes "check 21: tests/ is excluded" "$work/stv-tests"

grandfather "artifact-conformance ed25519 build/pkg.sh"
passes "check 21: a grandfathered path counts as no pkg building" "$work/stv-component"
grandfather "artifact-conformance other-repo build/pkg.sh"
fails "check 21: another repo's grandfathered line" "$work/stv-component" 'via stevedore'
grandfather

pkok "$work/stv-full" 'stevedore component --root stage out.pkg'
passes "check 21: a stevedore repo that satisfies 21, 23 and 29 passes" "$work/stv-full"
pkok "$work/stv-old" "$PKG" build/old.sh
printf '#!/bin/sh\nstevedore component --root stage out.pkg\n' > "$work/stv-old/build/new.sh"; add "$work/stv-old"
grandfather "artifact-conformance ed25519 build/new.sh"
fails "check 21: a grandfathered stevedore path does not excuse a direct pkgbuild call" "$work/stv-old" 'packager build/old.sh'
grandfather

# spec: SKILL.md "Family conventions" check 36 -- a job on a macos-* runner needs a macos-runner:<job>
#       deviation or a conventions-grandfathered line.
mac() {  # $1 = label, $2 = the job's body after "  mac:"
  d="$work/mac-$1"; mkrepo7 "$d"
  printf 'name: ci\non: push\njobs:\n  mac:\n%s\n' "$2" > "$d/.github/workflows/ci.yml"; add "$d"
}
mac scalar '    runs-on: macos-14
    steps:
      - run: true'
fails "check 36: macos-14" "$work/mac-scalar" 'macos-runner mac'
mac latest '    runs-on: macos-latest
    steps:
      - run: true'
fails "check 36: macos-latest" "$work/mac-latest" 'macos-runner mac'
mac list '    runs-on: [self-hosted, macos-15]
    steps:
      - run: true'
fails "check 36: a runs-on list" "$work/mac-list" 'macos-runner mac'
mac matrix '    strategy:
      matrix:
        os: [ubuntu-latest, macos-26]
    runs-on: ${{ matrix.os }}
    steps:
      - run: true'
fails "check 36: a matrix" "$work/mac-matrix" 'macos-runner mac'
mac linux '    strategy:
      matrix:
        os: [ubuntu-latest, ubuntu-24.04-arm]
    runs-on: ${{ matrix.os }}
    steps:
      - run: echo macos-14'
passes "check 36: a Linux job" "$work/mac-linux"
mac ubuntu '    runs-on: ubuntu-latest
    steps:
      - run: true'
passes "check 36: ubuntu" "$work/mac-ubuntu"

mac dev '    runs-on: macos-14
    steps:
      - run: true'
printf '\n## Conformance deviations\n\n- macos-runner:mac: the 10.9 guest needs a macOS host, exit when a Linux host runs it\n' >> "$work/mac-dev/INGREDIENTS.md"
add "$work/mac-dev"
passes "check 36: a macos-runner deviation" "$work/mac-dev"

grandfather "macos-runner ed25519 mac"
passes "check 36: a grandfathered job" "$work/mac-scalar"
grandfather "macos-runner ed25519 other"
fails "check 36: another job's grandfathered line" "$work/mac-scalar" 'macos-runner mac'
grandfather "macos-runner other-repo mac"
fails "check 36: another repo's grandfathered line" "$work/mac-scalar" 'macos-runner mac'
grandfather "packager ed25519 mac"
fails "check 36: another check's grandfathered line" "$work/mac-scalar" 'macos-runner mac'
grandfather

# spec: scripts/conventions-grandfathered -- one "<check> <repo> <job|path>" per line, sorted, no
#       duplicates, naming a registered repo; each runner conversion or packager move deletes its
#       lines, so the per-check count may only go down.
GF="$here/../scripts/conventions-grandfathered"
MAX_MACOS_RUNNER=56
MAX_PACKAGER=18
MAX_ARTIFACT_CONFORMANCE=0
[ -f "$GF" ] || { echo "FAIL: scripts/conventions-grandfathered is missing"; exit 1; }
LC_ALL=C sort -c "$GF" 2>/dev/null || { echo "FAIL: scripts/conventions-grandfathered is not sorted"; exit 1; }
[ -z "$(LC_ALL=C sort "$GF" | uniq -d)" ] || { echo "FAIL: scripts/conventions-grandfathered has duplicate lines"; exit 1; }
while read -r c r k extra; do
  [ -n "$k" ] && [ -z "$extra" ] || { echo "FAIL: conventions-grandfathered line is not '<check> <repo> <job|path>': $c $r $k $extra"; exit 1; }
  case "$c" in macos-runner|packager|artifact-conformance) ;; *) echo "FAIL: conventions-grandfathered names an unknown check: $c"; exit 1 ;; esac
  awk -v r="$r" '$3 == r { f = 1 } END { exit !f }' "$here/../scripts/product-names" \
    || { echo "FAIL: conventions-grandfathered names $r, which no product-names line registers"; exit 1; }
done < "$GF"
count() { awk -v c="$1" '$1 == c { n++ } END { print n + 0 }' "$GF"; }
for pair in "macos-runner:$MAX_MACOS_RUNNER" "packager:$MAX_PACKAGER" "artifact-conformance:$MAX_ARTIFACT_CONFORMANCE"; do
  c="${pair%%:*}"; max="${pair#*:}"; n="$(count "$c")"
  [ "$n" -le "$max" ] || { echo "FAIL: conventions-grandfathered has $n $c lines; the ceiling is $max and may only go down"; exit 1; }
done

echo "PASS: check-family-conventions-7"
