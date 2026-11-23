#!/bin/sh
# platform: host-agnostic -- stevedore builds the fixture releases, served from file:// via MAVERGREEN_RELEASES
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/install-products.sh"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }; export STEVEDORE="$SD"
top="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/install-products.XXXXXX")" && pwd)"; trap 'rm -rf "$top"' EXIT
fail() { echo "FAIL: $1"; [ -z "${out:-}" ] || printf '%s\n' "--- output:" "$out"; exit 1; }
export SOURCE_DATE_EPOCH=1700000000 SHIPYARD_FETCH_BACKOFF=0 SHIPYARD_FETCH_TRIES=1 INSTALL_PRODUCTS_HOST=mac
n=0

fresh() {
  n=$((n + 1)); w="$top/$n"; mkdir -p "$w/root"
  printf '%s\n' 'a dev.mavergreen.a arepo' 'b dev.mavergreen.b brepo' 'c dev.mavergreen.c crepo' \
    'd dev.mavergreen.d drepo' 'x dev.mavergreen.x xrepo' > "$w/names"
  printf '%s\n' 'c b setup c --now' > "$w/provisioners"
  export MAVERGREEN_PRODUCT_NAMES="$w/names" MAVERGREEN_PRODUCT_PROVISIONERS="$w/provisioners"
  export MAVERGREEN_RELEASES="file://$w/rel" MAVERGREEN_PKG_CACHE="$w/cache"
}

release() {
  _s=$1; _t=$2; shift 2; _v=$_t; _ac=1; _ul=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --version) _v=$2; shift 2 ;;
      --no-appcast) _ac=""; shift ;;
      --unlisted) _ul=1; shift ;;
      --appcast-unlisted) _ul=xml; shift ;;
      *) break ;;
    esac
  done
  _repo="${_s}repo"; _rel="$w/rel/Mavergreen/$_repo/releases/download/$_t"; _st="$w/stage/$_s-$_t/root"
  mkdir -p "$_rel" "$_st/usr/local/mavergreen/$_s"
  echo "$_s" > "$_st/usr/local/mavergreen/$_s/file"
  _k=$#
  while [ "$_k" -gt 0 ]; do set -- "$@" --requires "$1"; shift; _k=$((_k - 1)); done
  sh "$here/../scripts/render-manifest.sh" --stage "$_st" --product "$_s" --name "$_s" --version "$_v" "$@"
  sh "$here/../scripts/build_component_pkg.sh" --root "$_st" --identifier "dev.mavergreen.$_s" --version 1.0 \
    --install-location / --out "$w/stage/$_s-$_t/comp.pkg" > /dev/null 2>&1
  cat > "$w/stage/$_s-$_t/dist.xml" <<DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
  <pkg-ref id="dev.mavergreen.$_s" version="1.0">comp.pkg</pkg-ref>
  <choices-outline><line choice="dev.mavergreen.$_s"/></choices-outline>
  <choice id="dev.mavergreen.$_s"><pkg-ref id="dev.mavergreen.$_s"/></choice>
</installer-gui-script>
DIST
  "$SD" product --distribution "$w/stage/$_s-$_t/dist.xml" --package "$w/stage/$_s-$_t/comp.pkg" \
    --mtime 1700000000 --out "$_rel/$_s-$_t.pkg" > /dev/null
  if [ -n "$_ac" ]; then
    printf '<rss><channel><item>\n<enclosure url="https://github.com/Mavergreen/%s/releases/download/%s/%s-%s.pkg" type="application/octet-stream" length="1" />\n</item></channel></rss>\n' \
      "$_repo" "$_t" "$_s" "$_t" > "$_rel/$_s.xml"
  fi
  ( cd "$_rel" && { [ "$_ul" = 1 ] || shasum -a 256 "$_s-$_t.pkg"; [ -z "$_ac" ] || [ "$_ul" = xml ] || shasum -a 256 "$_s.xml"; } > SHA256SUMS )
}
latest() { mkdir -p "$w/rel/Mavergreen/${1}repo/releases"; echo "$2" > "$w/rel/Mavergreen/${1}repo/releases/latest"; }
installed() {
  mkdir -p "$w/root/usr/local/mavergreen/$1"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>version</key>\n  <string>%s</string>\n%b</dict>\n</plist>\n' \
    "$2" "${3:-}" > "$w/root/usr/local/mavergreen/$1/mavergreen.plist"
}
plan() { rc=0; out="$(sh "$S" --root "$w/root" --dry-run "$@" 2>&1)" || rc=$?; }
plan_stdout() { rc=0; out="$(sh "$S" --root "$w/root" --dry-run "$@" 2>/dev/null)" || rc=$?; }
lines() { printf '%s\n' "$@"; }
has() { case "$out" in *"$1"*) return 0 ;; esac; return 1; }

