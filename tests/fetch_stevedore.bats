#!/usr/bin/env bats
# platform: host-agnostic

setup() {
  FETCH="$BATS_TEST_DIRNAME/../scripts/fetch_stevedore.sh"
  PIN="$(sed -n 1p "$BATS_TEST_DIRNAME/../.mavergreen/ingredients/stevedore/VERSION")"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/fetch-stevedore-test.XXXXXX")" && pwd)"
  export STEVEDORE_RELEASES="file://$WORK/rel" SHIPYARD_FETCH_BACKOFF=0
  export XDG_CACHE_HOME="$WORK/xdg" HOME="$WORK/home" STEVEDORE_EUID=1000
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

@test "a product's MAVERGREEN_RELEASES and MAVERGREEN_PKG_CACHE never reach stevedore" {
  linux_release "$PIN"
  mkdir -p "$WORK/product-rel"
  export STEVEDORE_HOST=Linux MAVERGREEN_RELEASES="file://$WORK/product-rel" MAVERGREEN_PKG_CACHE="$WORK/product-cache"
  output="$(sh "$FETCH" 2>/dev/null)"
  [ "$output" = "$WORK/xdg/mavergreen-pkgs/stevedore/$PIN/stevedore" ]
  [ ! -e "$WORK/product-cache" ]
}

@test "without STEVEDORE_RELEASES the source is github, not MAVERGREEN_RELEASES" {
  mkdir -p "$WORK/product-rel"
  unset STEVEDORE_RELEASES
  export STEVEDORE_HOST=Linux MAVERGREEN_RELEASES="file://$WORK/product-rel"
  run sh "$FETCH"
  case "$output" in *"file://$WORK/product-rel"*) false ;; esac
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
  pin="$BATS_TEST_DIRNAME/../.mavergreen/ingredients/stevedore/VERSION"
  sed -n 1p "$pin" | grep -qE '^[0-9]{8}\.[0-9]+$'
  sed -n 2p "$pin" | grep -qF '# renovate: datasource=github-releases depName=Mavergreen/stevedore '
  renovate="$BATS_TEST_DIRNAME/../.github/renovate.json"
  grep -qF '/^\\.mavergreen/ingredients/stevedore/VERSION$/' "$renovate"
}

@test "as root the default cache is root's own home, not the caller's HOME" {
  linux_release "$PIN"
  export STEVEDORE_HOST=Linux STEVEDORE_EUID=0 STEVEDORE_ROOT_HOME="$WORK/roothome"
  unset STEVEDORE_CACHE
  output="$(sh "$FETCH" 2>/dev/null)"
  [ "$output" = "$WORK/roothome/.cache/mavergreen-pkgs/stevedore/$PIN/stevedore" ]
  [ ! -e "$WORK/home" ]
  [ ! -e "$WORK/xdg" ]
}

@test "as root on Darwin the default cache is root's Library/Caches" {
  export STEVEDORE_HOST=Darwin STEVEDORE_EUID=0 STEVEDORE_ROOT_HOME="$WORK/roothome"
  unset STEVEDORE_CACHE
  mkdir -p "$WORK/roothome/Library/Caches/mavergreen-pkgs/stevedore/$PIN"
  fake_stevedore "$WORK/roothome/Library/Caches/mavergreen-pkgs/stevedore/$PIN/stevedore" "$PIN"
  output="$(sh "$FETCH" 2>/dev/null)"
  [ "$output" = "$WORK/roothome/Library/Caches/mavergreen-pkgs/stevedore/$PIN/stevedore" ]
}

@test "an explicit STEVEDORE_CACHE still wins as root" {
  linux_release "$PIN"
  export STEVEDORE_HOST=Linux STEVEDORE_EUID=0 STEVEDORE_CACHE="$WORK/chosen" STEVEDORE_ROOT_HOME="$WORK/roothome"
  output="$(sh "$FETCH" 2>/dev/null)"
  [ "$output" = "$WORK/chosen/$PIN/stevedore" ]
}
