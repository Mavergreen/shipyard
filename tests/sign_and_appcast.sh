#!/bin/sh
# platform: host-agnostic
# spec: scripts/sign_and_appcast.sh -- mavericks-ed25519 carries the real ed25519-sign; this
#       stubs the signer so the test exercises this script's orchestration, not the crypto (no
#       compiler or network fetch needed).
set -eu
# spec: scripts/run-repo-tests.sh --strict-host -- a host-agnostic test must RUN when called bare,
#       as the shared runner does when it globs tests/*.sh, so the root defaults to this checkout;
#       ctest still passes it explicitly (see add_test in CMakeLists.txt).
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
T=$(mktemp -d "${TMPDIR:-/tmp}/mav-signappcast.XXXXXX")
trap 'rm -rf "$T"' EXIT

# spec: tests/sign_and_appcast_key.bats -- how the key reaches the signer (-f - <file>, key on
#       stdin) is that file's concern; this stub only returns a fixed, well-formed base64
#       signature.
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

SPARKLE_PRIVATE_KEY="ignored-by-stub" sh "$ROOT/scripts/sign_and_appcast.sh" \
  --signer "$T/sign" --product openssh --feed-dir "$T/feeds" --channel-title "Test Channel" --version 1.2.3 \
  --pkg-url "https://example.invalid/x.pkg" --notes-file "$T/notes.md" --pkg "$T/x.pkg" --pubkey stub > "$T/stdout"
OUT="$(cat "$T/feeds/openssh.xml")"

fail() { echo "sign_and_appcast test: $1" >&2; exit 1; }
printf '%s\n' "$OUT" | grep -q "sparkle:edSignature=\"$SIG\"" || fail "signer's signature not in the enclosure"
printf '%s\n' "$OUT" | grep -q "length=\"$LEN\"" || fail "pkg length not in the enclosure"
printf '%s\n' "$OUT" | grep -q '<sparkle:version>1.2.3</sparkle:version>' || fail "version missing"
printf '%s\n' "$OUT" | grep -q 'https://example.invalid/x.pkg' || fail "enclosure url missing"
printf '%s\n' "$OUT" | grep -q '<li>thing one</li>' || fail "notes not rendered"
[ ! -s "$T/stdout" ] || fail "the feed goes to --feed-dir as <product>.xml, never to stdout, where a caller could name it anything"
[ "$(ls -A "$T/feeds")" = openssh.xml ] || fail "only the feed is left in --feed-dir: $(ls -A "$T/feeds")"
rc=0; SPARKLE_PRIVATE_KEY=x sh "$ROOT/scripts/sign_and_appcast.sh" --signer "$T/sign" --product no-such-product \
  --feed-dir "$T/feeds2" --channel-title C --version 1.2.3 --pkg-url https://example.invalid/x.pkg \
  --notes-file "$T/notes.md" --pkg "$T/x.pkg" --pubkey stub 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "an unregistered --product has no feed; expected exit 2, got $rc"
[ ! -e "$T/feeds2" ] || fail "a refused call writes no feed"
rc=0; SPARKLE_PRIVATE_KEY=x sh "$ROOT/scripts/sign_and_appcast.sh" --signer "$T/sign" --product openssh \
  --channel-title C --version 1.2.3 --pkg-url https://example.invalid/x.pkg \
  --notes-file "$T/notes.md" --pkg "$T/x.pkg" --pubkey stub 2>/dev/null || rc=$?
[ "$rc" -eq 2 ] || fail "--feed-dir is required; expected exit 2, got $rc"

echo "sign_and_appcast OK"
