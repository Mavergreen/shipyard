value-file-line: every value file under .mavergreen/ holds its value alone on line 1, with at most a Renovate annotation on line 2.

## Why
Every reader takes line 1 as the value, so a space or a tab before or after it, or the CR of a CRLF line
ending, becomes part of the value: of the version, the tag, a scope glob. The one file Renovate bumps in a
directory carries "# renovate: datasource=... depName=..." on line 2; any other line 2 is a value nobody reads.
An upstream/VERSION that starts with a v puts the v in every release tag.

## Incident
None recorded.

## Limits
Value files are every file under .mavergreen/ except the prose and list files and the executables: reason,
revisit, untracked, tracked-by, any .md file, the one-per-line lists role, watch, target, union and intree,
and everything under hooks/, config/ and release-notes/. A file or directory whose name starts with a dot is
skipped. It checks the shape of line 1, not what the value means. An empty file passes, as a switch is one.

## Deviating
Write .mavergreen/deviations/value-file-line/<label>/ with scope (the path, from the repo root), reason and
revisit. A good reason says what reads the file beyond line 1; a good revisit says when that reader goes.

New in the flag day (P2, replacing upstream-version-bare, which checked UPSTREAM_VERSION alone)
