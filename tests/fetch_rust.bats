#!/usr/bin/env bats
# platform: host-agnostic
setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/fetch_rust.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/fetch-rust.XXXXXX")"
  printf 'rust dev.mavergreen.rust.rust rust\n' > "$WORK/names"
  export MAVERGREEN_PRODUCT_NAMES="$WORK/names" MAVERGREEN_RELEASES="file://$WORK/releases"
  export MAVERGREEN_TAR_CACHE="$WORK/tars" MAVERGREEN_RUST_CACHE="$WORK/rust"
  export RUST_INSTALLED="$WORK/installed" SHIPYARD_FETCH_TRIES=1 SHIPYARD_FETCH_BACKOFF=0
  PIN="$WORK/components/rust"
  mkdir -p "$PIN"
  printf '1.99.1-mavericks.99\n' > "$PIN/version"
  REL="$WORK/releases/Mavergreen/rust/releases/download/1.99.1-mavericks.99"
  mkdir -p "$REL"
  ASSET=rust-1.99.1-mavericks.99-linux-x86_64.tar.gz
  python3 - "$REL/$ASSET" <<'PY'
import io, sys, tarfile
with tarfile.open(sys.argv[1], 'w:gz') as t:
    for tool in ('cargo', 'rustc', 'rustc.bin', 'rustdoc'):
        m = tarfile.TarInfo('opt/mavergreen/rust/bin/' + tool); m.mode = 0o755; m.size = 1
        t.addfile(m, io.BytesIO(b'x'))
PY
  SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REL/$ASSET")"
  printf '%s  %s\n' "$SHA" "$ASSET" > "$REL/SHA256SUMS"
}
teardown() { rm -rf "$WORK"; }
tools_at() {
  mkdir -p "$1/bin"
  for t in cargo rustc rustdoc; do printf old > "$1/bin/$t"; chmod 755 "$1/bin/$t"; done
  printf '<plist><dict>\n<key>version</key>\n<string>%s</string>\n</dict></plist>\n' "$2" > "$1/mavergreen.plist"
}

@test 'linux: the archive, verified against the release SHA256SUMS, is the printed prefix' {
  out="$(RUST_HOST=linux sh "$HELPER" "$PIN")"
  [ "$out" = "$WORK/rust/1.99.1-mavericks.99/linux" ] || { echo "$out"; return 1; }
  [ -x "$out/bin/cargo" ] && [ -x "$out/bin/rustc" ] && [ -x "$out/bin/rustdoc" ]
}
@test 'linux: an archive SHA256SUMS does not list fails, and nothing is unpacked' {
  printf '%s  %s\n' "$SHA" rust-1.99.1-mavericks.98-linux-x86_64.tar.gz > "$REL/SHA256SUMS"
  run env RUST_HOST=linux sh "$HELPER" "$PIN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fetch_rust: could not fetch and verify $ASSET"* ]] || { echo "$output"; return 1; }
  [ ! -d "$WORK/rust/1.99.1-mavericks.99/linux" ] || false
}
@test 'linux: a digest that does not match the archive is refused' {
  printf '%064d  %s\n' 0 "$ASSET" > "$REL/SHA256SUMS"
  run env RUST_HOST=linux sh "$HELPER" "$PIN"
  [ "$status" -eq 1 ]
  [ ! -d "$WORK/rust/1.99.1-mavericks.99/linux" ] || false
}
@test 'an installed rust at the pinned release is used, with no fetch' {
  tools_at "$RUST_INSTALLED" 1.99.1-mavericks.99
  rm "$REL/SHA256SUMS"
  for h in linux mac; do
    out="$(RUST_HOST=$h sh "$HELPER" "$PIN")"
    [ "$out" = "$RUST_INSTALLED" ] || { echo "$h: $out"; return 1; }
  done
}
@test 'linux: an installed rust at another release is left alone, and the pinned one goes to the cache' {
  tools_at "$RUST_INSTALLED" 1.99.1-mavericks.17
  out="$(RUST_HOST=linux sh "$HELPER" "$PIN")"
  [ "$out" = "$WORK/rust/1.99.1-mavericks.99/linux" ] || { echo "$out"; return 1; }
  [ "$(cat "$RUST_INSTALLED/bin/cargo")" = old ] || false
}
@test 'a pin that is not a release tag is a usage error' {
  printf '../x\n' > "$PIN/version"
  run env RUST_HOST=linux sh "$HELPER" "$PIN"
  [ "$status" -eq 2 ]
  run sh "$HELPER"
  [ "$status" -eq 2 ]
}
@test 'an unknown RUST_HOST is a usage error' {
  run env RUST_HOST=windows sh "$HELPER" "$PIN"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not linux or mac"* ]] || { echo "$output"; return 1; }
}
