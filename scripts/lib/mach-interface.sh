# platform: host-agnostic
#   usage: . scripts/lib/mach-nm.sh; . scripts/lib/mach-interface.sh
#          shipyard_rust_sym_normalize: a filter, one Mach-O symbol per line. First, on any line, LLVM's
#          trailing .llvm.<decimal> is set aside and comes back as .llvm.N; the rules below see the rest.
#          LLVM's _anon.<32 lowercase hex>.<n> reads _anon.H.<n>. A legacy Rust name
#          (__ZN...17h<16 hex>E) has its hash written H. A v0 name (__R...) has each crate root's
#          Cs<base62>_ disambiguator written Cs_, and each back-reference renumbered to its target's
#          offset in the rewritten name, so one target compares equal and two stay distinct. rustc's
#          metadata symbol (_rust_metadata_<crate>_<hash>, the hash 1 to 16 lowercase hex, unpadded) has
#          its hash written H; the hash is the part after the last underscore, so a crate name ending
#          _<hex> loses that part when no hash follows it, which rustc never emits. Every other line, a
#          single-underscore _R or _ZN (a C name), and a __R line that does not parse as v0 or whose
#          back-reference has no target, passes unchanged.
#          shipyard_mach_kind FILE: thin, fat, archive or other, from the magic bytes. cafebabe is fat only
#          when its big-endian slice count is below 0x2D; otherwise it is a Java class file.
#          shipyard_mach_interface FILE: FILE's interface, sorted, one "<arch> <fact>" per line: export
#          <sym> (not for MH_EXECUTE), import <sym>, dylib <n> <load|weak|reexport|upward|lazy> <path>, id
#          <install name>, rpath <n> <path>, minos <kind> <v>, sdk <kind> <v>, section <seg>,<sect>, where
#          <kind> is the load command (version_min_macosx, or build_version <platform>). Symbols pass through
#          shipyard_rust_sym_normalize; in dylib and id paths "-<16 lowercase hex>." reads "-H.". A static
#          archive prints only its Mach-O members' export and import lines; other members are skipped.
#          Readers: NM, else shipyard_mach_nm's llvm-nm; OTOOL and LIPO, else the llvm-otool and llvm-lipo
#          beside the chosen llvm-otool or llvm-nm, else an installed clang22's or clang22-cross's
#          (SHIPYARD_MG_PREFIX, default /usr/local/mavergreen); llvm-ar likewise. Never one from PATH.
#          Exit 0; 1 FILE is not Mach-O (an archive with no Mach-O member is not); 2 a reader is missing
#          or cannot read FILE, which stderr names.

