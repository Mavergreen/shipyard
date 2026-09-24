#!/bin/sh
# platform: macOS-only -- lipo and otool read Mach-O load commands
#   usage: assert_binary_compatible.sh <binary>...
#          10.9 userland compat guard for one or more shipped Mach-O binaries. Per binary:
#          (1) no post-10.9 UNDEFINED import, (2) no post-10.9 ObjC selector sent, (3) arch exactly
#          x86_64, (4) LC_VERSION_MIN_MACOSX == 10.9. Fail-closed if nothing measured.
#          Knobs:
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

  U=$(mav_undefs "$b")
  hard_leak=$(printf '%s\n' "$U" | awk '$1=="H"{print $2}' | grep -xE "($POST_10_9)" || true)
  weak_leak=$(printf '%s\n' "$U" | awk '$1=="W"{print $2}' | grep -xE "($POST_10_9)" || true)
  if [ -n "$ALLOW_WEAK" ]; then
    weak_leak=$(printf '%s\n' "$weak_leak" | grep -vxE "($ALLOW_WEAK)" || true)
  fi
  leak=$(printf '%s\n%s\n' "$hard_leak" "$weak_leak" | grep -v '^$' || true)
  [ -z "$leak" ] || { echo "compat guard: post-10.9 undefined import(s) in $b:" >&2; printf '%s\n' "$leak" | sed 's/^/  /' >&2; fail=1; }

  sel_leak=$(strings -a "$b" 2>/dev/null | grep -xE "($POST_10_9_SEL)" | sort -u || true)
  if [ -n "$ALLOW_SEL" ]; then
    sel_leak=$(printf '%s\n' "$sel_leak" | grep -vxE "($ALLOW_SEL)" || true)
  fi
  sel_leak=$(printf '%s\n' "$sel_leak" | grep -v '^$' || true)
  [ -z "$sel_leak" ] || { echo "compat guard: post-10.9 ObjC selector(s) sent in $b:" >&2; printf '%s\n' "$sel_leak" | sed 's/^/  /' >&2; fail=1; }

  if [ -n "$REQUIRE_DEFINED" ]; then
    # platform: nm marks an undefined symbol's line with a leading 'U'/'u'; everything else counts
    #           as defined.
    defined=$(nm "$b" 2>/dev/null | grep -vE '^[[:space:]]*[Uu] ' | awk '{print $NF}')
    for _req in $(printf '%s\n' "$REQUIRE_DEFINED" | tr '|' ' '); do
      printf '%s\n' "$defined" | grep -xq "$_req" \
        || { echo "compat guard: required symbol '$_req' not DEFINED in $b" >&2; fail=1; }
    done
  fi

  archs=$(lipo -info "$b" 2>/dev/null | sed 's/.*: //' || true)
  [ "$archs" = x86_64 ] || { echo "compat guard: $b arch '$archs' != x86_64" >&2; fail=1; }
  minos=$(otool -l "$b" 2>/dev/null | awk '/LC_VERSION_MIN_MACOSX/{f=1} f&&$1=="version"{print $2; exit}')
  [ "$minos" = 10.9 ] || { echo "compat guard: $b min-OS '$minos' != 10.9" >&2; fail=1; }
done
[ "$checked" -gt 0 ] || mav_die "no binaries checked"
if [ "$fail" = 0 ]; then
  echo "compat guard: $checked binaries clean (x86_64, min-10.9, no post-10.9 imports)"
else
  exit 1
fi
