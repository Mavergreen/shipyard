#!/bin/sh
# platform: host-agnostic
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: no python3"; exit 77; }
cd "$here"
_tmp="${TMPDIR:-/tmp}"
w="$(mktemp -d "${_tmp%/}/renovate-captures.XXXXXX")"; trap 'rm -rf "$w"' EXIT
git -c core.quotepath=off ls-files > "$w/files" 2>/dev/null || { echo "SKIP: not a git checkout"; exit 77; }
python3 - "$w/files" .github/renovate.json default.json <<'PY'
import json, re, sys
def js(rx):
    out, i, cls = [], 0, False
    while i < len(rx):
        c = rx[i]
        if c == '\\':
            out.append(rx[i:i + 2]); i += 2; continue
        if cls:
            cls = c != ']'
        elif c == '[':
            cls = True
        elif c == '$':
            c = r'\Z'
        elif rx.startswith('(?<', i) and rx[i + 3:i + 4] not in ('=', '!'):
            c = '(?P<'; i += 2
        out.append(c); i += 1
    return ''.join(out)
def matcher(pat):
    m = re.fullmatch(r'/(.*)/([a-z]*)', pat)
    rx = re.compile(js(m.group(1)), re.I if 'i' in m.group(2) else 0)
    return lambda f: rx.search(f) is not None
files = [f for f in open(sys.argv[1]).read().split('\n') if f]
bad, seen = [], 0
for cfg in sys.argv[2:]:
    for mgr in json.load(open(cfg)).get('customManagers', []):
        pats = [matcher(p) for p in mgr.get('managerFilePatterns', [])]
        for f in (f for f in files if any(p(f) for p in pats)):
            seen += 1
            text = open(f).read()
            line1 = text.split('\n', 1)[0]
            got = [m.group('currentValue') for ms in mgr.get('matchStrings', []) for m in re.finditer(js(ms), text)]
            if got != [line1]:
                bad.append('%s: %s captures %r from %s, not its line 1 %r' % (cfg, mgr.get('depNameTemplate'), got, f, line1))
if not seen:
    bad.append('no manager matched a tracked file')
for b in bad:
    print('FAIL ' + b)
sys.exit(1 if bad else 0)
PY
echo "PASS renovate-captures"
