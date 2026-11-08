#!/bin/sh
# platform: host-agnostic
#   usage: assert_binary_compatible.sh <binary>...
#          10.9 userland compat guard for one or more shipped Mach-O binaries. Per binary:
#          (1) no post-10.9 UNDEFINED import, (2) no post-10.9 ObjC selector sent, (3) the arches
#          present are exactly MAVERICKS_ALLOW_ARCHS, (4) every slice records its arch's
#          pinned minos and SDK (sdk-pins.sh). (1) and (2) read the x86_64 slice. A file whose bytes are
#          a pinned third-party binary (Sparkle) is exempt by content. A declared "- sdk-pin:<glob>:
#          <reason>" deviation whose glob matches the file's path AS GIVEN here excuses (4), and only
#          (4). Fail-closed if nothing measured, or if the deviations cannot be read.
#          (2) is a selector list unless the caller opts in with MAVERGREEN_OBJC_STRICT=1. Opted in, (2) is
#          the strict Objective-C analyzer (scripts/objc-compat.sh) run on the binary as shipped: every
#          send it finds unsupported or unresolved against the versioned reference set
#          (scripts/objc-reference-dir.sh) fails, with no selector list anywhere, and one it cannot measure is
#          cannot-measure. Each run measures afresh; no earlier report is an input. Opted in, a declared
#          "- objc-api:<glob>: evidence=<file>#<record id> <review reason>" deviation whose glob matches
#          the file's path RELATIVE TO MAVERGREEN_OBJC_ROOT hands that reviewed record (a plain file
#          inside MAVERICKS_DEVIATIONS_ROOT) to the analyzer, which excuses the one blocking finding the
#          record names exactly -- artifact, site, receiver, kind, selector, digests, basis, reviewer,
#          the declared reason and a retirement condition (Drydock's src/objc/main.m "objc-api scoped
#          deviations"); the finding stays in the report, and the guard says which deviation applied.
#          Exit 0 clean, 1 a check failed, 2 misuse (MAVERGREEN_OBJC_STRICT neither 1 nor unset, an
#          analyzer knob without it, a selector knob with it, evidence for more than one binary, a
#          binary outside MAVERGREEN_OBJC_ROOT), 4 cannot measure.
#          Knobs:
#            MAVERICKS_DEVIATIONS_ROOT         the repo whose INGREDIENTS.md declares the deviations
#                                               (default: the current directory;
#                                               mavericks_assert_binary_compatible passes
#                                               CMAKE_SOURCE_DIR).
#            MAVERICKS_ALLOW_ARCHS             the exact arch set each binary must contain (default
#                                               "x86_64"; a universal updater passes "x86_64 arm64").
#            MAVERICKS_POST_10_9_SYMBOLS       extra post-10.9 symbols (grep -E alternation) that
#                                               must not appear as undefined imports.
#            MAVERICKS_POST_10_9_SELECTORS     extra post-10.9 ObjC selectors (grep -E alternation)
#                                               to deny. Not opted in only.
#            MAVERICKS_ALLOW_SELECTORS         post-10.9 selectors the code guards with
#                                               -respondsToSelector:. Not opted in only.
#            MAVERGREEN_OBJC_STRICT             1: (2) is the strict analyzer. Unset or empty: the list.
#          Opted in only (each is misuse otherwise, never silently ignored):
#            MAVERGREEN_OBJC_ROOT               the shipped root the analyzer resolves each binary's
#                                               dependencies in, and names it relative to (default:
#                                               the binary's own directory). Every binary must be
#                                               inside it.
#            MAVERGREEN_OBJC_REFERENCES         the reference set (default: the pinned Drydock's,
#                                               scripts/objc-reference-dir.sh).
#            MAVERGREEN_OBJC_BUILD_EVIDENCE     schema-1 build evidence (scripts/objc-build-evidence.sh),
#            MAVERGREEN_OBJC_PROVIDER_PREFIX    an Objective-C provider prefix, and
#            MAVERGREEN_OBJC_SOURCE_RECEIPT     the provider body's source receipt, each passed to the
#                                               analyzer as its --build-evidence, --provider-prefix
#                                               and --source-receipt. Build evidence is bound to one
#                                               artifact, so with it the guard takes one binary.
#            MAVERGREEN_OBJC_REPORT_DIR         keep each binary's report there, as
#                                               N.<basename>.objc-compat.json; one already there is
#                                               never replaced (the guard fails instead).
#            OBJC_COMPAT                       the analyzer command (default: sh objc-compat.sh beside
#                                               this script, the pinned Drydock's drydock-objc). An
#                                               analyzer that is missing, cannot be fetched or cannot
#                                               measure is fail-closed.
#          Shared:
#            MAVERICKS_REQUIRE_DEFINED_SYMBOLS symbols that MUST be DEFINED (a project's 10.9 shims).
#            LIPO, NM, STRINGS, OTOOL          the Mach-O readers (default: lipo, nm, strings and
#                                               otool from PATH; macho-slices.sh reads LIPO and
#                                               OTOOL). A 10.9 build without Xcode's Command Line
#                                               Tools, whose lipo, nm, otool and strings are stubs,
#                                               names mavericks-clang-22's llvm-lipo, llvm-nm,
#                                               llvm-strings and llvm-otool, which give this guard
#                                               the same answers. A reader that fails is fail-closed.
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
. "$SELF/sdk-pins.sh"
. "$SELF/deviation-reason.sh"

