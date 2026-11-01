registry-read: nothing tracked reads the CMake user package registry.

## Why
shipyard now lives in shipyard-cmake's own prefix, and nothing writes ~/.cmake/packages any more. A script
that reads it reads a file that is no longer there, and reads it silently, resolving to an empty path
rather than failing. The fix is to run shipyard-scripts, which asks shipyard-cmake where the scripts are, or
to use $SHIPYARD_SCRIPTS in CI.

## Incident
None recorded.

## Limits
It is a text match on tracked files, written so that its own message cannot spell the full path or the
gate would flag itself. A registry path built from pieces at run time is not seen. Two blind spots were
found in it: a locator reading $HOME/.local/share/cmake/... is not matched, and tests/ is skipped, so a
locator there is never reported.

## Deviating
Write "- registry-read:<path>: <reason>" for one tracked file. A good reason says why that file must read
the registry (a historical document that quotes it, say), and when it stops: "Revisit when <condition>."

Formerly gate check 16
