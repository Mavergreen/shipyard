#!/bin/sh
# platform: host-agnostic -- stevedore reads the pkgs and manifests; the installer and provisioner commands run where it does
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
#          verified against that SHA256SUMS. Reading the mavergreen.plist out of a pkg's Payload needs
#          gzip and cpio, checked before the pkg is fetched; the plist is kept beside the pkg as
#          ASSET.SHORT.SHA256.mavergreen.plist, so a later run for that very pkg reads it there instead,
#          and on Linux does not fetch the pkg at all. Versions compare with scripts/lib/vercmp.sh.
#          The plan has one line per product in install order: `keep SHORT VERSION`,
#          `install SHORT VERSION` or `provision SHORT via COMMAND...`. --dry-run prints it on stdout;
#          otherwise each line is carried out and reported on stderr: install runs
#          `$INSTALLER -pkg PKG -target DIR` on the verified cached pkg (default `installer`, under
#          `sudo` unless root or no sudo is installed); provision runs COMMAND (under `sudo` likewise, and
#          on Linux only when `sudo -n true` succeeds; SUDO= overrides) and then
#          requires DIR/usr/local/mavergreen/SHORT/mavergreen.plist to exist. After each product, kept
#          ones included, `SHORT VERSION` is appended to $MAVERGREEN_INSTALLED when set; the first
#          failing step stops the run, so the file lists only what completed.
#          Exit 1 when a product cannot be resolved, fetched or verified, or a floor cannot be met;
#          2 on a usage error. MAVERGREEN_RELEASES replaces https://github.com (the tests serve file://);
#          MAVERGREEN_PRODUCT_NAMES replaces the registry.
#          On Linux no installer runs. Each product goes to the same DIR/usr/local/mavergreen/SHORT as
#          its pkg, staged whole in DIR/usr/local/mavergreen/.install-products/SHORT (made with $SUDO mkdir
#          and chowned to the caller's numeric uid:gid, or, with no sudo, made directly, failing with exit 1
#          unless root or DIR/usr/local/mavergreen is writable) and then renamed into place, an older tree
#          renamed aside first and removed after, so the prefix never holds a partial tree: a release whose SHA256SUMS lists
#          SHORT-TAG-linux-x86_64.tar.gz installs that archive (fetch_product_tar.sh, on an x86_64 host),
#          any other its pkg's usr/local/mavergreen/SHORT payload (fetch_product_pkg.sh), and either way
#          the pkg's own mavergreen.plist marks it. An archive holding opt/mavergreen/SHORT/mavergreen.plist
#          supplies that manifest itself, the version and requires included, and its pkg is never
#          fetched; the archive is cached in ${MAVERGREEN_TAR_CACHE:-$HOME/.cache/mavergreen-tars}/REPO/TAG. An SDK product, sdk<NNN> for a pin in sdk-pins.sh,
#          is provisioned `via fetch_sdk.sh --arch ARCH` instead of by its provider: the pinned SDK,
#          with the SDKSettings.json longboat adds, lands in SHORT/SDKs/, marked as longboat's pkg
#          marks it at the latest release of SHORT's repo. Installs into one prefix take turns through
#          .install-products/SHORT/lock, created exclusively and holding the installer's pid (a lock
#          whose process is gone is taken over; a live one is waited on up to SHIPYARD_LOCK_WAIT
#          seconds, default 900), and one that finds the marker already at its version keeps the tree.
#          INSTALL_PRODUCTS_HOST (linux or mac) replaces the host's own answer from uname -s.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavericks_fetch.sh"
. "$SELF/lib/vercmp.sh"
. "$SELF/lib/requires.sh"
. "$SELF/sdk-pins.sh"
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
ROOT="${ROOT%/}"
HOST="${INSTALL_PRODUCTS_HOST:-}"
if [ -z "$HOST" ]; then
  case "$(uname -s)" in Linux) HOST=linux ;; *) HOST=mac ;; esac
