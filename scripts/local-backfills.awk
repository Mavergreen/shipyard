# platform: host-agnostic
# spec: scripts/scan-local-backfills.sh -- reads "<name>\t<known|inventory>" lines, then a list of
#       repo-relative paths, and prints one "path\tline\tcategory\tsymbol\treason" per candidate.
function emit(path, ln, cat, s, msg,   k) {
  k = path SUBSEP ln SUBSEP cat SUBSEP s
  if (k in seen) return
  seen[k] = 1
  printf "%s\t%d\t%s\t%s\t%s\n", path, ln, cat, s, msg
}
function obj(s) { return sym[s] == "known" ? "a known Darwin/Recaulk API" : "an inventory-declared symbol" }
function why(cat, s) {
  if (cat == "definition") return "defines " obj(s)
  if (cat == "inline-definition") return "inline definition of " obj(s)
  if (cat == "patch-definition") return "patch adds a definition of " obj(s)
  if (cat == "embedded-definition") return "code producer embeds a definition of " obj(s)
  if (cat == "macro-definition") return "macro defines " obj(s) " name"
  return "declares " obj(s)
}
function ftype(path,   base, ext, n) {
  n = split(path, parts, "/"); base = parts[n]
  if (base == "CMakeLists.txt" || base == "Makefile" || base == "GNUmakefile" || base == "makefile") return "producer"
  if (base ~ /\.in$/) base = substr(base, 1, length(base) - 3)
  if (base !~ /.\./) return ""
  ext = tolower(base); sub(/^.*\./, "", ext)
  if (ext in cext) return "c"
  if (ext == "patch" || ext == "diff") return "patch"
  if (ext in pext) return "producer"
  return ""
}
function typeish(x,   n, i, w) {
  x = x " "
  if (x !~ /^[ \t*]*([A-Za-z_][A-Za-z0-9_]*[ \t*]+)*$/) return 0
  if (x !~ /[A-Za-z_]/) return 0
  n = split(x, w, /[ \t*]+/)
  for (i = 1; i <= n; i++) if (w[i] in kw) return 0
  return 1
}
function strip(x,   k) {
  gsub(/extern[ \t]*"C"/, " ", x)
  for (k = 0; k < 4; k++) gsub(/\([^()]*\)/, " ", x)
  return x
}
function decide(tail,   b, s) {
  b = index(tail, "{"); s = index(tail, ";")
  if (b && (!s || b < s)) return "def"
  if (s) return "decl"
  return ""
}
function settle(kind) {
  if (kind == "def") emit(cur, pend_ln, pend_cat, pend_sym, why(pend_cat, pend_sym))
  else emit(cur, pend_ln, "declaration", pend_sym, why("declaration", pend_sym))
  pend_sym = ""
}
function candidates(body, type, prev, ln,   i, s, off, rest, p, at, pre, inl, cat, d) {
  if (index(body, "(") == 0) return
  for (i = 1; i <= nsym; i++) {
    s = names[i]; off = 0; rest = body
    while ((p = index(rest, s)) > 0) {
      at = off + p
      off = at - 1 + length(s); rest = substr(body, off + 1)
      if (at > 1 && substr(body, at - 1, 1) ~ /[A-Za-z0-9_]/) continue
      if (rest !~ /^[ \t]*\(/) continue
      pre = substr(body, 1, at - 1)
      if (pre == "") { pre = prev; if (!typeish(strip(pre))) continue }
      else if (!typeish(strip(pre))) continue
      inl = (pre ~ /(^|[^A-Za-z0-9_])(__)?inline(__)?([^A-Za-z0-9_]|$)/)
      if (type == "patch") cat = "patch-definition"
      else if (type == "c") cat = inl ? "inline-definition" : "definition"
      else cat = "embedded-definition"
      d = decide(rest)
      pend_sym = s; pend_ln = ln; pend_cat = cat; pend_age = 0
      if (d != "") settle(d)
      break
    }
  }
}
function scan(path, type,   line, ln, r, c, body, plus, prev, m, lb) {
  ln = 0; prev = ""; pend_sym = ""
  while ((r = (getline line < path)) > 0) {
    ln++
    if (ln == 1 && type == "") { if (line ~ /^#!/) type = "producer"; else break }
    plus = 1; body = line
    if (type == "patch") {
      if (line ~ /^\+\+\+ /) {
        pend_sym = ""
        if (tolower(substr(line, 5)) ~ pathre) emit(path, ln, "suspicious-path", "-", "patch targets a shim, polyfill, backfill or compat path")
        continue
      }
      if (line ~ /^(--- |@@|diff |index )/) { pend_sym = ""; continue }
      c = substr(line, 1, 1)
      if (c == "-") continue
      if (c != "+" && c != " ") { pend_sym = ""; continue }
      body = substr(line, 2); plus = (c == "+")
    }
    if (pend_sym != "") {
      m = decide(body)
      if (m != "") settle(m)
      else if (++pend_age > 8) pend_sym = ""
    }
    if (plus) {
      lb = tolower(body)
      if ((type == "c" || type == "patch") && lb ~ annre) emit(path, ln, "annotation", "-", "compatibility annotation")
      if (body ~ /^[ \t]*#[ \t]*define[ \t]/) {
        m = body; sub(/^[ \t]*#[ \t]*define[ \t]+/, "", m)
        if (match(m, /^[A-Za-z_][A-Za-z0-9_]*/) && (substr(m, 1, RLENGTH) in sym))
          emit(path, ln, "macro-definition", substr(m, 1, RLENGTH), why("macro-definition", substr(m, 1, RLENGTH)))
      } else if (body !~ /^[ \t]*#/) candidates(body, type, prev, ln)
    }
    prev = body
  }
  if (r < 0) { print "scan-local-backfills: cannot read " path > "/dev/stderr"; bad = 1 }
  close(path)
}
BEGIN {
  FS = "\t"
  split("c h m mm cc cp cpp cxx c++ hh hpp hxx h++ inc ipp tcc", t, " "); for (i in t) cext[t[i]] = 1
  split("sh bash ksh zsh py pl pm rb cmake mk make go rs swift", t, " "); for (i in t) pext[t[i]] = 1
  split("return else case goto do if while for switch sizeof typeof throw new delete co_return co_await", t, " "); for (i in t) kw[t[i]] = 1
  pathre = "(shim|polyfill|back-?fill|compat)"
  annre = "(polyfill|back-?fill|backport(ed)? of|compat(ibility)? shim|shim for|fallback (implementation|for)|(missing|absent|unavailable|not available) (on|in|from|before|prior to) (mac ?os ?x? ?|os x )?(10\\.[0-9]|mavericks)|(10\\.9|mavericks) (lacks|does not have|doesn't have))"
}
FNR == NR {
  if (!($1 in sym)) names[++nsym] = $1
  if (!($1 in sym) || $2 == "known") sym[$1] = $2
  next
}
{
  cur = $0
  if (cur == "compatibility-inventory.tsv") next
  if (tolower(cur) ~ pathre) emit(cur, 0, "suspicious-path", "-", "path names a shim, polyfill, backfill or compat component")
  scan(cur, ftype(cur))
}
END { exit bad }
