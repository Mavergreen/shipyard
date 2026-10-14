manifest: a pkg that installs a product carries exactly one valid manifest, and installs only what it lists.

## Why
Anything that wants to know what is installed (the helper, conformance, uninstall) globs
/usr/local/mavergreen/*/mavergreen.plist, so a pkg without a manifest is invisible to all of them, and a file
installed outside the product's tree that the manifest's outside list does not name is left behind by
uninstall. The check requires: exactly one manifest per pkg that installs anything besides the base's staged
helper; its product equal to its directory; its identifier the one the registry gives that product and one
of the pkg's components; its outside list naming every file installed outside the tree, exactly as
uninstall would remove it (the entry, or a bundle directory and what is inside it), with no entry left
unused and none in a shape the helper refuses; and every generated entry in a shape the helper accepts.
stage_product.sh writes the manifest; never write it by hand.

## Incident
None recorded.

## Limits
A manifest is read only from a component installed at "/", since a product tree always is. Reports are
capped, so a pkg with many offenders shows the first and a count. It checks the manifest against the
payload and the registry; the helper's behaviour is tested separately.

## Deviating
Write "- manifest:<pkg file glob>: <reason>". Rarely warranted: a hand-rolled pkg that cannot use
stage_product.sh says why and when it will. The stage-product check is its repo-side companion.

Formerly the conformance rule manifest
