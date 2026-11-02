self-upstream-exclude: not a check but a deviation key: a self-upstream-exclude deviation whose scope is <glob> names paths whose changes do not move a self-upstream date.

## Why
A self-upstream repo's version is a date that moves when its own code does. self-upstream-version.sh
derives it from git history, and a path this key names (a git pathspec glob, where * stays within one
path component) is left out, so a change to it alone keeps the last date.

## Incident
None recorded.

## Limits
It shapes the derived version only. deviations.sh refuses a glob of only * and /, which would make no
change own code, so every release would keep the last date.

## Deviating
Write .mavergreen/deviations/self-upstream-exclude/<label>/ with a scope (<glob>), a reason and a revisit. A good reason says why changes there are not the
product's own code.

Formerly self-upstream-version.sh's self-upstream-exclude declaration
