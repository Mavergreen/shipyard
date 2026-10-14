release-concurrency: release.yml declares a concurrency: block.

## Why
A workflow that can publish must say how its runs relate to each other. With no concurrency block, two
runs can compute the same next version and race for the same tag. The block this family uses is the one
described under concurrency-group: a group of one for every run that can publish, and superseding only
for pull requests. This id only asks that a block exists; concurrency-group asks whether it is the right one.

## Incident
The shared-group shape this rule replaced lost a release: golang's run on 2026-09-09 was evicted 13
seconds after the run that displaced it, and nothing went red. That incident is recorded under
concurrency-group, which is the check that catches its shape.

## Limits
It looks for the key on a non-comment line of .github/workflows/release.yml. It does not read the block's
meaning, so a block that exists but is wrong passes here and fails concurrency-group instead. In a repo
with no release.yml it reports itself not run, as every rule that reads release.yml does; the repo-wide
rules still run there.

## Deviating
No deviation is read for this id; a "- release-concurrency:" line in INGREDIENTS.md excuses nothing.
Add the block instead:

  concurrency:
    group: release-${{ github.event_name == 'pull_request' && github.ref || github.run_id }}
    cancel-in-progress: ${{ github.event_name == 'pull_request' }}

Formerly gate check 1
