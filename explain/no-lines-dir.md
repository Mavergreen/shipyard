no-lines-dir: no lines/ directory exists at the repo root.

## Why
lines/<id>/ is the retired shape for an upstream that supports several lines at once. A line is a product
and a product is a repo: Mavergreen/golang-126, clang-22, nodejs-24, each serving its line from the root
with its own UPSTREAM_VERSION and patches/. A reappearing lines/ means the retired shape crept back. A new
line belongs in a new repo, and renaming a line repo is a flag-day step that is asked for, never done in
passing.

## Incident
2026-09-22: golang, nodejs and clang all migrated to one repo per line, and no family repo carries lines/
any more.

## Limits
It looks for a directory with that name at the repo root only. It does not check that a line repo derives
its line from UPSTREAM_VERSION, or that its Renovate cap names the next line.

## Deviating
No deviation is read for this id. Move the line's UPSTREAM_VERSION and patches/ to the repo root of a repo
named for the line.

Formerly gate check 7b
