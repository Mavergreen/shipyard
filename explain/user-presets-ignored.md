user-presets-ignored: a repo that commits CMakePresets.json also ignores CMakeUserPresets.json.

## Why
CMakeUserPresets.json is the per-developer build-location override, and the only thing that can override the
shared default: a preset's own environment block is applied after the real process environment, so
exporting MAVERICKS_BUILD_ROOT cannot redirect a --preset build. Left unignored it sits in git status and
gets committed by accident, pinning everyone to one person's paths. A repo with no committed presets file
has no override channel and is not asked.

## Incident
None recorded.

## Limits
It asks git whether CMakeUserPresets.json would be ignored. It does not check what a committed user presets
file points at.

## Deviating
No deviation is read for this id. Add CMakeUserPresets.json to .gitignore.

Formerly gate check 20
