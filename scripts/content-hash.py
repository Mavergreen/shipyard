# platform: host-agnostic -- Python 3 standard library only
#   usage: content-hash.py FILE TOKEN...
#          content-hash.py --rows ARTIFACT ROOT PREFIX MODES SCOPES TOKEN...
#          The first form prints the SHA-256 of FILE's bytes with each TOKEN replaced by @VERSION@,
#          read in 1 MiB chunks, so a token across a chunk boundary is replaced too.
#          --rows prints content-manifest.sh's rows for the tree at ROOT: "file ARTIFACT PATH MODE SHA",
#          "link ARTIFACT PATH TARGET" and "dir ARTIFACT PATH MODE". PATH is PREFIX ("" or "a/b/") then
#          the path below ROOT; PATH and TARGET have each TOKEN replaced by @VERSION@, then "%" and space
#          written %25 and %20. MODES is af_payload_modes' listing ("<path> <uid> <gid> <ls mode>") naming
#          the entries and their modes, or - to walk ROOT and read the modes from it. A PATH matching a
#          line of the file SCOPES as a shell case pattern, before replacement, gets no row. Exit 1 on a
#          path holding a newline or a tab, or an unreadable entry; 2 on usage.
import fnmatch
import hashlib
import os
import stat
import sys

CHUNK = 1 << 20
MARK = b"@VERSION@"


def usage():
    sys.stderr.write("usage: content-hash.py FILE TOKEN... | --rows ARTIFACT ROOT PREFIX MODES SCOPES TOKEN...\n")
    sys.exit(2)


def tokens_of(args):
    toks = sorted({t.encode() for t in args if t}, key=len, reverse=True)
    if not toks:
        usage()
    return toks


def replace(data, toks):
    for t in toks:
        data = data.replace(t, MARK)
    return data


def file_hash(path, toks):
    h = hashlib.sha256()
    keep = max(len(t) for t in toks) - 1
    carry = b""
    with open(path, "rb") as f:
        while True:
            chunk = f.read(CHUNK)
            buf = carry + chunk
            cut = len(buf) if not chunk else max(len(buf) - keep, 0)
            pos = 0
            while True:
                hits = [(buf.find(t, pos), t) for t in toks]
                hits = [(i, t) for i, t in hits if 0 <= i < cut]
                if not hits:
                    break
                i, t = min(hits, key=lambda x: (x[0], -len(x[1])))
                h.update(buf[pos:i])
                h.update(MARK)
                pos = i + len(t)
            end = max(pos, cut)
            h.update(buf[pos:end])
            carry = buf[end:]
            if not chunk:
                break
    return h.hexdigest()


def enc(b):
    return b.replace(b"%", b"%25").replace(b" ", b"%20").decode("utf-8", "surrogateescape")


def ls_mode(s):
    if len(s) != 10:
        raise ValueError(s)
    m = 0
    for i, (r, w, x) in enumerate(((1, 2, 3), (4, 5, 6), (7, 8, 9))):
        shift = 6 - 3 * i
        if s[r] == "r":
            m |= 4 << shift
        if s[w] == "w":
            m |= 2 << shift
        if s[x] in "xst":
            m |= 1 << shift
    if s[3] in "sS":
        m |= 0o4000
    if s[6] in "sS":
        m |= 0o2000
    if s[9] in "tT":
        m |= 0o1000
    return m


def listed(root, modes):
    out = []
    with open(modes, "rb") as f:
        for line in f:
            parts = line.rstrip(b"\n").split(b" ")
            if len(parts) != 4:
                raise ValueError(line)
            p = parts[0].replace(b"%20", b" ").replace(b"%25", b"%")
            if p == b".":
                continue
            kind = {"-": "f", "d": "d", "l": "l"}[parts[3][:1].decode()]
            out.append((p, kind, ls_mode(parts[3].decode())))
    return out


def walked(root):
    out = []
    rb = os.fsencode(root)
    for d, dirs, files in os.walk(rb):
        for name in dirs + files:
            full = os.path.join(d, name)
            st = os.lstat(full)
            rel = os.path.relpath(full, rb)
            if stat.S_ISLNK(st.st_mode):
                kind = "l"
            elif stat.S_ISDIR(st.st_mode):
                kind = "d"
            elif stat.S_ISREG(st.st_mode):
                kind = "f"
            else:
                raise ValueError(full)
            out.append((rel, kind, stat.S_IMODE(st.st_mode)))
    return out


def rows(artifact, root, prefix, modes, scopes, toks):
    with open(scopes, "rb") as f:
        globs = [os.fsdecode(g) for g in f.read().split(b"\n") if g]
    entries = walked(root) if modes == "-" else listed(root, modes)
    rb = os.fsencode(root)
    pb = os.fsencode(prefix)
    out = []
    for rel, kind, mode in entries:
        if b"\n" in rel or b"\t" in rel:
            sys.stderr.write("content-hash: a path holds a newline or a tab: %r\n" % rel)
            sys.exit(1)
        path = pb + rel
        if any(fnmatch.fnmatchcase(os.fsdecode(path), g) for g in globs):
            continue
        full = os.path.join(rb, rel)
        shown = enc(replace(path, toks))
        if kind == "d":
            out.append("dir %s %s %04o" % (artifact, shown, mode))
        elif kind == "l":
            target = os.readlink(full)
            if b"\n" in target or b"\t" in target:
                sys.stderr.write("content-hash: a link target holds a newline or a tab: %r\n" % rel)
                sys.exit(1)
            out.append("link %s %s %s" % (artifact, shown, enc(replace(target, toks))))
        else:
            out.append("file %s %s %04o %s" % (artifact, shown, mode, file_hash(full, toks)))
    sys.stdout.write("".join(r + "\n" for r in out))


def main(argv):
    try:
        if argv[:1] == ["--rows"]:
            if len(argv) < 7:
                usage()
            rows(argv[1], argv[2], argv[3], argv[4], argv[5], tokens_of(argv[6:]))
        else:
            if len(argv) < 2 or argv[0].startswith("-"):
                usage()
            print(file_hash(argv[0], tokens_of(argv[1:])))
    except (OSError, ValueError, KeyError) as e:
        sys.stderr.write("content-hash: %s\n" % e)
        sys.exit(1)


main(sys.argv[1:])
