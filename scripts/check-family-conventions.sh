#!/bin/sh
# platform: host-agnostic
#   usage: check-family-conventions.sh
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md, "Family
#       conventions (checked, not just written down)" -- the why and history for every check below
#       lives there; each check's chk_fail message carries the actionable summary.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"   # siblings live here (.shipyard/scripts in a consumer)
SHIPYARD_SCRIPTS="$SELF"
. "$SELF/registry-lookup.sh"
. "$SELF/lib/py.sh"
. "$SELF/deviation-reason.sh"
REL=".github/workflows/release.yml"
[ -f "$REL" ] || { echo "check-family-conventions: no $REL — not a product repo, nothing to check"; exit 0; }

CI_FILES="$(ls .github/workflows/*.yml 2>/dev/null || true)"
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md, "Family
#       conventions" -- "mentions" means on a non-comment line, and why; same test, same spelling, as
#       scripts/release-notes.sh's is_caller().
ci_mentions() {  # $1 = pattern. -e so a pattern starting with '-' (--notes-file) is not read as a flag.
  [ -n "$CI_FILES" ] || return 1
  # shellcheck disable=SC2086  # CI_FILES is a deliberate word-split list of paths
  grep -hv '^[[:space:]]*#' $CI_FILES 2>/dev/null | grep -q -e "$1"
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/conventions.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
TAB="$(printf '\t')"

TF="$tmp/tracked"
HAVE_TRACKED=1
chk_ran tracked-files
chk_tracked_files > "$TF" || { HAVE_TRACKED=0; : > "$TF"; }
tracked() { grep -qxF -- "$1" "$TF"; }
tracked_under() { awk -v p="$1/" 'index($0, p) == 1 { f = 1 } END { exit !f }' "$TF"; }
SRC_RX='\.(sh|yml|yaml|cmake)$|^CMakeLists\.txt$'
SRC_BATS_RX='\.(sh|yml|yaml|cmake|bats)$|^CMakeLists\.txt$'

chk_ran python3
PY_OK=0
if chk_python3 >/dev/null; then PY_OK=1; fi
# spec: SKILL.md "Renovate" -- one parse of .github/renovate.json, before the checks that read it:
#       an unparseable config is renovate-json-valid's failure alone, and those checks skip it.
RJ=.github/renovate.json
RJ_OK=0; RJ_RC=0
: > "$tmp/rjson"
if [ -f "$RJ" ] && [ "$PY_OK" -eq 1 ]; then
  chk_py /dev/stdin "$RJ" > "$tmp/rjson" <<'PY' || RJ_RC=$?
import json, sys
try:
    c = json.load(open(sys.argv[1]))
except ValueError as e:
    print('invalid: %s' % e)
    sys.exit(0)
ext = c.get('extends') if isinstance(c, dict) else None
pre = 'github>Mavergreen/shipyard'
if not (isinstance(ext, list) and any(isinstance(x, str) and x.split(':')[0].split('#')[0] == pre for x in ext)):
    print('noext')
PY
  if [ "$RJ_RC" -eq 0 ] && ! grep -q '^invalid: ' "$tmp/rjson"; then RJ_OK=1; fi
fi
py_crashed() {
  chk_fail "$1" "its python3 step did not run to the end" \
    "python3 exited non-zero and its own error is printed above" \
    "run the gate again; if the same error comes back, report it against Mavergreen/shipyard"
}

# spec: SKILL.md "Family conventions" check 1 -- release.yml must declare concurrency:; two publishes
#       racing the same tag is a corrupt release, not a flaky build.
chk_ran release-concurrency
grep -q '^concurrency:' "$REL" \
  || chk_fail release-concurrency "$REL declares no concurrency:" \
       "two publishes can race the same tag" \
       "add a concurrency: block -- group keyed on github.run_id, cancel-in-progress naming pull_request"

# spec: SKILL.md "Family conventions" check 1b -- a run that CAN PUBLISH must be alone in its
#       concurrency group and cancellable by nothing. cancel-in-progress: false protects only the
#       EXECUTING run, not a QUEUED one; the old shared-group shape discarded a mavericks-golang
#       release silently, 13 seconds after the run that evicted it (2026-09-09).
chk_ran concurrency-group
CONC="$(awk '/^concurrency:/{f=1;next} /^[^[:space:]#]/{f=0} f' "$REL")"
GROUP="$(printf '%s\n' "$CONC" | awk '/^[[:space:]]*group:/{f=1;print;next} /^[[:space:]]*cancel-in-progress:/{f=0} f')"
CANCEL="$(printf '%s\n' "$CONC" | awk '/^[[:space:]]*cancel-in-progress:/{f=1;print;next} /^[[:space:]]*group:/{f=0} f')"

printf '%s\n' "$GROUP" | grep -q 'github\.run_id' \
  || chk_fail concurrency-group "$REL concurrency group is shared between runs that can publish" \
       "a queued one is evicted by the next arrival and its release silently never happens" \
       "key the group per run: group: release-\${{ github.event_name == 'pull_request' && github.ref || github.run_id }}"

printf '%s\n' "$CANCEL" | grep -q 'pull_request' \
  || chk_fail concurrency-group "$REL can cancel a run that publishes" \
       "cancel-in-progress must name pull_request, the only event that may supersede" \
       "cancel-in-progress: \${{ github.event_name == 'pull_request' }}"

# spec: SKILL.md "Family conventions" check 2 -- test files that exist must be run by something; hand
#       enumeration is how a suite quietly stops running.
chk_ran tests-run-in-ci
if [ -d tests ] && [ -n "$(ls tests/*.sh tests/*.bats 2>/dev/null || true)" ]; then
  ci_mentions 'run-repo-tests' || ci_mentions 'ctest' \
    || chk_fail tests-run-in-ci "tests/ has test files but no workflow runs them" \
         "hand enumeration is how a suite quietly stops running" \
         "add: sh \"\$SHIPYARD_SCRIPTS/run-repo-tests.sh\"   (or ctest, where that is the driver)"
fi

# spec: SKILL.md "Family conventions" check 3 -- INGREDIENTS.md must exist.
chk_ran ingredients-md
[ -f INGREDIENTS.md ] \
  || chk_fail ingredients-md "no INGREDIENTS.md" \
       "the repo's build inputs are undocumented" \
       "list each input, where it is pinned, its Renovate status, and what a bump does"

# spec: SKILL.md "Family conventions" check 4 -- no Renovate key may restate a value the shared
#       preset already sets; the SAME key with a DIFFERENT value stays a legal override.
chk_ran renovate-no-restated-defaults
if [ -f .github/renovate.json ]; then
  for pair in 'ignoreTests:false'; do
    k="${pair%%:*}"; presetval="${pair#*:}"
    grep -q "\"$k\"[[:space:]]*:[[:space:]]*$presetval" .github/renovate.json \
      && chk_fail renovate-no-restated-defaults "renovate.json sets \"$k\": $presetval" \
           "that is exactly what the shared preset sets" \
           "delete the key (the preset owns it); keep it only to override with a different value"
  done
fi

# spec: SKILL.md "Family conventions" check 4b -- an automerge exception must carry a description
#       saying why a green build isn't enough (BUILD FINE AND BE WRONG); unexplained, it reads as
#       drift, not a decision.
chk_ran automerge-described
if [ -f .github/renovate.json ] && [ "$RJ_OK" -eq 1 ]; then
  rc=0
  chk_py /dev/stdin .github/renovate.json > "$tmp/automerge" <<'PY' || rc=$?
import json, sys
bad = []
for r in json.load(open(sys.argv[1])).get('packageRules', []):
    if 'automerge' in r and not (r.get('description') or '').strip():
        bad.append(r.get('matchDepNames') or r.get('matchPackageNames') or '(unnamed rule)')
if bad:
    print(bad)
PY
  if [ "$rc" -ne 0 ]; then
    py_crashed automerge-described
  elif [ -s "$tmp/automerge" ]; then
    chk_fail automerge-described "automerge exception with no description: $(cat "$tmp/automerge")" \
      "an exception nobody explains reads as drift, not a decision" \
      "say why a green build is not enough here (what would build fine and be wrong), or drop the rule and take the family default (ship-if-green)"
  fi
fi

# spec: SKILL.md "Family conventions" check 7 -- VERSION is a build product, never committed (an
#       untracked one in the tree is fine); something must also be able to SUPPLY the upstream
#       version (a committed UPSTREAM_VERSION, or a derive script).
chk_ran no-tracked-version
if [ "$HAVE_TRACKED" -eq 1 ] && tracked VERSION; then
  chk_fail no-tracked-version "VERSION is committed" \
    "it is a build product, and the committed copy goes stale while tags move on" \
    "git rm --cached VERSION; add /VERSION to .gitignore; commit UPSTREAM_VERSION instead"
fi

chk_ran upstream-version
if [ ! -f UPSTREAM_VERSION ] \
   && [ -z "$(ls build/derive-upstream-version.sh scripts/derive-upstream-version.sh 2>/dev/null || true)" ]; then
  chk_fail upstream-version "no UPSTREAM_VERSION and nothing to derive one" \
    "the version cannot be computed" \
    "commit UPSTREAM_VERSION (bare x.y.z or a date), or add build/derive-upstream-version.sh"
fi

# spec: SKILL.md "Family conventions" check 7b -- lines/ is the RETIRED per-line directory shape
#       (golang, nodejs and clang all migrated to one repo per line, 2026-09-22); a reappearing
#       TRACKED lines/ means the retired shape crept back into a repo. TRACKED, the same rule
#       checks 7/17 apply above: on this family's NFS checkouts, an ignored AppleDouble `._*` file
#       (lines/._126, lines/126/._patches) survives a migrating repo's `git pull` past the point
#       git deletes the tracked files, leaving an untracked `lines/` directory on disk that must
#       not fail a migrated checkout. Outside a git checkout this looks at nothing -- the
#       tracked-files failure above already fails the whole run when that happens.
chk_ran no-lines-dir
if [ "$HAVE_TRACKED" -eq 1 ] && tracked_under lines; then
  chk_fail no-lines-dir "lines/ exists" \
    "that per-line directory shape is retired; each upstream line is its own repo now" \
    "move this line's UPSTREAM_VERSION and patches/ to the repo root (see SKILL.md \"Multiple upstream lines\"); a NEW line belongs in a NEW repo, never a new lines/<id>/ here"
fi

# spec: SKILL.md "Family conventions" check 7c -- build/version.sh (and its wrapper siblings) must
#       not be git-ignored; a too-broad pattern drops them silently and only CI's fresh checkout fails.
chk_ran version-sh-tracked
if [ "$HAVE_TRACKED" -eq 1 ]; then
  if ci_mentions 'build/version.sh' || [ -e build/version.sh ]; then
    if git check-ignore -q build/version.sh 2>/dev/null; then
      chk_fail version-sh-tracked "build/version.sh is git-ignored" \
        "a too-broad .gitignore pattern (e.g. build*/) drops the committed version wrappers; local passes, CI's fresh checkout fails 'no build/version.sh'" \
        "ignore only build OUTPUT dirs (/_build/, build-*/, build/work/) — never build/ itself"
    fi
  fi
fi

# spec: SKILL.md "Family conventions" check 7d -- every build output dir the repo writes must be
#       git-ignored; mirrors check 7c. tailscale's untracked, unignored build/updater is the incident
#       that motivated it. tests/check-family-conventions-*-test.sh covers the detection edge cases.
chk_ran build-dirs-ignored
if [ "$HAVE_TRACKED" -eq 1 ]; then
  # platform: BSD sed aborts on binary content ("RE error: illegal byte sequence"), which a find(1)
  #           sweep would hit via NFS AppleDouble ._*.sh files -- the tracked list names only
  #           committed content, so this reads that instead.
  bdirs="$(
    {
      [ -n "$CI_FILES" ] && cat $CI_FILES 2>/dev/null
      grep '\.sh$' "$TF" | tr '\n' '\0' | xargs -0 cat 2>/dev/null
      :
    } | sed -e 's/^[[:space:]]*#.*$//' \
      | grep -oE 'cmake[^;|&]*-B[[:space:]]*[^[:space:];|&)]+' \
      | sed -e 's/.*-B[[:space:]]*//' -e 's/^["'"'"']//' -e 's/["'"'"']$//' || true
    if [ -f CMakePresets.json ]; then
      sed -n 's/.*"binaryDir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' CMakePresets.json
    fi
    :
  )"
  for d in $bdirs; do
    d="${d#\$\{sourceDir\}/}"          # presets say ${sourceDir}/build-native; we ask about build-native
    d="${d%/}"
    case "$d" in
      ''|/*|~*|*'$'*|*..*) continue ;; # out of tree, or a path we cannot resolve: not ours to demand
    esac
    case "$d" in
      *[!A-Za-z0-9._/+-]*) continue ;;
    esac
    # platform: ask about "$d/", not "$d". A .gitignore pattern written `build/updater/` matches a
    #           DIRECTORY, and git can only tell a nonexistent path is one if the query says so.
    #           Build output is exactly the thing that does not exist in a fresh checkout, so
    #           querying without the slash would have failed every correctly-ignored repo the
    #           moment this ran in CI.
    git check-ignore -q "$d/" 2>/dev/null && continue
    chk_fail build-dirs-ignored "$d is a build output directory this repo writes, but .gitignore does not cover it" \
      "one \`git add -A\` commits the build tree, and a stale CMakeCache keeps resolving a package that has been renamed away" \
      "add $d/ to .gitignore (any pattern that covers it; the family does not share one spelling)"
  done
fi

# spec: SKILL.md "Family conventions" check 8 -- every workflow must PARSE with duplicate keys
#       rejected; GitHub silently refuses to run a workflow with one, so nothing else in CI can catch
#       it. Cannot-verify (no python3) is the python3 failure above -- SKILL.md "Cannot-verify is a
#       FAILURE, never a pass." -- and the PyYAML it imports is the vendored copy chk_py puts first.
chk_ran workflow-yaml
if [ -n "$CI_FILES" ] && [ "$PY_OK" -eq 1 ]; then
  rc=0
  # shellcheck disable=SC2086  # deliberate word-split list of paths
  chk_py /dev/stdin $CI_FILES > "$tmp/yamlfail" <<'PYEOF' || rc=$?
import sys, yaml

class Strict(yaml.SafeLoader):
    pass

def no_duplicate_keys(loader, node, deep=False):
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in seen:
            raise ValueError("duplicate key %r on line %d" % (key, key_node.start_mark.line + 1))
        seen.add(key)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)

Strict.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, no_duplicate_keys)

for path in sys.argv[1:]:
    try:
        with open(path) as fh:
            yaml.load(fh, Strict)
    except Exception as exc:
        print("%s\t%s" % (path, " ".join(str(exc).split())))
PYEOF
  if [ "$rc" -ne 0 ]; then
    py_crashed workflow-yaml
  else
    while IFS="$TAB" read -r p m; do
      chk_fail workflow-yaml "$p does not parse: $m" \
        "GitHub rejects the whole workflow -- it never runs, so no other gate sees this" \
        "correct $p at the place named (a repeated key, a bad indent), then run the gate again"
    done < "$tmp/yamlfail"
  fi
fi

# spec: SKILL.md "Family conventions" check 9 -- every ❌ ingredient row must say "untrackable" or
#       wire a Renovate manager; a bare ❌ reads as an oversight, not a decision.
chk_ran ingredient-tracked
if [ -f INGREDIENTS.md ]; then
  while IFS= read -r line; do
    case "$line" in
      *❌*)
        case "$line" in
          *[Uu]ntrackable*) : ;;   # declared, with a reason nearby
          *) chk_fail ingredient-tracked "INGREDIENTS.md marks an ingredient as not auto-updating: $(printf '%s' "$line" | cut -c1-60)..." \
               "a bare ❌ reads as an oversight, not a decision" \
               "wire a Renovate customManager for it (a pinned hash that blocks the bot can verify against upstream's published SHA256SUMS instead), or mark it **untrackable** and say why" ;;
        esac
        ;;
    esac
  done < INGREDIENTS.md
fi

# spec: scripts/check-family-conventions.sh -- the delegating checks (10, 15, 22) run a sibling
#       script that reports its own failure under its own id; a pass shows what the sibling
#       printed, except where $6 is "quiet". Under shipyard-check (SHIPYARD_CHECK_RUNLOG set) they
#       do not run here at all: the dispatcher runs each sibling once, by its own registry row.
#       Run directly, the gate still delegates, so a consumer that calls it sees all three.
delegate() {  # $1 = id, $2 = the sibling script, $3 = rule, $4 = why, $5 = fix, $6 = quiet or empty
  _dg_id="$1"; _dg_script="$2"; _dg_quiet="${6:-}"
  [ -z "${SHIPYARD_CHECK_RUNLOG:-}" ] || return 0
  chk_ran "$_dg_id"
  if [ ! -f "$SELF/$_dg_script" ]; then
    chk_fail "$_dg_id" "cannot find $_dg_script next to this gate" \
      "the shipyard checkout is incomplete" \
      "check out the whole repo (family-conventions.yml does), not just this one script"
    return 0
  fi
  if _dg_out="$(sh "$SELF/$_dg_script" 2>"$tmp/dg.err")"; then
    [ -n "$_dg_quiet" ] || [ -z "$_dg_out" ] || printf '%s\n' "$_dg_out"
    [ ! -s "$tmp/dg.err" ] || cat "$tmp/dg.err" >&2
  elif [ "$(sed -n 1p "$tmp/dg.err" | cut -d: -f1)" = "$_dg_id" ]; then
    cat "$tmp/dg.err" >&2
    chk_status=1
  else
    chk_fail "$_dg_id" "$3" "$4" "$5"
    [ -z "$_dg_out" ] || printf '%s\n' "$_dg_out" | sed 's/^/  /' >&2
    sed 's/^/  /' "$tmp/dg.err" >&2
  fi
}

# spec: SKILL.md "Family conventions" check 10 -- no shell construct the 10.9 base system lacks;
#       invisible to CI by construction, since the runner that would catch it is never used.
#       Delegates to check-shell-portability.sh so the family's rule and shipyard's own test suite
#       cannot drift apart.
delegate shell-portability check-shell-portability.sh \
  "a tracked script uses a shell construct the 10.9 base system lacks" \
  "the runner that would catch it is never used, so nothing in CI sees it" \
  "apply the fix line printed under each hit below" quiet

# spec: SKILL.md "Family conventions" check 11 -- a release shipping a new upstream must link
#       upstream's own notes: a committed build/ or scripts/upstream-release-notes-url.sh, or
#       INGREDIENTS.md saying why there is nothing to link.
chk_ran upstream-notes
hook_tracked=no; hook_present=no
for d in build scripts; do
  if tracked "$d/upstream-release-notes-url.sh"; then hook_tracked=yes; fi
  if [ -f "$d/upstream-release-notes-url.sh" ]; then hook_present=yes; fi
done
if [ "$hook_tracked" = no ] && ! grep -q 'No upstream release notes: *[^ ]' INGREDIENTS.md 2>/dev/null; then
  if [ "$hook_present" = yes ]; then
    chk_fail upstream-notes "upstream-release-notes-url.sh exists but is not committed" \
      "a .gitignore'd build/ drops it silently, and CI's fresh checkout never sees it" \
      "git add -f it (and ignore only build OUTPUT dirs, never build/ itself)"
  else
    chk_fail upstream-notes "a release shipping a new upstream cannot link upstream's notes" \
      "there is no committed build/upstream-release-notes-url.sh, and INGREDIENTS.md does not say why" \
      "add the hook (usually one printf -- see the conventions skill, 'A new upstream links upstream's own notes'), or a line 'No upstream release notes: <reason>' in INGREDIENTS.md"
  fi
fi

# spec: SKILL.md "Family conventions" check 12 -- a workflow that signs must also call
#       scan-for-key.yml; publish-release.yml refuses a signed release with no scan record.
chk_ran signing-scans-for-key
if ci_mentions 'sign_and_appcast'; then
  ci_mentions 'scan-for-key.yml' \
    || chk_fail signing-scans-for-key "a workflow signs (sign_and_appcast.sh) but none calls scan-for-key.yml" \
         "publish-release.yml refuses a signed release with no scan record" \
         "add a scan job between the signing job and publish, under always() (the snippet is at the top of shipyard's scan-for-key.yml), and make publish need it"
fi

# spec: SKILL.md "Family conventions" check 12 -- sign_and_appcast.sh writes <feed-dir>/<product>.xml
#       itself, so every call passes both and redirects nothing; a line ending in \ continues the call.
chk_ran sign-call-shape
_bad12="$(for f in $CI_FILES; do
  awk '
    /^[[:space:]]*#/ { next }
    { sub(/(^|[[:space:]])#.*$/, "") }
    /\\$/ { sub(/\\$/, ""); held = held $0 " "; next }
    { print held $0; held = "" }
    END { if (held != "") print held }
  ' "$f" \
    | grep -E '(^|[;&|`]|[$]\(|[[:space:]]then|[[:space:]]do|[[:space:]]exec|^[[:space:]]*-?[[:space:]]*run:)[[:space:]]*((if|elif|while|until|!)[[:space:]]+)*((/bin/)?sh([[:space:]]+-[A-Za-z]+)*[[:space:]]+[^[:space:]=]*sign_and_appcast\.sh|[^[:space:]=]*/sign_and_appcast\.sh)"*([[:space:]]|$)' \
    | while IFS= read -r call; do
        args="$(printf '%s\n' "$call" | sed -e 's/.*sign_and_appcast\.sh"*//' -e 's/[;|].*//' -e 's/&&.*//')"
        printf '%s\n' "$args" | grep -Eq '(^|[[:space:]])--product[[:space:]]' \
          && printf '%s\n' "$args" | grep -Eq '(^|[[:space:]])--feed-dir[[:space:]]' \
          && ! printf '%s\n' "$args" | grep -Eq '(^|[^2])>' \
          || echo "$f: $call"
      done
