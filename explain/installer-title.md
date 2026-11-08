installer-title: a product's Installer title is the one derived from the product.

## Why
The Installer window title is Mavergreen <name>, where the name is the product's noun, then its line if it has one. Hand-chosen titles drifted: versions, em-dash taglines and whole sentences, so the window named the product differently from its Release, its feed and its manifest. A System Replace pkg is titled Mavergreen <name> System Replace.

## Incident
2026-10-13: the names survey found Installer titles carrying versions, taglines, short names and "Make OpenSSH for Mavericks the system default".

## Limits
It reads the <title> of a product archive's Distribution, with its XML entities decoded. A component package has no Distribution and no title; the base check fails a product shipped that way.

## Deviating
Write .mavergreen/deviations/installer-title/<label>/ with a scope (<pkg file glob>), a reason and a revisit. A good reason says why the window must show another title.

New in the flag day (P3, the names spec's Checks)
