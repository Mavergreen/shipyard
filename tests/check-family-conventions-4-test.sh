#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/conventions_fixture.sh"

A='--stage stage --product w --name W --version 1 --scripts-out scr'
pkcall "$work/pkif" "if sh \"\$SHIPYARD_SCRIPTS/stage_product.sh\" $A; then :; fi"
pkcall "$work/pkelif" "if false; then :
elif sh \"\$SHIPYARD_SCRIPTS/stage_product.sh\" $A; then :; fi"
pkcall "$work/pkwhile" "while sh \"\$SHIPYARD_SCRIPTS/stage_product.sh\" $A; do break; done"
pkcall "$work/pkuntil" "until sh \"\$SHIPYARD_SCRIPTS/stage_product.sh\" $A; do :; done"
pkcall "$work/pkbang" "! sh \"\$SHIPYARD_SCRIPTS/stage_product.sh\" $A || exit 1"
pkcall "$work/pkifbang" "if ! sh \"\$SHIPYARD_SCRIPTS/stage_product.sh\" $A; then exit 1; fi"
pkcall "$work/pkbinsh" "/bin/sh \"\$SHIPYARD_SCRIPTS/stage_product.sh\" $A"
pkcall "$work/pkshe" "sh -e \"\$SHIPYARD_SCRIPTS/stage_product.sh\" $A"
pkcall "$work/pkshex" "sh -ex \"\$SHIPYARD_SCRIPTS/stage_product.sh\" $A"
pkcall "$work/pkmidq" "sh \"\$SHIPYARD_SCRIPTS\"/stage_product.sh $A"
pkcall "$work/pkmidqpath" "\"\$SHIPYARD_SCRIPTS\"/stage_product.sh $A"

# spec: scripts/check-family-conventions.sh check 23 -- a variable that merely holds the script's
#       path is not a call, and neither is a keyword spelled inside an echo'd string.
mkrepo "$work/pkassign"
printf '#!/bin/sh\npkgbuild --root stage --identifier dev.mavergreen.w out.pkg\nSP="$SHIPYARD_SCRIPTS/stage_product.sh"\necho "if sh stage_product.sh"\necho "/bin/sh -e $SHIPYARD_SCRIPTS/stage_product.sh"\n' > "$work/pkassign/build/package.sh"
printf '      - run: sh "$SHIPYARD_SCRIPTS/artifact-facts.sh" dist "$FULL" | sh "$SHIPYARD_SCRIPTS/check-artifact-conformance.sh"\n' >> "$work/pkassign/.github/workflows/release.yml"
out="$(cd "$work/pkassign" && git add -A && sh "$S" 2>&1)" \
  && { echo "FAIL: an assignment of stage_product.sh's path, or an echo'd string spelling a call, must not satisfy check 23"; exit 1; }
first_is "$out" stage-product \
  || { echo "FAIL: check 23 must be what fails when stage_product.sh's path is only assigned or echoed: $out"; exit 1; }

mkrepo "$work/pkc"; printf '#!/bin/sh\npkgbuild --root stage out.pkg\n' > "$work/pkc/build/package.sh"
printf '      # - run: sh "$SHIPYARD_SCRIPTS/check-artifact-conformance.sh"\n' >> "$work/pkc/.github/workflows/release.yml"
(cd "$work/pkc" && git add -A && sh "$S" >/dev/null 2>&1) && { echo "FAIL: a commented-out conformance call must not count as wired"; exit 1; }
printf '\n## Conformance deviations\n\n- artifact-conformance: ships a disk image, not a Mavergreen pkg\n- product-layout: ships a disk image, not a Mavergreen pkg\n' >> "$work/pkc/INGREDIENTS.md"
(cd "$work/pkc" && git add -A && sh "$S" >/dev/null 2>&1) || { echo "FAIL: declared artifact-conformance and product-layout deviations should excuse it: $(cd "$work/pkc" && sh "$S" 2>&1)"; exit 1; }
mkrepo "$work/pks"; printf '      - run: sh "$SHIPYARD_SCRIPTS/sign_and_appcast.sh" --product w --feed-dir dist --pkg dist/x.pkg\n  scan:\n    uses: Mavergreen/shipyard/.github/workflows/scan-for-key.yml@v1\n' >> "$work/pks/.github/workflows/release.yml"
out="$(cd "$work/pks" && git add -A && sh "$S" 2>&1 || true)"
has_id "$out" artifact-checks-wired || { echo "FAIL: a repo that signs an appcast builds a pkg, and must run conformance: $out"; exit 1; }
mkrepo "$work/pkt"; printf '#!/bin/sh\npkgbuild --root x t.pkg\n' > "$work/pkt/tests/fixture.sh"
(cd "$work/pkt" && git add -A && sh "$S" >/dev/null 2>&1) || { echo "FAIL: a pkgbuild in tests/ is a fixture, not a product: $(cd "$work/pkt" && sh "$S" 2>&1)"; exit 1; }

