#!/bin/sh
# platform: host-agnostic
#   usage: install-action-pyyaml-test.sh
#          install@v1 makes PyYAML importable for the python3 already on PATH, on every runner and
#          for every source, so a product repo's own suite can run the conventions gate. Exit 0
#          clean, 1 on failure.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Cannot-verify is a FAILURE,
#       never a pass"
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/pyyaml-test.XXXXXX")"
trap 'rm -rf "$t"' EXIT
fails=0
bad() { echo "FAIL: install-action-pyyaml: $1"; fails=1; }

python3 - "$here/../.github/actions/install/action.yml" "$t/run.sh" <<'PY' || exit 1
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))["runs"]["steps"]
bad = []
m = [s for s in steps if s.get("id") == "mav-pyyaml"]
if len(m) != 1:
    print("FAIL: install-action-pyyaml: expected exactly one step with id mav-pyyaml, got %d" % len(m)); sys.exit(1)
s = m[0]
if s.get("if"):
    bad.append("the mav-pyyaml step must run on every runner and every source, not only when: %s" % s["if"])
for o in steps:
    if "setup-python" in (o.get("uses") or ""):
        bad.append("install@v1 must not replace the job's python3 (setup-python): a consumer's build may depend on it")
if bad:
    print("FAIL: install-action-pyyaml:\n  " + "\n  ".join(bad)); sys.exit(1)
open(sys.argv[2], "w").write(s["run"])
PY

mkdir -p "$t/bin"
cat > "$t/bin/python3" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >> "$T/py.log"
case "$*" in
  "-c import yaml") [ -f "$T/has-yaml" ] ;;
  "-m pip install"*) : > "$T/has-yaml" ;;
  "-c import yaml; print("*) [ -f "$T/has-yaml" ] && echo "PyYAML 9.9" ;;
  *) exit 2 ;;
esac
FAKE
chmod +x "$t/bin/python3"

: > "$t/py.log"; rm -f "$t/has-yaml"
out="$(T="$t" PATH="$t/bin:$PATH" bash "$t/run.sh" 2>&1)" || bad "without PyYAML, the step fails: $out"
grep -qx -- '-m pip install --quiet --user --break-system-packages pyyaml' "$t/py.log" \
  || bad "without PyYAML, it installs it with pip --user --break-system-packages into the python3 on PATH: $(cat "$t/py.log")"
case "$out" in *"PyYAML 9.9"*) ;; *) bad "after installing, it proves PyYAML imports: $out" ;; esac

: > "$t/py.log"; : > "$t/has-yaml"
out="$(T="$t" PATH="$t/bin:$PATH" bash "$t/run.sh" 2>&1)" || bad "with PyYAML, the step fails: $out"
grep -q 'pip' "$t/py.log" && bad "with PyYAML already importable, it installs nothing: $(cat "$t/py.log")"

cat > "$t/bin/python3" <<'FAKE'
#!/bin/sh
case "$*" in "-c import yaml") exit 1 ;; "-m pip install"*) exit 1 ;; *) exit 0 ;; esac
FAKE
if T="$t" PATH="$t/bin:$PATH" bash "$t/run.sh" >/dev/null 2>&1; then bad "a failed pip install fails the step"; fi

[ "$fails" -eq 0 ] || exit 1
echo "PASS: install-action-pyyaml"
