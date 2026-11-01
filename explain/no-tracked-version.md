no-tracked-version: VERSION is not committed.

## Why
VERSION is a build product, written by resolve-version.sh and gitignored. A committed copy drifts from the
tags: container-tools built -mavericks.14 from a file that said .2, which also made its tag path
(tag equals VERSION) impossible to satisfy. An untracked VERSION is fine.

## Incident
container-tools built -mavericks.14 from a committed VERSION that said .2 (undated in the conventions skill).

## Limits
It asks git what is tracked; without a git checkout or a tracked-file list it cannot answer, and
tracked-files reports that. It checks only the file named VERSION at the repo root. version-ignored is the
mirror that checks the file is also ignored.

## Deviating
No deviation is read for this id. Remove it from the index and ignore it:
git rm --cached VERSION, add /VERSION to .gitignore, and commit .mavergreen/upstream/VERSION instead.

Formerly gate check 7 (VERSION)