done)"
if [ -n "$_bad12" ]; then
  chk_fail sign-call-shape "a call to sign_and_appcast.sh must pass --product and --feed-dir and redirect nothing" \
    "it writes <feed-dir>/<product>.xml itself; the calls that do not: $(printf '%s\n' "$_bad12" | tr '\n' ';' | sed 's/;$//')" \
    "sh \"\$SHIPYARD_SCRIPTS/sign_and_appcast.sh\" --product <short> --feed-dir dist ... as one command (continue it with a trailing \\), with no > after it"
fi

# spec: SKILL.md "Family conventions" check 13 -- a Renovate manager whose captured pin ends in
#       -mavericks.N needs regex versioning that compares N; default versioning coerces it away and
#       every repackage compares equal (swift-runtime missed three releases this way).
chk_ran renovate-suffix-versioning
if [ -f .github/renovate.json ] && [ "$HAVE_TRACKED" -eq 1 ] && [ "$RJ_OK" -eq 1 ]; then
  rc=0
  chk_py /dev/stdin .github/renovate.json "$TF" > "$tmp/suffix" <<'PY' || rc=$?
import fnmatch, json, re, sys
def js(rx):  # Renovate regexes are JS: (?<name>...) is Python's (?P<name>...); lookbehinds stay as they are
    return re.sub(r'\(\?<(?![=!])', '(?P<', rx)
