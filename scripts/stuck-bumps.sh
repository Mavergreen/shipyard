#!/bin/sh
# platform: host-agnostic -- CI-only, where gh and python3 are
set -eu
days="${STUCK_DAYS:-7}"
case "$days" in
  ''|*[!0-9]*) echo "stuck-bumps: STUCK_DAYS is '$days', not a whole number of days" >&2; exit 2 ;;
esac
python3 - "$days" <<'PY'
import datetime, json, os, subprocess, sys
days = int(sys.argv[1])
def gh(*args):
    run = subprocess.run(('gh',) + args, stdout=subprocess.PIPE, text=True)
    if run.returncode:
        sys.exit('stuck-bumps: gh %s exited %d' % (' '.join(args), run.returncode))
    return json.loads(run.stdout)
now = datetime.datetime.now(datetime.timezone.utc)
rows = []
for repo in sorted(r['nameWithOwner'] for r in gh('repo', 'list', 'Mavergreen', '--no-archived', '--limit', '1000', '--json', 'nameWithOwner')):
    for pr in gh('pr', 'list', '-R', repo, '--state', 'open', '--limit', '1000', '--json', 'number,title,createdAt,headRefName'):
        title = pr['title'].lower()
        if not pr['headRefName'].startswith('renovate/') or ('mavergreen/' not in title and 'mavergreen ingredients' not in title):
            continue
        age = now - datetime.datetime.fromisoformat(pr['createdAt'].replace('Z', '+00:00'))
        if age > datetime.timedelta(days=days):
            rows.append((-age, repo, pr['number'], '%s#%d %d %s' % (repo, pr['number'], age.days, pr['title'])))
lines = [r[3] for r in sorted(rows)]
for l in lines:
    print(l)
summary = os.environ.get('GITHUB_STEP_SUMMARY')
if summary:
    with open(summary, 'a') as f:
        f.write('## Family bumps open longer than %d days\n\n' % days)
        if lines:
            f.write('```\n' + ''.join(l + '\n' for l in lines) + '```\n')
        else:
            f.write('No family bump has been open longer than %d days.\n' % days)
PY
