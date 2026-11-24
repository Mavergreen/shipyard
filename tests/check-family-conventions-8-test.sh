#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/conventions_fixture.sh"
python3 -c 'import yaml' 2>/dev/null || { echo "SKIP: needs a python3 with PyYAML"; exit 77; }

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
lacks() {  # $1 = label, $2 = dir, $3 = phrase the output must not carry
  out="$(gate "$2")" || :
  printf '%s\n' "$out" | grep -q -- "$3" && { echo "FAIL: $1 must not report '$3': $out"; exit 1; }
  :
}
add() { (cd "$1" && git add -A) >/dev/null 2>&1; }
mkrepo8() { mkrepo "$@"; printf '# Build ingredients\n' > "$1/INGREDIENTS.md"; }
declare_mac() {  # $1 = dir, $2.. = <workflow file>:<job> keys
  d="$1"; shift
  { printf '\n## Conformance deviations\n\n'
    for k in "$@"; do printf -- '- macos-runner:%s: the fixture needs macOS, exit when it does not\n' "$k"; done
  } >> "$d/INGREDIENTS.md"
}

# spec: SKILL.md "Family conventions" check 38 -- every job on a macos-* or xcode-* runner has, through
#       needs:, at least one job on an ubuntu-* runner (or a call to a shipyard reusable workflow, or to
#       a local one whose every job runs on ubuntu-*), so a macOS job never starts to fail on what Linux
#       could have caught.
wf() {  # $1 = label, $2 = the jobs of ci.yml, $3.. = macos-runner keys to declare
  d="$work/lg-$1"; l="$2"; mkrepo8 "$d"; shift 2
  printf 'name: ci\non: push\njobs:\n%s\n' "$l" > "$d/.github/workflows/ci.yml"
  [ $# -eq 0 ] || declare_mac "$d" "$@"
  add "$d"
}
LINT='  lint:
    runs-on: ubuntu-latest
    steps:
      - run: sh "$SHIPYARD_SCRIPTS/check-ingredient-pins.sh"'
MAC='  mac:
    runs-on: macos-26
    steps:
      - run: true'

wf alone "$MAC" ci.yml:mac
fails "check 38: a macOS job that needs nothing" "$work/lg-alone" 'linux-gate ci.yml:mac'
fails "check 38: the message says what to add" "$work/lg-alone" "add needs: on a Linux gate job"

wf direct "$LINT
$MAC
    needs: [lint]" ci.yml:mac
passes "check 38: a macOS job that needs a Linux job" "$work/lg-direct"

wf scalar "$LINT
$MAC
    needs: lint" ci.yml:mac
passes "check 38: needs: as a single name" "$work/lg-scalar"

wf chain "$LINT
  mid:
    needs: [lint]
    runs-on: macos-15
    steps:
      - run: true
$MAC
    needs: [mid]" ci.yml:mid ci.yml:mac
passes "check 38: a Linux job reached through another macOS job" "$work/lg-chain"

wf macmac "  mid:
    runs-on: macos-15
    steps:
      - run: true
$MAC
    needs: [mid]" ci.yml:mid ci.yml:mac
fails "check 38: a macOS job that needs only macOS jobs" "$work/lg-macmac" 'linux-gate ci.yml:mac'
fails "check 38: its macOS ancestor is reported too" "$work/lg-macmac" 'linux-gate ci.yml:mid'

wf selfhosted "  other:
    runs-on: self-hosted
    steps:
      - run: true
$MAC
    needs: [other]" ci.yml:mac
fails "check 38: a self-hosted job is not a Linux gate" "$work/lg-selfhosted" 'linux-gate ci.yml:mac'

wf xcode "  mac:
    runs-on: xcode-16
    steps:
      - run: true"
fails "check 38: an xcode-* runner is a macOS runner" "$work/lg-xcode" 'linux-gate ci.yml:mac'

wf matrix "  lint:
    strategy:
      matrix:
        os: [ubuntu-latest, ubuntu-24.04-arm]
    runs-on: \${{ matrix.os }}
    steps:
      - run: true
  mac:
    needs: [lint]
    strategy:
      matrix:
        os: [ubuntu-latest, macos-26]
    runs-on: \${{ matrix.os }}
    steps:
      - run: true" ci.yml:mac
passes "check 38: a matrix of ubuntu runners is a Linux gate" "$work/lg-matrix"

wf mixed "  lint:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-26]
    runs-on: \${{ matrix.os }}
    steps:
      - run: true
  mac:
    needs: [lint]
    runs-on: macos-26
    steps:
      - run: true" ci.yml:lint ci.yml:mac
fails "check 38: a matrix that also runs macOS is not a Linux gate" "$work/lg-mixed" 'linux-gate ci.yml:mac'

wf conv "  conventions:
    uses: Mavergreen/shipyard/.github/workflows/family-conventions.yml@v1
$MAC
    needs: [conventions]" ci.yml:mac
passes "check 38: a call to shipyard's family-conventions.yml is a Linux gate" "$work/lg-conv"

wf remote "  elsewhere:
    uses: Someone/else/.github/workflows/x.yml@v1
$MAC
    needs: [elsewhere]" ci.yml:mac
fails "check 38: a call to another org's reusable workflow is not a Linux gate" "$work/lg-remote" 'linux-gate ci.yml:mac'

wf local "  gate:
    uses: ./.github/workflows/gate.yml
$MAC
    needs: [gate]" ci.yml:mac
printf 'name: gate\non: workflow_call\njobs:\n  notes:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: true\n' > "$work/lg-local/.github/workflows/gate.yml"
add "$work/lg-local"
passes "check 38: a call to a local workflow that runs only on ubuntu is a Linux gate" "$work/lg-local"

# spec: SKILL.md "Family conventions" check 38 -- a reusable workflow's jobs are gated by their caller,
#       so a workflow_call-only file is skipped and the job calling it is held to the rule instead.
wf reusable "$LINT
  smoke:
    uses: ./.github/workflows/smoke.yml" smoke.yml:run
printf 'name: smoke\non:\n  workflow_call:\njobs:\n  run:\n    runs-on: macos-26\n    steps:\n      - run: true\n' > "$work/lg-reusable/.github/workflows/smoke.yml"
add "$work/lg-reusable"
fails "check 38: the caller of a local macOS workflow needs a Linux gate" "$work/lg-reusable" 'linux-gate ci.yml:smoke'
lacks "check 38: the reusable workflow's own job is its caller's to gate" "$work/lg-reusable" 'linux-gate smoke.yml:run'
awk '/^    uses: \.\/\.github\/workflows\/smoke\.yml$/ { print "    needs: [lint]" } { print }' \
  "$work/lg-reusable/.github/workflows/ci.yml" > "$work/lg-reusable/c.yml"
mv "$work/lg-reusable/c.yml" "$work/lg-reusable/.github/workflows/ci.yml"; add "$work/lg-reusable"
passes "check 38: a gated caller of a local macOS workflow" "$work/lg-reusable"

wf macgate "  gate:
    uses: ./.github/workflows/gate.yml
$MAC
    needs: [gate]" ci.yml:mac gate.yml:notes
printf 'name: gate\non: workflow_call\njobs:\n  notes:\n    runs-on: macos-26\n    steps:\n      - run: true\n' > "$work/lg-macgate/.github/workflows/gate.yml"
add "$work/lg-macgate"
fails "check 38: a call to a local workflow that runs on macOS is not a Linux gate" "$work/lg-macgate" 'linux-gate ci.yml:mac'

wf linux "$LINT"
passes "check 38: a repo with no macOS job" "$work/lg-linux"

grandfather "linux-gate ed25519 ci.yml:mac"
passes "check 38: a grandfathered job" "$work/lg-alone"
grandfather "linux-gate ed25519 ci.yml:other"
fails "check 38: another job's grandfathered line" "$work/lg-alone" 'linux-gate ci.yml:mac'
grandfather "linux-gate other-repo ci.yml:mac"
fails "check 38: another repo's grandfathered line" "$work/lg-alone" 'linux-gate ci.yml:mac'
grandfather "macos-runner ed25519 ci.yml:mac"
fails "check 38: another check's grandfathered line" "$work/lg-alone" 'linux-gate ci.yml:mac'
grandfather

# spec: SKILL.md "Family conventions" check 39 -- modern-smoke runs only in a run that will publish:
#       its if: carries every condition of the publish job's if: (status functions aside), at top
#       level, so a push, a PR or a branch run skips it.
DECIDE="needs.vm-test.outputs.publish == 'yes'"
sm() {  # $1 = label, $2 = modern-smoke's if: (empty: none), $3 = publish's if: (empty: none), $4 = reusable: publish calls publish-release.yml as job ship
  d="$work/sm-$1"; mkrepo8 "$d"
  printf '\n## Conformance deviations\n\n- arm64:usr/local/mavergreen/w/bin/*: developers on Apple Silicon run w to build Mavericks artifacts\n- macos-runner:release.yml:modern-smoke: the arm64 slice runs only on Apple Silicon, exit when a Linux host can run it\n' >> "$d/INGREDIENTS.md"
  awk -v pif="$3" -v how="${4:-}" '
    $0 == "  publish:" { skip = 4
      if (how == "reusable") { print "  ship:"; print "    needs: [vm-test, modern-smoke]"; if (pif != "") print "    if: " pif
                               print "    uses: Mavergreen/shipyard/.github/workflows/publish-release.yml@v1" }
      else { print; print "    needs: [vm-test, modern-smoke]"; if (pif != "") print "    if: " pif
             print "    runs-on: ubuntu-latest"; print "    steps:"; print "      - run: echo published" }
      next }
    skip > 0 { skip--; next }
    { print }' "$d/.github/workflows/release.yml" > "$d/r.yml"
  mv "$d/r.yml" "$d/.github/workflows/release.yml"
  { printf '  modern-smoke:\n    needs: [vm-test]\n'
    [ -z "$2" ] || printf '    if: %s\n' "$2"
    printf '    runs-on: macos-26\n    steps:\n      - run: true\n'
  } >> "$d/.github/workflows/release.yml"
  add "$d"
}
sm same "$DECIDE" "$DECIDE"
passes "check 39: modern-smoke gated on publish's own condition" "$work/sm-same"
sm none '' "$DECIDE"
fails "check 39: an ungated modern-smoke" "$work/sm-none" 'smoke-gate release.yml:modern-smoke'
fails "check 39: the message names publish's condition" "$work/sm-none" "$DECIDE"
sm wrapped "\${{ $DECIDE }}" "$DECIDE"
passes "check 39: the \${{ }} spelling is the same condition" "$work/sm-wrapped"
sm status "success() && ($DECIDE)" "always() && $DECIDE"
passes "check 39: status functions on either side do not count" "$work/sm-status"
sm other "github.event_name == 'workflow_dispatch'" "$DECIDE"
fails "check 39: a condition of its own" "$work/sm-other" 'smoke-gate release.yml:modern-smoke'
sm wider "$DECIDE || github.event_name == 'push'" "$DECIDE"
fails "check 39: a disjunction that also runs on a push" "$work/sm-wider" 'smoke-gate release.yml:modern-smoke'
sm narrower "$DECIDE && github.ref == 'refs/heads/main'" "$DECIDE"
passes "check 39: a narrower condition still runs only when publishing" "$work/sm-narrower"
sm partial "$DECIDE" "$DECIDE && github.repository_owner == 'Mavergreen'"
fails "check 39: every conjunct of publish's condition" "$work/sm-partial" 'smoke-gate release.yml:modern-smoke'
sm nopubif "$DECIDE" ''
fails "check 39: a publish job with no if: gives modern-smoke nothing to share" "$work/sm-nopubif" 'smoke-gate release.yml:modern-smoke: the publish job (publish) has no if:'
sm reusable '' "$DECIDE" reusable
command grep -q 'publish-release.yml' "$work/sm-reusable/.github/workflows/release.yml" || { echo "FAIL: the fixture did not call publish-release.yml"; exit 1; }
fails "check 39: the job calling publish-release.yml is the publish job" "$work/sm-reusable" 'publish job (ship)'
sm reusableok "$DECIDE" "$DECIDE" reusable
passes "check 39: gated on the condition of the job calling publish-release.yml" "$work/sm-reusableok"

mkrepo8 "$work/sm-nojob"
passes "check 39: no modern-smoke job" "$work/sm-nojob"

grandfather "smoke-gate ed25519 release.yml:modern-smoke"
passes "check 39: a grandfathered modern-smoke" "$work/sm-none"
grandfather "smoke-gate other-repo release.yml:modern-smoke"
fails "check 39: another repo's grandfathered line" "$work/sm-none" 'smoke-gate release.yml:modern-smoke'
grandfather "modern-smoke ed25519 release.yml:modern-smoke"
fails "check 39: check 37's grandfathered line does not excuse it" "$work/sm-none" 'smoke-gate release.yml:modern-smoke'
grandfather

echo "PASS: check-family-conventions-8"
