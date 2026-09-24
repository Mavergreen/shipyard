#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/ingredient-pins.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/ingredient-pins-test.XXXXXX")"; trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
mkdir -p .github/workflows components/golang components/tailscale
printf '1.26.5-mavericks.1\n' > components/golang/version
printf 'REF=v1.102.0\n'       > components/tailscale/version
printf '1.26.5\n'             > UPSTREAM_VERSION
printf 'MLS_VERSION=1.5.2\n'  > versions.sh
git add -A; git commit -qm base

out="$(sh "$S")"
[ -z "$out" ] || { echo "FAIL: no caller workflow (a repo with no ingredients) should be empty, exit 0: got '$out'"; exit 1; }

cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    branches: [main]
    paths: ['components/**']
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
    with:
      own-upstream-paths: components/tailscale/version
YML
out="$(sh "$S")"
[ "$out" = components/golang/version ] || { echo "FAIL: inline form (tailscale/container-tools shape) plus own-upstream exclusion: got '$out'"; exit 1; }

cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    branches: [main]
    paths:
      - versions.sh        # the shim pin, the CA hash pin
      - UPSTREAM_VERSION   # deliberately listed to prove exclusion works
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
    with:
      own-upstream-paths: UPSTREAM_VERSION
YML
out="$(sh "$S")"
[ "$out" = versions.sh ] || { echo "FAIL: block form with trailing comments (golang shape); own upstream must be excluded even when watched: got '$out'"; exit 1; }

cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    paths: ['nosuchdir/**']
jobs:
  repackage:
    with:
      own-upstream-paths: ""
YML
out="$(sh "$S")"
[ -z "$out" ] || { echo "FAIL: a glob matching nothing should be empty -- the guard, not this script, is what complains: got '$out'"; exit 1; }

# spec: repackage-decision.sh already understands "pins.env:SWIFT_VERSION" (a KEY inside a
#       shared pin file is the repo's own upstream, not an ingredient). This script once only
#       compared whole paths ([ "$f" = "$o" ]), so "pins.env:SWIFT_VERSION" never matched the bare
#       path "pins.env" and the file was never excluded at all -- on the swift repos' next Swift
#       bump, the notes would list SWIFT_VERSION as a moved ingredient while repackage-decision.sh
#       simultaneously said SKIP=own-upstream-changed.
cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    branches: [main]
    paths: ['pins.env']
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
    with:
      own-upstream-paths: pins.env:SWIFT_VERSION
YML
printf 'SWIFT_VERSION="6.3.3"\nLLVM_SHA="aaaa"\n' > pins.env
git add -A; git commit -qm "add swift-shaped pins.env"
out="$(sh "$S")"
[ "$out" = "pins.env:SWIFT_VERSION" ] \
  || { echo "FAIL path:KEY: expected the key-annotated path, got '$out'"; exit 1; }

cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    branches: [main]
    paths: ['pins.env']
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
    with:
      own-upstream-paths: pins.env
YML
out="$(sh "$S")"
[ -z "$out" ] || { echo "FAIL: a whole-path own-upstream entry must still exclude the file entirely (no regression from the path:KEY fix): got '$out'"; exit 1; }

# spec: repackage-decision.sh never parses this YAML itself -- GitHub Actions' own engine
#       resolves `with:` before that script sees a plain env var -- so this hand-rolled reader is
#       the only place a block scalar ("own-upstream-paths: |") needs handling, and it must
#       resolve to the same tokens a real YAML parser would. Unused by any family repo today
#       (pre-existing, latent), but must genuinely parse rather than lookalike-exclude nothing.
cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    branches: [main]
    paths: ['pins.env', 'other.txt']
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
    with:
      own-upstream-paths: |
        pins.env:SWIFT_VERSION
        other.txt
YML
printf 'x\n' > other.txt
git add -A; git commit -qm "add other.txt, block-scalar own-upstream-paths"
out="$(sh "$S")"
printf '%s\n' "$out" | grep -qx 'pins.env:SWIFT_VERSION' \
  || { echo "FAIL block-scalar: pins.env:SWIFT_VERSION not derived, got '$out'"; exit 1; }
printf '%s\n' "$out" | grep -qx 'other.txt' \
  && { echo "FAIL block-scalar: other.txt should be excluded whole, got '$out'"; exit 1; }

cat > .github/workflows/repackage-on-ingredient-bump.yml <<'YML'
on:
  push:
    branches: [main]
    paths: ['pins.env', 'other.txt']
jobs:
  repackage:
    uses: Mavergreen/shipyard/.github/workflows/repackage-on-ingredient-bump.yml@v1
    with:
      own-upstream-paths: |
        pins.env:SWIFT_VERSION
      dispatch-field: other.txt
YML
git add -A; git commit -qm "block-scalar own-upstream-paths with a colliding sibling value"
out="$(sh "$S")"
printf '%s\n' "$out" | grep -qx 'pins.env:SWIFT_VERSION' \
  || { echo "FAIL block-scalar sibling keys: pins.env:SWIFT_VERSION missing, got '$out'"; exit 1; }
printf '%s\n' "$out" | grep -qx 'other.txt' \
  || { echo "FAIL: a real YAML parser ends the block scalar at the first line no MORE indented than \"own-upstream-paths:\" itself -- the reader once terminated inblock only on a column-0 line, so a sibling key's own VALUE (here \"other.txt\", a real watched path) got swallowed into the own-upstream token list and wrongly excluded: block-scalar sibling keys: other.txt wrongly excluded by a sibling key's value, got '$out'"; exit 1; }

echo "PASS: ingredient-pins"
