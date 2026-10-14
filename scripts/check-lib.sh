#!/bin/sh
# platform: host-agnostic
chk_status=0
: "${SHIPYARD_CHECK_DIR:=$(cd "$(dirname "$0")" && pwd)}"
: "${SHIPYARD_CHECK_REGISTRY:=$SHIPYARD_CHECK_DIR/check-ids.tsv}"

chk_registered() {
  cut -f1 "$SHIPYARD_CHECK_REGISTRY" | grep -qx "$1"
}

chk_fail() {
  _cf_id="$1"; _cf_rule="${2%.}"; _cf_why="${3%.}"; _cf_fix="$4"
  if ! chk_registered "$_cf_id"; then
    echo "check-lib: '$_cf_id' is not in check-ids.tsv -- register it before failing it" >&2
    exit 2
  fi
  printf '%s: %s. %s.\n  fix: %s\n  more: shipyard-check --explain %s\n' \
    "$_cf_id" "$_cf_rule" "$_cf_why" "$_cf_fix" "$_cf_id" >&2
  [ -z "${SHIPYARD_CHECK_FAILLOG:-}" ] || echo "$_cf_id" >> "$SHIPYARD_CHECK_FAILLOG"
  chk_status=1
}

chk_ran() {
  [ -z "${SHIPYARD_CHECK_RUNLOG:-}" ] || echo "$1" >> "$SHIPYARD_CHECK_RUNLOG"
}

chk_notrun() {
  printf '%s: not run: %s\n' "$1" "$2"
  [ -z "${SHIPYARD_CHECK_NOTRUNLOG:-}" ] || echo "$1" >> "$SHIPYARD_CHECK_NOTRUNLOG"
}

chk_tracked_files() {
  if [ -n "${SHIPYARD_CHECK_FILES:-}" ]; then
    cat "$SHIPYARD_CHECK_FILES"
  elif git ls-files 2>/dev/null; then
    :
  else
    chk_fail tracked-files "the tracked-file list couldn't be read" \
      "this is not a git checkout and SHIPYARD_CHECK_FILES is not set" \
      "run in a git checkout, or set SHIPYARD_CHECK_FILES to a file listing the tracked paths"
    return 1
  fi
}

chk_deviated() {
  _cd_facts="${SHIPYARD_CHECK_DEVIATION_FACTS:-}"
  [ -n "$_cd_facts" ] && [ -f "$_cd_facts" ] || return 1
  . "$SHIPYARD_CHECK_DIR/deviation-reason.sh"
  _cd_reason="$(mav_deviation_reason "$_cd_facts" "$1" "${2:-}")"
  [ -n "$_cd_reason" ] || return 1
  printf '%s\n' "$_cd_reason"
}

chk_shell_scripts() {
  while IFS= read -r _ss_f; do
    [ -f "$_ss_f" ] || continue
    case "${_ss_f##*/}" in
      *.sh) printf '%s\n' "$_ss_f" ;;
      *.*) ;;
      *) head -n 1 "$_ss_f" 2>/dev/null | grep -Eq '^#!(/bin/sh|/bin/bash|/usr/bin/env (ba)?sh)([[:space:]]|$)' && printf '%s\n' "$_ss_f" || : ;;
    esac
  done
}