shipyard_die() { echo "compat guard CANNOT MEASURE (fail-closed): $*" >&2; exit 4; }
# spec: a reader's stderr goes to $work/reader.err, quiet on success (nm warns about every empty archive
#       member) and replayed here when the reader fails, so the failure shows the reader's own error.
shipyard_reader_die() { echo "compat guard CANNOT MEASURE (fail-closed): $*" >&2; cat "$work/reader.err" >&2; exit 4; }
shipyard_misuse() { echo "compat guard: $*" >&2; exit 2; }

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Objective-C sends are measured, not
#       listed" -- the analyzer is opt-in until every family product has been measured; a knob that belongs to
#       the other mode fails rather than being silently ignored.
case "${MAVERGREEN_OBJC_STRICT:-}" in
  1) OBJC_STRICT=1 ;;
  '') OBJC_STRICT= ;;
  *) shipyard_misuse "MAVERGREEN_OBJC_STRICT is 1 or unset, not '$MAVERGREEN_OBJC_STRICT'" ;;
esac
if [ -n "$OBJC_STRICT" ]; then
  [ -z "${MAVERICKS_POST_10_9_SELECTORS:-}" ] || shipyard_misuse "MAVERICKS_POST_10_9_SELECTORS is retired under
  MAVERGREEN_OBJC_STRICT=1: the strict Objective-C analyzer finds any send the 10.9 floor cannot answer from the
  versioned reference set (reference/objc), without a list. Unset it; a later API the reference set does not
  catch is a reference gap to report, not a pattern to add."
  [ -z "${MAVERICKS_ALLOW_SELECTORS:-}" ] || shipyard_misuse "MAVERICKS_ALLOW_SELECTORS is retired under
  MAVERGREEN_OBJC_STRICT=1: a selector string is not proof that a call is guarded. Unset it, and give each send
  that the analyzer blocks but your code guards a reviewed, scoped exception: an INGREDIENTS.md \"- objc-api:<artifact
  path>: evidence=<file>#<record id> <review reason>\" deviation whose evidence record names that finding."
else
  for _k in MAVERGREEN_OBJC_ROOT MAVERGREEN_OBJC_REFERENCES MAVERGREEN_OBJC_BUILD_EVIDENCE MAVERGREEN_OBJC_PROVIDER_PREFIX \
            MAVERGREEN_OBJC_SOURCE_RECEIPT MAVERGREEN_OBJC_REPORT_DIR OBJC_COMPAT; do
    eval "_v=\${$_k:-}"
    [ -z "$_v" ] || shipyard_misuse "$_k needs MAVERGREEN_OBJC_STRICT=1: it is the strict Objective-C analyzer's"
  done
