host: not a check but a deviation key: "- host:<os>: <reason>" excuses bash32-parse on a host that cannot measure it.

## Why
bash32-parse needs a real bash 3.2 as /bin/sh, which 10.9 and macOS have and Linux does not. A host that
cannot measure fails "can't measure here" unless a host deviation, naming the lowercase uname -s of that host
(linux), excuses it. The run prints that it skipped by deviation, and counts it. This is conventions-as-checks'
K4 escape: the 10.9 constraint wins, and a check needing a tool a host cannot have is a declared deviation
with its reason, never a quiet pass.

## Incident
None recorded.

## Limits
It excuses only bash32-parse. A host deviation does not make the check pass on that host; it records that
nothing was measured there.

## Deviating
Write "- host:linux: bash32-parse needs a bash 3.2 /bin/sh and Linux has none. Revisit when QUEUE #60's
Apple-shells collection ships its Linux tarball." A good reason names the missing tool and the exit.
shipyard declares exactly this line.

New in the flag day (QUEUE #59)