shipyard_rust_sym_normalize() {
  awk '
    function peek() { return substr(s, p, 1) }
    function take(n) { out = out substr(s, p, n); p += n }
    function b62(   q) {
      q = p
      while (substr(s, p, 1) ~ /[0-9A-Za-z]/) p++
      if (substr(s, p, 1) != "_") { bad = 1; return "" }
      p++
      return substr(s, q, p - q)
    }
    function raw62(   q) { q = p; p++; b62(); out = out substr(s, q, p - q) }
    function undis(   q, n) {
      if (bad) return
      q = p
      if (peek() == "u") p++
      if (peek() == "0") { p++; n = 0 }
      else {
        n = 0
        if (peek() !~ /[1-9]/) { bad = 1; return }
        while (peek() ~ /[0-9]/) { n = n * 10 + peek(); p++ }
      }
      if (peek() == "_") p++
      if (p + n - 1 > length(s)) { bad = 1; return }
      p += n
      out = out substr(s, q, p - q)
    }
    function dis() { if (!bad && peek() == "s") raw62() }
    function backref(   d, i, n, m, e) {
      p++; d = b62()
      if (bad) return
      n = 0
      if (d != "_") {
        for (i = 1; i < length(d); i++) n = n * 62 + index(B62, substr(d, i, 1)) - 1
        n++
      }
      if (!(n in at)) { bad = 1; return }
      m = at[n]; e = "_"
      if (m > 0) { m--; e = ""; do { e = substr(B62, m % 62 + 1, 1) e; m = int(m / 62) } while (m > 0); e = e "_" }
      out = out "B" e
    }
    function mark() { if (!((p - 1) in at)) at[p - 1] = length(out) }
    function until_e(kind) {
      while (!bad && peek() != "E") {
        if (p > length(s)) { bad = 1; return }
        if (kind == "type") type(); else if (kind == "arg") genarg(); else dyntrait()
      }
      if (!bad) take(1)
    }
    function path(   c) { mark()
      if (bad || ++depth > 1000) { bad = 1; return }
      c = peek()
      if (c == "C") { take(1); if (peek() == "s") { p++; b62(); out = out "s_" } undis() }
      else if (c == "M") { take(1); dis(); path(); type() }
      else if (c == "X") { take(1); dis(); path(); type(); path() }
      else if (c == "Y") { take(1); type(); path() }
      else if (c == "N") { take(1); if (peek() !~ /[A-Za-z]/) { bad = 1; return } take(1); path(); dis(); undis() }
      else if (c == "I") { take(1); path(); until_e("arg") }
      else if (c == "B") backref()
      else bad = 1
      depth--
    }
    function genarg(   c) {
      c = peek()
      if (c == "L") raw62()
      else if (c == "K") { take(1); konst() }
      else type()
    }
    function konst(   c) { mark()
      c = peek()
      if (c == "p") take(1)
      else if (c == "B") backref()
      else {
        type()
        if (bad) return
        if (peek() == "n") take(1)
        while (peek() ~ /[0-9a-f]/) take(1)
        if (peek() != "_") { bad = 1; return }
        take(1)
      }
    }
    function type(   c) { mark()
      if (bad || ++depth > 1000) { bad = 1; return }
      c = peek()
      if (c != "" && index("abcdefhijlmnopstuvxyz", c)) take(1)
      else if (c == "A") { take(1); type(); konst() }
      else if (c == "S" || c == "P" || c == "O") { take(1); type() }
      else if (c == "T") { take(1); until_e("type") }
      else if (c == "R" || c == "Q") { take(1); if (peek() == "L") raw62(); type() }
      else if (c == "F") {
        take(1)
        if (peek() == "G") raw62()
        if (peek() == "U") take(1)
        if (peek() == "K") { take(1); if (peek() == "C") take(1); else undis() }
        until_e("type"); type()
      }
      else if (c == "D") {
        take(1)
        if (peek() == "G") raw62()
        until_e("dyn")
        if (peek() != "L") { bad = 1; return }
        raw62()
      }
      else if (c == "B") backref()
      else path()
      depth--
    }
    function dyntrait() {
      path()
      while (!bad && peek() == "p") { take(1); undis(); type() }
    }
    BEGIN {
      B62 = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
      legacy = "^__ZN.*17h"
      for (i = 0; i < 16; i++) legacy = legacy "[0-9a-f]"
      legacy = legacy "E$"
      anon = "^_anon\\."
      for (i = 0; i < 32; i++) anon = anon "[0-9a-f]"
      anon = anon "\\.[0-9]+$"
    }
    { sfx = "" }
    match($0, /\.llvm\.[0-9]+$/) { sfx = ".llvm.N"; $0 = substr($0, 1, RSTART - 1) }
    $0 ~ anon { print "_anon.H" substr($0, 39) sfx; next }
    $0 ~ legacy { print substr($0, 1, length($0) - 17) "HE" sfx; next }
    /^_rust_metadata_[A-Za-z0-9_]+$/ {
      h = $0; sub(/.*_/, "", h)
      if (h ~ /^[0-9a-f]+$/ && length(h) <= 16 && length($0) - length(h) > 16) { print substr($0, 1, length($0) - length(h)) "H" sfx; next }
    }
    /^__R/ {
      pre = "__R"; split("", at)
      s = substr($0, length(pre) + 1); p = 1; out = ""; bad = 0; depth = 0
      while (peek() ~ /[0-9]/) take(1)
      path()
      if (!bad && p <= length(s) && peek() !~ /[.$]/) path()
      if (!bad && p <= length(s)) { out = out substr(s, p); p = length(s) + 1 }
      if (bad || p != length(s) + 1) print $0 sfx; else print pre out sfx
      next
    }
    { print $0 sfx }'
}

shipyard_mach_kind() {
  _mk_h="$(od -An -tx1 -N8 "$1" 2>/dev/null | tr -d ' \n')"
  case "$_mk_h" in
    feedface*|feedfacf*|cefaedfe*|cffaedfe*) echo thin ;;
    cafebabe????????|cafebabf????????)
      if [ $((0x${_mk_h#cafebab?})) -lt 45 ]; then echo fat; else echo other; fi ;;
    213c617263683e0a) echo archive ;;
    *) echo other ;;
  esac
}

_mi_tool() {
  for _mt_r in "$_mi_O" "$_mi_N"; do
    case "$_mt_r" in */llvm-otool|*/llvm-nm) [ -x "${_mt_r%/*}/llvm-$1" ] && { printf '%s\n' "${_mt_r%/*}/llvm-$1"; return 0; } ;; esac
  done
  for _mt_d in clang22 clang22-cross; do
    _mt_t="${SHIPYARD_MG_PREFIX:-/usr/local/mavergreen}/$_mt_d/bin/llvm-$1"
    [ -x "$_mt_t" ] && { printf '%s\n' "$_mt_t"; return 0; }
  done
  echo "mach-interface: no pinned llvm-$1, neither beside OTOOL or NM nor in clang22 or clang22-cross under ${SHIPYARD_MG_PREFIX:-/usr/local/mavergreen}" >&2
  return 1
}

