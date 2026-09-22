#!/bin/sh
#   usage: check-family-conventions.sh
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md, "Family
#       conventions (checked, not just written down)" -- the why and history for every check below
#       lives there; each check's fail() message carries the actionable summary.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"   # siblings live here (.shipyard/scripts in a consumer)
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

status=0
fail() { echo "check-family-conventions: $1" >&2; echo "    fix: $2" >&2; status=1; }

# spec: SKILL.md "Family conventions" check 1 -- release.yml must declare concurrency:; two publishes
#       racing the same tag is a corrupt release, not a flaky build.
grep -q '^concurrency:' "$REL" \
  || fail "$REL declares no concurrency: — two publishes can race the same tag" \
          "add a concurrency: block -- group keyed on github.run_id, cancel-in-progress naming pull_request"

# spec: SKILL.md "Family conventions" check 1b -- a run that CAN PUBLISH must be alone in its
#       concurrency group and cancellable by nothing. cancel-in-progress: false protects only the
#       EXECUTING run, not a QUEUED one; the old shared-group shape discarded a mavericks-golang
#       release silently, 13 seconds after the run that evicted it (2026-09-09).
CONC="$(awk '/^concurrency:/{f=1;next} /^[^[:space:]#]/{f=0} f' "$REL")"
GROUP="$(printf '%s\n' "$CONC" | awk '/^[[:space:]]*group:/{f=1;print;next} /^[[:space:]]*cancel-in-progress:/{f=0} f')"
CANCEL="$(printf '%s\n' "$CONC" | awk '/^[[:space:]]*cancel-in-progress:/{f=1;print;next} /^[[:space:]]*group:/{f=0} f')"

printf '%s\n' "$GROUP" | grep -q 'github\.run_id' \
  || fail "$REL concurrency group is shared between runs that can publish — a queued one is evicted by the next arrival and its release silently never happens" \
          "key the group per run: group: release-\${{ github.event_name == 'pull_request' && github.ref || github.run_id }}"

printf '%s\n' "$CANCEL" | grep -q 'pull_request' \
  || fail "$REL can cancel a run that publishes — cancel-in-progress must name pull_request, the only event that may supersede" \
          "cancel-in-progress: \${{ github.event_name == 'pull_request' }}"

# spec: SKILL.md "Family conventions" check 2 -- test files that exist must be run by something; hand
#       enumeration is how a suite quietly stops running.
if [ -d tests ] && [ -n "$(ls tests/*.sh tests/*.bats 2>/dev/null || true)" ]; then
  ci_mentions 'run-repo-tests' || ci_mentions 'ctest' \
    || fail "tests/ has test files but no workflow runs them" \
            "add: sh \"\$SHIPYARD_SCRIPTS/run-repo-tests.sh\"   (or ctest, where that is the driver)"
fi

# spec: SKILL.md "Family conventions" check 3 -- INGREDIENTS.md must exist.
[ -f INGREDIENTS.md ] \
  || fail "no INGREDIENTS.md — the repo's build inputs are undocumented" \
          "list each input, where it is pinned, its Renovate status, and what a bump does"

# spec: SKILL.md "Family conventions" check 4 -- no Renovate key may restate a value the shared
#       preset already sets; the SAME key with a DIFFERENT value stays a legal override.
if [ -f .github/renovate.json ]; then
  for pair in 'ignoreTests:false'; do
    k="${pair%%:*}"; presetval="${pair#*:}"
    grep -q "\"$k\"[[:space:]]*:[[:space:]]*$presetval" .github/renovate.json \
      && fail "renovate.json sets \"$k\": $presetval, which is exactly what the shared preset sets" \
              "delete the key (the preset owns it); keep it only to override with a different value"
  done
fi

# spec: SKILL.md "Family conventions" check 4b -- an automerge exception must carry a description
#       saying why a green build isn't enough (BUILD FINE AND BE WRONG); unexplained, it reads as
#       drift, not a decision.
if [ -f .github/renovate.json ]; then
  python3 - .github/renovate.json <<'PY' || status=1