# spec: SKILL.md "Family conventions" check 22 -- delegated to check-host-tools.sh, whose own
#       test covers the rule; this proves the gate CALLS it. The baseline declares no host, so it
#       has not adopted the split and passes (the baseline case, first in
#       tests/check-family-conventions-1-test.sh); one declared script adopts it.
mkrepo "$work/host"; printf '#!/bin/sh\n# platform: host-agnostic\notool -L x\n' > "$work/host/tests/a-test.sh"
printf '#!/bin/sh\n# platform: host-agnostic\nprintf "https://example.com/v%%s\\n" "$1"\n' > "$work/host/build/upstream-release-notes-url.sh"
(cd "$work/host" && git add -A) >/dev/null 2>&1
out="$(cd "$work/host" && sh "$S" 2>&1)" && { echo "FAIL: a host-agnostic script running otool should fail check 22"; exit 1; }
first_is "$out" host-tools || { echo "FAIL: check 22 should be a host-tools failure: $out"; exit 1; }
printf '#!/bin/sh\n# platform: host-agnostic\nexit 0\n' > "$work/host/tests/a-test.sh"
(cd "$work/host" && git add -A && sh "$S" >/dev/null 2>&1) || { echo "FAIL: a clean, declared repo should pass check 22: $(cd "$work/host" && sh "$S" 2>&1)"; exit 1; }

# spec: scripts/check-family-conventions.sh check 24 -- the registry check applies to a repo that
#       builds a .pkg and already satisfies checks 21 and 23, so $work/pk is the compliant pkg repo
#       from the check 21/23 cases, rebuilt here because those cases live in another file.
mkrepo "$work/pk"; printf '#!/bin/sh\npkgbuild --root stage --identifier dev.mavergreen.w out.pkg\n' > "$work/pk/build/package.sh"
printf 'sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage stage --product w --name W --version 1 --scripts-out scr\n' >> "$work/pk/build/package.sh"
printf '      - run: sh "$SHIPYARD_SCRIPTS/artifact-facts.sh" dist "$FULL" | sh "$SHIPYARD_SCRIPTS/check-artifact-conformance.sh"\n' >> "$work/pk/.github/workflows/release.yml"
(cd "$work/pk" && git add -A) >/dev/null 2>&1

# spec: SKILL.md "Family conventions" check 24 -- a pkg-building repo is one scripts/product-names
#       assigns products to, compared by name (a fork runs the same gate).
out="$(cd "$work/pk" && GITHUB_REPOSITORY=Mavergreen/nobody-registered-this sh "$S" 2>&1)" \
  && { echo "FAIL: check 24: a pkg repo the registry does not name must fail"; exit 1; }
