#!/bin/sh
# platform: host-agnostic
#   usage: content-manifest.sh DIST VERSION REPO_ROOT
#          Prints the installed content of the release in DIST, one row per line, sorted and unique:
#            file <artifact> <path> <mode> <sha256>
#            link <artifact> <path> <target>
#            dir <artifact> <path> <mode>
#            meta <artifact> identifier|install-location <value>, and script:<component>:<name> <sha256>,
#                 for each component but dev.mavergreen.base and dev.mavergreen.mavergreen
#            meta <artifact> floor|before|arch-rule|host-architectures <value>, from the Distribution
#            meta <short> feed-min-os <floor>, meta <short> feed-url <url>, meta <short> requires <dep> <kind> <min|->
#          for every DIST/*.pkg and DIST/*.tar.gz but *-dSYM.tar.gz. <artifact> is the file name less
#          -<VERSION>, VERSION less one leading v. A pkg's paths are relative to /, a tarball's to its
#          root; modes are four octal digits; paths and targets write "%" and space as %25 and %20. Each
#          occurrence of VERSION (less its v) and of its mavergreen_build_version, in paths, targets,
#          script and file bytes, reads @VERSION@. A path a reproducible deviation's scope matches (other
#          than *) gets no row. Products are REPO_ROOT's .mavergreen/products/. Exit 1, printing nothing,
#          on an artifact that cannot be read, a path holding a newline or a tab, or no python3 >= 3.9;
#          2 on usage.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Reproducible builds" -- the
#       content manifest is what a release decision compares, so a rebuild that changes nothing a user
#       installs publishes nothing.
set -eu
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
usage() { echo "usage: content-manifest.sh DIST VERSION REPO_ROOT" >&2; exit 2; }
[ $# -eq 3 ] && [ -n "$2" ] && [ -d "$1" ] && [ -d "$3" ] || usage
DIST="$(cd "$1" && pwd)"; VERSION="$2"; ROOT="$(cd "$3" && pwd)"
MAVERGREEN_REPO_ROOT="$ROOT"; export MAVERGREEN_REPO_ROOT
SHIPYARD_CHECK_DIR="$SELF"
. "$SELF/lib/vercmp.sh"
. "$SELF/lib/py.sh"
. "$SELF/lib/arch-rules.sh"
. "$SELF/lib/pkg-tree.sh"
. "$SELF/deviation-reason.sh"
die() { echo "content-manifest: $1" >&2; exit 1; }

V0="${VERSION#v}"; BV="$(mavergreen_build_version "$VERSION")"
PY="$(chk_python3 2>&1)" || { printf '%s\n' "$PY" >&2; exit 1; }
hash() { PYTHONDONTWRITEBYTECODE=1 "$PY" "$SELF/content-hash.py" "$@"; }

w="$(mktemp -d "${TMPDIR:-/tmp}/content-manifest.XXXXXX")"; trap 'af_rm "$w"' EXIT
rows="$w/rows"; : > "$rows"
shipyard_deviations "$ROOT" > /dev/null || die "cannot read $ROOT/.mavergreen/deviations/"
shipyard_deviation_scopes reproducible | { grep -vx '\*' || :; } > "$w/scopes"

artifact() {
  case "$1" in
    *"-$V0"*) printf '%s%s\n' "${1%%"-$V0"*}" "${1#*"-$V0"}" | af_enc ;;
    *) printf '%s\n' "$1" | af_enc ;;
  esac
}

