#!/bin/sh
# platform: host-agnostic -- stevedore reads the pkgs and manifests; nothing here installs yet
#   usage: install-products.sh [--root DIR] [--dry-run] SHORT@TAG...
#          Installs each named Mavergreen product at exactly its release TAG and, first, everything it
#          requires, transitively. A product's requires are the `requires` array of the mavergreen.plist
#          in its release pkg (SHORT or SHORT>=FLOOR); a require already installed under DIR (default /)
#          at or above its floor is kept, a provisioned one (scripts/product-provisioners, or
#          $MAVERGREEN_PRODUCT_PROVISIONERS) is set up by its provider's command, and any other resolves
#          to its repo's latest release, which must meet the highest floor any product declares. A named
#          product is kept only when its installed manifest version is the pinned release's.
#          A release's pkg is the one its appcast SHORT.xml names, else the only .pkg in its SHA256SUMS;
#          it is fetched into ${MAVERGREEN_PKG_CACHE:-$HOME/Library/Caches/mavergreen-pkgs}/REPO/TAG and
#          verified against that SHA256SUMS. Versions compare with scripts/lib/vercmp.sh.
#          --dry-run prints the plan on stdout, one line per product in install order:
#          `keep SHORT VERSION`, `install SHORT VERSION` or `provision SHORT via COMMAND...`.
#          Exit 1 when a product cannot be resolved, fetched or verified, or a floor cannot be met;
#          2 on a usage error. MAVERGREEN_RELEASES replaces https://github.com (the tests serve file://);
#          MAVERGREEN_PRODUCT_NAMES replaces the registry.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavericks_fetch.sh"
. "$SELF/lib/vercmp.sh"
usage() { echo "usage: install-products.sh [--root DIR] [--dry-run] SHORT@TAG..." >&2; exit 2; }
die() { echo "install-products: $*" >&2; exit 1; }
ROOT=/; DRY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] && [ -n "$2" ] || usage; ROOT=$2; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || usage
seen=" "
for p in "$@"; do
  s="${p%%@*}"; t="${p#*@}"
  case "$p" in *@*) : ;; *) echo "install-products: '$p' is not SHORT@TAG" >&2; usage ;; esac
  case "$s" in ''|-*|*[!a-z0-9-]*) echo "install-products: '$p' names no product" >&2; usage ;; esac
  case "$t" in ''|.|..|latest|*[!A-Za-z0-9._+-]*) echo "install-products: '$p' names no release tag" >&2; usage ;; esac
  case "$seen" in
    *" $s@$t "*) : ;;
    *" $s@"*) echo "install-products: $s is named at two tags" >&2; usage ;;
  esac
  seen="$seen$s@$t "
done
[ -n "$DRY" ] || { echo "install-products: installing is not implemented yet; pass --dry-run" >&2; exit 2; }
ROOT="${ROOT%/}"
STEVEDORE="$(sh "$SELF/fetch_stevedore.sh")" || die "no stevedore to read the pkgs with"
T="$(mktemp -d "${TMPDIR:-/tmp}/install-products.XXXXXX")"
trap 'rm -rf "$T"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$T/pin" "$T/floor" "$T/m" "$T/w"
for p in "$@"; do printf '%s\n' "${p#*@}" > "$T/pin/${p%%@*}"; done

