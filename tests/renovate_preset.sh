#!/bin/sh
# platform: host-agnostic
set -eu
cd "$(dirname "$0")/.."
python3 -m json.tool default.json >/dev/null || { echo "invalid JSON in default.json"; exit 1; }
PYTHONPATH=scripts/lib python3 -B - default.json <<'PY'
import json, re, sys
from renovate_regex import LINE2, js
c = json.load(open(sys.argv[1]))
cms = c.get("customManagers", [])
assert "mavericks-legacysupport" not in json.dumps(c) and "macports-legacy-support" not in json.dumps(c), "no repo pins macports-legacy-support any more; the preset must not track it"
assert "(?P<" not in json.dumps(cms), "managers must use Renovate (?<name>...) syntax, not Python (?P<name>...)"

assert len(cms) == 1, "the preset has one custom manager, which reads line 2 of every pin"
mgr = cms[0]
assert mgr.get("customType") == "regex", "the one manager is a regex manager"
assert mgr["managerFilePatterns"] == ["/^\\.mavergreen\\/upstream\\/(VERSION|COMMIT|PIN)$/", "/^\\.mavergreen\\/ingredients\\/[^/]+\\/(VERSION|PIN|COMMIT)$/"], "the one manager reads the upstream's and every ingredient's VERSION, COMMIT or PIN"
assert not [k for k in mgr if k.endswith("Template")], "the manager takes datasource, depName, versioning and extractVersion from line 2's captures; a template would set an absent versioning to an empty one"
pats = [re.compile(js(p[1:-1])) for p in mgr["managerFilePatterns"]]
def manages(f):
    return any(p.search(f) for p in pats)
for f in [".mavergreen/upstream/VERSION", ".mavergreen/upstream/COMMIT", ".mavergreen/upstream/PIN", ".mavergreen/ingredients/cmake/VERSION", ".mavergreen/ingredients/s6/PIN", ".mavergreen/ingredients/x/COMMIT"]:
    assert manages(f), "the manager must read %s" % f
for f in [".mavergreen/ingredients/clang22/LINUX_SHA256", ".mavergreen/ingredients/libcxx22/from", ".mavergreen/ingredients/a/b/VERSION", "components/recaulk/version", ".mavergreen/upstream/description", "x/.mavergreen/upstream/VERSION"]:
    assert not manages(f), "the manager must not read %s" % f
def deps(text):
    return [{k: v for k, v in m.groupdict().items() if v is not None} for ms in mgr["matchStrings"] for m in re.finditer(js(ms), text)]
MMVER = "regex:^(?<major>\\d+)\\.(?<minor>\\d+)\\.(?<patch>\\d+)-mavericks\\.(?<build>\\d+)$"
SHA = "f8745da2d9b1c3e4f5a6b7c8d9e0f1a2b3c4d5e6"
cases = [
    ("a VERSION on github-releases with -mavericks.N versioning",
     "4.4.5-mavericks.2\n# renovate: datasource=github-releases depName=Mavergreen/cmake versioning=%s\n" % MMVER,
     [{"currentValue": "4.4.5-mavericks.2", "datasource": "github-releases", "depName": "Mavergreen/cmake", "versioning": MMVER}]),
    ("the same VERSION with no final newline",
     "4.4.5-mavericks.2\n# renovate: datasource=github-releases depName=Mavergreen/cmake versioning=%s" % MMVER,
     [{"currentValue": "4.4.5-mavericks.2", "datasource": "github-releases", "depName": "Mavergreen/cmake", "versioning": MMVER}]),
    ("a PIN on git-tags",
     "v1.5.7@%s\n# renovate: datasource=git-tags depName=https://github.com/owner/repo\n" % SHA,
     [{"currentValue": "v1.5.7", "currentDigest": SHA, "datasource": "git-tags", "depName": "https://github.com/owner/repo"}]),
    ("a VERSION with extractVersion",
     "1.26.8\n# renovate: datasource=github-tags depName=golang/go extractVersion=^go(?<version>\\S+)$\n",
     [{"currentValue": "1.26.8", "datasource": "github-tags", "depName": "golang/go", "extractVersion": "^go(?<version>\\S+)$"}]),
    ("a VERSION with versioning and extractVersion",
     "1.2.3-mavericks.4\n# renovate: datasource=github-tags depName=a/b versioning=%s extractVersion=^v(?<version>.+)$\n" % MMVER,
     [{"currentValue": "1.2.3-mavericks.4", "datasource": "github-tags", "depName": "a/b", "versioning": MMVER, "extractVersion": "^v(?<version>.+)$"}]),
    ("a VERSION on pypi with no versioning",
     "6.0.3\n# renovate: datasource=pypi depName=PyYAML\n",
     [{"currentValue": "6.0.3", "datasource": "pypi", "depName": "PyYAML"}]),
    ("a COMMIT on git-refs, which tracks the default branch",
     "%s\n# renovate: datasource=git-refs depName=https://github.com/floodyberry/ed25519-donna\n" % SHA,
     [{"currentDigest": SHA, "datasource": "git-refs", "depName": "https://github.com/floodyberry/ed25519-donna"}]),
    ("a VERSION that is all hex digits but no commit",
     "20221003\n# renovate: datasource=github-releases depName=a/b\n",
     [{"currentValue": "20221003", "datasource": "github-releases", "depName": "a/b"}]),
    ("a file with no line 2", "1.0\n", []),
    ("a file with no line 2 and no final newline", "1.0", []),
    ("a line 2 that is not an annotation", "1.0\nsomething else\n", []),
    ("a line 2 with its keys out of order",
     "1.0\n# renovate: depName=a/b datasource=github-tags\n", []),
    ("a line 2 with extractVersion before versioning",
     "1.0\n# renovate: datasource=github-tags depName=a/b extractVersion=^v(?<version>.+)$ versioning=semver\n", []),
]
for what, text, want in cases:
    got = deps(text)
    assert got == want, "%s: the manager captures %r, not %r" % (what, got, want)
    l2 = (text.split("\n") + [""])[1]
    if l2.startswith("# renovate:"):
        assert bool(LINE2.fullmatch(l2)) == bool(want), "%s: renovate-suffix-versioning's line-2 grammar and the manager disagree" % what
assert "line 2" in " ".join(c["description"]), "the description says the preset reads line 2 of every pin"
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