pkg_rows() {
  _pkg="$1"; _a="$2"
  _rc=0; af_pkg_tree "$_pkg" "$w/x" || _rc=$?
  [ "$_rc" -eq 0 ] || die "cannot expand $_pkg${AF_WHY:+: $AF_WHY}"
  if [ -f "$AF_TREE/Distribution" ]; then
    _fl="$(sed -n 's/.*<os-version[^>]*[[:space:]]min="\([^"]*\)".*/\1/p' "$AF_TREE/Distribution" | head -n 1)"
    set -- $(arch_read_distribution "$AF_TREE/Distribution")
    [ "$2" != none ] || set -- "$1" - "$3"
    printf 'meta %s floor %s\nmeta %s before %s\nmeta %s arch-rule %s\nmeta %s host-architectures %s\n' \
      "$_a" "${_fl:--}" "$_a" "$2" "$_a" "$3" "$_a" "$1" >> "$rows"
  fi
  find "$AF_TREE" -name '*.root' -prune -o -name PackageInfo -type f -print > "$w/infos"
  while IFS= read -r _pi; do
    _cd="${_pi%/PackageInfo}"
    _id="$(sed -n '/<pkg-info/ s/.*[[:space:]]identifier="\([^"]*\)".*/\1/p' "$_pi" | head -n 1)"
    [ -n "$_id" ] || die "$_pkg: $_pi names no identifier"
    case "$_id" in dev.mavergreen.base|dev.mavergreen.mavergreen) continue ;; esac
    _loc="$(sed -n '/<pkg-info/ s/.*[[:space:]]install-location="\([^"]*\)".*/\1/p' "$_pi" | head -n 1)"
    printf 'meta %s identifier %s\nmeta %s install-location %s\n' "$_a" "$_id" "$_a" "$(printf '%s\n' "${_loc:-/}" | af_enc)" >> "$rows"
    if [ -s "$_cd/Payload" ]; then
      af_unpack_payload "$_cd/Payload" || die "cannot unpack the payload of $_id in $_pkg"
      af_payload_modes "$_cd/Payload" > "$w/modes" || die "cannot list the payload of $_id in $_pkg"
      hash --rows "$_a" "$AF_ROOT" "$AF_LOC" "$w/modes" "$w/scopes" "$V0" ${BV:+"$BV"} >> "$rows" \
        || die "cannot read the payload of $_id in $_pkg"
    fi
    _sd=""
    if [ -d "$_cd/Scripts" ]; then _sd="$_cd/Scripts"
    elif [ -f "$_cd/Scripts" ]; then
      _sd="$_cd/Scripts.d"; mkdir -p "$_sd"
      af_unpack_scripts "$_cd/Scripts" "$_sd" || die "cannot unpack the scripts of $_id in $_pkg"
    fi
    [ -n "$_sd" ] || continue
    ( cd "$_sd" && find . -type f ) | sed 's|^\./||' > "$w/scripts"
    while IFS= read -r _s; do
      _h="$(hash "$_sd/$_s" "$V0" ${BV:+"$BV"})" || die "cannot read the script $_s of $_id in $_pkg"
      printf 'meta %s script:%s:%s %s\n' "$_a" "$_id" "$(printf '%s\n' "$_s" | af_enc)" "$_h" >> "$rows"
    done < "$w/scripts"
  done < "$w/infos"
}

tar_rows() {
  _t="$w/t/${1##*/}"; mkdir -p "$_t"
  ( umask 000; af_extract "$1" "$_t" ) || die "cannot extract $1"
  hash --rows "$2" "$_t" "" - "$w/scopes" "$V0" ${BV:+"$BV"} >> "$rows" || die "cannot read $1"
}

[ "$BV" != "$V0" ] || BV=""
for f in "$DIST"/*.pkg "$DIST"/*.tar.gz; do
  [ -f "$f" ] || continue
  b="${f##*/}"
  case "$b" in *-dSYM.tar.gz) continue ;; esac
  a="$(artifact "$b")"
  case "$b" in *.pkg) pkg_rows "$f" "$a" ;; *) tar_rows "$f" "$a" ;; esac
done

for s in $(mg_list products); do
  fl="$(mavergreen_floor "$s")" || die "cannot read $s's floor"
  url="$(sh "$SELF/updater-identity.sh" feed "$s")" || die "cannot derive $s's feed URL"
  printf 'meta %s feed-min-os %s\nmeta %s feed-url %s\n' "$s" "$fl" "$s" "$url" >> "$rows"
  for d in $(mg_list "products/$s/requires"); do
    k="$(mg_value "products/$s/requires/$d/kind")" || die "products/$s/requires/$d has no kind"
    m="$(mg_value "products/$s/requires/$d/min")" || m=-
    printf 'meta %s requires %s %s %s\n' "$s" "$d" "$k" "$m" >> "$rows"
  done
done
sort -u "$rows"
