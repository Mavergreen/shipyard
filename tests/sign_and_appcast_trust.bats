# platform: host-agnostic -- the signer is the pinned ed25519 release (Linux tarball, or pkg read with stevedore) and the fixture pkgs are built with stevedore
bats_require_minimum_version 1.5.0
load lib/sparkle_pkg

setup_file() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TOOLS="$(sh "$ROOT/scripts/fetch_ed25519_tools.sh" "$BATS_FILE_TMPDIR/tools")" || { echo "fetch_ed25519_tools.sh failed: no signer" >&2; return 1; }
  mkdir "$BATS_FILE_TMPDIR/keys"
  for k in old new other; do
    "$TOOLS/ed25519-keygen" -f "$BATS_FILE_TMPDIR/keys/$k" > /dev/null
  done
  export TOOLS
}

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  T="$BATS_TEST_TMPDIR"
  KOLD="$(cat "$BATS_FILE_TMPDIR/keys/old.pub")"
  KNEW="$(cat "$BATS_FILE_TMPDIR/keys/new.pub")"
  KOTHER="$(cat "$BATS_FILE_TMPDIR/keys/other.pub")"
  FEED="file://$T/appcast.xml"
  printf '## Notes\n\n- thing\n' > "$T/notes.md"
}

sign_and_appcast() {  # sign_and_appcast PRIVATE_KEY_NAME [extra args]
  local k="$1"; shift
  SPARKLE_PRIVATE_KEY="$(cat "$BATS_FILE_TMPDIR/keys/$k")" sh "$ROOT/scripts/sign_and_appcast.sh" \
    --signer "$TOOLS/ed25519-sign" --product openssh --feed-dir "$T/feeds" \
    --channel-title C --version 1.2.3 --pkg-url https://example.invalid/new.pkg \
    --notes-file "$T/notes.md" --pkg "$T/new.pkg" "$@"
}

live_release() {  # KEY
  mkpkg "$T/prev.pkg" "$1" "$FEED" TestUpdater
  mkfeed "$T/appcast.xml" "file://$T/prev.pkg"
}

@test "first release: a signature from the key the new updater ships gets its appcast, and it verifies" {
  mkpkg "$T/new.pkg" "$KNEW" "$FEED" TestUpdater
  run --separate-stderr sign_and_appcast new
  [ "$status" -eq 0 ]
  sig="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$T/feeds/openssh.xml")"
  [ -n "$sig" ]
  "$TOOLS/ed25519-verify" -p "$KNEW" "$T/new.pkg" "$sig"
}

@test "first release: a signature from any other key gets no appcast at all" {
  mkpkg "$T/new.pkg" "$KNEW" "$FEED" TestUpdater
  run --separate-stderr sign_and_appcast other
  [ "$status" -ne 0 ]
  [ ! -e "$T/feeds/openssh.xml" ]
  [[ "$stderr" == *"$KNEW"* ]] || false
}

@test "key mismatch: the new key's signature over a live pkg that trusts the old key gets no appcast" {
  live_release "$KOLD"
  mkpkg "$T/new.pkg" "$KNEW" "$FEED" TestUpdater
  run --separate-stderr sign_and_appcast new
  [ "$status" -ne 0 ]
  [ ! -e "$T/feeds/openssh.xml" ]
  [[ "$stderr" == *"$KOLD"* ]] || false
}

@test "bridge release: signed by the old key, shipping the new one, gets its appcast" {
  live_release "$KOLD"
  mkpkg "$T/new.pkg" "$KNEW" "$FEED" TestUpdater
  run --separate-stderr sign_and_appcast old
  [ "$status" -eq 0 ]
  [ -s "$T/feeds/openssh.xml" ]
  [[ "$stderr" == *"next release"* ]] || false
}

@test "unreadable live pkg fails closed: no appcast" {
  printf 'not a pkg\n' > "$T/prev.pkg"
  mkfeed "$T/appcast.xml" "file://$T/prev.pkg"
  mkpkg "$T/new.pkg" "$KNEW" "$FEED" TestUpdater
  run --separate-stderr sign_and_appcast new
  [ "$status" -ne 0 ]
  [ ! -e "$T/feeds/openssh.xml" ]
  [[ "$stderr" == *"no readable Sparkle updater"* ]] || false
}

@test "with no ed25519-verify beside --signer, and no --verifier, it refuses rather than skip the check" {
  mkpkg "$T/new.pkg" "$KNEW" "$FEED" TestUpdater
  mkdir "$T/bin"; cp "$TOOLS/ed25519-sign" "$T/bin/"
  run --separate-stderr sign_and_appcast new --signer "$T/bin/ed25519-sign"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"ed25519-verify"* ]] || false
  run --separate-stderr sign_and_appcast new --signer "$T/bin/ed25519-sign" --verifier "$TOOLS/ed25519-verify"
  [ "$status" -eq 0 ]
}

@test "--pubkey and --allow-key-change reach the check" {
  mkpkg "$T/new.pkg"
  run --separate-stderr sign_and_appcast new
  [ "$status" -ne 0 ]
  run --separate-stderr sign_and_appcast new --pubkey "$KNEW"
  [ "$status" -eq 0 ]
  live_release "$KOLD"
  mkpkg "$T/new.pkg" "$KNEW" "$FEED" TestUpdater
  run --separate-stderr sign_and_appcast new
  [ "$status" -ne 0 ]
  run --separate-stderr sign_and_appcast new --allow-key-change
  [ "$status" -eq 0 ]
}
