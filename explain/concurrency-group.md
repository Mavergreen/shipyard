concurrency-group: release.yml's concurrency group is keyed per run, and only a pull request may cancel.

## Why
A run that can publish must be alone in its group and cancelled by nothing. cancel-in-progress: false
protects the run that is executing and not the one that is queued: GitHub keeps only the newest pending run
per group and cancels the rest, so a shared group silently discards releases. Cancelling a push run is no
better, because concurrency is decided when the run is queued, long before the version step knows whether
this run releases, and cancelling the run cancels its publish job too, which can leave a half-uploaded
release whose tag is already taken. So the group is keyed on github.run_id for everything except a pull
request, and cancel-in-progress names pull_request. Both halves are checked, because either alone lets the
old shape back in: a group that mentions github.event_name looks keyed per event and is not.

Two dispatches can now compute the same -mavericks.(N+1). Nothing replaces the old lock, on purpose:
publish-release.yml refuses the loser at publish time with a message naming the tag, and the loser
re-dispatches. A wasted build with a red X is better than a release that silently never happened.

## Incident
2026-09-09: mavericks-golang lost a release 13 seconds after the run that evicted it. A deliberate probe
reproduced it: two same-SHA dispatches merely queue, and the third cancels the queued one while
cancel-in-progress evaluates to false.

## Limits
It reads the group and cancel-in-progress expressions as text. It cannot tell that a group keyed on
github.run_id is composed with something that makes it shared again, and it does not look at other
workflows that publish.

## Deviating
No deviation is read for this id. Write the block from release-concurrency's explanation; there is no
shape of "queued publishes may be dropped" that the family accepts.

Formerly gate check 1b