def matcher(pat):
    m = re.fullmatch(r'/(.*)/([a-z]*)', pat)
    if m:
        rx = re.compile(js(m.group(1)), re.I if 'i' in m.group(2) else 0)
        return lambda f: rx.search(f) is not None
    return lambda f: fnmatch.fnmatch(f, pat)
# What Renovate sees is what is committed: the tracked list is the second argument
files = [f for f in open(sys.argv[2]).read().split('\n') if f]
compared = {'major', 'minor', 'patch', 'build', 'revision'}  # 'prerelease' marks a version unstable
bad = []
for mgr in json.load(open(sys.argv[1])).get('customManagers', []):
    if mgr.get('customType') != 'regex':
        continue
    pats = [matcher(p) for p in mgr.get('managerFilePatterns', [])]
    vt = mgr.get('versioningTemplate') or ''
    for f in (f for f in files if any(p(f) for p in pats)):
        try:
            text = open(f, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        for ms in mgr.get('matchStrings', []):
            for m in re.finditer(js(ms), text, re.M):
                cv = (m.groupdict().get('currentValue') or '').strip()
                n = re.search(r'-mavericks\.(\d+)$', cv)
                if not n:
                    continue
                vm = re.match(js(vt[len('regex:'):]), cv) if vt.startswith('regex:') else None
                if vm and any(k in compared and v == n.group(1) for k, v in vm.groupdict().items()):
                    continue
                dep = mgr.get('depNameTemplate') or (m.groupdict().get('depName')) or mgr.get('packageNameTemplate') or '(unnamed)'
                bad.append('%s = %s (%s)' % (dep, cv, f))
for b in bad:
    print(b)
PY
  if [ "$rc" -ne 0 ]; then
    py_crashed renovate-suffix-versioning
  else
    while IFS= read -r b; do
      chk_fail renovate-suffix-versioning "Renovate cannot see new -mavericks.N releases of $b" \
        "its versioning does not compare N, so every -mavericks.N of one upstream compares equal" \
        'give that manager "versioningTemplate": "regex:^(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)-mavericks\\.(?<build>\\d+)$"'
    done < "$tmp/suffix"
  fi
fi

# spec: SKILL.md "Family conventions" check 14 -- the release body must come from the shared
#       generator (release-notes.sh), never hand-written, never GitHub's --generate-notes; the appcast
#       and the Release page must read the same file. tests/check-family-conventions-*-test.sh covers
#       the detection edge cases (quoting, line continuations, variable-routed paths).
chk_ran release-notes-generated
if [ -n "$CI_FILES" ]; then
  ci_mentions '[/ ]release-notes\.sh' \
    || chk_fail release-notes-generated "no workflow builds the release body with the shared generator (release-notes.sh)" \
         "the release body comes from one generator, so every consumer reads the same file" \
         "call \$SHIPYARD_SCRIPTS/release-notes.sh --tag/--version/--product --out dist/RELEASE_NOTES.md"

  if ci_mentions '>[[:space:]]*[^ ]*RELEASE_NOTES\.md' \
     || ci_mentions '[[:space:]]cp[[:space:]][^;&|]*[[:space:]][^ ;&|]*RELEASE_NOTES\.md'; then
    chk_fail release-notes-generated "a workflow hand-writes the release body into RELEASE_NOTES.md" \
      "release-notes.sh is the only thing that may write that file" \
      "delete it -- release-notes.sh --out <path> is the only thing that writes that file"
  fi

  if ci_mentions '--generate-notes'; then
    chk_fail release-notes-generated "a workflow publishes GitHub's autogenerated notes (--generate-notes)" \
      "they cannot say which ingredient moved" \
      "build the body with release-notes.sh"
  fi

  # platform: a flag and its value are separated by a space OR an "=", and grep and sed see only
  #           the characters, so the separator below is a character class rather than a literal
  #           space. Demanding one of the two is also what keeps --out-dir and --output from
  #           matching as --out.
  strip_arg() {  # $1 = the flag itself, e.g. '--out'; prints each value it is given, unquoted, once
    # shellcheck disable=SC2086  # CI_FILES is a deliberate word-split list of paths
    grep -hv '^[[:space:]]*#' $CI_FILES 2>/dev/null \
      | awk '
          { if (buf != "") sub(/^[[:space:]]+/, "") }     # the indent of a continuation line is not data
          /\\[[:space:]]*$/ {
            sub(/\\[[:space:]]*$/, ""); sub(/[[:space:]]+$/, "")
            buf = buf $0 " "                              # exactly one space: two would capture ""
            next
          }
          { print buf $0; buf = "" }
          END { if (buf != "") print buf }' \
      | grep -o -e "$1[ =][\"']\{0,1\}[^ \"']*" \
      | sed "s/^$1[ =][\"']\{0,1\}//" | sort -u
  }
  outs="$(strip_arg '--out' | grep '\.md$' || true)"
  ins="$(strip_arg '--notes-file' || true)"
  for n in $ins; do
    case "$n" in
      *'$'*|*'{'*|*'\'*) continue ;;
    esac
    printf '%s\n' "$outs" | grep -qxF "$n" \
      || chk_fail release-notes-generated "a workflow reads a notes file the generator does not write: --notes-file $n" \
           "the appcast and the Release page must read the same file" \
           "pass the same path release-notes.sh was given as --out"
  done
fi

# spec: SKILL.md "Family conventions" check 15 -- every comment cites a reason (# platform: or
#       # spec:); delegates to check-comments.sh so the family's rule and shipyard's own scanner
#       cannot drift apart. Opt-in falls out of check-comments.sh itself: it exits 0 with no
#       comment-reasons file, so a consumer inherits this check through @v1 but not its failure,
#       until it sweeps its own tree and adds one. A swept repo that still wants ONE declared
#       exception states it under INGREDIENTS.md "## Conformance deviations" as
#       "- comments: <reason>", and that switches the check off REPO-WIDE. The "<check>:<glob>"
#       scoping that check-artifact-conformance.sh honours is NOT honoured here and is rejected
#       rather than swallowed as part of the reason.
delegate comments check-comments.sh \
  "a comment cites no reason" \
  "every comment says why it is there, and the lines below are the ones that do not" \
  "cite one: # platform: <a fact about the platform or a tool>, or # spec: <a locatable pointer>"

# spec: scripts/deviations.sh -- ONE parser for the "## Conformance deviations" grammar, shared with
#       check-artifact-conformance.sh; an incomplete entry is reported once, by check-deviations.sh.
DEVS="$(sh "$SELF/deviations.sh" . 2>/dev/null || true)"
printf '%s\n' "$DEVS" | mav_deviation_facts > "$tmp/devfacts"
SHIPYARD_CHECK_DEVIATION_FACTS="$tmp/devfacts"
deviated() { chk_deviated "$1" "$2" >/dev/null; }

# spec: SKILL.md "Family conventions" check 16 -- nothing tracked may read the CMake user package
#       registry. tests/ is excluded for the same reason check 18 excludes it: a test that asserts the
#       registry is GONE has to name it, and a sweep that cannot tell an assertion from a usage would
#       report that proof as the violation. What a repo SHIPS is what is checked, so a COMMENT naming
#       the registry is prose, not a read. This check's own chk_fail message may not spell the full
#       path either, or the gate matches itself -- a first draft reported shipyard as the family's
#       worst offender that way.
chk_ran registry-read
grep -E "$SRC_BATS_RX" "$TF" | grep -v '^tests/' > "$tmp/l532" || :
while IFS= read -r f; do
  # platform: the pattern must not be a literal occurrence of itself, or this gate is its own first
  #           offender. "package[s]" is the `ps | grep [f]oo` idiom; the bracket changes nothing about
  #           what it matches.
  grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -q '\.cmake/package[s]' || continue
  deviated registry-read "$f" && continue
  chk_fail registry-read "$f reads the CMake user package registry (the ~/.cmake export(PACKAGE) tree)" \
    "nothing writes it any more" \
    "source msc.sh (it asks shipyard-cmake and exports SHIPYARD_SCRIPTS), or use \$SHIPYARD_SCRIPTS in CI"
done < "$tmp/l532"

# spec: SKILL.md "Family conventions" check 26 -- a family repo's Renovate config is
#       .github/renovate.json and no other path: checks 4, 4b and 13 read only that file, and
#       shipyard's configure step scaffolds it when absent, so a config tracked anywhere else is dead
#       beside the scaffold and exempts its repo from those checks. These are every other place
#       Renovate itself looks for a config file (package.json's "renovate" key is not a file and is
#       not scanned). Tracked paths only, like checks 7 and 16; a repo holding BOTH fails too, since
#       Renovate takes one by precedence and the other is dead config.
chk_ran renovate-path
for f in renovate.json renovate.json5 .renovaterc .renovaterc.json .renovaterc.json5 \
         .github/renovate.json5 .gitlab/renovate.json .gitlab/renovate.json5; do
  tracked "$f" || continue
  deviated renovate-path "$f" && continue
  chk_fail renovate-path "$f is a tracked Renovate config, and the family's is .github/renovate.json only" \
    "the Renovate checks (4, 4b, 13) never read $f" \
    "git mv $f .github/renovate.json (merge into the existing .github/renovate.json instead if there is one), or declare '- renovate-path:$f: <reason>' under INGREDIENTS.md's ## Conformance deviations"
done

# spec: SKILL.md "Family conventions" check 17 -- a product's msc.sh must equal shipyard's canonical
#       template byte for byte. TRACKED copies only, the same rule checks 7c/7d apply: an untracked
#       build/msc.sh in a developer's worktree is not what the repo ships, and failing on it would
#       make the gate unrunnable for exactly the person mid-way through fixing it.
chk_ran msc-template
_tmpl="$SELF/templates/msc.sh"
if [ ! -f "$_tmpl" ]; then
  # platform: `cmp -s` with a missing operand is "different", so comparing against a template that
  #           MOVED would tell all fifteen repos at once that their msc.sh is not canonical, with the
  #           one true cause nowhere in the message. Name the template instead.
  chk_fail msc-template "cannot find shipyard's canonical msc.sh at $_tmpl" \
    "the shipyard checkout is incomplete, or the template moved" \
    "check out the whole repo (family-conventions.yml does); if the template moved, this check must move with it"
else
  for f in build/msc.sh msc.sh; do
    tracked "$f" || continue
    deviated msc-template "$f" && continue
    cmp -s "$f" "$_tmpl" && continue
    _diff="$(diff "$_tmpl" "$f" 2>/dev/null | head -6 | tr '\n' ';' | sed 's/;$//')"
    chk_fail msc-template "$f is not shipyard's canonical msc.sh" \
      "the template is the one source and a product's copy never differs from it; the first differences: $_diff" \
      "copy it from shipyard: cp \"\$SHIPYARD_SCRIPTS/templates/msc.sh\" $f   (never edit your copy -- change the template)"
  done
fi

# spec: SKILL.md "Family conventions" check 18 -- configure, test and package with shipyard-cmake /
#       shipyard-ctest / shipyard-cpack. It reads lines, not shell syntax; SKILL.md's "Check 18" notes
#       state the deliberate blind spot (a bare "(" before the command), the shapes that still count
#       as a call inside quotes and heredocs, and the known false negatives. Every one of them is
#       pinned by tests/check-family-conventions-*-test.sh, so the list cannot quietly go stale.
chk_ran shipyard-cmake-only
cmdlist="$tmp/cmds"
: > "$cmdlist"
if [ -n "$CI_FILES" ] && [ "$PY_OK" -eq 1 ]; then
  rc=0
  # shellcheck disable=SC2086  # deliberate word-split list of paths
  chk_py /dev/stdin $CI_FILES >> "$cmdlist" <<'PYEOF' || rc=$?
import sys, yaml
for p in sys.argv[1:]:
    try:
        wf = yaml.safe_load(open(p)) or {}
    except Exception:
        continue          # check 8 owns "this workflow does not parse"; do not report it twice
    if not isinstance(wf, dict):
        continue
    for job in (wf.get("jobs") or {}).values():
        if not isinstance(job, dict):
            continue
        # A job that demonstrably runs off macOS is skipped: shipyard ships no Linux pkg and no
        # Linux shipyard-cmake, so demanding it there is incoherent -- the same reasoning
        # MavericksShipyardConfig.cmake gives for skipping its refusal unless CMAKE_HOST_APPLE.
        # Requiring it anyway broke container-tools' ubuntu jobs twice, most recently 2026-09-16.
        # Skip ONLY when runs-on is plainly non-macOS; anything unresolvable (an expression, a
        # matrix) is still checked, because a gate that stays silent when it cannot tell is the
        # failure this family keeps paying for.
        ro = job.get("runs-on")
        labels = ro if isinstance(ro, list) else [ro]
        if labels and all(isinstance(l, str) and "${{" not in l for l in labels) \
           and not any("macos" in l.lower() for l in labels):
            continue
        for st in (job.get("steps") or []):
            if not isinstance(st, dict):
                continue
            # `run:` is not necessarily a string. YAML reads an unquoted `run: true` as a BOOL, and
            # `or ""` keeps a True -- which then has no .splitlines() and takes the whole gate down
            # with a traceback pointing at stdin. Ask what it IS.
            run = st.get("run")
            if not isinstance(run, str):
                continue
            for line in run.splitlines():
                print("%s\t%s" % (p, line))
PYEOF
  [ "$rc" -eq 0 ] || py_crashed shipyard-cmake-only
fi
grep '\.sh$' "$TF" | grep -v '^tests/' > "$tmp/l634" || :
while IFS= read -r f; do
  sed "s|^|$f$TAB|" "$f"
done < "$tmp/l634" >> "$cmdlist"
# platform: one process per line made this check 71% of the gate's run time on shipyard (about
#           20,000 process starts); one awk pass filters every line instead. `[[:space:]]` and
#           `sub(/^[^\t]*\t/,...)` are verified on BSD awk 20070501. The hits go to a file, not a
#           pipe, so the loop stays in this shell and `chk_fail` still counts.
# spec: SKILL.md "Check 18" -- command position is line start, a separator (; & | or a backtick),
#       "$(", or then/do/exec. A bare "(" is deliberately NOT command position: a whole-org survey
#       found three compliant repos whose only hit was `... || { echo "not built (cmake --build
#       <dir>)"; }`. A `(cd x && cmake ...)` still matches, on the "&".
cmdhits="$tmp/hits"
# platform: a failed awk must fail the gate, not pass it as "no hits" -- `set -e` alone would end the
#           run with no word about which check died.
awk -F"$TAB" '{
  l = $0; sub(/^[^\t]*\t/, "", l)
  t = l; sub(/^[[:space:]]+/, "", t)
  if (t == "" || substr(t, 1, 1) == "#") next
  if (l ~ /(^|[;&|`]|[$]\(|[[:space:]]then|[[:space:]]do|[[:space:]]exec|^then|^do|^exec)[[:space:]]*(cmake|ctest|cpack)([[:space:]]|$)/) print
}' "$cmdlist" > "$cmdhits" \
  || chk_fail shipyard-cmake-only "check 18 could not scan shell lines (awk failed)" \
       "an empty hit list would read as no plain cmake anywhere" \
       "run \`command -v awk\` ($(command -v awk || echo none)) and make sure it is a working awk"
while IFS="$TAB" read -r f line; do
  deviated shipyard-cmake-only "$f" && continue
  chk_fail shipyard-cmake-only "$f runs plain cmake/ctest/cpack: $(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-70)" \
    "MavericksShipyardConfig.cmake refuses any other cmake" \
    "use shipyard-cmake / shipyard-ctest / shipyard-cpack"
done < "$cmdhits"

# spec: SKILL.md "Family conventions" check 19 -- a repo whose CI builds must CALL the
#       out-of-tree assertion. The assertion asks what the source tree looks like after a
#       build and never how the build ran, so it holds for a build system nobody has invented
#       yet; requiring the call is what makes it impossible to skip by doing nothing. The
#       design this replaces inspected CMakePresets.json's binaryDir instead, which would have
#       exempted clang and golang -- the two repos with the MOST in-tree build references --
#       because they build from shell scripts. ci_mentions strips comment lines, so a
#       commented-out call is not a call.
# spec: SKILL.md "Check 19" -- BOTH halves are required, because --record returns 0
#       unconditionally: a repo that calls only --record has adopted the half that can never
#       fail. Matching the call SHAPE rather than the bare script name is also what tells a call
#       from a mention -- a step name or a trailing comment carries no leading "/" and no
#       argument. The "*" allows the closing quote in `sh "$SHIPYARD_SCRIPTS/...sh" --record`;
#       both that spelling and shipyard's own unquoted `sh scripts/...sh` are in use family-wide.
chk_ran tree-clean-wired
if [ -n "$CI_FILES" ]; then
  ci_mentions '/assert-tree-clean\.sh"*[[:space:]]*--record' \
    || chk_fail tree-clean-wired "no workflow records the source tree before the build -- assert-tree-clean.sh --record is never called" \
         "the bare call has nothing to compare against without it" \
         "call \$SHIPYARD_SCRIPTS/assert-tree-clean.sh --record before the build"
  ci_mentions '/assert-tree-clean\.sh"*[[:space:]]*$' \
    || chk_fail tree-clean-wired "no workflow asserts that the build wrote nothing into the source tree" \
         "--record on its own returns 0 unconditionally and can never fail" \
         "call \$SHIPYARD_SCRIPTS/assert-tree-clean.sh after the build"
fi

# spec: SKILL.md "Family conventions" check 21 -- a repo that builds a .pkg must run artifact
#       conformance, or nothing checks what its pkg installs: the identity and install-path rules
#       ("Install layout and identity") live in check-artifact-conformance.sh, and a product that
#       never calls it is exempt from all of them by omission. Tests are excluded: fixtures build
#       throwaway pkgs on purpose.
chk_ran artifact-checks-wired
builds_pkg=""
for f in $(grep -E "$SRC_RX" "$TF" | grep -v '^tests/' || true); do
  grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -qE '(^|[^A-Za-z0-9_-])(pkgbuild|productbuild)([[:space:]]|$)' && { builds_pkg="$f"; break; }
done
[ -n "$builds_pkg" ] || ! ci_mentions 'sign_and_appcast' || builds_pkg="a signing workflow"
if [ -n "$builds_pkg" ] && ! ci_mentions 'check-artifact-conformance\.sh' && ! deviated artifact-checks-wired "$REL"; then
  chk_fail artifact-checks-wired "this repo builds a .pkg ($builds_pkg) but no workflow runs check-artifact-conformance.sh" \
    "nothing checks what it installs or under which identity" \
    "pipe artifact-facts.sh into check-artifact-conformance.sh at package time (see the conventions skill, 'Artifact conformance'), or declare '- artifact-checks-wired: <reason>' under INGREDIENTS.md's ## Conformance deviations"
fi

# spec: SKILL.md "Family conventions" check 20 -- CMakeUserPresets.json is the per-developer
#       build-location override. A preset's own `environment` block is applied AFTER the real
#       process environment, so exporting MAVERICKS_BUILD_ROOT cannot redirect a --preset
#       build and this file is the only thing that can. It must be gitignored, or it pollutes
#       git status and gets committed by accident. Keyed on a COMMITTED CMakePresets.json: a
#       repo with no presets has no override channel to protect.
chk_ran user-presets-ignored
if [ -f CMakePresets.json ] && tracked CMakePresets.json; then
  git check-ignore -q CMakeUserPresets.json 2>/dev/null \
    || chk_fail user-presets-ignored "CMakeUserPresets.json is not gitignored" \
         "it is the per-developer build-location override, and it pollutes git status or gets committed by accident" \
         "add CMakeUserPresets.json to .gitignore"
fi

# spec: SKILL.md "Family conventions" check 22 -- every tracked script declares its host, and a
#       host-agnostic one runs no macOS-only tool. Delegated to check-host-tools.sh, like 10 and 15,
#       so the family's rule and shipyard's own Linux job cannot drift apart. Opt-in falls out of
#       check-host-tools.sh itself: a repo where no script declares a host passes, saying so.
delegate host-tools check-host-tools.sh \
  "a tracked script breaks the host-declaration rule" \
  "a host-agnostic script has to run on Linux too, and once one script declares a host every script must" \
  "apply the fix line printed under each hit below"

# spec: SKILL.md "Family conventions" check 23 -- a pkg-building repo gets its install scripts and
#       manifest from stage_product.sh, or the layout conformance enforces has no one generating it.
# spec: scripts/check-family-conventions.sh check 18 -- a mention is not a call unless it sits in
#       COMMAND POSITION: line start, a separator (; & | or a backtick), "$(", then/do/exec (check
#       18's own anchor set), a YAML "run:" key or a CMake "COMMAND" keyword, optionally followed by
#       if/elif/while/until/!, which run the command after them. The call is sh or /bin/sh (with
#       option flags) and a word ending stage_product.sh, or a word ending /stage_product.sh; a word
#       holding "=" is an assignment, not a call. SKILL.md's check 23 row lists what this misses.
chk_ran stage-product
if [ -n "$builds_pkg" ] && ! deviated stage-product "$REL"; then
  staged=""
  grep -E "$SRC_RX" "$TF" | grep -v '^tests/' > "$tmp/l741" || :
  while IFS= read -r f; do
    grep -v '^[[:space:]]*#' "$f" 2>/dev/null \
      | grep -Eq '(^|[;&|`]|[$]\(|[[:space:]]then|[[:space:]]do|[[:space:]]exec|^then|^do|^exec|^[[:space:]]*-?[[:space:]]*run:|[[:space:](]COMMAND)[[:space:]]*((if|elif|while|until|!)[[:space:]]+)*((/bin/)?sh([[:space:]]+-[A-Za-z]+)*[[:space:]]+[^[:space:]=]*stage_product\.sh|[^[:space:]=]*/stage_product\.sh)"*([[:space:]]|$)' \
      && { staged="$f"; break; }
  done < "$tmp/l741"
  [ -n "$staged" ] || chk_fail stage-product "this repo builds a .pkg ($builds_pkg) but never calls stage_product.sh" \
                         "its install scripts and manifest are hand-rolled" \
                         "stage the product under usr/local/mavergreen/<name>/ and call \$SHIPYARD_SCRIPTS/stage_product.sh (see the conventions skill, 'Install layout'), or declare '- stage-product: <reason>' under INGREDIENTS.md's ## Conformance deviations"
fi

# spec: SKILL.md "Family conventions" check 24 -- every feed URL and updater identity is derived from
#       the registry's repo, so a pkg-building repo the registry does not name publishes feeds nothing polls.
chk_ran registered
if [ -n "$builds_pkg" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && ! deviated registered "$REL"; then
  _c24=0; registry_lookup shorts "${GITHUB_REPOSITORY#*/}" || _c24=$?
  case "$_c24" in
    0) ;;
    1) chk_fail registered "this repo builds a .pkg ($builds_pkg), but shipyard's scripts/product-names assigns no product to ${GITHUB_REPOSITORY#*/}" \
            "every feed URL and updater identity is derived from the registry's repo" \
            "register its short names with this repo in scripts/product-names, or rename the repo to the one registered" ;;
    *) chk_fail registered "cannot look up ${GITHUB_REPOSITORY#*/} in shipyard's registry" \
            "$REG_WHY" \
            "fix shipyard's scripts/product-names -- sh product-name.sh check says what is wrong with it" ;;
  esac
fi

# spec: SKILL.md "Family conventions" check 25, and "Rosetta" above -- the family is retiring
#       Rosetta, so an undeclared use is swept before macOS 28 removes Rosetta for good, not found
#       the day it does. Neither the pattern nor a chk_fail message below may spell what it scans for
#       as one contiguous run of a command word, a space, and its flag -- the same self-match
#       check 16 avoids by writing "package[s]" -- or this check is its own first offender. tests/
#       is scanned too: a best-effort test that SKIPs (77) without Rosetta still runs translated
#       when it doesn't skip, so it still needs a declaration -- see "Rosetta", above.
chk_ran rosetta
grep -E "$SRC_BATS_RX" "$TF" | grep -v '^tests/fixtures/checks/' > "$tmp/l775" || :
while IFS= read -r f; do
  # spec: SKILL.md "Family conventions" check 25 -- a trailing " #..." remark is stripped (a "#"
  #       preceded by whitespace) before matching, so it cannot force a bogus declaration.
  hit="$(grep -v '^[[:space:]]*#' "$f" 2>/dev/null \
    | sed 's/[[:space:]]#.*$//' \
    | grep -E '(^|[^A-Za-z0-9_./-])((/usr/bin/)?arch[[:space:]]+(-x86_64|-arch[[:space:]]+x86_64)|softwareupdate[[:space:]]+--install-rosetta)([[:space:]]|$)' \
    | head -1 | sed 's/^[[:space:]]*//' | cut -c1-70)"
  [ -n "$hit" ] || continue
  deviated rosetta "$f" && continue
  chk_fail rosetta "$f depends on Rosetta translation, with no declared rosetta:<path> deviation covering it: $hit" \
    "the family is retiring Rosetta, so an undeclared use is swept before macOS 28 removes it" \
    "declare what runs translated, why it can't be native yet, and when to reconsider under INGREDIENTS.md's ## Conformance deviations as '- rosetta:$f: <reason>' (see the conventions skill, 'Rosetta')"
done < "$tmp/l775"

# spec: SKILL.md "Family conventions" check 27 -- superpowers working files live in the gitignored
#       .superpowers/, and an IDE's per-user state (.idea/) is never tracked. Both dirs must be
#       ignored AND nothing may be tracked under them or under docs/superpowers/. Needs the tracked
#       list, like check 7.
chk_ran superpowers-ignored
if [ "$HAVE_TRACKED" -eq 1 ]; then
  for _d in .superpowers .idea; do
    grep -qxE "/?\\$_d/?" .gitignore 2>/dev/null \
      || chk_fail superpowers-ignored ".gitignore has no line ignoring $_d/" \
           "the directory holds per-user working files that must not be committed" \
           "add a line '$_d/' to .gitignore"
  done
  for _d in .superpowers docs/superpowers .idea; do
    if tracked_under "$_d"; then
      chk_fail superpowers-ignored "files are tracked under $_d/, which is never committed" \
        "it holds per-user working files" \
        "git rm -r --cached $_d (the files stay on disk), and make sure .gitignore ignores it"
    fi
  done
fi

# spec: SKILL.md "The `ignoreTests` policy" -- Renovate's automerge waits on a CI status check, so
#       release.yml must build pull requests to main (or every push); a repo with no build to gate
#       sets ignoreTests: true instead. Comments and "on:" blocks are read as text so this needs no python3.
on_block() {  # $1 = a workflow; its top-level on: block, comment lines dropped
  grep -v '^[[:space:]]*#' "$1" | awk '/^(on|"on"):/ { f = 1; print; next } /^[^[:space:]]/ { f = 0 } f'
}
on_has() {  # stdin = an on: block; $1 = a trigger, as a key, in a list or inline
  grep -Eq "^(on|\"on\"):.*[^a-z_]$1([^a-z_]|\$)|^[[:space:]]+-[[:space:]]*$1[[:space:]]*\$|^  $1:"
}
trigger_lines() {  # stdin = an on: block; $1 = a trigger; prints that trigger's own block
  awk -v t="$1" '$0 ~ "^  " t ":" { f = 1; print; next } /^  [^[:space:]]/ { f = 0 } /^[^[:space:]]/ { f = 0 } f'
}
chk_ran pr-trigger
on_block "$REL" > "$tmp/on-release"
if ! grep -q '"ignoreTests"[[:space:]]*:[[:space:]]*true' .github/renovate.json 2>/dev/null \
   && ! deviated pr-trigger "$REL"; then
  _pr=0
  if on_has pull_request < "$tmp/on-release"; then
    trigger_lines pull_request < "$tmp/on-release" > "$tmp/pr-lines"
    if ! grep -q 'branches:' "$tmp/pr-lines" \
       || grep -Eq "(\[|,|-)[[:space:]]*['\"]?(main|\*\*)['\"]?[[:space:]]*(\]|,|\$)" "$tmp/pr-lines"; then _pr=1; fi
  fi
  if [ "$_pr" -eq 0 ] && on_has push < "$tmp/on-release" \
     && trigger_lines push < "$tmp/on-release" | grep -Eq "(\[|,|-)[[:space:]]*['\"]?\*\*['\"]?[[:space:]]*(\]|,|\$)"; then
    _pr=1
  fi
  [ "$_pr" -eq 1 ] || chk_fail pr-trigger "$REL does not build pull requests to main" \
    "Renovate's automerge waits on a CI check, and without one on the bump PR it stalls forever" \
    "add pull_request: with branches: [main] under on:, or set \"ignoreTests\": true in .github/renovate.json if the repo has no build to gate"
fi

# spec: SKILL.md "Release workflow" -- the notes are generated first, then the state is recorded, then the
#       appcast is signed, then the release is published: the appcast and the Release must carry the
#       same notes. Order is by first non-comment mention in release.yml; a step a repo does not have
#       takes no part (release-notes-generated and signing-scans-for-key say whether it must exist).
chk_ran publish-order
if ! deviated publish-order "$REL"; then
  _prev=0; _prevname=""
  for _step in 'release-notes\.sh' 'release-state-record\.sh' 'sign_and_appcast\.sh' 'publish-release\.yml'; do
    _ln="$(awk -v re="(^|[^A-Za-z0-9_-])$_step" '/^[[:space:]]*#/ { next } $0 ~ re { print NR; exit }' "$REL")"
    [ -n "$_ln" ] || continue
    _name="$(printf '%s' "$_step" | sed 's/\\//g')"
    if [ "$_ln" -lt "$_prev" ]; then
      chk_fail publish-order "$REL mentions $_name (line $_ln) before $_prevname (line $_prev)" \
        "the appcast and the Release must carry the same notes, which only holds if notes come first, then the state, then signing, then publishing" \
        "reorder the steps: release-notes.sh, release-state-record.sh, sign_and_appcast.sh, then publish-release.yml"
      break
    fi
    _prev="$_ln"; _prevname="$_name"
  done
fi

# spec: SKILL.md "Renovate" -- .github/renovate.json extends github>Mavergreen/shipyard, and the
#       preset's defaults (automerge, ignoreTests) only reach a repo that does. Parsing is python3's
#       (like 4b); a missing python3 is reported once, as `python3`.
chk_ran renovate-json-valid
chk_ran renovate-extends-preset
if [ ! -f "$RJ" ]; then
  deviated renovate-extends-preset "$RJ" \
    || chk_fail renovate-extends-preset "there is no $RJ" \
         "without it the repo gets none of the preset's defaults" \
         "add .github/renovate.json with {\"extends\": [\"github>Mavergreen/shipyard\"]}"
elif [ "$PY_OK" -eq 1 ]; then
  if [ "$RJ_RC" -ne 0 ]; then
    py_crashed renovate-json-valid
  elif grep -q '^invalid: ' "$tmp/rjson"; then
    chk_fail renovate-json-valid "$RJ is not valid JSON ($(sed 's/^invalid: //' "$tmp/rjson"))" \
      "Renovate ignores a config it cannot parse, so the repo silently stops getting updates" \
      "fix the syntax; python3 -m json.tool $RJ shows where"
  elif grep -q '^noext$' "$tmp/rjson" && ! deviated renovate-extends-preset "$RJ"; then
    chk_fail renovate-extends-preset "$RJ does not extend github>Mavergreen/shipyard" \
      "the preset carries the family's automerge and ignoreTests defaults" \
      "add \"github>Mavergreen/shipyard\" to its \"extends\" list"
  fi
fi

# spec: SKILL.md "Versioning" -- a hardcoded upstream version in the build machinery fails its own
#       CI on the next Renovate bump and blocks the automerge, so build/, packaging/, the workflows
#       and CMakeLists.txt read UPSTREAM_VERSION. The match is the whole dotted version: 12.3 is not
#       found inside 112.34, ABC12.3 or 12.3.1, and v12.3 is. tests/ may name it; a test that does so reads the file.
chk_ran no-hardcoded-version
if [ "$HAVE_TRACKED" -eq 1 ] && [ -f UPSTREAM_VERSION ]; then
  _uv="$(sed -n '1{s/[[:space:]]//g;p;}' UPSTREAM_VERSION)"
  case "$_uv" in
    ''|*[!0-9A-Za-z._-]*) ;;
    *.*|?????*)
      _rx="(^|[^0-9A-Za-z.]|[vV])$(printf '%s' "$_uv" | sed 's/[.]/\\./g')([^0-9.]|\\.([^0-9]|\$)|\$)"
      grep -E '^(build/|packaging/|\.github/workflows/)|^CMakeLists\.txt$' "$TF" > "$tmp/hcfiles" || :
      while IFS= read -r f; do
        [ -f "$f" ] || continue
        _hit="$(grep -nE "$_rx" "$f" 2>/dev/null | head -1 | cut -c1-70 || true)"
        [ -n "$_hit" ] || continue
        deviated no-hardcoded-version "$f" && continue
        chk_fail no-hardcoded-version "$f names the upstream version $_uv ($_hit)" \
          "a Renovate bump changes UPSTREAM_VERSION and this file keeps the old one, failing the bump's own CI" \
          "read UPSTREAM_VERSION instead of spelling the version out"
      done < "$tmp/hcfiles" ;;
  esac
