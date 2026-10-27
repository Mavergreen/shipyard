#!/usr/bin/env bats
# platform: macOS-only -- the Darwin branch of fetch_stevedore.sh expands the release pkg with pkgutil, and pkgbuild makes it

setup() {
  FETCH="$BATS_TEST_DIRNAME/../scripts/fetch_stevedore.sh"
  PIN="$(sed -n 's/^STEVEDORE_VERSION=//p' "$BATS_TEST_DIRNAME/../scripts/stevedore.pin")"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/fetch-stevedore-test.XXXXXX")" && pwd)"
  export STEVEDORE_RELEASES="file://$WORK/rel" SHIPYARD_FETCH_BACKOFF=0
  export STEVEDORE_CACHE="$WORK/cache" XDG_CACHE_HOME="$WORK/xdg" HOME="$WORK/home"
  unset STEVEDORE
  REL="$WORK/rel/Mavergreen/stevedore/releases/download/$PIN"
  mkdir -p "$REL"
}
teardown() { rm -rf "$WORK"; }

fake_stevedore() {
  printf '#!/bin/sh\n[ "${1:-}" = --version ] && echo "stevedore %s"\n' "$2" > "$1"
  chmod +x "$1"
}

@test "Darwin reads the release pkg with pkgutil --expand and cpio" {
  mkdir -p "$WORK/root/usr/local/mavergreen/stevedore/bin"
  fake_stevedore "$WORK/root/usr/local/mavergreen/stevedore/bin/stevedore" "$PIN"
  pkgbuild --quiet --root "$WORK/root" --identifier dev.mavergreen.stevedore --version 1 "$REL/stevedore-$PIN.pkg"
  ( cd "$REL" && shasum -a 256 "stevedore-$PIN.pkg" > SHA256SUMS )
  export STEVEDORE_HOST=Darwin
  output="$(sh "$FETCH" 2>/dev/null)"
  [ "$output" = "$WORK/cache/$PIN/stevedore" ]
  [ "$("$output" --version)" = "stevedore $PIN" ]
}
