product-complete: every product directory has a noun, a short name the name rules allow, known app and edition values, and a kind and a why for each requirement, with a where for an external one.

## Why
A product's directory under .mavergreen/products/ is where its names, its install layout and its requirements
come from, so a gap in it is a gap in every one of those. The short name becomes a directory under the prefix
and part of the pkg identifier, so it is lowercase ASCII letters, digits and hyphens, never starting with a
hyphen, and never one the install layout reserves: var, bin, sbin, share, mavergreen, system-replace or base.
app is noun or upstream and edition is system, because the code that names the bundle and picks the edition
knows only those. Each requirement says what kind of thing it is and why the product needs it, and an
external one, which the Engine never installs, says in where what the preinstall tells the user.

## Incident
None recorded.

## Limits
It reads the directories, not what they describe: it does not check that a noun is the product's real name,
or that a where names a place that exists. The name rules are product-name.sh's, from one shared file.

## Deviating
No deviation is read for this id. Add the missing file, correct the value, or rename the directory.

New in the flag day (P2, replacing the name rules product-name.sh check applied to the registry)