fi

# spec: SKILL.md "Release workflow", "Shared shape" -- a new repo adds no tags: trigger; tags are retired
#       as a release input and a workflow_dispatch covers every case a tag used to. Only a tags: key
#       under push: is a trigger; a dispatch input named tags is not.
chk_ran no-tags-trigger
if [ -n "$CI_FILES" ] && [ "$PY_OK" -eq 1 ]; then
  rc=0
  # shellcheck disable=SC2086  # deliberate word-split list of paths
  chk_py /dev/stdin $CI_FILES > "$tmp/tagfiles" <<'PYEOF' || rc=$?
import sys, yaml
for p in sys.argv[1:]:
    try:
        wf = yaml.safe_load(open(p))
    except Exception:
        print('@@unparseable@@\t' + p)
        continue
    on = wf.get('on', wf.get(True)) if isinstance(wf, dict) else None
    push = on.get('push') if isinstance(on, dict) else None
    if isinstance(push, dict) and ('tags' in push or 'tags-ignore' in push):
        print(p)
PYEOF
  if [ "$rc" -ne 0 ]; then
    py_crashed no-tags-trigger
  else
    while IFS= read -r f; do
      case "$f" in
        "@@unparseable@@$TAB"*)
          chk_fail no-tags-trigger "${f#*$TAB} doesn't parse as YAML, so its triggers can't be read" \
            "a workflow that cannot be read would pass as having no tags: trigger" \
            "fix ${f#*$TAB} so it parses (workflow-yaml names the place)"
          continue ;;
      esac
      deviated no-tags-trigger "$f" && continue
      chk_fail no-tags-trigger "$f has a tags: trigger" \
        "tags are retired as a release input, and a workflow_dispatch covers every case a tag used to" \
        "delete the tags: key under push:; to release from a tag's commit, run: gh workflow run release.yml --ref <ref>"
    done < "$tmp/tagfiles"
  fi
