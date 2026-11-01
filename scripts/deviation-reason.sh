# platform: host-agnostic
#   usage: . deviation-reason.sh     (sourced; $SELF or $SHIPYARD_CHECK_DIR names the scripts directory)
#          shipyard_deviations [<repo root | INGREDIENTS.md> | -]
#                                                        loads that repo's deviations (default .; "-" reads fact
#                                                        lines on stdin) into $SHIPYARD_DEVIATION_FACTS, once per
#                                                        root, prints them, and returns deviations.sh's status
#                                                        with its refusals on stderr
#          shipyard_deviated <check> [<subject>]         prints the reason the loaded deviations give to excuse
#                                                        <check> for <subject>, or returns 1
#          shipyard_deviation_scopes <check>             prints that check's scopes, one per line, * for unscoped
#          Under those, the matcher:
#          shipyard_deviation_facts                      stdin: deviations.sh's "<check> <glob or *> <reason>"
#                                                        lines; stdout: one fact line per deviation,
#                                                        "deviation <check> <reason>" when unscoped,
#                                                        "deviation <check>:<glob> <reason>" when scoped
#          shipyard_deviation_reason <facts> <check> [<subject>]
#                                                        prints the reason a deviation in <facts> (a file of
#                                                        those lines) gives to excuse <check> for
#                                                        <subject>; prints nothing when none does
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Conformance deviations" and
#       "SDK pinning" -- ONE matcher, because check-artifact-conformance.sh (package time) and
#       assert_binary_compatible.sh (build time) must excuse exactly the same files: an unscoped
#       deviation excuses its check for every subject; a scoped one excuses a subject its glob
#       matches as a shell `case` pattern, where `*` spans "/" and spaces, the first match with a
#       reason winning; and a glob with no reason excuses nothing.

shipyard_deviation_facts() {
  while read -r _mdf_check _mdf_glob _mdf_reason; do
    [ -n "$_mdf_check" ] || continue
    if [ "$_mdf_glob" = '*' ]; then printf 'deviation %s %s\n' "$_mdf_check" "$_mdf_reason"
    else printf 'deviation %s:%s %s\n' "$_mdf_check" "$_mdf_glob" "$_mdf_reason"; fi
  done
}

_shipyard_deviation_match() {  # stdin = facts, $1 = check, $2 = the subject it concerns (optional)
  _sdm_facts="$(cat)"
  _mdr="$(printf '%s\n' "$_sdm_facts" | sed -n "s/^deviation ${1} \(..*\)$/\1/p" | head -1)"
  if [ -z "$_mdr" ] && [ -n "${2:-}" ]; then
    while IFS= read -r _mdr_line; do
      _mdr_rest="${_mdr_line#deviation ${1}:}"
      _mdr_glob="${_mdr_rest%% *}"
      _mdr_why="${_mdr_rest#* }"
      [ "$_mdr_why" = "$_mdr_rest" ] && _mdr_why=""      # no space => a glob with no reason, which is not a deviation
      case "$2" in
        $_mdr_glob) [ -n "$_mdr_why" ] && _mdr="$_mdr_why" && break ;;
      esac
    done <<EOF
$(printf '%s\n' "$_sdm_facts" | grep "^deviation ${1}:" || true)
EOF
  fi
  printf '%s' "$_mdr"
}

shipyard_deviation_reason() {  # $1 = facts file, $2 = check, $3 = the subject it concerns (optional)
  _shipyard_deviation_match "$2" "${3:-}" < "$1"
}

shipyard_deviations() {  # $1 = a repo root or its INGREDIENTS.md, or "-" for fact lines on stdin
  _sd_root="${1:-.}"
  _sd_rc=0; _sd_err=""
  case "$_sd_root" in
    -) _sd_facts="$(grep '^deviation ' || true)" ;;
    *)
      case "$_sd_root" in *INGREDIENTS.md) _sd_root="$(dirname "$_sd_root")" ;; esac
      if [ "${SHIPYARD_DEVIATION_ROOT:-}" = "$_sd_root" ] && [ -n "${SHIPYARD_DEVIATION_RC+x}" ]; then
        [ -z "$SHIPYARD_DEVIATION_FACTS" ] || printf '%s\n' "$SHIPYARD_DEVIATION_FACTS"
        return "$SHIPYARD_DEVIATION_RC"
      fi
      _sd_out="$(sh "${SELF:-${SHIPYARD_CHECK_DIR:-.}}/deviations.sh" "$_sd_root" 2>&1)" || _sd_rc=$?
      _sd_err="$(printf '%s\n' "$_sd_out" | grep '^deviations\.sh: ' || true)"
      _sd_facts="$(printf '%s\n' "$_sd_out" | grep -v '^deviations\.sh: ' | shipyard_deviation_facts)"
      ;;
  esac
  SHIPYARD_DEVIATION_ROOT="$_sd_root"; SHIPYARD_DEVIATION_FACTS="$_sd_facts"; SHIPYARD_DEVIATION_RC="$_sd_rc"
  [ -z "$_sd_err" ] || printf '%s\n' "$_sd_err" >&2
  [ -z "$_sd_facts" ] || printf '%s\n' "$_sd_facts"
  return "$_sd_rc"
}

shipyard_deviated() {  # $1 = check, $2 = the subject it concerns (optional)
  [ -n "${SHIPYARD_DEVIATION_RC+x}" ] || shipyard_deviations . >/dev/null 2>&1 || :
  _sdd_reason="$(printf '%s\n' "$SHIPYARD_DEVIATION_FACTS" | _shipyard_deviation_match "$1" "${2:-}")"
  [ -n "$_sdd_reason" ] || return 1
  printf '%s\n' "$_sdd_reason"
}

shipyard_deviation_scopes() {  # $1 = check; one scope per line, * for an unscoped deviation
  [ -n "${SHIPYARD_DEVIATION_RC+x}" ] || shipyard_deviations . >/dev/null 2>&1 || :
  printf '%s\n' "$SHIPYARD_DEVIATION_FACTS" \
    | sed -n -e "s/^deviation ${1}\$/*/p" -e "s/^deviation ${1} .*\$/*/p" -e "s/^deviation ${1}:\([^ ]*\).*\$/\1/p"
}
