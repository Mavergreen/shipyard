#!/bin/sh
# platform: host-agnostic
#   usage: local-backfill-publish-test.sh
#          publish-release.yml refuses a release whose source violates the local-backfill policy, on
#          evidence bound to the build source commit and the exact assets: local-backfill-report.sh
#          writes that evidence only for a strict-clean source, and the publisher checks out the
#          caller at the build source, recomputes strict policy there and compares every asset,
#          before any tag or release is touched. The publish job runs here step by step, with the
#          GitHub actions it uses replaced by local stand-ins and the release action by a marker.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
R="$root/scripts/local-backfill-report.sh"
V="$root/scripts/verify-local-backfill-report.sh"
WF="$root/.github/workflows/publish-release.yml"
FX="$here/fixtures/local-backfills"
unset MAVERGREEN_SOURCE_FILES MAVERGREEN_CHECK_REPOSITORY GITHUB_REPOSITORY GIT_DIR GIT_WORK_TREE 2>/dev/null || true
command -v git >/dev/null 2>&1 || { echo "SKIP: no git, and the evidence is bound to a commit"; exit 77; }
command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null \
  || { echo "FAIL: needs python3 with PyYAML to run the publish job"; exit 1; }
w="$(mktemp -d "${TMPDIR:-/tmp}/lb-publish-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT

[ -f "$R" ] || { echo "FAIL: $R does not exist"; exit 1; }
[ -f "$V" ] || { echo "FAIL: $V does not exist"; exit 1; }

TAB="$(printf '\t')"
G() { git -C "$P" -c user.name=t -c user.email=t@example.invalid "$@"; }
sha256() { (cd "$(dirname "$1")" && { shasum -a 256 "./${1##*/}" 2>/dev/null || sha256sum "./${1##*/}"; }) | awk '{print $1}'; }

P="$w/product"
mkdir -p "$P/src"
printf '# fixture\n' > "$P/README.md"
printf 'int main(void) { return 0; }\n' > "$P/src/main.c"
git init -q "$P"; G add -A; G commit -qm clean
CLEAN="$(G rev-parse HEAD)"
printf 'more\n' > "$P/NOTES.txt"; G add -A; G commit -qm second
SECOND="$(G rev-parse HEAD)"
G branch -q release-branch
cp "$FX/external-definition/repo/src/time_backport.c" "$P/src/time_backport.c"; G add -A; G commit -qm violation
BAD="$(G rev-parse HEAD)"
G checkout -q "$CLEAN"

D="$w/dist"
fresh_dist() {
  rm -rf "$D"; mkdir -p "$D"
  printf '## thing 1.0.0\n\n### What changed\n- a change\n' > "$D/RELEASE_NOTES.md"
  [ "${1:-}" = none ] && return 0
  printf 'pkg bytes\n' > "$D/thing-1.0.0.pkg"
  printf '<rss/>\n' > "$D/thing.xml"
}

rc=0
report() { rc=0; MAVERGREEN_CHECK_REPOSITORY=Mavergreen/fixture sh "$R" "$@" > "$w/out" 2>&1 || rc=$?; }
expect() {
  [ "$rc" -eq "$1" ] || { echo "FAIL: $2: expected exit $1, got $rc"; cat "$w/out"; exit 1; }
}
says() { grep -q -- "$1" "$w/out" || { echo "FAIL: $2: output must contain \"$1\"; got:"; cat "$w/out"; exit 1; }; }

fresh_dist
report "$P" "$D" "$CLEAN" "$w/r.tsv"; expect 0 "a clean source and its assets"
want="$(printf 'source-sha\t%s\nasset\t%s\tthing-1.0.0.pkg\nasset\t%s\tthing.xml' "$CLEAN" "$(sha256 "$D/thing-1.0.0.pkg")" "$(sha256 "$D/thing.xml")")"
[ "$(cat "$w/r.tsv")" = "$want" ] || { echo "FAIL: the report is not the source sha and the sorted asset records:"; cat "$w/r.tsv"; exit 1; }

fresh_dist none
report "$P" "$D" "$CLEAN" "$w/r.tsv"; expect 0 "notes alone"
[ "$(cat "$w/r.tsv")" = "$(printf 'source-sha\t%s' "$CLEAN")" ] || { echo "FAIL: a notes-only report is its source-sha line alone:"; cat "$w/r.tsv"; exit 1; }

