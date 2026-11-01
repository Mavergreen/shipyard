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
conf='      - run: SHIPYARD_CHECK_VERSION="$FULL" shipyard-check --dist dist'
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
fails "check 35: a direct pkgbuild call" "$work/pk-plain" 'packager: build/package.sh'
pkok "$work/pk-product" 'productbuild --package w.pkg out.pkg'
fails "check 35: a direct productbuild call" "$work/pk-product" 'packager: build/package.sh'

pkok "$work/pk-dev" "$PKG"
printf '\n## Conformance deviations\n\n- packager:build/package.sh: the oracle compares against the system tool, exit when stevedore is the oracle\n' >> "$work/pk-dev/INGREDIENTS.md"
add "$work/pk-dev"
passes "check 35: a packager deviation" "$work/pk-dev"

pkok "$work/pk-gf" "$PKG"
grandfather "packager ed25519 build/package.sh"
passes "check 35: a grandfathered path" "$work/pk-gf"
grandfather "packager other-repo build/package.sh"
fails "check 35: another repo's grandfathered line" "$work/pk-gf" 'packager: build/package.sh'
grandfather "packager ed25519 build/other.sh"
fails "check 35: another path's grandfathered line" "$work/pk-gf" 'packager: build/package.sh'
grandfather "macos-runner ed25519 build/package.sh"
fails "check 35: another check's grandfathered line" "$work/pk-gf" 'packager: build/package.sh'
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
fails "check 21: stevedore component" "$work/stv-component" 'shipyard-check --dist'
stv product '"$SD" product --distribution d.xml out.pkg'
passes "check 21: a product subcommand on a variable is invisible" "$work/stv-product"
stv product2 'stevedore product --distribution d.xml out.pkg'
fails "check 21: stevedore product" "$work/stv-product2" 'via stevedore'
stv bcp 'sh "$SHIPYARD_SCRIPTS/build_component_pkg.sh" --root stage out.pkg'
fails "check 21: build_component_pkg.sh" "$work/stv-bcp" 'builds a .pkg (build/pkg.sh via stevedore)'
stv sif 'sh "$SHIPYARD_SCRIPTS/set_install_floor.sh" out.pkg 10.9'
fails "check 21: set_install_floor.sh" "$work/stv-sif" 'builds a .pkg (build/pkg.sh via stevedore)'
stv echoed 'echo "sh $SHIPYARD_SCRIPTS/build_component_pkg.sh"'
passes "check 21: an echoed mention is not an invocation" "$work/stv-echoed"
stv bare '"$SHIPYARD_SCRIPTS/set_install_floor.sh" out.pkg 10.9'
fails "check 21: a bare path at command position" "$work/stv-bare" 'via stevedore'
stv other 'stevedore version'
passes "check 21: other stevedore commands build nothing" "$work/stv-other"
stv comment '# stevedore component --root stage out.pkg'
passes "check 21: a comment is not a call" "$work/stv-comment"

mkrepo7 "$work/stv-tests"
printf '#!/bin/sh\nstevedore component --root stage out.pkg\n' > "$work/stv-tests/tests/fixture.sh"; add "$work/stv-tests"
passes "check 21: tests/ is excluded" "$work/stv-tests"

grandfather "artifact-checks-wired ed25519 build/pkg.sh"
passes "check 21: a grandfathered path counts as no pkg building" "$work/stv-component"
grandfather "artifact-checks-wired other-repo build/pkg.sh"
fails "check 21: another repo's grandfathered line" "$work/stv-component" 'via stevedore'
grandfather

pkok "$work/stv-full" 'stevedore component --root stage out.pkg'
passes "check 21: a stevedore repo that satisfies 21, 23 and 29 passes" "$work/stv-full"
pkok "$work/stv-old" "$PKG" build/old.sh
printf '#!/bin/sh\nstevedore component --root stage out.pkg\n' > "$work/stv-old/build/new.sh"; add "$work/stv-old"
grandfather "artifact-checks-wired ed25519 build/new.sh"
fails "check 21: a grandfathered stevedore path does not excuse a direct pkgbuild call" "$work/stv-old" 'packager: build/old.sh'
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
fails "check 36: macos-14" "$work/mac-scalar" 'macos-runner: ci.yml:mac'
mac latest '    runs-on: macos-latest
    steps:
      - run: true'
fails "check 36: macos-latest" "$work/mac-latest" 'macos-runner: ci.yml:mac'
mac list '    runs-on: [self-hosted, macos-15]
    steps:
      - run: true'
fails "check 36: a runs-on list" "$work/mac-list" 'macos-runner: ci.yml:mac'
mac matrix '    strategy:
      matrix:
        os: [ubuntu-latest, macos-26]
    runs-on: ${{ matrix.os }}
    steps:
      - run: true'
fails "check 36: a matrix" "$work/mac-matrix" 'macos-runner: ci.yml:mac'
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
printf '\n## Conformance deviations\n\n- macos-runner:ci.yml:mac: the 10.9 guest needs a macOS host, exit when a Linux host runs it\n' >> "$work/mac-dev/INGREDIENTS.md"
add "$work/mac-dev"
passes "check 36: a macos-runner deviation" "$work/mac-dev"

