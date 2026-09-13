#!/bin/sh
#   usage: check-comments.sh [path...]
#          with no paths, scans every tracked *.sh and *.yml. A path named on
#          the command line that is not a readable file is a usage error, not
#          a silent skip -- a caller's typo'd glob must not read as "clean".
#          Violations print <file>:<line>: <line> plus a fix hint; when any
#          are found, a final "<n> comments cite no reason" line goes to
#          stderr. Exit 0 clean, 1 if any violation was found, 2 on a usage
#          error.
set -eu
ROOT="$(pwd)"
REASONS="$ROOT/comment-reasons"
# spec: SKILL.md "Comments cite a reason" -- opt-in via comment-reasons keeps
#       14 consumer repos green until each has swept; the path is the REPO's, never shipyard's
#       installed prefix, since consumers run this script from there.
[ -f "$REASONS" ] || exit 0
alt="$(tr '\n' '|' < "$REASONS" | sed 's/|$//')"

_tmp="${TMPDIR:-/tmp}"
countfile="$(mktemp "${_tmp%/}/check-comments-count.XXXXXX")"
listfile="$(mktemp "${_tmp%/}/check-comments-list.XXXXXX")"
rawfile="$(mktemp "${_tmp%/}/check-comments-raw.XXXXXX")"
trap 'rm -f "$countfile" "$listfile" "$rawfile"' EXIT

if [ "$#" -gt 0 ]; then
  # spec: SKILL.md "Comments cite a reason" -- a path NAMED on the command
  #       line is the caller's claim that it exists. Tasks 3-6 drive this script with globbed
  #       lists (scripts/[a-m]*.sh); a typo'd or non-matching glob would otherwise land here as
  #       an empty argument list that quietly scans nothing -- exit 0, no output, indistinguishable
  #       from "this directory is clean". So refuse it instead of skipping it. The silent skip
  #       kept below, in the main loop, is only for the INTERNAL git-ls-files listing, where a
  #       missing entry means the index is mid-change, not a caller's mistake.
  for f in "$@"; do
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
      echo "check-comments: not a readable file: $f" >&2
      exit 2
    fi
    printf '%s\n' "$f" >> "$listfile"
  done
else
  # platform: a bare "( ... )" subshell's exit status does not survive a pipe under set -e,
  #           and & and \ are metacharacters in a sed replacement -- either one can turn a
  #           failed or mangled listing into an empty one, exit 0.
  if ! git -C "$ROOT" ls-files '*.sh' '*.yml' > "$rawfile"; then
    echo "check-comments: git ls-files failed in $ROOT -- refusing to report clean having examined nothing" >&2
    exit 2
  fi
  : > "$listfile"
  while IFS= read -r rel; do
    printf '%s/%s\n' "${ROOT%/}" "$rel" >> "$listfile"
  done < "$rawfile"
fi

