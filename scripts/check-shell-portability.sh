#!/bin/sh
# platform: host-agnostic
#   usage: check-shell-portability.sh [file ...]
#          Gate: no shell construct that the 10.9 base system lacks, in the scripts this family
#          ships. Scans the repo's git-TRACKED *.sh and *.bats (so vendored or fetched upstream
#          trees, which we do not get to rewrite, are out of scope) and the run:/prepare: text of
#          every workflow step that runs in the 10.9 guest (uses: Mavergreen/mavericks-vm, or
#          shell: mavericks), or exactly the files named on the command line. The rule table below
#          is one row per construct:
#            pattern<TAB>sample-it-must-match<TAB>what<TAB>what to do instead
#          One more rule needs a parser, not a pattern: a ( ) subshell or (( )) command whose
#          status nothing checks. A finding in a path that scripts/conventions-grandfathered names
#          as "unchecked-subshell <repo> <path>" warns instead of failing.
# platform: these all share one shape: they work on a CI runner and fail on the platform the family
#           exists to support, so CI is structurally incapable of catching them -- which is how two
#           of them shipped from shipyard itself and reached every consumer through @v1 (`sort -V` in
#           previous-release-tag.sh silently emptied a release-notes baseline; a bare `mktemp -d` in
#           run-repo-tests.sh and 12 test files meant the suite could not START on 10.9). It also
#           bans the assertion forms that CANNOT FAIL there, worse than failing: a bare `[[ ]]`
#           mid-test (bash < 4.1, 10.9's /bin/bash, which pkgsrc's bats runs under, does not let it
#           fail the test) and a bare `! cmd` (no bash lets errexit see it). .bats counts as shell
#           too: the first cut of this lint checked only *.sh and reported ed25519 clean while
#           tests/version.bats died on exactly this bare `mktemp -d`.
set -eu

