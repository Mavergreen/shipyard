#!/usr/bin/env bats
# platform: host-agnostic

setup() {
  CHECKS="$BATS_TEST_DIRNAME/../scripts/required-checks.sh"
  REPO="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/required-checks-test.XXXXXX")" && pwd)"
  mkdir -p "$REPO/.github/workflows"
  git -C "$REPO" init -q
}
teardown() { rm -rf "$REPO"; }

wf() {
  cat > "$REPO/.github/workflows/$1"
  git -C "$REPO" add ".github/workflows/$1"
}

gate() {
  printf '  required:\n    name: required (%s)\n    needs: [build]\n    if: always()\n    runs-on: ubuntu-latest\n    steps:\n      - run: true\n' "$1"
}

@test "map on: with pull_request is gated" {
  { printf 'on:\n  push:\n    branches: [main]\n  pull_request:\njobs:\n  build:\n    runs-on: ubuntu-latest\n'; gate ci; } | wf ci.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "required (ci)" ]
}

@test "scalar on: pull_request is gated" {
  { printf 'on: pull_request\njobs:\n'; gate scalar; } | wf scalar.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "required (scalar)" ]
}

@test "list on: [push, pull_request] is gated" {
  { printf 'on: [push, pull_request]\njobs:\n'; gate listy; } | wf listy.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "required (listy)" ]
}

@test "pull_request only in a comment is not PR-triggered" {
  printf 'on:\n  push:\n  # pull_request:\njobs:\n  build:\n    runs-on: ubuntu-latest\n' | wf pushy.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a conventions caller yields its job key" {
  printf 'on: [push]\njobs:\n  conventions:\n    uses: Mavergreen/shipyard/.github/workflows/family-conventions.yml@v1\n' | wf conv.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "conventions / conventions" ]
}

@test "a conventions caller with a name: uses it" {
  printf 'on: [push]\njobs:\n  conv:\n    name: Family conventions\n    uses: ./.github/workflows/family-conventions.yml\n' | wf conv.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "Family conventions / conventions" ]
}

@test "output is sorted and combines both kinds" {
  printf 'on: [push]\njobs:\n  conventions:\n    uses: ./.github/workflows/family-conventions.yml\n' | wf conv.yml
  { printf 'on: pull_request\njobs:\n'; gate zed; } | wf zed.yml
  { printf 'on: pull_request\njobs:\n'; gate alpha; } | wf alpha.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "conventions / conventions
required (alpha)
required (zed)" ]
}

@test "a PR workflow without a gate fails naming the file" {
  printf 'on: pull_request\njobs:\n  build:\n    runs-on: ubuntu-latest\n' | wf nogate.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nogate.yml"* ]] || false
}

@test "a gate with the wrong name fails naming the file" {
  { printf 'on: pull_request\njobs:\n'; gate other; } | wf wrong.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"wrong.yml"* ]] || false
}

@test "a file that does not parse fails naming the file" {
  printf 'on: [unclosed\n  jobs: {\n' | wf broken.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken.yml"* ]] || false
}

@test "untracked workflows are ignored" {
  { printf 'on: pull_request\njobs:\n'; gate ci; } | wf ci.yml
  printf 'on: pull_request\njobs:\n  build:\n    runs-on: ubuntu-latest\n' > "$REPO/.github/workflows/untracked.yml"
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "required (ci)" ]
}

@test "a directory that is not a git checkout is an error" {
  rm -rf "$REPO/.git"
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 2 ]
}

@test "a caller of shipyard's ingredients-settled adds the ingredients-settled context" {
  printf 'on: [push]\njobs:\n  settled:\n    uses: Mavergreen/shipyard/.github/workflows/ingredients-settled.yml@v1\n' | wf ingredients-settled.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "ingredients-settled" ]
}

@test "ingredients-settled sorts among the other contexts" {
  printf 'on: [push]\njobs:\n  settled:\n    uses: Mavergreen/shipyard/.github/workflows/ingredients-settled.yml@v1\n' | wf ingredients-settled.yml
  printf 'on: [push]\njobs:\n  conventions:\n    uses: Mavergreen/shipyard/.github/workflows/family-conventions.yml@v1\n' | wf conv.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "conventions / conventions
ingredients-settled" ]
}

@test "a commented-out ingredients-settled call yields nothing" {
  printf 'on: [push]\njobs:\n  build:\n    runs-on: ubuntu-latest\n  # settled:\n  #   uses: Mavergreen/shipyard/.github/workflows/ingredients-settled.yml@v1\n' | wf ingredients-settled.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a workflow of that name that does not call shipyard's yields nothing" {
  printf 'on: [push]\njobs:\n  settled:\n    uses: ./.github/workflows/other.yml\n' | wf ingredients-settled.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "both callers and a gated release yield exactly three contexts, with no gate demanded of the settled caller" {
  printf 'on:\n  pull_request:\n  schedule:\n    - cron: "17 * * * *"\njobs:\n  settled:\n    uses: Mavergreen/shipyard/.github/workflows/ingredients-settled.yml@v1\n' | wf ingredients-settled.yml
  printf 'on: [push]\njobs:\n  conventions:\n    uses: Mavergreen/shipyard/.github/workflows/family-conventions.yml@v1\n' | wf conventions.yml
  { printf 'on: pull_request\njobs:\n  build:\n    runs-on: ubuntu-latest\n'; gate release; } | wf release.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "conventions / conventions
ingredients-settled
required (release)" ]
}

@test "a settled caller that also has real PR jobs still needs its gate" {
  printf 'on: pull_request\njobs:\n  settled:\n    uses: Mavergreen/shipyard/.github/workflows/ingredients-settled.yml@v1\n  build:\n    runs-on: ubuntu-latest\n' | wf ingredients-settled.yml
  run sh "$CHECKS" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ingredients-settled.yml"* ]] || false
}
