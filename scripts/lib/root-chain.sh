# platform: host-agnostic
# spec: tests/root-chain-test.sh -- the root-only chain (decision 2), definitions only (no exit, $0 or set),
#       so every pre/postinstall and the stamped helper carry it inline in place of their source line.

mavergreen_chain_judge() (
  LC_ALL=C; export LC_ALL
  awk -v uid="${MAVERGREEN_CHAIN_UID:-0}" '
    NR == 1 {
      if (length($1) < 10 || $3 !~ /^[0-9]+$/) bad = 1
      else if ($3 != uid) r = "owner"
      else if (substr($1, 6, 1) == "w") r = "group-writable"
      else if (substr($1, 9, 1) == "w") r = "other-writable"
      next
    }
    !/^ *[0-9]+: .* (allow|deny) [^ ]+$/ { bad = 1; next }
    r == "" && $(NF - 1) == "allow" {
      n = split($NF, p, ",")
      for (k = 1; k <= n; k++)
        if (p[k] ~ /^(write|append|add_file|add_subdirectory|delete_child|delete|writesecurity|chown)$/) {
          r = "acl-write"; i = $1; sub(/:$/, "", i)
        }
    }
    END {
      if (NR == 0 || bad) r = "unreadable"
      print (r == "" ? "ok" : r)
      if (r == "acl-write") print i
    }'
)

mavergreen_chain_verdict() (
  mavergreen_chain_judge | sed -n 1p
)

mavergreen_chain_q() (
  printf "'%s'" "$(printf '%s\n' "$1" | sed "s/'/'\\\\''/g")"
)

mavergreen_chain_say() (
  printf '%s: %s; root will not write or run here; fix: %s\n' "$1" "$2" "$3" >&2
)

mavergreen_chain_in() (
  [ "$2" = / ] && return 0
  case "$1/" in "$2"/*) return 0 ;; esac
  return 1
)

mavergreen_chain_above() (
  [ "$1" = / ] && return 0
  case "$2/" in "$1"/*) return 0 ;; esac
  return 1
)

# platform: only Darwin's ls has -e, which lists the ACL entries under the line.
mavergreen_chain_ls() (
  LC_ALL=C; export LC_ALL
  case "$(uname -s)" in Darwin) ls -ldne -- "$1" ;; *) ls -ldn -- "$1" ;; esac
)

mavergreen_chain_one() (
  LC_ALL=C; export LC_ALL
  v="$(mavergreen_chain_ls "$1" 2>/dev/null | mavergreen_chain_judge)"
  r="$(printf '%s\n' "$v" | sed -n 1p)"
  q="$(mavergreen_chain_q "$1")"
  case "$r" in
    ok) return 0 ;;
    owner)
      if [ "$1" = "$2" ]; then f="sudo diskutil enableOwnership $q"; else f="sudo chown root:wheel $q"; fi ;;
    group-writable|other-writable) f="sudo chmod go-w $q" ;;
    acl-write)
      i="$(printf '%s\n' "$v" | sed -n 2p)"
      e="$(ls -lde -- "$1" 2>/dev/null | awk -v i="$i" '
        /^ *[0-9]+: / { n = $1; sub(/:$/, "", n)
          if (n == i) { sub(/^ *[0-9]+: /, ""); sub(/ inherited /, " "); print; exit } }')"
      f="sudo chmod -a $(mavergreen_chain_q "$e") $q" ;;
    *) r=unreadable; f="sudo ls -lde $q" ;;
  esac
  mavergreen_chain_say "$1" "$r" "$f"
  return 1
)

mavergreen_chain_ok() (
  LC_ALL=C; export LC_ALL
  vol="$(cd -P -- "$2" 2>/dev/null && pwd -P)" \
    || { mavergreen_chain_say "$2" missing "name the target volume's root"; return 1; }
  case "$vol" in //*) vol="/${vol#"${vol%%[!/]*}"}" ;; esac
  out="install under $(mavergreen_chain_q "$vol")"
  case "$1" in /*) rest="$1" ;; *) rest="$(pwd -P)/$1" ;; esac
  cur=/; seen=0; fresh=1; n=0
  while :; do
    if [ "$fresh" = 1 ]; then
      fresh=0
      if mavergreen_chain_in "$cur" "$vol"; then
        [ "$cur" != "$vol" ] || seen=1
        mavergreen_chain_one "$cur" "$vol" || return 1
      elif [ "$seen" = 1 ] && ! mavergreen_chain_above "$cur" "$vol"; then
        mavergreen_chain_say "$cur" "outside $vol" "$out"; return 1
      fi
    fi
    rest="${rest#"${rest%%[!/]*}"}"
    [ -n "$rest" ] || break
    c="${rest%%/*}"; rest="${rest#"$c"}"
    case "$c" in
      .) continue ;;
      ..) cur="$(dirname -- "$cur")"; fresh=1; continue ;;
    esac
    case "$cur" in /) next="/$c" ;; *) next="$cur/$c" ;; esac
    if [ -L "$next" ]; then
      if [ "$seen" = 1 ] && ! mavergreen_chain_in "$cur" "$vol"; then
        mavergreen_chain_say "$next" "outside $vol" "$out"; return 1
      fi
      n=$((n + 1))
      [ "$n" -le 32 ] || { mavergreen_chain_say "$1" "symlink loop" "sudo rm $(mavergreen_chain_q "$1")"; return 1; }
      t="$(readlink "$next")" || { mavergreen_chain_say "$next" unreadable "sudo ls -l $(mavergreen_chain_q "$next")"; return 1; }
      case "$t" in /*) cur=/; fresh=1 ;; esac
      rest="$t$rest"
      continue
    fi
    if [ -d "$next" ]; then cur="$next"; fresh=1; continue; fi
    if [ -n "${rest#"${rest%%[!/]*}"}" ]; then
      if [ -e "$next" ]; then
        mavergreen_chain_say "$next" "not a directory" "sudo mv $(mavergreen_chain_q "$next") $(mavergreen_chain_q "$next.old")"
      else
        mavergreen_chain_say "$next" missing "sudo mkdir -m 755 $(mavergreen_chain_q "$next")"
      fi
      return 1
    fi
    if [ -e "$next" ] && mavergreen_chain_in "$cur" "$vol"; then mavergreen_chain_one "$next" "$vol" || return 1; fi
    break
  done
  mavergreen_chain_in "$cur" "$vol" || { mavergreen_chain_say "$1" "outside $vol" "$out"; return 1; }
)

mavergreen_dir_ok() (
  LC_ALL=C; export LC_ALL
  q="$(mavergreen_chain_q "$1")"
  if [ -L "$1" ]; then mavergreen_chain_say "$1" symlink "sudo mv $q $(mavergreen_chain_q "$1.old")"; return 1; fi
  [ -e "$1" ] || { mavergreen_chain_say "$1" missing "sudo mkdir -m 755 $q"; return 1; }
  [ -d "$1" ] || { mavergreen_chain_say "$1" "not a directory" "sudo mv $q $(mavergreen_chain_q "$1.old")"; return 1; }
  mavergreen_chain_one "$1" ""
)

mavergreen_root_dir() (
  LC_ALL=C; export LC_ALL
  u="${MAVERGREEN_CHAIN_UID:-0}"
  if [ ! -e "$1" ] && [ ! -L "$1" ] && mkdir -m 755 "$1" 2>/dev/null; then
    if [ "$u" = 0 ]; then chown -h 0:0 "$1"; else chown -h "$u" "$1"; fi 2>/dev/null
  fi
  mavergreen_dir_ok "$1"
)