abc() {
  release a 1 'b>=2' c
  release b 1; release b 2; release b 3
}

fresh; abc; latest b 3
plan_stdout a@1
[ "$rc" -eq 0 ] || fail "order: the plan must succeed, got $rc"
[ "$out" = "$(lines 'install b 3' 'provision c via b setup c --now' 'install a 1')" ] \
  || fail "order: requires before the product, a provider before what it provisions, b at its latest"

fresh; abc; latest b 3; installed b 2
plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "$(lines 'keep b 2' 'provision c via b setup c --now' 'install a 1')" ] \
  || fail "keep_when_floor_met: an installed require at the floor is kept"

fresh; abc; latest b 3; installed c 20261012.2
plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "$(lines 'install b 3' 'keep c 20261012.2' 'install a 1')" ] \
  || fail "an installed provisioned product with no floor is kept"

fresh; release a 1 c; release b 3; latest b 3
plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "$(lines 'install b 3' 'provision c via b setup c --now' 'install a 1')" ] \
  || fail "a provisioned require brings in its provider first"

fresh; release a 1 c; release b 3; latest b 3; installed c 20261012.2
plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "$(lines 'keep c 20261012.2' 'install a 1')" ] \
  || fail "a kept provisioned require does not need its provider"

fresh; abc; latest b 1
plan a@1
[ "$rc" -eq 1 ] || fail "latest_below_floor_fails: exit 1, got $rc"
has "b>=2 (required by a) cannot be met: the latest release of Mavergreen/brepo is 1, version 1" \
  || fail "latest_below_floor_fails: the message names b, the floor 2, its requirer and the latest 1"

fresh; abc; latest b 3; installed b 2; release d 1 'b>=3'
plan_stdout a@1 d@1
[ "$rc" -eq 0 ] || fail "shared_require_highest_floor: the plan must succeed, got $rc"
[ "$out" = "$(lines 'install b 3' 'provision c via b setup c --now' 'install a 1' 'install d 1')" ] \
  || fail "shared_require_highest_floor: one b line, at the highest floor"

fresh; abc; latest b 3; release d 1 'b>=3'
plan a@1 d@1 b@2
[ "$rc" -eq 1 ] && has "b" && has ">=3" || fail "a named pin below a require's floor fails, naming both"

fresh; release a 1 b; release x 1; release x 5; latest x 5; installed x 1
release b 3 x; latest b 3; release d 1 'b>=3'
installed b 1 '  <key>requires</key>\n  <array>\n    <string>x&gt;=5</string>\n  </array>\n'
plan_stdout a@1 d@1
[ "$rc" -eq 0 ] && [ "$out" = "$(lines 'keep x 1' 'install b 3' 'install a 1' 'install d 1')" ] \
  || fail "a floor from a requirer the restarted pass no longer chooses does not survive the restart"

fresh; release a 1 b; latest b 1; installed b 1 '  <key>requires</key>\n  <array>\n    <dict/>\n  </array>\n'
plan a@1
[ "$rc" -eq 1 ] && has "requires:0" || fail "an unreadable requires entry fails rather than ending the list"

fresh; release a 1 b; latest b 1; installed b 1 '  <key>requires</key>\n  <string>x</string>\n'
plan a@1
[ "$rc" -eq 1 ] && has "not an array" || fail "a requires that is not an array fails rather than reading as none"

fresh; release a 1 --appcast-unlisted
plan a@1
[ "$rc" -eq 1 ] && has "a.xml is not listed" || fail "an appcast SHA256SUMS does not list fails"

fresh; release a 1 b; release b 1 a; latest b 1; latest a 1
plan a@1
[ "$rc" -eq 1 ] && has "cycle" && has "a -> b -> a" || fail "cycle_fails: exit 1 naming the cycle"