fresh_dist
rm -f "$w/r.tsv"
G checkout -q "$BAD"
report "$P" "$D" "$BAD" "$w/r.tsv"; expect 1 "a violating source"; says 'local-backfill:' "the strict finding is shown"
[ ! -e "$w/r.tsv" ] || { echo "FAIL: a violating source must leave no report behind"; exit 1; }
G checkout -q "$CLEAN"

report "$P" "$D" "$SECOND" "$w/r.tsv"; expect 2 "a source sha that is not the checkout's HEAD"; says "$CLEAN" "names the commit checked out"
[ ! -e "$w/r.tsv" ] || { echo "FAIL: a mismatched source sha must leave no report behind"; exit 1; }
report "$P" "$D" main "$w/r.tsv"; expect 2 "a source that is not a full commit sha"
report --report "$P" "$D" "$CLEAN" "$w/r.tsv"; expect 2 "--report is refused: evidence is strict or nothing"
report "$P" "$D" "$CLEAN" "$D/local-backfill-report.tsv"; expect 2 "a report written into the release assets"
[ ! -e "$D/local-backfill-report.tsv" ] || { echo "FAIL: the report must never land among the assets"; exit 1; }

printf 'x\n' > "$D/bad${TAB}name.pkg"
report "$P" "$D" "$CLEAN" "$w/r.tsv"; expect 2 "an asset name holding a tab"
rm -f "$D/bad${TAB}name.pkg"
printf 'x\n' > "$D/bad
name.pkg"
report "$P" "$D" "$CLEAN" "$w/r.tsv"; expect 2 "an asset name holding a newline"
fresh_dist

mkdir -p "$w/bin"
REALGIT="$(command -v git)"
cat > "$w/bin/git" <<EOF
#!/bin/sh
[ "\$1" = ls-remote ] && exit 0
exec "$REALGIT" "\$@"
EOF
cat > "$w/bin/gh" <<'EOF'
#!/bin/sh
case "$*" in *releases*) echo 1 ;; esac
EOF
chmod +x "$w/bin/git" "$w/bin/gh"

cat > "$w/harness.py" <<'PY'
import fnmatch, json, os, re, shutil, subprocess, sys, yaml
wf_path, cfg_path = sys.argv[1], sys.argv[2]
cfg = json.load(open(cfg_path))
wf = yaml.safe_load(open(wf_path))
on = wf.get("on") or wf.get(True)
inputs = {k: v.get("default") for k, v in on["workflow_call"]["inputs"].items()}
inputs.update(cfg["inputs"])
ctx = {"inputs": inputs, "github": cfg["github"], "steps": {}, "runner": {"temp": cfg["run"] + "/.runner-temp"}}
os.makedirs(ctx["runner"]["temp"], exist_ok=True)
run = cfg["run"]

def lookup(term):
    term = term.strip()
    if term.startswith("'") and term.endswith("'"):
        return term[1:-1]
    cur = ctx
    for part in term.split("."):
        if not isinstance(cur, dict) or part not in cur:
            raise SystemExit("harness: cannot evaluate %r" % term)
        cur = cur[part]
    return cur

def expr(e):
    for term in e.split("||"):
        v = lookup(term)
        if v not in (None, "", False):
            return v
    return v

def ev(s):
    if not isinstance(s, str):
        return s
    def sub(m):
        v = expr(m.group(1))
        return ("true" if v else "false") if isinstance(v, bool) else str(v if v is not None else "")
    return re.sub(r"\$\{\{\s*(.*?)\s*\}\}", sub, s)

def result(text):
    open(os.path.join(run, "RESULT"), "w").write(text + "\n")

