preset-icon: a Porthole preset's vendor icon source still serves its icon.

## Why
A preset never ships its app's icon; it names where the user's Mac gets it: ICON_URL, a vendor-hosted PNG
fetched at install, and ICON_GLOB, the icon's path inside the vendor's package, extracted from the app's
container. Vendors move these. The check fails when ICON_URL stops serving a PNG, and when ICON_GLOB matches
nothing in the newest package named first in APT_PKGS from APT_REPO (checked only when APT_KEY_URL and
APT_REPO are set). Each preset repo calls preset-icons.yml@v1 on push and weekly, so a moved source turns a
run red between releases.

## Incident
None recorded.

## Limits
It needs the network, curl, dpkg and dpkg-deb, and exits 77 (skip) without the tools. It reads only apt
packages. The glob uses one path segment per "*", as the container's shell expands it. It reads the preset
from SHIPYARD_CHECK_PRESET_CONF.

## Deviating
No deviation is read for this id. Point ICON_URL or ICON_GLOB in the preset's conf at the vendor's current
location, or name the vendor's package first in APT_PKGS.

Formerly check-preset-icons.sh
