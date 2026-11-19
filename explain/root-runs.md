root-runs: root runs a launch daemon or an install script only from a root-only chain.

## Why
Vision principle 6(a): root runs code (daemons, kexts, install scripts, the helper) only from a chain of
root-owned directories that no group or other can write. An admin can write /usr/local, /Users, /tmp,
/private/tmp, a home directory and /Applications, so a non-root process can replace anything root runs
from there. Every pkg is read three ways. A Library/LaunchDaemons plist's Program, or else its
ProgramArguments item 0, starts with /opt/mavergreen/, /bin/, /sbin/, /usr/bin/, /usr/sbin/,
/usr/libexec/ or /System/. Each component's preinstall and postinstall starts with #!/bin/sh or
#!/bin/bash. Neither script names /usr/local, /Users, /tmp, /private/tmp or /Applications, in any
case (HFS+ and APFS ignore it), each ending at a /, a quote, a space, a tab, a newline, ;, ), &, |, },
<, >, a backtick or the end of the script. /Applications passes only as /Applications/Mavergreen, a whole path component
with no .. after it: Applications/Mavergreen is the directory root creates for itself (principle 6(b)).
Nor does either script name $HOME, ${HOME, ~/, or a ~ that starts a word or follows = or : (an
assignment's value, which the shell expands too) and ends its command, all of which are a home
directory.
Every payload entry on the way to or under opt/mavergreen/ and Applications/Mavergreen/ (the payload's
root, opt, opt/mavergreen, Applications, Applications/Mavergreen and everything below the two) is owned
0:0 and grants no group or other write; a link's own mode is not judged. The modes are read from the
payload's cpio listing (BSD and GNU cpio -tvn), whatever built the pkg.

## Incident
2026-10-13: flavours-darkmode's payload directory was world-writable, a live root hole closed by hand
(vision, "Coordination").

## Limits
It reads the scripts as text, not as a shell parse. A path built at run time, such as one joined from
parts or read from a file, is not seen; nor is a root followed by another character, such as /tmp*, nor
~user, nor a ~ followed by another word, which reads like awk's match operator. awk's ~/re/, with no
space, still fails, because it reads like ~/. A mention that is not a
call, such as a comment or a message naming /usr/local, still fails, and so does /var/tmp or
/System/Applications, which contain a root. Only preinstall and postinstall are read, not other files in Scripts
that they run. A daemon is read only from a payload installed at /.

stevedore forces uid and gid 0 but copies each entry's mode from the staging tree, so a group-writable
opt/mavergreen/<short>/sbin ships as one. scripts/build_component_pkg.sh strips group and other write
from the staged tree before it packs; a pkg built any other way is caught here by its payload's modes.
It reads what a pkg ships, not what a box holds: a directory made writable after the install is not
seen here. mavergreen check judges each product tree's own chain but not what is below it; the helper
judges a pre-uninstall hook's whole chain before it runs one.

Library/Application Support is itself root:admin 775. The generated preinstall refuses an ancestor below
it that is a symlink or not root-owned, but that parent stays admin-writable because the OS dictates it,
and root never runs from there.

## Deviating
Write .mavergreen/deviations/root-runs/<label>/ with a scope (<pkg file glob>), a reason and a revisit.
A good reason says why root must run from that place, and why no root-only chain can hold what it runs.

New in the flag day (P4, the install-layout plan's R7)
