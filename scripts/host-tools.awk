# platform: host-agnostic
# spec: scripts/check-host-tools.sh -- reads ONE host-agnostic file and prints
#       "<line>\t<tool>\t<text>" for every macOS-only tool it finds at command position. A lexer,
#       not a line regex, because check 18's line regex is blind to a bare "(", a path, a prefix
#       command and a multi-line string, and real breakage hid in each.
function report(tool) { printf "%d\t%s\t%s\n", FNR, tool, $0 }
function push(v) { st[++depth] = v }
function word_done(   base) {
  if (!inword) return
  inword = 0
  if (!cmdpos) return
  if (skiparg) { skiparg = 0; return }
  if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) return
  if (w in prefix) { flags = 1; sudo = (w == "sudo"); cmdword = w; return }
  if (flags && cmdword == "command" && w ~ /^-[vV]$/) { cmdpos = 0; flags = 0; return }
  if (flags && w ~ /^-/) { if (sudo && w ~ /^-[ugCph]$/) skiparg = 1; return }
  cmdpos = 0; flags = 0; sudo = 0
  if (fndef) return
  base = w; sub(/.*\//, "", base)
  if ((base in ban) && !guard) report(base)
}
function atcmd() { word_done(); cmdpos = 1; flags = 0; sudo = 0; skiparg = 0 }
BEGIN {
  n = split("otool lipo sw_vers installer pkgutil pkgbuild productbuild codesign xcrun plutil hdiutil sips defaults launchctl softwareupdate system_profiler diskutil PlistBuddy", b, " ")
  for (i = 1; i <= n; i++) ban[b[i]] = 1
  n = split("sudo command exec time nohup env run xargs then do else elif if while until ! {", b, " ")
  for (i = 1; i <= n; i++) prefix[b[i]] = 1
  q = ""; hd = ""; depth = 0; cont = 0
}
hd != "" { t = $0; if (hdtabs) sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
FNR == 1 && /^#!/ { next }
q == "" && !cont && /^[ \t]*#/ { guard = ($0 ~ /^[ \t]*# platform: guarded macOS-only call -- /); next }
{
  s = $0; L = length(s); i = 1
  if (q == "" && !cont) atcmd()
  cont = 0; pend = ""
  while (i <= L) {
    c = substr(s, i, 1)
    if (q == "S") { if (c == "'") q = ""; else if (inword) w = w c; i++; continue }
    if (c == "\\") {
      if (i == L) { cont = 1; i++; continue }
      if (inword) w = w substr(s, i + 1, 1); i += 2; continue
    }
    if (c == "`") {
      if (depth > 0 && substr(st[depth], 1, 1) == "`") { word_done(); q = substr(st[depth], 2, 1); if (q == "N") q = ""; depth--; i++; continue }
      push("`" (q == "D" ? "D" : "N")); q = ""; atcmd(); i++; continue
    }
    if (q == "D") {
      if (c == "\"") q = ""
      else if (c == "$" && substr(s, i + 1, 1) == "(" && substr(s, i + 2, 1) != "(") { push("(D"); q = ""; atcmd(); i += 2; continue }
      else if (inword) w = w c
      i++; continue
    }
    if (c == "'") { q = "S"; if (cmdpos && !inword) { inword = 1; w = "" } i++; continue }
    if (c == "\"") { q = "D"; if (cmdpos && !inword) { inword = 1; w = "" } i++; continue }
    if (c == " " || c == "\t") { word_done(); i++; continue }
    if (c == "#" && !inword) break
    if (c == "$" && substr(s, i + 1, 1) == "(") {
      if (substr(s, i + 2, 1) == "(") {
        e = index(substr(s, i), "))"); if (e == 0) e = L - i
        if (inword) w = w substr(s, i, e + 1); i += e + 1; continue
      }
      push("(N"); atcmd(); i += 2; continue
    }
    if (c == "$" && substr(s, i + 1, 1) == "{") {
      e = index(substr(s, i), "}"); if (e == 0) e = L - i + 1
      if (inword) w = w substr(s, i, e); i += e; continue
    }
    if (c == "(") {
      fndef = (inword && substr(s, i + 1, 1) == ")")
      word_done(); fndef = 0
      if (substr(s, i + 1, 1) == ")") { i += 2; atcmd(); continue }
      push("(N"); atcmd(); i++; continue
    }
    if (c == ")") {
      word_done()
      if (depth > 0 && substr(st[depth], 1, 1) == "(") { q = substr(st[depth], 2, 1); if (q == "N") q = ""; depth--; cmdpos = 0 }
      else atcmd()
      i++; continue
    }
    if (c == ";" || c == "&" || c == "|") { atcmd(); i++; continue }
    if (c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<") {
      word_done(); r = substr(s, i + 2); hdtabs = (substr(r, 1, 1) == "-"); if (hdtabs) r = substr(r, 2)
      sub(/^[ \t]*/, "", r); gsub(/["'\\]/, "", r); match(r, /^[A-Za-z_][A-Za-z0-9_]*/)
      if (RLENGTH > 0) pend = substr(r, 1, RLENGTH)
      i += 2; continue
    }
    if (c == "<" || c == ">") { word_done(); cmdpos = 0; i++; continue }
    if (!inword) { inword = 1; w = "" }
    w = w c; i++
  }
  if (q == "") word_done()
  guard = 0
  if (pend != "") hd = pend
}
