#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/conventions_fixture.sh"

# spec: SKILL.md "Family conventions" check 30 -- nothing publishes a release but shipyard's
#       publish-release.yml, and every job calling it needs a job that makes the
#       local-backfill-report artifact with local-backfill-report.sh.
REL=.github/workflows/release.yml
case_() {  # $1 = name; stdin = python transforming release.yml text s
  d="$work/c30-$1"; mkrepo "$d"
  python3 -c 'import sys; p=sys.argv[1]; s=open(p).read(); exec(sys.stdin.read()); open(p,"w").write(s)' "$d/$REL"
  (cd "$d" && git add -A) >/dev/null 2>&1
}
fails() {  # $1 = name, $2 = phrase
  out="$(cd "$work/c30-$1" && sh "$S" 2>&1)" && { echo "FAIL: check 30: $1 must fail"; exit 1; }
  printf '%s\n' "$out" | grep -q -- "$2" || { echo "FAIL: check 30: $1 should fail with '$2': $out"; exit 1; }
}
passes() {
  (cd "$work/c30-$1" && sh "$S" >/dev/null 2>&1) || { echo "FAIL: check 30: $1 must pass: $(cd "$work/c30-$1" && sh "$S" 2>&1)"; exit 1; }
}
NOREPORT='no job it needs makes the local-backfill-report artifact'
INLINE='publishes a release itself'
RUNLINE='      - run: sh "$SHIPYARD_SCRIPTS/local-backfill-report.sh" . dist "$GITHUB_SHA" "$RUNNER_TEMP/local-backfill-report.tsv"\n'
UPLOAD='          name: local-backfill-report\n'

case_ baseline <<'PY'
PY
passes baseline

case_ norun <<PY
s = s.replace('$RUNLINE', '')
PY
fails norun "$NOREPORT"

case_ commentrun <<PY
s = s.replace('$RUNLINE', '      - run: |\n          # sh local-backfill-report.sh . dist\n          true\n')
PY
fails commentrun "$NOREPORT"

case_ noupload <<PY
s = s.replace('$UPLOAD', '          name: something-else\n')
PY
fails noupload "$NOREPORT"

case_ unneeded <<'PY'
s = s.replace('    needs: [vm-test, build]\n', '    needs: [vm-test]\n')
PY
fails unneeded "$NOREPORT"

case_ transitive <<'PY'
s = s.replace('    needs: [vm-test, build]\n', '    needs: vm-test\n')
s = s.replace('  vm-test:\n    runs-on', '  vm-test:\n    needs: [build]\n    runs-on')
PY
passes transitive

case_ localcaller <<'PY'
s = s.replace('uses: Mavergreen/shipyard/.github/workflows/publish-release.yml@v1', 'uses: ./.github/workflows/publish-release.yml')
PY
passes localcaller
case_ localcaller-noreport <<PY
s = s.replace('uses: Mavergreen/shipyard/.github/workflows/publish-release.yml@v1', 'uses: ./.github/workflows/publish-release.yml')
s = s.replace('$RUNLINE', '')
PY
fails localcaller-noreport "$NOREPORT"

n=0
for inline in 'gh release create "$TAG" dist/*' 'gh release upload "$TAG" dist/x.pkg' 'gh release edit "$TAG" --draft=false' \
              'gh api -X POST repos/Mavergreen/w/releases -f tag_name=v1' 'x=1; gh release create v1' \
              'gh release delete-asset "$TAG" x.pkg --yes' 'gh api repos/Mavergreen/w/releases -f tag_name=v1' \
              'gh api --method=PATCH repos/Mavergreen/w/releases/1' 'gh api repos/Mavergreen/w/releases --input body.json' \
              'curl -X POST -H @headers https://api.github.com/repos/Mavergreen/w/releases' \
              'curl --data-binary @x.pkg "https://uploads.github.com/repos/Mavergreen/w/releases/1/assets?name=x.pkg"'; do
  n=$((n + 1))
  case_ "inline$n" <<PY
s += '      - run: $inline\n'
PY
  fails "inline$n" "$INLINE"
done
for action in softprops/action-gh-release@v3 ncipollo/release-action@v1 actions/create-release@v1; do
  n=$((n + 1))
  case_ "inline$n" <<PY
s += '      - uses: $action\n'
PY
  fails "inline$n" "$INLINE"
done

case_ reads <<'PY'
s += '      - run: |\n          # gh release create "$TAG"\n          gh release view v1 --json tagName\n          gh release download v1 -R Mavergreen/x\n          gh release list -R Mavergreen/x\n'
s += '          gh api repos/Mavergreen/x/releases/tags/v1 --jq .id\n          gh api -X GET repos/Mavergreen/x/releases -f per_page=1\n'
s += '          curl -fsSL https://api.github.com/repos/Mavergreen/x/releases/tags/v1\n'
PY
passes reads

script_case() {  # $1 = name, $2 = script body, $3 = the run line calling it
  d="$work/c30-$1"; mkrepo "$d"
  printf '#!/bin/sh\n%s\n' "$2" > "$d/build/pub.sh"
  printf '      - run: %s\n' "$3" >> "$d/$REL"
  (cd "$d" && git add -A) >/dev/null 2>&1
}
PUBLISHES='set -eu
gh release upload "$TAG" dist/x.pkg --clobber'
n=0
for call in 'sh build/pub.sh upload' 'bash -e ./build/pub.sh' '. build/pub.sh' './build/pub.sh upload' 'set -e; sh "build/pub.sh"'; do
  n=$((n + 1))
  script_case "script$n" "$PUBLISHES" "$call"
  fails "script$n" 'build/pub.sh, which runs: gh release upload'
done
script_case script-reads 'gh release view "$TAG" --json assets' 'sh build/pub.sh'
passes script-reads
script_case script-mention "$PUBLISHES" 'cat build/pub.sh'
passes script-mention
script_case script-commented '# gh release create "$TAG"' 'sh build/pub.sh'
passes script-commented

mkrepo "$work/c30-shared"; cp "$here/../.github/workflows/publish-release.yml" "$work/c30-shared/.github/workflows/publish-release.yml"
(cd "$work/c30-shared" && git add -A) >/dev/null 2>&1
passes shared
mkrepo "$work/c30-edited"
sed 's/name: publish-release/name: my-publisher/' "$here/../.github/workflows/publish-release.yml" > "$work/c30-edited/.github/workflows/publish-release.yml"
(cd "$work/c30-edited" && git add -A) >/dev/null 2>&1
fails edited "$INLINE"

echo "PASS: check-family-conventions-6"