fi

POST_10_9='_clock_gettime|_clock_gettime_nsec_np|_os_unfair_lock_.*|_os_log.*'
if [ -n "${MAVERICKS_POST_10_9_SYMBOLS:-}" ]; then
  POST_10_9="$POST_10_9|$MAVERICKS_POST_10_9_SYMBOLS"
fi

REQUIRE_DEFINED="${MAVERICKS_REQUIRE_DEFINED_SYMBOLS:-}"
ALLOW_WEAK="${MAVERICKS_ALLOW_GUARDED_WEAK:-}"

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
OBJC_REFS="${MAVERGREEN_OBJC_REFERENCES:-}"
# spec: scripts/objc-reference-dir.sh header -- the default reference set is the pinned Drydock's, resolved only when the
#       analyzer will run; one that cannot be had is cannot-measure.
if [ -n "$OBJC_STRICT" ] && [ -z "$OBJC_REFS" ]; then
  OBJC_REFS="$(sh "$SELF/objc-reference-dir.sh")" || shipyard_die "no Objective-C reference set: objc-reference-dir.sh said why above"
fi
if [ -n "${MAVERGREEN_OBJC_BUILD_EVIDENCE:-}" ] && [ "$#" -ne 1 ]; then
  shipyard_misuse "MAVERGREEN_OBJC_BUILD_EVIDENCE is bound to one artifact: give exactly one binary, not $#"
fi
_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/compat-guard.XXXXXX")"; trap 'rm -rf "$work"' EXIT

# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "SDK pinning" -- the guard
#       honours the same sdk-pin:<glob> exemptions as the package-time rule, parsed by the same
#       deviations.sh and matched by the same shipyard_deviation_reason, so a file excused in the pkg is
#       excused at build time. Read before any binary: a malformed declaration fails every run, not
#       only the one that needed it.
devs_root="${MAVERICKS_DEVIATIONS_ROOT:-.}"
# platform: not a pipeline -- deviations.sh exits 1 on a malformed entry, and a pipeline would report
#           shipyard_deviation_facts' status instead, turning "this declaration is malformed" into "there
#           are no deviations".
_devs="$(sh "$SELF/deviations.sh" "$devs_root")" \
  || shipyard_die "$devs_root/INGREDIENTS.md declares a malformed conformance deviation (deviations.sh said why above)"
printf '%s\n' "$_devs" | shipyard_deviation_facts > "$work/devs"

# platform: nm -m lines look like "<addr|spaces> (undefined) [weak] external _sym (from libX)"; nm
#           -u loses the weak flag, so nm -m is parsed instead (the undefined NAME set is identical).
#           Stripping only a trailing " (from libX)" parenthetical, not also " (dynamically looked
#           up)", left $NF = "up)" for a dynamic_lookup undefined, and the hard import slipped past
#           the guard.
shipyard_undefs() {
  _nm_out="$("${NM:-nm}" -m "$1" 2>"$work/reader.err")" || return 1
  printf '%s\n' "$_nm_out" | grep -F '(undefined)' | sed -E 's/ \([^)]*\)$//' \
    | awk '{ w = (/ weak /) ? "W" : "H"; print w, $NF }'
}

command -v shasum >/dev/null 2>&1 \
  || shipyard_die "no shasum on PATH, so no binary can be matched to a pinned third-party one (on Linux, shasum is perl's)"
