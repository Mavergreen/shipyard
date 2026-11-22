#!/bin/sh
# platform: host-agnostic
#   usage: build-equivalence.sh [--repo DIR] A B
#          Compares two builds of one product. A and B are each a flat .pkg (expanded with the pinned
#          stevedore, every component's payload unpacked at its install location) or a directory holding
#          a staged payload tree. Files and symlinks are paired by path relative to the install root,
#          after one normalisation: in a file name, "-<16 lowercase hex>." compares as "-H.". Two
#          names in one build that normalise alike are exit 2, never a guess.
#          Levels: bytes (contents differ), interface (a Mach-O or archive whose interface differs),
#          meta (a symlink target or the executable bit differs), only-a, only-b. Identical files are
#          not printed. stdout: one line per difference, "<level>TAB<path>TAB<excusing glob or ->",
#          sorted by path, an interface difference followed by indented detail lines; then
#          "unused TAB - TAB <glob>" for each entry that excused nothing. stderr: "build-equivalence:
#          N differences, M excused, K unused".
#          Entries come from DIR's (default .) INGREDIENTS.md through deviations.sh:
#          build-equivalence:<glob> excuses bytes, build-equivalence-interface:<glob> excuses interface
#          and bytes. meta, only-a and only-b are never excusable. A glob is a shell case pattern over
#          the normalised path. A DIR without INGREDIENTS.md declares no entries.
#          Exit 0 every difference excused and no entry unused; 1 an unexcused difference or an unused
#          entry; 2 misuse or an input it cannot read.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
LC_ALL=C; export LC_ALL
TAB="$(printf '\t')"
NL='
'
die() { echo "build-equivalence: $*" >&2; exit 2; }

# spec: tests/build-equivalence-test.sh -- a differing Mach-O or archive is compared here: one word, bytes or
#       interface, then indented detail lines; nonzero exit when a Mach-O cannot be read.
be_classify_macho() {
  echo bytes
}

be_magic() {
  case "$(od -An -tx1 -N8 "$1" 2>/dev/null | tr -d ' \n')" in
    feedface*|feedfacf*|cefaedfe*|cffaedfe*|cafebabe*|bebafeca*|213c617263683e0a) echo macho ;;
    *) echo other ;;
  esac
}

repo=.
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo needs a directory"; repo="$2"; shift 2 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[ $# -eq 2 ] || die "usage: build-equivalence.sh [--repo DIR] A B"
[ -d "$repo" ] || die "--repo $repo is not a directory"
for input in "$1" "$2"; do
  [ -d "$input" ] || [ -f "$input" ] || die "$input is neither a directory nor a .pkg"
done

work="$(mktemp -d "${TMPDIR:-/tmp}/build-equivalence.XXXXXX")"
trap 'rm -rf "$work"' EXIT

unpack() {
  _sd="$(sh "$SELF/fetch_stevedore.sh" 2>/dev/null)" || die "no stevedore to expand $1 with"
  "$_sd" expand "$1" "$work/expanded.$$" >/dev/null 2>&1 || die "$1 is not a pkg stevedore can expand"
  mkdir -p "$2"
  _found=0
  for _comp in "$work/expanded.$$" "$work"/expanded.$$/*; do
    [ -f "$_comp/Payload" ] || continue
    _found=1
    _loc="$(sed -n 's/.*install-location="\([^"]*\)".*/\1/p' "$_comp/PackageInfo" 2>/dev/null | head -1)"
    mkdir -p "$2/$_loc"
    ( cd "$2/$_loc" && gzip -dc "$_comp/Payload" | cpio -id >/dev/null 2>&1 ) || die "could not unpack $_comp/Payload of $1"
  done
  rm -rf "$work/expanded.$$"
  [ "$_found" -eq 1 ] || die "$1 holds no payload"
}

