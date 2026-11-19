#!/bin/sh
# platform: host-agnostic -- reads Mach-O through NM, LIPO, OTOOL and AR (clang22's llvm-nm, llvm-lipo, llvm-otool and llvm-ar off macOS)
#   usage: [NM=<nm>] [LIPO=<lipo>] [OTOOL=<otool>] [AR=<ar>] macho-cxxabi.sh FILE
#          Prints, per slice of FILE, "<arch> defines <symbol> <visible|hidden>" for each symbol it defines
#          that matches scripts/cxxabi-machinery.txt, whether exported or not (a private external, or a
#          non-external symbol of a linked image, is hidden), and "<arch> loads <path>" for each dylib it
#          loads or re-exports whose basename starts libc++abi. A static archive is read member by member;
#          a member that is not Mach-O (an rlib's lib.rmeta) is skipped, a bitcode member exits 4, and an
#          archive with no Mach-O member is not Mach-O. An old toolchain's
#          "<symbol>.eh" frame label counts as <symbol>.
#          Exit 0; 1 if FILE is not Mach-O; 2 on a usage error; 4 if a reader is missing or failed,
#          or a member with Mach-O magic could not be read.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/mavergreen-meta.sh"
. "$SELF/lib/name-rules.sh"
. "$SELF/lib/macho-tools.sh"
mach_tool LIPO 2>/dev/null || :; mach_tool OTOOL 2>/dev/null || :
mach_tool NM 2>/dev/null || NM=nm; export NM
[ "$#" -eq 1 ] && [ -f "$1" ] || { echo "usage: macho-cxxabi.sh FILE" >&2; exit 2; }
f="$1"
_tmp="${TMPDIR:-/tmp}"
t="$(mktemp -d "${_tmp%/}/macho-cxxabi.XXXXXX")"; trap 'rm -rf "$t"' EXIT
reader_died() { echo "macho-cxxabi: $1 could not read $f" >&2; cat "$t/err" >&2; exit 4; }
: > "$t/err"
if [ -z "${AR:-}" ]; then
  case "$NM" in */llvm-nm) [ -x "${NM%/*}/llvm-ar" ] && AR="${NM%/*}/llvm-ar" ;; esac
  AR="${AR:-ar}"
fi
case "$NM" in *llvm-nm) nm_flags=--no-llvm-bc ;; *) nm_flags= ;; esac
for _r in "$NM" "${LIPO:-lipo}" "${OTOOL:-otool}"; do
  command -v "$_r" >/dev/null 2>&1 || reader_died "$_r (not found)"