fi

# spec: SKILL.md "Release workflow" -- pull_request_target runs with the base repo's secrets on a
#       fork PR's code, and no family workflow needs it.
chk_ran no-pull-request-target
for f in $CI_FILES; do
  grep -v '^[[:space:]]*#' "$f" | grep -q 'pull_request_target' || continue
  deviated no-pull-request-target "$f" && continue
  chk_fail no-pull-request-target "$f uses pull_request_target" \
    "it would hand a fork PR this repo's secrets" \
    "use pull_request, which gets no secrets from a fork"
done

# spec: SKILL.md "Release workflow" -- the build jobs run hours of third-party build code, so a
#       checkout leaves no token on disk (persist-credentials: false) and the workflow's default
#       token reads contents only; the publishing job declares its own write.
chk_ran checkout-drops-credentials
if ! deviated checkout-drops-credentials "$REL" && [ "$PY_OK" -eq 1 ]; then
  rc=0
  chk_py /dev/stdin "$REL" > "$tmp/barecheckouts" <<'PYEOF' || rc=$?
import sys, yaml
try:
    wf = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    print('@@unparseable@@\t0')
    sys.exit(0)
jobs = wf.get('jobs') if isinstance(wf, dict) else None
for name, job in (jobs.items() if isinstance(jobs, dict) else []):
    steps = job.get('steps') if isinstance(job, dict) else None
    for i, st in enumerate(steps if isinstance(steps, list) else [], 1):
        use = st.get('uses') if isinstance(st, dict) else None
        if not (isinstance(use, str) and use.startswith('actions/checkout@')):
            continue
        w = st.get('with')
        if str(w.get('persist-credentials') if isinstance(w, dict) else None).lower() != 'false':
            print('%s\t%d' % (name, i))