def use(step, w):
    u = step["uses"]
    path = os.path.join(run, w.get("path", "."))
    if u.startswith("actions/checkout@"):
        repo = w.get("repository") or cfg["github"]["repository"]
        if repo == "Mavergreen/shipyard":
            os.makedirs(path, exist_ok=True)
            shutil.copytree(cfg["shipyard_scripts"], os.path.join(path, "scripts"))
            return 0
        if repo != cfg["github"]["repository"]:
            raise SystemExit("harness: checkout of an unexpected repository %r" % repo)
        ref = w.get("ref") or cfg["github"]["sha"]
        r = subprocess.run(["git", "-C", cfg["product"], "rev-parse", "--verify", "-q", ref + "^{commit}"],
                           stdout=subprocess.PIPE, universal_newlines=True)
        if r.returncode != 0 or subprocess.call(["git", "clone", "-q", cfg["product"], path]) != 0:
            print("harness: checkout of %r failed" % ref); return 1
        return subprocess.call(["git", "-C", path, "-c", "advice.detachedHead=false", "checkout", "-q", "--detach", r.stdout.strip()])
    if u.startswith("actions/download-artifact@"):
        arts = cfg["artifacts"]
        if "name" in w:
            if w["name"] not in arts:
                print("harness: no artifact named %s" % w["name"]); return 1
            names = [w["name"]]
        else:
            names = [n for n in arts if fnmatch.fnmatchcase(n, w["pattern"])]
        for n in names:
            os.makedirs(path, exist_ok=True)
            for f in os.listdir(arts[n]):
                shutil.copy(os.path.join(arts[n], f), os.path.join(path, f))
        return 0
    if u.startswith("softprops/action-gh-release@"):
        json.dump(w, open(os.path.join(run, "PUBLISHED.json"), "w"))
        return 0
    raise SystemExit("harness: no stand-in for %s" % u)

steps = [s for job in wf["jobs"].values() for s in job.get("steps") or []]
for step in steps:
    name = step.get("name") or step.get("uses")
    cond = step.get("if")
    if cond is not None:
        if "failure" in str(cond):
            continue
        raise SystemExit("harness: cannot evaluate if: %r" % cond)
    w = {k: ev(v) for k, v in (step.get("with") or {}).items()}
    if "uses" in step:
        rc = use(step, w)
        if "action-gh-release" in step["uses"] and rc == 0:
            result("published")
            sys.exit(0)
    else:
        out = os.path.join(run, ".github-output")
        open(out, "w").close()
        env = dict(os.environ)
        env.update({k: ev(v) for k, v in (step.get("env") or {}).items()})
        env["GITHUB_OUTPUT"] = out
        script = os.path.join(run, ".step.sh")
        open(script, "w").write(step["run"])
        rc = subprocess.call(["sh", "-e", script], cwd=run, env=env)
        outputs, lines, i = {}, open(out).read().split("\n"), 0
        while i < len(lines):
            m = re.match(r"^([A-Za-z0-9_-]+)<<(.+)$", lines[i])
            if m:
                j = lines.index(m.group(2), i + 1)
                outputs[m.group(1)] = "\n".join(lines[i + 1:j]); i = j + 1; continue
            if "=" in lines[i]:
                k, v = lines[i].split("=", 1); outputs[k] = v
            i += 1
        if step.get("id"):
            ctx["steps"][step["id"]] = {"outputs": outputs}
    if rc != 0:
        result("refused: %s" % name)
        sys.exit(0)
result("finished without publishing")
PY