fresh; release a 1 --unlisted
plan a@1
[ "$rc" -eq 1 ] && has "not listed" || fail "unlisted_asset_fails: exit 1, saying not listed"

fresh; release a 1 --no-appcast
plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "install a 1" ] || fail "without an appcast, the only .pkg in SHA256SUMS is the asset"

fresh; release a 1 --no-appcast
cp "$w/rel/Mavergreen/arepo/releases/download/1/a-1.pkg" "$w/rel/Mavergreen/arepo/releases/download/1/a-x.pkg"
( cd "$w/rel/Mavergreen/arepo/releases/download/1" && shasum -a 256 a-1.pkg a-x.pkg > SHA256SUMS )
plan a@1
[ "$rc" -eq 1 ] && has "a" && has "1" || fail "no appcast and more than one .pkg fails, naming the product and release"

fresh; release a 1 e
plan a@1
[ "$rc" -eq 1 ] && has "e" && has "not registered" || fail "unregistered_require_fails: exit 1 naming e"

fresh; release a 1
plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "install a 1" ] || fail "no_requires_key_installs_alone"

fresh; abc; latest b 3; installed b 1.0-rc1
plan a@1
[ "$rc" -eq 1 ] && has "1.0-rc1" || fail "unorderable_installed_fails: exit 1 naming the version"

fresh; release a 1
for bad in a a@ a@latest a@1/2 @1 'A@1' a@..; do
  plan a@1 "$bad"
  [ "$rc" -eq 2 ] || fail "malformed_product_is_usage_error: '$bad' must exit 2, got $rc"
done
[ ! -e "$w/cache" ] || fail "malformed_product_is_usage_error: nothing is fetched"
plan; [ "$rc" -eq 2 ] || fail "no products is a usage error"
plan a@1 a@2; [ "$rc" -eq 2 ] || fail "one product named at two tags is a usage error"
plan --bogus a@1; [ "$rc" -eq 2 ] || fail "an unknown option is a usage error"

fresh; release a 1; installed a 0.9
plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "install a 1" ] || fail "named_exact_pin: a different installed version is replaced"
installed a 1
plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "keep a 1" ] || fail "named_exact_pin: the pinned version installed is kept"
installed a 2
plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "install a 1" ] || fail "named_exact_pin: a newer installed version is downgraded to the pin"

fresh; release b 3; latest b 3
plan c@1
[ "$rc" -eq 1 ] && has "c" || fail "a provisioned product cannot be named at a release tag"