PYEOF
  if [ "$rc" -ne 0 ]; then
    py_crashed checkout-drops-credentials
  else
    while IFS="$TAB" read -r _job _step; do
      if [ "$_job" = "@@unparseable@@" ]; then
        chk_fail checkout-drops-credentials "$REL doesn't parse as YAML, so its checkouts can't be read" \
          "a workflow that cannot be read would pass as having no bare checkout" \
          "fix $REL so it parses (workflow-yaml names the place)"
        continue
      fi
      chk_fail checkout-drops-credentials "$REL job $_job, step $_step is an actions/checkout without persist-credentials: false" \
        "a checkout that keeps its token leaves it readable by every later step, including third-party build code" \
        "add persist-credentials: false under with: on that actions/checkout step"
    done < "$tmp/barecheckouts"
  fi
fi

chk_ran permissions-contents-read
if ! deviated permissions-contents-read "$REL"; then
  _perm="$(grep -v '^[[:space:]]*#' "$REL" | awk '/^permissions:/ { print; p = 1; next } p && /^[^[:space:]]/ { p = 0 } p')"
  printf '%s\n' "$_perm" | grep -Eq '^  contents: read[[:space:]]*(#.*)?$|^permissions:[[:space:]]*(read-all|\{\})[[:space:]]*(#.*)?$' \
    || chk_fail permissions-contents-read "$REL has no top-level permissions: with contents: read" \
         "without it every job holds the repository default token, which can write" \
         "add a top-level permissions: block with contents: read, and give only the publishing job contents: write"