grandfather "macos-runner ed25519 ci.yml:mac"
passes "check 36: a grandfathered job" "$work/mac-scalar"
grandfather "macos-runner ed25519 ci.yml:other"
fails "check 36: another job's grandfathered line" "$work/mac-scalar" 'macos-runner: ci.yml:mac'
grandfather "macos-runner other-repo ci.yml:mac"
fails "check 36: another repo's grandfathered line" "$work/mac-scalar" 'macos-runner: ci.yml:mac'
grandfather "packager ed25519 ci.yml:mac"
fails "check 36: another check's grandfathered line" "$work/mac-scalar" 'macos-runner: ci.yml:mac'
grandfather

mac2() {  # a second workflow with a job of the same id
  printf 'name: other\non: push\njobs:\n  mac:\n    runs-on: macos-14\n    steps:\n      - run: true\n' > "$work/mac-scalar/.github/workflows/other.yml"; add "$work/mac-scalar"
}
mac2
grandfather "macos-runner ed25519 ci.yml:mac"
fails "check 36: the same job id in another workflow" "$work/mac-scalar" 'macos-runner: other.yml:mac'
grandfather "macos-runner ed25519 ci.yml:mac" "macos-runner ed25519 other.yml:mac"
passes "check 36: both workflows' jobs grandfathered" "$work/mac-scalar"
grandfather
rm "$work/mac-scalar/.github/workflows/other.yml"; add "$work/mac-scalar"

refused() {  # $1 = dir, $2 = the deviation line, $3 = the phrase the refusal must carry
  printf '\n## Conformance deviations\n\n%s\n' "$2" >> "$1/INGREDIENTS.md"; add "$1"
  out="$(cd "$1" && sh "$sc/check-deviations.sh" 2>&1)" && { echo "FAIL: wildcard deviation [$2] must be refused"; exit 1; }
  printf '%s\n' "$out" | grep -q -- "$3" || { echo "FAIL: [$2] should be refused with '$3': $out"; exit 1; }
}
for dev in '- macos-runner: every job' '- macos-runner:*: every job' '- macos-runner:ci.yml:*: every job' '- macos-runner:*:mac: every file'; do
  rm -rf "$work/mac-wild"; cp -R "$work/mac-scalar" "$work/mac-wild"; printf '# Build ingredients\n' > "$work/mac-wild/INGREDIENTS.md"
  refused "$work/mac-wild" "$dev" 'deviations.sh'
done
for dev in '- packager: every path' '- packager:*: every path' '- packager:build/*: every path'; do
  rm -rf "$work/pk-wild"; cp -R "$work/pk-plain" "$work/pk-wild"; printf '# Build ingredients\n' > "$work/pk-wild/INGREDIENTS.md"
  refused "$work/pk-wild" "$dev" 'deviations.sh'
done

# spec: SKILL.md "Family conventions" check 36 -- a run without GITHUB_REPOSITORY (a developer's
#       shell through $SHIPYARD_SCRIPTS) takes the repo's name from origin, https or ssh.
grandfather "macos-runner ed25519 ci.yml:mac"
for url in https://github.com/Mavergreen/ed25519.git https://github.com/Mavergreen/ed25519 git@github.com:Mavergreen/ed25519.git ssh://git@github.com/Mavergreen/ed25519.git; do
  (cd "$work/mac-scalar" && git config remote.origin.url "$url")
  (cd "$work/mac-scalar" && sh "$S2" >/dev/null 2>&1) || { echo "FAIL: origin $url should name the repo: $(cd "$work/mac-scalar" && sh "$S2" 2>&1)"; exit 1; }