import json, sys
bad = []
for r in json.load(open(sys.argv[1])).get('packageRules', []):
    if 'automerge' in r and not (r.get('description') or '').strip():
        bad.append(r.get('matchDepNames') or r.get('matchPackageNames') or '(unnamed rule)')
if bad:
    print("check-family-conventions: automerge exception with no description: %s" % bad, file=sys.stderr)
    print("    fix: say why a green build is not enough here (what would build fine and be wrong),", file=sys.stderr)
    print("         or drop the rule and take the family default (ship-if-green)", file=sys.stderr)
    sys.exit(1)
PY
fi

# spec: SKILL.md "Family conventions" check 5 (weak form) -- some notes must reach the release;
#       superseded for WIRING by check 14 below. --notes-file also matches a Sparkle appcast call, so
#       this is weaker than it reads for a repo that hasn't adopted the shared publisher.
ci_mentions 'publish-release.yml' || ci_mentions '--notes-file' || ci_mentions 'body_path' \
  || ci_mentions '--generate-notes' \
  || fail "the release publishes no notes body" \
          "publish via publish-release.yml@v1, or pass --notes-file / body_path when creating the release"

# spec: SKILL.md "Family conventions" check 7 -- VERSION is a build product, never committed (an
#       untracked one in the tree is fine); something must also be able to SUPPLY the upstream
#       version (a committed UPSTREAM_VERSION, or a derive script).
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git ls-files --error-unmatch VERSION >/dev/null 2>&1; then
    fail "VERSION is committed — it is a build product, and the committed copy goes stale while tags move on" \
         "git rm --cached VERSION; add /VERSION to .gitignore; commit UPSTREAM_VERSION instead"
  fi
else
  echo "check-family-conventions: not a git checkout — cannot check whether VERSION is committed" >&2
  status=1
fi

if [ ! -f UPSTREAM_VERSION ] \
   && [ -z "$(ls build/derive-upstream-version.sh scripts/derive-upstream-version.sh 2>/dev/null || true)" ]; then
  fail "no UPSTREAM_VERSION and nothing to derive one — the version cannot be computed" \
       "commit UPSTREAM_VERSION (bare x.y.z or a date), or add build/derive-upstream-version.sh"
fi

# spec: SKILL.md "Family conventions" check 7b -- lines/ is the RETIRED per-line directory shape
#       (golang, nodejs and clang all migrated to one repo per line, 2026-09-22); a reappearing
#       TRACKED lines/ means the retired shape crept back into a repo. TRACKED, the same rule
#       checks 7/17 apply above: on this family's NFS checkouts, an ignored AppleDouble `._*` file
#       (lines/._126, lines/126/._patches) survives a migrating repo's `git pull` past the point
#       git deletes the tracked files, leaving an untracked `lines/` directory on disk that must
#       not fail a migrated checkout. Outside a git checkout this looks at nothing — check 7 above
#       already fails the whole run ("not a git checkout") when that happens.
if git rev-parse --git-dir >/dev/null 2>&1; then
  # platform: the trailing slash on the pathspec matters -- `-- lines` (no slash) also matches a
  #           tracked plain FILE literally named "lines", which is not the retired directory shape
  #           this check exists to catch; `-- lines/` matches only paths INSIDE a lines/ directory.
  if [ -n "$(git ls-files -- lines/ | head -1)" ]; then
    fail "lines/ exists — that per-line directory shape is retired; each upstream line is its own repo now" \
         "move this line's UPSTREAM_VERSION and patches/ to the repo root (see SKILL.md \"Multiple upstream lines\"); a NEW line belongs in a NEW repo, never a new lines/<id>/ here"
  fi
fi

