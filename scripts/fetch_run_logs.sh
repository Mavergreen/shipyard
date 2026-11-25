#!/bin/sh
# platform: host-agnostic
#   usage: fetch_run_logs.sh REPO RUN_ID DIR      ->  DIR/job-<id>.log ...
#          Fetches the log of every FINISHED job in a workflow run, one file each, for
#          scan-for-key.yml to scan. Finished only: the job running this is still writing its own
#          log, and it never touches the key. Needs gh with a token that can read the run's logs --
#          `actions: read`. A run with no finished job is an error: nothing to scan is not a pass.
#          CI-only.
# platform: "not skipped" -- GitHub calls a skipped job "completed", but it never ran, so it has no
#           log (fetching it 404s) and cannot have printed anything. A publishing run that fails
#           before signing skips the rest, and the always() scan then died on those -- a second red
#           job hiding the real one. A public repo's logs still require `actions: read` --
#           anonymous requests get 403.
set -eu
[ "$#" -eq 3 ] || { echo "usage: fetch_run_logs.sh REPO RUN_ID DIR" >&2; exit 2; }
REPO="$1"; RUN="$2"; DIR="$3"
mkdir -p "$DIR"

rows="$(gh api "repos/$REPO/actions/runs/$RUN/jobs" --paginate \
         --jq '.jobs[] | select(.status == "completed" and .conclusion != "skipped")
               | [.id, (if .runner_id != null or ((.steps // []) | length) > 0 then "ran" else "never" end),
                  (.conclusion // "none"), (.name // "")] | @tsv')" \
  || { echo "fetch_run_logs: cannot list the jobs of $REPO run $RUN" >&2; exit 1; }
[ -n "$rows" ] || { echo "fetch_run_logs: run $RUN has no finished job -- nothing to scan is not a pass" >&2; exit 1; }

# platform: a build log is colored, and without --allow-escape-sequences gh refuses to print the
#           response at all ("the response contains terminal escape sequences") -- which is how
#           openssh's first scan died. On a failure, gh's own stderr says why; guessing a reason here
#           once sent the diagnosis the wrong way.
# platform: a job with no runner and no steps never started and has no log: report it and skip it.
tab="$(printf '\t')"
n=0
while IFS="$tab" read -r id ran concl name; do
  if [ "$ran" = never ]; then
    echo "fetch_run_logs: job $id ($name) has no log ($concl): nothing to scan" >&2
    continue
  fi
  gh api "repos/$REPO/actions/jobs/$id/logs" --allow-escape-sequences > "$DIR/job-$id.log" \
    || { echo "fetch_run_logs: cannot fetch job $id's log (gh's reason is above)" >&2; exit 1; }
  n=$((n + 1))
done <<EOF
$rows
EOF
[ "$n" -gt 0 ] || { echo "fetch_run_logs: run $RUN has no job that started -- nothing to scan is not a pass" >&2; exit 1; }
echo "fetch_run_logs: $n finished job log(s) from $REPO run $RUN" >&2
