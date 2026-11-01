#!/bin/sh
# platform: host-agnostic
#   usage: check-family-rules-test.sh
#          Runs the gate (scripts/check-family-conventions.sh) over edits of the pr-trigger pass
#          fixture for the family rules that product repos used to hand-roll: inline cases cover the
#          exceptions and edge shapes. The fixtures themselves run in check-fixtures-run.sh.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
S="$here/scripts/check-family-conventions.sh"
fx="$here/tests/fixtures/checks"
. "$here/tests/lib/fixture_tree.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/check-family-rules-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
. "$here/tests/lib/deviation_tree.sh"
fail() { echo "FAIL $1"; exit 1; }
unset GITHUB_REPOSITORY

run() {  # $1 = a fixture tree holding FILES; the gate runs in a git-init copy of it, output in $w/out
  rm -rf "$w/copy"; mkdir "$w/copy"
  (cd "$1" && tar cf - .) | (cd "$w/copy" && tar xf -)
  (cd "$w/copy" && git init -q && while IFS= read -r f; do git add -f -- "$f"; done < FILES)
  (cd "$w/copy" && sh "$S") > "$w/out" 2>&1
}

failing() {  # the ids the last run reported failing, one per line
  sed -n 's/^  more: shipyard-check --explain //p' "$w/out" | sort -u
}
only_fails() {  # $1 = what ran, $2 = the one id that may fail
  [ "$(failing)" = "$2" ] || fail "$1 should fail only $2, got: $(failing | tr '\n' ' ')"
}

fresh() {  # $1 = name; a copy of the baseline pass tree to edit in place
  rm -rf "$w/$1"; mkdir "$w/$1"
  fixture_tree "$fx" "$fx/pr-trigger/pass" "$w/$1"
  mkdir -p "$w/$1/build"
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
  only_fails "$1" "$2"
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
deviation "$w/devpr" pr-trigger no-build '*' 'no build to gate'
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
printf '12.3\n' > "$w/otherversion/.mavergreen/upstream/VERSION"
printf '#!/bin/sh\necho "node 112.34 and 2.12.30 and ABC12.3 and 12.3.1 are all different"\n' > "$w/otherversion/build/fetch.sh"
printf 'build/fetch.sh\n' >> "$w/otherversion/FILES"
ok otherversion

fresh dotted
printf '12.3\n' > "$w/dotted/.mavergreen/upstream/VERSION"
printf '#!/bin/sh\necho "12.3."\n' > "$w/dotted/build/fetch.sh"
printf 'build/fetch.sh\n' >> "$w/dotted/FILES"
refused dotted no-hardcoded-version

fresh vprefix
printf '12.3\n' > "$w/vprefix/.mavergreen/upstream/VERSION"
printf '#!/bin/sh\necho "get v12.3 now"\n' > "$w/vprefix/build/fetch.sh"
printf 'build/fetch.sh\n' >> "$w/vprefix/FILES"
refused vprefix no-hardcoded-version

fresh hardcoded-dev
printf '#!/bin/sh\necho "fetching 1.0.0"\n' > "$w/hardcoded-dev/build/fetch.sh"
printf 'build/fetch.sh\n' >> "$w/hardcoded-dev/FILES"
deviation "$w/hardcoded-dev" no-hardcoded-version fetch build/fetch.sh 'the pin is the contract'
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

fresh legacyversion
printf '12.3\n' > "$w/legacyversion/UPSTREAM_VERSION"
printf '#!/bin/sh\necho "get v12.3 now"\n' > "$w/legacyversion/build/fetch.sh"
printf 'build/fetch.sh\n' >> "$w/legacyversion/FILES"
ok legacyversion

fresh vignore
printf 'VERSION\n.superpowers/\n.idea/\n' > "$w/vignore/.gitignore"
ok vignore

fresh flowtags
seton flowtags "on: {push: {branches: [main], tags: ['v*']}, pull_request: {branches: [main]}}"
refused flowtags no-tags-trigger

fresh flowclean
seton flowclean "on: {push: {branches: [main]}, pull_request: {branches: [main]}}"
ok flowclean

fresh spacename
printf '12.3\n' > "$w/spacename/.mavergreen/upstream/VERSION"
printf '#!/bin/sh\necho "get v12.3 now"\n' > "$w/spacename/build/my fetch.sh"
printf 'build/my fetch.sh\n' >> "$w/spacename/FILES"
refused spacename no-hardcoded-version

fresh sourcescurl
printf '#!/bin/sh\n. "$SHIPYARD_SCRIPTS/mavergreen_fetch.sh"\ncurl -fsSL "$1"\n' > "$w/sourcescurl/build/f.sh"
printf 'build/f.sh\n' >> "$w/sourcescurl/FILES"
refused sourcescurl bare-curl

fresh librarycurl
mkdir -p "$w/librarycurl/scripts"
printf '#!/bin/sh\ncurl -fsSL "$1"\n' > "$w/librarycurl/scripts/mavericks_fetch.sh"
printf 'scripts/mavericks_fetch.sh\n' >> "$w/librarycurl/FILES"
ok librarycurl

fresh keywordcurl
printf '#!/bin/sh\nif ! curl -fsS "$1"; then exit 1; fi\nwhile curl -s "$2"; do :; done\n{ curl -s "$3"; }\n' > "$w/keywordcurl/build/f.sh"
printf 'build/f.sh\n' >> "$w/keywordcurl/FILES"
refused keywordcurl bare-curl

fresh prosecurl
printf '#!/bin/sh\n# curl and brew and apt-get\necho "use curl, not wget, brew or port or apt"\ncommand -v curl >/dev/null\nmy_curl_wrapper x\nxcurl y\n' > "$w/prosecurl/build/f.sh"
printf 'build/f.sh\n' >> "$w/prosecurl/FILES"
ok prosecurl

fresh compositeapt
mkdir -p "$w/compositeapt/.github/actions/i"
printf "name: i\nruns:\n  using: composite\n  steps:\n    - shell: sh\n      run: sudo apt-get install -y bats\n" > "$w/compositeapt/.github/actions/i/action.yml"
printf '.github/actions/i/action.yml\n' >> "$w/compositeapt/FILES"
refused compositeapt apt

fresh testsmayname
printf '#!/bin/sh\nbrew install x\ncurl y\n' > "$w/testsmayname/tests/b-test.sh"
printf 'tests/b-test.sh\n' >> "$w/testsmayname/FILES"
ok testsmayname

echo "PASS check-family-rules"
