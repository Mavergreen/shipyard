compat-imports: a shipped binary imports no symbol newer than 10.9.

## Why
A newer-SDK cross build will happily let you link a post-10.9 symbol that is not present on a real Mavericks
box, and it fails only there. A hard post-10.9 import always fails the guard: 10.9's dyld aborts on a
missing hard lazy symbol, and also on a missing weak lazy symbol that is actually called. The default denylist
is _clock_gettime, _clock_gettime_nsec_np, _os_unfair_lock_* and _os_log*; MAVERICKS_POST_10_9_SYMBOLS adds
more as a grep alternation. MAVERICKS_ALLOW_GUARDED_WEAK permits listed symbols only when imported weak, for a
runtime that weak-links a post-10.9 SPI and NULL-checks it first (swift's runtime); that is an assertion that
the call is guarded. This is the in-CI proof of native-10.9 equivalence, since no 10.9 runner validates a
cross build's output. A reader that is missing or fails fails the check, naming the variable to set (OTOOL,
LIPO, NM, STRINGS; LLVM's tools by default, never Apple's).

## Incident
2026-09-13: an openssh patch called launch_activate_socket(), a 10.10-era function undeclared in the 10.9
SDK; it compiled and linked, and the guard reported clean (QUEUE #2). That symbol genuinely exists in the 10.9
SDK, so even the proposed allowlist would not catch it.

## Limits
A denylist must predict which future API someone will call; swift-runtime widened its own for that reason.
QUEUE #2 proposes an allowlist derived from the libraries a product links, taken from the frozen 10.9 SDK. It
catches "does not exist", not "exists but is unavailable here". It reads the x86_64 slice. QUEUE #66: it does
not check where a binary's load commands point, so a binary that loads host libraries (a pkgsrc liblzma) passed.

## Deviating
A "- compat-imports:<glob>: <reason>. Revisit when <exit>." line in
INGREDIENTS.md excuses this id for the binaries whose path the glob matches: under shipyard-check --dist, the
path inside the pkg or tarball (usr/local/mavergreen/<product>/...). That is how one binary in a dist keeps
the allowance its CMake target passes in a knob, since --dist applies one environment to every binary. The knobs are per-build
environment variables (MAVERICKS_POST_10_9_SYMBOLS, MAVERICKS_ALLOW_GUARDED_WEAK) that
mavericks_assert_binary_compatible passes. A good use of the weak allowance names the runtime that guards the
call.

Formerly the compat guard's imports rule