rc=0
while IFS= read -r f; do
  [ -f "$f" ] || continue
  awk -v FNAME="$f" -v ALT="$alt" -v COUNTFILE="$countfile" '
    BEGIN { split(ALT, r, "|"); for (i in r) ok[r[i]] = 1 }

    # spec: SKILL.md "Comments cite a reason" -- counting occurrences of a
    #       one-character needle without a separate loop at every call site: replace each with
    #       itself and let gsub report how many substitutions it made.
    function sq_count(s,   c) { c = s; return gsub(/'"'"'/, "&", c) }
    function dq_count(s,   c) { c = s; return gsub(/"/, "&", c) }

    # spec: SKILL.md "Comments cite a reason" -- a heredoc body is payload, not
    #       commentary: package-pkg.sh writes a whole script inside one. Track the terminator
    #       and skip until it closes.
    heredoc != "" {
      line = $0; sub(/^[ \t]+/, "", line)
      if (line == heredoc) heredoc = ""
      next
    }
    # spec: SKILL.md "Comments cite a reason" -- a shell cannot open a heredoc
    #       from a comment, so this must not either. A "#" line documenting the ORIGINAL bug in
    #       prose can itself contain a quoted example of the bug shape, plus an incidental
    #       contraction or possessive elsewhere on the same line -- and that extra, unrelated
    #       quote character shifts the quote-parity count below to EVEN, fooling it into treating
    #       the quoted example as a real heredoc. Counting quotes better cannot fix that; only
    #       excluding comment lines from heredoc-open detection entirely can. This check must
    #       come BEFORE the quote-aware scan below, and only when not already inside a heredoc
    #       body -- a "#" line that IS heredoc payload (package-pkg.sh writes whole scripts,
    #       comments and all, inside one) keeps being skipped by the block above.
    !/^[ \t]*#/ {
      if ($0 ~ /[^ \t]/) sawcode = 1
      # spec: SKILL.md "Comments cite a reason" -- a "<<WORD" sitting inside a
      #       quoted string, such as a bare word followed by <<EOF inside an echo argument, is
      #       not a heredoc and must not be read as one: the real incident silently ate ~120
      #       lines of a workflow file this way, exit 0, no output, indistinguishable from
      #       clean. Full shell quoting is a parser problem and
      #       out of scope, but the common shapes are not -- for every "<<" candidate on the
      #       line, count the quote characters that come before it and accept it as real only
      #       when neither kind has an odd (still-open) count there. When a real operator and a
      #       quoted fake share one line, the LAST real one wins: that is the one the shell
      #       actually opens.
      line = $0
      lastreal = 0; searchfrom = 1
      while ((p = index(substr(line, searchfrom), "<<")) > 0) {
        pos = searchfrom + p - 1
        prefix = substr(line, 1, pos - 1)
        if (sq_count(prefix) % 2 == 0 && dq_count(prefix) % 2 == 0 &&
            substr(line, pos) ~ /^<<-?[ ]*'"'"'?[A-Za-z_][A-Za-z0-9_]*'"'"'?/)
          lastreal = pos
        searchfrom = pos + 2
      }
      if (lastreal > 0) {
        t = substr(line, lastreal)
        sub(/^<<-?[ ]*/, "", t); gsub(/'"'"'/, "", t)
        sub(/[ \t].*$/, "", t)
        if (t != "") { heredoc = t; next }
      }
    }

    FNR == 1 && /^#!/ { next }
    !/^[ \t]*#/ { intag = 0; inusage = 0; next }

    /^[ \t]*#[ \t]*shellcheck/ { next }
    # spec: SKILL.md "Comments cite a reason" -- a continuation is recognized by
    #       indentation of its content past the label, not by the column of the leading "#":
    #       that character sits in column 1 for every left-margin comment, tag line and
    #       continuation alike, so comparing it never distinguishes them. What must be compared
    #       is where the text after "#" begins.
    /^[ \t]*#[ \t]*usage:/ {
      if (sawcode == 1) {
        printf "%s:%d: %s\n    a usage: block must come before the first line of code -- the exemption covers a header contract; anywhere else it is unlimited untagged prose under a four-letter word. Move it to the top, or cite a reason\n", FNAME, FNR, $0
        bad++
        inusage = 0
        next
      }
      inusage = 1; match($0, /^[ \t]*#[ \t]*/); usecol = RLENGTH + 1; next
    }
    inusage == 1 {
      match($0, /^[ \t]*#[ \t]*/)
      if (RLENGTH + 1 > usecol) next
      inusage = 0
    }

    {
      line = $0
      sub(/^[ \t]*#[ \t]*/, "", line)
      tag = line; sub(/:.*$/, "", tag)
      if (line ~ /^[a-z][a-z0-9_-]*:/ && tag in ok) {
        # spec: 2026-09-13-comments-cite-a-reason spec-citation-tightening -- "spec:" is defined
        #       as a POINTER to the authority, not a restatement of it: one line, no argument, no
        #       prose. 111 of 202 "spec:" tags in tests/ turned out to be the original comment
        #       with a four-character prefix, which the OLD rule accepted because it only checked
        #       the prefix -- the closed set drifting into a catch-all, the exact failure closing
        #       it was meant to prevent. So the TAG LINE ITSELF (never its continuations, which
        #       stay free-form prose) must contain something locatable: a path, a bare filename
        #       with a known extension, a YYYY-MM-DD spec name, or a numbered decision/check.
        #       "platform:" is unaffected -- it states a fact, not a pointer, so prose is correct
        #       there.
        if (tag == "spec") {
          rest = line; sub(/^spec:[ \t]*/, "", rest)
          if (rest !~ /[^ \t\/]+\/[^ \t\/]+|\.(sh|yml|md|cmake|bats)|[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]|check[ \t]+[0-9]+[a-z]*|decision[ \t]+[0-9]+|ruling[ \t]+[0-9]+|[A-Z][A-Za-z0-9]*-[A-Za-z0-9]+-[0-9]+/) {
            printf "%s:%d: %s\n    spec: needs a locatable citation -- e.g. \"# spec: claude-plugins/modernmavericks/skills/modernmavericks-conventions/SKILL.md check 15\"\n", FNAME, FNR, $0
            bad++
            intag = 0
            next
          }
        }
        intag = 1; match($0, /^[ \t]*#[ \t]*/); tagcol = RLENGTH + 1; next
      }
      if (intag == 1) {
        match($0, /^[ \t]*#[ \t]*/)
        if (RLENGTH + 1 > tagcol) next
      }
      intag = 0
      if (line ~ /^[a-z][a-z0-9_-]*:/)
        printf "%s:%d: %s\n    unknown reason \"%s\" -- propose a new reason to Amitai, do not invent a tag\n", FNAME, FNR, $0, tag
      else
        printf "%s:%d: %s\n    cite a reason: \"# platform: <a platform fact that bit us>\" or \"# spec: <where the decision lives>\"\n", FNAME, FNR, $0
      bad++
    }
    END {
      if (bad > 0) {
        print bad >> COUNTFILE
        close(COUNTFILE)
        exit 1
      }
    }
  ' "$f" || rc=1
done < "$listfile"

n=0
[ -s "$countfile" ] && n="$(awk '{s += $1} END { print s + 0 }' "$countfile")"
[ "$n" -gt 0 ] && echo "$n comments cite no reason" >&2

exit "$rc"
