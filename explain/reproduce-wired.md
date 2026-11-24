reproduce-wired: release.yml rebuilds its latest release weekly and on reproduce_tag.

## Why
Reproducible releases: a release that can't be rebuilt from its tag isn't reproducible, and nothing
notices until the day a rebuild is needed. So every release.yml that publishes takes a reproduce_tag
dispatch input, and a schedule: with exactly one weekly cron (its day-of-week field is not *). Under the
schedule the reproduce job rebuilds the line's latest tag cold, and under reproduce_tag it rebuilds that
tag; reproduce.sh compares the rebuild's CONTENT-MANIFEST.txt with the release's and names each
difference.

## Incident
None recorded.

## Limits
It checks the wiring, not the result: that the input and the cron exist, not that the reproduce job runs
reproduce.sh or that the rebuild matched. A release.yml that does not call publish-release.yml has nothing
to reproduce and is not held.

## Deviating
No deviation is read under this id. Write .mavergreen/deviations/reproducible/<label>/ with the scope *, a reason naming what can't be made
stable, and a revisit. A deviation scoped to paths exempts those paths from the comparison and leaves the
wiring required.

New in the flag day (P6, reproducible releases)