list() {
  _root="$1"; _side="$2"
  _bad="$(cd "$_root" && find . \( -type f -o -type l \) \( -name '*
*' -o -name "*$TAB*" \) -print | head -1)"
  [ -z "$_bad" ] || die "$_root holds a path with a newline or tab: $_bad"
  ( cd "$_root" && {
      find . -type l | sed 's|^\./||; s|$|'"$TAB"'l|'
      find . -type f -perm -100 | sed 's|^\./||; s|$|'"$TAB"'x|'
      find . -type f ! -perm -100 | sed 's|^\./||; s|$|'"$TAB"'f|'
    } ) | awk -F "$TAB" '
      BEGIN { re = "-"; for (i = 0; i < 16; i++) re = re "[0-9a-f]"; re = re "[.]" }
      {
        dir = ""; base = $1; n = 0
        for (i = length($1); i > 0; i--) if (substr($1, i, 1) == "/") { n = i; break }
        if (n > 0) { dir = substr($1, 1, n); base = substr($1, n + 1) }
        gsub(re, "-H.", base)
        print dir base "\t" $1 "\t" $2
      }' | sort -t "$TAB" -k1,1 > "$work/$_side.list"
  _dup="$(cut -f1 "$work/$_side.list" | uniq -d | head -1)"
  [ -z "$_dup" ] || die "two paths in $_root normalise to $_dup"
}

A="$1"; B="$2"
if [ -f "$A" ]; then unpack "$A" "$work/a"; A="$work/a"; fi
if [ -f "$B" ]; then unpack "$B" "$work/b"; B="$work/b"; fi
list "$A" a
list "$B" b

_entries="$(sh "$SELF/deviations.sh" "$repo")" || die "$repo/INGREDIENTS.md declares an entry deviations.sh refuses"
printf '%s\n' "$_entries" | awk '$1 == "build-equivalence" || $1 == "build-equivalence-interface" { print ++n "\t" $1 "\t" $2 }' > "$work/entries"
: > "$work/used"
: > "$work/out"

awk -F "$TAB" '
  FNR == NR { ra[$1] = $2; ka[$1] = $3; next }
  { rb[$1] = $2; kb[$1] = $3 }
  END {
    for (k in ra) print k "\t" ra[k] "\t" ka[k] "\t" ((k in rb) ? rb[k] : ".") "\t" ((k in rb) ? kb[k] : ".")
    for (k in rb) if (!(k in ra)) print k "\t.\t.\t" rb[k] "\t" kb[k]
  }' "$work/a.list" "$work/b.list" | sort -t "$TAB" -k1,1 > "$work/union"

set -f
excuser=-
excuse() {
  excuser=-
  case "$1" in bytes|interface) ;; *) return 0 ;; esac
  while IFS="$TAB" read -r _en _ek _eg; do
    case "$2" in $_eg) ;; *) continue ;; esac
    [ "$_ek" = build-equivalence-interface ] || [ "$1" = bytes ] || continue
    echo "$_en" >> "$work/used"
    [ "$excuser" != - ] || excuser="$_eg"
  done < "$work/entries"
}

ndiff=0; nex=0; nunused=0
while IFS="$TAB" read -r n ra ka rb kb; do
  level=same; detail=
  if [ "$ra" = . ]; then level=only-b
  elif [ "$rb" = . ]; then level=only-a
  elif [ "$ka" = l ] || [ "$kb" = l ]; then
    if [ "$ka" = l ] && [ "$kb" = l ] && [ "$(readlink "$A/$ra")" = "$(readlink "$B/$rb")" ]; then :; else level=meta; fi
  elif [ "$ka" != "$kb" ]; then level=meta
  elif ! cmp -s "$A/$ra" "$B/$rb"; then
    if [ "$(be_magic "$A/$ra")" = macho ] || [ "$(be_magic "$B/$rb")" = macho ]; then
      _res="$(be_classify_macho "$A/$ra" "$B/$rb")" || die "cannot compare $n"
      level="$(printf '%s\n' "$_res" | sed -n 1p)"
      detail="$(printf '%s\n' "$_res" | sed 1d)"
      case "$level" in bytes|interface) ;; *) die "be_classify_macho said '$level' for $n" ;; esac
    else
      level=bytes
    fi
  fi
  [ "$level" != same ] || continue
  excuse "$level" "$n"
  ndiff=$((ndiff + 1))
  [ "$excuser" = - ] || nex=$((nex + 1))
  printf '%s\t%s\t%s\n' "$level" "$n" "$excuser" >> "$work/out"
  [ -z "$detail" ] || printf '%s\n' "$detail" >> "$work/out"
done < "$work/union"

while IFS="$TAB" read -r _en _ek _eg; do
  grep -qx "$_en" "$work/used" && continue
  nunused=$((nunused + 1))
  printf 'unused\t-\t%s\n' "$_eg" >> "$work/out"
done < "$work/entries"

cat "$work/out"
echo "build-equivalence: $ndiff differences, $nex excused, $nunused unused" >&2
[ "$ndiff" -eq "$nex" ] && [ "$nunused" -eq 0 ]
