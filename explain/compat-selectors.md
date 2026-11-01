compat-selectors: a shipped binary sends no Objective-C selector newer than 10.9.

## Why
A selector newer than 10.9 is as invisible to a cross build as a post-10.9 import is (see compat-imports). The
guard runs strings over the x86_64 slice and matches each line exactly against
a post-10.9 selector list. MAVERICKS_POST_10_9_SELECTORS adds selectors to deny; MAVERICKS_ALLOW_SELECTORS
lists those the code guards with -respondsToSelector:.

## Incident
2026-10-12, filed from mavergreen-gh: gh 2.102.0, pure Go and with no Objective-C sections,
failed with "post-10.9 ObjC selector(s) sent: labelColor". The word came from Go's type data: a struct
field in the tview library, which strings printed as its own line. gh works around it by allowing
labelColor, which is a different thing from the guarded selectors the allowance is for.

## Limits
It reads every string in the file, not just the Objective-C method names, so any byte run that spells a
selector counts. A proposal reads only __TEXT,__objc_methname, so that a binary with no such
section has sent no selectors, keeping the reader fail-closed.

## Deviating
A "- compat-selectors:<glob>: <reason>. Revisit when <exit>." line in
INGREDIENTS.md excuses this id for the binaries whose path the glob matches: under shipyard-check --dist, the
path inside the pkg or tarball (usr/local/mavergreen/<product>/...). That is how one binary in a dist keeps
the allowance its CMake target passes in a knob, since --dist applies one environment to every binary. Add the selector to
MAVERICKS_ALLOW_SELECTORS, or excuse the binary, only if the code guards it with -respondsToSelector:. A false positive from non-Objective-C data is that proposal's to fix, not an allowance's.

Formerly the compat guard's selectors rule