mkdir "$top/bin"
cat > "$top/bin/installer" <<'FAKE'
#!/bin/sh
[ "$1" = -pkg ] && [ "$3" = -target ] && [ -n "$4" ] || exit 2
echo "installer $(basename "$2")" >> "$FAKE_LOG"
case "$2" in *"${FAKE_INSTALLER_FAIL:-//none//}"*) exit 1 ;; esac
d="$(mktemp -d "${TMPDIR:-/tmp}/fake-installer.XXXXXX")"
"$STEVEDORE" expand "$2" "$d/x" > /dev/null || exit 1
for pi in "$d"/x/PackageInfo "$d"/x/*/PackageInfo; do
  [ -f "$pi" ] || continue
  ( cd "$4" && gzip -dc "$(dirname "$pi")/Payload" | cpio -id --quiet ) || exit 1
done
rm -rf "$d"
FAKE
cat > "$top/bin/b" <<'FAKE'
#!/bin/sh
echo "b $*" >> "$FAKE_LOG"
[ -z "${FAKE_B_FAIL:-}" ] || exit 1
[ -n "${FAKE_B_NOMANIFEST:-}" ] && exit 0
mkdir -p "$FAKE_ROOT/usr/local/mavergreen/$2"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>version</key>\n  <string>20261012.2</string>\n</dict>\n</plist>\n' \
  > "$FAKE_ROOT/usr/local/mavergreen/$2/mavergreen.plist"
FAKE
chmod +x "$top/bin/installer" "$top/bin/b"
real() {
  printf '%s\n' 'c b provision c' > "$w/provisioners"
  : > "$w/log"; : > "$w/installed"; rm -rf "$w/root"; mkdir -p "$w/root"
  export FAKE_LOG="$w/log" FAKE_ROOT="$w/root" MAVERGREEN_INSTALLED="$w/installed"
  export INSTALLER="$top/bin/installer" SUDO= PATH="$top/bin:$PATH"
  unset FAKE_INSTALLER_FAIL FAKE_B_FAIL FAKE_B_NOMANIFEST
}
run() { rc=0; out="$(sh "$S" --root "$w/root" "$@" 2>&1)" || rc=$?; }

fresh; abc; latest b 3; real
run a@1
[ "$rc" -eq 0 ] || fail "installs_in_order: exit 0, got $rc"
[ "$(cat "$w/log")" = "$(lines 'installer b-3.pkg' 'b provision c' 'installer a-1.pkg')" ] \
  || fail "installs_in_order: b, then b provisions c, then a ($(cat "$w/log"))"
has "installing a 1" || fail "the script says what it changed"
[ "$(cat "$w/installed")" = "$(lines 'b 3' 'c 20261012.2' 'a 1')" ] || fail "installed_file_lists_all: $(cat "$w/installed")"

fresh; abc; latest b 3; installed b 3; real; installed b 3
run a@1
[ "$rc" -eq 0 ] && [ "$(cat "$w/installed")" = "$(lines 'b 3' 'c 20261012.2' 'a 1')" ] \
  || fail "kept products are recorded too"
[ "$(grep -c '^installer' "$w/log")" -eq 1 ] || fail "a kept product is not reinstalled"

fresh; abc; latest b 3; real; export FAKE_B_FAIL=1
run a@1
[ "$rc" -eq 1 ] && [ "$(cat "$w/installed")" = "b 3" ] && ! grep -q 'a-1' "$w/log" \
  || fail "provisioner_failure_fails: exit 1, only b recorded, a not installed"
has "'b provision c' failed" || fail "provisioner_failure_fails: names the command"

fresh; abc; latest b 3; real; export FAKE_B_NOMANIFEST=1
run a@1
[ "$rc" -eq 1 ] && [ "$(cat "$w/installed")" = "b 3" ] && has "c:" && has "b provision c" \
  || fail "provision_without_manifest_fails: names c and the command"

fresh; abc; latest b 3; real; export FAKE_INSTALLER_FAIL=a-1.pkg
run a@1
[ "$rc" -eq 1 ] && [ "$(cat "$w/installed")" = "$(lines 'b 3' 'c 20261012.2')" ] && has "a 1" \
  || fail "installer_failure_fails: exit 1, a not recorded"

fresh; abc; latest b 3; real; export FAKE_INSTALLER_FAIL=b-3.pkg
run a@1
[ "$rc" -eq 1 ] && [ ! -s "$w/installed" ] && ! grep -q '^b ' "$w/log" \
  || fail "a failed step stops everything after it"

fresh; release a 1 'c>=20261013'; release b 3; latest b 3; real
run a@1
[ "$rc" -eq 1 ] && has "c>=20261013" && has "20261012.2" && [ "$(cat "$w/installed")" = "b 3" ] \
  || fail "a provision below the floor fails, naming the floor and version"

fresh; release a 1 'c>=20261013'; release b 3; latest b 3; real; installed c 20261001; export FAKE_B_NOMANIFEST=1
run a@1
[ "$rc" -eq 1 ] && has "unchanged" && [ "$(cat "$w/installed")" = "b 3" ] \
  || fail "a provision that leaves a stale manifest untouched fails"

cat > "$top/bin/logger-installer" <<'FAKE'
#!/bin/sh
echo "installer $*" >> "$FAKE_LOG"
FAKE
cat > "$top/bin/sudo" <<'FAKE'
#!/bin/sh
echo "sudo $*" >> "$FAKE_LOG"
case "$1" in installer) shift; exec "$FAKE_SUDO_INSTALLER" "$@" ;; esac
FAKE
chmod +x "$top/bin/logger-installer" "$top/bin/sudo"

fresh; release a 1; real
run_root() { rc=0; out="$(sh "$S" --root / "$@" 2>&1)" || rc=$?; }
INSTALLER="$top/bin/logger-installer" run_root a@1
grep -q "^installer -pkg .*a-1.pkg -target /$" "$w/log" \
  || fail "default_root_target_is_slash: the installer target is exactly /"
[ "$(sed -n 's/.* -target //p' "$w/log")" = "/" ] || fail "default_root_target_is_slash: one target, exactly /"

if [ "$(id -u)" -ne 0 ]; then
  fresh; release a 1; real; unset INSTALLER; export FAKE_SUDO_INSTALLER="$top/bin/logger-installer"
  run_root a@1
  grep -q "^sudo installer -pkg .*a-1.pkg -target /$" "$w/log" \
    || fail "default_sudo_installer: unset INSTALLER runs sudo installer -pkg PKG -target /"
fi

linux() {
  real; export INSTALL_PRODUCTS_HOST=linux MAVERGREEN_TAR_CACHE="$w/tars"
  export INSTALLER="$top/bin/logger-installer" FAKE_SUDO_INSTALLER="$top/bin/logger-installer"
}
linuxtar() {
  _rel="$w/rel/Mavergreen/${1}repo/releases/download/$2"
  python3 -c '
import io, sys, tarfile
with tarfile.open(sys.argv[1], "w:gz") as t:
    m = tarfile.TarInfo("opt/mavergreen/%s/bin/tool" % sys.argv[2]); m.mode = 0o755; m.size = 5
    t.addfile(m, io.BytesIO(b"linux"))
    if len(sys.argv) > 3:
        t.add(sys.argv[3], "opt/mavergreen/%s/mavergreen.plist" % sys.argv[2])
' "$_rel/$1-$2-linux-x86_64.tar.gz" "$1" ${3:+"$3"}
  ( cd "$_rel" && shasum -a 256 "$1-$2-linux-x86_64.tar.gz" >> SHA256SUMS )
}
mg() { printf '%s\n' "$w/root/usr/local/mavergreen/$1"; }
noinstaller() { ! grep -q installer "$w/log"; }
pget() { "$SD" plist get "$(mg "$1")/mavergreen.plist" "$2" 2>/dev/null; }

fresh; release a 1; linuxtar a 1; linux
run a@1
[ "$rc" -eq 0 ] || fail "linux_tarball: exit 0, got $rc"
[ "$(cat "$(mg a)/bin/tool")" = linux ] && [ -x "$(mg a)/bin/tool" ] && [ ! -e "$(mg a)/file" ] \
  || fail "linux_tarball: the linux-x86_64 archive, not the pkg payload, is unpacked at the prefix"
[ "$(pget a version)" = 1 ] && [ "$(pget a product)" = a ] || fail "linux_tarball: the pkg's own mavergreen.plist marks the prefix"
[ -z "$(find "$(mg a)" -name '.*')" ] || fail "linux_tarball: nothing but the product is left in the prefix"
noinstaller && [ "$(cat "$w/installed")" = "a 1" ] || fail "linux_tarball: no installer runs, and a 1 is recorded"
[ -f "$w/cache/arepo/1/a-1.pkg" ] || fail "linux_tarball: an archive with no mavergreen.plist falls back to the pkg's"

path_without() {
  _pw="$top/without-$1"
  if [ ! -d "$_pw" ]; then
    mkdir -p "$_pw"; _ifs=$IFS; IFS=:
    for _d in $PATH; do
      for _f in "$_d"/*; do
        [ "${_f##*/}" != "$1" ] && [ -x "$_f" ] && [ ! -e "$_pw/${_f##*/}" ] && ln -s "$_f" "$_pw/${_f##*/}" || :
      done
    done
    IFS=$_ifs
  fi
  printf '%s\n' "$_pw"
}

