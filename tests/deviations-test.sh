#!/bin/sh
# platform: host-agnostic
#   usage: deviations-test.sh
#          ONE parser for INGREDIENTS.md's "## Conformance deviations": the artifact checker and the
#          conventions gate must read a declared exception identically, and a deviation without a
#          reason is not a declaration.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; S="$here/../scripts/deviations.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/dev-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
cat > "$w/INGREDIENTS.md" <<'EOF'
# x
## Conformance deviations
- scheme: shipyard ports nothing
- enclosure-url:appcast.xml: the tag carries a v
- shipyard-cmake-only:build/legacy.sh: runs under the host cmake to bootstrap
- rosetta:build/cross.sh: gyp's host tools are x86_64 and run under Rosetta
## Next
- not-a-deviation: ignored
EOF
out="$(sh "$S" "$w")"
printf '%s\n' "$out" | grep -qx 'scheme \* shipyard ports nothing' || { echo "FAIL: unscoped entry; got:"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'enclosure-url appcast.xml the tag carries a v' || { echo "FAIL: scoped entry; got:"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'shipyard-cmake-only build/legacy.sh runs under the host cmake to bootstrap' || { echo "FAIL: path-scoped entry"; exit 1; }
# spec: SKILL.md "Family conventions" check 25 -- rosetta:<scope> is a deviation key like any
#       other; this parser accepts any check name, so the family-conventions gate's check 25 can
#       rely on it without deviations.sh naming rosetta specially.
printf '%s\n' "$out" | grep -qx 'rosetta build/cross.sh gyp'\''s host tools are x86_64 and run under Rosetta' || { echo "FAIL: rosetta:<path> entry must parse like any other scoped deviation; got:"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q 'not-a-deviation' && { echo "FAIL: entries outside the section must be ignored"; exit 1; }
printf '## Conformance deviations\n- scheme:\n' > "$w/INGREDIENTS.md"
if sh "$S" "$w" >/dev/null 2>&1; then echo "FAIL: an entry without a reason must fail"; exit 1; fi

# spec: scripts/deviations.sh -- "- check:reason", no space after the colon, is the same declaration
#       written wrong: the grammar reads up to the SECOND colon as a glob, so this yields an EMPTY
#       glob and the reason's first word silently becomes the scope. It fails safe, which is exactly
#       what makes it worth rejecting.
printf '## Conformance deviations\n- scheme:shipyard ports nothing\n' > "$w/INGREDIENTS.md"
if out="$(sh "$S" "$w" 2>&1)"; then echo "FAIL: a missing space after the colon must fail; got: $out"; exit 1; fi
printf '%s\n' "$out" | grep -qi 'glob' || { echo "FAIL: should say what is wrong (an empty glob): $out"; exit 1; }

# spec: SKILL.md "Acceptance on real 10.9" -- a bare on-target stands in for the 10.9 acceptance job
#       and parses with scope "*"; on-target:<part> names one gap in the job's coverage and keeps its
#       part, which is how check 29 tells the two apart.
printf '## Conformance deviations\n- on-target: no 10.9 acceptance job yet\n- on-target:docker-vm: Fusion cannot nest in QEMU\n' > "$w/INGREDIENTS.md"
out="$(sh "$S" "$w")"
printf '%s\n' "$out" | grep -qx 'on-target \* no 10.9 acceptance job yet' || { echo "FAIL: a bare on-target must parse unscoped; got: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'on-target docker-vm Fusion cannot nest in QEMU' || { echo "FAIL: on-target:<part> must keep its part; got: $out"; exit 1; }

printf '## Conformance deviations\n- scheme:a/b.pkg: a real scope\n' > "$w/INGREDIENTS.md"
sh "$S" "$w" | grep -qx 'scheme a/b.pkg a real scope' || { echo "FAIL: a scoped entry must still parse"; exit 1; }
# spec: SKILL.md "Release notes" -- unlinked: is scoped to a pin, and a pin is a file plus its KEY,
#       so a scope may end in :KEY (uppercase, as the pin's assignment spells it).
printf '## Conformance deviations\n- unlinked:components/boot2docker/version:BASE: no notes for a digest refresh\n' > "$w/INGREDIENTS.md"
sh "$S" "$w" | grep -qx 'unlinked components/boot2docker/version:BASE no notes for a digest refresh' \
  || { echo "FAIL: a KEY-qualified scope must keep its KEY; got: $(sh "$S" "$w")"; exit 1; }
# spec: SKILL.md "Conformance deviations" -- only unlinked: scopes a pin, so only it takes a :KEY;
#       on any other kind the KEY could never match a subject, and would excuse nothing in silence.
printf '## Conformance deviations\n- rosetta:build/x.sh:FOO: runs translated\n' > "$w/INGREDIENTS.md"
if out="$(sh "$S" "$w" 2>&1)"; then echo "FAIL: a :KEY scope on rosetta must fail; got: $out"; exit 1; fi
printf '%s\n' "$out" | grep -q 'unlinked' || { echo "FAIL: should say only unlinked: takes a :KEY: $out"; exit 1; }

# spec: SKILL.md "Release notes" -- unlinked: excuses named pins; an unscoped or "*" one would switch
#       the rule off for the whole repo, which is drift, not a declaration.
for bad in '- unlinked: no notes anywhere' '- unlinked:*: no notes anywhere'; do
  printf '## Conformance deviations\n%s\n' "$bad" > "$w/INGREDIENTS.md"
  if out="$(sh "$S" "$w" 2>&1)"; then echo "FAIL: '$bad' must be refused; got: $out"; exit 1; fi
done
printf '## Conformance deviations\n- unlinked:components/*: a glob covers every KEY of every file under it\n' > "$w/INGREDIENTS.md"
sh "$S" "$w" | grep -qx 'unlinked components/\* a glob covers every KEY of every file under it' \
  || { echo "FAIL: a file glob is a scope"; exit 1; }
echo "PASS: deviations"