# spec: SKILL.md "Family conventions" check 7c -- build/version.sh (and its wrapper siblings) must
#       not be git-ignored; a too-broad pattern drops them silently and only CI's fresh checkout fails.
if git rev-parse --git-dir >/dev/null 2>&1; then
  if ci_mentions 'build/version.sh' || [ -e build/version.sh ]; then
    if git check-ignore -q build/version.sh 2>/dev/null; then
      fail "build/version.sh is git-ignored — a too-broad .gitignore pattern (e.g. build*/) drops the committed version wrappers; local passes, CI's fresh checkout fails 'no build/version.sh'" \
           "ignore only build OUTPUT dirs (/_build/, build-*/, build/work/) — never build/ itself"
    fi
  fi
fi

# spec: SKILL.md "Family conventions" check 7d -- every build output dir the repo writes must be
#       git-ignored; mirrors check 7c. tailscale's untracked, unignored build/updater is the incident
#       that motivated it. tests/check-family-conventions-test.sh covers the detection edge cases.
if git rev-parse --git-dir >/dev/null 2>&1; then
  # platform: BSD sed aborts on binary content ("RE error: illegal byte sequence"), which a find(1)
  #           sweep would hit via NFS AppleDouble ._*.sh files -- git ls-files reads only tracked
  #           content, so this reads git ls-files instead.
  bdirs="$(
    {
      [ -n "$CI_FILES" ] && cat $CI_FILES 2>/dev/null
      git ls-files -z '*.sh' 2>/dev/null | xargs -0 cat 2>/dev/null
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
    fail "$d is a build output directory this repo writes, but .gitignore does not cover it — one \`git add -A\` commits the build tree, and a stale CMakeCache keeps resolving a package that has been renamed away" \
         "add $d/ to .gitignore (any pattern that covers it; the family does not share one spelling)"
  done
fi

# spec: SKILL.md "Family conventions" check 8 -- every workflow must PARSE with duplicate keys
#       rejected; GitHub silently refuses to run a workflow with one, so nothing else in CI can catch
#       it. Cannot-verify (no PyYAML) still FAILS -- SKILL.md "Cannot-verify is a FAILURE, never a
#       pass."
if [ -n "$CI_FILES" ] && command -v python3 >/dev/null 2>&1; then
  # platform: GitHub's macOS runner python3 ships without PyYAML.
  if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    fail "python3 has no PyYAML — cannot verify that the workflows parse, so a duplicate key would ship unseen" \
         "install it (python3 -m pip install pyyaml); shipyard's .github/actions/install does this for CI"
  else
  # shellcheck disable=SC2086  # deliberate word-split list of paths
  python3 - $CI_FILES <<'PYEOF' || status=1
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

rc = 0
for path in sys.argv[1:]:
    try:
        with open(path) as fh:
            yaml.load(fh, Strict)
    except Exception as exc:
        sys.stderr.write("check-family-conventions: %s does not parse: %s\n" % (path, exc))
        sys.stderr.write("    fix: GitHub rejects the whole workflow -- it never runs, so no other gate sees this\n")
        rc = 1
sys.exit(rc)
PYEOF
  fi
fi

# spec: SKILL.md "Family conventions" check 9 -- every ❌ ingredient row must say "untrackable" or
#       wire a Renovate manager; a bare ❌ reads as an oversight, not a decision.
if [ -f INGREDIENTS.md ]; then
  while IFS= read -r line; do
    case "$line" in
      *❌*)
        case "$line" in
          *[Uu]ntrackable*) : ;;   # declared, with a reason nearby
          *) fail "INGREDIENTS.md marks an ingredient as not auto-updating: $(printf '%s' "$line" | cut -c1-60)..." \
                  "wire a Renovate customManager for it (a pinned hash that blocks the bot can verify against upstream's published SHA256SUMS instead), or mark it **untrackable** and say why" ;;
        esac
        ;;
    esac
  done < INGREDIENTS.md
fi

# spec: SKILL.md "Family conventions" check 10 -- no shell construct the 10.9 base system lacks;
#       invisible to CI by construction, since the runner that would catch it is never used.
#       Delegates to check-shell-portability.sh so the family's rule and shipyard's own test suite
#       cannot drift apart.
if [ -f "$SELF/check-shell-portability.sh" ]; then
  sh "$SELF/check-shell-portability.sh" >/dev/null || status=1