fresh; release a 1; linuxtar a 1; linux
rc=0; out="$(PATH="$(path_without cpio)" sh "$S" --root "$w/root" a@1 2>&1)" || rc=$?
[ "$rc" -eq 1 ] && has "a 1: needs cpio to read the mavergreen.plist in a-1.pkg; install the cpio package" \
  && ! has "could not decompress" && [ ! -e "$w/cache/arepo/1/a-1.pkg" ] && [ ! -s "$w/installed" ] \
  || fail "linux_no_cpio: a pkg's plist without cpio fails before the pkg is fetched, naming cpio"

fresh; release a 1; linuxtar a 1; linux
run a@1
[ "$rc" -eq 0 ] || fail "linux_plist_cached: the first install reads the pkg's plist"
_rel="$w/rel/Mavergreen/arepo/releases/download/1"
rm -rf "$(mg a)" "$w/cache/arepo/1/a-1.pkg" "$_rel/a-1.pkg"; : > "$w/installed"
rc=0; out="$(PATH="$(path_without cpio)" sh "$S" --root "$w/root" a@1 2>&1)" || rc=$?
[ "$rc" -eq 0 ] && [ "$(cat "$(mg a)/bin/tool")" = linux ] && [ "$(pget a version)" = 1 ] && [ "$(pget a product)" = a ] \
  && [ ! -e "$w/cache/arepo/1/a-1.pkg" ] && [ "$(cat "$w/installed")" = "a 1" ] \
  || fail "linux_plist_cached: a plist already read from that very pkg spares fetching and decompressing it"
