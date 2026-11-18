#!/bin/sh
# platform: host-agnostic
# spec: scripts/lib/root-chain.sh -- the root-only chain (decision 2): from PATH up to VOLROOT (Q5), each
#       directory is uid 0, grants no group or other write, and carries no ACL allowing a write.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "FAIL: $*"; exit 1; }
. "$here/../scripts/lib/root-chain.sh"
w="$(mktemp -d "${TMPDIR:-/tmp}/root-chain-test.XXXXXX")"; trap 'rm -rf "$w"' EXIT
unset MAVERGREEN_CHAIN_UID

v() { printf '%s\n' "$@" | mavergreen_chain_verdict; }
[ "$(v 'drwxr-xr-x  3 0  0  102 Nov 18 13:25 /opt')" = ok ] || fail "uid 0, 755 is ok"
[ "$(v 'drwxr-xr-x  3 501  0  102 Nov 18 13:25 /opt')" = owner ] || fail "uid 501 is owner"
[ "$(v 'drwxrwxr-x  3 0  80  102 Nov 18 13:25 /opt')" = group-writable ] || fail "g+w is group-writable"
[ "$(v 'drwxr-xrwx  3 0  0  102 Nov 18 13:25 /opt')" = other-writable ] || fail "o+w is other-writable"
[ "$(v 'drwxr-xr-x+ 3 0  0  102 Nov 18 13:25 /opt' ' 0: group:everyone deny delete')" = ok ] || fail "a deny entry is ok"
[ "$(v 'drwxr-xr-x+ 3 0  0  102 Nov 18 13:25 /opt' ' 0: group:admin allow add_subdirectory')" = acl-write ] || fail "allow add_subdirectory is acl-write"
[ "$(v 'drwxr-xr-x+ 3 0  0  102 Nov 18 13:25 /opt' ' 0: group:everyone deny delete' ' 1: ABCDEFAB-CDEF-ABCD-EFAB-CDEF00000050 inherited allow list,delete_child,file_inherit')" = acl-write ] || fail "an inherited allow delete_child behind a deny is acl-write"
[ "$(v 'drwxr-xr-x+ 3 0  0  102 Nov 18 13:25 /opt' ' 0: group:staff allow list,search,readattr')" = ok ] || fail "an allow without a write is ok"
for p in write append add_file delete writesecurity chown; do
  [ "$(v 'drwxr-xr-x+ 3 0  0  102 Nov 18 13:25 /opt' " 0: user:me allow $p")" = acl-write ] || fail "allow $p is acl-write"
done
for bad in 'garbage' ' 0: group:admin allow' ' 0: group:admin permit add_file' ' x: group:admin deny delete' '0 group:admin deny delete'; do
  [ "$(v 'drwxr-xr-x+ 3 0  0  102 Nov 18 13:25 /opt' "$bad")" = unreadable ] || fail "an ACL line that doesn't parse ('$bad') is unreadable"
done
[ "$(v 'total 0')" = unreadable ] || fail "a first line that isn't ls -ldn's is unreadable"
[ "$(printf '' | mavergreen_chain_verdict)" = unreadable ] || fail "no input is unreadable"
[ "$(v 'drwxr-xr-x  3 0  0  102 Nov 18 13:25 /Volumes/Macintosh HD 2/opt')" = ok ] || fail "a name with spaces parses as ok"
[ "$(v 'drwxrwxr-x  3 0  0  102 Nov 18 13:25 /Volumes/Macintosh HD 2/opt')" = group-writable ] || fail "a name with spaces parses as group-writable"
[ "$(v 'drwxr-xr-x  3 501  0  102 Nov 18 13:25 /Volumes/Macintosh 0 0/opt')" = owner ] || fail "a name with spaces parses as owner"

me="$(id -u)"
MAVERGREEN_CHAIN_UID="$me"; export MAVERGREEN_CHAIN_UID
ok() { mavergreen_chain_ok "$1" "$2" 2>"$w/err" || { cat "$w/err"; fail "$3"; }; }
no() {
  if mavergreen_chain_ok "$1" "$2" 2>"$w/err"; then fail "$3 (it passed)"; fi
  [ "$(wc -l < "$w/err" | tr -d ' ')" = 1 ] || { cat "$w/err"; fail "$3: one line on stderr"; }
  grep -qF -- "$4" "$w/err" || { cat "$w/err"; fail "$3: the line names '$4'"; }
  grep -qF '; root will not write or run here; fix: ' "$w/err" || { cat "$w/err"; fail "$3: the line says root will not write or run here, and a fix"; }
}
mkdir -p "$w/gw/vol/a/b/c"
chmod 755 "$w/gw/vol" "$w/gw/vol/a" "$w/gw/vol/a/b" "$w/gw/vol/a/b/c"
chmod 775 "$w/gw"
V="$(cd -P "$w/gw/vol" && pwd -P)"
ok "$V/a/b/c" "$V" "a clean three-level chain passes"
ok "$V/a/b/c" "$V" "VOLROOT bounds the walk: the group-writable dir above it is ignored"
chmod g+w "$V/a/b"
no "$V/a/b/c" "$V" "g+w on the middle dir fails" "$V/a/b: group-writable; root will not write or run here; fix: sudo chmod go-w '$V/a/b'"
chmod g-w "$V/a/b"; chmod o+w "$V/a"
no "$V/a/b/c" "$V" "o+w on the top dir fails" "$V/a: other-writable"
chmod o-w "$V/a"
no "$V/a/b/c" "$w/gw" "a group-writable VOLROOT fails" "${V%/vol}: group-writable"
ok "$V/a/b/c/missing" "$V" "a missing leaf is judged by its parent"
chmod g+w "$V/a/b/c"
no "$V/a/b/c/missing" "$V" "a missing leaf's g+w parent fails" "$V/a/b/c: group-writable"
chmod g-w "$V/a/b/c"
no "$V/a/b/c/missing/deeper" "$V" "a missing parent fails" "$V/a/b/c/missing"

