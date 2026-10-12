#!/bin/sh
# platform: macOS-only -- reads PlistBuddy, the local directory node and the mavericks-vm guest's first-boot marker
#   usage: . tests/lib/system_replace_guest_gate.sh; why="$(e2e_guest_gate)" || <refuse, saying $why>
#          Succeeds only as root, on 10.9, opted in, in the throwaway mavericks-vm guest; otherwise
#          prints the first unmet condition and returns 1. It only reads: env, id, PlistBuddy,
#          test -f and dscl.
# spec: tests/system-replace-mavericks.sh
e2e_guest_gate() {
  if [ "${MAVERGREEN_E2E_GUEST:-}" != I-am-a-throwaway-vm ]; then
    echo "MAVERGREEN_E2E_GUEST is not I-am-a-throwaway-vm (only .github/workflows/system-replace-mavericks.yml sets it)"
    return 1
  fi
  if [ "$(id -u)" != 0 ]; then echo "not root"; return 1; fi
  _gg_pv="$(/usr/libexec/PlistBuddy -c 'Print :ProductVersion' /System/Library/CoreServices/SystemVersion.plist 2>/dev/null)" || _gg_pv=""
  case "$_gg_pv" in 10.9|10.9.*) : ;; *) echo "this volume is ${_gg_pv:-unknown}, not 10.9"; return 1 ;; esac
  # spec: Mavergreen/packer-plugin-macosx templates/mavericks/verify.sh -- every mavericks-vm guest has
  #       the first-boot payload's marker (its build fails without it) and the vagrant account the
  #       box's Vagrantfile logs in as; a Mac someone uses has neither.
  if [ ! -f /private/var/db/.mqg-firstboot/.done ]; then
    echo "no mavericks-vm first-boot marker /private/var/db/.mqg-firstboot/.done"
    return 1
  fi
  if ! dscl . -read /Users/vagrant UniqueID >/dev/null 2>&1; then echo "no local vagrant account"; return 1; fi
  return 0
}