SELF="$(cd "$(dirname "$0")" && pwd)"
tmpd="$(mktemp -d "${TMPDIR:-/tmp}/shell-portability.XXXXXX")"
trap 'rm -rf "$tmpd"' EXIT
rulesfile="$tmpd/rules"
cat > "$rulesfile" <<'RULES'
sort[[:space:]]+(-[A-Za-z]*V\b|--version-sort)	git tag --list | sort -V | tail -1	sort -V	compare numerically instead (shipyard's lib.sh ver_cmp; see previous-release-tag.sh) -- 10.9's BSD sort has no -V and exits 2 having printed NOTHING, so a caller that swallows stderr gets a silently empty result
\$\(mktemp([[:space:]]+-[A-Za-z]+)*[[:space:]]*\)	work="$(mktemp -d)"	mktemp with no template	give it one: mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX" -- 10.9 BSD mktemp rejects a bare -d with a usage error
lipo[^|;&]*[[:space:]]-archs\b	for a in $(lipo -archs "$b"); do	lipo -archs	use `lipo -info "$f" | sed -n 's/.*: //p'` (add | xargs when comparing for an EXACT arch set) -- 10.9's lipo has no -archs and dies "unknown flag: -archs". -info exists on every macOS; sed -n ...p prints only the line that names the archs, which matters because 10.9's lipo also prints "input file X is not a fat file" to STDOUT for a thin file, and a plain s/.*: // would pass that noise straight through
^[[:space:]]*\[\[[[:space:]].*\]\][[:space:]]*(#.*)?$|\]\][[:space:]]*;[[:space:]]*done	  [[ "$output" == *"<li>one</li>"* ]]	a bare [[ ]] assertion	end it `|| false` (what bats documents for this) -- on bash < 4.1, 10.9's /bin/bash and the one pkgsrc's bats runs under, a failing [[ ]] that is not the last command of a test does NOT fail it, so on 10.9 the assertion checks nothing
^[[:space:]]*![[:space:]]([^|&]|\|[^|]|&[^&])*[^\\|&]$	  ! echo "$output" | grep -q 'tag v1)'	a bare !-negated command	end it `|| false`, or in bats write `run ! cmd` -- on ANY bash a !-negated command never trips errexit, so anywhere but a test's last line it checks nothing
base64[^|;&]*[[:space:]]-d([[:space:]]|$)	gh api x --jq .content | base64 -d > out	base64 -d	use base64 --decode -- 10.9's base64 reads -d as debug: it re-encodes its input and exits 0, so a decode silently yields base64 again (cut-release.sh, 2026-10-18); --decode works on 10.9, modern macOS and GNU
\[\^?[^][]*\[[:.=]([^a-z]|$)	if (glob !~ /^[^*?[:]+$/) {	a bracket expression with a '[' just before ':', '.' or '='	keep '[' out of the bracket expression -- test for it with index() in awk, or put it first: '[[]'. gawk and mawk (every Linux runner) read '[:' as the start of a POSIX class and die "unterminated regexp" on it, as does the newer BWK awk on a macOS runner, while 10.9's awk accepts it, so the host this family develops on cannot see the failure (deviations.sh, 2026-10-27)
RULES

# spec: tests/unchecked-subshell-test.sh -- measured on 10.9.5, whose /bin/sh is Apple's bash 3.2.53:
#       under -e a failing ( ) subshell, or a (( )) command, whose status nothing reads does not
#       stop the script, and no ERR trap fires. It does stop when it is followed by || or && (or |
#       or &), is an if/while/until condition or negated, is followed by a command that reads $?,
#       is a function's body or its last command, or is the last command of a subshell, a $( ),
#       or the script; a compound command whose own status is read passes that on to its last
#       command. bash 4.0 and later, and Apple's patched 3.2.57, stop on every one, so only a lint
#       sees it. Heredocs, quotes, comments, $( ), $(( )), case patterns and f() are parsed, not
#       matched. Inside backquotes and heredoc bodies nothing is checked; a file it cannot parse
#       is reported as a warning and skipped.
cat > "$tmpd/subshell.awk" <<'AWK'
BEGIN { unit = ""; n = 0 }
/^@@unit\t/ { flush(); unit = substr($0, 8); n = 0; next }
{ t = index($0, "\t"); n++; ln[n] = substr($0, 1, t - 1); raw[n] = substr($0, t + 1) }
END { flush() }

function flush(   i, t) {
  if (unit == "" || n == 0) return
  S = ""
  for (i = 1; i <= n; i++) S = S raw[i] "\n"
  L = length(S); P = 1; LINE = 1; PB = 0; HD = ""; NN = 0; ABORT = 0; ERR = ""; ERRL = 1
  CUR = 0; CIGN = 0
  t = parse_list("top", 0, 0)
  if (!ABORT) { next_token(); if (TT != "EOF") die("unexpected '" TV "'") }
  if (ABORT) { print unit "\tparse\t" ln[ERRL] "\t" ERR; return }
  if (t) tailof[t] = -1
  for (i = 1; i <= NN; i++) {
    if (kind[i] != "subshell" && kind[i] != "arith") continue
    if (!masked(i)) continue
    if (exempt(line[i]) || exempt(cline[i])) continue
    print unit "\t" ln[line[i]] "\t" kind[i]
  }
}

function exempt(l) { return l > 0 && l <= n && raw[l] ~ /portability-ok:[ \t]*[^ \t]/ }

function masked(i,   a, m, p) {
  if (fb[i] || ok[i] || ign[i]) return 0
  for (a = anc[i]; a > 0; a = anc[a]) if (ign[a] || ig[a]) return 0
  m = i
  while (tailof[m]) {
    p = tailof[m]
    if (p < 0) return 0
    if (kind[p] == "subshell" || fb[p] || ok[p]) return 0
    m = p
  }
  return 1
}

function die(msg) { if (!ABORT) { ERR = msg; ERRL = LINE }; ABORT = 1 }

function newnode(k, l) {
  NN++; kind[NN] = k; anc[NN] = CUR; ign[NN] = CIGN; line[NN] = l; cline[NN] = 0
  ok[NN] = 0; ig[NN] = 0; tailof[NN] = 0; fb[NN] = 0
  return NN
}

function ch(i) { return substr(S, i, 1) }

function adv_to(x) { while (P < x) { if (ch(P) == "\n") LINE++; P++ } }

function unget() { PB = 1; PTT = TT; PTV = TV; PTS = TS; PTL = TL; PTQ = TQ }

function next_token() {
  if (PB) { PB = 0; TT = PTT; TV = PTV; TS = PTS; TL = PTL; TQ = PTQ; return }
  lex()
}

function lex(   c, c2, c3, i) {
  if (ABORT) { TT = "EOF"; TV = ""; TS = L + 1; TL = LINE; TQ = 0; return }
  for (;;) {
    c = ch(P)
    if (c == " " || c == "\t" || c == "\r") { P++; continue }
    if (c == "\\" && ch(P + 1) == "\n") { P += 2; LINE++; continue }
    if (c == "#") { while (P <= L && ch(P) != "\n") P++; continue }
    break
  }
  TS = P; TL = LINE; TQ = 0
  if (P > L) { TT = "EOF"; TV = ""; return }
  if (c == "\n") { P++; LINE++; TT = "NL"; TV = "\n"; heredocs(); return }
  c2 = substr(S, P, 2); c3 = substr(S, P, 3)
  if (c3 == ";;&" || c3 == "&>>" || c3 == "<<<") { TT = "OP"; TV = c3; P += 3; return }
  if (c3 == "<<-") { P += 3; heredoc_word(1); TT = "OP"; TV = "<<"; return }
  if (c2 == "<<") { P += 2; heredoc_word(0); TT = "OP"; TV = "<<"; return }
  if (c2 == "<(" || c2 == ">(") { word(); return }
  if (c2 == "&&" || c2 == "||" || c2 == ";;" || c2 == ";&" || c2 == "|&" || c2 == "&>" || c2 == ">>" || c2 == "<&" || c2 == ">&" || c2 == "<>" || c2 == ">|") { TT = "OP"; TV = c2; P += 2; return }
  if (index("&|;()<>", c)) { TT = "OP"; TV = c; P++; return }
  if (c ~ /[0-9]/) {
    i = P
    while (ch(i) ~ /[0-9]/) i++
    if (ch(i) == "<" || ch(i) == ">") { P = i; lex(); TS = i; return }
  }
  word()
}

function word(   c, start, sl, q) {
  start = P; sl = LINE; q = 0
  while (P <= L && !ABORT) {
    c = ch(P)
    if (c == "\\") { if (ch(P + 1) == "\n") LINE++; P += 2; q = 1; continue }
    if (c == "'") { q = 1; P++; squote(); continue }
    if (c == "\"") { q = 1; P++; dquote(); continue }
    if (c == "`") { q = 1; P++; backtick(); continue }
    if (c == "$") { dollar(); continue }
    if ((c == "<" || c == ">") && ch(P + 1) == "(") { P += 2; subparse(); continue }
    if (index("@!+*?", c) && ch(P + 1) == "(") { P++; parens(); continue }
    if (c == "=" && ch(P + 1) == "(" && substr(S, start, P - start) ~ /^[A-Za-z_][A-Za-z_0-9]*(\[.*\])?\+?$/) { P++; parens(); continue }
    if (index(" \t\r\n;&|()<>", c)) break
    P++
  }
  TT = "W"; TV = substr(S, start, P - start); TS = start; TL = sl; TQ = q
}

function squote(   c) {
  while (P <= L) { c = ch(P); P++; if (c == "\n") LINE++; if (c == "'") return }
  die("unterminated single quote")
}

function dquote(   c) {
  while (P <= L && !ABORT) {
    c = ch(P)
    if (c == "\\") { if (ch(P + 1) == "\n") LINE++; P += 2; continue }
    if (c == "\"") { P++; return }
    if (c == "`") { P++; backtick(); continue }
    if (c == "$") { dollar(); continue }
    if (c == "\n") LINE++
    P++
  }
  die("unterminated double quote")
}

function backtick(   c) {
  while (P <= L) {
    c = ch(P)
    if (c == "\\") { if (ch(P + 1) == "\n") LINE++; P += 2; continue }
    P++
    if (c == "\n") LINE++
    if (c == "`") return
  }
  die("unterminated backquote")
}

function dollar(   c) {
  c = ch(P + 1)
  if (c == "(") {
    if (ch(P + 2) == "(" && arith_end(P + 3)) { adv_to(AEND); return }
    P += 2; subparse(); return
  }
  if (c == "{") { P += 2; braces(); return }
  if (c == "'") {
    P += 2
    while (P <= L) { c = ch(P); if (c == "\\") { P += 2; continue }; P++; if (c == "\n") LINE++; if (c == "'") return }
    die("unterminated $'"); return
  }
  P++
}

function arith_end(i,   d, c) {
  d = 0
  while (i <= L) {
    c = ch(i)
    if (c == "(") d++
    else if (c == ")") {
      if (d > 0) d--
      else { if (ch(i + 1) == ")") { AEND = i + 2; return 1 }; return 0 }
    }
    i++
  }
  return 0
}

function braces(   d, c) {
  d = 1
  while (P <= L && !ABORT) {
    c = ch(P)
    if (c == "\\") { if (ch(P + 1) == "\n") LINE++; P += 2; continue }
    if (c == "'") { P++; squote(); continue }
    if (c == "\"") { P++; dquote(); continue }
    if (c == "`") { P++; backtick(); continue }
    if (c == "$") { dollar(); continue }
    if (c == "{") d++
    if (c == "}") { d--; if (d == 0) { P++; return } }
    if (c == "\n") LINE++
    P++
  }
  die("unterminated ${")
}

function parens(   d, c) {
  d = 0
  while (P <= L && !ABORT) {
    c = ch(P)
    if (c == "\\") { if (ch(P + 1) == "\n") LINE++; P += 2; continue }
    if (c == "'") { P++; squote(); continue }
    if (c == "\"") { P++; dquote(); continue }
    if (c == "`") { P++; backtick(); continue }
    if (c == "$") { dollar(); continue }
    if (c == "(") d++
    if (c == ")") { d--; if (d == 0) { P++; return } }
    if (c == "\n") LINE++
    P++
  }
  die("unterminated (")
}

function subparse(   nd, t, so, si) {
  nd = newnode("cmdsub", LINE); ig[nd] = 1
  so = CUR; si = CIGN
  t = parse_list("paren", nd, 0)
  if (t) tailof[t] = nd
  CUR = so; CIGN = si
  next_token()
  if (!(TT == "OP" && TV == ")")) die("unclosed $(")
}

function heredoc_word(strip,   c, d, q) {
  while (ch(P) == " " || ch(P) == "\t") P++
  d = ""
  while (P <= L) {
    c = ch(P)
    if (index(" \t\n;&|()<>", c)) break
    if (c == "'" || c == "\"") { q = c; P++; while (P <= L && ch(P) != q) { d = d ch(P); P++ }; P++; continue }
    if (c == "\\") { d = d ch(P + 1); P += 2; continue }
    d = d c; P++
  }
  if (d == "") { die("heredoc without a delimiter"); return }
  HD = HD (strip ? "-" : "+") d "\034"
}

function heredocs(   e, k, strip, d, s) {
  while (HD != "") {
    k = index(HD, "\034"); e = substr(HD, 1, k - 1); HD = substr(HD, k + 1)
    strip = substr(e, 1, 1) == "-"; d = substr(e, 2)
    for (;;) {
      if (LINE > n) { die("heredoc " d " never ends"); return }
      s = raw[LINE]; P += length(s) + 1; LINE++
      sub(/\r$/, "", s)
      if (strip) sub(/^\t+/, "", s)
      if (s == d) break
    }
  }
}

function is_term(k) {
  if (TT == "OP") {
    if (k == "paren") return TV == ")"
    if (k == "case") return TV == ";;" || TV == ";&" || TV == ";;&"
    return 0
  }
  if (TT != "W" || TQ) return 0
  if (k == "brace") return TV == "}"
  if (k == "then") return TV == "then"
  if (k == "fi_else") return TV == "elif" || TV == "else" || TV == "fi"
  if (k == "do") return TV == "do"
  if (k == "done") return TV == "done"
  if (k == "case") return TV == "esac"
  return 0
}

function skipnl() { do next_token(); while (TT == "NL"); unget() }

function expectw(w) { next_token(); if (!(TT == "W" && !TQ && TV == w)) die("expected '" w "', found '" TV "'") }

function parse_list(k, owner, ignf,   so, si, t, tail, pend, st) {
  so = CUR; si = CIGN; CUR = owner; CIGN = ignf
  tail = 0; pend = 0
  while (!ABORT) {
    next_token()
    if (TT == "NL") continue
    if (TT == "EOF") { if (k != "top") die("unexpected end of file"); break }
    if (is_term(k)) { unget(); break }
    unget(); st = TS
    t = parse_andor()
    next_token()
    if (pend && substr(S, st, TS - st) ~ /[$][?]|[$][{][?][}]/) ok[pend] = 1
    pend = 0
    if (TT == "OP" && TV == "&") { if (t) ok[t] = 1; tail = 0; continue }
    if ((TT == "OP" && TV == ";") || TT == "NL") { pend = t; tail = t; continue }
    unget(); tail = t; break
  }
  CUR = so; CIGN = si
  return tail
}

function parse_andor(   t) {
  for (;;) {
    t = parse_pipeline()
    if (ABORT) return 0
    next_token()
    if (TT == "OP" && (TV == "&&" || TV == "||")) { if (t) { ok[t] = 1; ig[t] = 1 }; skipnl(); continue }
    unget(); return t
  }
}

function parse_pipeline(   t, neg, si) {
  neg = 0
  next_token()
  if (TT == "W" && !TQ && TV == "!") neg = 1
  else if (!(TT == "W" && !TQ && TV == "time")) unget()
  si = CIGN; if (neg) CIGN = 1
  for (;;) {
    t = parse_command()
    if (ABORT) break
    next_token()
    if (TT == "OP" && (TV == "|" || TV == "|&")) { if (t) ok[t] = 1; skipnl(); continue }
    unget(); break
  }
  CIGN = si
  if (neg && t) { ok[t] = 1; ig[t] = 1 }
  return t
}

function redirs() {
  for (;;) {
    next_token()
    if (TT == "OP" && (substr(TV, 1, 1) == "<" || substr(TV, 1, 1) == ">" || substr(TV, 1, 2) == "&>")) {
      if (TV != "<<") { next_token(); if (TT != "W") { die("redirection without a target"); return } }
      continue
    }
    unget(); return
  }
}

function simple() {
  for (;;) {
    next_token()
    if (TT == "W") continue
    if (TT == "OP" && (substr(TV, 1, 1) == "<" || substr(TV, 1, 1) == ">" || substr(TV, 1, 2) == "&>")) {
      if (TV != "<<") { next_token(); if (TT != "W") { die("redirection without a target"); return 0 } }
      continue
    }
    unget(); return 0
  }
}

function body(nd, k,   t) { t = parse_list(k, nd, 0); if (t) tailof[t] = nd }

function parse_command(   nd, w, l, prev, cnt) {
  next_token()
  if (TT == "OP" && TV == "(") {
    l = TL
    if (ch(P) == "(" && arith_end(P + 1)) { adv_to(AEND); nd = newnode("arith", l); cline[nd] = LINE; redirs(); return nd }
    nd = newnode("subshell", l)
    body(nd, "paren")
    next_token()
    if (!(TT == "OP" && TV == ")")) { die("unclosed subshell"); return 0 }
    cline[nd] = TL
    redirs(); return nd
  }
  if (TT == "OP" && (substr(TV, 1, 1) == "<" || substr(TV, 1, 1) == ">" || substr(TV, 1, 2) == "&>")) { unget(); return simple() }
  if (TT != "W") { die("unexpected '" TV "'"); return 0 }
  w = TV; l = TL
  if (!TQ) {
    if (w == "{") { nd = newnode("brace", l); body(nd, "brace"); expectw("}"); redirs(); return nd }
    if (w == "if") {
      nd = newnode("if", l)
      parse_list("then", nd, 1); expectw("then"); body(nd, "fi_else")
      for (;;) {
        next_token()
        if (TT == "W" && TV == "elif") { parse_list("then", nd, 1); expectw("then"); body(nd, "fi_else"); continue }
        if (TT == "W" && TV == "else") { body(nd, "fi_else"); continue }
        if (TT == "W" && TV == "fi") break
        die("expected fi"); return 0
      }
      redirs(); return nd
    }
    if (w == "while" || w == "until") {
      nd = newnode("loop", l)
      parse_list("do", nd, 1); expectw("do"); body(nd, "done"); expectw("done"); redirs(); return nd
    }
    if (w == "for" || w == "select") {
      nd = newnode("loop", l); prev = ""; cnt = 0
      for (;;) {
        next_token()
        if (TT == "EOF" || ABORT) { die("for without do"); return 0 }
        if (TT == "W" && !TQ && TV == "do" && (prev == ";" || prev == "NL" || cnt == 1)) break
        prev = (TT == "NL") ? "NL" : TV; cnt++
      }
      body(nd, "done"); expectw("done"); redirs(); return nd
    }
    if (w == "case") {
      nd = newnode("case", l)
      next_token(); skipnl(); expectw("in")
      for (;;) {
        skipnl(); next_token()
        if (TT == "W" && !TQ && TV == "esac") break
        if (TT == "OP" && TV == "(") next_token()
        while (!(TT == "OP" && TV == ")")) { if (TT == "EOF" || ABORT) { die("unclosed case pattern"); return 0 }; next_token() }
        body(nd, "case")
        next_token()
        if (TT == "OP" && (TV == ";;" || TV == ";&" || TV == ";;&")) continue
        if (TT == "W" && !TQ && TV == "esac") break
        die("expected ;; or esac"); return 0
      }
      redirs(); return nd
    }
    if (w == "[[") {
      for (;;) { next_token(); if (TT == "W" && TV == "]]") break; if (TT == "EOF" || ABORT) { die("unclosed [["); return 0 } }
      simple(); return 0
    }
    if (w == "function") {
      next_token()
      if (substr(S, P, 64) ~ /^[ \t]*\(/) { next_token(); next_token() }
      skipnl(); nd = parse_command(); if (nd) fb[nd] = 1; return 0
    }
    if (w == "@test") {
      for (;;) { next_token(); if (TT == "W" && !TQ && TV == "{") break; if (TT == "NL" || TT == "EOF" || ABORT) { die("@test without {"); return 0 } }
      nd = newnode("brace", l); fb[nd] = 1; body(nd, "brace"); expectw("}"); return 0
    }
    if (w == "}" || w == "then" || w == "fi" || w == "do" || w == "done" || w == "esac" || w == "elif" || w == "else" || w == "in") { die("unexpected '" w "'"); return 0 }
  }
  if (w ~ /^[A-Za-z_][A-Za-z0-9_.:@-]*$/ && substr(S, P, 64) ~ /^[ \t]*\([ \t]*\)/) {
    next_token(); next_token(); skipnl(); nd = parse_command(); if (nd) fb[nd] = 1; return 0
  }
  unget(); return simple()
}

AWK

cat > "$tmpd/guest.awk" <<'AWK'
function ind(s) { match(s, /^ */); return RLENGTH }
function flushitem() { if (item && mav && buf != "") printf "%s", buf; item = 0; mav = 0; buf = "" }
function unq(s) {
  if (s ~ /^'.*'$/) { s = substr(s, 2, length(s) - 2); gsub(/''/, "'", s); return s }
  if (s ~ /^".*"$/) return substr(s, 2, length(s) - 2)
  return s
}
{
  line = $0; sub(/\r$/, "", line)
  i = ind(line)
  if (inb) {
    if (line ~ /^[ \t]*$/) { buf = buf NR "\t\n"; next }
    if (i > key) { if (bi < 0 || i < bi) bi = i; buf = buf NR "\t" substr(line, bi + 1) "\n"; next }
    inb = 0
  }
  if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) next
  if (item && i <= iti) flushitem()
  if (!item && line ~ /^ *- /) { item = 1; iti = i; mav = 0; buf = "" }
  if (!item) next
  b = line; sub(/^ *(- +)?/, "", b)
  k = i; if (line ~ /^ *- /) { match(line, /^ *- +/); k = RLENGTH }
  if (b ~ /^uses:[ \t]*["']?Mavergreen\/mavericks-vm([@ \t"']|$)/) mav = 1
  if (b ~ /^shell:[ \t]*["']?mavericks([ \t"']|$)/) mav = 1
  if (b ~ /^(run|prepare):/) {
    v = b; sub(/^(run|prepare):[ \t]*/, "", v)
    if (v ~ /^[|>][-+0-9]*[ \t]*(#.*)?$/) { inb = 1; key = k; bi = -1; buf = buf "@@unit\t" f "\n" }
    else if (v != "") buf = buf "@@unit\t" f "\n" NR "\t" unq(v) "\n"
  }
}
END { flushitem() }
AWK

units() {
  for f in "$@"; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "$(basename "$0")" ] && continue
    case "$f" in
      *.yml|*.yaml) awk -v f="$f" -f "$tmpd/guest.awk" "$f" ;;
      *) awk -v f="$f" 'BEGIN { print "@@unit\t" f } { print NR "\t" $0 }' "$f" ;;
    esac
  done
}

scan_text() {
  awk -v f="$1" -f "$tmpd/guest.awk" "$1" | awk '
    /^@@unit\t/ { next }
    { t = index($0, "\t"); l = substr($0, 1, t - 1) + 0; x[l] = substr($0, t + 1); if (l > m) m = l }
    END { for (i = 1; i <= m; i++) print x[i] }'
}

# spec: tests/shell-portability-test.sh -- a single physical line only: uncertain syntax keeps the original diagnostic.
#       Reject lists and compound/Bash prefixes before sh -n checks a terminal keyword.
#       No surrounding-context, runtime alias or eval analysis is attempted.
conditional_predicate() {
  printf '%s\n' "$1" | LC_ALL=C awk '
    {
      if (NR != 1 || index($0, "$(") || index($0, "`") || index($0, "<<")) exit 1
      # spec: tests/shell-portability-test.sh -- dollar prefixes can change nested quoting across shells.
      if (index($0, "$\047") || index($0, "$\"") || index($0, "${") || index($0, "$[")) exit 1
      if (index($0, "||") || index($0, "&&")) exit 1
      if ($0 ~ /(^[[:space:]]*![[:space:]]+|[|][[:space:]]*)(if|then|elif|else|fi|while|until|for|do|done|case|esac|in|time|coproc|select|function|\[\[|!)([[:space:];|&<>]|$)/) exit 1
      quote = ""; boundary = 1; previous = ""; semicolons = 0
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (quote == "\047") {
          if (c == quote) quote = ""
          continue
        }
        if (c == "\\") {
          if (i == length($0)) exit 1
          nextchar = substr($0, i + 1, 1)
          if (quote == "" || index("$`\"\\", nextchar)) i++
          boundary = 0; previous = ""
          continue
        }
        if (quote == "\"") {
          if (c == quote) quote = ""
          continue
        }
        if (c == "#" && boundary) break
        if (c == "\047" || c == "\"") {
          quote = c; boundary = 0; previous = ""
          continue
        }
        if (index("(){}", c)) exit 1
        if (c == "&" && previous != "<" && previous != ">") exit 1
        if (c == ";") { semicolons++; separator = i }
        boundary = (c ~ /[[:space:];|&<>]/)
        previous = c
      }
      if (quote != "" || semicolons != 1) exit 1
      if (substr($0, separator + 1, i - separator - 1) !~ /^[[:space:]]*(then|do)[[:space:]]*$/) exit 1
    }
  ' || return 1
  printf 'if : ||\n%s\n:\nfi\n' "$1" | /bin/sh -n 2>/dev/null ||
    printf 'while : ||\n%s\n:\ndone\n' "$1" | /bin/sh -n 2>/dev/null
}

# spec: tests/shell-portability-test.sh -- preserve grep hits unless both gates accept.
filter_negation_hits() {
  while IFS= read -r hit; do
    if conditional_predicate "${hit#*:}"; then continue; fi
    printf '%s\n' "$hit"
  done
}

TAB="$(printf '\t')"
status=0

# spec: tests/shell-portability-test.sh -- every rule must still match its own sample, or the lint
#       is dead rather than clean: a pattern that quietly stopped matching would stay green forever.
while IFS="$TAB" read -r pat sample what instead; do
  [ -n "$pat" ] || continue
  printf '%s\n' "$sample" | grep -qE "$pat" || {
    echo "check-shell-portability: the rule for '$what' no longer matches its own sample -- the lint is dead, not clean" >&2
    echo "    fix: repair the pattern, or drop the rule deliberately" >&2
    status=1
  }
done < "$rulesfile"

while IFS="$TAB" read -r pat sample what instead; do
  [ "$what" = 'a bare !-negated command' ] || continue
  if [ -z "$(printf '1:%s\n' "$sample" | filter_negation_hits)" ]; then
    echo "check-shell-portability: the negation filter hides its own sample -- the lint is dead, not clean" >&2
    status=1
  fi
done < "$rulesfile"

printf '@@unit\tsample\n1\t( false )\n2\t( false ) || exit 1\n3\t:\n' | awk -f "$tmpd/subshell.awk" > "$tmpd/sample"
if [ "$(cut -f2 "$tmpd/sample")" != 1 ]; then
  echo "check-shell-portability: the rule for an unchecked subshell no longer finds exactly its own sample -- the lint is dead, not clean" >&2
  status=1
fi

if [ "$#" -gt 0 ]; then
  files="$*"
elif git rev-parse --git-dir >/dev/null 2>&1; then
  files="$(git ls-files '*.sh' '*.bats' '.github/workflows/*.yml' '.github/workflows/*.yaml' 2>/dev/null || true)"
else
  echo "check-shell-portability: not a git checkout and no files named -- nothing scanned" >&2
  echo "    fix: run it in the repo, or pass the files to scan" >&2
  exit 1
fi

# spec: tests/shell-portability-test.sh -- full-line comments are stripped first, so the prose
#       explaining a ban is not itself a violation. A line carrying `portability-ok:` plus a reason
#       is exempt too -- the same escape hatch, and the same obligation to justify it, as this tree's
#       `# shellcheck disable=... # <reason>` lines -- mainly for the lint's OWN test fixtures, which
#       must contain violations to be worth anything. sed preserves the line count, so grep -n still
#       reports the real line number.
while IFS="$TAB" read -r pat sample what instead; do
  [ -n "$pat" ] || continue
  for f in $files; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "$(basename "$0")" ] && continue
    case "$f" in
      *.yml|*.yaml) hits="$(scan_text "$f" | sed -e 's/^[[:space:]]*#.*//' -e '/portability-ok:[[:space:]]*[^[:space:]]/s/.*//' | grep -nE "$pat" || true)" ;;
      *) hits="$(sed -e 's/^[[:space:]]*#.*//' -e '/portability-ok:[[:space:]]*[^[:space:]]/s/.*//' "$f" | grep -nE "$pat" || true)" ;;
    esac
    if [ "$what" = 'a bare !-negated command' ] && [ -n "$hits" ]; then
      hits="$(printf '%s\n' "$hits" | filter_negation_hits)"
    fi
    [ -n "$hits" ] || continue
    printf '%s\n' "$hits" | while IFS= read -r h; do
      echo "check-shell-portability: $f:${h%%:*} uses $what -- a hazard on 10.9" >&2
    done
    echo "    fix: $instead" >&2
    status=1
  done
done < "$rulesfile"

# spec: scripts/conventions-grandfathered -- the repo is $GITHUB_REPOSITORY's name, else the last
#       path component of origin's URL, as check-family-conventions.sh reads it.
REPO_NAME=""
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  REPO_NAME="${GITHUB_REPOSITORY#*/}"
elif _url="$(git config --get remote.origin.url 2>/dev/null)"; then
  _url="${_url%/}"; _url="${_url%.git}"; REPO_NAME="${_url##*[/:]}"
fi
grandfathered() {
  [ -n "$REPO_NAME" ] && [ -f "$SELF/conventions-grandfathered" ] \
    && grep -qxF "unchecked-subshell $REPO_NAME $1" "$SELF/conventions-grandfathered"
}

# shellcheck disable=SC2086  # $files is a deliberate word-split list of paths
units $files | awk -f "$tmpd/subshell.awk" > "$tmpd/subshells"
found=0
while IFS="$TAB" read -r f l k reason; do
  if [ "$l" = parse ]; then
    echo "::warning::check-shell-portability: $f:$k cannot be parsed ($reason), so its subshells went unchecked" >&2
    continue
  fi
  if grandfathered "$f"; then
    echo "::warning::check-shell-portability: $f:$l uses an unchecked subshell (grandfathered: unchecked-subshell $REPO_NAME $f)" >&2
    continue
  fi
  case "$k" in
    arith) echo "check-shell-portability: $f:$l uses an unchecked subshell, a (( )) command no status check reads -- a hazard on 10.9" >&2 ;;
    *) echo "check-shell-portability: $f:$l uses an unchecked subshell, a ( ) no status check reads -- a hazard on 10.9" >&2 ;;
  esac
  found=1
done < "$tmpd/subshells"
if [ "$found" = 1 ]; then
  echo "    fix: end it || exit 1 (|| return 1 in a function) when its body is one && chain of commands; when the body is a sequence that relies on -e, leave it alone and check \$? on the next line: [ \$? -eq 0 ] || exit 1 -- 10.9's sh (bash 3.2.53) does not stop on a failing subshell under -e, and an || after one switches -e off inside it on every shell" >&2
  status=1
fi

[ "$status" -eq 0 ] || exit 1
echo "check-shell-portability: ok — no 10.9-unavailable constructs"