printf '%064d  a-1.pkg\n' 0 > "$_rel/SHA256SUMS.new"
grep -v ' a-1.pkg$' "$_rel/SHA256SUMS" >> "$_rel/SHA256SUMS.new"; mv "$_rel/SHA256SUMS.new" "$_rel/SHA256SUMS"
rm -rf "$(mg a)"
rc=0; out="$(PATH="$(path_without cpio)" sh "$S" --root "$w/root" a@1 2>&1)" || rc=$?
[ "$rc" -eq 1 ] && has "needs cpio" || fail "linux_plist_cached: a plist read from another pkg digest is not used"

mkdir -p "$top/badgz"
fresh; release a 1; linux
printf '#!/bin/sh\nexit 1\n' > "$top/badgz/gzip"; chmod +x "$top/badgz/gzip"
rc=0; out="$(PATH="$top/badgz:$PATH" sh "$S" --root "$w/root" --dry-run a@1 2>&1)" || rc=$?
[ "$rc" -eq 1 ] && has "could not decompress the Payload of dev.mavergreen.a" || fail "a failing gzip is named as the decompress"
fresh; release a 1; linux
printf '#!/bin/sh\nexec yes payload\n' > "$top/badgz/gzip"; printf '#!/bin/sh\nexit 1\n' > "$top/badgz/cpio"
chmod +x "$top/badgz/gzip" "$top/badgz/cpio"
rc=0; out="$(PATH="$top/badgz:$PATH" sh "$S" --root "$w/root" --dry-run a@1 2>&1)" || rc=$?
[ "$rc" -eq 1 ] && has "could not unpack the Payload of dev.mavergreen.a" && ! has "decompress" \
  || fail "a failing cpio is not blamed on the gzip it stops reading"

fresh; release a 1 'b>=2'; release b 3; latest b 3
_rel="$w/rel/Mavergreen/arepo/releases/download/1"; rm -f "$_rel/a-1.pkg" "$_rel/a.xml"; : > "$_rel/SHA256SUMS"
linuxtar a 1 "$w/stage/a-1/root/usr/local/mavergreen/a/mavergreen.plist"; linux
INSTALL_PRODUCTS_HOST=linux plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "$(lines 'install b 3' 'install a 1')" ] \
  || fail "linux_tarball_plist: the archive's own mavergreen.plist gives the version and the requires"
run a@1
[ "$rc" -eq 0 ] && [ "$(cat "$(mg a)/bin/tool")" = linux ] && [ "$(pget a version)" = 1 ] && [ "$(pget a product)" = a ] \
  || fail "linux_tarball_plist: the release installs from its archive, marked by the archive's plist, with no pkg in the release"
[ -z "$(find "$w/cache/arepo" -type f 2>/dev/null)" ] && [ "$(cat "$w/installed")" = "$(lines 'b 3' 'a 1')" ] \
  || fail "linux_tarball_plist: no pkg of a is requested or cached"

fresh; release b 1; linux
run b@1
[ "$rc" -eq 0 ] && [ "$(cat "$(mg b)/file")" = b ] && [ "$(pget b version)" = 1 ] \
  || fail "linux_pkg_payload: a release with no linux archive installs its pkg's payload, marker included"
noinstaller && [ "$(cat "$w/installed")" = "b 1" ] || fail "linux_pkg_payload: no installer runs, and b 1 is recorded"
release b 2; run b@2
[ "$rc" -eq 0 ] && [ "$(pget b version)" = 2 ] && [ -z "$(find "$(mg b)" -name '.*')" ] \
  || fail "linux_pkg_payload: another pin replaces the installed product in place"

