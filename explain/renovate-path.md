renovate-path: the only tracked Renovate config is .github/renovate.json.

## Why
The Renovate checks (renovate-no-restated-defaults, automerge-described, renovate-suffix-versioning, and
the ids that read the preset) read only .github/renovate.json. A config kept at the root, in .gitlab/ or as
.renovaterc* exempts its repo from them without anyone deciding it should. shipyard's configure step
scaffolds .github/renovate.json when it is absent, so a config kept elsewhere also gets a second,
preset-only config written beside it by the first build; that dirties the tree assert-tree-clean checks,
and Renovate reads only the first config it finds, so one of the two is silently dead. The check fails any
other tracked Renovate config path, alone or beside the right one.

## Incident
None recorded.

## Limits
It lists the paths Renovate accepts (renovate.json, renovate.json5, .renovaterc, .renovaterc.json,
.renovaterc.json5, .github/renovate.json5, .gitlab/renovate.json, .gitlab/renovate.json5). A config
embedded in package.json is not one of them.

## Deviating
Write "- renovate-path:<path>: <reason>" for the one path. A good reason says why the file cannot move
(a tool that reads it from there), and its exit. Otherwise git mv it to .github/renovate.json.

Formerly gate check 26
