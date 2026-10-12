#!/bin/sh
# platform: macOS-only -- as root, on a Mac OS X 10.9 volume's own /usr/bin and /etc; it runs only in the throwaway Mavergreen/mavericks-vm guest
#   usage: sudo env MAVERGREEN_E2E_GUEST=I-am-a-throwaway-vm sh tests/system-replace-mavericks.sh
#          The System Replace life cycle, end to end, through Installer on the guest's real /.
#          Exits 77 anywhere else: unless it is root, on 10.9, opted in, and in the mavericks-vm
#          guest (its vagrant account and its first-boot marker), it reads nothing else and changes nothing.
# spec: .github/workflows/system-replace-mavericks.yml
set -eu
# platform: sudo and a non-interactive ssh session each pick their own PATH, and installer and
#           pkgutil live in /usr/sbin, so root runs with 10.9's own system PATH.
PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib/system_replace_guest_gate.sh"
why="$(e2e_guest_gate)" || { echo "not the throwaway 10.9 guest: $why -- skipping"; exit 77; }
W="$(mktemp -d "${TMPDIR:-/tmp}/system-replace-mavericks.XXXXXX")"
E2E_MODE=guest; R=""; RUID=0
. "$here/lib/system_replace_flow.sh"