else
  fail "cannot find check-shell-portability.sh next to this gate — the shipyard checkout is incomplete" \
       "check out the whole repo (family-conventions.yml does), not just this one script"
fi

# spec: SKILL.md "Family conventions" check 11 -- a release shipping a new upstream must link
#       upstream's own notes: a committed build/ or scripts/upstream-release-notes-url.sh, or
#       INGREDIENTS.md saying why there is nothing to link.
hook_tracked=no; hook_present=no
for d in build scripts; do
  if git ls-files --error-unmatch "$d/upstream-release-notes-url.sh" >/dev/null 2>&1; then hook_tracked=yes; fi
  if [ -f "$d/upstream-release-notes-url.sh" ]; then hook_present=yes; fi
done
if [ "$hook_tracked" = no ] && ! grep -q 'No upstream release notes: *[^ ]' INGREDIENTS.md 2>/dev/null; then
  if [ "$hook_present" = yes ]; then
    fail "upstream-release-notes-url.sh exists but is not committed — a .gitignore'd build/ drops it silently, and CI's fresh checkout never sees it" \
         "git add -f it (and ignore only build OUTPUT dirs, never build/ itself)"
  else
    fail "a release shipping a new upstream cannot link upstream's notes: no committed build/upstream-release-notes-url.sh, and INGREDIENTS.md does not say why" \
         "add the hook (usually one printf -- see the conventions skill, 'A new upstream links upstream's own notes'), or a line 'No upstream release notes: <reason>' in INGREDIENTS.md"
  fi
fi

# spec: SKILL.md "Family conventions" check 12 -- a workflow that signs must also call
#       scan-for-key.yml; publish-release.yml refuses a signed release with no scan record.
if ci_mentions 'sign_and_appcast'; then
  ci_mentions 'scan-for-key.yml' \
    || fail "a workflow signs (sign_and_appcast.sh) but none calls scan-for-key.yml — publish-release.yml refuses a signed release with no scan record" \
            "add a scan job between the signing job and publish, under always() (the snippet is at the top of shipyard's scan-for-key.yml), and make publish need it"
fi

# spec: SKILL.md "Family conventions" check 13 -- a Renovate manager whose captured pin ends in
#       -mavericks.N needs regex versioning that compares N; default versioning coerces it away and
#       every repackage compares equal (swift-runtime missed three releases this way).
if [ -f .github/renovate.json ] && git rev-parse --git-dir >/dev/null 2>&1; then
  python3 - .github/renovate.json <<'PY' || status=1
import fnmatch, json, re, subprocess, sys
def js(rx):  # Renovate regexes are JS: (?<name>...) is Python's (?P<name>...); lookbehinds stay as they are
    return re.sub(r'\(\?<(?![=!])', '(?P<', rx)
def matcher(pat):
    m = re.fullmatch(r'/(.*)/([a-z]*)', pat)
    if m:
        rx = re.compile(js(m.group(1)), re.I if 'i' in m.group(2) else 0)
        return lambda f: rx.search(f) is not None
    return lambda f: fnmatch.fnmatch(f, pat)
# What Renovate sees is what is committed (the heredoc is this script's stdin, so git is asked here)
files = [f for f in subprocess.run(['git', 'ls-files', '-z'], capture_output=True, text=True,
                                   check=True).stdout.split('\0') if f]
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
if bad:
    for b in bad:
        print("check-family-conventions: Renovate cannot see new -mavericks.N releases of %s -- its versioning does not compare N, so every -mavericks.N of one upstream compares equal" % b, file=sys.stderr)
    print('    fix: give that manager "versioningTemplate": "regex:^(?<major>\\\\d+)\\\\.(?<minor>\\\\d+)\\\\.(?<patch>\\\\d+)-mavericks\\\\.(?<build>\\\\d+)$"', file=sys.stderr)
    sys.exit(1)
