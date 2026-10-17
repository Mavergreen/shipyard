#!/usr/bin/env bats
# platform: host-agnostic

setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/fetch-release-pkg.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/fetch-release-pkg-test.XXXXXX")" && pwd)"
  export MAVERGREEN_RELEASES="file://$WORK/rel" SHIPYARD_FETCH_BACKOFF=0
  REL="$WORK/rel/Mavergreen/shipyard/releases/download/v1.0.9"
  mkdir -p "$REL"
  printf 'the pkg' > "$REL/mavericks-shipyard-1.0.9.pkg"
  ( cd "$REL" && shasum -a 256 mavericks-shipyard-1.0.9.pkg > SHA256SUMS )
}
teardown() { rm -rf "$WORK"; }

@test "fetches the listed asset, verified; stdout is its path only" {
  out="$(sh "$HELPER" shipyard v1.0.9 mavericks-shipyard-1.0.9.pkg "$WORK/out" 2>/dev/null)"
  [ "$out" = "$WORK/out/mavericks-shipyard-1.0.9.pkg" ]
  [ "$(cat "$out")" = "the pkg" ]
}

@test "an asset whose bytes don't match SHA256SUMS fails and leaves nothing" {
  printf 'tampered' > "$REL/mavericks-shipyard-1.0.9.pkg"
  run sh "$HELPER" shipyard v1.0.9 mavericks-shipyard-1.0.9.pkg "$WORK/out"
  [ "$status" -eq 1 ]
  [ ! -e "$WORK/out/mavericks-shipyard-1.0.9.pkg" ]
}

@test "an asset SHA256SUMS doesn't list fails, naming it" {
  run sh "$HELPER" shipyard v1.0.9 other.pkg "$WORK/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"other.pkg is not listed"* ]] || false
}

@test "a release with no SHA256SUMS fails" {
  rm "$REL/SHA256SUMS"
  run sh "$HELPER" shipyard v1.0.9 mavericks-shipyard-1.0.9.pkg "$WORK/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not fetch"*"SHA256SUMS"* ]] || false
}

@test "a usage error exits 2" {
  run sh "$HELPER" shipyard v1.0.9 ../x "$WORK/out"
  [ "$status" -eq 2 ]
}