reg() {
  _rv="$(sh "$SELF/product-name.sh" "$1" "$2")" && return 0
  case $? in
    1) die "$2 is not registered in shipyard's scripts/product-names${3:+ (required by $3)}" ;;
    *) die "the registry cannot look up the $1 of $2" ;;
  esac
}
ge() {
  _c="$(mavergreen_vercmp "$1" "$2")" || die "$3: cannot order version $1 against $2 (see scripts/lib/vercmp.sh)"
  [ "$_c" -ge 0 ]
}
mver() {
  _v="$("$STEVEDORE" plist get "$1" version 2>/dev/null)" && [ -n "$_v" ] || die "$2: $1 has no version"
}
listed() {
  _ls="$(awk -v f="$2" '$2 == f || $2 == "*" f { print $1 }' "$1")"
  case "$_ls" in *[!0-9a-f]*|'') return 1 ;; esac
  [ "${#_ls}" -eq 64 ]
}
enclosures() {
  awk '{ s = s $0 " " }
    END { while (match(s, /<enclosure[^>]*>/)) {
            e = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
            if (match(e, /url="[^"]*"/)) print substr(e, RSTART + 5, RLENGTH - 6) } }' "$1" | sort -u
}

manifest() {
  _mf="$T/m/$1@$3.plist"
  [ ! -f "$_mf" ] || return 0
  _base="${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/$2/releases/download/$3"
  _cache="${MAVERGREEN_PKG_CACHE:-$HOME/Library/Caches/mavergreen-pkgs}/$2/$3"
  _w="$T/w/$1@$3"
  rm -rf "$_w"; mkdir -p "$_w" "$_cache" || die "$1 $3: cannot make $_w or $_cache"
  shipyard_curl --quiet "$_base/SHA256SUMS" "$_w/SHA256SUMS" || die "$1 $3: could not fetch $_base/SHA256SUMS"
  reg feed "$1"; _xml="${_rv##*/}"
  if listed "$_w/SHA256SUMS" "$_xml"; then
    shipyard_fetch_verified "$_base/$_xml" "$_ls" "$_cache" "$_xml" || die "$1 $3: could not fetch and verify $_base/$_xml"
    cp "$_cache/$_xml" "$_w/appcast" || die "$1 $3: cannot copy $_xml"
  else
    shipyard_curl --quiet "$_base/$_xml" "$_w/appcast" 2>/dev/null || rm -f "$_w/appcast"
  fi
  if [ -f "$_w/appcast" ]; then
    _u="$(enclosures "$_w/appcast")"
    case "$_u" in
      ''|*"
"*) die "$1 $3: $_base/$_xml does not name exactly one pkg" ;;
    esac
    _asset="${_u##*/}"
  else
    _asset="$(awk '$2 ~ /\.pkg$/ { sub(/^\*/, "", $2); print $2 }' "$_w/SHA256SUMS" | sort -u)"
    case "$_asset" in
      ''|*"
"*) die "$1 $3: the release has no $_xml and not exactly one .pkg in $_base/SHA256SUMS" ;;
    esac
  fi
  case "$_asset" in ''|.|..|*[!A-Za-z0-9._+-]*) die "$1 $3: '$_asset' is not a release asset name" ;; esac
  listed "$_w/SHA256SUMS" "$_asset" || die "$1 $3: $_asset is not listed (once) in $_base/SHA256SUMS"
  shipyard_fetch_verified "$_base/$_asset" "$_ls" "$_cache" "$_asset" \
    || die "$1 $3: could not fetch and verify $_base/$_asset"
  "$STEVEDORE" expand "$_cache/$_asset" "$_w/x" > /dev/null || die "$1 $3: could not expand $_cache/$_asset"
  _m="$(grep -l "identifier=\"$4\"" "$_w"/x/PackageInfo "$_w"/x/*/PackageInfo 2>/dev/null || :)"
  [ "$(printf '%s\n' "$_m" | grep -c .)" = 1 ] || die "$1 $3: expected one component $4 in $_asset"
  mkdir "$_w/p" || die "$1 $3: cannot make $_w/p"
  ( cd "$_w/p" && gzip -dc "$(dirname "$_m")/Payload" | cpio -id --quiet "*usr/local/mavergreen/$1/mavergreen.plist" ) 2>/dev/null \
    || die "$1 $3: could not unpack the Payload of $4"
  mv "$_w/p/usr/local/mavergreen/$1/mavergreen.plist" "$_mf" 2>/dev/null \
    || die "$1 $3: $4 in $_asset installs no usr/local/mavergreen/$1/mavergreen.plist"
  rm -rf "$_w"
}

resolve() {
  s=$1; fl=$2; stack=$3; by="${stack##* }"
  case " $stack " in
    *" $s "*)
      _cy=""
      for _x in $stack; do [ -z "$_cy" ] && [ "$_x" != "$s" ] || _cy="$_cy$_x -> "; done
      die "a cycle of requires: $_cy$s" ;;
  esac
  if [ -f "$T/floor/$s" ]; then
    _old="$(cat "$T/floor/$s")"
    if [ -z "$fl" ] || ! ge "$fl" "$_old" "$s"; then fl=$_old; fi
  fi
  [ -z "$fl" ] || printf '%s\n' "$fl" > "$T/floor/$s"
  if [ -f "$T/done/$s" ]; then
    v="$(cat "$T/done/$s")"
    if [ -z "$fl" ] || [ "$v" = - ] || ge "$v" "$fl" "$s"; then return 0; fi
    [ ! -f "$T/pin/$s" ] || die "$s is named at $(cat "$T/pin/$s") (version $v), below $s>=$fl${by:+ required by $by}"
    exit 3
  fi
  reg repo "$s" "$by"; repo=$_rv
  reg identifier "$s" "$by"; id=$_rv
  prov="$(sh "$SELF/product-name.sh" provisioner "$s")" || case $? in
    1) prov="" ;;
    *) die "the registry cannot look up the provisioner of $s" ;;
  esac
  inst=""; ip="$ROOT/usr/local/mavergreen/$s/mavergreen.plist"
  if [ -f "$ip" ]; then mver "$ip" "$s"; inst=$_v; fi
  src=""
  if [ -f "$T/pin/$s" ]; then
    [ -z "$prov" ] || die "$s is set up by '$prov', not released: name its provider instead"
    tag="$(cat "$T/pin/$s")"
    manifest "$s" "$repo" "$tag" "$id"; src=$_mf
    mver "$src" "$s"; v=$_v
    [ -z "$fl" ] || ge "$v" "$fl" "$s" || die "$s is named at $tag (version $v), below $s>=$fl${by:+ required by $by}"
    if [ "$inst" = "$v" ]; then act=keep; else act=install; fi
  elif [ -n "$inst" ] && { [ -z "$fl" ] || ge "$inst" "$fl" "$s"; }; then
    act=keep; v=$inst; src=$ip
  elif [ -n "$prov" ]; then
    ( resolve "${prov%% *}" "" "$stack $s" ) || exit $?
    act=provision; v=-
  else
    tag="$(shipyard_latest_tag "$repo")" || die "$s: no latest release of Mavergreen/$repo${by:+ (required by $by)}"
    manifest "$s" "$repo" "$tag" "$id"; src=$_mf
    mver "$src" "$s"; v=$_v
    [ -z "$fl" ] || ge "$v" "$fl" "$s" \
      || die "$s>=$fl${by:+ (required by $by)} cannot be met: the latest release of Mavergreen/$repo is $tag, version $v"
    act=install
  fi
  i=0
  while [ -n "$src" ] && r="$("$STEVEDORE" plist get "$src" "requires:$i" 2>/dev/null)"; do
    rn="${r%%>=*}"; rf=""
    case "$r" in *'>='*) rf="${r#*>=}" ;; esac
    case "$rn" in ''|-*|*[!a-z0-9-]*) die "$s requires '$r', which names no product" ;; esac
    ( resolve "$rn" "$rf" "$stack $s" ) || exit $?
    i=$((i + 1))
  done
  printf '%s\n' "$v" > "$T/done/$s"
  case "$act" in
    provision) printf 'provision %s via %s\n' "$s" "$prov" ;;
    *) printf '%s %s %s\n' "$act" "$s" "$v" ;;
  esac >> "$T/plan"
}

while :; do
  rm -rf "$T/done"; mkdir "$T/done"; : > "$T/plan"
  rc=0
  for p in "$@"; do
    ( resolve "${p%%@*}" "" "" ) || { rc=$?; break; }
  done
  [ "$rc" -eq 3 ] || break
done
[ "$rc" -eq 0 ] || exit 1
cat "$T/plan"
