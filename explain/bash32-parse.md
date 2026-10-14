bash32-parse: /bin/sh -n accepts every tracked shell script.

## Why
Bash 3.2 is the /bin/sh of 10.9 and of macOS, and it refuses quoting and syntax that dash, busybox, Linux and
newer bashes accept. Shell portability's pattern lint cannot see it. The check runs /bin/sh -n on every
tracked shell script (a .sh file, or a shebang naming sh), and /bin/bash -n on those whose shebang names bash,
after a canary that proves the shell refuses an apostrophe inside ${VAR:?word} in double quotes. A host whose
/bin/sh is not bash 3.2, or where the canary passes, cannot measure, and the check fails "can't measure
here" instead of passing silently. The install action runs shipyard-check --only bash32-parse in every macOS
job that installs shipyard, once the repo is checked out, so a repo wires nothing; on-target runs it on 10.9.
A repo that tracks no shell script reports it not run. SHIPYARD_BASH32_SH and SHIPYARD_BASH32_BASH name other bash 3.2 shells.

## Incident
2026-10-14 (filed from snow-leopard-vm): longboat's first release run failed on macOS, run 38569568867.
build/install-go.sh had an apostrophe inside ${SHIPYARD_SCRIPTS:?...} within double quotes, a parse error
under bash 3.2. Bash 5 in POSIX mode, dash and busybox accept it, so shell-portability and every Linux-side
check missed it. Longboat's own copy (a38553b) goes in its flag-day commit.

## Limits
Linux has no bash 3.2, so it cannot measure there, and shipyard declares a host deviation for it. It checks
that a script parses, not that it behaves; it cannot see runtime differences. QUEUE #60 plans a family
collection of Apple's shells so that Linux can measure, and the older floors' shells too.

## Deviating
Write "- bash32-parse:<path>: <reason>. Revisit when <exit>." to excuse one script, or
"- host:<os>: <reason>. Revisit when <exit>." for a host that cannot measure it (see the host id). A good
reason says why the script must use a construct bash 3.2 refuses, and the exit.

New in the flag day (QUEUE #59)