fi
case "$HOST" in linux|mac) : ;; *) echo "install-products: INSTALL_PRODUCTS_HOST is '$HOST', not linux or mac" >&2; exit 2 ;; esac
STEVEDORE="$(sh "$SELF/fetch_stevedore.sh")" || die "no stevedore to read the pkgs with"
T="$(mktemp -d "${TMPDIR:-/tmp}/install-products.XXXXXX")"
stg=""; lk=""
trap 'rm -rf "$T" ${stg:+"$stg"} ${lk:+"$lk"}' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$T/pin" "$T/carry" "$T/m" "$T/w" "$T/pkg" "$T/tag"
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

sdkarch() {
  _sa=""
  [ "$HOST" = linux ] || return 0
  for _a in x86_64 arm64; do
    _pin="$(shipyard_sdk_pin "$_a")" || continue
    _sd="${_pin##* }"; _sv="${_sd#MacOSX}"; _sv="${_sv%.sdk}"
    if [ "sdk$(printf '%s' "$_sv" | tr -d .)" = "$1" ]; then _sa=$_a; _sdir=$_sd; _sver=$_sv; return 0; fi
  done
}

manifest() {
  _mf="$T/m/$1@$3.plist"
  [ ! -f "$_mf" ] || return 0
  _base="${MAVERGREEN_RELEASES:-https://github.com}/Mavergreen/$2/releases/download/$3"
  _cache="${MAVERGREEN_PKG_CACHE:-$HOME/Library/Caches/mavergreen-pkgs}/$2/$3"
  _w="$T/w/$1@$3"
  rm -rf "$_w"; mkdir -p "$_w" "$_cache" || die "$1 $3: cannot make $_w or $_cache"
  shipyard_curl --quiet "$_base/SHA256SUMS" "$_w/SHA256SUMS" || die "$1 $3: could not fetch $_base/SHA256SUMS"
  _tar="$1-$3-linux-x86_64.tar.gz"
  if [ "$HOST" = linux ] && [ "$(uname -m)" = x86_64 ] && listed "$_w/SHA256SUMS" "$_tar"; then
    _tc="${MAVERGREEN_TAR_CACHE:-$HOME/.cache/mavergreen-tars}/$2/$3"
    shipyard_fetch_verified "$_base/$_tar" "$_ls" "$_tc" "$_tar" || die "$1 $3: could not fetch and verify $_base/$_tar"
    mkdir "$_w/t" || die "$1 $3: cannot make $_w/t"
    if tar -xzf "$_tc/$_tar" -C "$_w/t" "opt/mavergreen/$1/mavergreen.plist" 2>/dev/null \
      && [ -f "$_w/t/opt/mavergreen/$1/mavergreen.plist" ]; then
      [ "$("$STEVEDORE" plist get "$_w/t/opt/mavergreen/$1/mavergreen.plist" identifier 2>/dev/null || :)" = "$4" ] \
        || die "$1 $3: the mavergreen.plist in $_tar is not $4's"
      mv "$_w/t/opt/mavergreen/$1/mavergreen.plist" "$_mf" || die "$1 $3: cannot keep the mavergreen.plist in $_tar"
      : > "${_mf%.plist}.pkgpath"
      cp "$_w/SHA256SUMS" "${_mf%.plist}.sums" || die "$1 $3: cannot keep $_base/SHA256SUMS"
      rm -rf "$_w"; return 0
    fi
    _cache="${MAVERGREEN_PKG_CACHE:-$HOME/Library/Caches/mavergreen-pkgs}/$2/$3"
  fi
  reg feed "$1"; _xml="${_rv##*/}"
  if listed "$_w/SHA256SUMS" "$_xml"; then
    shipyard_fetch_verified "$_base/$_xml" "$_ls" "$_cache" "$_xml" || die "$1 $3: could not fetch and verify $_base/$_xml"
    cp "$_cache/$_xml" "$_w/appcast" || die "$1 $3: cannot copy $_xml"
  elif shipyard_curl --quiet "$_base/$_xml" "$_w/appcast" 2>/dev/null; then
    die "$1 $3: $_xml is not listed (once) in $_base/SHA256SUMS"
  else
    case "$?:$shipyard_curl_http" in
      22:404|37:*) rm -f "$_w/appcast" ;;
      *) die "$1 $3: could not fetch $_base/$_xml" ;;
    esac
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
  _pc="$_cache/$_asset.$1.$_ls.mavergreen.plist"
  if [ -f "$_pc" ] && [ "$("$STEVEDORE" plist get "$_pc" identifier 2>/dev/null || :)" = "$4" ]; then
    [ "$HOST" = linux ] || shipyard_fetch_verified "$_base/$_asset" "$_ls" "$_cache" "$_asset" \
      || die "$1 $3: could not fetch and verify $_base/$_asset"
    cp "$_pc" "$_mf" || die "$1 $3: cannot copy $_pc"
    printf '%s\n' "$_cache/$_asset" > "${_mf%.plist}.pkgpath"
    cp "$_w/SHA256SUMS" "${_mf%.plist}.sums" || die "$1 $3: cannot keep $_base/SHA256SUMS"
    rm -rf "$_w"; return 0
  fi
  for _tool in gzip cpio; do
    command -v "$_tool" > /dev/null 2>&1 || die "$1 $3: needs $_tool to read the mavergreen.plist in $_asset; install the $_tool package"
  done
  shipyard_fetch_verified "$_base/$_asset" "$_ls" "$_cache" "$_asset" \
    || die "$1 $3: could not fetch and verify $_base/$_asset"
  "$STEVEDORE" expand "$_cache/$_asset" "$_w/x" > /dev/null || die "$1 $3: could not expand $_cache/$_asset"
  _m="$(grep -lF "identifier=\"$4\"" "$_w"/x/PackageInfo "$_w"/x/*/PackageInfo 2>/dev/null || :)"
  [ "$(printf '%s\n' "$_m" | grep -c .)" = 1 ] || die "$1 $3: expected one component $4 in $_asset"
  printf '%s\n' "$_cache/$_asset" > "${_mf%.plist}.pkgpath"
  cp "$_w/SHA256SUMS" "${_mf%.plist}.sums" || die "$1 $3: cannot keep $_base/SHA256SUMS"
  mkdir "$_w/p" || die "$1 $3: cannot make $_w/p"
  ( cd "$_w/p" && { if gzip -dc "$(dirname "$_m")/Payload"; then echo 0 > "$_w/gzip.rc"; else echo $? > "$_w/gzip.rc"; fi; } \
    | { if cpio -id --quiet "*usr/local/mavergreen/$1/mavergreen.plist"; then echo 0 > "$_w/cpio.rc"; else echo $? > "$_w/cpio.rc"; fi; } ) 2>/dev/null || :
  [ "$(cat "$_w/cpio.rc" 2>/dev/null || :)" = 0 ] || die "$1 $3: could not unpack the Payload of $4 in $_asset"
  [ "$(cat "$_w/gzip.rc" 2>/dev/null || :)" = 0 ] || die "$1 $3: could not decompress the Payload of $4 in $_asset"
  [ -f "$_w/p/usr/local/mavergreen/$1/mavergreen.plist" ] \
    || die "$1 $3: $4 in $_asset installs no usr/local/mavergreen/$1/mavergreen.plist"
  cp "$_w/p/usr/local/mavergreen/$1/mavergreen.plist" "$_pc.$$" && mv -f "$_pc.$$" "$_pc" || rm -f "$_pc.$$"
  mv "$_w/p/usr/local/mavergreen/$1/mavergreen.plist" "$_mf" || die "$1 $3: cannot keep the mavergreen.plist of $4"
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
    printf '%s\n' "$fl" > "$T/carry/$s"
    exit 3
  fi
  reg repo "$s" "$by"; repo=$_rv
  reg identifier "$s" "$by"; id=$_rv
  prov="$(sh "$SELF/product-name.sh" provisioner "$s")" || case $? in
    1) prov="" ;;
    *) die "the registry cannot look up the provisioner of $s" ;;
  esac
  sdkarch "$s"
  [ -z "$_sa" ] || prov="fetch_sdk.sh --arch $_sa"
  inst=""; ip="$ROOT/usr/local/mavergreen/$s/mavergreen.plist"
  if [ -f "$ip" ]; then mver "$ip" "$s"; inst=$_v; fi
  src=""
  if [ -f "$T/pin/$s" ]; then
    [ -z "$prov" ] || die "$s is set up by '$prov', not released: name its provider instead"
    tag="$(cat "$T/pin/$s")"
    manifest "$s" "$repo" "$tag" "$id"; src=$_mf; cp "${_mf%.plist}.pkgpath" "$T/pkg/$s"
    printf '%s\n' "$tag" > "$T/tag/$s"
    mver "$src" "$s"; v=$_v
    [ -z "$fl" ] || ge "$v" "$fl" "$s" || die "$s is named at $tag (version $v), below $s>=$fl${by:+ required by $by}"
    if [ "$inst" = "$v" ]; then act=keep; else act=install; fi
  elif [ -n "$inst" ] && { [ -z "$fl" ] || ge "$inst" "$fl" "$s"; }; then
    act=keep; v=$inst; src=$ip
  elif [ -n "$prov" ]; then
    [ -n "$_sa" ] || ( resolve "${prov%% *}" "" "$stack $s" ) || exit $?
    act=provision; v=-
  else
    tag="$(shipyard_latest_tag "$repo")" || die "$s: no latest release of Mavergreen/$repo${by:+ (required by $by)}"
    manifest "$s" "$repo" "$tag" "$id"; src=$_mf; cp "${_mf%.plist}.pkgpath" "$T/pkg/$s"
    printf '%s\n' "$tag" > "$T/tag/$s"
    mver "$src" "$s"; v=$_v
    [ -z "$fl" ] || ge "$v" "$fl" "$s" \
      || die "$s>=$fl${by:+ (required by $by)} cannot be met: the latest release of Mavergreen/$repo is $tag, version $v"
    act=install
  fi
  if [ -n "$src" ]; then
    mavergreen_requires "$STEVEDORE" "$src" "$T/err" > "$T/req.$s" || die "$s$(cat "$T/err")"
    while IFS= read -r r <&3; do
      rn="${r%%>=*}"; rf=""
      case "$r" in *'>='*) rf="${r#*>=}" ;; esac
      ( resolve "$rn" "$rf" "$stack $s" ) 3<&- || exit $?
    done 3< "$T/req.$s"
  fi
  printf '%s\n' "$v" > "$T/done/$s"
  case "$act" in
    provision) printf 'provision %s via %s\n' "$s" "$prov" ;;
    *) printf '%s %s %s\n' "$act" "$s" "$v" ;;
  esac >> "$T/plan"
}

# spec: tests/install-products-test.sh -- a pass's floors come only from the requirers it chose,
#       plus those that forced a restart
pass=0
while :; do
  pass=$((pass + 1))
  [ "$pass" -le 50 ] || die "the requires did not settle after 50 passes: $(cd "$T/carry" && for f in *; do printf '%s>=%s ' "$f" "$(cat "$f")"; done)"
  rm -rf "$T/done" "$T/floor"; mkdir "$T/done"; cp -R "$T/carry" "$T/floor"; : > "$T/plan"
  rc=0
  for p in "$@"; do
    ( resolve "${p%%@*}" "" "" ) || { rc=$?; break; }
  done
  [ "$rc" -eq 3 ] || break
done
[ "$rc" -eq 0 ] || exit 1
if [ -n "$DRY" ]; then cat "$T/plan"; exit 0; fi

record() { [ -z "${MAVERGREEN_INSTALLED:-}" ] || printf '%s %s\n' "$1" "$2" >> "$MAVERGREEN_INSTALLED"; }
if [ "$(id -u)" -eq 0 ] || ! command -v sudo > /dev/null 2>&1; then _sudo=""; _inst=installer; else _sudo=sudo; _inst="sudo installer"; fi
if [ "${SUDO+set}" != set ] && [ -n "$_sudo" ] && [ "$HOST" = linux ] && ! sudo -n true > /dev/null 2>&1; then _sudo=""; fi
SUDO="${SUDO-$_sudo}"; INSTALLER="${INSTALLER:-$_inst}"
prefix() {
  P="$ROOT/usr/local/mavergreen/$1"; _wd="$ROOT/usr/local/mavergreen/.install-products/$1"
  if [ ! -d "$_wd" ] || [ ! -w "$_wd" ]; then
    if [ -n "$SUDO" ]; then
      $SUDO mkdir -p "$_wd" && $SUDO chown "$(id -u):$(id -g)" "$_wd" || die "$1: cannot make $_wd, owned by $(id -u):$(id -g)"
    else
      { mkdir -p "$_wd" 2> /dev/null && [ -w "$_wd" ]; } \
        || die "$1: cannot make $P: install-products needs root, sudo, or a writable $ROOT/usr/local/mavergreen"
    fi
  fi
  _ps=""
  if [ ! -w "${P%/*}" ] || { [ -d "$P" ] && [ ! -w "$P" ]; }; then
    [ -n "$SUDO" ] || die "$1: cannot replace $P: install-products needs root, sudo, or a writable $ROOT/usr/local/mavergreen"
    _ps=$SUDO
  fi
  _lf="$_wd/lock"; _wt=0
  until ( set -C; echo $$ > "$_lf" ) 2>/dev/null; do
    _hp="$(cat "$_lf" 2>/dev/null || :)"
    case "$_hp" in
      ''|*[!0-9]*) : ;;
      *) ps -p "$_hp" > /dev/null 2>&1 || { [ "$(cat "$_lf" 2>/dev/null || :)" != "$_hp" ] || rm -f "$_lf"; continue; } ;;
    esac
    [ "$_wt" -lt "${SHIPYARD_LOCK_WAIT:-900}" ] || die "$1: $_lf is still held${_hp:+ by process $_hp} after ${_wt}s"
    sleep 1; _wt=$((_wt + 1))
  done
  lk=$_lf
  if [ "$("$STEVEDORE" plist get "$P/mavergreen.plist" version 2>/dev/null || :)" = "$2" ]; then
    echo "install-products: $1 $2 is already at $P" >&2
    rm -f "$lk"; lk=""; return 1
  fi
  stg="$(mktemp -d "$_wd/stage.XXXXXX")" || die "$1: cannot stage in $_wd"
}
commit() {
  [ -f "$stg/tree/mavergreen.plist" ] || die "$1: the staged tree has no mavergreen.plist"
  chmod 755 "$stg/tree" || die "$1: cannot open the staged tree to every user"
  if [ -e "$P" ] || [ -h "$P" ]; then $_ps mv "$P" "$stg/old" || die "$1: cannot move the old $P aside"; fi
  if ! $_ps mv "$stg/tree" "$P"; then
    [ ! -e "$stg/old" ] || $_ps mv "$stg/old" "$P" || :
    die "$1: cannot move the new tree into $P"
  fi
  rm -rf "$stg" 2> /dev/null || [ -z "$_ps" ] || $_ps rm -rf "$stg" || :
  stg=""
  rm -f "$lk"; lk=""
}
linux_install() {
  _tag="$(cat "$T/tag/$1")"; _pkg="$(cat "$T/pkg/$1")"; _tar="$1-$_tag-linux-x86_64.tar.gz"
  prefix "$1" "$2" || return 0
  if listed "$T/m/$1@$_tag.sums" "$_tar"; then
    [ "$(uname -m)" = x86_64 ] || die "$1 $2: the release's Linux archive is $_tar, and this host is $(uname -m)"
    echo "install-products: installing $1 $2 from $_tar into $P" >&2
    sh "$SELF/fetch_product_tar.sh" "$1" "$_tag" "$stg/tree" > /dev/null || die "$1 $2: could not fetch, verify and unpack $_tar"
    rm -f "$stg/tree/.mavergreen-archive-sha256"
    cp "$T/m/$1@$_tag.plist" "$stg/tree/mavergreen.plist" || die "$1 $2: cannot copy its mavergreen.plist"
  else
    echo "install-products: installing $1 $2 from the payload of $_pkg into $P" >&2
    sh "$SELF/fetch_product_pkg.sh" --asset "${_pkg##*/}" "$1" "$_tag" "$stg/tree" > /dev/null \
      || die "$1 $2: the release lists no $_tar, and fetch_product_pkg.sh could not extract usr/local/mavergreen/$1 from $_pkg"
  fi
  commit "$1"
}
linux_sdk() {
  sdkarch "$1"
  reg repo "$1"; _tag="$(shipyard_latest_tag "$_rv")" || die "$1: no latest release of Mavergreen/$_rv to version it by"
  case "$_sver" in 10.[0-9]|10.1[01]) _sn="Mac OS X $_sver SDK" ;; *) _sn="macOS $_sver SDK" ;; esac
  prefix "$1" "$_tag" || return 0
  _sdk="$(MAVERICKS_SDK_SETTINGS_JSON='' sh "$SELF/fetch_sdk.sh" --arch "$_sa")" || die "$1: fetch_sdk.sh --arch $_sa failed"
  _st="$stg/root/usr/local/mavergreen/$1"
  mkdir -p "$_st/SDKs" && cp -RP "$_sdk" "$_st/SDKs/$_sdir" || die "$1: cannot copy $_sdk"
  if _js="$(shipyard_sdk_settings_json "$_sa")"; then
    printf '%s\n' "$_js" > "$_st/SDKs/$_sdir/SDKSettings.json" && chmod 644 "$_st/SDKs/$_sdir/SDKSettings.json" \
      || die "$1: cannot write SDKSettings.json"
  fi
  sh "$SELF/render-manifest.sh" --stage "$stg/root" --product "$1" --name "$_sn" --version "$_tag" >&2 \
    || die "$1: cannot write its mavergreen.plist"
  mv "$_st" "$stg/tree" || die "$1: cannot stage its tree"
  commit "$1"
}
while read -r act s rest; do
  case "$act" in
    keep) v=$rest ;;
    install)
      v=$rest; pkg="$(cat "$T/pkg/$s")"
      if [ "$HOST" = linux ]; then linux_install "$s" "$v"; record "$s" "$v"; continue; fi
      echo "install-products: installing $s $v from $pkg into ${ROOT:-/}" >&2
      # shellcheck disable=SC2086
      $INSTALLER -pkg "$pkg" -target "${ROOT:-/}" < /dev/null >&2 || die "$s $v: the installer failed on $pkg"
      ;;
    provision)
      cmd="${rest#via }"
      echo "install-products: provisioning $s via $cmd" >&2
      pm="$ROOT/usr/local/mavergreen/$s/mavergreen.plist"
      if [ "$HOST" = linux ] && [ "${cmd%% *}" = fetch_sdk.sh ]; then
        linux_sdk "$s"
      else
        before=""; [ ! -f "$pm" ] || before="$(cksum < "$pm")"
        # shellcheck disable=SC2086
        $SUDO $cmd < /dev/null >&2 || die "$s: '$cmd' failed"
        [ -f "$pm" ] || die "$s: '$cmd' left no $pm"
        [ -z "$before" ] || [ "$before" != "$(cksum < "$pm")" ] || die "$s: '$cmd' left the existing $pm unchanged"
      fi
      mver "$pm" "$s"; v=$_v
      if [ -f "$T/floor/$s" ]; then
        fl="$(cat "$T/floor/$s")"
        ge "$v" "$fl" "$s" || die "$s>=$fl cannot be met: '$cmd' provisioned version $v"
      fi
      ;;
  esac
  record "$s" "$v"
done < "$T/plan"
