#!/usr/bin/env bats
# platform: host-agnostic
setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/fetch_clang22.sh"
  WORK="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/fetch-clang22.XXXXXX")" && pwd)"
  export MAVERGREEN_RELEASES="file://$WORK/releases"
  export MAVERGREEN_TAR_CACHE="$WORK/tars" MAVERGREEN_CLANG22_CACHE="$WORK/clang22"
  export MAVERGREEN_ROOT="$WORK/prefix" MAVERGREEN_PKG_CACHE="$WORK/pkgs"
  INSTALLED="$WORK/prefix/opt/mavergreen/clang22-cross"
  PIN="$WORK/.mavergreen/ingredients/clang22"
  mkdir -p "$PIN"
  printf 'Mavergreen/clang-22\n' > "$PIN/REPO"; printf 'clang22\n' > "$PIN/product"
  printf '22.1.8-mavergreen.99\n# renovate: datasource=github-releases depName=Mavergreen/clang-22\n' > "$PIN/VERSION"
  REL="$WORK/releases/Mavergreen/clang-22/releases/download/22.1.8-mavergreen.99"
  mkdir -p "$REL"
  ASSET=clang22-22.1.8-mavergreen.99-linux-x86_64.tar.gz
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

@test 'linux: the pinned archive, verified against the release's SHA256SUMS, is the printed root' {
  out="$(CLANG22_HOST=linux sh "$HELPER" "$WORK")"
  [ "$out" = "$WORK/clang22/clang22-22.1.8-mavergreen.99" ] || { echo "$out"; return 1; }
  [ -x "$out/bin/ld64.lld" ]
}
@test 'linux: an archive SHA256SUMS does not list fails, naming SHA256SUMS' {
  printf '%s  %s\n' "$SHA" other.tar.gz > "$REL/SHA256SUMS"
  run env SHIPYARD_FETCH_TRIES=1 CLANG22_HOST=linux sh "$HELPER" "$WORK"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SHA256SUMS"* ]] || { echo "$output"; return 1; }
  [ ! -d "$WORK/clang22/clang22-22.1.8-mavergreen.99" ] || false
}
@test 'linux: a wrong digest in SHA256SUMS is refused' {
  printf '%064d  %s\n' 0 "$ASSET" > "$REL/SHA256SUMS"
  run env CLANG22_HOST=linux sh "$HELPER" "$WORK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SHA256SUMS"* ]] || { echo "$output"; return 1; }
}
@test 'mac: an installed clang22-cross at the pinned release is used, with no fetch' {
  mkdir -p "$INSTALLED/bin"
  for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do printf x > "$INSTALLED/bin/$t"; chmod 755 "$INSTALLED/bin/$t"; done
  printf '<plist><dict>\n<key>version</key>\n<string>22.1.8-mavergreen.99</string>\n</dict></plist>\n' > "$INSTALLED/mavergreen.plist"
  out="$(CLANG22_HOST=mac sh "$HELPER" "$WORK")"
  [ "$out" = "$INSTALLED" ]
}
@test 'mac: an installed clang22-cross at another release is not used' {
  mkdir -p "$INSTALLED/bin"
  for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do printf x > "$INSTALLED/bin/$t"; chmod 755 "$INSTALLED/bin/$t"; done
  printf '<plist><dict>\n<key>version</key>\n<string>22.1.8-mavergreen.98</string>\n</dict></plist>\n' > "$INSTALLED/mavergreen.plist"
  run env CLANG22_HOST=mac sh "$HELPER" "$WORK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"mavericks-clang-22-cross-22.1.8-mavergreen.99.pkg"* ]] || { echo "$output"; return 1; }
}
@test 'a version that is not a release tag is a usage error' {
  printf '../x\n' > "$PIN/VERSION"
  run sh "$HELPER" "$WORK"
  [ "$status" -eq 2 ]
}
@test 'NAME names another clang22 ingredient, whose own pin is used' {
  O="$WORK/.mavergreen/ingredients/other-clang"; mkdir -p "$O"
  cp "$PIN/REPO" "$PIN/product" "$PIN/VERSION" "$O/"
  printf '22.1.8-mavergreen.98\n' > "$PIN/VERSION"
  out="$(CLANG22_HOST=linux sh "$HELPER" "$WORK" other-clang)"
  [ "$out" = "$WORK/clang22/clang22-22.1.8-mavergreen.99" ] || { echo "$out"; return 1; }
  run env SHIPYARD_FETCH_TRIES=1 CLANG22_HOST=linux sh "$HELPER" "$WORK"
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}
@test 'a NAME that is not an ingredient name is a usage error' {
  run sh "$HELPER" "$WORK" ../clang22
  [ "$status" -eq 2 ]
}