PY
fi

# spec: SKILL.md "Family conventions" check 14 -- the release body must come from the shared
#       generator (release-notes.sh), never hand-written, never GitHub's --generate-notes; the appcast
#       and the Release page must read the same file. Check 5 above is the weak form this supersedes
#       for wiring. tests/check-family-conventions-test.sh covers the detection edge cases (quoting,
#       line continuations, variable-routed paths).
if [ -n "$CI_FILES" ]; then
  ci_mentions '[/ ]release-notes\.sh' \
    || fail "no workflow builds the release body with the shared generator (release-notes.sh)" \
            "call \$SHIPYARD_SCRIPTS/release-notes.sh --tag/--version/--product --out dist/RELEASE_NOTES.md"

  if ci_mentions '>[[:space:]]*[^ ]*RELEASE_NOTES\.md' \
     || ci_mentions '[[:space:]]cp[[:space:]][^;&|]*[[:space:]][^ ;&|]*RELEASE_NOTES\.md'; then
    fail "a workflow hand-writes the release body into RELEASE_NOTES.md" \
         "delete it -- release-notes.sh --out <path> is the only thing that writes that file"
  fi

  if ci_mentions '--generate-notes'; then
    fail "a workflow publishes GitHub's autogenerated notes (--generate-notes)" \
         "build the body with release-notes.sh; --generate-notes cannot say which ingredient moved"
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
      || fail "a workflow reads a notes file the generator does not write: --notes-file $n" \
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
if [ -f "$SELF/check-comments.sh" ]; then
  deviation=""; devscope=""
  if [ -f INGREDIENTS.md ]; then
    devscope="$(sed -n '/^## Conformance deviations/,/^## /p' INGREDIENTS.md \
      | sed -n 's/^- *comments *:\([^ :][^ :]*\).*$/\1/p' | head -1)"
    deviation="$(sed -n '/^## Conformance deviations/,/^## /p' INGREDIENTS.md \
      | sed -n 's/^- *comments *: *\(..*\)$/\1/p' | head -1)"
  fi
  if [ -n "$devscope" ]; then
    fail "INGREDIENTS.md scopes the comments deviation to \"$devscope\", but check 15's deviation is repo-wide and a glob is not honoured here" \
         "write \"- comments: <reason>\" (a space after the colon) and accept that it switches comment checking off for the whole repo, or drop the deviation and tag the comments"
  elif [ -n "$deviation" ]; then
    echo "check-family-conventions: comments: DECLARED DEVIATION -- $deviation"
  else
    sh "$SELF/check-comments.sh" \
      || fail "a comment cites no reason (see the lines named above)" \
              "cite one: # platform: <a fact about the platform or a tool>, or # spec: <a locatable pointer>"
  fi
else
  fail "cannot find check-comments.sh next to this gate -- the shipyard checkout is incomplete" \
       "check out the whole repo (family-conventions.yml does), not just this one script"
fi

# spec: scripts/deviations.sh -- ONE parser for the "## Conformance deviations" grammar, shared with
#       check-artifact-conformance.sh, so a declared exception cannot mean two things.
if ! DEVS="$(sh "$SELF/deviations.sh" .)"; then
  fail "INGREDIENTS.md declares a conformance deviation with no reason" "give every '- <check>[:<glob>]:' entry its reason on the same line"
fi
deviated() {  # $1 = check name, $2 = path: 0 if a declared deviation covers it
  printf '%s\n' "$DEVS" | { while read -r c g _; do
    [ "$c" = "$1" ] || continue
    # shellcheck disable=SC2254  # $g is a glob on purpose
    case "$2" in $g) exit 0;; esac
  done; exit 1; }
}