A="$w/artifacts"
publish() {  # $1 = assets input, $2 = target-commitish input; artifacts already staged under $A
  rm -rf "$w/run"; mkdir -p "$w/run"
  python3 - "$w/cfg.json" "$w/run" "$root/scripts" "$P" "$A" "$1" "$2" "$CLEAN" <<'PY'
import json, os, sys
cfg, run, scripts, product, arts, assets, target, sha = sys.argv[1:]
json.dump({"run": run, "shipyard_scripts": scripts, "product": product,
           "artifacts": {n: os.path.join(arts, n) for n in os.listdir(arts)},
           "inputs": {"version": "1.0.0", "artifact": "product-dist", "assets": assets, "target-commitish": target},
           "github": {"repository": "Mavergreen/fixture", "sha": sha, "ref_type": "branch", "ref_name": "main",
                      "token": "t", "action_ref": ""}}, open(cfg, "w"))
PY
  PATH="$w/bin:$PATH" python3 "$w/harness.py" "$WF" "$w/cfg.json" > "$w/out" 2>&1 \
    || { echo "FAIL: the harness itself failed:"; cat "$w/out"; exit 1; }
}
stage() {  # $1 = report file to ship as the local-backfill-report artifact, or "" for none
  rm -rf "$A"; mkdir -p "$A/product-dist"; cp "$D"/* "$A/product-dist/"
  if [ -n "$1" ]; then mkdir -p "$A/local-backfill-report"; cp "$1" "$A/local-backfill-report/local-backfill-report.tsv"; fi
}
published() {
  [ "$(cat "$w/run/RESULT")" = published ] || { echo "FAIL: $1: must publish; $(cat "$w/run/RESULT"):"; cat "$w/out"; exit 1; }
}
refused() {  # $1 = label, $2 = text the refusal must carry
  r="$(cat "$w/run/RESULT")"
  [ ! -e "$w/run/PUBLISHED.json" ] || { echo "FAIL: $1: reached the publication action"; exit 1; }
  case "$r" in
    "refused: "*local-backfill*) ;;
    *) echo "FAIL: $1: must be refused by the local-backfill evidence step; $r:"; cat "$w/out"; exit 1 ;;
  esac
  grep -q -- "$2" "$w/out" || { echo "FAIL: $1: the refusal must say \"$2\"; got:"; cat "$w/out"; exit 1; }
}
forge() {  # $1 = source sha: a well-formed report for $D, written without the strict check
  { printf 'source-sha\t%s\n' "$1"
    for f in "$D"/*; do
      b="${f##*/}"; [ "$b" = RELEASE_NOTES.md ] && continue
      printf 'asset\t%s\t%s\n' "$(sha256 "$f")" "$b"
    done; } > "$w/forged.tsv"
}

fresh_dist
report "$P" "$D" "$CLEAN" "$w/good.tsv"; expect 0 "the report for the publisher cases"
stage "$w/good.tsv"; publish required ""; published "a clean source with matching evidence"
python3 - "$w/run/PUBLISHED.json" "$CLEAN" <<'PY' || exit 1
import json, sys
w = json.load(open(sys.argv[1]))
if w.get("target_commitish") != sys.argv[2]:
    print("FAIL: the tag must be minted at the audited commit %s, not %r" % (sys.argv[2], w.get("target_commitish"))); sys.exit(1)
PY

stage ""; publish required ""; refused "no report" "no local-backfill report"

report "$P" "$D" "$CLEAN" "$w/good.tsv"
stage "$w/good.tsv"; publish required "$SECOND"; refused "a report from another commit" "$SECOND"

G checkout -q release-branch
report "$P" "$D" "$SECOND" "$w/branch.tsv"; expect 0 "the report at the release branch"
G checkout -q "$CLEAN"
stage "$w/branch.tsv"; publish required release-branch; published "a target-commitish naming a branch"
grep -q "\"target_commitish\": \"$SECOND\"" "$w/run/PUBLISHED.json" \
  || { echo "FAIL: a branch target-commitish is minted at the commit it resolved to, $SECOND:"; cat "$w/run/PUBLISHED.json"; exit 1; }

stage "$w/good.tsv"; printf 'tampered\n' >> "$A/product-dist/thing-1.0.0.pkg"
publish required ""; refused "an asset byte changed after the report" "thing-1.0.0.pkg"

stage "$w/good.tsv"; rm "$A/product-dist/thing.xml"
publish required ""; refused "an asset the report lists is missing" "thing.xml"

stage "$w/good.tsv"; printf 'extra\n' > "$A/product-dist/extra.tar.gz"
publish required ""; refused "an asset the report does not list" "extra.tar.gz"

stage "$w/good.tsv"; cp "$w/good.tsv" "$A/product-dist/local-backfill-report.tsv"
publish required ""; refused "the report among the release assets" "local-backfill-report.tsv"

for unsafe in '../thing.xml' 'sub/thing.xml' '/etc/thing.xml' '.' '..'; do
  { cat "$w/good.tsv"; printf 'asset\t%s\t%s\n' "$(sha256 "$D/thing.xml")" "$unsafe"; } > "$w/unsafe.tsv"
  stage "$w/unsafe.tsv"; publish required ""; refused "a report path \"$unsafe\"" "unsafe"
done
{ cat "$w/good.tsv"; printf 'asset\t%s\tthing.xml\textra-field\n' "$(sha256 "$D/thing.xml")"; } > "$w/unsafe.tsv"
stage "$w/unsafe.tsv"; publish required ""; refused "a report row with a fourth field" "malformed"

