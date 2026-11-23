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
tools_at() {
  mkdir -p "$1/bin"
  for t in clang ld64.lld llvm-lipo llvm-otool llvm-nm llvm-strings; do printf x > "$1/bin/$t"; chmod 755 "$1/bin/$t"; done
  printf '<plist><dict>\n<key>version</key>\n<string>%s</string>\n</dict></plist>\n' "$2" > "$1/mavergreen.plist"
}
@test 'linux: a clang22 installed at the prefix at the pinned release is used, with no fetch' {
  unset MAVERGREEN_CLANG22_CACHE
  export CLANG22_INSTALLED="$WORK/root/usr/local/mavergreen/clang22"
  tools_at "$CLANG22_INSTALLED" 22.1.8-mavericks.99
  rm "$REL/SHA256SUMS"
  out="$(CLANG22_HOST=linux sh "$HELPER" "$PIN")"
  [ "$out" = "$CLANG22_INSTALLED" ] || { echo "$out"; return 1; }
}
@test 'linux: with no MAVERGREEN_CLANG22_CACHE, install-products.sh installs the release at the prefix, marked' {
  unset MAVERGREEN_CLANG22_CACHE
  export SOURCE_DATE_EPOCH=1700000000 SHIPYARD_FETCH_TRIES=1 SHIPYARD_FETCH_BACKOFF=0 SUDO= MAVERGREEN_PKG_CACHE="$WORK/pkgs"
  export CLANG22_INSTALLED="$WORK/root/usr/local/mavergreen/clang22"
  tools_at "$CLANG22_INSTALLED" 22.1.8-mavericks.98
  SD="$(sh "$BATS_TEST_DIRNAME/../scripts/fetch_stevedore.sh")"
  st="$WORK/stage/root"; mkdir -p "$st/usr/local/mavergreen/clang22"; echo pkg > "$st/usr/local/mavergreen/clang22/from-pkg"
  sh "$BATS_TEST_DIRNAME/../scripts/render-manifest.sh" --stage "$st" --product clang22 --name clang22 --version 22.1.8-mavericks.99
  sh "$BATS_TEST_DIRNAME/../scripts/build_component_pkg.sh" --root "$st" --identifier dev.mavergreen.clang.clang22 --version 1.0 \
    --install-location / --out "$WORK/stage/comp.pkg" > /dev/null 2>&1
  printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' '<installer-gui-script minSpecVersion="1">' \
    '  <pkg-ref id="dev.mavergreen.clang.clang22" version="1.0">comp.pkg</pkg-ref>' \
    '  <choices-outline><line choice="dev.mavergreen.clang.clang22"/></choices-outline>' \
    '  <choice id="dev.mavergreen.clang.clang22"><pkg-ref id="dev.mavergreen.clang.clang22"/></choice>' \
    '</installer-gui-script>' > "$WORK/stage/dist.xml"
  PKG=mavericks-clang-22-native-22.1.8-mavericks.99.pkg
  "$SD" product --distribution "$WORK/stage/dist.xml" --package "$WORK/stage/comp.pkg" --mtime 1700000000 --out "$REL/$PKG" > /dev/null
  ( cd "$REL" && shasum -a 256 "$PKG" >> SHA256SUMS )
  out="$(CLANG22_HOST=linux sh "$HELPER" "$PIN")"
  [ "$out" = "$CLANG22_INSTALLED" ] || { echo "$out"; return 1; }
  [ -x "$out/bin/ld64.lld" ] && [ "$(cat "$out/bin/clang")" = x ] && [ ! -e "$out/from-pkg" ]
  [ "$("$SD" plist get "$out/mavergreen.plist" version)" = 22.1.8-mavericks.99 ]
  [ "$("$SD" plist get "$out/mavergreen.plist" identifier)" = dev.mavergreen.clang.clang22 ]
  [ ! -d "$WORK/clang22" ] || false
}
nosudo_path() {
  mkdir -p "$WORK/nosudo"
  _ifs=$IFS; IFS=:
  for _d in $PATH; do
    for _f in "$_d"/*; do
      [ "${_f##*/}" != sudo ] && [ -x "$_f" ] && [ ! -e "$WORK/nosudo/${_f##*/}" ] && ln -s "$_f" "$WORK/nosudo/${_f##*/}" || :
    done
  done
  IFS=$_ifs
  printf '%s\n' "$WORK/nosudo"
}
unwritable_prefix() {
  unset MAVERGREEN_CLANG22_CACHE SUDO
  export HOME="$WORK/home" CLANG22_INSTALLED="$WORK/ro/usr/local/mavergreen/clang22"
  mkdir -p "$HOME" "$WORK/ro"; chmod 555 "$WORK/ro"
}
@test 'linux: with no root, no sudo and no writable prefix, the per-user cache is used, saying path parity is off' {
  [ "$(id -u)" -ne 0 ] || skip 'root can always make the prefix'
  unwritable_prefix
  out="$(PATH="$(nosudo_path)" CLANG22_HOST=linux sh "$HELPER" "$PIN" 2> "$WORK/err")" || { cat "$WORK/err"; chmod 755 "$WORK/ro"; return 1; }
  chmod 755 "$WORK/ro"
  [ "$out" = "$HOME/.cache/mavergreen-clang22/22.1.8-mavericks.99/linux" ] || { echo "$out"; return 1; }
  [ -x "$out/bin/ld64.lld" ]
  [ "$(grep -c 'without path parity with' "$WORK/err")" = 1 ] || { cat "$WORK/err"; return 1; }
  ! grep -q 'sudo:' "$WORK/err" || { cat "$WORK/err"; return 1; }
}
@test 'linux: a sudo that needs a password counts as no sudo' {
  [ "$(id -u)" -ne 0 ] || skip 'root can always make the prefix'
  unwritable_prefix
  mkdir -p "$WORK/bin"
  printf '#!/bin/sh\necho "sudo $*" >> "%s/sudo.log"\nexit 1\n' "$WORK" > "$WORK/bin/sudo"; chmod 755 "$WORK/bin/sudo"
  out="$(PATH="$WORK/bin:$PATH" CLANG22_HOST=linux sh "$HELPER" "$PIN" 2> "$WORK/err")" || { cat "$WORK/err"; chmod 755 "$WORK/ro"; return 1; }
  chmod 755 "$WORK/ro"
  [ "$out" = "$HOME/.cache/mavergreen-clang22/22.1.8-mavericks.99/linux" ] || { echo "$out"; return 1; }
  [ "$(cat "$WORK/sudo.log")" = "sudo -n true" ] || { cat "$WORK/sudo.log"; return 1; }
}
@test 'linux: with no sudo, a clang22 already at the pinned release in the prefix is used' {
  unwritable_prefix
  chmod 755 "$WORK/ro"; tools_at "$CLANG22_INSTALLED" 22.1.8-mavericks.99; chmod 555 "$WORK/ro"
  out="$(PATH="$(nosudo_path)" CLANG22_HOST=linux sh "$HELPER" "$PIN" 2> "$WORK/err")" || { cat "$WORK/err"; chmod 755 "$WORK/ro"; return 1; }
  chmod 755 "$WORK/ro"
  [ "$out" = "$CLANG22_INSTALLED" ] && [ ! -s "$WORK/err" ] || { echo "$out"; cat "$WORK/err"; return 1; }
}
@test 'linux: MAVERGREEN_CLANG22_CACHE picks the cache with no word about path parity' {
  out="$(CLANG22_HOST=linux sh "$HELPER" "$PIN" 2> "$WORK/err")"
  [ "$out" = "$WORK/clang22/22.1.8-mavericks.99/linux" ] && ! grep -q 'path parity' "$WORK/err"
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
