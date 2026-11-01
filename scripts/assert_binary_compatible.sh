#!/bin/sh
# platform: host-agnostic
#   usage: assert_binary_compatible.sh <binary>...
#          assert_binary_compatible.sh        (under shipyard-check --dist: every Mach-O in the dist)
#          10.9 userland compat guard for one or more shipped Mach-O binaries. Per binary:
#          (1) no post-10.9 UNDEFINED import (compat-imports), (2) no post-10.9 ObjC selector sent
#          (compat-selectors), (3) the arches present are exactly MAVERICKS_ALLOW_ARCHS (compat-archs),
#          (4) every slice records its arch's pinned minos and SDK (sdk-pins.sh; sdk-pin), (5) the
#          symbols a project's shims must define are defined (compat-required-defined). (1) and (2)
#          read the x86_64 slice. A file whose bytes are a pinned third-party binary (Sparkle) is
#          exempt by content. A declared "- <id>:<glob>: <reason>" deviation whose glob matches the
#          file's path AS GIVEN here excuses that id's failure for that file, and only that id's:
#          compat-imports, compat-selectors, compat-archs, compat-required-defined or sdk-pin. Under
#          --dist the path is the file's path inside its pkg or tarball, as conformance sees it, and a
#          deviation is how one binary gets the allowance its CMake target passes in the knobs below,
#          which --dist applies to every binary alike. Fail-closed if nothing
#          measured, or if the deviations cannot be read. A reader that is missing or fails fails
#          the check it serves, naming the variable to set.
#          Knobs:
#            SHIPYARD_CHECK_DIST               the dist directory, when no binary is named.
#            MAVERICKS_DEVIATIONS_ROOT         the repo whose INGREDIENTS.md declares the deviations
#                                               (default: SHIPYARD_CHECK_REPO, else the current
#                                               directory; mavericks_assert_binary_compatible passes
#                                               CMAKE_SOURCE_DIR).
#            MAVERICKS_ALLOW_ARCHS             the exact arch set each binary must contain (default
#                                               "x86_64"; a universal updater passes "x86_64 arm64").
#            MAVERICKS_POST_10_9_SYMBOLS       extra post-10.9 symbols (grep -E alternation) that
#                                               must not appear as undefined imports.
#            MAVERICKS_POST_10_9_SELECTORS     extra post-10.9 ObjC selectors (grep -E alternation)
#                                               to deny.
#            MAVERICKS_ALLOW_SELECTORS         post-10.9 selectors the code guards with
#                                               -respondsToSelector:.
#            MAVERICKS_REQUIRE_DEFINED_SYMBOLS symbols that MUST be DEFINED (a project's 10.9 shims).
#            LIPO, NM, STRINGS, OTOOL          the Mach-O readers (default: LLVM's llvm-lipo, llvm-nm,
#                                               llvm-strings and llvm-otool, found by lib/macho-tools.sh,
#                                               never Apple's). A reader that fails is fail-closed.
#            MAVERICKS_ALLOW_GUARDED_WEAK      grep -E alternation of post-10.9 symbols permitted
#                                               ONLY when imported *weak*, for a runtime (e.g.
#                                               mavericks-swift) that weak-links a post-10.9 SPI and
#                                               NULL-checks it first (Swift's
#                                               SWIFT_RUNTIME_WEAK_CHECK). Default empty => strict:
#                                               ANY post-10.9 undefined fails, weak or not.
# platform: a newer-SDK cross-build will happily let you LINK a post-10.9 symbol that simply is not
#           present on a real Mavericks box; this catches it before it ships. A HARD post-10.9 import
#           always fails, allowlisted or not -- 10.9's dyld-239 aborts on a missing hard lazy symbol,
#           and also on a missing weak lazy symbol that is actually called, so the weak allowlist is
#           an assertion that the runtime guards the call with a NULL-check.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/check-lib.sh"
. "$SELF/sdk-pins.sh"
. "$SELF/deviation-reason.sh"
. "$SELF/lib/macho-tools.sh"
. "$SELF/lib/pkg-tree.sh"

_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/compat-guard.XXXXXX")"; trap 'af_rm "$work"' EXIT
for _id in compat-imports compat-selectors compat-archs sdk-pin; do chk_ran "$_id"; done