first_is "$out" registered || { echo "FAIL should be a registered failure: $out"; exit 1; }
(cd "$work/pk" && GITHUB_REPOSITORY=Mavergreen/golang-126 sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 24: a registered repo passes: $(cd "$work/pk" && GITHUB_REPOSITORY=Mavergreen/golang-126 sh "$S" 2>&1)"; exit 1; }
(cd "$work/pk" && GITHUB_REPOSITORY=someone/golang-126 sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 24 compares the repo's name, not its owner"; exit 1; }
(cd "$work/ok" && GITHUB_REPOSITORY=Mavergreen/nobody-registered-this sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 24: a repo that builds no pkg ships no short name, and is not asked"; exit 1; }
out="$(cd "$work/pk" && MAVERGREEN_PRODUCT_NAMES="$work/absent-registry" GITHUB_REPOSITORY=Mavergreen/golang-126 sh "$S" 2>&1)" \
  && { echo "FAIL: check 24: a registry that cannot be read must fail the gate"; exit 1; }
first_is "$out" registered || { echo "FAIL should be a registered failure: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'absent-registry' \
  || { echo "FAIL: check 24 must pass on product-name.sh's own reason: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'assigns no product' \
  && { echo "FAIL: check 24 must not call an unreadable registry an unregistered repo: $out"; exit 1; }

# spec: SKILL.md "Family conventions" check 25 -- the family is retiring Rosetta (see the
#       conventions skill, "Rosetta"). An undeclared translated-arch call must fail, naming
#       rosetta and the declaration form; a declared rosetta:<path> deviation must excuse it; a
#       comment-only mention must pass undeclared; and there is no tests/ exemption -- a call
#       there must fail undeclared and pass declared, exactly like one anywhere else.
# spec: scripts/check-family-conventions.sh check 25's own self-match-avoidance rule -- these two
#       pieces, joined only through %s at printf time, keep this file's own source from spelling
#       the flag contiguously (the same avoidance check 16 makes by writing "package[s]").
_arch="arch"; _x64="-x86_64"
mkrepo "$work/rosetta"
printf '#!/bin/sh\narch -x86_64 ./host-tool\n' > "$work/rosetta/build/cross.sh"
(cd "$work/rosetta" && git add -A) >/dev/null 2>&1
out="$(cd "$work/rosetta" && sh "$S" 2>&1)" && { echo "FAIL: check 25: an undeclared translated-arch call must fail"; exit 1; }
first_is "$out" rosetta || { echo "FAIL should be a rosetta failure: $out"; exit 1; }
printf '\n## Conformance deviations\n\n- rosetta:build/cross.sh: the cross build runs a host tool under Rosetta; reconsider when an arm64 host tool exists, and at the latest before macOS 28\n' >> "$work/rosetta/INGREDIENTS.md"
(cd "$work/rosetta" && git add -A && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 25: a declared rosetta:<path> deviation should excuse it: $(cd "$work/rosetta" && sh "$S" 2>&1)"; exit 1; }

# spec: scripts/check-family-conventions.sh check 25 -- the other two spellings the gate scans for.
mkrepo "$work/rosetta2"; printf '#!/bin/sh\narch -arch x86_64 ./host-tool\n' > "$work/rosetta2/build/cross.sh"
(cd "$work/rosetta2" && git add -A) >/dev/null 2>&1
(cd "$work/rosetta2" && sh "$S" >/dev/null 2>&1) && { echo "FAIL: check 25: undeclared 'arch -arch x86_64' must fail"; exit 1; }
mkrepo "$work/rosetta3"; printf '#!/bin/sh\n/usr/bin/arch -x86_64 ./host-tool\n' > "$work/rosetta3/build/cross.sh"
(cd "$work/rosetta3" && git add -A) >/dev/null 2>&1
(cd "$work/rosetta3" && sh "$S" >/dev/null 2>&1) && { echo "FAIL: check 25: undeclared '/usr/bin/arch -x86_64' must fail"; exit 1; }

# spec: scripts/check-family-conventions.sh check 25 -- a comment-only mention is prose, not a call.
mkrepo "$work/rosettac"
printf '#!/bin/sh\n# %s %s ./host-tool -- no longer true, kept as a note\nexit 0\n' "$_arch" "$_x64" > "$work/rosettac/build/cross.sh"
(cd "$work/rosettac" && git add -A && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 25: a comment-only mention of the flag must not fail: $(cd "$work/rosettac" && sh "$S" 2>&1)"; exit 1; }

# spec: SKILL.md "Family conventions" check 25 -- there is no tests/ exemption, per "Rosetta",
#       above: a best-effort test that SKIPs (77) without Rosetta still runs translated when it
#       doesn't skip, so a hit under tests/ fails undeclared and passes declared, like any other.
mkrepo "$work/rosettat"
printf '#!/bin/sh\narch -x86_64 ./product --version\n' > "$work/rosettat/tests/rosetta-smoke.sh"
(cd "$work/rosettat" && git add -A) >/dev/null 2>&1
(cd "$work/rosettat" && sh "$S" >/dev/null 2>&1) \
  && { echo "FAIL: check 25: a call under tests/ must fail undeclared: $(cd "$work/rosettat" && sh "$S" 2>&1)"; exit 1; }
printf '\n## Conformance deviations\n\n- rosetta:tests/rosetta-smoke.sh: best-effort smoke that runs the shipped x86_64 product under Rosetta when present, SKIPping (77) otherwise; reconsider when an arm64 test box exists, and at the latest before macOS 28\n' >> "$work/rosettat/INGREDIENTS.md"
(cd "$work/rosettat" && git add -A && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 25: a declared rosetta:tests/rosetta-smoke.sh deviation should excuse it: $(cd "$work/rosettat" && sh "$S" 2>&1)"; exit 1; }

# spec: SKILL.md "Family conventions" check 25 -- the regex matches anywhere on a non-comment
#       line, not just at command position (unlike check 23). A trailing " #..." remark is
#       stripped before matching, so an unrelated command with one does not force a bogus
#       declaration; a quoted MENTION on an otherwise-real command line still counts, because
#       excluding quotes reliably is not practical in BWK awk/sed -- both cases the checks table's
#       row 25 now says explicitly.
mkrepo "$work/rosettatrail"
printf '#!/bin/sh\necho hello there # not Rosetta, just mentions arch -x86_64 in a note\n' > "$work/rosettatrail/build/cross.sh"
(cd "$work/rosettatrail" && git add -A && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 25: a trailing # remark mentioning arch -x86_64 must not force a declaration: $(cd "$work/rosettatrail" && sh "$S" 2>&1)"; exit 1; }
mkrepo "$work/rosettaquote"
printf '#!/bin/sh\necho "legacy builds used %s %s here"\n' "$_arch" "$_x64" > "$work/rosettaquote/build/cross.sh"
(cd "$work/rosettaquote" && git add -A && sh "$S" >/dev/null 2>&1) \
  && { echo "FAIL: check 25: a quoted mention of the flag on a real command line must still count (documented limitation)"; exit 1; }

# spec: SKILL.md "Family conventions" check 25 -- a workflow's YAML run: block is scanned like any
#       other tracked file; the check does no YAML parsing, so indentation inside the block scalar
#       does not matter.
mkrepo "$work/rosettayml"
printf 'jobs:\n  build:\n    steps:\n      - run: |\n          %s %s ./cross-tool\n' "$_arch" "$_x64" > "$work/rosettayml/.github/workflows/x.yml"
(cd "$work/rosettayml" && git add -A) >/dev/null 2>&1
out="$(cd "$work/rosettayml" && sh "$S" 2>&1)" && { echo "FAIL: check 25: an undeclared translated-arch call inside a workflow run: block must fail"; exit 1; }
first_is "$out" rosetta || { echo "FAIL should be a rosetta failure: $out"; exit 1; }
printf '\n## Conformance deviations\n\n- rosetta:.github/workflows/x.yml: the release job cross-builds a host tool under Rosetta\n' >> "$work/rosettayml/INGREDIENTS.md"
(cd "$work/rosettayml" && git add -A && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 25: a declared rosetta:.github/workflows/x.yml deviation should excuse the workflow hit: $(cd "$work/rosettayml" && sh "$S" 2>&1)"; exit 1; }

# spec: SKILL.md "Family conventions" check 25 -- softwareupdate --install-rosetta is the plainest
#       Rosetta dependency there is: it installs the translator itself.
mkrepo "$work/rosettainstall"
printf '#!/bin/sh\nsoftwareupdate --install-rosetta --agree-to-license\n' > "$work/rosettainstall/build/prep.sh"
(cd "$work/rosettainstall" && git add -A) >/dev/null 2>&1
out="$(cd "$work/rosettainstall" && sh "$S" 2>&1)" && { echo "FAIL: check 25: an undeclared softwareupdate Rosetta-install call must fail"; exit 1; }
first_is "$out" rosetta || { echo "FAIL should be a rosetta failure: $out"; exit 1; }
printf '\n## Conformance deviations\n\n- rosetta:build/prep.sh: installs Rosetta so a later step can run x86_64 tools\n' >> "$work/rosettainstall/INGREDIENTS.md"
(cd "$work/rosettainstall" && git add -A && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 25: a declared rosetta:<path> deviation should excuse softwareupdate --install-rosetta: $(cd "$work/rosettainstall" && sh "$S" 2>&1)"; exit 1; }

# spec: SKILL.md "Family conventions" check 26 -- a Renovate config tracked anywhere but
#       .github/renovate.json fails, naming the path and the git mv. The baseline (only
#       .github/renovate.json) passes in the first case of
#       tests/check-family-conventions-1-test.sh. Each location Renovate itself searches
#       is a case; a repo holding BOTH fails (one is dead config); an UNTRACKED stray is not the
#       repo's (check 7's rule); a declared renovate-path:<path> deviation excuses exactly that path.
for loc in renovate.json renovate.json5 .renovaterc .renovaterc.json .renovaterc.json5 \
           .github/renovate.json5 .gitlab/renovate.json .gitlab/renovate.json5; do
  d="$work/rp-$(printf '%s' "$loc" | tr '/.' '__')"
  mkrepo "$d"
  mkdir -p "$d/$(dirname "$loc")"; printf '{"extends":["github>Mavergreen/shipyard"]}\n' > "$d/$loc"
  (cd "$d" && git add -A) >/dev/null 2>&1
  out="$(cd "$d" && sh "$S" 2>&1)" && { echo "FAIL: check 26: tracked $loc beside .github/renovate.json must fail"; exit 1; }
  first_is "$out" renovate-path || { echo "FAIL: check 26 should be a renovate-path failure for $loc: $out"; exit 1; }
done

# spec: SKILL.md "Family conventions" check 26 -- the OTHER way round: the alternate path alone (no
#       .github/renovate.json), the very shape that exempts a repo from checks 4, 4b and 13, fails too.
mkrepo "$work/rp-only"
git -C "$work/rp-only" mv .github/renovate.json renovate.json
out="$(cd "$work/rp-only" && sh "$S" 2>&1)" && { echo "FAIL: check 26: a root renovate.json alone must fail"; exit 1; }
first_is "$out" renovate-path || { echo "FAIL should be a renovate-path failure: $out"; exit 1; }

mkrepo "$work/rp-untracked"; printf '{}\n' > "$work/rp-untracked/renovate.json"
(cd "$work/rp-untracked" && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 26: an UNTRACKED renovate.json is not the repo's and must not fail: $(cd "$work/rp-untracked" && sh "$S" 2>&1)"; exit 1; }

printf '\n## Conformance deviations\n\n- renovate-path:renovate.json: legacy consumer config read by an external bot; move before the next release\n' >> "$work/rp-renovate_json/INGREDIENTS.md"
(cd "$work/rp-renovate_json" && git add -A && sh "$S" >/dev/null 2>&1) \
  || { echo "FAIL: check 26: a declared renovate-path:renovate.json deviation should excuse it: $(cd "$work/rp-renovate_json" && sh "$S" 2>&1)"; exit 1; }
(cd "$work/rp-renovate_json5" && git add -A && sh "$S" >/dev/null 2>&1) \
  && { echo "FAIL: check 26: a deviation for renovate.json must not excuse renovate.json5"; exit 1; }

# spec: SKILL.md "Family conventions" check 27 -- .superpowers/ and .idea/ are ignored, and nothing is
#       tracked under .superpowers/, docs/superpowers/ or .idea/. The baseline (mkrepo) is the positive control.
for form in '.superpowers/' '/.superpowers/' '.superpowers' '/.superpowers'; do
  d="$work/sp-ok$(printf '%s' "$form" | tr -c 'A-Za-z' _)"; mkrepo "$d"
  printf '/VERSION\n%s\n.idea/\n' "$form" > "$d/.gitignore"
  (cd "$d" && sh "$S" >/dev/null 2>&1) || { echo "FAIL: check 27: ignore line '$form' should pass: $(cd "$d" && sh "$S" 2>&1)"; exit 1; }
done
for form in '.idea/' '/.idea/' '.idea' '/.idea'; do
  d="$work/idea-ok$(printf '%s' "$form" | tr -c 'A-Za-z' _)"; mkrepo "$d"
  printf '/VERSION\n.superpowers/\n%s\n' "$form" > "$d/.gitignore"
  (cd "$d" && sh "$S" >/dev/null 2>&1) || { echo "FAIL: check 27: ignore line '$form' should pass: $(cd "$d" && sh "$S" 2>&1)"; exit 1; }
done

mkrepo "$work/sp1"; printf '/VERSION\n.idea/\n' > "$work/sp1/.gitignore"
out="$(cd "$work/sp1" && sh "$S" 2>&1)" && { echo "FAIL: check 27: no .superpowers/ ignore line must fail"; exit 1; }
first_is "$out" superpowers-ignored || { echo "FAIL should be a superpowers-ignored failure: $out"; exit 1; }

mkrepo "$work/sp-dot"; printf '/VERSION\nxsuperpowers/\nxidea/\n' > "$work/sp-dot/.gitignore"
out="$(cd "$work/sp-dot" && sh "$S" 2>&1)" && { echo "FAIL: check 27: xsuperpowers/ and xidea/ must not count as ignoring the dotted dirs"; exit 1; }
[ "$(printf '%s\n' "$out" | grep -c '^superpowers-ignored: ')" -eq 2 ] || { echo "FAIL: check 27 should fail both for the undotted lines: $out"; exit 1; }

mkrepo "$work/sp2"; printf '/VERSION\n.superpowers/\n' > "$work/sp2/.gitignore"
out="$(cd "$work/sp2" && sh "$S" 2>&1)" && { echo "FAIL: check 27: no .idea/ ignore line must fail"; exit 1; }
first_is "$out" superpowers-ignored || { echo "FAIL should be a superpowers-ignored failure: $out"; exit 1; }

for dir in .superpowers docs/superpowers .idea; do
  tracked="$dir/sub/f.txt"
  d="$work/tr-$(printf '%s' "$dir" | tr -c 'A-Za-z' _)"; mkrepo "$d"
  mkdir -p "$d/$dir/sub"; printf 'x\n' > "$d/$tracked"
  (cd "$d" && git add -f "$tracked") >/dev/null 2>&1
  out="$(cd "$d" && sh "$S" 2>&1)" && { echo "FAIL: check 27: a file tracked under $dir must fail"; exit 1; }
  first_is "$out" superpowers-ignored || { echo "FAIL: check 27 should be a superpowers-ignored failure for $dir: $out"; exit 1; }
done

mkrepo "$work/sp-untracked"; mkdir -p "$work/sp-untracked/.idea"; printf 'x\n' > "$work/sp-untracked/.idea/misc.xml"
(cd "$work/sp-untracked" && sh "$S" >/dev/null 2>&1) || { echo "FAIL: check 27: an untracked, ignored .idea/ must pass"; exit 1; }

mkrepo "$work/sp-nogit"; rm -rf "$work/sp-nogit/.git"
out="$(cd "$work/sp-nogit" && sh "$S" 2>&1)" && { echo "FAIL: check 27: outside a git checkout must fail (cannot verify)"; exit 1; }
first_is "$out" tracked-files || { echo "FAIL should be a tracked-files failure: $out"; exit 1; }

echo "PASS: check-family-conventions-4"
