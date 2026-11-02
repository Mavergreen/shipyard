#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/repackage-decision.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/repackage-decision-t.XXXXXX")"; trap 'rm -rf "$work"' EXIT
M="$work/.mavergreen"
mkdir -p "$M/upstream" "$M/ingredients/golang" "$M/ingredients/patches"
printf '1.0\n' > "$M/upstream/VERSION"
printf '1.26.1\n' > "$M/ingredients/golang/VERSION"
printf 'patches/**\nsrc/a b/*.c\n' > "$M/ingredients/patches/watch"

decide() { CHANGED="$1" MAVERGREEN_ROOT="$work" sh "$S"; }

out="$(decide '.mavergreen/upstream/VERSION')"
[ "$out" = "SKIP=own-upstream-changed" ] || { echo "FAIL own-upstream: $out"; exit 1; }

out="$(decide '.mavergreen/ingredients/golang/VERSION')"
[ "$out" = "DISPATCH" ] || { echo "FAIL ingredient value file: $out"; exit 1; }

out="$(decide 'README.md')"
[ "$out" = "SKIP=no-ingredient-changed" ] || { echo "FAIL nothing relevant: $out"; exit 1; }

out="$(decide '')"
[ "$out" = "SKIP=no-ingredient-changed" ] || { echo "FAIL empty push: $out"; exit 1; }

out="$(decide 'patches/deep/er/x.patch')"
[ "$out" = "DISPATCH" ] || { echo "FAIL watch ** glob across directories: $out"; exit 1; }

out="$(decide 'src/a b/x.c')"
[ "$out" = "DISPATCH" ] || { echo "FAIL watch glob with a space: $out"; exit 1; }

out="$(decide 'src/ab/x.c')"
[ "$out" = "SKIP=no-ingredient-changed" ] || { echo "FAIL a space is literal: $out"; exit 1; }

out="$(decide "$(printf '.mavergreen/ingredients/golang/VERSION\n.mavergreen/upstream/VERSION')")"
[ "$out" = "SKIP=own-upstream-changed" ] || { echo "FAIL own upstream and ingredient in one push: the new upstream owns it: $out"; exit 1; }

out="$(decide "$(printf 'README.md\npatches/x.patch')")"
[ "$out" = "DISPATCH" ] || { echo "FAIL one watched path among others: $out"; exit 1; }

rm -rf "$M/ingredients"; mkdir "$M/ingredients"
out="$(decide 'patches/x.patch')"
[ "$out" = "SKIP=no-ingredient-changed" ] || { echo "FAIL empty ingredients/ counts as no ingredients: $out"; exit 1; }

echo "PASS: repackage-decision"