rule_of() {
  case "$1" in
    compat-imports) echo "a binary imports no symbol newer than 10.9" ;;
    compat-selectors) echo "a binary sends no ObjC selector newer than 10.9" ;;
    compat-archs) echo "a binary holds exactly the arches MAVERICKS_ALLOW_ARCHS names" ;;
    compat-required-defined) echo "a binary defines every symbol MAVERICKS_REQUIRE_DEFINED_SYMBOLS names" ;;
    sdk-pin) echo "every shipped Mach-O slice records its arch's pinned minos and SDK" ;;
    deviation-complete) echo "every conformance deviation is complete" ;;
  esac
}
fix_of() {
  case "$1" in
    compat-imports) echo "remove the post-10.9 call or weak-link and NULL-check it (MAVERICKS_ALLOW_GUARDED_WEAK), and link against the pinned 10.9 SDK (scripts/fetch_sdk.sh)" ;;
    compat-selectors) echo "send the selector only after -respondsToSelector: and list it in MAVERICKS_ALLOW_SELECTORS, or use a 10.9 one" ;;
    compat-archs) echo "build exactly those arches, or set MAVERICKS_ALLOW_ARCHS to the set the binary should hold" ;;
    compat-required-defined) echo "link the shim that defines it into the binary" ;;
    sdk-pin) echo "link against the pinned SDK (scripts/fetch_sdk.sh), or declare '- sdk-pin:<glob>: <reason>' under '## Conformance deviations' in INGREDIENTS.md" ;;
    deviation-complete) echo "give the deviation a reason in INGREDIENTS.md ('- sdk-pin:<glob>: <reason>')" ;;
  esac
}
cannot_measure() {  # $1 = id, $2 = why. Fails closed: nothing after a reader that cannot answer is trustworthy.
  chk_fail "$1" "$(rule_of "$1")" "it CANNOT MEASURE (fail-closed): $2" "$(fix_of "$1")"
  exit 1
}
# spec: a reader's stderr goes to $work/reader.err, quiet on success (nm warns about every empty archive
#       member) and replayed here when the reader fails, so the failure shows the reader's own error.
reader_die() {  # $1 = id, $2 = what failed
  cannot_measure "$1" "$2: $(tr '\n' ' ' < "$work/reader.err")"
}
need_tool() {  # $1 = id, $2 = variable
  mach_tool "$2" 2>"$work/reader.err" || cannot_measure "$1" "$(tr '\n' ' ' < "$work/reader.err")"
}

POST_10_9='_clock_gettime|_clock_gettime_nsec_np|_os_unfair_lock_.*|_os_log.*'
if [ -n "${MAVERICKS_POST_10_9_SYMBOLS:-}" ]; then
  POST_10_9="$POST_10_9|$MAVERICKS_POST_10_9_SYMBOLS"
fi

REQUIRE_DEFINED="${MAVERICKS_REQUIRE_DEFINED_SYMBOLS:-}"
ALLOW_WEAK="${MAVERICKS_ALLOW_GUARDED_WEAK:-}"
if [ -n "$REQUIRE_DEFINED" ]; then chk_ran compat-required-defined; elif [ -n "${SHIPYARD_CHECK_RUNLOG:-}" ]; then chk_notrun compat-required-defined "MAVERICKS_REQUIRE_DEFINED_SYMBOLS names no symbol"; fi

# platform: post-10.9 Objective-C SELECTORS dispatch through objc_msgSend, so they are NOT undefined
#           symbols -- the import check above (nm) cannot see them. A 10.9 binary that SENDS one
#           (e.g. -[NSColor labelColor], 10.10+) links clean but no-ops/misbehaves on 10.9 (grey
#           buttons, wrong colors) -- the exact gap that let an SDK-12 Sparkle ship a grey "Install"
#           button. The selector name is a C string in __TEXT,__objc_methname; matched whole-line via
#           `strings -a`. See tests/compat_guard.bats.
POST_10_9_SEL='labelColor|secondaryLabelColor|tertiaryLabelColor|quaternaryLabelColor|controlAccentColor'
[ -n "${MAVERICKS_POST_10_9_SELECTORS:-}" ] && POST_10_9_SEL="$POST_10_9_SEL|$MAVERICKS_POST_10_9_SELECTORS"
ALLOW_SEL="${MAVERICKS_ALLOW_SELECTORS:-}"
ALLOW_ARCHS="$(printf '%s\n' ${MAVERICKS_ALLOW_ARCHS:-x86_64} | sort -u | xargs)"

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the guard
#       honours the same sdk-pin:<glob> exemptions as the package-time rule, parsed by the same
#       deviations.sh and matched by the same shipyard_deviation_reason, so a file excused in the pkg is
#       excused at build time. Read before any binary: a malformed declaration fails every run, not
#       only the one that needed it.
devs_root="${MAVERICKS_DEVIATIONS_ROOT:-${SHIPYARD_CHECK_REPO:-.}}"
# platform: not a pipeline -- deviations.sh exits 1 on a malformed entry, and a pipeline would report
#           shipyard_deviation_facts' status instead, turning "this declaration is malformed" into "there
#           are no deviations".
shipyard_deviations "$devs_root" > /dev/null 2> "$work/devs.err" \
  || cannot_measure deviation-complete "$devs_root/INGREDIENTS.md declares a malformed conformance deviation: $(cat "$work/devs.err")"

