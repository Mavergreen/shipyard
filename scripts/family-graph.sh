#!/bin/sh
# platform: host-agnostic
#   usage: family-graph.sh [--from-dir DIR]
#          Prints the family's ingredient graph: "<consumer> -> <ingredient>" for each repo that declares a
#          registered product of another repo in its "## Declared state", then "DIAMOND <consumer>: <X> via
#          <Y>" where the consumer declares both X and Y and Y reaches X, then "CYCLE a -> b -> ... -> a",
#          each cycle once, starting at its smallest name. Each group is sorted. Nodes are registry repos.
#          Default: reads every registry repo's INGREDIENTS.md at its default branch with read-only
#          `gh api` (needs gh and python3). --from-dir DIR reads DIR/<repo>/INGREDIENTS.md instead.
#          Exit 0; 1 when a Declared state is malformed; 2 on a usage error or when gh fails.
# spec: scripts/declared-state.sh; scripts/product-names
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
dir=""
case "$#:${1:-}" in
  0:) ;;
  2:--from-dir) dir="$2"; [ -d "$dir" ] || { echo "family-graph: $dir is not a directory" >&2; exit 2; } ;;
  *) echo "usage: family-graph.sh [--from-dir DIR]" >&2; exit 2 ;;
esac
[ -z "$dir" ] || dir="$(cd "$dir" && pwd)"
exec python3 - "$SELF" "$dir" <<'PY'
import os, subprocess, sys, tempfile

self_dir, src = sys.argv[1], sys.argv[2]
reg = os.environ.get("MAVERGREEN_PRODUCT_NAMES") or os.path.join(self_dir, "product-names")
repo_of = {}
try:
    with open(reg) as f:
        for line in f:
            w = line.split()
            if len(w) >= 3 and not w[0].startswith("#"):
                repo_of.setdefault(w[0], w[2])
except OSError as e:
    sys.exit("family-graph: cannot read the registry: %s" % e)
repos = sorted(set(repo_of.values()))

def fetch(repo, into):
    r = subprocess.run(["gh", "api", "-H", "Accept: application/vnd.github.raw",
                        "repos/Mavergreen/%s/contents/INGREDIENTS.md" % repo],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True)
    if r.returncode == 0:
        with open(os.path.join(into, "INGREDIENTS.md"), "w") as f:
            f.write(r.stdout)
    elif "HTTP 404" not in r.stderr:
        print("family-graph: gh api for %s: %s" % (repo, r.stderr.strip().replace("\n", " ")), file=sys.stderr)
        sys.exit(2)

edges = {}
bad = False
with tempfile.TemporaryDirectory() as tmp:
    for repo in repos:
        d = os.path.join(src, repo) if src else os.path.join(tmp, repo)
        if not src:
            os.mkdir(d)
            fetch(repo, d)
        if not os.path.isdir(d):
            continue
        r = subprocess.run(["sh", os.path.join(self_dir, "declared-state.sh"), d],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True)
        if r.returncode != 0:
            print("family-graph: %s: %s" % (repo, r.stderr.strip().replace("\n", " ")), file=sys.stderr)
            bad = True
            continue
        for line in r.stdout.splitlines():
            name = line.split("\t")[0]
            if name != "upstream" and name in repo_of:
                edges.setdefault(repo, set()).add(repo_of[name])
if bad:
    sys.exit(1)

def reach(a, b):
    seen, todo = set(), [a]
    while todo:
        n = todo.pop()
        for m in edges.get(n, ()):
            if m == b:
                return True
            if m not in seen:
                seen.add(m)
                todo.append(m)
    return False

for c in sorted(edges):
    for x in sorted(edges[c]):
        print("%s -> %s" % (c, x))
diamonds = set()
for c, deps in edges.items():
    for x in deps:
        for y in deps:
            if y != x and y != c and x != c and reach(y, x):
                diamonds.add("DIAMOND %s: %s via %s" % (c, x, y))
for d in sorted(diamonds):
    print(d)

cycles = set()
for start in sorted(set(edges) | {m for v in edges.values() for m in v}):
    stack = [(start, [start])]
    while stack:
        n, path = stack.pop()
        for m in edges.get(n, ()):
            if m == start:
                cycles.add(" -> ".join(path + [start]))
            elif m > start and m not in path:
                stack.append((m, path + [m]))
for c in sorted(cycles):
    print("CYCLE " + c)
PY
