docs-no-sudo: no user-facing doc or message tells the reader to run sudo.

## Why
Family tools elevate themselves, so a doc that prescribes sudo teaches a step the tool does itself, and runs
the tool's per-user work as root. Write the plain command: mavergreen install <file.pkg> for a pkg, or
double-click it. Docs write the bare mavergreen, never its path. Runtime messages are the opposite: they keep
the absolute path, because they surface where paths.d is not read (the daily notification, Installer's log,
IDEs, cron, ssh commands). The check covers README*, *.md (except release-notes/**, explain/**, the conventions skill,
and design, decision and plan records under docs/decisions/**, docs/adr/**, docs/plans/** and
docs/superpowers/**), man pages, pkg resources, and echo, printf or heredoc text in a tracked script outside
tests/. An executed sudo in a script is code and passes.

## Incident
2026-10-14 (QUEUE #63): clang-22 22.1.8-mavericks.1 documented sudo longboat install 10.9 in its
INGREDIENTS.md, and QUEUE #45 said the same. The maintainer agreed the line that day: docs never prescribe
sudo, and the tools elevate per step.

## Limits
It is a text match on the word sudo; it cannot tell a doc that warns against sudo from one that prescribes it.
Scripts are scanned for the quoted argument of echo and printf and for heredoc bodies; prose assembled any
other way is not seen. QUEUE #63's runtime policy (mav_root_policy, mav_sudo) is a separate piece.

## Deviating
Write "- docs-no-sudo:<path>: <reason, naming the exit>". A good reason says what root step no family
command can do yet, or which tool has not adopted mav_root_begin, and when that ends. shipyard's own entry for
README.md names the Engine's mavergreen install and uninstall as its exit.

New in the flag day (QUEUE #63)
