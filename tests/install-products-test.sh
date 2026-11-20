#!/bin/sh
# platform: host-agnostic -- stevedore builds the fixture releases, served from file:// via MAVERGREEN_RELEASES
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/install-products.sh"
SD="$(sh "$here/../scripts/fetch_stevedore.sh")" || { echo "FAIL: fetch_stevedore.sh failed"; exit 1; }; export STEVEDORE="$SD"
top="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/install-products.XXXXXX")" && pwd)"; trap 'rm -rf "$top"' EXIT
fail() { echo "FAIL: $1"; [ -z "${out:-}" ] || printf '%s\n' "--- output:" "$out"; exit 1; }
export SOURCE_DATE_EPOCH=1700000000 SHIPYARD_FETCH_BACKOFF=0 SHIPYARD_FETCH_TRIES=1
n=0

fresh() {
  n=$((n + 1)); w="$top/$n"; mkdir -p "$w/root"
  printf '%s\n' 'a dev.mavergreen.a arepo' 'b dev.mavergreen.b brepo' 'c dev.mavergreen.c crepo' \
    'd dev.mavergreen.d drepo' > "$w/names"
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
  ( cd "$_rel" && { [ -n "$_ul" ] || shasum -a 256 "$_s-$_t.pkg"; [ -z "$_ac" ] || shasum -a 256 "$_s.xml"; } > SHA256SUMS )
}
latest() { mkdir -p "$w/rel/Mavergreen/${1}repo/releases"; echo "$2" > "$w/rel/Mavergreen/${1}repo/releases/latest"; }
installed() {
  mkdir -p "$w/root/usr/local/mavergreen/$1"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n  <key>version</key>\n  <string>%s</string>\n</dict>\n</plist>\n' \
    "$2" > "$w/root/usr/local/mavergreen/$1/mavergreen.plist"
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
has "b" && has ">=2" && has "1" || fail "latest_below_floor_fails: the message names b, the floor 2 and the latest 1"

fresh; abc; latest b 3; installed b 2; release d 1 'b>=3'
plan_stdout a@1 d@1
[ "$rc" -eq 0 ] || fail "shared_require_highest_floor: the plan must succeed, got $rc"
[ "$out" = "$(lines 'install b 3' 'provision c via b setup c --now' 'install a 1' 'install d 1')" ] \
  || fail "shared_require_highest_floor: one b line, at the highest floor"

fresh; abc; latest b 3; release d 1 'b>=3'
plan a@1 d@1 b@2
[ "$rc" -eq 1 ] && has "b" && has ">=3" || fail "a named pin below a require's floor fails, naming both"

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
rc=0; out="$(sh "$S" --root "$w/root" a@1 2>&1)" || rc=$?
[ "$rc" -eq 2 ] || fail "without --dry-run the script does not install yet"

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

echo "PASS: install-products"