done
(cd "$work/mac-scalar" && git config remote.origin.url https://github.com/Mavergreen/elsewhere.git && ! sh "$S2" >/dev/null 2>&1) \
  || { echo "FAIL: another origin must not match the grandfathered line"; exit 1; }
grandfather

# spec: SKILL.md "Family conventions" check 37 -- release.yml has a job named modern-smoke, on a
#       macos-* runner, that publish needs, exactly when INGREDIENTS.md declares an arm64:<glob>
#       deviation; a repo grandfathered as modern-smoke skips the check.
ms() {  # $1 = label, $2 = decl|nodecl, $3 = runs-on (empty: no job), $4 = needed|unneeded
  d="$work/ms-$1"; mkrepo7 "$d"
  { printf '\n## Conformance deviations\n\n'
    [ "$2" = decl ] && printf -- '- arm64:usr/local/mavergreen/w/bin/*: developers on Apple Silicon run w to build Mavericks artifacts\n'
    printf -- '- macos-runner:release.yml:modern-smoke: the arm64 slice runs only on Apple Silicon, exit when a Linux host can run it\n'
  } >> "$d/INGREDIENTS.md"
  if [ -n "$3" ]; then
    printf '  modern-smoke:\n    runs-on: %s\n    steps:\n      - run: true\n' "$3" >> "$d/.github/workflows/release.yml"
    if [ "$4" = needed ]; then
      sed 's/^    needs: \[vm-test\]$/    needs: [vm-test, modern-smoke]/' "$d/.github/workflows/release.yml" > "$d/r.yml"
      mv "$d/r.yml" "$d/.github/workflows/release.yml"
    fi
  fi
  add "$d"
}
grandfather
ms none nodecl '' ''
passes "check 37: no arm64 declaration and no modern-smoke job" "$work/ms-none"
ms full decl macos-26 needed
passes "check 37: a declaration and a modern-smoke job publish needs" "$work/ms-full"
ms list decl '[self-hosted, macos-15]' needed
passes "check 37: a runs-on list naming macos-*" "$work/ms-list"
ms nojob decl '' ''
fails "check 37: a declaration with no modern-smoke job" "$work/ms-nojob" 'modern-smoke: INGREDIENTS.md declares an arm64 slice, but release.yml has no modern-smoke job'
ms linux decl ubuntu-latest needed
fails "check 37: a modern-smoke job off macOS" "$work/ms-linux" 'modern-smoke: the modern-smoke job does not run on a macos-\* runner'
ms unneeded decl macos-26 unneeded
fails "check 37: a modern-smoke job publish does not need" "$work/ms-unneeded" 'modern-smoke: publish does not need the modern-smoke job'
ms nodecl nodecl macos-26 needed
fails "check 37: a modern-smoke job with no declaration" "$work/ms-nodecl" 'modern-smoke: release.yml has a modern-smoke job, but INGREDIENTS.md declares no arm64 slice'
out="$(gate "$work/ms-nojob")" || :
printf '%s\n' "$out" | grep -q 'declares no arm64 slice' && { echo "FAIL: check 37: each direction has its own message: $out"; exit 1; }
out="$(gate "$work/ms-nodecl")" || :
printf '%s\n' "$out" | grep -q 'has no modern-smoke job' && { echo "FAIL: check 37: each direction has its own message: $out"; exit 1; }

grandfather "modern-smoke ed25519 release.yml:modern-smoke"
passes "check 37: a grandfathered declaration with no job" "$work/ms-nojob"
passes "check 37: a grandfathered job with no declaration" "$work/ms-nodecl"
grandfather "modern-smoke other-repo release.yml:modern-smoke"
fails "check 37: another repo's grandfathered line" "$work/ms-nojob" 'modern-smoke: '
grandfather "macos-runner ed25519 release.yml:modern-smoke"
fails "check 37: another check's grandfathered line" "$work/ms-nojob" 'modern-smoke: '
grandfather

# spec: scripts/conventions-grandfathered -- one "<check> <repo> <job|path>" per line, sorted, no
#       duplicates, naming a repo of the org; each runner conversion or packager move deletes its
#       lines, so the per-check count may only go down.
GF="$here/../scripts/conventions-grandfathered"
MAX_MACOS_RUNNER=57
MAX_PACKAGER=17
MAX_ARTIFACT_CHECKS_WIRED=0
MAX_MODERN_SMOKE=13
MAX_CXXABI=2
[ -f "$GF" ] || { echo "FAIL: scripts/conventions-grandfathered is missing"; exit 1; }
LC_ALL=C sort -c "$GF" 2>/dev/null || { echo "FAIL: scripts/conventions-grandfathered is not sorted"; exit 1; }
[ -z "$(LC_ALL=C sort "$GF" | uniq -d)" ] || { echo "FAIL: scripts/conventions-grandfathered has duplicate lines"; exit 1; }
while read -r c r k extra; do
  [ -n "$k" ] && [ -z "$extra" ] || { echo "FAIL: conventions-grandfathered line is not '<check> <repo> <job|path>': $c $r $k $extra"; exit 1; }
  case "$c" in macos-runner|packager|artifact-checks-wired|modern-smoke|cxxabi) ;; *) echo "FAIL: conventions-grandfathered names an unknown check: $c"; exit 1 ;; esac
  case "$c:$k" in
    macos-runner:*.yml:*|macos-runner:*.yaml:*|packager:*|artifact-checks-wired:*|modern-smoke:release.yml:modern-smoke|cxxabi:usr/local/mavergreen/*|cxxabi:Applications/*|cxxabi:Library/*) ;;
    *) echo "FAIL: conventions-grandfathered key is not <workflow file>:<job> (macos-runner), release.yml:modern-smoke (modern-smoke), an installed path (cxxabi) or a path: $c $r $k"; exit 1 ;;
  esac
done < "$GF"
count() { awk -v c="$1" '$1 == c { n++ } END { print n + 0 }' "$GF"; }
for pair in "macos-runner:$MAX_MACOS_RUNNER" "packager:$MAX_PACKAGER" "artifact-checks-wired:$MAX_ARTIFACT_CHECKS_WIRED" "modern-smoke:$MAX_MODERN_SMOKE" "cxxabi:$MAX_CXXABI"; do
  c="${pair%%:*}"; max="${pair#*:}"; n="$(count "$c")"
  [ "$n" -le "$max" ] || { echo "FAIL: conventions-grandfathered has $n $c lines; the ceiling is $max and may only go down"; exit 1; }
done

echo "PASS: check-family-conventions-7"
