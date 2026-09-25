#!/bin/sh
# platform: macOS-only -- lipo and otool read Mach-O load commands
#   usage: assert_binary_compatible.sh <binary>...
#          10.9 userland compat guard for one or more shipped Mach-O binaries. Per binary:
#          (1) no post-10.9 UNDEFINED import, (2) no post-10.9 ObjC selector sent, (3) the arches
#          present are exactly MAVERICKS_ALLOW_ARCHS, (4) every slice records its arch's
#          pinned minos and SDK (sdk-pins.sh). (1) and (2) read the x86_64 slice. A file whose bytes are
#          a pinned third-party binary (Sparkle) is exempt by content. Fail-closed if nothing measured.
#          Knobs:
#            MAVERICKS_ALLOW_ARCHS             the exact arch set each binary must contain (default
#                                               "x86_64"; a universal updater passes "x86_64 arm64").
#            MAVERICKS_POST_10_9_SYMBOLS       extra post-10.9 symbols (grep -E alternation) that
#                                               must not appear as undefined imports.
#            MAVERICKS_POST_10_9_SELECTORS     extra post-10.9 ObjC selectors (grep -E alternation)
#                                               to deny.
#            MAVERICKS_ALLOW_SELECTORS         post-10.9 selectors the code guards with
#                                               -respondsToSelector:.
#            MAVERICKS_REQUIRE_DEFINED_SYMBOLS symbols that MUST be DEFINED (a project's 10.9 shims).
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

mav_die() { echo "compat guard CANNOT MEASURE (fail-closed): $*" >&2; exit 4; }

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
ALLOW_ARCHS="$(printf '%s\n' ${MAVERICKS_ALLOW_ARCHS:-x86_64} | sort | xargs)"
_tmp="${TMPDIR:-/tmp}"
work="$(mktemp -d "${_tmp%/}/compat-guard.XXXXXX")"; trap 'rm -rf "$work"' EXIT

# platform: nm -m lines look like "<addr|spaces> (undefined) [weak] external _sym (from libX)"; nm
#           -u loses the weak flag, so nm -m is parsed instead (the undefined NAME set is identical).
#           Stripping only a trailing " (from libX)" parenthetical, not also " (dynamically looked
#           up)", left $NF = "up)" for a dynamic_lookup undefined, and the hard import slipped past
#           the guard.
mav_undefs() {
  nm -m "$1" 2>/dev/null | grep -F '(undefined)' | sed -E 's/ \([^)]*\)$//' \
    | awk '{ w = (/ weak /) ? "W" : "H"; print w, $NF }'
}

fail=0; checked=0
for b in "$@"; do
  [ -f "$b" ] || { echo "compat guard: MISSING $b" >&2; fail=1; continue; }
  checked=$((checked+1))
  if mav_sdk_exempt_sha256 "$(shasum -a 256 "$b" | awk '{print $1}')"; then
    echo "compat guard: $b is a pinned third-party binary (exempt by content)"; continue
  fi
  slices="$(sh "$SELF/macho-slices.sh" "$b")" || { echo "compat guard: $b is not a readable Mach-O" >&2; fail=1; continue; }

  archs="$(printf '%s\n' "$slices" | awk '{print $1}' | sort -u | xargs)"
  [ "$archs" = "$ALLOW_ARCHS" ] || { echo "compat guard: $b arches '$archs' != '$ALLOW_ARCHS'" >&2; fail=1; }
  while read -r _a _ft _mn _sd; do
    why="$(mav_sdk_rule "$_a" "$_ft" "$_mn" "$_sd")" || { echo "compat guard: $b: $why" >&2; fail=1; }
  done <<EOF
$slices
EOF

  # platform: the post-10.9 import and selector checks concern what runs ON 10.9, which is only ever the
  #           x86_64 slice; thinned first, because nm -m and strings read every slice of a fat file.
  case " $archs " in *" x86_64 "*) ;; *) continue ;; esac
  x="$b"
  if [ "$archs" != x86_64 ]; then
    x="$work/x86_64.$checked"
    lipo -thin x86_64 "$b" -output "$x" 2>/dev/null \
      || { echo "compat guard: cannot thin the x86_64 slice of $b" >&2; fail=1; continue; }
  fi

  U=$(mav_undefs "$x")
  hard_leak=$(printf '%s\n' "$U" | awk '$1=="H"{print $2}' | grep -xE "($POST_10_9)" || true)
  weak_leak=$(printf '%s\n' "$U" | awk '$1=="W"{print $2}' | grep -xE "($POST_10_9)" || true)
  if [ -n "$ALLOW_WEAK" ]; then
    weak_leak=$(printf '%s\n' "$weak_leak" | grep -vxE "($ALLOW_WEAK)" || true)
  fi
  leak=$(printf '%s\n%s\n' "$hard_leak" "$weak_leak" | grep -v '^$' || true)
  [ -z "$leak" ] || { echo "compat guard: post-10.9 undefined import(s) in $b:" >&2; printf '%s\n' "$leak" | sed 's/^/  /' >&2; fail=1; }

  sel_leak=$(strings -a "$x" 2>/dev/null | grep -xE "($POST_10_9_SEL)" | sort -u || true)
  if [ -n "$ALLOW_SEL" ]; then
    sel_leak=$(printf '%s\n' "$sel_leak" | grep -vxE "($ALLOW_SEL)" || true)
  fi
  sel_leak=$(printf '%s\n' "$sel_leak" | grep -v '^$' || true)
  [ -z "$sel_leak" ] || { echo "compat guard: post-10.9 ObjC selector(s) sent in $b:" >&2; printf '%s\n' "$sel_leak" | sed 's/^/  /' >&2; fail=1; }

  if [ -n "$REQUIRE_DEFINED" ]; then
    # platform: nm marks an undefined symbol's line with a leading 'U'/'u'; everything else counts
    #           as defined.
    defined=$(nm "$x" 2>/dev/null | grep -vE '^[[:space:]]*[Uu] ' | awk '{print $NF}')
    for _req in $(printf '%s\n' "$REQUIRE_DEFINED" | tr '|' ' '); do
      printf '%s\n' "$defined" | grep -xq "$_req" \
        || { echo "compat guard: required symbol '$_req' not DEFINED in $b" >&2; fail=1; }
    done
  fi
done
[ "$checked" -gt 0 ] || mav_die "no binaries checked"
if [ "$fail" = 0 ]; then
  echo "compat guard: $checked binaries clean ($ALLOW_ARCHS, pinned minos and SDK per arch, no post-10.9 imports)"
else
  exit 1
fi