# spec: scripts/objc-compat.sh header -- strict mode on the binary as shipped (its x86_64 slice, fat or
#       not, so the evidence's artifact hash is the shipped file's), a fresh report each time. Sets
#       objc_rc; the analyzer's stderr, which names each blocking finding, is in $work/objc.err.
shipyard_objc() {  # $1 binary, $2 report
  _objc_report=$2
  set -- --artifact "$1" --root "${MAVERGREEN_OBJC_ROOT:-$(dirname "$1")}" --references "$OBJC_REFS" \
    --report "$2" --mode strict
  [ -z "${MAVERGREEN_OBJC_BUILD_EVIDENCE:-}" ] || set -- "$@" --build-evidence "$MAVERGREEN_OBJC_BUILD_EVIDENCE"
  [ -z "${MAVERGREEN_OBJC_PROVIDER_PREFIX:-}" ] || set -- "$@" --provider-prefix "$MAVERGREEN_OBJC_PROVIDER_PREFIX"
  [ -z "${MAVERGREEN_OBJC_SOURCE_RECEIPT:-}" ] || set -- "$@" --source-receipt "$MAVERGREEN_OBJC_SOURCE_RECEIPT"
  [ ! -s "$work/exceptions" ] || set -- "$@" --exceptions "$work/exceptions"
  objc_rc=0
  if [ -n "${OBJC_COMPAT:-}" ]; then
    # platform: bash 3.2 as sh, under set -e, reports a command that does not exist as status 1 from
    #           inside a function -- a missing analyzer would read as a blocking verdict.
    [ -x "$OBJC_COMPAT" ] || { echo "OBJC_COMPAT $OBJC_COMPAT is not an executable" >"$work/objc.err"; objc_rc=4; return; }
    "$OBJC_COMPAT" "$@" >"$work/objc.err" 2>&1 || objc_rc=$?
  else sh "$SELF/objc-compat.sh" "$@" >"$work/objc.err" 2>&1 || objc_rc=$?; fi
  # spec: Drydock's src/objc/main.m header -- a verdict comes with its strict report: 0 only from a complete one, 1
  #       only with the blocking findings it names. Anything else is not a measurement.
  case "$objc_rc" in
    0) grep -F '"mode": "strict", "complete_within_boundary": true,' "$_objc_report" >/dev/null 2>&1 ||
         { echo "the analyzer exited 0 without a complete strict report at $_objc_report" >>"$work/objc.err"; objc_rc=4; } ;;
    1) [ -f "$_objc_report" ] && grep '^objc-compat: blocking: ' "$work/objc.err" >/dev/null ||
         { echo "the analyzer exited 1 without a report naming a blocking finding" >>"$work/objc.err"; objc_rc=4; } ;;
  esac
}

