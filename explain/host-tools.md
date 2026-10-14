host-tools: every tracked script declares its host, and a host-agnostic one runs no macOS-only tool.

## Why
Nothing stopped a script that a Linux job depends on from growing an otool or sw_vers call: it passed every
gate and broke on the runner. check-shell-portability.sh cannot see it, since flawless POSIX sh can still
call lipo. A script declares, in its header after any shebang and before the first line of code, exactly one
of "# platform: host-agnostic" or "# platform: macOS-only -- <why>"; the reason is required. An undeclared
script fails rather than defaulting to host-agnostic, because a default makes the gate silently incomplete.
A host-agnostic file may not run a tool from the list in host-tools.awk (otool, lipo, sw_vers, installer,
pkgutil, pkgbuild, codesign, xcrun, plutil, hdiutil, defaults, launchctl and others) at command position;
extend that list, never trim it. A guarded call carries "# platform: guarded macOS-only call -- <the guard>"
on the line directly above it, covering that one line only.

## Incident
None recorded.

## Limits
It reads shell with a lexer, not a parser. Known blind spots: a tool named through a variable, eval, a .py
file's subprocess calls, *.cmake and workflow run: blocks. Known false positives: a case pattern at the
start of a line (otool)), a function defined with a space, a .py line shaped like shell. Known false
negatives: a redirection before the command, a prefix wrapper such as nice or timeout, find -exec. It is
opt-in: a repo where no script declares a host passes and says it has not adopted the split; --required
makes that a failure, and shipyard runs it that way so it cannot quietly un-adopt. --strict-host cannot see
a host-agnostic suite that skips part of itself without exiting 77.

## Deviating
No deviation is read for this id. Declare the script macOS-only with a reason, reword the false-positive
line, or guard the call with the comment above.

Formerly gate check 22
