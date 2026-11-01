upstream-complete: a product repo has .mavergreen/upstream/ with exactly one of VERSION, COMMIT or PIN, and a description.

## Why
Every release's version is <upstream>-mavericks.N, and the upstream comes from this directory: VERSION is the
version itself, and a COMMIT or a PIN is turned into one by .mavergreen/hooks/derive-upstream-version. With
none, there is no version to cut. With two, which one the version came from is a guess. A COMMIT or a PIN with
no derive hook has nothing to turn it into a version. The description says, in one line, what the upstream is.

## Incident
None recorded.

## Limits
It runs only where there is a .github/workflows/release.yml, as a repo without one cuts no version. It checks
that the files exist, not what they hold: value-file-line checks the shape of each value, and running the
derive hook is version.sh's job.

## Deviating
No deviation is read for this id. Create .mavergreen/upstream/ with VERSION (or COMMIT or PIN, plus
.mavergreen/hooks/derive-upstream-version) and a one-line description.

New in the flag day (P2, replacing upstream-version, which looked for a root UPSTREAM_VERSION or a derive script)
