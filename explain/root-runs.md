root-runs: root runs a launch daemon or an install script only from a root-only chain.

## Why
Vision principle 6(a): root runs code (daemons, kexts, install scripts, the helper) only from a chain of
root-owned directories that no group or other can write. An admin can write /usr/local, /Users, /tmp,
/private/tmp, a home directory and /Applications, so a non-root process can replace anything root runs
from there. Every pkg is read three ways. A Library/LaunchDaemons plist's Program, or else its
ProgramArguments item 0, starts with /opt/mavergreen/, /bin/, /sbin/, /usr/bin/, /usr/sbin/,
/usr/libexec/ or /System/. Each component's preinstall and postinstall starts with #!/bin/sh or
#!/bin/bash. Neither script names /usr/local/, /Users/, /tmp/, /private/tmp/, $HOME, ${HOME, or
/Applications/ not followed by Mavergreen as a whole path component. Applications/Mavergreen is the
directory root creates for itself (principle 6(b)).

## Incident
2026-10-13: flavours-darkmode's payload directory was world-writable, a live root hole closed by hand
(vision, "Coordination").

## Limits
It reads the scripts as text, not as a shell parse. A path built at run time, such as one joined from
parts or read from a file, is not seen. A mention that is not a call, such as a comment or a message
naming /usr/local/, still fails. Only preinstall and postinstall are read, not other files in Scripts
that they run. A daemon is read only from a payload installed at /.

It does not read the owner or mode a payload gives its directories. stevedore forces uid and gid 0 but
copies each directory's mode from the staging tree, so a group-writable opt/mavergreen/<short>/sbin
ships as one. stevedore has no command that reports a payload's modes, so nothing here sees that.

Library/Application Support is itself root:admin 775. The generated preinstall refuses an ancestor below
it that is a symlink or not root-owned, but that parent stays admin-writable because the OS dictates it,
and root never runs from there.

## Deviating
Write .mavergreen/deviations/root-runs/<label>/ with a scope (<pkg file glob>), a reason and a revisit.
A good reason says why root must run from that place, and why no root-only chain can hold what it runs.

New in the flag day (P4, the install-layout plan's R7)
