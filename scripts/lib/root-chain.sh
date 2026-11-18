# platform: host-agnostic
# spec: tests/root-chain-test.sh -- the root-only chain (decision 2), definitions only (no exit, $0 or set),
#       so every pre/postinstall and the stamped helper carry it inline in place of their source line.

mavergreen_chain_judge() (
  LC_ALL=C; export LC_ALL
  awk -v uid="${MAVERGREEN_CHAIN_UID:-0}" '
    NR == 1 {
      if ($3 != uid) r = "owner"
      else if (substr($1, 6, 1) == "w") r = "group-writable"
      else if (substr($1, 9, 1) == "w") r = "other-writable"
      next
    }
    r == "" && /^ *[0-9]+: / && $(NF - 1) == "allow" {
      n = split($NF, p, ",")
      for (k = 1; k <= n; k++)
        if (p[k] ~ /^(write|append|add_file|add_subdirectory|delete_child|delete|writesecurity|chown)$/) {
          r = "acl-write"; i = $1; sub(/:$/, "", i)
        }
    }
    END {
      if (NR == 0) r = "unreadable"
      print (r == "" ? "ok" : r)
      if (r == "acl-write") print i
    }'
)

mavergreen_chain_verdict() (
  mavergreen_chain_judge | sed -n 1p
)

mavergreen_chain_say() (
  printf '%s: %s; root will not write or run here; fix: %s\n' "$1" "$2" "$3" >&2
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
  case "$r" in
    ok) return 0 ;;
    owner)
      if [ "$1" = "$2" ]; then f="sudo diskutil enableOwnership $1"; else f="sudo chown root:wheel $1"; fi ;;
    group-writable|other-writable) f="sudo chmod go-w $1" ;;
    acl-write)
      i="$(printf '%s\n' "$v" | sed -n 2p)"
      e="$(ls -lde -- "$1" 2>/dev/null | awk -v i="$i" '
        /^ *[0-9]+: / { n = $1; sub(/:$/, "", n)
          if (n == i) { sub(/^ *[0-9]+: /, ""); sub(/ inherited /, " "); print; exit } }')"
      f="sudo chmod -a '$e' $1" ;;
    *) r=unreadable; f="sudo ls -lde $1" ;;
  esac
  mavergreen_chain_say "$1" "$r" "$f"
  return 1
)

mavergreen_chain_ok() (
  LC_ALL=C; export LC_ALL
  vol="$(cd -P -- "$2" 2>/dev/null && pwd -P)" \
    || { mavergreen_chain_say "$2" missing "name the target volume's root"; return 1; }
  p="$1"; n=0
  while [ -L "$p" ]; do
    n=$((n + 1))
    [ "$n" -le 32 ] || { mavergreen_chain_say "$1" "symlink loop" "sudo rm $1"; return 1; }
    t="$(readlink "$p")" || { mavergreen_chain_say "$p" unreadable "sudo ls -l $p"; return 1; }
    case "$t" in /*) p="$t" ;; *) p="$(dirname -- "$p")/$t" ;; esac
  done
  leaf=""
  if [ -d "$p" ]; then
    d="$(cd -P -- "$p" && pwd -P)" || { mavergreen_chain_say "$p" unreadable "sudo ls -lde $p"; return 1; }
  else
    up="$(dirname -- "$p")"
    d="$(cd -P -- "$up" 2>/dev/null && pwd -P)" || { mavergreen_chain_say "$up" missing "sudo mkdir -m 755 $up"; return 1; }
    [ ! -e "$p" ] || leaf="${d%/}/$(basename -- "$p")"
  fi
  case "$vol" in
    /) ;;
    *) case "$d/" in "$vol"/*) ;; *) mavergreen_chain_say "${leaf:-$d}" "outside $vol" "install under $vol"; return 1 ;; esac ;;
  esac
  [ -z "$leaf" ] || mavergreen_chain_one "$leaf" "$vol" || return 1
  while :; do
    mavergreen_chain_one "$d" "$vol" || return 1
    [ "$d" != "$vol" ] || return 0
    d="$(dirname -- "$d")"
  done
)

mavergreen_dir_ok() (
  LC_ALL=C; export LC_ALL
  if [ -L "$1" ]; then mavergreen_chain_say "$1" symlink "sudo mv $1 $1.old"; return 1; fi
  [ -e "$1" ] || { mavergreen_chain_say "$1" missing "sudo mkdir -m 755 $1"; return 1; }
  [ -d "$1" ] || { mavergreen_chain_say "$1" "not a directory" "sudo mv $1 $1.old"; return 1; }
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
