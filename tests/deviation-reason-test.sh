#!/bin/sh
# platform: host-agnostic
#   usage: deviation-reason-test.sh
#          The ONE matcher for declared deviations, sourced by the package-time checker and the
#          build-time compat guard alike: a scoped glob matches with shell `case` (`*` spans "/"
#          and spaces), a glob with no reason excuses nothing, an unscoped deviation excuses every
#          subject, and a deviation excuses only its own check.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../scripts/deviation-reason.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/devreason-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT

says() {  # $1 = expected reason ("" for none), then mav_deviation_reason's arguments
  _want="$1"; shift
  _got="$(mav_deviation_reason "$@")"
  [ "$_got" = "$_want" ] || { echo "FAIL: mav_deviation_reason $* -- wanted '$_want', got '$_got'"; exit 1; }
}

cat > "$w/devs" <<'EOF'
deviation sdk-pin:*/lib/libswiftCore.dylib the Swift runtime ships prebuilt
deviation sdk-pin:*/bin/no-reason
deviation sdk-pin:*/bin/second first match wins
deviation sdk-pin:*/bin/sec* not this one
deviation sdk-pin-extra:*/bin/tool a different check
deviation install-path:Library/Application*Support/Foo/* a kext's support files
deviation scheme shipyard ports nothing
EOF
d="$w/devs"

# spec: SKILL.md "SDK pinning" -- one glob written with a leading */ matches the payload path and
#       the build path alike.
says 'the Swift runtime ships prebuilt' "$d" sdk-pin usr/local/mavergreen/swift/lib/libswiftCore.dylib
says 'the Swift runtime ships prebuilt' "$d" sdk-pin /Users/runner/work/swift/build/lib/libswiftCore.dylib
says '' "$d" sdk-pin usr/local/mavergreen/swift/lib/libswiftRemoteMirror.dylib
# spec: SKILL.md "Conformance deviations" -- a glob with no reason is not a declaration
says '' "$d" sdk-pin build/bin/no-reason
says 'first match wins' "$d" sdk-pin build/bin/second
# spec: SKILL.md "Artifact conformance" -- a deviation excuses only its OWN check; a longer check
#       name is a different check.
says '' "$d" sdk-pin build/bin/tool
says 'a different check' "$d" sdk-pin-extra build/bin/tool
says "a kext's support files" "$d" install-path 'Library/Application Support/Foo/x y'
says '' "$d" sdk-pin 'Library/Application Support/Foo/x'
# spec: SKILL.md "Conformance deviations" -- an unscoped deviation excuses its check for every
#       subject, and for a failure that names none.
says 'shipyard ports nothing' "$d" scheme
says 'shipyard ports nothing' "$d" scheme any/path/at/all
# spec: scripts/deviation-reason.sh -- a scoped deviation never excuses a failure that names no
#       subject.
says '' "$d" sdk-pin
says '' "$d" floor x.pkg
: > "$w/empty"
says '' "$w/empty" sdk-pin a/b

# spec: scripts/deviation-reason.sh -- mav_deviation_facts turns deviations.sh's "<check> <glob or *>
#       <reason>" into the fact lines the matcher reads; end to end from INGREDIENTS.md, the path
#       check-artifact-conformance.sh (via artifact-facts.sh) and assert_binary_compatible.sh both take.
cat > "$w/INGREDIENTS.md" <<'EOF'
## Conformance deviations
- sdk-pin:*/lib/libswiftCore.dylib: the Swift runtime ships prebuilt
- scheme: shipyard ports nothing
EOF
sh "$here/../scripts/deviations.sh" "$w" | mav_deviation_facts > "$w/facts"
grep -qx 'deviation sdk-pin:\*/lib/libswiftCore.dylib the Swift runtime ships prebuilt' "$w/facts" \
  || { echo "FAIL: a scoped entry's fact line; got:"; cat "$w/facts"; exit 1; }
grep -qx 'deviation scheme shipyard ports nothing' "$w/facts" \
  || { echo "FAIL: an unscoped entry's fact line; got:"; cat "$w/facts"; exit 1; }
says 'the Swift runtime ships prebuilt' "$w/facts" sdk-pin build/lib/libswiftCore.dylib
[ -z "$(printf '\n' | mav_deviation_facts)" ] || { echo "FAIL: no deviations must yield no facts"; exit 1; }
echo "PASS: deviation-reason"