fi

# spec: SKILL.md "Versioning" -- UPSTREAM_VERSION is one bare version on one line: no leading v, no
#       spaces, no second line. What the version looks like (x.y.z, a date) is the product's.
chk_ran upstream-version-bare
if [ -f UPSTREAM_VERSION ] && ! deviated upstream-version-bare UPSTREAM_VERSION; then
  _uvn="$(grep -c '[^[:space:]]' UPSTREAM_VERSION || true)"
  _uv1="$(head -1 UPSTREAM_VERSION | tr -d '\r')"
  _bad=""
  [ "$_uvn" -eq 1 ] || _bad="it holds $_uvn non-blank lines"
  case "$_uv1" in
    v[0-9]*|V[0-9]*) _bad="${_bad:-it starts with a v}" ;;
    *[[:space:]]*) _bad="${_bad:-it has whitespace around or inside the version}" ;;
  esac
  [ -z "$_bad" ] || chk_fail upstream-version-bare "UPSTREAM_VERSION is not a bare version: $_bad" \
    "version.sh and the release tag build on it, and a v or a stray space ends up in the tag" \
    "make the file one line holding just the version, with no v and no spaces"
fi

# spec: SKILL.md "Versioning" -- /VERSION is a build product, so it is ignored as well as untracked
#       (no-tracked-version only catches it once it has been committed).
chk_ran version-ignored
grep -qxE '/?VERSION' .gitignore 2>/dev/null \
  || chk_fail version-ignored ".gitignore has no line ignoring /VERSION" \
       "VERSION is written by every build, and the first git add -A commits it" \
       "add a line '/VERSION' to .gitignore"