# spec: scripts/assert_binary_compatible.sh header -- the objc-api deviations whose declared glob matches the
#       binary's path relative to the shipped root, through the common matcher, become the analyzer's
#       --exceptions list, "EVIDENCE<TAB>RECORD_ID<TAB>REVIEW_REASON" per line, EVIDENCE the physical path of a
#       plain file inside MAVERICKS_DEVIATIONS_ROOT. Any other evidence path is cannot-measure: an exception's
#       proof lives in the repo that declares it.
shipyard_objc_exceptions() {  # $1 binary
  : > "$work/exceptions"
  _oe_root="$(cd "${MAVERGREEN_OBJC_ROOT:-$(dirname "$1")}" 2>/dev/null && pwd -P)" || return 0
  _oe_bin="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
  case "$_oe_bin" in "$_oe_root"/*) _oe_rel="${_oe_bin#"$_oe_root"/}" ;; *) return 0 ;; esac
  _oe_devs="$(cd "$devs_root" && pwd -P)"
  _oe_tab="$(printf '\t')"
  shipyard_deviation_reasons "$work/devs" objc-api "$_oe_rel" > "$work/objc-api"
  while IFS= read -r _oe_line; do
    _oe_ref="${_oe_line%% *}"; _oe_ref="${_oe_ref#evidence=}"; _oe_why="${_oe_line#* }"
    _oe_path="${_oe_ref%#*}"; _oe_id="${_oe_ref##*#}"
    case "$_oe_path" in
      /*|..|../*|*/..|*/../*) shipyard_die "objc-api:$_oe_rel names evidence $_oe_path outside $devs_root" ;;
    esac
    case "$_oe_line" in *"$_oe_tab"*) shipyard_die "objc-api:$_oe_rel: a tab in the declaration" ;; esac
    _oe_file="$devs_root/$_oe_path"
    [ -f "$_oe_file" ] && [ ! -L "$_oe_file" ] \
      || shipyard_die "objc-api:$_oe_rel names evidence $_oe_path, which is not a plain file in $devs_root"
    _oe_dir="$(cd "$(dirname "$_oe_file")" && pwd -P)"
    case "$_oe_dir/" in "$_oe_devs"/*) ;; *) shipyard_die "objc-api:$_oe_rel names evidence $_oe_path, which resolves outside $devs_root" ;; esac
    printf '%s\t%s\t%s\n' "$_oe_dir/$(basename "$_oe_file")" "$_oe_id" "$_oe_why" >> "$work/exceptions"
  done < "$work/objc-api"
}

fail=0; checked=0; excused=0; measured=0
for b in "$@"; do
  [ -f "$b" ] || { echo "compat guard: MISSING $b" >&2; fail=1; continue; }
  checked=$((checked+1))
  if shipyard_sdk_exempt_sha256 "$(shasum -a 256 "$b" | awk '{print $1}')"; then
    echo "compat guard: $b is a pinned third-party binary (exempt by content)"; continue
  fi
  rc=0; slices="$(sh "$SELF/macho-slices.sh" "$b")" || rc=$?
  [ "$rc" -ne 4 ] || shipyard_die "a Mach-O reader (${LIPO:-lipo} or ${OTOOL:-otool}) failed on $b (macho-slices.sh said which, above)"
  [ "$rc" -eq 0 ] || { echo "compat guard: $b is not a readable Mach-O" >&2; fail=1; continue; }

  archs="$(printf '%s\n' "$slices" | awk '{print $1}' | sort -u | xargs)"
  [ "$archs" = "$ALLOW_ARCHS" ] || { echo "compat guard: $b arches '$archs' != '$ALLOW_ARCHS'" >&2; fail=1; }
  sdk_bad=""
  while read -r _a _ft _mn _sd; do
    why="$(shipyard_sdk_rule "$_a" "$_ft" "$_mn" "$_sd")" || sdk_bad="${sdk_bad}compat guard: $b: $why
"
  done <<EOF
$slices
EOF
  if [ -n "$sdk_bad" ]; then
    excuse="$(shipyard_deviation_reason "$work/devs" sdk-pin "$b")"
    if [ -n "$excuse" ]; then
      echo "compat guard: $b is excused from sdk-pin: $excuse"; excused=$((excused+1))
    else
      printf '%s' "$sdk_bad" >&2; fail=1
    fi
  fi

  # platform: the post-10.9 import and selector checks concern what runs ON 10.9, which is only ever the
  #           x86_64 slice; thinned first, because nm -m and strings read every slice of a fat file.
  case " $archs " in *" x86_64 "*) ;; *) continue ;; esac
  x="$b"
  if [ "$archs" != x86_64 ]; then
    x="$work/x86_64.$checked"
    "${LIPO:-lipo}" -thin x86_64 "$b" -output "$x" 2>"$work/reader.err" \
      || shipyard_reader_die "${LIPO:-lipo} -thin could not read the x86_64 slice of $b"
  fi

  U=$(shipyard_undefs "$x") || shipyard_reader_die "${NM:-nm} -m could not read $b's symbols"
  hard_leak=$(printf '%s\n' "$U" | awk '$1=="H"{print $2}' | grep -xE "($POST_10_9)" || true)
  weak_leak=$(printf '%s\n' "$U" | awk '$1=="W"{print $2}' | grep -xE "($POST_10_9)" || true)
  if [ -n "$ALLOW_WEAK" ]; then
    weak_leak=$(printf '%s\n' "$weak_leak" | grep -vxE "($ALLOW_WEAK)" || true)
  fi
  leak=$(printf '%s\n%s\n' "$hard_leak" "$weak_leak" | grep -v '^$' || true)
  [ -z "$leak" ] || { echo "compat guard: post-10.9 undefined import(s) in $b:" >&2; printf '%s\n' "$leak" | sed 's/^/  /' >&2; fail=1; }

  if [ -n "$OBJC_STRICT" ]; then
    # platform: Objective-C selectors dispatch through objc_msgSend, so they are NOT undefined symbols -- the
    #           import check above cannot see them. A 10.9 binary that SENDS a later one (-[NSColor
    #           labelColor], -[NSWorkspace openURLs:...]) links clean and misbehaves or aborts on 10.9. The
    #           analyzer measures every send; the selector list below finds only the names it lists.
    if [ -n "${MAVERGREEN_OBJC_REPORT_DIR:-}" ]; then report="${MAVERGREEN_OBJC_REPORT_DIR%/}/$checked.$(basename "$b").objc-compat.json"
    else report="$work/objc.$checked.json"; fi
    shipyard_objc_exceptions "$b"
    shipyard_objc "$b" "$report"
    # spec: scripts/assert_binary_compatible.sh header -- every applied (or unused) objc-api deviation is said.
    case "$objc_rc" in 0|1)
      grep '^objc-compat: deviation: ' "$work/objc.err" | while IFS= read -r _l; do
        echo "compat guard: $b: objc-api deviation ${_l#objc-compat: deviation: }"
      done ;;
    esac
    case "$objc_rc" in
      0) measured=$((measured+1)) ;;
      1) echo "compat guard: Objective-C send(s) in $b that 10.9 cannot answer (report: $report):" >&2
         sed -n 's/^objc-compat: blocking: /  /p' "$work/objc.err" >&2
         measured=$((measured+1)); fail=1 ;;
      2) cat "$work/objc.err" >&2
         shipyard_misuse "the Objective-C analyzer refused its arguments for $b (said why above; a binary not inside MAVERGREEN_OBJC_ROOT, or a report already in MAVERGREEN_OBJC_REPORT_DIR)" ;;
      *) cat "$work/objc.err" >&2
         shipyard_die "the Objective-C analyzer (${OBJC_COMPAT:-objc-compat.sh}) could not measure $b (exit $objc_rc, said why above)" ;;
    esac
  else
    _strings_out="$("${STRINGS:-strings}" -a "$x" 2>"$work/reader.err")" || shipyard_reader_die "${STRINGS:-strings} -a could not read $b"
    sel_leak=$(printf '%s\n' "$_strings_out" | grep -xE "($POST_10_9_SEL)" | sort -u || true)
    if [ -n "$ALLOW_SEL" ]; then
      sel_leak=$(printf '%s\n' "$sel_leak" | grep -vxE "($ALLOW_SEL)" || true)
    fi
    sel_leak=$(printf '%s\n' "$sel_leak" | grep -v '^$' || true)
    [ -z "$sel_leak" ] || { echo "compat guard: post-10.9 ObjC selector(s) sent in $b:" >&2; printf '%s\n' "$sel_leak" | sed 's/^/  /' >&2; fail=1; }
  fi

  if [ -n "$REQUIRE_DEFINED" ]; then
    # platform: nm marks an undefined symbol's line with a leading 'U'/'u'; everything else counts
    #           as defined.
    _nm_all="$("${NM:-nm}" "$x" 2>"$work/reader.err")" || shipyard_reader_die "${NM:-nm} could not read $b's symbols"
    defined=$(printf '%s\n' "$_nm_all" | grep -vE '^[[:space:]]*[Uu] ' | awk '{print $NF}')
    for _req in $(printf '%s\n' "$REQUIRE_DEFINED" | tr '|' ' '); do
      printf '%s\n' "$defined" | grep -xq "$_req" \
        || { echo "compat guard: required symbol '$_req' not DEFINED in $b" >&2; fail=1; }
    done
  fi
done
[ "$checked" -gt 0 ] || shipyard_die "no binaries checked"
if [ "$fail" = 0 ]; then
  pinned="pinned minos and SDK per arch"
  [ "$excused" = 0 ] || pinned="$pinned, $excused excused from sdk-pin"
  if [ -n "$OBJC_STRICT" ]; then
    echo "compat guard: $checked binaries clean ($ALLOW_ARCHS, $pinned, no post-10.9 imports, Objective-C sends measured floor-answerable in $measured)"
  else
    echo "compat guard: $checked binaries clean ($ALLOW_ARCHS, $pinned, no post-10.9 imports)"
  fi
else
  exit 1
fi
