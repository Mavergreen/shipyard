#!/bin/sh
# platform: host-agnostic
# spec: BACKLOG.md #32 -- publish-release.yml's `assets` input: `required` (the default, unchanged
#       for every product that has assets) or `none`, a release of notes alone for a product with
#       nothing to attach, such as a GitHub Action consumed by its tag. The assets step's own
#       script, run as the runner would run it, decides each case.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
w="$(mktemp -d "${TMPDIR:-/tmp}/publish-notes-only-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT

python3 - "$root/.github/workflows/publish-release.yml" "$w/assets-step.sh" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
inp = wf[True]["workflow_call"]["inputs"] if True in wf else wf["on"]["workflow_call"]["inputs"]
a = inp.get("assets")
if not a or a.get("default") != "required" or a.get("type") != "string":
    print("FAIL: no `assets` input of type string defaulting to required: %r" % a); sys.exit(1)
step = [s for j in wf["jobs"].values() for s in j["steps"] if s.get("id") == "assets"][0]
if step.get("env", {}).get("ASSETS") != "${{ inputs.assets }}":
    print("FAIL: the assets step does not read inputs.assets as $ASSETS"); sys.exit(1)
open(sys.argv[2], "w").write(step["run"])
PY

# spec: BACKLOG.md #32 -- the step's run: block, against a stand-in shipyard checkout and dist,
#       as the runner would run it
mkdir -p "$w/run/.shipyard"; cp -R "$root/scripts" "$w/run/.shipyard/scripts"
notes="$(printf '%s\n\n%s\n%s' '## thing 1.0.0' '### What changed' '- a change')"
step() {  # $1 = ASSETS, $2.. = files to put in dist besides the notes
  a="$1"; shift
  rm -rf "$w/run/dist"; mkdir -p "$w/run/dist"; printf '%s\n' "$notes" > "$w/run/dist/RELEASE_NOTES.md"
  for f in "$@"; do printf 'x\n' > "$w/run/dist/$f"; done
  : > "$w/run/out"
  (cd "$w/run" && ASSETS="$a" NOTES=RELEASE_NOTES.md CHECKSUMS=true VERSION=1.0.0 GITHUB_OUTPUT="$w/run/out" \
     sh -e "$w/assets-step.sh") > "$w/run/log" 2>&1
}

step none || { echo "FAIL: assets: none with notes alone must pass:"; cat "$w/run/log"; exit 1; }
files="$(sed -n '/^files<<EOF$/,/^EOF$/p' "$w/run/out" | sed '1d;$d')"
[ -z "$files" ] || { echo "FAIL: assets: none must attach nothing, not even SHA256SUMS: $files"; exit 1; }
[ ! -e "$w/run/dist/SHA256SUMS" ] || { echo "FAIL: assets: none must not write SHA256SUMS"; exit 1; }

if step none thing.tar.gz; then echo "FAIL: assets: none with an asset present must fail"; exit 1; fi

step required thing.tar.gz || { echo "FAIL: assets: required with an asset must pass:"; cat "$w/run/log"; exit 1; }
grep -q 'dist/thing.tar.gz' "$w/run/out" && grep -q 'dist/SHA256SUMS' "$w/run/out" \
  || { echo "FAIL: assets: required must attach the asset and its SHA256SUMS"; cat "$w/run/out"; exit 1; }

if step required; then echo "FAIL: assets: required with nothing to attach must still fail"; exit 1; fi
if step nothing thing.tar.gz; then echo "FAIL: an unknown assets value must fail"; exit 1; fi

echo "PASS: publish-notes-only"
