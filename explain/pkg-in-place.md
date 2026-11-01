pkg-in-place: a built pkg installs in place and always overwrites.

## Why
Two install-time footguns that pkgbuild enables by default and build_component_pkg.sh disables: a relocatable
bundle (Installer may install it at a path it finds elsewhere on the disk, instead of the declared one) and a
version-checked bundle (Installer skips overwriting a bundle it believes is newer). Every other check in the
family verifies that artifacts agree with each other; none exercised what the installer does on a machine that
already has the previous version. The check reads PackageInfo from each component of each pkg: no bundle may
appear under the relocate element or under bundle-version. Both were verified against real pkgbuild output on
2026-07-31: the pkg-info root's relocatable="false" attribute is a red herring (pkgbuild emits it even for a
relocatable component); the membership of the relocate element is the operative signal. It reads PackageInfo
with bsdtar on every host, so it needs neither pkgutil nor a Mac.

## Incident
None recorded. The script's header says only that the gate keeps a regression from "being discovered live on
a user's machine, weeks later, one product at a time"; no date or product is recorded.

## Limits
It reads what the pkg declares in PackageInfo, not what Installer then does. A pkg with no PackageInfo fails.
It needs stevedore, which fetch_stevedore.sh fetches at its pinned version, and a readable xar.

## Deviating
No deviation is read for this id. Build the component with build_component_pkg.sh, which disables both.

Formerly assert_pkg_installs_in_place.sh