mkdir -p "$V/t/u"; chmod 755 "$V/t" "$V/t/u"
ln -s t "$V/lnk"
ok "$V/lnk/u" "$V" "a symlinked middle dir passes by its target"
chmod g+w "$V/t"
no "$V/lnk/u" "$V" "a symlinked middle dir is judged by its target" "$V/t: group-writable"
chmod g-w "$V/t"

ok "$w//gw//vol/a/b/c" "$w//gw//vol/" "doubled slashes resolve to the same chain"
ln -s gw "$w/tmplink"
ok "$w/tmplink/vol/a/b/c" "$w/tmplink/vol" "a symlinked TMPDIR resolves on both sides"
ok "$V/a/b/c" "$w/tmplink/vol" "a physical PATH under a symlinked VOLROOT passes"
mkdir -p "$w/other"; chmod 755 "$w/other"
no "$w/other" "$V" "a PATH outside VOLROOT fails" "outside $V"
no "$V/a" "$w/nowhere" "a missing VOLROOT fails" "$w/nowhere"

MAVERGREEN_CHAIN_UID=12345
mavergreen_dir_ok "$V/a/b/c" 2>"$w/err" && fail "an owner other than the trusted uid fails"
grep -qxF "$V/a/b/c: owner; root will not write or run here; fix: sudo chown root:wheel '$V/a/b/c'" "$w/err" || { cat "$w/err"; fail "the owner fix is chown root:wheel"; }
no "$V/a/b/c" "$V" "the walk judges VOLROOT first" "$V: owner"
no "$V" "$V" "a VOLROOT not owned by the trusted uid names enableOwnership" "$V: owner; root will not write or run here; fix: sudo diskutil enableOwnership '$V'"
mavergreen_chain_ok "$V" // 2>"$w/err" && fail "a // VOLROOT is judged as /"
grep -qxF "/: owner; root will not write or run here; fix: sudo diskutil enableOwnership '/'" "$w/err" || { cat "$w/err"; fail "a // VOLROOT is normalised to /"; }
MAVERGREEN_CHAIN_UID="$me"

