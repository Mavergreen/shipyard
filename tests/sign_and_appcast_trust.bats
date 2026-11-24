# platform: host-agnostic -- the signer is the pinned ed25519 release (Linux tarball, or pkg read with stevedore), and curl is stubbed to fail
bats_require_minimum_version 1.5.0

setup_file() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TOOLS="$(sh "$ROOT/scripts/fetch_ed25519_tools.sh" "$BATS_FILE_TMPDIR/tools")" || { echo "fetch_ed25519_tools.sh failed: no signer" >&2; return 1; }
  mkdir "$BATS_FILE_TMPDIR/keys"
  for k in family other; do
    "$TOOLS/ed25519-keygen" -f "$BATS_FILE_TMPDIR/keys/$k" > /dev/null
  done
  export TOOLS
}

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/repo/.mavergreen/products/openssh"; echo OpenSSH > "$T/repo/.mavergreen/products/openssh/noun"; export MAVERGREEN_REPO_ROOT="$T/repo"
  KFAM="$(cat "$BATS_FILE_TMPDIR/keys/family.pub")"
  printf 'pkg bytes\n' > "$T/new.pkg"
  printf '## Notes\n\n- thing\n' > "$T/notes.md"
  mkdir -p "$T/stub"
  printf '#!/bin/sh\necho "curl must not run" >&2\nexit 7\n' > "$T/stub/curl"
  chmod +x "$T/stub/curl"
}

sign_and_appcast() {  # sign_and_appcast PRIVATE_KEY_NAME [extra args]
  local k="$1"; shift
  PATH="$T/stub:$PATH" SPARKLE_PRIVATE_KEY="$(cat "$BATS_FILE_TMPDIR/keys/$k")" sh "$ROOT/scripts/sign_and_appcast.sh" \
    --signer "$TOOLS/ed25519-sign" --product openssh --feed-dir "$T/feeds" \
    --version 1.2.3 --pkg-url https://example.invalid/new.pkg \
    --notes-file "$T/notes.md" --pkg "$T/new.pkg" "$@"
}

@test "signed by the family key: the appcast is written, and its signature verifies" {
  run --separate-stderr sign_and_appcast family --key "$BATS_FILE_TMPDIR/keys/family.pub"
  [ "$status" -eq 0 ]
  sig="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$T/feeds/openssh.xml")"
  [ -n "$sig" ]
  "$TOOLS/ed25519-verify" -p "$KFAM" "$T/new.pkg" "$sig"
}

@test "signed by any other key: no appcast at all, and the refusal names the family key" {
  run --separate-stderr sign_and_appcast other --key "$BATS_FILE_TMPDIR/keys/family.pub"
  [ "$status" -ne 0 ]
  [ ! -e "$T/feeds/openssh.xml" ]
  [[ "$stderr" == *"$KFAM"* ]] || false
}

@test "with no --key, a signature by a key other than keys/feed-ed25519.pub gets no appcast" {
  run --separate-stderr sign_and_appcast other
  [ "$status" -ne 0 ]
  [ ! -e "$T/feeds/openssh.xml" ]
  [[ "$stderr" == *"keys/feed-ed25519.pub"* ]] || false
}

@test "--pubkey and --allow-key-change are refused, before anything is signed" {
  run --separate-stderr sign_and_appcast family --pubkey "$KFAM"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"the trusted key is keys/feed-ed25519.pub; rotate it there"* ]] || false
  run --separate-stderr sign_and_appcast family --allow-key-change
  [ "$status" -eq 2 ]
  [ ! -e "$T/feeds/openssh.xml" ]
}

@test "with no ed25519-verify beside --signer, and no --verifier, it refuses rather than skip the check" {
  mkdir "$T/bin"; cp "$TOOLS/ed25519-sign" "$T/bin/"
  run --separate-stderr sign_and_appcast family --key "$BATS_FILE_TMPDIR/keys/family.pub" --signer "$T/bin/ed25519-sign"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"ed25519-verify"* ]] || false
  run --separate-stderr sign_and_appcast family --key "$BATS_FILE_TMPDIR/keys/family.pub" --signer "$T/bin/ed25519-sign" --verifier "$TOOLS/ed25519-verify"
  [ "$status" -eq 0 ]
}