# spec: SKILL.md, the `bare-curl` and `brew`, `macports`, `pkgsrc`, `apt` rows of the checks table --
#       one id per package manager, plus bare-curl. Commands are matched at command position (check 18's rule, with "{", "!" and the shell's keywords added), in
#       tracked shell scripts outside tests/ and in every workflow and composite-action run: block,
#       Linux jobs included; prefixes are matched anywhere on a non-comment line of the same text. Only the fetch
#       library itself may call curl.
chk_ran bare-curl
chk_ran brew
chk_ran macports
chk_ran pkgsrc
chk_ran apt
: > "$tmp/shfiles"
if [ "$HAVE_TRACKED" -eq 1 ]; then
  chk_shell_scripts < "$TF" | grep -v '^tests/' > "$tmp/shfiles" || :
fi
: > "$tmp/pmlines"
while IFS= read -r f; do
  awk -v f="$f" '{ print f "\t" $0 }' "$f"
done < "$tmp/shfiles" >> "$tmp/pmlines"
: > "$tmp/fetchers"
printf 'scripts/mavericks_fetch.sh\nscripts/mavergreen_fetch.sh\n' >> "$tmp/fetchers"
if [ "$PY_OK" -eq 1 ]; then
  _acts="$(grep -E '^\.github/actions/[^/]+/action\.ya?ml$' "$TF" || :)"
  rc=0
  # shellcheck disable=SC2086  # deliberate word-split list of paths
  chk_py /dev/stdin $CI_FILES $_acts >> "$tmp/pmlines" <<'PYEOF' || rc=$?
import sys, yaml
for p in sys.argv[1:]:
    try:
        doc = yaml.safe_load(open(p)) or {}
    except Exception:
        print("%s\t@@unparseable@@" % p)
        continue
    if not isinstance(doc, dict):
        continue
    groups = []
    jobs = doc.get("jobs")
    if isinstance(jobs, dict):
        groups += [j.get("steps") for j in jobs.values() if isinstance(j, dict)]
    runs = doc.get("runs")
    if isinstance(runs, dict):
        groups.append(runs.get("steps"))
    for steps in groups:
        for st in (steps if isinstance(steps, list) else []):
            run = st.get("run") if isinstance(st, dict) else None
            if isinstance(run, str):
                for line in run.splitlines():
                    print("%s\t%s" % (p, line))
PYEOF
  [ "$rc" -eq 0 ] || py_crashed bare-curl
fi
pmhits="$tmp/pmhits"
while IFS="$TAB" read -r f _; do
  [ -n "$f" ] || continue
  chk_fail bare-curl "$f doesn't parse as YAML, so its run: blocks can't be scanned" \
    "an unreadable workflow would pass as using no curl and no outside package manager" \
    "fix $f so it parses (workflow-yaml names the place)"
done <<EOF2
$(grep "$TAB@@unparseable@@\$" "$tmp/pmlines" || :)
EOF2
awk -F"$TAB" '
  NR == FNR { fetcher[$0] = 1; next }
  {
    p = $1; l = $0; sub(/^[^\t]*\t/, "", l)
    t = l; sub(/^[[:space:]]+/, "", t)
    if (t == "" || substr(t, 1, 1) == "#") next
    cp = "(^|[;&|`{!]|[$][(]|[[:space:]](then|do|exec|if|elif|while|until|else)|^(then|do|exec|if|elif|while|until|else))[[:space:]]*((sudo|env|command|time)[[:space:]]+)*"
    if (!(p in fetcher) && l ~ (cp "curl([[:space:]]|$)")) hit("bare-curl")
    if (l ~ (cp "brew([[:space:]]|$)") || l ~ /(\/opt\/homebrew|\/usr\/local\/Homebrew|\/home\/linuxbrew)([^A-Za-z0-9_]|$)/) hit("brew")
    if (l ~ (cp "port([[:space:]]|$)") || l ~ /\/opt\/local([^A-Za-z0-9_-]|$)/) hit("macports")
    if (l ~ (cp "(pkgin|pkg_add|bmake)([[:space:]]|$)") || l ~ /(\/opt\/pkg|\/usr\/pkg)([^A-Za-z0-9_-]|$)/) hit("pkgsrc")
    if (l ~ (cp "(apt-get|apt|dpkg[[:space:]]+-i)([[:space:]]|$)")) hit("apt")
  }
  function hit(id) { if (!seen[id SUBSEP p]++) print id "\t" p "\t" l }
' "$tmp/fetchers" "$tmp/pmlines" > "$pmhits" \
  || chk_fail bare-curl "the package-manager scan could not read shell lines (awk failed)" \
       "an empty hit list would read as no outside package manager anywhere" \
       "run \`command -v awk\` ($(command -v awk || echo none)) and make sure it is a working awk"
while IFS="$TAB" read -r _id f line; do
  deviated "$_id" "$f" && continue
  _l="$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-70)"
  case "$_id" in
    bare-curl)
      chk_fail bare-curl "$f runs curl directly: $_l" \
        "a bare curl does not retry a transient failure, and one connection reset cost a two-hour rerun" \
        "use mav_curl (QUEUE #58), or declare '- bare-curl:$f: <reason>. Revisit when <exit>.' under ## Conformance deviations" ;;
    *)
      case "$_id" in
        brew) _mgr="Homebrew, Linuxbrew or Tigerbrew" ;;
        macports) _mgr="MacPorts" ;;
        pkgsrc) _mgr="pkgsrc" ;;
        apt) _mgr="apt" ;;
      esac
      chk_fail "$_id" "$f uses $_mgr: $_l" \
        "the family works toward no outside package manager, and each use is counted as a declared deviation" \
        "replace it with the family product or facility that supplies the tool, or declare '- $_id:$f: <reason>. Revisit when <exit>.' under ## Conformance deviations" ;;
  esac
done < "$pmhits"

# spec: SKILL.md, the `vendored` row of the checks table -- a vendored copy is
#       counted: any tracked path under a directory named vendor/ or third_party/ needs a `vendored`
#       deviation covering it, one failure per vendored entry. shipyard's own fixtures are excluded
#       like every other check's.
chk_ran vendored
if [ "$HAVE_TRACKED" -eq 1 ]; then
  grep -E '(^|/)(vendor|third_party)/' "$TF" | grep -v '^tests/fixtures/checks/' > "$tmp/vendored" || :
  : > "$tmp/vendored-seen"
  while IFS= read -r f; do
    deviated vendored "$f" && continue
    _g="$(printf '%s\n' "$f" | sed -E 's#^(.*(^|/)(vendor|third_party)/[^/]+).*$#\1#')"
    grep -qxF -- "$_g" "$tmp/vendored-seen" && continue
    printf '%s\n' "$_g" >> "$tmp/vendored-seen"
    _scope="$_g/**"; [ "$_g" != "$f" ] || _scope="$f"
    chk_fail vendored "$f is tracked under a vendor/ or third_party/ directory with no vendored deviation" \
      "a vendored copy is code the family does not build, and each one is counted until it is deleted" \
      "declare '- vendored:$_scope: <reason>. Revisit when <exit>.' under ## Conformance deviations, naming the condition that deletes the copy"
  done < "$tmp/vendored"
fi

[ "$chk_status" -eq 0 ] && echo "check-family-conventions: ok"

exit "$chk_status"
