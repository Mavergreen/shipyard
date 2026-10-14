#!/bin/sh
# platform: host-agnostic
# spec: tests/check-family-conventions-1-test.sh through -4-test.sh -- those four files source
#       this one and never run it; the caller sets here, and this file builds the compliant
#       baseline $work/ok plus the helpers that more than one place needs.
unset GITHUB_REPOSITORY
S="$here/../scripts/check-family-conventions.sh"
SHIPYARD_CHECK_DIR="$here/../scripts"
. "$SHIPYARD_CHECK_DIR/lib/py.sh"
first_is() {
  case "$(printf '%s\n' "$1" | awk 'prev != "" && /^  fix: / { print prev; exit } { prev = $0 }')" in "$2: "*) return 0 ;; esac
  return 1
}
has_id() {
  printf '%s\n' "$1" | grep -q "^$2: "
}
work="$(mktemp -d "${TMPDIR:-/tmp}/family-conventions.XXXXXX")"; trap 'rm -rf "$work"' EXIT  # template: 10.9 BSD mktemp requires one

# spec: scripts/check-family-conventions.sh -- the baseline is a repo that satisfies EVERY
#       check, so each case below can turn exactly one thing off. Since check 14 the release
#       body has to come from the shared generator, so the
#       baseline calls release-notes.sh and hands the publisher the very path it was given as
#       --out; a fixture that still hand-waved `--notes-file "$NOTES"` would fail 14 in thirty
#       unrelated cases.
mkrepo() {  # $1 = dir
  mkdir -p "$1/.github/workflows" "$1/tests"
  cat > "$1/.github/workflows/release.yml" <<'YML'
name: release
on:
  push:
    tags: ['*-mavericks.*']
concurrency:
  group: release-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
jobs:
  build:
    steps:
      - run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh" --record
      - run: sh "$SHIPYARD_SCRIPTS/run-repo-tests.sh"
      - run: |
          sh "$SHIPYARD_SCRIPTS/release-notes.sh" --tag "$TAG" --version "$FULL" \
            --product Widget --min-os 10.9.5 --out dist/RELEASE_NOTES.md
      - run: sh "$SHIPYARD_SCRIPTS/assert-tree-clean.sh"
      - run: gh release create "$TAG" dist/* --notes-file dist/RELEASE_NOTES.md
YML
  printf '# Build ingredients\n' > "$1/INGREDIENTS.md"
  printf '{"extends":["github>Mavergreen/shipyard"]}\n' > "$1/.github/renovate.json"
  printf '#!/bin/sh\nexit 0\n' > "$1/tests/a-test.sh"
  # spec: scripts/check-family-conventions.sh -- a compliant repo commits UPSTREAM_VERSION and
  #       gitignores VERSION (a build product), and the gate asks git what is tracked -- so the
  #       fixture has to be a real checkout. It also
  #       says where upstream's own release notes live, for a release that ships a new upstream.
  printf '1.0.0\n' > "$1/UPSTREAM_VERSION"
  printf '/VERSION\n.superpowers/\n.idea/\n' > "$1/.gitignore"
  mkdir -p "$1/build"
  printf '#!/bin/sh\nprintf "https://example.com/v%%s\\n" "$1"\n' > "$1/build/upstream-release-notes-url.sh"
  (cd "$1" && git init -q && git add -A) >/dev/null 2>&1
}
mkrepo "$work/ok"

# spec: SKILL.md "Family conventions" check 12 -- sign_and_appcast.sh writes <feed-dir>/<product>.xml
#       itself, so a call that omits --product or --feed-dir, or redirects its stdout, is the retired
#       `--pkg ... > dist/appcast.xml` shape; a call continued over lines with a trailing \ is one call.
signs() {  # $1 = dir, $2 = the lines of one run: | block
  mkrepo "$1"
  { printf '      - run: |\n'; printf '%s\n' "$2" | sed 's/^/          /'
    printf '      - run: sh "$SHIPYARD_SCRIPTS/artifact-facts.sh" dist "$FULL" | sh "$SHIPYARD_SCRIPTS/check-artifact-conformance.sh"\n'
    printf '      - run: sh "$SHIPYARD_SCRIPTS/stage_product.sh" --stage stage --product w --name W --version 1 --scripts-out scr\n'
    printf '  scan:\n    needs: [build]\n    if: always()\n    uses: Mavergreen/shipyard/.github/workflows/scan-for-key.yml@v1\n'
  } >> "$1/.github/workflows/release.yml"
  (cd "$1" && git add -A) >/dev/null 2>&1
}
sa_refused() {  # $1 = dir, $2 = what the case is
  out="$(cd "$1" && sh "$S" 2>&1)" && { echo "FAIL: check 12: $2 must fail"; exit 1; }
  first_is "$out" sign-call-shape \
    || { echo "FAIL: check 12: $2 must be refused for its shape: $out"; exit 1; }
}

# spec: scripts/check-family-conventions.sh check 23 -- a keyword that runs its command (if, elif,
#       while, until, !) is still command position, /bin/sh is sh, sh takes option flags, and a
#       quoted variable may end mid-path: each of these spellings is a call.
pkcall() {  # $1 dir  $2 the build script's body after its pkgbuild line
  mkrepo "$1"; printf '#!/bin/sh\npkgbuild --root stage --identifier dev.mavergreen.w out.pkg\n%s\n' "$2" > "$1/build/package.sh"
  printf '      - run: sh "$SHIPYARD_SCRIPTS/artifact-facts.sh" dist "$FULL" | sh "$SHIPYARD_SCRIPTS/check-artifact-conformance.sh"\n' >> "$1/.github/workflows/release.yml"
  (cd "$1" && git add -A && sh "$S" >/dev/null 2>&1) \
    || { echo "FAIL: this spelling is a stage_product.sh call and should satisfy check 23: [$2]: $(cd "$1" && sh "$S" 2>&1)"; exit 1; }
}