_mi_die() {
  echo "mach-interface: cannot read $_mi_f: $*" >&2
  [ ! -s "$_mi_t/err" ] || sed 's/^/  /' "$_mi_t/err" >&2
  exit 2
}

_mi_syms() {
  if [ "$3" = yes ]; then
    "$_mi_N" --no-llvm-bc -gU --defined-only -j "$1" > "$_mi_t/syms" 2> "$_mi_t/err" || _mi_die "$_mi_N -gU"
    shipyard_rust_sym_normalize < "$_mi_t/syms" | awk -v a="$2" '$0 != "" { print a " export " $0 }'
  fi
  "$_mi_N" --no-llvm-bc -u -j "$1" > "$_mi_t/syms" 2> "$_mi_t/err" || _mi_die "$_mi_N -u"
  shipyard_rust_sym_normalize < "$_mi_t/syms" | awk -v a="$2" '$0 != "" { print a " import " $0 }'
}

_mi_thin() {
  "$_mi_O" -hv "$1" > "$_mi_t/h" 2> "$_mi_t/err" || _mi_die "$_mi_O -hv"
  _mi_ft="$(awk '$1 ~ /^MH_(MAGIC|CIGAM)/ { print $5; exit }' "$_mi_t/h")"
  [ -n "$_mi_ft" ] || _mi_die "$_mi_O -hv shows no Mach header"
  _mi_a="${3:-}"
  if [ -z "$_mi_a" ]; then
    _mi_a="$(awk '$1 ~ /^MH_(MAGIC|CIGAM)/ { print $2 ":" $3; exit }' "$_mi_t/h")"
    case "$_mi_a" in
      I386:ALL) _mi_a=i386 ;;
      X86_64:ALL) _mi_a=x86_64 ;;
      X86_64:Haswell) _mi_a=x86_64h ;;
      ARM64:ALL) _mi_a=arm64 ;;
      ARM64:E) _mi_a=arm64e ;;
      *) _mi_die "$_mi_O -hv names cputype and cpusubtype $_mi_a, not i386, x86_64, x86_64h, arm64 or arm64e" ;;
    esac
  fi
  if [ "$2" = members ]; then _mi_syms "$1" "$_mi_a" yes; return 0; fi
  "$_mi_O" -l "$1" > "$_mi_t/l" 2> "$_mi_t/err" || _mi_die "$_mi_O -l"
  if [ "$_mi_ft" = EXECUTE ]; then _mi_syms "$1" "$_mi_a" no; else _mi_syms "$1" "$_mi_a" yes; fi
  awk -v a="$_mi_a" '
    function hash(x) { gsub(re, "-H.", x); return x }
    function vkind(   x) { x = tolower(cmd); sub(/^lc_/, "", x); return x }
    function arg(   x) { x = $0; sub(/^[ \t]*[a-z]+[ \t]+/, "", x); sub(/ \(offset [0-9]+\)$/, "", x); return x }
    BEGIN {
      re = "-"; for (i = 0; i < 16; i++) re = re "[0-9a-f]"; re = re "[.]"
      split("macos ios tvos watchos bridgeos maccatalyst iossimulator tvossimulator watchossimulator driverkit visionos visionossimulator", pl, " ")
      for (i = 1; i in pl; i++) pname[i] = pl[i]
    }
    $1 == "cmd" { cmd = $2; plat = "?"; next }
    $1 == "name" && cmd == "LC_ID_DYLIB" { print a " id " hash(arg()); cmd = ""; next }
    $1 == "name" && cmd ~ /^LC_(LOAD|LOAD_WEAK|REEXPORT|LOAD_UPWARD|LAZY_LOAD)_DYLIB$/ {
      k = "load"
      if (cmd == "LC_LOAD_WEAK_DYLIB") k = "weak"
      if (cmd == "LC_REEXPORT_DYLIB") k = "reexport"
      if (cmd == "LC_LOAD_UPWARD_DYLIB") k = "upward"
      if (cmd == "LC_LAZY_LOAD_DYLIB") k = "lazy"
      print a " dylib " (++nd) " " k " " hash(arg()); cmd = ""; next
    }
    $1 == "path" && cmd == "LC_RPATH" { print a " rpath " (++nr) " " arg(); cmd = ""; next }
    cmd ~ /^LC_VERSION_MIN_/ && $1 == "version" { print a " minos " vkind() " " $2; next }
    cmd ~ /^LC_VERSION_MIN_/ && $1 == "sdk" { print a " sdk " vkind() " " $2; next }
    cmd == "LC_BUILD_VERSION" && $1 == "platform" { plat = ($2 in pname) ? pname[$2] : tolower($2); next }
    cmd == "LC_BUILD_VERSION" && ($1 == "minos" || $1 == "sdk") { print a " " $1 " build_version " plat " " $2; next }
    $1 == "sectname" { sect = $2; next }
    $1 == "segname" && sect != "" { print a " section " $2 "," sect; sect = ""; next }' "$_mi_t/l"
}

