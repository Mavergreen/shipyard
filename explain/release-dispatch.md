release-dispatch: release.yml's workflow_dispatch takes force_publish (the reason) and reproduce_tag, nothing else, and its publish job runs only on a dispatch.

## Why
Reproducible releases: a dispatch asks for a release, and the release decision publishes only the content
that changed. One shape lets cut-release.sh and repackage-on-ingredient-bump.yml dispatch any repo the same
way, where the repos once took six shapes across eleven repos (local_release, repackage, release, and
others). The check holds a release.yml that calls publish-release.yml to four things: the dispatch inputs
are exactly force_publish, a string and not required, and optionally reproduce_tag; every call of
publish-release.yml passes force-reason: ${{ inputs.force_publish }}, so a forced release says why in its
notes; the publish job's if: requires github.event_name == 'workflow_dispatch', so a push only builds for
feedback; and the publish job never runs in a reproduce run, under schedule or with reproduce_tag set.

## Incident
None recorded. On 2026-10-18 the product repos' dispatch inputs took six shapes across eleven repos, so
the right -f was per repo and an agent cutting a release had to read each release.yml first.

## Limits
It reads the publish job's if: as text: it looks for github.event_name == 'workflow_dispatch', for
github.event_name != 'schedule' or that dispatch clause, and for inputs.reproduce_tag == '' or
!inputs.reproduce_tag, and does not evaluate the expression, so a negation around them is not caught. A
release.yml that does not call publish-release.yml has nothing for it to hold.

## Deviating
No deviation is read, apart from the push clause: a repo with a publish-unchanged deviation scoped *
(deviations/publish-unchanged/<label>/) may publish on a push, as shipyard does, and still may not publish
in a reproduce run. The dispatch shape itself can't be deviated.

New in the flag day (P6, reproducible releases)
