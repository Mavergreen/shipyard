#!/usr/bin/env python3
# platform: host-agnostic
"""Print where one moved pin's change is described, as "<label><TAB><url>", if a Renovate manager says.

    renovate-link.py <shipyard-root> <pin-path> <KEY or ""> <old or ""> <new>

Run from the repo root. Reads the repo's .github/renovate.json, then each shipyard preset it extends
(github>Mavergreen/shipyard[:name] is <shipyard-root>/<name or default>.json). The first regex
customManager whose managerFilePatterns match the pin path, and whose matchStrings put currentValue
on the KEY's own assignment line (any line for a whole-file pin), owns the pin. It links only for
github-releases or github-release-attachments (the new release) and github-tags (a compare of the
two tags); a manager on any other datasource owns the pin with no link, and prints "owned". Prints
nothing when no manager owns it.

CI-only (release notes are generated in CI), hence python3: Renovate's config is JSON holding
JavaScript regexes.
"""
import fnmatch
import json
import os
import re
import sys

OWNER_REPO = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")


def load(path):
    with open(path) as f:
        return json.load(f)


def configs(shipyard, cfg, seen):
    yield cfg
    for ext in cfg.get("extends", []):
        m = re.match(r"^(?:github|local)>Mavergreen/shipyard(?::([A-Za-z0-9_.-]+))?(?:#.*)?$", ext)
        if not m:
            continue
        path = os.path.join(shipyard, (m.group(1) or "default") + ".json")
        if path in seen:
            continue
        if not os.path.isfile(path):
            sys.exit("renovate-link.py: %s extends %s, but %s does not exist" % (".github/renovate.json", ext, path))
        seen.add(path)
        yield from configs(shipyard, load(path), seen)


def js_regex(src):
    return re.compile(re.sub(r"\(\?<([A-Za-z_][A-Za-z0-9_]*)>", r"(?P<\1>", src))


def file_matches(patterns, path):
    for p in patterns:
        if len(p) > 1 and p.startswith("/") and p.rfind("/") > 0:
            body = p[1:p.rfind("/")]
            if js_regex(body).search(path):
                return True
        elif fnmatch.fnmatchcase(path, p.replace("**", "*")):
            return True
    return False


def owns(mgr, content, key):
    for src in mgr.get("matchStrings", []):
        for m in js_regex(src).finditer(content):
            if "currentValue" not in m.groupdict() or m.start("currentValue") < 0:
                continue
            if not key:
                return m
            start = content.rfind("\n", 0, m.start("currentValue")) + 1
            end = content.find("\n", start)
            line = content[start:] if end < 0 else content[start:end]
            if re.match(r"^\s*(export\s+)?" + re.escape(key) + "=", line):
                return m
    return None


def render(template, groups):
    return re.sub(r"\{\{\{?\s*([A-Za-z_]+)\s*\}?\}\}", lambda t: groups.get(t.group(1)) or "", template)


def repo_of(mgr, groups):
    for name in ("packageName", "depName"):
        tmpl = mgr.get(name + "Template")
        value = render(tmpl, groups) if tmpl else groups.get(name)
        if not value:
            continue
        value = re.sub(r"^https://github\.com/", "", value)
        value = re.sub(r"\.git$", "", value)
        if OWNER_REPO.match(value):
            return value
    return None


def tag_prefix(mgr):
    m = re.match(r"^\^((?:[A-Za-z0-9_.-]\??|\\.)*)\(\?<version>", mgr.get("extractVersionTemplate", ""))
    if not m:
        return ""
    lit = re.sub(r"[A-Za-z0-9_.-]\?", "", m.group(1))
    return re.sub(r"\\(.)", r"\1", lit)


def main(argv):
    if len(argv) != 6:
        sys.stderr.write("usage: renovate-link.py <shipyard-root> <pin-path> <KEY or \"\"> <old or \"\"> <new>\n")
        return 2
    shipyard, path, key, old, new = argv[1:]
    repo_cfg = ".github/renovate.json"
    if not os.path.isfile(repo_cfg) or not os.path.isfile(path):
        return 0
    with open(path) as f:
        content = f.read()
    for cfg in configs(shipyard, load(repo_cfg), set()):
        for mgr in cfg.get("customManagers", []):
            if mgr.get("customType") != "regex":
                continue
            if not file_matches(mgr.get("managerFilePatterns", mgr.get("fileMatch", [])), path):
                continue
            m = owns(mgr, content, key)
            if not m:
                continue
            groups = {k: v for k, v in m.groupdict().items() if v}
            datasource = mgr.get("datasourceTemplate") or groups.get("datasource")
            repo = repo_of(mgr, groups)
            if datasource not in ("github-releases", "github-release-attachments", "github-tags") or not repo:
                print("owned")
                return 0
            pre = tag_prefix(mgr)
            base = "https://github.com/" + repo
            if datasource == "github-tags" and old:
                print("changes\t%s/compare/%s%s...%s%s" % (base, pre, old, pre, new))
            else:
                print("release notes\t%s/releases/tag/%s%s" % (base, pre, new))
            return 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
