#!/bin/sh
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
assert "extractVersionTemplate" in m, "must strip the leading v"

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
print("renovate-preset OK")
PY
