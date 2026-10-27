#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
python3 -m json.tool default.json >/dev/null || { echo "invalid JSON in default.json"; exit 1; }
python3 - default.json <<'PY'
import json, re, sys
c = json.load(open(sys.argv[1]))
cms = c.get("customManagers", [])
m = [x for x in cms if x.get("depNameTemplate") == "mavericks-legacysupport"]
assert m, "no mavericks-legacysupport customManager"
m = m[0]
assert m["datasourceTemplate"] == "github-releases", "wrong datasource"
assert m["packageNameTemplate"] == "Mavergreen/macports-legacy-support", "wrong packageName"
assert "extractVersionTemplate" not in m, "the fork tags releases bare (1.5.2-mavericks.N), so the tag is the version; an optional v? also leaves release notes unable to name the tag"

# no Python (?P<...>) syntax anywhere in the manager -- Renovate uses (?<...>)
assert "(?P<" not in json.dumps(m), "manager must use Renovate (?<name>...) syntax, not Python (?P<name>...)"

# The patterns must be anchored regexes (NOT bare globs). Renovate renamed fileMatch ->
# managerFilePatterns and wraps each pattern as a regex literal (/.../); this assertion still said
# fileMatch long after the preset moved on, and nothing ran it to notice.
fm = m["managerFilePatterns"]
assert "/(^|/)versions\\.sh$/" in fm, "managerFilePatterns must contain the anchored /(^|/)versions\\.sh$/ regex, not a glob"

# matchStrings must name-capture via Renovate syntax and, semantically, capture the version
pat = m["matchStrings"][0]
assert "(?<currentValue>" in pat, "matchStrings must capture currentValue via Renovate (?<...>) syntax"
assert m["versioningTemplate"].startswith("regex:"), "versioningTemplate must be a regex: scheme"
py_pat = re.sub(r'\(\?<(?![=!])', '(?P<', pat)   # translate for a Python-side capture check
mm = re.search(py_pat, 'export MLS_VERSION=1.5.2-mavericks.1   # mavericks-legacysupport')
assert mm and mm.group("currentValue") == "1.5.2-mavericks.1", "marker regex must capture the version"
# The legacysupport manager must not claim a Recaulk release.
vt = m["versioningTemplate"][len("regex:"):]
py_vt = re.sub(r'\(\?<(?![=!])', '(?P<', vt)
assert not re.match(py_vt, "20261006.1"), "a Recaulk release must never read as a legacysupport version: consumers still pinned to macports-legacy-support would be bumped onto a different product"

rc = [x for x in cms if x.get("managerFilePatterns") == ["/^components/recaulk/version$/"]]
assert len(rc) == 1, "consumers track components/recaulk/version through this one shared manager (contract), never a repo-local one"
rc = rc[0]
assert rc["matchStrings"] == ["^(?<currentValue>\\S+)\\s*$"], "consumers track components/recaulk/version through this one shared manager (contract), never a repo-local one"
assert rc["depNameTemplate"] == "recaulk" and rc["packageNameTemplate"] == "Mavergreen/recaulk", "consumers track components/recaulk/version through this one shared manager (contract), never a repo-local one"
assert rc["datasourceTemplate"] == "github-releases", "consumers track components/recaulk/version through this one shared manager (contract), never a repo-local one"
assert rc["versioningTemplate"] == "regex:^(?<major>\\d{8})\\.(?<minor>\\d+)$", "consumers track components/recaulk/version through this one shared manager (contract), never a repo-local one"
rv = re.sub(r'\(\?<(?![=!])', '(?P<', rc["versioningTemplate"][len("regex:"):])
assert re.match(rv, "20261005.1"), "the recaulk versioning regex must match 20261005.1"
assert not re.match(rv, "1.5.2-mavericks.6"), "the recaulk versioning regex must not match 1.5.2-mavericks.6"
import fnmatch
gr = [x for x in c.get("packageRules", []) if x.get("groupName") == "Mavergreen ingredients"]
assert len(gr) == 1, "one packageRule must group every Mavergreen update under groupName 'Mavergreen ingredients'"
gr = gr[0]
assert gr["matchPackageNames"] == ["Mavergreen/**", "!Mavergreen/shipyard", "!Mavergreen/mavericks-vm"], "the group rule must match Mavergreen/** minus the shipyard and mavericks-vm workflow actions"
def glob_match(pattern, name):
    return re.match("^" + re.escape(pattern).replace(r"\*\*", ".*").replace(r"\*", "[^/]*") + "$", name) is not None
def grouped(name):
    pats = gr["matchPackageNames"]
    if any(glob_match(p[1:], name) for p in pats if p.startswith("!")):
        return False
    return any(glob_match(p, name) for p in pats if not p.startswith("!"))
assert grouped("Mavergreen/recaulk"), "the group rule must match Mavergreen/recaulk"
assert grouped("Mavergreen/clang-22"), "the group rule must match Mavergreen/clang-22"
assert not grouped("madler/zlib"), "the group rule must not match madler/zlib"
assert not grouped("Mavergreen/shipyard"), "the shipyard workflow action must not be grouped with ingredients"
assert not grouped("Mavergreen/mavericks-vm"), "the mavericks-vm workflow action must not be grouped with ingredients"
assert "holds the whole" in " ".join(c["description"]), "the exception guidance must say an automerge:false exception holds the whole group"
assert c.get("vulnerabilityAlerts", {}).get("labels") == ["security"], "security updates must carry the security label so they can skip the queue"
print("renovate-preset OK")
PY
