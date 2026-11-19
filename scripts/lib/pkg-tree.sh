#!/bin/sh
# platform: host-agnostic
#   usage: . pkg-tree.sh     (sourced after $SELF names the scripts directory; defines the af_* functions)
#          af_pkg_tree <pkg> <scratch>     expands a .pkg with stevedore into AF_TREE, once: under
#                                          shipyard-check --dist ($SHIPYARD_CHECK_PKGS set) into
#                                          $SHIPYARD_CHECK_PKGS/<name> and every later reader finds it
#                                          there; otherwise into <scratch>/<name>. Returns 3, AF_WHY set,
#                                          when stevedore cannot be fetched; 1 when it cannot expand the pkg.
#          af_unpack_payload <Payload>     extracts it to <its directory>.root (once), and sets AF_ROOT to
#                                          that tree and AF_LOC to its install-location ("" or "a/b/")
#          af_payload_modes <Payload>      prints "<path> <uid> <gid> <mode>" for every entry, its path
#                                          relative to the payload (. for its root, %20-encoded) and its
#                                          mode as ls spells it; returns 1 on a line that does not parse
#          af_unpack_scripts <Scripts> <dir>  extracts a component's Scripts archive into the existing <dir>
#          af_extract <tarball> <dir>      extracts a release tarball into the existing <dir>
#          af_interpreter <script>         prints the first word of its #! line, or none
#          af_mentions <script>            prints, once each, the admin-writable roots its text names, in
#                                          any case, each ending at a boundary (/ " ' space tab newline ; ) & | }
#                                          < > ` or the end): /usr/local/, /Users/, /tmp/, /private/tmp/, and
#                                          /Applications/ unless Mavergreen follows as a whole component with
#                                          no .. after it; also $HOME, ${HOME, ~/, and ~ alone as a word or
#                                          after = or : that ends its command (awk's ` ~ /re/` is not one)
#          af_macho_kind <file>            prints strict (a Mach-O magic, or a fat one af_fat_macho
#                                          accepts), loose (an ar archive, Mach-O only if the readers say
#                                          so) or nothing (a Java class file shares the fat magic)
#          af_fat_macho <file>             0 when the file is a fat Mach-O: the fat magic, then an arch
#                                          count from 1 to 29, where a class file has its version (45+)
#          af_enc                          stdin to stdout, with "%" as %25 and " " as %20
#          af_rm <dir>                     removes a tree extraction left read-only
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact conformance" --
#       one reader of a built pkg on every host: stevedore expands the xar, whose Payload and Scripts
#       are gzip'd cpio archives, so neither bsdtar nor pkgutil is needed.

af_stevedore() {
  [ -z "${AF_STEVEDORE_OK:-}" ] || return 0
  STEVEDORE="$(sh "$SELF/fetch_stevedore.sh" 2>/dev/null)" || {
    AF_WHY="stevedore, which reads the pkgs, cannot be fetched ($(sh "$SELF/fetch_stevedore.sh" 2>&1 >/dev/null | tail -1))"
    return 1
  }
  export STEVEDORE
  AF_STEVEDORE_OK=1
}

af_pkg_tree() {
  af_stevedore || return 3
  _at_name="${1##*/}"
  if [ -n "${SHIPYARD_CHECK_PKGS:-}" ]; then AF_TREE="$SHIPYARD_CHECK_PKGS/$_at_name"; else AF_TREE="$2/$_at_name"; fi
  [ ! -d "$AF_TREE" ] || return 0
  mkdir -p "${AF_TREE%/*}"
  if "$STEVEDORE" expand "$1" "$AF_TREE.part" >/dev/null 2>&1; then
    mv "$AF_TREE.part" "$AF_TREE"
  else
    af_rm "$AF_TREE.part"
    return 1
  fi
}

af_cpio() {
  _ac_tmp="$2.cpio"
  gzip -dc "$1" > "$_ac_tmp" 2>/dev/null || { rm -f "$_ac_tmp"; return 1; }
  _ac_rc=0; ( cd "$2" && cpio -id < "$_ac_tmp" >/dev/null 2>&1 ) || _ac_rc=$?
  rm -f "$_ac_tmp"
  return "$_ac_rc"
}

