#!/usr/bin/env bats
# platform: host-agnostic
setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/fetch_clang22.sh"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/fetch-clang22.XXXXXX")"
  printf 'clang22 dev.mavergreen.clang.clang22 clang-22\nclang22-cross dev.mavergreen.clang.clang22-cross clang-22\n' > "$WORK/names"
  export MAVERGREEN_PRODUCT_NAMES="$WORK/names" MAVERGREEN_RELEASES="file://$WORK/releases"
  export MAVERGREEN_TAR_CACHE="$WORK/tars" MAVERGREEN_CLANG22_CACHE="$WORK/clang22"
  export CLANG22_INSTALLED="$WORK/installed"
  PIN="$WORK/components/clang22"
  mkdir -p "$PIN"
  printf '22.1.8-mavericks.99\n' > "$PIN/version"
  REL="$WORK/releases/Mavergreen/clang-22/releases/download/22.1.8-mavericks.99"
  mkdir -p "$REL"
  ASSET=clang22-22.1.8-mavericks.99-linux-x86_64.tar.gz
  python3 - "$REL/$ASSET" <<'PY'
import io, sys, tarfile
with tarfile.open(sys.argv[1], 'w:gz') as t:
    for tool in ('clang', 'ld64.lld', 'llvm-lipo', 'llvm-otool', 'llvm-nm', 'llvm-strings'):
        m = tarfile.TarInfo('opt/mavergreen/clang22/bin/' + tool); m.mode = 0o755; m.size = 1
        t.addfile(m, io.BytesIO(b'x'))
PY
  SHA="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REL/$ASSET")"
  printf '%s  %s\n' "$SHA" "$ASSET" > "$REL/SHA256SUMS"
}
teardown() { rm -rf "$WORK"; }

@test 'linux: the archive, verified against the release SHA256SUMS, is the printed root' {
  out="$(CLANG22_HOST=linux sh "$HELPER" "$PIN")"
  [ "$out" = "$WORK/clang22/22.1.8-mavericks.99/linux" ] || { echo "$out"; return 1; }
  [ -x "$out/bin/ld64.lld" ]
}
@test 'linux: a binary-mode SHA256SUMS line (*name) is read too' {
  printf '%s *%s\n' "$SHA" "$ASSET" > "$REL/SHA256SUMS"
  run env CLANG22_HOST=linux sh "$HELPER" "$PIN"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
@test 'linux: an archive SHA256SUMS does not list fails, naming it' {
  printf '%s  %s\n' "$SHA" clang22-22.1.8-mavericks.98-linux-x86_64.tar.gz > "$REL/SHA256SUMS"
  run env CLANG22_HOST=linux sh "$HELPER" "$PIN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$ASSET is not listed"*"22.1.8-mavericks.99/SHA256SUMS"* ]] || { echo "$output"; return 1; }
  [ ! -d "$WORK/clang22/22.1.8-mavericks.99/linux" ] || false
}
@test 'linux: a SHA256SUMS digest that does not match the archive is refused' {
  printf '%064d  %s\n' 0 "$ASSET" > "$REL/SHA256SUMS"
  run env CLANG22_HOST=linux sh "$HELPER" "$PIN"
  [ "$status" -ne 0 ]
  [ ! -d "$WORK/clang22/22.1.8-mavericks.99/linux" ] || false
}
@test 'mac: an installed clang22-cross at the pinned release is used, with no fetch' {
  mkdir -p "$CLANG22_INSTALLED/bin"
  for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do printf x > "$CLANG22_INSTALLED/bin/$t"; chmod 755 "$CLANG22_INSTALLED/bin/$t"; done
  printf '<plist><dict>\n<key>version</key>\n<string>22.1.8-mavericks.99</string>\n</dict></plist>\n' > "$CLANG22_INSTALLED/mavergreen.plist"
  out="$(CLANG22_HOST=mac sh "$HELPER" "$PIN")"
  [ "$out" = "$CLANG22_INSTALLED" ]
}
@test 'mac: an installed clang22-cross at another release is not used' {
  mkdir -p "$CLANG22_INSTALLED/bin"
  for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do printf x > "$CLANG22_INSTALLED/bin/$t"; chmod 755 "$CLANG22_INSTALLED/bin/$t"; done
  printf '<plist><dict>\n<key>version</key>\n<string>22.1.8-mavericks.98</string>\n</dict></plist>\n' > "$CLANG22_INSTALLED/mavergreen.plist"
  run env CLANG22_HOST=mac sh "$HELPER" "$PIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mavericks-clang-22-cross-22.1.8-mavericks.99.pkg"* ]] || { echo "$output"; return 1; }
}
@test 'a version that is not a release tag is a usage error' {
  printf '../x\n' > "$PIN/version"
  run sh "$HELPER" "$PIN"
  [ "$status" -eq 2 ]
}
