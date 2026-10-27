#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
python3 -m json.tool default.json >/dev/null || { echo "invalid JSON in default.json"; exit 1; }
python3 - default.json <<'PY'
import json, re, sys
c = json.load(open(sys.argv[1]))
cms = c.get("customManagers", [])
assert "mavericks-legacysupport" not in json.dumps(c) and "macports-legacy-support" not in json.dumps(c), "no repo pins macports-legacy-support any more; the preset must not track it"
assert "(?P<" not in json.dumps(cms), "managers must use Renovate (?<name>...) syntax, not Python (?P<name>...)"

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
assert gr.get("separateMajorMinor") is False, "the group rule must set separateMajorMinor false: every date-versioned bump is a major, and Renovate would split those out of the one grouped PR"
assert grouped("Mavergreen/recaulk"), "the group rule must match Mavergreen/recaulk"
assert grouped("Mavergreen/clang-22"), "the group rule must match Mavergreen/clang-22"
assert not grouped("madler/zlib"), "the group rule must not match madler/zlib"
assert not grouped("Mavergreen/shipyard"), "the shipyard workflow action must not be grouped with ingredients"
assert not grouped("Mavergreen/mavericks-vm"), "the mavericks-vm workflow action must not be grouped with ingredients"
assert "holds the whole" in " ".join(c["description"]), "the exception guidance must say an automerge:false exception holds the whole group"
assert c.get("vulnerabilityAlerts", {}).get("labels") == ["security"], "security updates must carry the security label so they can skip the queue"
print("renovate-preset OK")
PY
