#!/bin/sh
# platform: host-agnostic
#   usage: check-family-rules-test.sh
#          Runs the gate (scripts/check-family-conventions.sh) over tests/fixtures/checks/<id>/ for the
#          family rules that product repos used to hand-roll: a pass fixture is clean, a fail* fixture
#          fails with its own id, and inline cases cover the exceptions and edge shapes.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
S="$here/scripts/check-family-conventions.sh"
fx="$here/tests/fixtures/checks"
w="$(mktemp -d "${TMPDIR:-/tmp}/check-family-rules-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $1"; exit 1; }
unset GITHUB_REPOSITORY

run() {  # $1 = a fixture tree holding FILES; the gate runs in a git-init copy of it, output in $w/out
  rm -rf "$w/copy"; mkdir "$w/copy"
  (cd "$1" && tar cf - .) | (cd "$w/copy" && tar xf -)
  (cd "$w/copy" && git init -q && while IFS= read -r f; do git add -f -- "$f"; done < FILES)
  (cd "$w/copy" && sh "$S") > "$w/out" 2>&1
}

IDS="pr-trigger publish-order renovate-extends-preset renovate-json-valid no-hardcoded-version
     no-tags-trigger no-pull-request-target checkout-drops-credentials permissions-contents-read
     upstream-version-bare version-ignored"

for id in $IDS; do
  [ -d "$fx/$id/pass" ] || fail "$id has a pass fixture"
  run "$fx/$id/pass" || fail "$id/pass should be clean: $(cat "$w/out")"
  set -- "$fx/$id"/fail*
  [ -d "$1" ] || fail "$id has a fail fixture"
  for d in "$@"; do
    if run "$d"; then fail "$id/$(basename "$d") should fail"; fi
    grep -q "^$id: " "$w/out" || fail "$id/$(basename "$d") should fail $id: $(cat "$w/out")"
    grep -q '^  fix: ' "$w/out" || fail "$id/$(basename "$d") names a fix"
  done
done

fresh() {  # $1 = name; a copy of the baseline pass tree to edit in place
  rm -rf "$w/$1"; mkdir "$w/$1"
  (cd "$fx/pr-trigger/pass" && tar cf - .) | (cd "$w/$1" && tar xf -)
}
wf=".github/workflows/release.yml"
seton() {  # $1 = name, $2 = the new on: block, \n-separated
  ON="$(printf '%b' "$2")" awk '/^on:/ { print ENVIRON["ON"]; skip = 1; next } /^permissions:/ { skip = 0 } !skip' \
    "$w/$1/$wf" > "$w/$1/wf.new" && mv "$w/$1/wf.new" "$w/$1/$wf"
}
ok() {  # $1 = name; the edited copy must be clean
  run "$w/$1" || fail "$1 should be clean: $(cat "$w/out")"
}
refused() {  # $1 = name, $2 = id
  if run "$w/$1"; then fail "$1 should fail $2"; fi
  grep -q "^$2: " "$w/out" || fail "$1 should fail $2: $(cat "$w/out")"
}

fresh ignoretests
printf '{"extends":["github>Mavergreen/shipyard"],"ignoreTests":true}\n' > "$w/ignoretests/.github/renovate.json"
seton ignoretests 'on:\n  push:\n    branches: [main]'
ok ignoretests

fresh pushall
seton pushall "on:
  push:
    branches: ['**']"
ok pushall

fresh barepr
seton barepr 'on:
  push:
    branches: [main]
  pull_request:'
ok barepr

fresh prlist
seton prlist "on:
  push:
    branches: [main]
  pull_request:
    branches:
      - 'main'"
ok prlist

fresh inlineon
seton inlineon 'on: [push, pull_request]'
ok inlineon

fresh devpr
seton devpr 'on:
  push:
    branches: [main]'
printf '# x\n\n## Conformance deviations\n\n- pr-trigger: no build to gate\n' > "$w/devpr/INGREDIENTS.md"
ok devpr

fresh norenovate
rm "$w/norenovate/.github/renovate.json"; grep -v 'renovate.json' "$w/norenovate/FILES" > "$w/f"; mv "$w/f" "$w/norenovate/FILES"
refused norenovate renovate-extends-preset

fresh subpreset
printf '{"extends":["config:recommended","github>Mavergreen/shipyard:strict"]}\n' > "$w/subpreset/.github/renovate.json"
ok subpreset

fresh sibling
printf '{"description":"github>Mavergreen/shipyard","extends":["config:recommended"]}\n' > "$w/sibling/.github/renovate.json"
refused sibling renovate-extends-preset

fresh otherversion
printf '12.3\n' > "$w/otherversion/UPSTREAM_VERSION"
printf '#!/bin/sh\necho "node 112.34 and 2.12.30 and ABC12.3 and 12.3.1 are all different"\n' > "$w/otherversion/build/fetch.sh"
printf 'build/fetch.sh\n' >> "$w/otherversion/FILES"
ok otherversion

fresh dotted
printf '12.3\n' > "$w/dotted/UPSTREAM_VERSION"
printf '#!/bin/sh\necho "12.3."\n' > "$w/dotted/build/fetch.sh"
printf 'build/fetch.sh\n' >> "$w/dotted/FILES"
refused dotted no-hardcoded-version

fresh vprefix
printf '12.3\n' > "$w/vprefix/UPSTREAM_VERSION"
printf '#!/bin/sh\necho "get v12.3 now"\n' > "$w/vprefix/build/fetch.sh"
printf 'build/fetch.sh\n' >> "$w/vprefix/FILES"
refused vprefix no-hardcoded-version

fresh hardcoded-dev
printf '#!/bin/sh\necho "fetching 1.0.0"\n' > "$w/hardcoded-dev/build/fetch.sh"
printf 'build/fetch.sh\n' >> "$w/hardcoded-dev/FILES"
printf '# x\n\n## Conformance deviations\n\n- no-hardcoded-version:build/fetch.sh: the pin is the contract\n' > "$w/hardcoded-dev/INGREDIENTS.md"
ok hardcoded-dev

fresh tests-may-name
printf '#!/bin/sh\necho "1.0.0"\n' > "$w/tests-may-name/tests/b-test.sh"
printf 'tests/b-test.sh\n' >> "$w/tests-may-name/FILES"
ok tests-may-name

fresh tagsinput
seton tagsinput 'on:
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      tags:
        type: string'
ok tagsinput

fresh ptag
printf "name: other
on:
  push:
    tags: ['v*']
jobs:
  j:
    steps:
      - run: true
" > "$w/ptag/.github/workflows/other.yml"
printf '.github/workflows/other.yml\n' >> "$w/ptag/FILES"
refused ptag no-tags-trigger

fresh vfile
printf '1.0.0\n\n' > "$w/vfile/UPSTREAM_VERSION"
ok vfile
printf '1.0.0\n1.0.1\n' > "$w/vfile/UPSTREAM_VERSION"
refused vfile upstream-version-bare
printf '1.0.0 \n' > "$w/vfile/UPSTREAM_VERSION"
refused vfile upstream-version-bare

fresh vignore
printf 'VERSION\n.superpowers/\n.idea/\n' > "$w/vignore/.gitignore"
ok vignore

echo "PASS check-family-rules"
