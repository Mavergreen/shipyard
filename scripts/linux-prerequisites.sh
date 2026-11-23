#!/bin/sh
# platform: host-agnostic
#   usage: linux-prerequisites.sh [--check]
#          The tools shipyard's scripts and a family Linux cross build need, checked at once: cmake,
#          make, curl, git, tar, gzip, cpio, xz, python3 with PyYAML (or pip to get it), and the CA
#          bundle. Missing ones are installed with apt-get as root or under `sudo -n` (SUDO= overrides).
#          With --check, with no apt-get, or with neither root nor sudo, it installs nothing and exits 1,
#          naming every missing tool and its package in one message. Exit 0 when all are present.
#          LINUX_PREREQUISITES replaces the table (lines `NAME PACKAGE CHECK...`; test-only).
# spec: tests/linux-prerequisites-test.sh
set -eu
CHECK=""
case "${1:-}" in
  --check) CHECK=1 ;;
  '') : ;;
  *) echo "usage: linux-prerequisites.sh [--check]" >&2; exit 2 ;;
esac
table="${LINUX_PREREQUISITES:-cmake cmake command -v cmake
make make command -v make
curl curl command -v curl
git git command -v git
tar tar command -v tar
gzip gzip command -v gzip
cpio cpio command -v cpio
xz xz-utils command -v xz
python3 python3 command -v python3
PyYAML python3-yaml python3 -c 'import yaml' || python3 -m pip --version
ca-certificates ca-certificates [ -s /etc/ssl/certs/ca-certificates.crt ]}"
missing() {
  printf '%s\n' "$table" | while read -r _n _p _c; do
    [ -n "$_n" ] || continue
    sh -c "$_c" > /dev/null 2>&1 || printf '%s %s\n' "$_n" "$_p"
  done
}
m="$(missing)"
[ -n "$m" ] || { echo "linux-prerequisites: all present" >&2; exit 0; }
if [ "$(id -u)" -eq 0 ]; then _s=""
elif command -v sudo > /dev/null 2>&1 && sudo -n true > /dev/null 2>&1; then _s="sudo -n"
else _s=-; fi
[ "$(id -u)" -eq 0 ] || [ "${SUDO+set}" != set ] || _s="${SUDO:--}"
names="$(printf '%s\n' "$m" | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $1 }')"
pkgs="$(printf '%s\n' "$m" | awk '{ print $2 }' | sort -u | tr '\n' ' ' | sed 's/ $//')"
why=""
if [ -n "$CHECK" ]; then why="--check installs nothing"
elif ! command -v apt-get > /dev/null 2>&1; then why="there is no apt-get"
elif [ "$_s" = - ]; then why="this user is not root and has no working sudo -n"
fi
if [ -z "$why" ]; then
  echo "linux-prerequisites: installing $pkgs (for $names)" >&2
  if [ "$_s" = - ]; then _s=""; fi
  # shellcheck disable=SC2086
  { $_s env DEBIAN_FRONTEND=noninteractive apt-get update -qq \
      && $_s env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $pkgs; } > /dev/null \
    || why="apt-get install $pkgs failed"
  if [ -z "$why" ]; then
    m="$(missing)"
    [ -n "$m" ] || exit 0
    names="$(printf '%s\n' "$m" | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $1 }')"
    pkgs="$(printf '%s\n' "$m" | awk '{ print $2 }' | sort -u | tr '\n' ' ' | sed 's/ $//')"
    why="apt-get installed them and they are still missing"
  fi
fi
echo "linux-prerequisites: missing $names, and $why: install the packages $pkgs first" >&2
exit 1
