#!/usr/bin/env bats
# platform: host-agnostic
setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/fetch_clang22.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/fetch-clang22.XXXXXX")" && pwd)"
  export MAVERGREEN_RELEASES="file://$WORK/releases"
  export MAVERGREEN_TAR_CACHE="$WORK/tars" MAVERGREEN_CLANG22_CACHE="$WORK/clang22"
  export MAVERGREEN_PREFIX="$WORK/prefix" MAVERGREEN_PKG_CACHE="$WORK/pkgs"
  INSTALLED="$WORK/prefix/clang22-cross"
  PIN="$WORK/.mavergreen/ingredients/clang22"
  mkdir -p "$PIN"
  printf 'Mavergreen/clang-22\n' > "$PIN/REPO"; printf 'clang22\n' > "$PIN/product"
  printf '22.1.8-mavericks.99\n# renovate: datasource=github-releases depName=Mavergreen/clang-22\n' > "$PIN/VERSION"
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
}
teardown() { rm -rf "$WORK"; }

@test 'linux: the pinned archive, verified against LINUX_SHA256, is the printed root' {
  printf '%s\n' "$SHA" > "$PIN/LINUX_SHA256"
  out="$(CLANG22_HOST=linux sh "$HELPER" "$WORK")"
  [ "$out" = "$WORK/clang22/clang22-22.1.8-mavericks.99" ] || { echo "$out"; return 1; }
  [ -x "$out/bin/ld64.lld" ]
}
@test 'linux: a LINUX_SHA256 with no final newline is read' {
  printf '%s' "$SHA" > "$PIN/LINUX_SHA256"
  run env CLANG22_HOST=linux sh "$HELPER" "$WORK"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
@test 'linux: no LINUX_SHA256 fails, naming the SHA256SUMS to copy from' {
  run env CLANG22_HOST=linux sh "$HELPER" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no LINUX_SHA256 for $ASSET"*"22.1.8-mavericks.99/SHA256SUMS"* ]] || { echo "$output"; return 1; }
  [ ! -d "$WORK/clang22/clang22-22.1.8-mavericks.99" ] || false
}
@test 'linux: a LINUX_SHA256 that is not a digest fails, naming the SHA256SUMS to copy from' {
  printf '%s  %s\n' "$SHA" "$ASSET" > "$PIN/LINUX_SHA256"
  run env CLANG22_HOST=linux sh "$HELPER" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not the SHA-256 of $ASSET"*"22.1.8-mavericks.99/SHA256SUMS"* ]] || { echo "$output"; return 1; }
}
@test 'linux: a wrong digest is refused, naming the SHA256SUMS to copy from' {
  printf '%064d\n' 0 > "$PIN/LINUX_SHA256"
  run env CLANG22_HOST=linux sh "$HELPER" "$WORK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"22.1.8-mavericks.99/SHA256SUMS"* ]] || { echo "$output"; return 1; }
}
@test 'mac: an installed clang22-cross at the pinned release is used, with no fetch' {
  mkdir -p "$INSTALLED/bin"
  for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do printf x > "$INSTALLED/bin/$t"; chmod 755 "$INSTALLED/bin/$t"; done
  printf '<plist><dict>\n<key>version</key>\n<string>22.1.8-mavericks.99</string>\n</dict></plist>\n' > "$INSTALLED/mavergreen.plist"
  out="$(CLANG22_HOST=mac sh "$HELPER" "$WORK")"
  [ "$out" = "$INSTALLED" ]
}
@test 'mac: an installed clang22-cross at another release is not used' {
  mkdir -p "$INSTALLED/bin"
  for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do printf x > "$INSTALLED/bin/$t"; chmod 755 "$INSTALLED/bin/$t"; done
  printf '<plist><dict>\n<key>version</key>\n<string>22.1.8-mavericks.98</string>\n</dict></plist>\n' > "$INSTALLED/mavergreen.plist"
  run env CLANG22_HOST=mac sh "$HELPER" "$WORK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mavericks-clang-22-cross-22.1.8-mavericks.99.pkg"* ]] || { echo "$output"; return 1; }
}
@test 'a version that is not a release tag is a usage error' {
  printf '../x\n' > "$PIN/VERSION"
  run sh "$HELPER" "$WORK"
  [ "$status" -eq 2 ]
}
