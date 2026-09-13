#!/bin/sh
# spec: mavericks-ed25519 carries the real ed25519-sign; this stubs the signer so the test
#       exercises sign_and_appcast.sh's orchestration, not the crypto (no compiler or network
#       fetch needed).
set -eu
# spec: scripts/run-repo-tests.sh -- exit 77 is the family's SKIP idiom, not a failure. Called
#       bare, as the shared runner does when it globs tests/*.sh, there is no root to test
#       against; ctest itself always supplies the source root (see add_test in CMakeLists.txt).
[ "$#" -ge 1 ] || { echo "no source root given (ctest supplies it) -- skipping" >&2; exit 77; }
ROOT="$1"
T=$(mktemp -d "${TMPDIR:-/tmp}/mav-signappcast.XXXXXX")
trap 'rm -rf "$T"' EXIT

# spec: how the key reaches the signer (-f - <file>, key on stdin) is
#       tests/sign_and_appcast_key.bats's concern -- this stub only returns a fixed, well-formed
#       base64 signature.
SIG="c3R1YnNpZ25hdHVyZWZvcnRlc3Rpbmdvbmx5QUFBQUFBQUFBQUFBQUFBQUFBQUFBQT09"
cat > "$T/sign" <<EOF
#!/bin/sh
echo "$SIG"
EOF
chmod +x "$T/sign"
# spec: ed25519-verify sits beside the signer, where sign_and_appcast.sh looks. This test is
#       about the appcast, not about trust (tests/sign_and_appcast_trust.bats), so it always
#       verifies, against --pubkey.
printf '#!/bin/sh\nexit 0\n' > "$T/ed25519-verify"
chmod +x "$T/ed25519-verify"

printf 'dummy pkg bytes\n' > "$T/x.pkg"
printf '## Notes\n\n- thing one\n- thing two\n' > "$T/notes.md"
LEN=$(wc -c < "$T/x.pkg" | tr -d '[:space:]')

OUT=$(SPARKLE_PRIVATE_KEY="ignored-by-stub" sh "$ROOT/scripts/sign_and_appcast.sh" \
  --signer "$T/sign" --channel-title "Test Channel" --version 1.2.3 \
  --pkg-url "https://example.invalid/x.pkg" --notes-file "$T/notes.md" --pkg "$T/x.pkg" --pubkey stub)

fail() { echo "sign_and_appcast test: $1" >&2; exit 1; }
printf '%s\n' "$OUT" | grep -q "sparkle:edSignature=\"$SIG\"" || fail "signer's signature not in the enclosure"
printf '%s\n' "$OUT" | grep -q "length=\"$LEN\"" || fail "pkg length not in the enclosure"
printf '%s\n' "$OUT" | grep -q '<sparkle:version>1.2.3</sparkle:version>' || fail "version missing"
printf '%s\n' "$OUT" | grep -q 'https://example.invalid/x.pkg' || fail "enclosure url missing"
printf '%s\n' "$OUT" | grep -q '<li>thing one</li>' || fail "notes not rendered"

echo "sign_and_appcast OK"
