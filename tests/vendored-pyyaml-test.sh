#!/bin/sh
# platform: host-agnostic
#   usage: vendored-pyyaml-test.sh
#          scripts/vendor/yaml is PyYAML's lib/yaml at the version .mavergreen/ingredients/pyyaml/VERSION names, chk_py prefers
#          it to any yaml on PYTHONPATH, and a `vendored` deviation carrying its exit declares the vendoring.
#          Without a network the comparison with the sdist is left out and the offline checks run.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/vendored-pyyaml-test.XXXXXX")"
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL $1"; exit 1; }
sync="$here/scripts/vendor/sync-pyyaml.sh"

sh "$sync" --verify || fail "the vendored tree matches yaml.sha256 and the pyyaml ingredient"
online=0
rc=0; sh "$sync" --check >/dev/null 2>&1 || rc=$?
case "$rc" in
  0) online=1 ;;
  2) echo "NOTE no network: the vendored tree was not compared with the sdist" ;;
  *) sh "$sync" --check; fail "the vendored tree matches the pinned sdist" ;;
esac

copy() {
  rm -rf "$t/r"; mkdir -p "$t/r/scripts" "$t/r/.mavergreen/ingredients"
  cp -R "$here/scripts/vendor" "$t/r/scripts/vendor"
  cp "$here/scripts/mavericks_fetch.sh" "$here/scripts/mavergreen-meta.sh" "$t/r/scripts/"
  cp -R "$here/.mavergreen/ingredients/pyyaml" "$t/r/.mavergreen/ingredients/pyyaml"
}
copy
sh "$t/r/scripts/vendor/sync-pyyaml.sh" --verify || fail "a copy of the vendored tree and its pin verifies"
printf '#' >> "$t/r/scripts/vendor/yaml/__init__.py"
if sh "$t/r/scripts/vendor/sync-pyyaml.sh" --verify >/dev/null 2>&1; then fail "one changed byte is caught offline"; fi
if [ "$online" -eq 1 ]; then
  if sh "$t/r/scripts/vendor/sync-pyyaml.sh" --check >/dev/null 2>&1; then fail "one changed byte is caught by --check"; fi
fi

copy
printf '0.0.0\n' > "$t/r/.mavergreen/ingredients/pyyaml/VERSION"
if sh "$t/r/scripts/vendor/sync-pyyaml.sh" --verify >/dev/null 2>&1; then fail "a pin bumped without re-vendoring is caught offline"; fi

mkdir -p "$t/shadow/yaml"
printf 'raise ImportError("the vendored yaml must win")\n' > "$t/shadow/yaml/__init__.py"
printf 'import yaml, os\nprint(os.path.dirname(yaml.__file__))\n' > "$t/where.py"
got="$(cd "$t" && PYTHONPATH="$t/shadow" SHIPYARD_CHECK_DIR="$here/scripts" SHIPYARD_SCRIPTS="$here/scripts" \
  sh -c '. "$SHIPYARD_CHECK_DIR/lib/py.sh"; chk_py "$1"' sh "$t/where.py")" || fail "chk_py imports yaml past a broken one on PYTHONPATH"
[ "$got" = "$here/scripts/vendor/yaml" ] || fail "chk_py loads the vendored yaml, got $got"

dev="$(sh "$here/scripts/deviations.sh" "$here" | grep '^vendored scripts/vendor/yaml/\*\* ')" || fail "shipyard declares a vendored deviation of scope scripts/vendor/yaml/**"
printf '%s\n' "$dev" | grep -q 'ssl' || fail "the deviation names its reason"
tr '\n' ' ' < "$here/.mavergreen/deviations/vendored/pyyaml/revisit" | grep -q 'python-315 ships ssl and pip works (its phase 2); then delete the vendored copy and the checks import a pip-installed PyYAML' || fail "the deviation names its exit"
[ -f "$here/.mavergreen/ingredients/pyyaml/description" ] || fail "the pyyaml ingredient has a description"
echo "PASS vendored-pyyaml"