# spec: SKILL.md "Family conventions" check 16 -- nothing tracked may read the CMake user package
#       registry. tests/ is excluded for the same reason check 18 excludes it: a test that asserts the
#       registry is GONE has to name it, and a sweep that cannot tell an assertion from a usage would
#       report that proof as the violation. What a repo SHIPS is what is checked, so a COMMENT naming
#       the registry is prose, not a read. This check's own fail message may not spell the full path
#       either, or the gate matches itself -- a first draft reported shipyard as the family's worst
#       offender that way.
for f in $(git ls-files -- '*.sh' '*.yml' '*.yaml' '*.cmake' 'CMakeLists.txt' '*.bats' 2>/dev/null | grep -v '^tests/'); do
  # platform: the pattern must not be a literal occurrence of itself, or this gate is its own first
  #           offender. "package[s]" is the `ps | grep [f]oo` idiom; the bracket changes nothing about
  #           what it matches.
  grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -q '\.cmake/package[s]' || continue
  deviated registry-read "$f" && continue
  fail "$f reads the CMake user package registry (the ~/.cmake export(PACKAGE) tree), which nothing writes any more" \
       "source msc.sh (it asks shipyard-cmake and exports SHIPYARD_SCRIPTS), or use \$SHIPYARD_SCRIPTS in CI"
done

# spec: SKILL.md "Family conventions" check 17 -- a product's msc.sh must equal shipyard's canonical
#       template byte for byte. TRACKED copies only, the same rule checks 7c/7d apply: an untracked
#       build/msc.sh in a developer's worktree is not what the repo ships, and failing on it would
#       make the gate unrunnable for exactly the person mid-way through fixing it.
_tmpl="$SELF/templates/msc.sh"
if [ ! -f "$_tmpl" ]; then
  # platform: `cmp -s` with a missing operand is "different", so comparing against a template that
  #           MOVED would tell all fifteen repos at once that their msc.sh is not canonical, with the
  #           one true cause nowhere in the message. Name the template instead.
  fail "cannot find shipyard's canonical msc.sh at $_tmpl — the shipyard checkout is incomplete, or the template moved" \
       "check out the whole repo (family-conventions.yml does); if the template moved, this check must move with it"
else
  for f in build/msc.sh msc.sh; do
    git ls-files --error-unmatch "$f" >/dev/null 2>&1 || continue
    deviated msc-template "$f" && continue
    cmp -s "$f" "$_tmpl" && continue
    # platform: a literal newline in a BSD sed replacement is an error, so the newline lives in the
    #           printf format string and sed only adds the indent.
    _diff="$(diff "$_tmpl" "$f" 2>/dev/null | head -6 | sed 's/^/    /')"
    fail "$(printf '%s is not shipyard'\''s canonical msc.sh\n%s' "$f" "$_diff")" \
         "copy it from shipyard: cp \"\$SHIPYARD_SCRIPTS/templates/msc.sh\" $f   (never edit your copy -- change the template)"
  done
fi

# spec: SKILL.md "Family conventions" check 18 -- configure, test and package with shipyard-cmake /
#       shipyard-ctest / shipyard-cpack. It reads lines, not shell syntax; SKILL.md's "Check 18" notes
#       state the deliberate blind spot (a bare "(" before the command), the shapes that still count
#       as a call inside quotes and heredocs, and the known false negatives. Every one of them is
#       pinned by tests/check-family-conventions-test.sh, so the list cannot quietly go stale.
cmdlist="$(mktemp "${TMPDIR:-/tmp}/conventions-cmds.XXXXXX")"
TAB="$(printf '\t')"
{
  if [ -n "$CI_FILES" ] && python3 -c 'import yaml' >/dev/null 2>&1; then
    # shellcheck disable=SC2086  # deliberate word-split list of paths
    python3 - $CI_FILES <<'PYEOF'
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
  fi
  for f in $(git ls-files -- '*.sh' 2>/dev/null | grep -v '^tests/'); do
    sed "s|^|$f$TAB|" "$f"
  done
} > "$cmdlist"
while IFS="$TAB" read -r f line; do
  case "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')" in '#'*|'') continue;; esac
  # spec: SKILL.md "Check 18" -- command position is line start, a separator (; & | or a backtick),
  #       "$(", or then/do/exec. A bare "(" is deliberately NOT command position: a whole-org survey
  #       found three compliant repos whose only hit was `... || { echo "not built (cmake --build
  #       <dir>)"; }`. A `(cd x && cmake ...)` still matches, on the "&".
  printf '%s\n' "$line" | grep -Eq '(^|[;&|`]|[$]\(|[[:space:]]then|[[:space:]]do|[[:space:]]exec|^then|^do|^exec)[[:space:]]*(cmake|ctest|cpack)([[:space:]]|$)' || continue
  deviated shipyard-cmake-only "$f" && continue
  fail "$f runs plain cmake/ctest/cpack: $(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-70)" \
       "use shipyard-cmake / shipyard-ctest / shipyard-cpack -- MavericksShipyardConfig.cmake refuses any other cmake"
