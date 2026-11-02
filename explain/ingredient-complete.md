ingredient-complete: every directory under .mavergreen/ingredients/ has a role, a description and a why, at most one of PIN and VERSION, and exactly one way a new release reaches it.

## Why
An ingredient is one build input, declared once. The ingredients table, the release notes and provisioning
read its role (one or more of linked, shipped, build-only, test and reference, one per line), its one-line
description, and its one-line why: what it is, and why this repo needs it. A directory with both PIN and
VERSION has two pins, and which one the build reads would be a guess. Exactly one of three things says how a
new release reaches the repo: a "# renovate:" line 2 on the value file Renovate bumps, an untracked file
saying why nothing can, or a tracked-by file naming the built-in Renovate manager that bumps the pin where
it lives. With none, nobody decided; with two, the notes and the table would have to pick one.

## Incident
None recorded.

## Limits
It checks that the files exist and that each role is a known one, not what the description or why say. A
from ingredient is tracked through its parent, so the tracking rule skips it; from-parent checks it instead.
A repo with no ingredient directories reports it not run. pin-well-formed checks a PIN's shape, and
value-file-line the shape of each value file.

## Deviating
No deviation is read for this id. Add the missing file, or delete the extra one.

New in the flag day (P2, replacing ingredient-tracked, which read the INGREDIENTS.md table's marks)
