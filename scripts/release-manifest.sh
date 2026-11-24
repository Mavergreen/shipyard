#!/bin/sh
# platform: host-agnostic
#   usage: release-manifest.sh DIST VERSION REPO_ROOT
#          Prints a release's build facts, the RELEASE-MANIFEST.txt other repos read, sorted:
#            shipyard <version>                 $SHIPYARD_VERSION, else shipyard-version.sh's FULL
#            ingredient <name> <pin>            line 1 of .mavergreen/ingredients/<name>/VERSION, else PIN
#            ingredient <name> from <parent>    for an ingredient with a from file
#            requires <short> <dep> <kind> <min|->
#            relocatable <short>                each product a relocatable deviation's scope names; a
#                                               scope of * is a consumer's, for every ingredient, and names none
#            dylib <short> <install-name>       each LC_ID_DYLIB of each Mach-O in DIST/<short>-<VERSION>.pkg,
#                                               but in components dev.mavergreen.base and dev.mavergreen.mavergreen
#          An ingredient with neither file is left out. Never normalized and never compared. Exit 0; 1 on
#          an unreadable artifact or a Mach-O reader that is missing or fails; 2 on usage.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Reproducible builds" -- build
#       facts are published beside the content manifest and never decide a release, so an ingredient
#       bump that changes nothing installed still skips.
set -eu
LC_ALL=C; export LC_ALL
SELF="$(cd "$(dirname "$0")" && pwd)"
usage() { echo "usage: release-manifest.sh DIST VERSION REPO_ROOT" >&2; exit 2; }
[ $# -eq 3 ] && [ -n "$2" ] && [ -d "$1" ] && [ -d "$3" ] || usage
DIST="$(cd "$1" && pwd)"; V0="${2#v}"; ROOT="$(cd "$3" && pwd)"
MAVERGREEN_REPO_ROOT="$ROOT"; export MAVERGREEN_REPO_ROOT
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/pkg-tree.sh"
. "$SELF/deviation-reason.sh"
die() { echo "release-manifest: $1" >&2; exit 1; }
w="$(mktemp -d "${TMPDIR:-/tmp}/release-manifest.XXXXXX")"; trap 'af_rm "$w"' EXIT
rows="$w/rows"; : > "$rows"

sv="${SHIPYARD_VERSION:-}"
[ -n "$sv" ] || sv="$(sh "$SELF/shipyard-version.sh" | sed -n 's/^FULL=//p')"
[ -n "$sv" ] || die "no shipyard version: set SHIPYARD_VERSION"
printf 'shipyard %s\n' "$sv" >> "$rows"

for i in $(mg_list ingredients); do
  [ -d "$(mg_dir)/ingredients/$i" ] || continue
  if p="$(mg_value "ingredients/$i/from")"; then printf 'ingredient %s from %s\n' "$i" "$p" >> "$rows"
  elif p="$(mg_value "ingredients/$i/VERSION")" || p="$(mg_value "ingredients/$i/PIN")"; then
    printf 'ingredient %s %s\n' "$i" "$p" >> "$rows"
  fi
done

shipyard_deviations "$ROOT" > /dev/null || die "cannot read $ROOT/.mavergreen/deviations/"
products="$(mg_list products)"
for s in $products; do
  for d in $(mg_list "products/$s/requires"); do
    k="$(mg_value "products/$s/requires/$d/kind")" || die "products/$s/requires/$d has no kind"
    m="$(mg_value "products/$s/requires/$d/min")" || m=-
    printf 'requires %s %s %s %s\n' "$s" "$d" "$k" "$m" >> "$rows"
  done
  while IFS= read -r g; do
    [ -n "$g" ] && [ "$g" != '*' ] || continue
    case "$s" in $g) printf 'relocatable %s\n' "$s" >> "$rows"; break ;; esac
  done <<EOF
$(shipyard_deviation_scopes relocatable)
EOF
done

for s in $products; do
  pkg="$DIST/$s-$V0.pkg"
  [ -f "$pkg" ] || continue
  rc=0; af_pkg_tree "$pkg" "$w/x" || rc=$?
  [ "$rc" -eq 0 ] || die "cannot expand $pkg${AF_WHY:+: $AF_WHY}"
  find "$AF_TREE" -name '*.root' -prune -o -name PackageInfo -type f -print > "$w/infos"
  : > "$w/payloads"
  while IFS= read -r pi; do
    id="$(sed -n '/<pkg-info/ s/.*[[:space:]]identifier="\([^"]*\)".*/\1/p' "$pi" | head -n 1)"
    case "$id" in dev.mavergreen.base|dev.mavergreen.mavergreen) continue ;; esac
    printf '%s/Payload\n' "${pi%/PackageInfo}" >> "$w/payloads"
  done < "$w/infos"
  while IFS= read -r pl; do
    [ -s "$pl" ] || continue
    af_unpack_payload "$pl" || die "cannot unpack a payload of $pkg"
    ( cd "$AF_ROOT" && find . -type f ) > "$w/files"
    while IFS= read -r f; do
      [ "$(af_macho_kind "$AF_ROOT/$f")" = strict ] || continue
      out="$(sh "$SELF/macho-loads.sh" "$AF_ROOT/$f" 2> "$w/err")" \
        || die "cannot read the load commands of ${f#./} in $pkg: $(tail -n 1 "$w/err")"
      printf '%s\n' "$out" | awk -v s="$s" '$2 == "id" { sub(/^[^ ]+ id /, ""); print "dylib", s, $0 }' >> "$rows"
    done < "$w/files"
  done < "$w/payloads"
done
sort -u "$rows"