# platform: nm -m lines look like "<addr|spaces> (undefined) [weak] external _sym (from libX)"; nm
#           -u loses the weak flag, so nm -m is parsed instead (the undefined NAME set is identical).
#           Stripping only a trailing " (from libX)" parenthetical, not also " (dynamically looked
#           up)", left $NF = "up)" for a dynamic_lookup undefined, and the hard import slipped past
#           the guard.
shipyard_undefs() {
  _nm_out="$("$NM" -m "$1" 2>"$work/reader.err")" || return 1
  printf '%s\n' "$_nm_out" | grep -F '(undefined)' | sed -E 's/ \([^)]*\)$//' \
    | awk '{ w = (/ weak /) ? "W" : "H"; print w, $NF }'
}

checked=0; excused=0
guard_fail() {  # $1 = id, $2 = the path deviations match, $3 = why; a deviation for $1 covering $2 excuses it
  _gf="$(shipyard_deviated "$1" "$2" || true)"
  if [ -n "$_gf" ]; then
    echo "compat guard: $2 is excused from $1: $_gf"; excused=$((excused+1))
  else
    chk_fail "$1" "$(rule_of "$1")" "$3" "$(fix_of "$1")"
  fi
}

check_one() {  # $1 = the file, $2 = the path to report and match deviations against, $3 = strict|loose
  b="$2"
  checked=$((checked+1))
  if shipyard_sdk_exempt_sha256 "$(shasum -a 256 "$1" | awk '{print $1}')"; then
    echo "compat guard: $b is a pinned third-party binary (exempt by content)"; return 0
  fi
  rc=0; slices="$(sh "$SELF/macho-slices.sh" "$1" 2>"$work/reader.err")" || rc=$?
  if [ "$rc" -eq 1 ] && [ "${3:-strict}" = loose ]; then checked=$((checked-1)); return 0; fi
  [ "$rc" -ne 4 ] || reader_die compat-archs "a Mach-O reader (LIPO or OTOOL) failed on $b"
  [ "$rc" -eq 0 ] || { chk_fail compat-archs "$(rule_of compat-archs)" "$b is not a readable Mach-O" "$(fix_of compat-archs)"; return 0; }

  archs="$(printf '%s\n' "$slices" | awk '{print $1}' | sort -u | xargs)"
  [ "$archs" = "$ALLOW_ARCHS" ] \
    || guard_fail compat-archs "$b" "$b arches '$archs' != '$ALLOW_ARCHS'"
  sdk_bad=""
  while read -r _a _ft _mn _sd; do
    why="$(shipyard_sdk_rule "$_a" "$_ft" "$_mn" "$_sd")" || sdk_bad="${sdk_bad}$b: $why
"
  done <<EOF
$slices
EOF
  [ -z "$sdk_bad" ] || guard_fail sdk-pin "$b" "$(printf '%s' "$sdk_bad" | tr '\n' ' ')"

  # platform: the post-10.9 import and selector checks concern what runs ON 10.9, which is only ever the
  #           x86_64 slice; thinned first, because nm -m and strings read every slice of a fat file.
  case " $archs " in *" x86_64 "*) ;; *) return 0 ;; esac
  need_tool compat-imports NM
  x="$1"
  if [ "$archs" != x86_64 ]; then
    need_tool compat-archs LIPO
    x="$work/x86_64.$checked"
    "$LIPO" -thin x86_64 "$1" -output "$x" 2>"$work/reader.err" \
      || reader_die compat-imports "$LIPO -thin could not read the x86_64 slice of $b"
  fi

  U=$(shipyard_undefs "$x") || reader_die compat-imports "$NM -m could not read $b's symbols"
  hard_leak=$(printf '%s\n' "$U" | awk '$1=="H"{print $2}' | grep -xE "($POST_10_9)" || true)
  weak_leak=$(printf '%s\n' "$U" | awk '$1=="W"{print $2}' | grep -xE "($POST_10_9)" || true)
  if [ -n "$ALLOW_WEAK" ]; then
    weak_leak=$(printf '%s\n' "$weak_leak" | grep -vxE "($ALLOW_WEAK)" || true)
  fi
  leak=$(printf '%s\n%s\n' "$hard_leak" "$weak_leak" | grep -v '^$' || true)
  [ -z "$leak" ] || guard_fail compat-imports "$b" "post-10.9 undefined import(s) in $b: $(printf '%s' "$leak" | tr '\n' ' ')"

  need_tool compat-selectors STRINGS
  _strings_out="$("$STRINGS" -a "$x" 2>"$work/reader.err")" || reader_die compat-selectors "$STRINGS -a could not read $b"
  sel_leak=$(printf '%s\n' "$_strings_out" | grep -xE "($POST_10_9_SEL)" | sort -u || true)
  if [ -n "$ALLOW_SEL" ]; then
    sel_leak=$(printf '%s\n' "$sel_leak" | grep -vxE "($ALLOW_SEL)" || true)
  fi
  sel_leak=$(printf '%s\n' "$sel_leak" | grep -v '^$' || true)
  [ -z "$sel_leak" ] || guard_fail compat-selectors "$b" "post-10.9 ObjC selector(s) sent in $b: $(printf '%s' "$sel_leak" | tr '\n' ' ')"

  if [ -n "$REQUIRE_DEFINED" ]; then
    # platform: nm marks an undefined symbol's line with a leading 'U'/'u'; everything else counts
    #           as defined.
    _nm_all="$("$NM" "$x" 2>"$work/reader.err")" || reader_die compat-required-defined "$NM could not read $b's symbols"
    defined=$(printf '%s\n' "$_nm_all" | grep -vE '^[[:space:]]*[Uu] ' | awk '{print $NF}')
    _missing=""
    for _req in $(printf '%s\n' "$REQUIRE_DEFINED" | tr '|' ' '); do
      printf '%s\n' "$defined" | grep -xq "$_req" || _missing="$_missing $_req"
    done
    [ -z "$_missing" ] || guard_fail compat-required-defined "$b" "required symbol(s)$_missing not DEFINED in $b"
  fi
}