done < "$cmdlist"
rm -f "$cmdlist"

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
if [ -n "$CI_FILES" ]; then
  ci_mentions '/assert-tree-clean\.sh"*[[:space:]]*--record' \
    || fail "no workflow records the source tree before the build -- assert-tree-clean.sh --record is never called" \
            "call \$SHIPYARD_SCRIPTS/assert-tree-clean.sh --record before the build; the bare call has nothing to compare against without it"
  ci_mentions '/assert-tree-clean\.sh"*[[:space:]]*$' \
    || fail "no workflow asserts that the build wrote nothing into the source tree" \
            "call \$SHIPYARD_SCRIPTS/assert-tree-clean.sh after the build; --record on its own returns 0 unconditionally and can never fail"
fi

# spec: SKILL.md "Family conventions" check 21 -- a repo that builds a .pkg must run artifact
#       conformance, or nothing checks what its pkg installs: the identity and install-path rules
#       ("Identity and install paths") live in check-artifact-conformance.sh, and a product that
#       never calls it is exempt from all of them by omission. Tests are excluded: fixtures build
#       throwaway pkgs on purpose.
builds_pkg=""
for f in $(git ls-files -- '*.sh' '*.yml' '*.yaml' '*.cmake' 'CMakeLists.txt' 2>/dev/null | grep -v '^tests/'); do
  grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -qE '(^|[^A-Za-z0-9_-])(pkgbuild|productbuild)([[:space:]]|$)' && { builds_pkg="$f"; break; }
done
[ -n "$builds_pkg" ] || ! ci_mentions 'sign_and_appcast' || builds_pkg="a signing workflow"
if [ -n "$builds_pkg" ] && ! ci_mentions 'check-artifact-conformance\.sh' && ! deviated artifact-conformance "$REL"; then
  fail "this repo builds a .pkg ($builds_pkg) but no workflow runs check-artifact-conformance.sh -- nothing checks what it installs or under which identity" \
       "pipe artifact-facts.sh into check-artifact-conformance.sh at package time (see the conventions skill, 'Artifact conformance'), or declare '- artifact-conformance: <reason>' under INGREDIENTS.md's ## Conformance deviations"
fi

# spec: SKILL.md "Family conventions" check 20 -- CMakeUserPresets.json is the per-developer
#       build-location override. A preset's own `environment` block is applied AFTER the real
#       process environment, so exporting MAVERICKS_BUILD_ROOT cannot redirect a --preset
#       build and this file is the only thing that can. It must be gitignored, or it pollutes
#       git status and gets committed by accident. Keyed on a COMMITTED CMakePresets.json: a
#       repo with no presets has no override channel to protect.
if [ -f CMakePresets.json ] && git ls-files --error-unmatch CMakePresets.json >/dev/null 2>&1; then
  git check-ignore -q CMakeUserPresets.json 2>/dev/null \
    || fail "CMakeUserPresets.json is not gitignored, and it is the per-developer build-location override" \
            "add CMakeUserPresets.json to .gitignore"
fi

[ "$status" -eq 0 ] && echo "check-family-conventions: ok"

exit "$status"
