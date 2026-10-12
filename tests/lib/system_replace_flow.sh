#!/bin/sh
# platform: macOS-only -- pkgbuild builds the pkgs, Installer (or its emulation) installs them, and lsbom, PlistBuddy and BSD stat read the volume
#   usage: . tests/lib/system_replace_flow.sh, with these set by the sourcing test:
#            E2E_MODE  guest (the throwaway 10.9 guest, as root, on /) or fake (a non-root user, on a fake volume)
#            R         the volume: empty for /, else the fake volume, which must be "$W/vol"
#            W         an empty work directory the flow owns, removed when it exits
#            RUID      the uid that owns what Installer installs: 0, or the fake run's own uid
#            here      the tests directory
#          Builds a fake product with stage_product.sh, installs it, and runs its System Replace
#          through replace, upgrade, a refused upgrade, Apple's put-back, restore, uninstall and a
#          volume that is no longer 10.9. Exits 0 when every step holds, else prints FAIL and exits 1.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "System replacement (10.9 only)"
S="$here/../scripts"
PB=/usr/libexec/PlistBuddy
P=sr-e2e
MG="$R/usr/local/mavergreen"; SA="$MG/var/system-replace/$P"; VAR="$MG/var/$P"; TREE="$MG/$P"
PROG=/usr/bin/at; SIBS="/usr/bin/atq /usr/bin/atrm /usr/bin/batch"
MAN=/usr/share/man/man1/at.1
CONF=/etc/ftpusers; CONF2=/etc/csh.logout; IDENT=/etc/mavergreen-e2e-identity
DECL="$PROG $SIBS $MAN $CONF $CONF2 $IDENT"
SYSVER="$R/System/Library/CoreServices/SystemVersion.plist"
HV=9999.0
EV="$W/events"
TAB="$(printf '\t')"
probe_pid=""

fail() { echo "FAIL: $1" >&2; exit 1; }
e2e_cleanup() {
  if [ -n "$probe_pid" ]; then kill "$probe_pid" 2>/dev/null || :; fi
  if [ -f "$W/SystemVersion.plist.orig" ]; then
    cp -p "$W/SystemVersion.plist.orig" "$SYSVER" || echo "FAIL: could not put $SYSVER back from $W/SystemVersion.plist.orig"
  fi
  chmod -R u+w "$W" 2>/dev/null || :
  rm -rf "$W"
}
trap e2e_cleanup EXIT
trap 'exit 130' INT TERM HUP

case "$E2E_MODE" in
  guest)
    . "$here/lib/system_replace_guest_gate.sh"
    _gw="$(e2e_guest_gate)" || fail "the guest flow changes / only in the throwaway 10.9 guest: $_gw"
    [ -z "$R" ] && [ "$RUID" = 0 ] || fail "the guest flow runs as root on / (R='$R', RUID=$RUID)" ;;
  fake) [ "$R" = "$W/vol" ] && [ "$(id -u)" != 0 ] && [ "$RUID" = "$(id -u)" ] \
          || fail "the fake flow runs as a non-root user on $W/vol (R='$R', RUID=$RUID, uid $(id -u))" ;;
  *) fail "E2E_MODE must be guest or fake, got '${E2E_MODE:-}'" ;;
