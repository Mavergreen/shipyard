os-overwrite: a regular product only adds files to Mac OS X 10.9.5, and never replaces one the OS ships.

## Why
A regular product that replaces an OS file is a system package by another name. Vision area 15 draws
the boundary: a system package replaces files the OS ships, and a regular product may only add new
files, in its own tree or in the places the OS dictates. Installing over an OS file breaks the OS in
ways nobody tests, a Software Update can put the old file back, and uninstalling cannot restore what
was there. Every file a regular product's pkg installs is looked up in scripts/os-inventory-10.9.5.gz,
the paths 10.9.5's own receipts list, and one that is there fails. A directory the OS ships may still
gain a file: only an exact path is matched.

A pkg is a system edition's, and is not read, when its identifier ends in .system-replace (the System
Replace pkg, which package-system-replace.sh builds) or is the derived identifier of a product whose
.mavergreen/products/<short>/edition says system. Every other pkg is a regular product's. An inventory
that is missing, empty or unreadable fails the check rather than passing it.

## Incident
2026-10-13: the vision's area 15 set the boundary between a system package and a regular product, and
said it is checked against the 10.9 file inventory. Until then nothing compared what a pkg installs
with what the OS ships.

## Limits
The inventory was made on one 10.9.5 Mac, build 13F1911, by gen-os-inventory.sh: 427149 paths, files
and directories, from every com.apple.pkg.*.bom in /var/db/receipts. That Mac carries Apple packages a
fresh install lacks, such as the Command Line Tools, Java, Safari 9, iTunes, a printer driver, the
2016-004 security update and two downloaded OS installer apps, so their paths count as shipped too.
A file Apple installs without a receipt, or one the OS writes at run time, is not in it.

Only 10.9.5 is read. A file that a later macOS ships, and 10.9.5 does not, passes.

The match is on the path as the payload names it, not as the disk resolves it. etc, tmp and var are
links into private, so a payload's etc/aliases is not matched with the inventory's
private/etc/aliases.

## Deviating
Write .mavergreen/deviations/os-overwrite/<label>/ with a scope (<installed path glob>), a reason and a
revisit. A good reason says why the product must replace that OS file rather than add its own, and why
it cannot be a system edition. As with install-path, a scope of * excuses every path a pkg installs, and
a deviation with no reason excuses nothing.

New in the flag day (P4, the install-layout plan's Q6)