# platform: BSD and GNU cpio -tvn both list an entry as ls -ln does: mode, links, uid, gid, size, a
#           three-word date, then the name, and a link's name as "name -> target".
af_payload_modes() {
  _apm_tmp="$1.list"
  gzip -dc "$1" > "$_apm_tmp.cpio" 2>/dev/null && cpio -itvn < "$_apm_tmp.cpio" > "$_apm_tmp" 2>/dev/null \
    || { rm -f "$_apm_tmp" "$_apm_tmp.cpio"; return 1; }
  rm -f "$_apm_tmp.cpio"
  _apm_rc=0
  LC_ALL=C awk '
    {
      if ($1 !~ /^[-dl][-r][-w][-xsS][-r][-w][-xsS][-r][-w][-xtT]$/ || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ \
          || !match($0, /^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ /)) { bad = 1; exit 1 }
      n = substr($0, RLENGTH + 1)
      if (substr($1, 1, 1) == "l") { i = index(n, " -> "); if (i == 0) { bad = 1; exit 1 }; n = substr(n, 1, i - 1) }
      if (n == ".") n = ""; sub(/^\.\//, "", n); sub(/\/$/, "", n)
      if (n == "") n = "."
      gsub(/%/, "%25", n); gsub(/ /, "%20", n)
      print n, $3, $4, $1; seen = 1
    }
    END { if (bad || !seen) exit 1 }' "$_apm_tmp" || _apm_rc=1
  rm -f "$_apm_tmp"
  return "$_apm_rc"
}

af_interpreter() {
  _ai="$(sed -n '1s/^#![[:space:]]*//p' "$1" | awk '{ print $1 }')"
  printf '%s\n' "${_ai:-none}"
}

af_mentions() {
  awk 'function bnd(c) { return c == "" || index(B, c) > 0 }
    function root(s, r,   p) {
      while ((p = index(s, r)) > 0) { s = substr(s, p + length(r)); if (bnd(substr(s, 1, 1))) return 1 }
      return 0
    }
    { t = t $0 "\n" }
    END {
      B = "/\"\047 \t\n;)&|}<>`"
      l = tolower(t)
      n = split("/usr/local /users /tmp /private/tmp", r, " "); split("/usr/local/ /Users/ /tmp/ /private/tmp/", o, " ")
      for (i = 1; i <= n; i++) if (root(l, r[i])) print o[i]
      if (index(t, "$HOME")) print "$HOME"
      if (index(t, "${HOME")) print "${HOME"
      s = l
      while ((p = index(s, "/applications")) > 0) {
        s = substr(s, p + 13); c = substr(s, 1, 1)
        if (!bnd(c)) continue
        bad = c != "/" || substr(s, 2, 10) != "mavergreen" || !bnd(substr(s, 12, 1))
        if (!bad) {
          for (q = 12; q <= length(s) && (substr(s, q, 1) == "/" || !bnd(substr(s, q, 1))); q++) ;
          bad = index(substr(s, 12, q - 12) "/", "/../") > 0
        }
        if (bad) { print "/Applications/"; break }
      }
      s = t; pc = ""
      while ((p = index(s, "~")) > 0) {
        if (p > 1) pc = substr(s, p - 1, 1)
        s = substr(s, p + 1); c = substr(s, 1, 1); c0 = c
        w = 0
        if (pc == "" || pc == " " || pc == "\t" || pc == "\n" || pc == "=" || pc == ":") {
          if (c == " " || c == "\t") { match(s, /^[ \t]*/); c = substr(s, RLENGTH + 1, 1); w = c == "" || index(";&|)<>\n", c) > 0 }
          else w = bnd(c)
        }
        if (c0 == "/" || w) { print "~"; break }
        pc = "~"
      }
    }' "$1"
}

af_extract() {
  tar -xf "$1" -C "$2" >/dev/null 2>&1
}

af_unpack_scripts() {
  af_cpio "$1" "$2"
}

af_unpack_payload() {
  _au_dir="${1%/Payload}"
  AF_LOC="$(sed -n '/<pkg-info/ s/.*[[:space:]]install-location="\([^"]*\)".*/\1/p' "$_au_dir/PackageInfo" 2>/dev/null | head -1)"
  AF_LOC="${AF_LOC:-/}"; AF_LOC="${AF_LOC#/}"; AF_LOC="${AF_LOC%/}"
  [ -z "$AF_LOC" ] || AF_LOC="$AF_LOC/"
  AF_ROOT="$_au_dir.root"
  [ ! -f "$AF_ROOT.done" ] || return 0
  mkdir -p "$AF_ROOT"
  if [ -s "$1" ]; then af_cpio "$1" "$AF_ROOT" || return 1; fi
  : > "$AF_ROOT.done"
}

af_fat_macho() {
  _afm="$(head -c 8 "$1" | od -An -tx1 | tr -d ' \n')"
  case "$_afm" in cafebabe????????|cafebabf????????) ;; *) return 1 ;; esac
  _afm=$((0x${_afm#cafebab?}))
  [ "$_afm" -ge 1 ] && [ "$_afm" -le 29 ]
}

af_macho_kind() {
  case "$(head -c 4 "$1" | od -An -tx1 | tr -d ' \n')" in
    cffaedfe|cefaedfe|feedfacf|feedface) echo strict ;;
    cafebabe|cafebabf) if af_fat_macho "$1"; then echo strict; fi ;;
    213c6172) echo loose ;;
  esac
}

af_enc() { sed -e 's/%/%25/g' -e 's/ /%20/g'; }

af_rm() { chmod -R u+rwX "$1" 2>/dev/null || :; rm -rf "$1"; }
