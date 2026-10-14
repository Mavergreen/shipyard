#!/bin/sh
# platform: host-agnostic
#   usage: check-bash32-parse-test.sh
#          scripts/check-bash32-parse.sh over tests/fixtures/checks/bash32-parse/, once with a stand-in
#          bash 3.2 that refuses the canary (any host) and once with this host's /bin/sh when that is
#          bash 3.2; and the "can't measure here" cases: a shell that is not bash 3.2, a shell that
#          accepts the canary, and the `host` deviation that excuses a host, which are never a silent pass.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
S="$here/scripts/check-bash32-parse.sh"
fx="$here/tests/fixtures/checks/bash32-parse"
w="$(mktemp -d "${TMPDIR:-/tmp}/check-bash32-parse-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
fail() { echo "FAIL $1"; exit 1; }
unset SHIPYARD_BASH32_SH SHIPYARD_BASH32_BASH

cat > "$w/fake32" <<'SH'
#!/bin/sh
case "$1" in
  -c) printf 3.2.57 ;;
  -n) ! grep -q "{[^}]*'" "$2" && ! grep -q '<(' "$2" ;;
esac
SH
cat > "$w/fakebash32" <<'SH'
#!/bin/sh
case "$1" in
  -c) printf 3.2.57 ;;
  -n) ! grep -q "{[^}]*'" "$2" ;;
esac
SH
cat > "$w/accepts" <<'SH'
#!/bin/sh
case "$1" in -c) printf 3.2.57 ;; -n) exit 0 ;; esac
SH
cat > "$w/dashlike" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$w/fakebash32" "$w/fake32" "$w/accepts" "$w/dashlike"

run() {  # $1 = fixture dir, $2 = the /bin/sh stand-in, $3 = the /bin/bash stand-in (default: $2); output in $w/out
  (cd "$1" && SHIPYARD_BASH32_SH="$2" SHIPYARD_BASH32_BASH="${3:-$2}" SHIPYARD_CHECK_FILES="$1/FILES" sh "$S") > "$w/out" 2>&1
}
host="$(uname -s | tr 'A-Z' 'a-z')"

shells="$w/fake32:$w/fakebash32"
case "$(/bin/sh -c 'printf %s "$BASH_VERSION"' 2>/dev/null || :)" in 3.2.*) shells="$shells /bin/sh:/bin/bash" ;; esac
for pair in $shells; do
  sh_="${pair%%:*}"; bash_="${pair#*:}"
  run "$fx/pass" "$sh_" "$bash_" || fail "pass is clean under $pair: $(cat "$w/out")"
  grep -q '^bash32-parse: ok -- 2 tracked shell scripts' "$w/out" || fail "pass says what it checked under $pair: $(cat "$w/out")"
  for d in fail fail-shebang fail-sh-process-substitution; do
    if run "$fx/$d" "$sh_" "$bash_"; then fail "$d should fail under $pair"; fi
    grep -q '^bash32-parse: build/[a-z.-]* does not parse' "$w/out" || fail "$d names its file under $pair: $(cat "$w/out")"
    grep -q '^  fix: ' "$w/out" || fail "$d names a fix under $pair"
  done
done

for s in "$w/accepts" "$w/dashlike" "$w/missing"; do
  if run "$fx/pass" "$s"; then fail "$(basename "$s") cannot measure, so it fails"; fi
  grep -q "^bash32-parse: can't measure here" "$w/out" || fail "$(basename "$s") says it can't measure: $(cat "$w/out")"
done
grep -q 'accepts the construct' "$w/out" && fail "a missing shell is not a canary result"

mkdir -p "$w/dev"; cp "$fx/pass/FILES" "$w/dev/FILES"; mkdir -p "$w/dev/build"; cp "$fx/pass/build/good.sh" "$w/dev/build/"
printf '# x\n\n## Conformance deviations\n\n- host:%s: no bash 3.2 here. Revisit when the Apple shells ship.\n' "$host" > "$w/dev/INGREDIENTS.md"
run "$w/dev" "$w/dashlike" || fail "a host deviation excuses a host that cannot measure: $(cat "$w/out")"
grep -q "^bash32-parse: not run: skipped by deviation (host:$host)" "$w/out" || fail "the skip is printed: $(cat "$w/out")"
printf '# x\n\n## Conformance deviations\n\n- host:no-such-os: nowhere\n' > "$w/dev/INGREDIENTS.md"
if run "$w/dev" "$w/dashlike"; then fail "a deviation for another host excuses nothing"; fi
printf '# x\n\n## Conformance deviations\n\n- host:%s: no bash 3.2 here. Revisit when the Apple shells ship.\n' "$host" > "$w/dev/INGREDIENTS.md"
run "$w/dev" "$w/fake32" "$w/fakebash32" || fail "a host that can measure still measures: $(cat "$w/out")"
grep -q 'skipped by deviation' "$w/out" && fail "a host that can measure is not excused"

mkdir -p "$w/none"; : > "$w/none/FILES"
if run "$w/none" "$w/fake32" "$w/fakebash32"; then fail "no shell script found is not a pass"; fi
grep -q 'nothing was checked' "$w/out" || fail "an empty list says so: $(cat "$w/out")"

mkdir -p "$w/exc/build"; cp "$fx/fail/build/bad.sh" "$w/exc/build/"; printf 'build/bad.sh\n' > "$w/exc/FILES"
printf '# x\n\n## Conformance deviations\n\n- bash32-parse:build/bad.sh: it is a polyglot. Revisit when it is split.\n' > "$w/exc/INGREDIENTS.md"
run "$w/exc" "$w/fake32" "$w/fakebash32" || fail "a path deviation excuses a script: $(cat "$w/out")"
grep -q '1 excused by deviation' "$w/out" || fail "the excused count is printed: $(cat "$w/out")"

python3 - "$here/.github/workflows/ci.yml" <<'PY' || fail "ci.yml's macOS test job runs shipyard-check --only bash32-parse"
import sys, yaml
job = yaml.safe_load(open(sys.argv[1]))["jobs"]["test"]
assert "macos" in job["runs-on"], job["runs-on"]
assert any(isinstance(s.get("run"), str) and "shipyard-check --only bash32-parse" in s["run"] for s in job["steps"])
PY
echo "PASS check-bash32-parse"