G checkout -q "$BAD"
forge "$BAD"
G checkout -q "$CLEAN"
stage "$w/forged.tsv"; publish required "$BAD"; refused "a violating source with forged evidence (direct publisher call)" "local-backfill:"

G checkout -q "$BAD"
rc=0; MAVERGREEN_CHECK_REPOSITORY=Mavergreen/fixture sh "$root/scripts/check-local-backfills.sh" --report "$P" > "$w/report-mode.tsv" 2>/dev/null || rc=$?
G checkout -q "$CLEAN"
[ "$rc" -eq 0 ] || { echo "FAIL: --report must exit 0 on a violating source, which is what makes it no evidence"; exit 1; }
[ -s "$w/report-mode.tsv" ] || { echo "FAIL: --report printed nothing to substitute"; exit 1; }
stage "$w/report-mode.tsv"; publish required "$BAD"; refused "--report output in place of the evidence" "malformed"

fresh_dist none
report "$P" "$D" "$CLEAN" "$w/notes.tsv"; expect 0 "the notes-only report"
stage "$w/notes.tsv"; publish none ""; published "a notes-only release with its evidence"
stage ""; publish none ""; refused "a notes-only release with no report" "no local-backfill report"
G checkout -q "$BAD"; forge "$BAD"; G checkout -q "$CLEAN"
stage "$w/forged.tsv"; publish none "$BAD"; refused "a notes-only release of a violating source" "local-backfill:"
fresh_dist

python3 - "$WF" <<'PY'
import re, sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get("on") or wf.get(True)
steps = [s for j in wf["jobs"].values() for s in j.get("steps") or []]
bad = []
for name in on["workflow_call"]["inputs"]:
    if re.search(r"report|strict|backfill|policy", name):
        bad.append("input %r could downgrade or replace the local-backfill gate; there is no such input" % name)
lines = [l for l in open(sys.argv[1]).read().splitlines() if not l.lstrip().startswith("#")]
if any("--report" in l for l in lines):
    bad.append("the publisher passes --report somewhere; publication is strict only")
co = [i for i, s in enumerate(steps) if (s.get("with") or {}).get("path") == ".product"]
if not co or (steps[co[0]].get("with") or {}).get("repository") != "${{ github.repository }}" \
   or steps[co[0]]["with"].get("ref") != "${{ inputs.target-commitish || github.sha }}":
    bad.append("the product is not checked out from github.repository at inputs.target-commitish || github.sha into .product")
ver = [i for i, s in enumerate(steps) if "verify-local-backfill-report.sh" in (s.get("run") or "")]
if not ver:
    bad.append("no step runs verify-local-backfill-report.sh")
else:
    env = steps[ver[0]].get("env") or {}
    if env.get("MAVERGREEN_CHECK_REPOSITORY") != "${{ github.repository }}":
        bad.append("the evidence step must take MAVERGREEN_CHECK_REPOSITORY from github.repository, got %r" % env.get("MAVERGREEN_CHECK_REPOSITORY"))
    guard = [i for i, s in enumerate(steps) if "assert_tag_publishable.sh" in (s.get("run") or "")]
    if not guard or ver[0] > guard[0] or (co and co[0] > guard[0]):
        bad.append("the checkout and the evidence step must come before the tag guard and everything after it")
pubs = [s for s in steps if "action-gh-release" in (s.get("uses") or "")]
for s in pubs:
    if (s.get("with") or {}).get("target_commitish") != "${{ steps.source.outputs.sha }}":
        bad.append("publish attempt %r does not mint the tag at the audited commit (steps.source.outputs.sha)" % s.get("name"))
for s in steps:
    if "README.md" in (s.get("run") or "") and (s.get("env") or {}).get("SHA") != "${{ steps.source.outputs.sha }}":
        bad.append("the first-release README is not read at the audited commit")
if bad:
    for b in bad: print("FAIL: " + b)
    sys.exit(1)
PY

MAVERGREEN_CHECK_REPOSITORY=Mavergreen/shipyard sh "$root/scripts/check-local-backfills.sh" "$root" > "$w/out" 2>&1 \
  || { echo "FAIL: shipyard's own tree must pass strict local-backfill policy, since it publishes through this gate:"; cat "$w/out"; exit 1; }

echo "PASS: local-backfill-publish"