fresh; release a 1 'b>=2'; release b 3; latest b 3; linux; installed b 2
run a@1
[ "$rc" -eq 0 ] && [ "$(cat "$w/installed")" = "$(lines 'b 2' 'a 1')" ] && [ ! -e "$(mg b)/file" ] \
  || fail "linux_keep_at_floor: an installed require at its floor is kept, read from its marker"

fresh; printf '%s\n' 'sdk109 dev.mavergreen.longboat.sdk109 lbrepo' 'lb dev.mavergreen.lb lbrepo' >> "$w/names"
printf '%s\n' 'sdk109 lb sdk install 10.9' > "$w/provisioners"; latest lb 20261027.13
mkdir -p "$w/sdksrc/MacOSX10.9.sdk/usr/lib"; : > "$w/sdksrc/MacOSX10.9.sdk/usr/lib/libSystem.tbd"
( cd "$w/sdksrc" && tar -czf "$w/sdk.tar" MacOSX10.9.sdk )
export MAVERICKS_SDK_URL="file://$w/sdk.tar" MAVERICKS_SDK_SHA256="$(shasum -a 256 "$w/sdk.tar" | awk '{print $1}')" MAVERICKS_SDK_CACHE="$w/sdkcache"
release a 1 'sdk109>=20261027'
INSTALL_PRODUCTS_HOST=linux plan_stdout a@1
[ "$rc" -eq 0 ] && [ "$out" = "$(lines 'provision sdk109 via fetch_sdk.sh --arch x86_64' 'install a 1')" ] \
  || fail "linux_sdk: the plan provisions sdk109 with fetch_sdk.sh, and needs no longboat"
linux; printf '%s\n' 'sdk109 lb sdk install 10.9' > "$w/provisioners"
run a@1
sdk="$(mg sdk109)/SDKs/MacOSX10.9.sdk"
[ "$rc" -eq 0 ] && [ -f "$sdk/usr/lib/libSystem.tbd" ] || fail "linux_sdk: the pinned SDK lands at the prefix's SDKs/"
[ "$(cat "$sdk/SDKSettings.json")" = '{"CanonicalName":"macosx10.9","MaximumDeploymentTarget":"10.9","Version":"10.9"}' ] \
  || fail "linux_sdk: the SDK carries the SDKSettings.json longboat writes into it"
[ "$(pget sdk109 version)" = 20261027.13 ] && [ "$(pget sdk109 name)" = "Mac OS X 10.9 SDK" ] \
  && [ "$(pget sdk109 identifier)" = dev.mavergreen.longboat.sdk109 ] \
  || fail "linux_sdk: the marker is the one longboat's pkg installs, at longboat's latest version"
[ "$(cat "$w/installed")" = "$(lines 'sdk109 20261027.13' 'a 1')" ] && [ ! -s "$w/log" ] \
  || fail "linux_sdk: neither longboat nor an installer runs ($(cat "$w/log"))"
unset MAVERICKS_SDK_URL MAVERICKS_SDK_SHA256 MAVERICKS_SDK_CACHE

fresh; release x 1 --no-appcast; linux
cp "$w/stage/x-1/comp.pkg" "$w/rel/Mavergreen/xrepo/releases/download/1/x-1.pkg"
( cd "$w/rel/Mavergreen/xrepo/releases/download/1" && shasum -a 256 x-1.pkg > SHA256SUMS )
run x@1
[ "$rc" -eq 1 ] && has "x 1" && has "x-1-linux-x86_64.tar.gz" && [ ! -e "$(mg x)/mavergreen.plist" ] && [ ! -s "$w/installed" ] \
  || fail "linux_unextractable: no linux archive and a pkg fetch_product_pkg.sh cannot extract exits 1, naming both"
noinstaller || fail "linux_unextractable: the installer never runs on Linux"

fresh; release b 1; linux
for k in 1 2 3; do ( sh "$S" --root "$w/root" b@1 > "$w/par.$k" 2>&1; echo $? > "$w/par.$k.rc" ) & done; wait
for k in 1 2 3; do
  [ "$(cat "$w/par.$k.rc")" = 0 ] || { out="$(cat "$w/par.$k")"; fail "linux_concurrent: every concurrent install of one product succeeds"; }
done
[ "$(cat "$(mg b)/file")" = b ] && [ "$(pget b version)" = 1 ] && [ -z "$(find "$(mg b)" -name '.*')" ] \
  || fail "linux_concurrent: concurrent installs leave one whole, marked tree and nothing else"

