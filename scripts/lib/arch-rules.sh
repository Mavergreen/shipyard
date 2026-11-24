#!/bin/sh
# platform: host-agnostic
#   usage: . arch-rules.sh     (after lib/vercmp.sh; definitions only, no exit, $0 or set)
#          arch_is_target REL GLOBSFILE   0 when REL, relative to the product tree, matches a line of
#                                         GLOBSFILE as a case pattern
#          arch_derive                    reads "<path> <arch> <minos>" host-slice lines (path %20-encoded)
#                                         and prints "class <neutral|x86_64|universal>" then
#                                         "arm64-floor <V|none>"; 1, a message on stderr, for an arm64 slice
#                                         with no minimum OS or a host file with arm64 and no x86_64
#          arch_rule CLASS NEWER FLOOR ARM64FLOOR           prints none, intel, intel-newer or
#                                         "arm64-below V"; 1 for universal without newer-macos
#          arch_distribution CLASS NEWER FLOOR ARM64FLOOR   prints the allowed-os-versions element and,
#                                         with a rule, the installation-check and script, unindented
#          arch_requires_line CLASS NEWER FLOOR ARM64FLOOR  prints the release notes' <range>
#          arch_read_distribution FILE    prints "<hostArchitectures|none> <before|none> <rule>" for a
#                                         Distribution, its rule none (no installation-check), intel,
#                                         intel-newer, arm64-below:V or nonstandard (none of arch_distribution's)

arch_is_target() {
  [ -f "$2" ] || return 1
  while read -r arch_g || [ -n "$arch_g" ]; do
    [ -n "$arch_g" ] || continue
    case "$1" in $arch_g) return 0;; esac
  done < "$2"
  return 1
}

arch_derive() {
  arch_out="$(LC_ALL=C awk '
    { any = 1; arm = ($2 == "arm64" || $2 == "arm64e")
      if ($2 == "x86_64") x[$1] = 1
      if (arm) { if (!($1 in a)) order[++n] = $1; a[$1] = 1
        if ($3 == "-" || $3 == "?") bad = bad == "" ? $1 : bad
        else print "M " $3 } }
    END {
      if (bad != "") { print "E1 " bad; exit }
      for (i = 1; i <= n; i++) if (!(order[i] in x)) { print "E2 " order[i]; exit }
      print "C " (n > 0 ? "universal" : any ? "x86_64" : "neutral") }')"
  arch_class=neutral
  arch_max=
  while read -r arch_k arch_v; do
    case "$arch_k" in
      E1) echo "$arch_v: arm64 slice records no minimum OS, so the arm64 floor cannot be derived" >&2; return 1;;
      E2) echo "$arch_v is arm64 only; a host binary carries x86_64, and arm64 only beside it" >&2; return 1;;
      C) arch_class="$arch_v";;
      M) if [ -z "$arch_max" ] || [ "$(mavergreen_vercmp "$arch_v" "$arch_max")" = 1 ]; then arch_max="$arch_v"; fi;;
    esac
  done <<EOF2
$arch_out
EOF2
  case "$arch_max" in
    '') arch_max=none;;
    *.*) ;;
    *) arch_max="$arch_max.0";;
  esac
  printf 'class %s\narm64-floor %s\n' "$arch_class" "$arch_max"
}

arch_rule() {
  case "$1" in
    neutral) echo none;;
    x86_64) case "$2" in yes) echo intel-newer;; *) echo intel;; esac;;
    universal) [ "$2" = yes ] || return 1; echo "arm64-below $4";;
    *) return 1;;
  esac
}

arch_distribution() {
  arch_r="$(arch_rule "$1" "$2" "$3" "$4")" || return 1
  case "$1:$2" in
    universal:*|*:yes) arch_before=;;
    *) arch_before=' before="10.11"';;
  esac
  printf '<allowed-os-versions><os-version min="%s"%s/></allowed-os-versions>\n' "$3" "$arch_before"
  [ "$arch_r" != none ] || return 0
  arch_cond="system.sysctl('hw.optional.arm64') == 1"
  case "$arch_r" in
    intel) arch_title='Built for Intel Macs'; arch_msg='This package is built for Intel Macs running Mac OS X 10.9 or 10.10.';;
    intel-newer) arch_title='Built for Intel Macs'; arch_msg='This package is built for Intel Macs.';;
    arm64-below*)
      arch_cond="$arch_cond && system.compareVersions(system.version.ProductVersion, '$4') < 0"
      arch_title='Needs a newer macOS'; arch_msg="On Apple Silicon this package needs macOS $4 or later.";;
  esac
  cat <<EOF2
<installation-check script="mavergreen_arch()"/>
<script><![CDATA[
function mavergreen_arch() {
if ($arch_cond) {
my.result.type = 'Fatal';
my.result.title = '$arch_title';
my.result.message = '$arch_msg';
return false;
}
return true;
}
]]></script>
EOF2
}

arch_requires_line() {
  case "$1:$2" in
    universal:*) echo "Mac OS X $3 or later; on Apple Silicon, macOS $4 or later";;
    x86_64:yes) echo "an Intel Mac with Mac OS X $3 or later";;
    neutral:yes) echo "Mac OS X $3 or later";;
    *) echo "Mac OS X $3 through 10.10";;
  esac
}

arch_read_distribution() {
  arch_rd_host="$(sed -n 's/.*<options[^>]*[[:space:]]hostArchitectures="\([^"]*\)".*/\1/p' "$1" | head -n 1 | sed 's/[[:space:]][[:space:]]*/_/g')"
  arch_rd_before="$(sed -n 's/.*<os-version[^>]*[[:space:]]before="\([^"]*\)".*/\1/p' "$1" | head -n 1 | sed 's/[[:space:]][[:space:]]*/_/g')"
  arch_rd_run="$(sed 's/^[[:space:]]*//' "$1" | LC_ALL=C awk '
    /^<installation-check / { on = 1 }
    !on { next }
    /^<script>$/ { print "<script><![CDATA["; s = 1; next }
    /^<\/script>$/ { print "]]></script>"; exit }
    /^\]\]><\/script>$/ { print; exit }
    s { gsub(/&lt;/, "<"); gsub(/&gt;/, ">"); gsub(/&amp;/, "\\&") }
    { print }')"
  arch_rd_rule=none
  if [ -n "$arch_rd_run" ]; then
    arch_rd_rule=nonstandard
    arch_rd_v="$(printf '%s\n' "$arch_rd_run" | sed -n "s/.*system\.compareVersions(system\.version\.ProductVersion, '\([0-9][0-9.]*\)') < 0.*/\1/p" | head -n 1)"
    if [ "$arch_rd_run" = "$(arch_distribution x86_64 no 10.9.5 none | sed 1d)" ]; then arch_rd_rule=intel
    elif [ "$arch_rd_run" = "$(arch_distribution x86_64 yes 10.9.5 none | sed 1d)" ]; then arch_rd_rule=intel-newer
    elif [ -n "$arch_rd_v" ] && [ "$arch_rd_run" = "$(arch_distribution universal yes 10.9.5 "$arch_rd_v" | sed 1d)" ]; then
      arch_rd_rule="arm64-below:$arch_rd_v"
    fi
  fi
  printf '%s %s %s\n' "${arch_rd_host:-none}" "${arch_rd_before:-none}" "$arch_rd_rule"
}