done
is_archive() { [ "$(dd if="$1" bs=8 count=1 2>/dev/null)" = '!<arch>' ]; }
thin_arch() {
  set -- $(od -An -tx1 -N12 "$1")
  [ "$#" -eq 12 ] || return 1
  case "$1$2$3$4:$5$6$7$8" in
    cffaedfe:07000001) if [ "$9" = 08 ]; then echo x86_64h; else echo x86_64; fi ;;
    cffaedfe:0c000001) if [ "$9" = 02 ]; then echo arm64e; else echo arm64; fi ;;
    cefaedfe:07000000) echo i386 ;;
    *) return 1 ;;
  esac
}
is_bitcode() {
  case "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" in 4243c0de|dec0170b) return 0 ;; esac
  return 1
}
is_macho() {
  case "$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')" in
    cffaedfe|cefaedfe|feedfacf|feedface|cafebabe|bebafeca) return 0 ;;
  esac
  return 1
}
read_slice() {
  _s="$1"; _a="$2"
  "$NM" $nm_flags -Um "$_s" > "$t/nm" 2>"$t/err" || reader_died "$NM -Um"
  awk '/^[0-9a-f ]*\(/ && !/\):$/ {
         n = $0; sub(/ \(for [^)]*\)$/, "", n); sub(/.* /, "", n); sub(/\.eh$/, "", n)
         print n, ((/ external / && !/ private external /) ? "visible" : "hidden") }' "$t/nm" \
    | grep -E -f "$SELF/cxxabi-machinery.txt" | LC_ALL=C sort -u | sed "s/^/$_a defines /"
  "${OTOOL:-otool}" -l "$_s" > "$t/l" 2>"$t/err" || reader_died "${OTOOL:-otool} -l"
  awk -v a="$_a" '
    $1 == "cmd" { load = ($2 ~ /^LC_(LOAD|LOAD_WEAK|REEXPORT|LAZY_LOAD|LOAD_UPWARD)_DYLIB$/); next }
    load && $1 == "name" {
      p = $0; sub(/^[ \t]*name[ \t]+/, "", p); sub(/ \(offset [0-9]+\)$/, "", p)
      b = p; sub(/.*\//, "", b)
      if (index(b, "libc++abi") == 1) print a " loads " p
      load = 0
    }' "$t/l" | LC_ALL=C sort -u
}
read_member() {
if _ma="$(thin_arch "$1")"; then read_slice "$1" "$_ma"; return; fi
  _mi="$("${LIPO:-lipo}" -info "$1" 2>"$t/err")" || reader_died "${LIPO:-lipo} -info"
  _marchs="$(printf '%s\n' "$_mi" | sed -n 's/.*: //p' | xargs)"
  [ -n "$_marchs" ] || reader_died "${LIPO:-lipo} -info"
  for _ma in $_marchs; do
    _ms="$1"
    case "$_mi" in Architectures*) "${LIPO:-lipo}" -thin "$_ma" "$1" -output "$t/mt.$_ma" >/dev/null 2>"$t/err" || reader_died "${LIPO:-lipo} -thin $_ma"; _ms="$t/mt.$_ma" ;; esac
    read_slice "$_ms" "$_ma"
  done
}
read_archive() {
  case "$1" in /*) _ar="$1" ;; *) _ar="$PWD/$1" ;; esac
  "$AR" t "$_ar" > "$t/members" 2>"$t/err" || reader_died "$AR t"
  awk '{ c[$0]++; print c[$0] "\t" $0 }' "$t/members" > "$t/members.n"
  while IFS='	' read -r _c _name; do
    _d="$(mktemp -d "$t/m.XXXXXX")"
    if [ "$_c" -eq 1 ]; then ( cd "$_d" && "$AR" x "$_ar" "$_name" ); else ( cd "$_d" && "$AR" xN "$_c" "$_ar" "$_name" ); fi 2>"$t/err" || reader_died "$AR x $_name"
    for _m in "$_d"/* "$_d"/.[!.]*; do
      [ -f "$_m" ] || continue
      if is_bitcode "$_m"; then echo "macho-cxxabi: bitcode member $_name of $f cannot be measured" >&2; exit 4; fi
      if is_macho "$_m"; then _seen=1; read_member "$_m"; fi
    done
  done < "$t/members.n"
}
if is_archive "$f"; then
  _seen=0; read_archive "$f" > "$t/res"; [ "$_seen" -eq 1 ] || exit 1
  LC_ALL=C sort -u "$t/res"
  exit 0
fi
info="$("${LIPO:-lipo}" -info "$f" 2>/dev/null)" || exit 1
archs="$(printf '%s\n' "$info" | sed -n 's/.*: //p' | xargs)"
[ -n "$archs" ] || exit 1
for a in $archs; do
  s="$f"
  case "$info" in Architectures*) "${LIPO:-lipo}" -thin "$a" "$f" -output "$t/$a" >/dev/null 2>"$t/err" || reader_died "${LIPO:-lipo} -thin $a"; s="$t/$a" ;; esac
  if is_archive "$s"; then _seen=0; read_archive "$s" > "$t/res"; [ "$_seen" -eq 1 ] || exit 1; LC_ALL=C sort -u "$t/res"; else read_slice "$s" "$a"; fi
done