fresh; release b 1; linux; mkdir -p "$(mg b)"; echo 2147483646 > "$(mg b)/.install-products.lock"
run b@1
[ "$rc" -eq 0 ] && [ "$(pget b version)" = 1 ] && [ ! -e "$(mg b)/.install-products.lock" ] \
  || fail "linux_stale_lock: a lock whose process is gone does not block the install"

nosudo="$top/nosudo"; mkdir -p "$nosudo"
_ifs=$IFS; IFS=:
for _d in $PATH; do
  for _f in "$_d"/*; do
    [ "${_f##*/}" != sudo ] && [ -x "$_f" ] && [ ! -e "$nosudo/${_f##*/}" ] && ln -s "$_f" "$nosudo/${_f##*/}" || :
  done
done
IFS=$_ifs
cat > "$top/bin/sudo-pw" <<'FAKE'
#!/bin/sh
echo "sudo $*" >> "$FAKE_LOG"
exit 1
FAKE
chmod +x "$top/bin/sudo-pw"; mkdir -p "$top/pw"; ln -s "$top/bin/sudo-pw" "$top/pw/sudo"

if [ "$(id -u)" -ne 0 ]; then
  fresh; release b 1; linux; unset SUDO; chmod 555 "$w/root"
  rc=0; out="$(PATH="$nosudo" sh "$S" --root "$w/root" b@1 2>&1)" || rc=$?
  chmod 755 "$w/root"
  [ "$rc" -eq 1 ] && has "needs root, sudo, or a writable $w/root/usr/local/mavergreen" \
    && ! has "not found" && ! has "cannot find name" && [ ! -s "$w/installed" ] \
    || fail "linux_no_sudo: with no sudo and no writable prefix, exit 1, saying what it needs"

  fresh; release b 1; linux; unset SUDO; chmod 555 "$w/root"
  rc=0; out="$(PATH="$top/pw:$PATH" sh "$S" --root "$w/root" b@1 2>&1)" || rc=$?
  chmod 755 "$w/root"
  [ "$rc" -eq 1 ] && has "needs root, sudo, or a writable" && [ "$(cat "$w/log")" = "sudo -n true" ] \
    || fail "linux_sudo_needs_password: a sudo that cannot run without a password is probed once and not used ($(cat "$w/log"))"

  fresh; printf '%s\n' 'sdk109 dev.mavergreen.longboat.sdk109 lbrepo' 'lb dev.mavergreen.lb lbrepo' >> "$w/names"
  printf '%s\n' 'sdk109 lb sdk install 10.9' > "$w/provisioners"; latest lb 20261027.13
  release a 1 'sdk109>=20261027'; linux; unset SUDO; printf '%s\n' 'sdk109 lb sdk install 10.9' > "$w/provisioners"
  export MAVERICKS_SDK_URL="file://$w/nosuch.tar" MAVERICKS_SDK_SHA256=0 MAVERICKS_SDK_CACHE="$w/sdkcache"
  chmod 555 "$w/root"
  rc=0; out="$(PATH="$nosudo" sh "$S" --root "$w/root" a@1 2>&1)" || rc=$?
  chmod 755 "$w/root"
  [ "$rc" -eq 1 ] && has "sdk109: cannot make $w/root/usr/local/mavergreen/sdk109: install-products needs root, sudo, or a writable" \
    && ! has "fetch_sdk.sh --arch x86_64 failed" && [ ! -e "$w/sdkcache" ] && ! has "not found" && [ ! -s "$w/installed" ] \
    || fail "linux_sdk_no_sudo: sdk109 needs the same root, sudo or writable prefix, checked before the SDK is fetched"
  unset MAVERICKS_SDK_URL MAVERICKS_SDK_SHA256 MAVERICKS_SDK_CACHE
fi

fresh; release b 1; linux; unset SUDO; mkdir -p "$w/root/usr/local/mavergreen"
rc=0; out="$(PATH="$nosudo" sh "$S" --root "$w/root" b@1 2>&1)" || rc=$?
[ "$rc" -eq 0 ] && [ "$(pget b version)" = 1 ] && [ "$(cat "$w/installed")" = "b 1" ] \
  || fail "linux_writable_no_sudo: a writable usr/local/mavergreen needs no sudo"

echo "PASS: install-products"
