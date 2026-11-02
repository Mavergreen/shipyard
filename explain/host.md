host: not a check but a deviation key: a host deviation whose scope is <os> excuses bash32-parse on a host that cannot measure it.

## Why
bash32-parse needs a real bash 3.2 as /bin/sh, which 10.9 and macOS have and Linux does not. A host that
cannot measure fails "can't measure here" unless a host deviation, naming the lowercase uname -s of that host
(linux), excuses it. The run then reports bash32-parse as not run, naming the deviation, and never counts it
as a pass. This is conventions-as-checks'
K4 escape: the 10.9 constraint wins, and a check needing a tool a host cannot have is a declared deviation
with its reason, never a quiet pass.

## Incident
None recorded.

## Limits
It excuses only bash32-parse. A host deviation does not make the check pass on that host; it records that
nothing was measured there.

## Deviating
Write .mavergreen/deviations/host/<label>/ with a scope (linux), a reason and a revisit. shipyard's reason is "bash32-parse needs a bash 3.2 /bin/sh and Linux has none"
and its revisit "the Apple-shells collection (bash 3.2 and the other shells Apple ships) has a Linux tarball." A good reason names the missing tool and the revisit the exit.

New in the flag day (filed 2026-10-14 from snow-leopard-vm)
