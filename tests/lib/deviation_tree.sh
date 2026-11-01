# platform: host-agnostic
deviation() {
  _dv="$1/.mavergreen/deviations/$2/$3"
  mkdir -p "$_dv"
  printf '%s\n' "$4" > "$_dv/scope"
  printf '%s\n' "$5" > "$_dv/reason"
  printf '%s\n' "${6-the reason stops holding}" > "$_dv/revisit"
}
