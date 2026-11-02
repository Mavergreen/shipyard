#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: no python3"; exit 77; }
cd "$here"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/renovate-captures.XXXXXX")"; trap 'rm -rf "$w"' EXIT
git -c core.quotepath=off ls-files > "$w/files" 2>/dev/null || { echo "SKIP: not a git checkout"; exit 77; }
PYTHONPATH=scripts/lib python3 -B - "$w/files" .github/renovate.json default.json <<'PY'
import json, re, sys
from renovate_regex import js
def matcher(pat):
    m = re.fullmatch(r'/(.*)/([a-z]*)', pat)
    rx = re.compile(js(m.group(1)), re.I if 'i' in m.group(2) else 0)
    return lambda f: rx.search(f) is not None
def expected(f, text):
    lines = text.split('\n')
    if len(lines) < 2 or not lines[1].startswith('# renovate:'):
        return []
    want = dict(t.split('=', 1) for t in lines[1][len('# renovate:'):].split())
    kind = f.rsplit('/', 1)[-1]
    if kind == 'PIN':
        want['currentValue'], want['currentDigest'] = lines[0].split('@', 1)
    elif kind == 'COMMIT':
        want['currentDigest'] = lines[0]
    else:
        want['currentValue'] = lines[0]
    return [want]
files = [f for f in open(sys.argv[1]).read().split('\n') if f]
bad, seen = [], 0
for cfg in sys.argv[2:]:
    for mgr in json.load(open(cfg)).get('customManagers', []):
        pats = [matcher(p) for p in mgr.get('managerFilePatterns', [])]
        for f in (f for f in files if any(p(f) for p in pats)):
            text = open(f).read()
            want = expected(f, text)
            seen += len(want)
            got = [{k: v for k, v in m.groupdict().items() if v is not None} for ms in mgr.get('matchStrings', []) for m in re.finditer(js(ms), text)]
            if got != want:
                bad.append('%s: its manager captures %r from %s, not %r' % (cfg, got, f, want))
if not seen:
    bad.append('no manager captured a tracked file')
for b in bad:
    print('FAIL ' + b)
sys.exit(1 if bad else 0)
PY
echo "PASS renovate-captures"
