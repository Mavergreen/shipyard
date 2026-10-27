#!/usr/bin/env bats
# platform: host-agnostic

setup() {
  FETCH="$BATS_TEST_DIRNAME/../scripts/fetch_stevedore.sh"
  PIN="$(sed -n 's/^STEVEDORE_VERSION=//p' "$BATS_TEST_DIRNAME/../scripts/stevedore.pin")"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/fetch-stevedore-test.XXXXXX")" && pwd)"
  export MAVERGREEN_RELEASES="file://$WORK/rel" SHIPYARD_FETCH_BACKOFF=0
  export MAVERGREEN_PKG_CACHE="$WORK/cache" XDG_CACHE_HOME="$WORK/xdg" HOME="$WORK/home"
  unset STEVEDORE
  REL="$WORK/rel/Mavergreen/stevedore/releases/download/$PIN"
  mkdir -p "$REL"
}
teardown() { rm -rf "$WORK"; }

fake_stevedore() {
  printf '#!/bin/sh\n[ "${1:-}" = --version ] && echo "stevedore %s"\n' "$2" > "$1"
  chmod +x "$1"
}

linux_release() {
  mkdir -p "$WORK/stage/opt/mavergreen/stevedore/bin"
  fake_stevedore "$WORK/stage/opt/mavergreen/stevedore/bin/stevedore" "$1"
  tar -czf "$REL/stevedore-$PIN-linux-x86_64.tar.gz" -C "$WORK/stage" opt
  ( cd "$REL" && shasum -a 256 "stevedore-$PIN-linux-x86_64.tar.gz" > SHA256SUMS )
}

@test "Linux tarball fetch verifies SHA256SUMS" {
  linux_release "$PIN"
  export STEVEDORE_HOST=Linux
  output="$(sh "$FETCH" 2>/dev/null)"
  [ "$output" = "$WORK/xdg/mavergreen-pkgs/stevedore/$PIN/stevedore" ]
  [ "$("$output" --version)" = "stevedore $PIN" ]
}

@test "sum mismatch refuses" {
  linux_release "$PIN"
  printf 'tampered' > "$REL/stevedore-$PIN-linux-x86_64.tar.gz"
  export STEVEDORE_HOST=Linux
  run sh "$FETCH"
  [ "$status" -eq 1 ]
  [ ! -e "$WORK/xdg/mavergreen-pkgs/stevedore/$PIN/stevedore" ]
}

@test "STEVEDORE override must report the pinned version" {
  fake_stevedore "$WORK/mine" "19990101.1"
  STEVEDORE="$WORK/mine" run sh "$FETCH"
  [ "$status" -eq 1 ]
  fake_stevedore "$WORK/mine" "$PIN"
  STEVEDORE="$WORK/mine" run sh "$FETCH"
  [ "$status" -eq 0 ]
  [ "$output" = "$WORK/mine" ]
}

@test "stale cache refetches" {
  linux_release "$PIN"
  export STEVEDORE_HOST=Linux
  mkdir -p "$WORK/xdg/mavergreen-pkgs/stevedore/$PIN"
  fake_stevedore "$WORK/xdg/mavergreen-pkgs/stevedore/$PIN/stevedore" "19990101.1"
  output="$(sh "$FETCH" 2>/dev/null)"
  [ "$("$output" --version)" = "stevedore $PIN" ]
}

@test "a good cache is used without the network" {
  linux_release "$PIN"
  export STEVEDORE_HOST=Linux
  sh "$FETCH" > /dev/null
  rm -rf "$WORK/rel"
  run sh "$FETCH"
  [ "$status" -eq 0 ]
}

@test "pin is a version, never latest" {
  pin="$BATS_TEST_DIRNAME/../scripts/stevedore.pin"
  [ "$(grep -c '^STEVEDORE_VERSION=' "$pin")" -eq 1 ]
  grep -qE '^STEVEDORE_VERSION=[0-9]{8}\.[0-9]+$' "$pin"
  renovate="$BATS_TEST_DIRNAME/../.github/renovate.json"
  grep -qF '/^scripts/stevedore\\.pin$/' "$renovate"
  grep -qF '"STEVEDORE_VERSION=(?<currentValue>' "$renovate"
}