_mi_archive() {
  case "$1" in /*) _ma_f="$1" ;; *) _ma_f="$PWD/$1" ;; esac
  _ma_d="$(mktemp -d "$_mi_t/ar.XXXXXX")" || _mi_die "mktemp"
  "$_mi_A" t "$_ma_f" > "$_ma_d/names" 2> "$_mi_t/err" || _mi_die "$_mi_A t"
  awk '{ print (++n[$0]) "\t" $0 }' "$_ma_d/names" > "$_ma_d/members"
  while IFS="$(printf '\t')" read -r _ma_n _ma_m; do
    rm -rf "$_ma_d/x"; mkdir "$_ma_d/x"
    ( cd "$_ma_d/x" && "$_mi_A" xN "$_ma_n" "$_ma_f" "$_ma_m" ) 2> "$_mi_t/err" || _mi_die "$_mi_A x $_ma_m"
    _ma_x="$_ma_d/x/${_ma_m##*/}"
    [ -f "$_ma_x" ] || _mi_die "$_mi_A x $_ma_m wrote no $_ma_x"
    case "$(shipyard_mach_kind "$_ma_x")" in
      thin|fat) _mi_seen=1; _mi_file "$_ma_x" members ;;
    esac
  done < "$_ma_d/members"
}

_mi_file() {
  case "$(shipyard_mach_kind "$1")" in
    thin) _mi_thin "$1" "$2" ;;
    archive) _mi_archive "$1" ;;
    fat)
      "$_mi_L" -archs "$1" > "$_mi_t/archs" 2> "$_mi_t/err" || _mi_die "$_mi_L -archs"
      _mf_as="$(cat "$_mi_t/archs")"
      [ -n "$_mf_as" ] || _mi_die "$_mi_L -archs names no architecture"
      for _mf_a in $_mf_as; do
        _mf_s="$(mktemp "$_mi_t/slice.XXXXXX")" || _mi_die "mktemp"
        "$_mi_L" -thin "$_mf_a" "$1" -output "$_mf_s" 2> "$_mi_t/err" || _mi_die "$_mi_L -thin $_mf_a"
        case "$(shipyard_mach_kind "$_mf_s"):$2" in
          thin:*) _mi_thin "$_mf_s" "$2" "$_mf_a" ;;
          archive:full) _mi_archive "$_mf_s" ;;
          *) _mi_die "its $_mf_a slice is neither Mach-O nor an archive" ;;
        esac
      done ;;
    *) _mi_die "not Mach-O" ;;
  esac
}

shipyard_mach_interface() (
  _mi_f="$1"
  _mi_k="$(shipyard_mach_kind "$_mi_f")"
  [ "$_mi_k" != other ] || exit 1
  _mi_N="$(shipyard_mach_nm)"
  if [ -z "${NM:-}" ] && { [ "$_mi_N" = nm ] || [ "$_mi_N" = llvm-nm ]; }; then echo "mach-interface: no pinned llvm-nm (set NM, or install clang22 under ${SHIPYARD_MG_PREFIX:-/usr/local/mavergreen})" >&2; exit 2; fi
  _mi_O="${OTOOL:-}"; [ -n "$_mi_O" ] || _mi_O="$(_mi_tool otool)" || exit 2
  _mi_L="${LIPO:-}"; [ -n "$_mi_L" ] || _mi_L="$(_mi_tool lipo)" || exit 2
  _mi_A="$(_mi_tool ar)" || exit 2
  _mi_t="$(mktemp -d "${TMPDIR:-/tmp}/mach-interface.XXXXXX")" || { echo "mach-interface: cannot make a temporary directory" >&2; exit 2; }
  trap 'rm -rf "$_mi_t"' EXIT
  : > "$_mi_t/err"
  _mi_seen=0
  _mi_file "$_mi_f" full > "$_mi_t/out"
  [ "$_mi_k" != archive ] || [ "$_mi_seen" -eq 1 ] || exit 1
  LC_ALL=C sort -u "$_mi_t/out"
)
