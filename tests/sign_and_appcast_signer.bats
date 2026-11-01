#!/usr/bin/env bats
# platform: host-agnostic -- ED25519_HOST picks the branch, and stevedore builds and reads the fixture pkg

SIG=c3R1YnNpZ25hdHVyZWZvcnRlc3Rpbmdvbmx5QUFBQUFBQUFBQUFBQUFBQUFBQUFBQT09

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/sign-signer-test.XXXXXX")" && pwd)"
  if [ -z "${STEVEDORE:-}" ]; then
    STEVEDORE="$(sh "$ROOT/scripts/fetch_stevedore.sh")" || { echo "fetch_stevedore.sh failed" >&2; return 1; }
  fi
  export STEVEDORE SOURCE_DATE_EPOCH=1700000000
  export MAVERGREEN_RELEASES="file://$WORK/rel" SHIPYARD_FETCH_BACKOFF=0
  PIN="$(sed -n 's/^ED25519_VERSION=//p' "$ROOT/scripts/ed25519.pin")"
  REL="$WORK/rel/Mavergreen/ed25519/releases/download/$PIN"
  mkdir -p "$REL" "$WORK/shims"
  printf '#!/bin/sh\necho "$0 $*" >> "%s/forbidden"\nexit 1\n' "$WORK" > "$WORK/shims/pkgutil"
  chmod +x "$WORK/shims/pkgutil"
  printf 'dummy pkg bytes\n' > "$WORK/x.pkg"
  printf '## Notes\n\n- thing\n' > "$WORK/notes.md"
}
teardown() { rm -rf "$WORK"; }

signer_tree() {  # signer_tree DIR TAG: ed25519-sign and ed25519-verify stubs under DIR/bin, the signer marking TAG
  mkdir -p "$1/bin"
  printf '#!/bin/sh\necho %s > "%s/signed-by"\ncat > /dev/null\necho %s\n' "$2" "$WORK" "$SIG" > "$1/bin/ed25519-sign"
  printf '#!/bin/sh\nexit 0\n' > "$1/bin/ed25519-verify"
  chmod +x "$1/bin/ed25519-sign" "$1/bin/ed25519-verify"
}

serve_tarball() {
  signer_tree "$WORK/tar/opt/mavergreen/ed25519" tarball
  mkdir -p "$WORK/tar/opt/mavergreen/ed25519/share/doc"
  : > "$WORK/tar/opt/mavergreen/ed25519/share/doc/THIRD-PARTY-NOTICES.txt"
  ( cd "$WORK/tar" && tar -czf "$REL/ed25519-$PIN-linux-x86_64.tar.gz" opt )
}

serve_pkg() {
  signer_tree "$WORK/pkgroot/usr/local/mavergreen/ed25519" pkg
  sh "$ROOT/scripts/build_component_pkg.sh" --root "$WORK/pkgroot" --identifier dev.mavergreen.ed25519 \
    --version 1.0 --install-location / --out "$REL/ed25519-$PIN.pkg" > /dev/null 2>&1
}

sums() { ( cd "$REL" && shasum -a 256 "$@" > SHA256SUMS ); }

sign() {  # sign HOST
  ED25519_HOST="$1" PATH="$WORK/shims:$PATH" SPARKLE_PRIVATE_KEY=x \
    sh "$ROOT/scripts/sign_and_appcast.sh" --product openssh --feed-dir "$WORK/feeds" --channel-title C \
    --version 1.2.3 --pkg-url https://example.invalid/x.pkg --notes-file "$WORK/notes.md" \
    --pkg "$WORK/x.pkg" --pubkey stub
}

@test "Linux takes the tarball" {
  serve_tarball
  serve_pkg
  sums "ed25519-$PIN-linux-x86_64.tar.gz" "ed25519-$PIN.pkg"
  run sign Linux
  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/signed-by")" = tarball ]
  grep -q "sparkle:edSignature=\"$SIG\"" "$WORK/feeds/openssh.xml"
  [ ! -e "$WORK/forbidden" ]
}

@test "old pin on Linux fails clearly" {
  serve_pkg
  sums "ed25519-$PIN.pkg"
  run sign Linux
  [ "$status" -ne 0 ]
  [[ "$output" == *"ed25519 $PIN"* ]] || false
  [[ "$output" == *"ed25519-$PIN-linux-x86_64.tar.gz"* ]] || false
  [ ! -e "$WORK/signed-by" ]
  [ ! -e "$WORK/forbidden" ]
  [ ! -e "$WORK/feeds" ]
}

@test "Darwin takes the pkg without pkgutil --expand-full" {
  serve_tarball
  serve_pkg
  sums "ed25519-$PIN-linux-x86_64.tar.gz" "ed25519-$PIN.pkg"
  run sign Darwin
  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/signed-by")" = pkg ]
  grep -q "sparkle:edSignature=\"$SIG\"" "$WORK/feeds/openssh.xml"
  [ ! -e "$WORK/forbidden" ]
}

@test "an explicit --signer still wins over the pinned release" {
  signer_tree "$WORK/mine" mine
  run env ED25519_HOST=Linux SPARKLE_PRIVATE_KEY=x sh "$ROOT/scripts/sign_and_appcast.sh" --signer "$WORK/mine/bin/ed25519-sign" \
    --product openssh --feed-dir "$WORK/feeds" --channel-title C --version 1.2.3 \
    --pkg-url https://example.invalid/x.pkg --notes-file "$WORK/notes.md" --pkg "$WORK/x.pkg" --pubkey stub
  [ "$status" -eq 0 ]
  [ "$(cat "$WORK/signed-by")" = mine ]
}

@test "a pkg with no signer never falls back to the working directory" {
  mkdir -p "$WORK/pkgroot/usr/local/mavergreen/ed25519/share"
  : > "$WORK/pkgroot/usr/local/mavergreen/ed25519/share/x"
  sh "$ROOT/scripts/build_component_pkg.sh" --root "$WORK/pkgroot" --identifier dev.mavergreen.ed25519 \
    --version 1.0 --install-location / --out "$REL/ed25519-$PIN.pkg" > /dev/null 2>&1
  sums "ed25519-$PIN.pkg"
  signer_tree "$WORK/cwd" planted
  cp "$WORK/cwd/bin/ed25519-sign" "$WORK/cwd/bin/ed25519-verify" "$WORK/cwd/"
  cd "$WORK/cwd"
  run sign Darwin
  [ "$status" -ne 0 ]
  [ ! -e "$WORK/signed-by" ]
}