if [ "$#" -gt 0 ]; then
  for b in "$@"; do
    [ -f "$b" ] || { chk_fail compat-archs "$(rule_of compat-archs)" "$b does not exist, so it cannot be measured" "$(fix_of compat-archs)"; continue; }
    check_one "$b" "$b" strict
  done
  [ "$checked" -gt 0 ] || cannot_measure compat-archs "no binaries checked"
elif [ -n "${SHIPYARD_CHECK_DIST:-}" ]; then
  : > "$work/list"
  n=0
  for f in "$SHIPYARD_CHECK_DIST"/*; do
    [ -f "$f" ] || continue
    n=$((n + 1)); x="$work/x$n"; mkdir -p "$x"
    case "${f##*/}" in
      *.pkg)
        rc=0; af_pkg_tree "$f" "$x" || rc=$?
        [ "$rc" -eq 0 ] || cannot_measure compat-archs "${f##*/} cannot be read$([ "$rc" -ne 3 ] || echo " ($AF_WHY)")"
        for pl in $(find "$AF_TREE" -name "*.root" -prune -o -name Payload -type f -print | sed 's/ /%20/g'); do
          pl="$(printf '%s' "$pl" | sed 's/%20/ /g')"
          af_unpack_payload "$pl" || cannot_measure compat-archs "a payload of ${f##*/} cannot be read"
          ( cd "$AF_ROOT" && find . -type f ) | sed 's|^\./||' | while IFS= read -r rel; do
            k="$(af_macho_kind "$AF_ROOT/$rel")"
            [ -z "$k" ] || printf '%s\t%s\t%s\n' "$AF_ROOT/$rel" "$AF_LOC$rel" "$k" >> "$work/list"
          done
        done ;;
      *.tar.gz|*.tgz|*.tar.xz|*.tar.bz2)
        af_extract "$f" "$x" || cannot_measure compat-archs "${f##*/} cannot be read as a tarball"
        ( cd "$x" && find . -type f ) | sed 's|^\./||' | while IFS= read -r rel; do
          k="$(af_macho_kind "$x/$rel")"
          [ -z "$k" ] || printf '%s\t%s\t%s\n' "$x/$rel" "$rel" "$k" >> "$work/list"
        done ;;
    esac
  done
  tab="$(printf '\t')"
  while IFS="$tab" read -r file subject kind; do
    check_one "$file" "$subject" "$kind"
  done < "$work/list"
  if [ "$checked" -eq 0 ]; then
    for _id in compat-imports compat-selectors compat-archs compat-required-defined; do
      chk_notrun "$_id" "no Mach-O in $SHIPYARD_CHECK_DIST"
    done
    exit "$chk_status"
  fi
else
  cannot_measure compat-archs "no binaries checked (usage: assert_binary_compatible.sh <binary>...)"
fi
if [ "$chk_status" -eq 0 ]; then
  pinned="pinned minos and SDK per arch"
  [ "$excused" = 0 ] || pinned="$pinned, $excused excused by deviation"
  echo "compat guard: $checked binaries clean ($ALLOW_ARCHS, $pinned, no post-10.9 imports)"
fi
exit "$chk_status"
