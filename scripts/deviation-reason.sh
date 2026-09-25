# platform: host-agnostic
#   usage: . deviation-reason.sh     (sourced; defines the two functions below)
#          mav_deviation_facts                           stdin: deviations.sh's "<check> <glob or *> <reason>"
#                                                        lines; stdout: one fact line per deviation,
#                                                        "deviation <check> <reason>" when unscoped,
#                                                        "deviation <check>:<glob> <reason>" when scoped
#          mav_deviation_reason <facts> <check> [<subject>]
#                                                        prints the reason a deviation in <facts> (a file of
#                                                        those lines) gives to excuse <check> for
#                                                        <subject>; prints nothing when none does
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Conformance deviations" and
#       "SDK pinning" -- ONE matcher, because check-artifact-conformance.sh (package time) and
#       assert_binary_compatible.sh (build time) must excuse exactly the same files: an unscoped
#       deviation excuses its check for every subject; a scoped one excuses a subject its glob
#       matches as a shell `case` pattern, where `*` spans "/" and spaces, the first match with a
#       reason winning; and a glob with no reason excuses nothing.

mav_deviation_facts() {
  while read -r _mdf_check _mdf_glob _mdf_reason; do
    [ -n "$_mdf_check" ] || continue
    if [ "$_mdf_glob" = '*' ]; then printf 'deviation %s %s\n' "$_mdf_check" "$_mdf_reason"
    else printf 'deviation %s:%s %s\n' "$_mdf_check" "$_mdf_glob" "$_mdf_reason"; fi
  done
}

mav_deviation_reason() {  # $1 = facts file, $2 = check, $3 = the subject it concerns (optional)
  _mdr="$(sed -n "s/^deviation ${2} \(..*\)$/\1/p" "$1" | head -1)"
  if [ -z "$_mdr" ] && [ -n "${3:-}" ]; then
    while IFS= read -r _mdr_line; do
      _mdr_rest="${_mdr_line#deviation ${2}:}"
      _mdr_glob="${_mdr_rest%% *}"
      _mdr_why="${_mdr_rest#* }"
      [ "$_mdr_why" = "$_mdr_rest" ] && _mdr_why=""      # no space => a glob with no reason, which is not a deviation
      case "$3" in
        $_mdr_glob) [ -n "$_mdr_why" ] && _mdr="$_mdr_why" && break ;;
      esac
    done <<EOF
$(grep "^deviation ${2}:" "$1" || true)
EOF
  fi
  printf '%s' "$_mdr"
}
