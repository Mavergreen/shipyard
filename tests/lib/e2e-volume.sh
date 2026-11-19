# platform: macOS-only -- Installer, hdiutil and diskutil
#   usage: . tests/lib/e2e-volume.sh     (definitions only, no exit, $0 or set; the caller sets W, a work directory)
#          e2e_volume NAME        makes a fresh image W/MGE2E<pid>-NAME.dmg (HFS+ before 10.13, APFS after),
#                                 attaches it with ownership on, makes its root root:wheel 755, copies the
#                                 host's SystemVersion.plist in, and prints its mount point; a failure says why
#                                 on stderr and returns 1. Run it in $( ), so NAME must differ per call
#          e2e_volume_detach V    detaches the image whose mount point V e2e_volume printed, and removes it
#          e2e_detach_all         detaches every image e2e_volume made that is still attached
#          e2e_trap               on exit, detaches every image, fails the run if host_changed, and removes W
#          fresh_volume           makes the next numbered volume into VOL (n counts them); returns 1 on failure
#          drop_volume            detaches VOL
#          install_to PKG         installer -pkg PKG -target VOL into $_log (installer output plus the
#                                 install.log lines it wrote); returns installer's status
#          bad MSG...             prints FAIL MSG and the tail of $_log, and returns 1
#          host_state             prints the running system's Mavergreen receipts and paths
#          host_changed           1 when host_state differs from $HOST_BEFORE; otherwise prints what changed,
#                                 once, and returns 0. The caller sets HOST_BEFORE="$(host_state)" and HOST_REPORTED=""
host_state() {
  for _p in $(pkgutil --pkgs 2>/dev/null | grep '^dev\.mavergreen\.' | sort); do
    printf 'receipt %s %s\n' "$_p" "$(pkgutil --pkg-info "$_p" 2>/dev/null | grep -E '^(version|install-time):' | tr '\n' ' ')"
  done
  for _f in /opt/mavergreen /usr/local/mavergreen /usr/local/bin/mavergreen /etc/paths.d/mavergreen /etc/paths.d/mavergreen-opt /etc/manpaths.d/mavergreen /etc/manpaths.d/mavergreen-opt /Applications/Mavergreen /Library/LaunchAgents/dev.mavergreen.*; do
    if [ -e "$_f" ] || [ -L "$_f" ]; then ls -ldT "$_f"; else echo "absent $_f"; fi
  done
}
host_changed() {
  _now="$(host_state)"
  [ "$_now" != "$HOST_BEFORE" ] || return 1
  [ -n "$HOST_REPORTED" ] && return 0
  HOST_REPORTED=1
  echo "FAIL THE RUNNING SYSTEM CHANGED: its Mavergreen receipts or paths differ from before the run"
  echo "  before:"; printf '%s\n' "$HOST_BEFORE" | sed 's/^/    /'
  echo "  after:"; printf '%s\n' "$_now" | sed 's/^/    /'
}
e2e_volume() {
  _name="MGE2E$$-$1"
  case "$(sw_vers -productVersion)" in
    10.[0-9]|10.[0-9].*|10.1[0-2]|10.1[0-2].*) _fs=HFS+ ;;
    *) _fs=APFS ;;
  esac
  hdiutil create -quiet -size 600m -fs "$_fs" -volname "$_name" "$W/$_name.dmg" || return 1
  _out="$(hdiutil attach -nobrowse -owners on "$W/$_name.dmg")" || return 1
  _dev="$(printf '%s\n' "$_out" | sed -n '1s/[[:space:]].*//p')"
  _vol="$(printf '%s\n' "$_out" | sed -n 's|.*[[:space:]]\(/Volumes/[^[:space:]]*\)[[:space:]]*$|\1|p' | sed -n '$p')"
  case "$_dev" in
    /dev/disk[0-9]*) printf '%s\t%s\t%s\n' "$_dev" "$_vol" "$W/$_name.dmg" >> "$W/e2e-volumes" ;;
    *) echo "attach named no /dev/diskN: $_out" >&2; return 1 ;;
  esac
  [ "$_vol" = "/Volumes/$_name" ] || { echo "attach did not mount /Volumes/$_name: $_out" >&2; return 1; }
  _info="$(diskutil info "$_vol")" || return 1
  _d="${_dev#/dev/}"
  _whole="$(printf '%s\n' "$_info" | sed -n 's/^ *Part of Whole: *//p')"
  _store="$(printf '%s\n' "$_info" | sed -n 's/^ *APFS Physical Store: *//p')"
  case "$_whole" in "$_d") ;; *)
    case "$_store" in "${_d}s"[0-9]*) ;; *) echo "$_vol is on $_whole (store '$_store'), not the image's $_dev" >&2; return 1 ;; esac ;;
  esac
  if ! printf '%s\n' "$_info" | grep -q 'Owners:.*Enabled'; then
    diskutil enableOwnership "$_vol" >/dev/null || return 1
    diskutil info "$_vol" | grep -q 'Owners:.*Enabled' || { echo "ownership is still off on $_vol" >&2; return 1; }
  fi
  mkdir "$_vol/.e2e-owner-probe" && chown 1:1 "$_vol/.e2e-owner-probe" || return 1
  [ "$(stat -f %u:%g "$_vol/.e2e-owner-probe")" = 1:1 ] \
    || { echo "$_vol does not honor ownership: a chown 1:1 reads back $(stat -f %u:%g "$_vol/.e2e-owner-probe")" >&2; return 1; }
  rmdir "$_vol/.e2e-owner-probe" || return 1
  chown root:wheel "$_vol" && chmod 755 "$_vol" || return 1
  [ "$(stat -f '%u:%g %Lp' "$_vol")" = "0:0 755" ] || { echo "$_vol is $(stat -f '%u:%g %Lp' "$_vol"), not 0:0 755: ownership is not honored" >&2; return 1; }
  mkdir -p "$_vol/System/Library/CoreServices" || return 1
  cp /System/Library/CoreServices/SystemVersion.plist "$_vol/System/Library/CoreServices/" || return 1
  printf '%s\n' "$_vol"
}
e2e_volume_detach() {
  _tab="$(printf '\t')"
  [ -f "$W/e2e-volumes" ] || return 0
  _ed="$(awk -F "$_tab" -v v="$1" '$2 == v { print $1; exit }' "$W/e2e-volumes")"
  [ -n "$_ed" ] || return 0
  hdiutil detach -quiet "$_ed" 2>/dev/null || hdiutil detach -quiet -force "$_ed" || return 1
  awk -F "$_tab" -v v="$1" '$2 != v' "$W/e2e-volumes" > "$W/e2e-volumes.new" && mv "$W/e2e-volumes.new" "$W/e2e-volumes"
  rm -f "$W/${1#/Volumes/}.dmg"
}
e2e_detach_all() {
  _tab="$(printf '\t')"
  [ -f "$W/e2e-volumes" ] || return 0
  while IFS="$_tab" read -r _ed _ev _ef; do
    hdiutil detach -quiet "$_ed" 2>/dev/null || hdiutil detach -quiet -force "$_ed" 2>/dev/null || true
  done < "$W/e2e-volumes"
  : > "$W/e2e-volumes"
}
e2e_cleanup() {
  _rc=$?
  e2e_detach_all
  if host_changed; then _rc=1; fi
  rm -rf "$W"
  exit "$_rc"
}
e2e_trap() {
  trap e2e_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}
fresh_volume() {
  n=$(( ${n:-0} + 1 ))
  VOL="$(e2e_volume "$n")"
}
drop_volume() {
  e2e_volume_detach "$VOL"
}
install_to() {
  _log="$W/install-$n-$(basename "$1").log"
  _off="$(wc -c < /var/log/install.log 2>/dev/null | tr -d ' ')" || _off=0
  _rc=0; installer -verbose -dumplog -pkg "$1" -target "$VOL" > "$_log" 2>&1 || _rc=$?
  tail -c +"$((${_off:-0} + 1))" /var/log/install.log >> "$_log" 2>/dev/null || :
  return "$_rc"
}
bad() { echo "    FAIL: $*"; [ -z "${_log:-}" ] || { echo "    last installer log ($_log), tail:"; tail -n 40 "$_log" | sed 's/^/    | /'; }; return 1; }