esac
case "$W" in /*) : ;; *) fail "the work directory $W is not absolute" ;; esac
case "$W" in *"'"*|*' '*|*'|'*|*'&'*|*'\'*) fail "the work directory $W holds a character the generated hooks cannot carry" ;; esac
umask 022

sha() {
  _sh="$(shasum -a 256 < "$1")" || return 1
  _sh="${_sh%% *}"; [ -n "$_sh" ] || return 1
  printf '%s\n' "$_sh"
}
fp() {
  if [ -L "$1" ]; then _fpv="$(readlink "$1")" || fail "cannot read the link $1"; printf 'link:%s\n' "$_fpv"
  elif [ -f "$1" ]; then _fpv="$(sha "$1")" || fail "cannot checksum $1"; printf '%s\n' "$_fpv"
  elif [ -e "$1" ]; then echo '?'
  else echo -
  fi
}
snap1() {
  if [ -L "$R$1" ]; then _s1v="$(readlink "$R$1")" || fail "cannot read the link $R$1"; _s1k=l
  elif [ -f "$R$1" ]; then _s1v="$(sha "$R$1")" || fail "cannot checksum $R$1"; _s1k=f
  elif [ -e "$R$1" ]; then printf '%s ?\n' "$1"; return 0
  else printf '%s -\n' "$1"; return 0
  fi
  _s1m="$(stat -f '%Mp%Lp %u %g %i %l' "$R$1")" && [ -n "$_s1m" ] || fail "cannot stat $R$1"
  printf '%s %s %s %s\n' "$1" "$_s1k" "$_s1v" "$_s1m"
}
snap() { for _sn in $DECL; do snap1 "$_sn"; done; }
state() {
  snap
  for _sv in ftpusers identity csh.logout; do _stv="$(fp "$VAR/$_sv")" || exit 1; printf 'var %s %s\n' "$_sv" "$_stv"; done
  _stv="$("$PB" -c 'Print :version' "$TREE/mavergreen.plist")" || fail "cannot read the installed manifest's version"
  printf 'manifest %s\n' "$_stv"
  for _sv in "$MG/bin/at" "$TREE/bin/at" "$SA/applied.plist" "$SA/.replaced"; do
    _stv="$(fp "$_sv")" || exit 1; printf '%s %s\n' "$_sv" "$_stv"
  done
}
same_snap() {
  snap > "$W/snap.now"
  cmp -s "$1" "$W/snap.now" || fail "$2: the declared system paths differ from $(basename "$1"):
$(diff "$1" "$W/snap.now")"
}
is_copy() { [ -f "$1" ] && [ ! -L "$1" ] && cmp -s "$1" "$2"; }
mode_owner() { stat -f '%Lp %u' "$1"; }
setid() { case "$(stat -f %Mp "$1")" in [1-7]) return 0 ;; esac; return 1; }
mgr() { "$R/usr/local/bin/mavergreen" --root "${R:-/}" "$@"; }
step() { echo "== $1"; }
checked() {
  _ck_rc=0; mgr check 2>"$W/check.now" || _ck_rc=$?
  [ "$_ck_rc" = "$check_rc" ] && cmp -s "$W/check.base" "$W/check.now" \
    || fail "after $1, mavergreen check (exit $_ck_rc) reports something its baseline (exit $check_rc) did not:
$(diff "$W/check.base" "$W/check.now")"
}
show() { sed 's/^/    | /' "$1"; }
install_log() {
  if [ "$E2E_MODE" = guest ]; then
    grep -E "$P|preinstall|postinstall|mavergreen" /var/log/install.log 2>/dev/null | tail -n 40 | sed 's/^/    | /'
  else show "$W/installer.out"; fi
}

# spec: scripts/stage_product.sh -- Installer runs the preinstall, lays the payload over the volume,
#       then runs the postinstall, each with the target volume as $3 and $0 in the expanded Scripts.
#       The fake run does the same from pkgutil --expand, and sets each path's mode from the Bom,
#       as Installer does; it cannot set the owner, which MAVERGREEN_TRUSTED_UID stands in for.
install_pkg() {
  : > "$W/installer.out"
  if [ "$E2E_MODE" = guest ]; then
    installer -pkg "$1" -target / > "$W/installer.out" 2>&1
    return
  fi
  inst_n=$((inst_n + 1)); _ix="$W/expanded.$inst_n"
  pkgutil --expand "$1" "$_ix" || return 1
  if [ -f "$_ix/Scripts/preinstall" ]; then
    sh "$_ix/Scripts/preinstall" "$1" "$R/" "$R/" "$R/" >> "$W/installer.out" 2>&1 || return 1
  fi
  tar -xpf "$_ix/Payload" -C "$R/" || return 1
  lsbom -p fm "$_ix/Bom" > "$_ix/modes" || return 1
  while IFS="$TAB" read -r _if _im; do
    case "$_im" in 12*) continue ;; esac
    chmod "${_im#"${_im%????}"}" "$R/${_if#./}" || return 1
  done < "$_ix/modes"
  if [ -f "$_ix/Scripts/postinstall" ]; then
    sh "$_ix/Scripts/postinstall" "$1" "$R/" "$R/" "$R/" >> "$W/installer.out" 2>&1 || return 1
  fi
  return 0
}
inst_n=0

stock_index() {
  for _sb in "$R"/var/db/receipts/com.apple.pkg.*.bom; do
    [ -f "$_sb" ] || continue
    lsbom -p fcs "$_sb" 2>/dev/null || :
  done > "$W/stock"
}
stock() {
  _sk="$(cksum < "$R$1")" || return 1
  K="$1" C="$(echo "$_sk" | awk '{ print $1 }')" Z="$(echo "$_sk" | awk '{ print $2 }')" awk -F '\t' '
    ($1 == "." ENVIRON["K"] || $1 == "./private" ENVIRON["K"]) && $2 "" == ENVIRON["C"] "" && $3 "" == ENVIRON["Z"] "" { f = 1 }
    END { exit !f }' "$W/stock"
}
fill() { sed -e "s|@W@|$W|g" -e "s|@EV@|$EV|g" -e "s|@V@|$2|g" > "$1"; }

# spec: tests/system-replace-mavericks.sh -- the fake volume holds what the guest's 10.9.5 has at the
#       same paths: the setuid at with three hard links, its man page, two /etc files behind the
#       /etc link, a receipt listing them, and a SystemVersion.plist saying 10.9.5.
fake_volume() {
  mkdir -p "$R/usr/bin" "$R/usr/share/man/man1" "$R/private/etc" "$R/System/Library/CoreServices" "$R/var/db/receipts" \
    || return 1
  ln -s private/etc "$R/etc" || return 1
  printf 'apple at\n' > "$R$PROG" && chmod 4555 "$R$PROG" || return 1
  for _fs in $SIBS; do ln "$R$PROG" "$R$_fs" || return 1; done
  printf '.TH AT 1 apple\n' > "$R$MAN" || return 1
  printf '# apple ftpusers\nroot\n' > "$R/private/etc/ftpusers" || return 1
  printf '# System-wide .logout file for csh(1).\n' > "$R/private/etc/csh.logout" || return 1
  "$PB" -c 'Add :ProductVersion string 10.9.5' "$SYSVER" >/dev/null || return 1
  for _fs in $PROG $SIBS $MAN /private/etc/ftpusers /private/etc/csh.logout; do
    mkdir -p "$W/apple$(dirname "$_fs")" && cp -p "$R$_fs" "$W/apple$_fs" || return 1
  done
  mkbom "$W/apple" "$R/var/db/receipts/com.apple.pkg.BSD.bom"
}

mkpkg() {
  _mv="$1"; _ms="$W/stage$_mv"; _mt="$_ms/usr/local/mavergreen/$P"; _mx="$W/src$_mv"
  mkdir -p "$_mt/bin" "$_mt/share" "$_mt/libexec/mavergreen" "$_mx" || return 1
  if [ "$_mv" = 1 ]; then cp /usr/bin/true "$_mt/bin/at"; else cp /usr/bin/false "$_mt/bin/at"; fi || return 1
  chmod 4555 "$_mt/bin/at" || return 1
  printf '# sr-e2e default ftpusers\n' > "$_mt/share/ftpusers.default" || return 1
  printf 'sr-e2e identity\n' > "$_mt/share/identity.default" && chmod 600 "$_mt/share/identity.default" || return 1
  set -- --replaces "$PROG=bin/at" --adopts "$CONF=ftpusers:config" --adopts "$IDENT=identity:identity" \
    --seed ftpusers=share/ftpusers.default --seed identity=share/identity.default
  if [ "$_mv" = 1 ]; then
    mkdir -p "$_mt/share/man/man1" && printf '.TH AT 1 sr-e2e\n' > "$_mt/share/man/man1/at.1" || return 1
    set -- "$@" --replaces "$MAN=share/man/man1/at.1"
  else
    printf '# System-wide .logout file for csh(1).\n# sr-e2e default csh.logout\n' > "$_mt/share/csh.logout.default" || return 1
    set -- "$@" --adopts "$CONF2=csh.logout:config" --seed csh.logout=share/csh.logout.default
  fi
  fill "$_mt/libexec/mavergreen/pre-system-replace" "$_mv" <<'HOOK' || return 1
#!/bin/sh
if [ -e '@W@/fail-pre-system-replace' ]; then
  echo "pre-system-replace: told to refuse" >&2
  exit 1
fi
for f in "$MAVERGREEN_STAGING"/*; do
  [ -f "$f" ] || continue
  if grep -qx e2e-reject "$f"; then echo "pre-system-replace: $f holds e2e-reject" >&2; exit 1; fi
done
echo "pre-system-replace @V@ staged=$(cd "$MAVERGREEN_STAGING" && ls | tr '\n' ' ')" >> '@EV@'
exit 0
HOOK
  chmod 755 "$_mt/libexec/mavergreen/pre-system-replace" || return 1
  fill "$_mx/preflight" "$_mv" <<'PREFLIGHT' || return 1
_e2e_farm=absent
if [ -L "$ROOT/usr/local/mavergreen/bin/at" ]; then _e2e_farm=present; fi
_e2e_c="$ROOT/usr/local/mavergreen/var/sr-e2e/ftpusers"
if [ -L "$_e2e_c" ]; then
  case "$(readlink "$_e2e_c")" in /*) _e2e_c="$ROOT$(readlink "$_e2e_c")" ;; esac
fi
"$PREFLIGHT_DIR/checkconf" "$_e2e_c"
_e2e_rc=$?
echo "preflight @V@ farm=$_e2e_farm checkconf=$_e2e_rc" >> '@EV@'
exit "$_e2e_rc"
PREFLIGHT
  cat > "$_mx/checkconf" <<'CHECKCONF' || return 1
#!/bin/sh
[ -e "$1" ] || exit 0
if grep -qx e2e-reject "$1"; then
  echo "checkconf: $1 holds a line this version rejects (e2e-reject)" >&2
  exit 1
fi
exit 0
CHECKCONF
  chmod 755 "$_mx/checkconf" || return 1
  echo "echo 'preinstall-hook $_mv' >> '$EV'" > "$_mx/prehook" || return 1
  echo "echo 'postinstall-hook $_mv' >> '$EV'" > "$_mx/posthook" || return 1
  MAVERGREEN_PRODUCT_NAMES="$W/product-names" sh "$S/stage_product.sh" --stage "$_ms" --product "$P" \
    --name "System Replace end to end" --version "$_mv" --scripts-out "$W/scripts$_mv" "$@" \
    --preflight "$_mx/preflight" --preflight-file "$_mx/checkconf" \
    --preinstall-hook "$_mx/prehook" --postinstall-hook "$_mx/posthook" > "$W/stage$_mv.log" 2>&1 || return 1
  sh "$S/build_component_pkg.sh" --root "$_ms" --identifier "dev.mavergreen.$P" --version "$_mv" \
    --install-location / --scripts "$W/scripts$_mv" --out "$W/$P-$_mv.pkg" >> "$W/stage$_mv.log" 2>&1
}

step "preconditions"
tools="pkgbuild pkgutil lsbom mkbom shasum cksum"
if [ "$E2E_MODE" = guest ]; then tools="$tools installer"; fi
for t in $tools; do
  command -v "$t" >/dev/null 2>&1 || fail "no $t on this host"
done
if [ "$E2E_MODE" = fake ]; then fake_volume || fail "could not build the fake volume $R"; fi
stock_index
[ -s "$W/stock" ] || fail "no Apple receipt BOM under $R/var/db/receipts lists anything"
[ -f "$R$PROG" ] && [ ! -L "$R$PROG" ] && setid "$R$PROG" || fail "precondition: $PROG is not a setuid regular file: $(ls -l "$R$PROG" 2>&1)"
for s in $SIBS; do
  [ "$(stat -f %i "$R$s")" = "$(stat -f %i "$R$PROG")" ] || fail "precondition: $s is not a hard link to $PROG"
done
stock "$PROG" || fail "precondition: $PROG is not Apple-stock by any receipt, so Apple's put-back (K.4) cannot be shown"
stock "$MAN" || fail "precondition: $MAN is not Apple-stock by any receipt"
stock "$CONF2" || fail "precondition: $CONF2 is not Apple-stock by any receipt, so its adoption would not take the at-baseline row"
[ -f "$R$CONF" ] && [ ! -L "$R$CONF" ] || fail "precondition: $CONF is not a regular file"
for x in "$IDENT" "$CONF.mavergreen-save" "$CONF2.mavergreen-save" "$IDENT.mavergreen-save"; do
  [ ! -e "$R$x" ] && [ ! -L "$R$x" ] || fail "precondition: $x already exists"
done
for x in "$TREE" "$VAR" "$SA" "$MG/kept/$P"; do
  [ ! -e "$x" ] && [ ! -L "$x" ] || fail "precondition: $x already exists, so $P is or was installed here"
done
printf '%s dev.mavergreen.%s shipyard\n' "$P" "$P" > "$W/product-names"

step "the branch's helper, installed by its base component"
sh "$S/build-base-component.sh" --version "$HV" --out "$W/base.pkg" > "$W/base.log" 2>&1 || { show "$W/base.log"; fail "build-base-component.sh failed"; }
rc=0; install_pkg "$W/base.pkg" || rc=$?
[ "$rc" -eq 0 ] || { install_log; fail "installing the base component failed (exit $rc)"; }
sed "s/@MAVERGREEN_VERSION@/$HV/" "$S/mavergreen.sh" > "$W/mavergreen.expected"
cmp -s "$W/mavergreen.expected" "$R/usr/local/bin/mavergreen" || fail "/usr/local/bin/mavergreen is not this branch's helper"
[ "$(mgr version)" = "$HV" ] || fail "the installed helper reports version $(mgr version), not $HV"
check_rc=0; mgr check 2>"$W/check.base" || check_rc=$?
if [ -s "$W/check.base" ]; then echo "note: before $P exists, mavergreen check reports (exit $check_rc):"; show "$W/check.base"; fi

step "build v1, v2 and v3 with stage_product.sh and pkgbuild"
for v in 1 2 3; do
  mkpkg "$v" || { show "$W/stage$v.log"; fail "building $P v$v failed"; }
done
for v in 1 2; do
  pkgutil --expand "$W/$P-$v.pkg" "$W/look$v" || fail "pkgutil cannot expand $P-$v.pkg"
  [ -f "$W/look$v/Scripts/.mavergreen-payload" ] || fail "pkgbuild left .mavergreen-payload out of $P-$v.pkg's Scripts"
  [ -x "$W/look$v/Scripts/preflight/checkconf" ] || fail "pkgbuild left preflight/checkconf, or its exec bit, out of $P-$v.pkg's Scripts"
  lsbom -s "$W/look$v/Bom" | grep -qx "./usr/local/mavergreen/$P/.mavergreen-payload" \
    || fail "$P-$v.pkg's payload does not carry $P/.mavergreen-payload"
  [ "$(lsbom -p fm "$W/look$v/Bom" | awk -F '\t' -v f="./usr/local/mavergreen/$P/bin/at" '$1 == f { print $2 }')" = 104555 ] \
    || fail "$P-$v.pkg's payload does not carry bin/at setuid (mode 4555)"
done

step "1. the admin customizes $CONF, and the declared paths are snapshotted"
printf '# sr-e2e admin customization\n' >> "$R$CONF" || fail "could not customize $CONF"
if stock "$CONF"; then fail "a customized $CONF still reads as Apple-stock"; fi
snap > "$W/snap.1"
cat "$W/snap.1"

step "2. install v1"
: > "$EV"
rc=0; install_pkg "$W/$P-1.pkg" || rc=$?
[ "$rc" -eq 0 ] || { install_log; fail "installing $P v1 failed (exit $rc)"; }
[ "$(sed -n 1p "$EV")" = "preflight 1 farm=absent checkconf=0" ] \
  || fail "the preflight did not run first, finding its checkconf beside \$0: $(cat "$EV")"
[ "$(sed -n 2p "$EV")" = "preinstall-hook 1" ] && [ "$(sed -n 3p "$EV")" = "postinstall-hook 1" ] \
  || fail "the install did not run preflight, preinstall hook, postinstall hook, in that order: $(cat "$EV")"
[ -f "$TREE/.mavergreen-payload" ] || fail "the installed tree has no .mavergreen-payload"
is_copy "$TREE/bin/at" "$W/stage1/usr/local/mavergreen/$P/bin/at" && [ "$(stat -f %Mp%Lp "$TREE/bin/at")" = 4555 ] \
  && [ "$(stat -f %u "$TREE/bin/at")" = "$RUID" ] || fail "the tree's bin/at is not v1's, setuid, owned by $RUID: $(ls -l "$TREE/bin/at")"
[ "$(cat "$VAR/ftpusers")" = "# sr-e2e default ftpusers" ] && [ "$(cat "$VAR/identity")" = "sr-e2e identity" ] \
  || fail "the postinstall did not seed var/$P"
grep -q "  ftpusers\$" "$VAR/.mavergreen-seeded" && grep -q "  identity\$" "$VAR/.mavergreen-seeded" \
  || fail "the postinstall did not record its seeds: $(cat "$VAR/.mavergreen-seeded" 2>&1)"
[ ! -e "$SA/.replaced" ] || fail "installing the product replaced something by itself"
same_snap "$W/snap.1" "installing v1, which is hermetic"
checked "installing v1"

step "3. system-replace, first refused by the pre-system-replace hook"
: > "$W/fail-pre-system-replace"
rc=0; mgr system-replace "$P" > "$W/out" 2>"$W/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-replace must refuse when its pre-system-replace hook fails"
grep -q pre-system-replace "$W/err" || fail "the refusal names the hook: $(cat "$W/err")"
[ ! -e "$SA/applied.plist" ] && [ ! -e "$SA/.replaced" ] || fail "a refused system-replace recorded something"
[ -f "$VAR/ftpusers" ] && [ ! -L "$VAR/ftpusers" ] || fail "a refused system-replace linked var/$P/ftpusers"
same_snap "$W/snap.1" "a refused system-replace"
checked "a refused system-replace"
rm -f "$W/fail-pre-system-replace"
rc=0; mgr system-replace "$P" > "$W/out" 2>"$W/err" || rc=$?
[ "$rc" -eq 0 ] || fail "system-replace failed (exit $rc): $(cat "$W/err")"
grep -q '^pre-system-replace 1 staged=' "$EV" || fail "the pre-system-replace hook did not run: $(cat "$EV")"
is_copy "$R$PROG" "$TREE/bin/at" || fail "$PROG is not a real copy of the tree's bin/at"
[ "$(stat -f '%Mp%Lp %u' "$R$PROG")" = "4555 $RUID" ] || fail "$PROG lost the tree file's owner or setuid mode: $(ls -l "$R$PROG")"
[ "$(mode_owner "$SA")" = "700 $RUID" ] || fail "the save area is not drwx------ owned by $RUID: $(ls -ld "$SA")"
apple_at_inode="$(awk -v p="$PROG" '$1 == p { print $7 }' "$W/snap.1")"
[ "$(stat -f %i "$SA$PROG")" = "$apple_at_inode" ] || fail "the saved $PROG is not Apple's own inode"
for s in $SIBS; do
  [ "$(stat -f '%i %l' "$R$s")" = "$apple_at_inode 4" ] && setid "$R$s" \
    || fail "$s is no longer Apple's setuid inode with four links: $(ls -li "$R$s")"
done
if [ "$E2E_MODE" = guest ]; then
  sudo -u nobody test -x /usr/bin/atq || fail "control: nobody cannot even run /usr/bin/atq, so the next check proves nothing"
  if sudo -u nobody test -x "$SA$PROG"; then fail "nobody can reach the saved setuid original $SA$PROG"; fi
fi
[ "$(readlink "$R$MAN")" = "/usr/local/mavergreen/$P/share/man/man1/at.1" ] || fail "$MAN is not a link into the tree"
[ "$(stat -f %i "$SA$MAN")" = "$(awk -v p="$MAN" '$1 == p { print $7 }' "$W/snap.1")" ] || fail "$MAN's original is not saved"
[ "$(sha "$R$CONF")" = "$(awk -v p="$CONF" '$1 == p { print $3 }' "$W/snap.1")" ] \
  || fail "the admin's customized $CONF did not stay live over the product's default"
[ "$(readlink "$VAR/ftpusers")" = "$CONF" ] || fail "var/$P/ftpusers is not a link to $CONF"
[ "$(cat "$SA/staging/ftpusers")" = "# sr-e2e default ftpusers" ] || fail "the product's default ftpusers was not set aside in staging/"
[ "$(cat "$R$IDENT")" = "sr-e2e identity" ] && [ "$(readlink "$VAR/identity")" = "$IDENT" ] \
  || fail "the identity with no system file did not move in (I4)"
[ "$(stat -f '%Lp %u' "$R$IDENT")" = "600 $RUID" ] || fail "$IDENT did not take the product file's owner and mode"
[ -f "$SA/.replaced" ] || fail "system-replace did not mark .replaced"
checked "system-replace"

step "4. upgrade to v2: new bytes, the man page dropped, $CONF2 adopted"
mkdir "$W/probe"
cat > "$W/probe.sh" <<'PROBE'
n=0
while [ ! -e "$1/stop" ]; do
  n=$((n + 1))
  for p in "$2" "$3" "$4"; do
    if [ ! -e "$p" ]; then echo "$p" >> "$1/absent"; fi
  done
done
echo "$n" > "$1/count"
PROBE
sh "$W/probe.sh" "$W/probe" "$R$PROG" "$R$CONF" "$R$IDENT" &
probe_pid=$!
: > "$EV"
rc=0; install_pkg "$W/$P-2.pkg" || rc=$?
: > "$W/probe/stop"
prc=0; wait "$probe_pid" || prc=$?
probe_pid=""
[ "$rc" -eq 0 ] || { install_log; fail "upgrading to v2 failed (exit $rc)"; }
[ "$prc" -eq 0 ] || fail "the presence probe exited $prc"
[ "$(cat "$W/probe/count")" -ge 50 ] || fail "the presence probe looked only $(cat "$W/probe/count") times, too few to say anything"
[ ! -s "$W/probe/absent" ] || fail "a path v2 keeps replaced was absent during the upgrade: $(sort "$W/probe/absent" | uniq -c)"
echo "probe: $PROG, $CONF and $IDENT present in all $(cat "$W/probe/count") looks during the upgrade"
[ "$(sed -n 1p "$EV")" = "preflight 2 farm=present checkconf=0" ] \
  || fail "v2's preflight did not run first, before unlink removed the farm link: $(cat "$EV")"
[ "$(sed -n 2p "$EV")" = "preinstall-hook 2" ] || fail "v2's preinstall hook did not run right after the preflight: $(cat "$EV")"
grep -q '^pre-system-replace 2 staged=.*csh\.logout ' "$EV" || fail "v2's re-replace did not stage its new adoption: $(cat "$EV")"
[ "$(tail -n 1 "$EV")" = "postinstall-hook 2" ] || fail "v2's postinstall hook did not run last: $(cat "$EV")"
is_copy "$R$PROG" "$TREE/bin/at" && is_copy "$TREE/bin/at" /usr/bin/false || fail "the postinstall did not refresh $PROG to v2's bytes"
[ "$(stat -f %i "$SA$PROG")" = "$apple_at_inode" ] || fail "the refresh disturbed the saved original of $PROG"
[ ! -e "$TREE/share/man/man1/at.1" ] || fail "the postinstall did not prune the dropped man page from the tree (the list beside \$0)"
[ "$(snap1 "$MAN")" = "$(grep "^$MAN " "$W/snap.1")" ] || fail "the dropped man page is not Apple's again: $(snap1 "$MAN")"
if "$PB" -c "Print :replaces:$MAN" "$SA/applied.plist" >/dev/null 2>&1; then fail "applied.plist still records the dropped man page"; fi
[ "$(cat "$R$CONF2")" = "$(cat "$W/stage2/usr/local/mavergreen/$P/share/csh.logout.default")" ] \
  || fail "the product's $CONF2 did not move in over Apple's stock file (the at-baseline row)"
[ "$(readlink "$VAR/csh.logout")" = "$CONF2" ] || fail "var/$P/csh.logout is not a link to $CONF2"
[ "$(stat -f %i "$SA$CONF2")" = "$(awk -v p="$CONF2" '$1 == p { print $7 }' "$W/snap.1")" ] || fail "Apple's $CONF2 was not saved"
[ "$("$PB" -c 'Print :version' "$TREE/mavergreen.plist")" = 2 ] || fail "the tree's manifest is not v2's"
checked "the upgrade to v2"

step "5. v3's preflight rejects the live config, and nothing changes"
cp "$R$CONF" "$W/conf.before-reject"
printf 'e2e-reject\n' >> "$R$CONF" || fail "could not add the line v3 rejects to $CONF"
state > "$W/state.5"
: > "$EV"
rc=0; install_pkg "$W/$P-3.pkg" || rc=$?
[ "$rc" -ne 0 ] || fail "installing v3 must fail when its preflight rejects the live config"
[ "$(cat "$EV")" = "preflight 3 farm=present checkconf=1" ] || fail "v3's install ran more than its preflight: $(cat "$EV")"
if [ "$E2E_MODE" = fake ]; then
  grep -q "$P: the new version cannot use this Mac's configuration; nothing was changed" "$W/installer.out" \
    && grep -q 'holds a line this version rejects' "$W/installer.out" || fail "the refusal does not say why: $(cat "$W/installer.out")"
else
  echo "Installer's log of the refusal:"; install_log
fi
state > "$W/state.5b"
cmp -s "$W/state.5" "$W/state.5b" || fail "a refused upgrade changed something: $(diff "$W/state.5" "$W/state.5b")"
cp "$W/conf.before-reject" "$R$CONF" || fail "could not take the rejected line back out of $CONF"
checked "a refused upgrade"

step "6. Apple puts $PROG back, byte for byte (K.4), and replace takes it for the original again"
cp -p "$SA$PROG" "$R/usr/bin/.at.e2e-putback" && mv -f "$R/usr/bin/.at.e2e-putback" "$R$PROG" \
  || fail "could not put Apple's $PROG back"
rc=0; mgr check 2>"$W/err" || rc=$?
[ "$rc" -ne 0 ] && grep -qF "$PROG is no longer $P's copy" "$W/err" || fail "check does not report the put-back $PROG: $(cat "$W/err")"
rc=0; mgr system-replace "$P" > "$W/out" 2>"$W/err" || rc=$?
[ "$rc" -eq 0 ] || fail "system-replace refused Apple's put-back $PROG (exit $rc): $(cat "$W/err")"
is_copy "$R$PROG" "$TREE/bin/at" || fail "the re-replace did not put v2's copy back at $PROG"
[ "$(stat -f %i "$SA$PROG")" = "$apple_at_inode" ] || fail "the re-replace swapped the saved original for the put-back copy"
checked "re-replacing over Apple's put-back"

step "7. the admin edits $CONF, then system-restore"
printf 'e2e-admin-edit-1\n' >> "$R$CONF" || fail "could not edit $CONF"
cp "$R$CONF" "$W/conf.live7"
rc=0; mgr system-restore "$P" > "$W/out" 2>"$W/err" || rc=$?
[ "$rc" -eq 0 ] || fail "system-restore failed (exit $rc): $(cat "$W/err")"
echo "system-restore said:"; show "$W/out"
grep -qxF "mavergreen: settings in $CONF that the restored original does not have:" "$W/out" \
  && grep -qx '+e2e-admin-edit-1' "$W/out" || fail "restore did not report the admin's edit as a diff"
same_snap "$W/snap.1" "system-restore"
is_copy "$VAR/ftpusers" "$W/conf.live7" || fail "the live $CONF did not go back to var/$P/ftpusers as a real file"
[ -f "$VAR/identity" ] && [ ! -L "$VAR/identity" ] && [ -f "$VAR/csh.logout" ] && [ ! -L "$VAR/csh.logout" ] \
  || fail "an adopted var path is still a link after restore"
[ "$(cd "$SA" && find . \( -type f -o -type l \) | sort)" = ./restored.sha256 ] \
  || fail "restore left more than restored.sha256 in the save area: $(cd "$SA" && find . | sort)"
checked "system-restore"

step "8. a var config the new binary rejects refuses replace; then replace again, edit $CONF, uninstall"
printf 'e2e-reject\n' >> "$VAR/ftpusers" || fail "could not add the rejected line to var/$P/ftpusers"
state > "$W/state.8"
rc=0; mgr system-replace "$P" > "$W/out" 2>"$W/err" || rc=$?
[ "$rc" -ne 0 ] || fail "system-replace must refuse when its pre-system-replace hook rejects the staged config"
grep -q "pre-system-replace: .*ftpusers holds e2e-reject" "$W/err" || fail "the hook's refusal does not name the staged file: $(cat "$W/err")"
state > "$W/state.8b"
cmp -s "$W/state.8" "$W/state.8b" || fail "a replace the hook refused changed something: $(diff "$W/state.8" "$W/state.8b")"
cp "$W/conf.live7" "$VAR/ftpusers" || fail "could not take the rejected line back out of var/$P/ftpusers"
rc=0; mgr system-replace "$P" > "$W/out" 2>"$W/err" || rc=$?
[ "$rc" -eq 0 ] || fail "replace after restore refused (exit $rc): $(cat "$W/err")"
is_copy "$R$CONF" "$W/conf.live7" || fail "replace after restore did not take the var file, the latest intent"
printf 'e2e-admin-edit-2\n' >> "$R$CONF" || fail "could not edit $CONF"
cp "$R$CONF" "$W/conf.live8"
checked "the second system-replace"
rc=0; mgr uninstall "$P" > "$W/out" 2>"$W/err" || rc=$?
[ "$rc" -eq 0 ] || fail "uninstall failed (exit $rc): $(cat "$W/err")"
echo "uninstall said:"; show "$W/out"
same_snap "$W/snap.1" "uninstall"
is_copy "$R$CONF.mavergreen-save" "$W/conf.live8" || fail "$CONF.mavergreen-save does not hold the admin's settings"
grep -qxF "mavergreen: $CONF.mavergreen-save keeps the settings $P used in $CONF" "$W/out" || fail "uninstall did not say where it kept them"
for x in "$CONF2" "$IDENT"; do
  [ ! -e "$R$x.mavergreen-save" ] || fail "uninstall saved $x, which the admin never changed or is an identity"
done
for x in "$SA" "$VAR" "$TREE" "$MG/bin/at" "$MG/kept/$P"; do
  [ ! -e "$x" ] && [ ! -L "$x" ] || fail "uninstall left $x"
done
if [ "$E2E_MODE" = guest ] && pkgutil --pkg-info "dev.mavergreen.$P" >/dev/null 2>&1; then
  fail "uninstall did not forget dev.mavergreen.$P's receipt"
fi
checked "uninstall"

step "9. a volume that is no longer 10.9: uninstall leaves Apple's paths and keeps non-Apple originals (R65, R78, R81)"
rm -f "$R$CONF.mavergreen-save"
chmod u+w "$R$PROG" && printf '# sr-e2e: no longer Apple-stock\n' >> "$R$PROG" && chmod 4555 "$R$PROG" \
  || fail "could not make $PROG's inode non-stock"
if stock "$PROG"; then fail "the changed $PROG still reads as Apple-stock"; fi
changed_at="$(sha "$R$PROG")"; conf9="$(sha "$R$CONF")"
rc=0; install_pkg "$W/$P-2.pkg" || rc=$?
[ "$rc" -eq 0 ] || { install_log; fail "reinstalling v2 failed (exit $rc)"; }
rc=0; mgr system-replace "$P" > "$W/out" 2>"$W/err" || rc=$?
[ "$rc" -eq 0 ] || fail "system-replace of the reinstall failed (exit $rc): $(cat "$W/err")"
cp "$R$CONF" "$W/conf.live9"
cp -p "$SYSVER" "$W/SystemVersion.plist.orig" || fail "could not back up $SYSVER"
"$PB" -c 'Set :ProductVersion 10.10.5' "$SYSVER" || fail "could not set $SYSVER to 10.10.5"
rc=0; mgr uninstall "$P" > "$W/out" 2>"$W/err" || rc=$?
cp -p "$W/SystemVersion.plist.orig" "$SYSVER" && cmp -s "$W/SystemVersion.plist.orig" "$SYSVER" \
  || fail "could not put $SYSVER back"
rm -f "$W/SystemVersion.plist.orig"
[ "$rc" -eq 0 ] || fail "uninstall off 10.9 failed (exit $rc): $(cat "$W/err")"
echo "uninstall off 10.9 said:"; show "$W/out"
grep -qF "$PROG still holds $P's copy" "$W/out" || fail "uninstall did not say it leaves $P's copy at $PROG"
is_copy "$R$PROG" /usr/bin/false || fail "off 10.9, uninstall wrote $PROG"
is_copy "$R$CONF.mavergreen-save" "$W/conf.live9" \
  && grep -qxF "mavergreen: $CONF.mavergreen-save keeps the settings $P used in $CONF" "$W/out" \
  || fail "off 10.9, uninstall did not keep the settings $P used as $CONF.mavergreen-save (R71)"
KEPT="$MG/kept/$P"
[ "$(mode_owner "$MG/kept")" = "700 $RUID" ] && [ "$(mode_owner "$KEPT")" = "700 $RUID" ] \
  || fail "kept/ or kept/$P is not root-only: $(ls -ld "$MG/kept" "$KEPT" 2>&1)"
[ -f "$KEPT$PROG" ] && [ "$(sha "$KEPT$PROG")" = "$changed_at" ] || fail "the non-Apple original of $PROG was not kept in $KEPT"
if setid "$KEPT$PROG"; then fail "the kept $PROG still carries a set-id bit: $(ls -l "$KEPT$PROG")"; fi
grep -qF "is kept as /usr/local/mavergreen/kept/$P$PROG" "$W/out" || fail "uninstall did not say where it kept $PROG"
for s in $SIBS; do
  [ "$(stat -f '%i %l' "$R$s")" = "$apple_at_inode 3" ] && setid "$R$s" && [ "$(sha "$R$s")" = "$changed_at" ] \
    || fail "keeping $PROG's original changed the inode $s shares (R81): $(ls -li "$R$s")"
done
[ -f "$KEPT$CONF" ] && [ "$(sha "$KEPT$CONF")" = "$conf9" ] || fail "the admin's original $CONF was not kept in $KEPT"
[ ! -e "$KEPT$CONF2" ] || fail "Apple's own $CONF2, which a receipt lists, was kept instead of discarded"
for x in "$SA" "$VAR" "$TREE"; do
  [ ! -e "$x" ] || fail "uninstall off 10.9 left $x"
done
checked "uninstall off 10.9"

echo "ok: System Replace end to end ($E2E_MODE)"
