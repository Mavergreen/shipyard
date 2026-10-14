sdk-pin: every shipped Mach-O slice records its arch's pinned minos and SDK.

## Why
Every Mach-O the family compiles that is installed on anyone's Mac records a pinned SDK, never the runner's:
x86_64 records minos 10.9 and sdk 10.9, arm64 minos 11.0 and sdk 11.3. Linking the runner's SDK lets a
post-10.9 declaration compile and fail only on the target, and a Linux host has no runner SDK at all. The
pins live in one place, scripts/sdk-pins.sh. Builds comply by configuring through the shipyard presets or
the toolchain file, or by passing -isysroot "$(sh "$SHIPYARD_SCRIPTS/fetch_sdk.sh" --arch <arch>)". The same
rule runs twice: here at package time on everything a release contains (the gate), and right after each
build inside the compat guard (early feedback). Sparkle 1.27.3 is exempt by content: sdk-pins.sh lists the
sha256 of its three Mach-O files.

## Incident
2026-09-24: an audit of every family release found builds through mavericks-clang, the Go wrapper or an
explicit sysroot recorded 10.9, while plain CMake builds with AppleClang silently linked the runner's SDK
(26.5). That included every Sparkle updater and every arm64 slice in the family, and nothing noticed: the
compat guard read minos and never the SDK.

## Limits
A kext records no version load command and is checked for arch only. A static archive's members built
against the 10.9 SDK record sdk n/a, accepted for x86_64 object files only. A static archive built natively
on 10.9 records no version at all, since 10.9's clang writes none into a .o. An excuse covers the minos and
SDK rule only; the guard still checks arches and imports.

## Deviating
Write "- sdk-pin:<glob>: <reason>". The glob matches the payload path (or the path inside a shipped tarball)
and cannot contain a space (write "*") or a colon. Write it with a leading "*/", as in
"- sdk-pin:*/lib/libswiftCore.dylib: <reason>", so one glob matches both the payload path and the staged
path the guard sees; "*" spans "/". A bare "- sdk-pin: <reason>" excuses every file: use it only if that is
what you mean. A good reason names a prebuilt third-party file or a build-only file never installed, and its
exit.

Formerly the conformance rule sdk-pin
