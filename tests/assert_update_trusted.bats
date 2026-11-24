# platform: host-agnostic -- the verifier is a stub with ed25519-verify's contract ("signed-by:K" verifies against K), and curl is stubbed to fail
bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  T="$BATS_TEST_TMPDIR"
  KFAM='ZmFtaWx5LWtleS1mYW1pbHkta2V5LWZhbWlseS1rZXk='
  KOTHER='b3RoZXIta2V5LW90aGVyLWtleS1vdGhlci1rZXktb3Q='
  printf '%s\n' "$KFAM" > "$T/family.pub"
  printf 'pkg bytes\n' > "$T/new.pkg"
  cat > "$T/verify" <<'EOF'
#!/bin/sh
keys=
while getopts p: o; do case $o in p) keys="$keys $OPTARG" ;; *) exit 2 ;; esac; done
shift $((OPTIND - 1)); [ -n "$keys" ] && [ "$#" -eq 2 ] || exit 2
[ -r "$1" ] || exit 2
for k in $keys; do [ "$2" = "signed-by:$k" ] && { printf '%s\n' "$k"; exit 0; }; done
exit 1
EOF
  chmod +x "$T/verify"
  mkdir -p "$T/stub"
  printf '#!/bin/sh\necho "curl must not run" >&2\nexit 7\n' > "$T/stub/curl"
  chmod +x "$T/stub/curl"
}

trusted() {  # SIGNATURE [extra args]
  local sig="$1"; shift
  PATH="$T/stub:$PATH" sh "$ROOT/scripts/assert_update_trusted.sh" --pkg "$T/new.pkg" --signature "$sig" --verifier "$T/verify" "$@"
}

@test "signed by the family key named by --key -> trusted, with no network" {
  run --separate-stderr trusted "signed-by:$KFAM" --key "$T/family.pub"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" != *"curl must not run"* ]] || false
}

@test "signed by any other key -> refused, naming the family key" {
  run --separate-stderr trusted "signed-by:$KOTHER" --key "$T/family.pub"
  [ "$status" -eq 1 ]
  printf "%s\n" "$stderr" | grep -q "^update-trusted: "
  [[ "$stderr" == *"$KFAM"* ]] || false
}

@test "with no --key, the key is keys/feed-ed25519.pub beside the scripts" {
  k="$(tr -d '[:space:]' < "$ROOT/keys/feed-ed25519.pub")"
  [ -n "$k" ]
  run --separate-stderr trusted "signed-by:$k"
  [ "$status" -eq 0 ]
  run --separate-stderr trusted "signed-by:$KOTHER"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"keys/feed-ed25519.pub"* ]] || false
}

@test "a --key file that is missing or empty fails closed" {
  run --separate-stderr trusted "signed-by:$KFAM" --key "$T/missing.pub"
  [ "$status" -eq 1 ]
  : > "$T/empty.pub"
  run --separate-stderr trusted "signed-by:$KFAM" --key "$T/empty.pub"
  [ "$status" -eq 1 ]
}

@test "a verifier that cannot check at all fails closed" {
  run --separate-stderr trusted "signed-by:$KFAM" --key "$T/family.pub" --pkg "$T/missing.pkg"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"could not check"* ]] || false
}

@test "--pubkey and --allow-key-change are refused: the trusted key is keys/feed-ed25519.pub" {
  run --separate-stderr trusted "signed-by:$KFAM" --pubkey x
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"the trusted key is keys/feed-ed25519.pub; rotate it there"* ]] || false
  run --separate-stderr trusted "signed-by:$KFAM" --allow-key-change
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"the trusted key is keys/feed-ed25519.pub; rotate it there"* ]] || false
}

@test "requires --pkg, --signature and --verifier" {
  run --separate-stderr sh "$ROOT/scripts/assert_update_trusted.sh" --pkg "$T/new.pkg" --signature x
  [ "$status" -eq 2 ]
}