mkdir -p "$V/Mac HD 2/opt"; chmod 755 "$V/Mac HD 2" "$V/Mac HD 2/opt"
ok "$V/Mac HD 2/opt" "$V" "a clean chain through a spaced name passes"
chmod g+w "$V/Mac HD 2/opt"
no "$V/Mac HD 2/opt" "$V" "a g+w spaced dir fails" "group-writable"
grep -qxF "$V/Mac HD 2/opt: group-writable; root will not write or run here; fix: sudo chmod go-w '$V/Mac HD 2/opt'" "$w/err" || { cat "$w/err"; fail "the fix line quotes a spaced path"; }
chmod g-w "$V/Mac HD 2/opt"
evil="$V/a'b;echo pwn"
mkdir "$evil"; chmod 775 "$evil"
no "$evil" "$V" "a g+w dir with a quote in its name fails" "group-writable"
grep -qxF "$evil: group-writable; root will not write or run here; fix: sudo chmod go-w '$V/a'\\''b;echo pwn'" "$w/err" || { cat "$w/err"; fail "the fix line escapes a quote in the path"; }
q="$(sed 's/.*fix: sudo chmod go-w //' "$w/err")"
eval "set -- $q"
[ $# = 1 ] && [ "$1" = "$evil" ] || fail "the quoted path reads back as one word, the path itself"
rmdir "$evil"

mkdir -p "$V/real/sub" "$V/farm"; chmod 755 "$V/real" "$V/real/sub"; chmod 775 "$V/farm"
printf 'x\n' > "$V/real/helper"; chmod 755 "$V/real/helper"
ln -s ../real/helper "$V/farm/helper"; ln -s ../real "$V/farm/r"
no "$V/farm/helper" "$V" "a file link in a g+w dir fails, naming the link's dir" "$V/farm: group-writable"
no "$V/farm/r/sub" "$V" "a dir link in a g+w dir fails, naming the link's dir" "$V/farm: group-writable"
chmod 755 "$V/farm"
ok "$V/farm/helper" "$V" "a file link in a clean dir passes"
ok "$V/farm/r/sub" "$V" "a dir link in a clean dir passes"

printf 'x\n' > "$V/a/b/f"; chmod 755 "$V/a/b/f"
ok "$V/a/b/f" "$V" "a clean file passes"
chmod g+w "$V/a/b/f"
no "$V/a/b/f" "$V" "a g+w file fails, naming the file" "$V/a/b/f: group-writable"
chmod g-w "$V/a/b/f"
ln -s ../a/b/f "$V/t/fl"; ln -s "$V/t/fl" "$V/t/fl2"
ok "$V/t/fl2" "$V" "a link to a link to a clean file passes"
chmod g+w "$V/a/b/f"
no "$V/t/fl2" "$V" "a link is judged by the file it reaches" "$V/a/b/f: group-writable"
chmod g-w "$V/a/b/f"
chmod g+w "$V/a"
no "$V/t/fl2" "$V" "a link's target's ancestors are walked" "$V/a: group-writable"
chmod g-w "$V/a"
ln -s loop1 "$V/loop2"; ln -s loop2 "$V/loop1"
no "$V/loop1" "$V" "a symlink loop fails" "$V/loop1"
ln -s "$w/other/x" "$V/out"
no "$V/out" "$V" "a link leaving VOLROOT fails" "outside $V"
ln -s "$w/tmplink/vol/a" "$V/back"
no "$V/back/b" "$V" "a link whose target passes through a link outside VOLROOT fails" "outside $V"
ln -s ../vol/a "$V/up"
ok "$V/up/b" "$V" "a link up through an ancestor of VOLROOT and back passes"
no "$V/../../other/../gw/vol/a" "$V" "a path that strays outside VOLROOT and back fails" "/other: outside $V"

rd() { mavergreen_root_dir "$1" 2>"$w/err"; }
rd "$V/made" || { cat "$w/err"; fail "root_dir creates a missing dir"; }
[ -d "$V/made" ] || fail "root_dir made the dir"
set -- $(ls -ldn "$V/made")
[ "$1" = drwxr-xr-x ] || fail "root_dir made it 755, got $1"
[ "$3" = "$me" ] || fail "root_dir chowned it to the trusted uid, got $3"
ln -s t "$V/islink"
if rd "$V/islink"; then fail "root_dir refuses a symlink"; fi
grep -qF "$V/islink: symlink; root will not write or run here; fix: " "$w/err" || { cat "$w/err"; fail "root_dir names the symlink"; }
[ -L "$V/islink" ] && [ "$(readlink "$V/islink")" = t ] || fail "root_dir leaves the symlink alone"
[ "$(ls -ldn "$V/t" | cut -c1-10)" = drwxr-xr-x ] || fail "root_dir leaves the link's target alone"
if rd "$V/a/b/f"; then fail "root_dir refuses a file"; fi
grep -qF "$V/a/b/f: not a directory; root will not write or run here; fix: " "$w/err" || { cat "$w/err"; fail "root_dir names the file"; }
mkdir "$V/tight"; chmod 700 "$V/tight"
rd "$V/tight" || { cat "$w/err"; fail "root_dir accepts an existing 700 dir"; }
[ "$(ls -ldn "$V/tight" | cut -c1-10)" = drwx------ ] || fail "root_dir leaves an existing dir's mode untouched"
mkdir "$V/loose"; chmod 775 "$V/loose"
if rd "$V/loose"; then fail "root_dir refuses an existing g+w dir"; fi
grep -qF "$V/loose: group-writable; root will not write or run here; fix: sudo chmod go-w '$V/loose'" "$w/err" || { cat "$w/err"; fail "root_dir names the g+w dir"; }
[ "$(ls -ldn "$V/loose" | cut -c1-10)" = drwxrwxr-x ] || fail "root_dir leaves a refused dir's mode untouched"
chmod 777 "$w/gw"
rd "$V/a" || { cat "$w/err"; fail "root_dir judges DIR alone, not its ancestors"; }
mavergreen_dir_ok "$V/a" 2>"$w/err" || { cat "$w/err"; fail "dir_ok judges DIR alone, not its ancestors"; }
if mavergreen_dir_ok "$V/absent" 2>"$w/err"; then fail "dir_ok refuses a missing dir"; fi

oo() { mavergreen_owned_ok "$1" 2>"$w/err"; }
oo "$V/absent" || { cat "$w/err"; fail "owned_ok passes a missing path, which the installer creates"; }
oo "$V/loose" || { cat "$w/err"; fail "owned_ok judges only the owner, so a g+w dir of the trusted uid passes"; }
if oo "$V/islink"; then fail "owned_ok refuses a symlink"; fi
grep -qxF "$V/islink: symlink; root will not write or run here; fix: sudo mv '$V/islink' '$V/islink.old'" "$w/err" || { cat "$w/err"; fail "owned_ok names the symlink"; }
MAVERGREEN_CHAIN_UID=12345
if oo "$V/loose"; then fail "owned_ok refuses an owner other than the trusted uid"; fi
grep -qxF "$V/loose: owner; root will not write or run here; fix: sudo chown root:wheel '$V/loose'" "$w/err" || { cat "$w/err"; fail "owned_ok names the owner"; }
MAVERGREEN_CHAIN_UID="$me"
echo "PASS: root-chain"
