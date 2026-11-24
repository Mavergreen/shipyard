#!/usr/bin/env python3
# platform: host-agnostic
"""usage: macho-pure-go.py FILE
       macho-pure-go.py --go-trimpath FILE

Prints one line per arm64 or arm64e slice of the Mach-O FILE, read without codesign, otool or lipo:

  <arch> <cgo> <linker> <loads> <platform> <minos> <codesig>

  cgo       the CGO_ENABLED build setting Go's build info records; "none" when the build info
            records none, "not-go" when the slice carries no Go build info, "unreadable" when it
            carries one this cannot read
  linker    "internal" for Go's own linker; "external" when -ldflags asks for -linkmode=external
            or LC_BUILD_VERSION lists a tool (Go's linker lists none, Apple's ld lists itself)
  loads     every LC_LOAD_DYLIB-family path, comma-separated, spaces as %20 and % as %25; "-" for none
  platform  LC_BUILD_VERSION's platform number (1 is macOS); "none" without one
  minos     LC_BUILD_VERSION's minos as otool prints it; "-" without one
  codesig   "ok" when the embedded CodeDirectory is an ad-hoc SHA-256 one whose every code-page
            hash matches the slice; otherwise the first finding, one word

--go-trimpath prints instead one line per slice of any arch that carries Go build info:

  <arch> yes|no|unreadable    whether the build info records -trimpath=true

Exit 0 with lines; 1 if FILE is not Mach-O or has no arm64 slice (with --go-trimpath, 0 with no lines
for a Mach-O that is not Go); 2 on a usage error.
"""
import hashlib
import struct
import sys

CPU_ARM64 = 0x0100000C
LOADS = {0xC, 0x20, 0x80000018, 0x8000001F, 0x80000023}
LC_SEGMENT_64 = 0x19
LC_BUILD_VERSION = 0x32
LC_CODE_SIGNATURE = 0x1D
BUILDINFO_MAGIC = b"\xff Go buildinf:"
CS_ADHOC = 0x2


def thin_slices(data):
    magic = data[:4]
    if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        wide = magic == b"\xca\xfe\xba\xbf"
        n = struct.unpack(">I", data[4:8])[0]
        out = []
        for i in range(n):
            if wide:
                ct, cs, off, size = struct.unpack(">IIQQ", data[8 + 32 * i:8 + 32 * i + 24])
            else:
                ct, cs, off, size = struct.unpack(">IIII", data[8 + 20 * i:8 + 20 * i + 16])
            out.append((ct, cs & 0xFFFFFF, data[off:off + size]))
        return out
    if magic == b"\xcf\xfa\xed\xfe":
        ct, cs = struct.unpack("<II", data[4:12])
        return [(ct, cs & 0xFFFFFF, data)]
    return None


def uvarint(buf, pos):
    shift = value = 0
    while True:
        b = buf[pos]
        pos += 1
        value |= (b & 0x7F) << shift
        if b < 0x80:
            return value, pos
        shift += 7


def build_settings(m, sections):
    blob = sections.get((b"__DATA", b"__go_buildinfo"))
    if blob is None:
        at = m.find(BUILDINFO_MAGIC)
        while at >= 0 and at % 16:
            at = m.find(BUILDINFO_MAGIC, at + 1)
        if at < 0:
            return None
        blob = m[at:at + 64 * 1024]
    if not blob.startswith(BUILDINFO_MAGIC):
        return None
    if len(blob) < 32 or not blob[15] & 0x2:
        return "unreadable"
    try:
        n, pos = uvarint(blob, 32)
        pos += n
        n, pos = uvarint(blob, pos)
        mod = blob[pos:pos + n]
    except IndexError:
        return "unreadable"
    if len(mod) >= 33 and mod[-17:-16] == b"\n":
        mod = mod[16:-16]
    settings = {}
    for line in mod.decode("utf-8", "replace").split("\n"):
        if line.startswith("build\t") and "=" in line:
            k, _, v = line[6:].partition("=")
            settings[k] = v
    return settings


def verify_signature(m, dataoff, datasize):
    sig = m[dataoff:dataoff + datasize]
    if len(sig) < 12 or len(sig) != datasize:
        return "signature-truncated"
    magic, _, count = struct.unpack(">III", sig[:12])
    if magic != 0xFADE0CC0:
        return "not-a-superblob"
    cd_off = None
    for i in range(count):
        typ, off = struct.unpack(">II", sig[12 + 8 * i:20 + 8 * i])
        if typ == 0:
            cd_off = off
    if cd_off is None:
        return "no-codedirectory"
    cd = sig[cd_off:]
    if len(cd) < 44 or struct.unpack(">I", cd[:4])[0] != 0xFADE0C02:
        return "bad-codedirectory"
    (_, length, _, flags, hash_off, _, _, nslots, code_limit,
     hash_size, hash_type, _, page_log) = struct.unpack(">IIIIIIIIIBBBB", cd[:40])
    if hash_type != 2 or hash_size != 32:
        return "hash-type-%d-not-sha256" % hash_type
    if not flags & CS_ADHOC:
        return "not-adhoc"
    if code_limit != dataoff:
        return "codelimit-%d-not-%d" % (code_limit, dataoff)
    page = 1 << page_log if page_log else code_limit
    if nslots != (code_limit + page - 1) // page:
        return "slots-%d-cover-not-%d" % (nslots, code_limit)
    if hash_off + nslots * hash_size > length:
        return "slots-outside-codedirectory"
    for i in range(nslots):
        want = cd[hash_off + i * hash_size:hash_off + (i + 1) * hash_size]
        got = hashlib.sha256(m[i * page:min((i + 1) * page, code_limit)]).digest()
        if got != want:
            return "page-%d-hash-mismatch" % i
    return "ok"


ARCHS = {0x01000007: "x86_64", 0x0100000C: "arm64", 7: "i386", 18: "ppc", 0x01000012: "ppc64"}


def go_trimpath(m):
    sections = {}
    if m[:4] == b"\xcf\xfa\xed\xfe":
        ncmds = struct.unpack("<I", m[16:20])[0]
        pos = 32
        for _ in range(ncmds):
            cmd, size = struct.unpack("<II", m[pos:pos + 8])
            if cmd == LC_SEGMENT_64:
                nsects = struct.unpack("<I", m[pos + 64:pos + 68])[0]
                for j in range(nsects):
                    s = pos + 72 + 80 * j
                    ssize = struct.unpack("<Q", m[s + 40:s + 48])[0]
                    soff = struct.unpack("<I", m[s + 48:s + 52])[0]
                    sections[(m[s + 16:s + 32].rstrip(b"\0"), m[s:s + 16].rstrip(b"\0"))] = m[soff:soff + ssize]
            pos += size
    settings = build_settings(m, sections)
    if settings is None:
        return None
    if settings == "unreadable":
        return "unreadable"
    return "yes" if settings.get("-trimpath") == "true" else "no"


def judge(m):
    if m[:4] != b"\xcf\xfa\xed\xfe":
        return None
    ncmds = struct.unpack("<I", m[16:20])[0]
    pos = 32
    loads, sections = [], {}
    platform, minos, ntools, sigcmd = "none", "-", 0, None
    for _ in range(ncmds):
        cmd, size = struct.unpack("<II", m[pos:pos + 8])
        if cmd in LOADS:
            name_off = struct.unpack("<I", m[pos + 8:pos + 12])[0]
            name = m[pos + name_off:pos + size].split(b"\0", 1)[0].decode("utf-8", "replace")
            loads.append(name.replace("%", "%25").replace(" ", "%20"))
        elif cmd == LC_BUILD_VERSION:
            p, mn, _, ntools = struct.unpack("<IIII", m[pos + 8:pos + 24])
            platform = str(p)
            minos = "%d.%d" % (mn >> 16, (mn >> 8) & 0xFF) + (".%d" % (mn & 0xFF) if mn & 0xFF else "")
        elif cmd == LC_CODE_SIGNATURE:
            sigcmd = struct.unpack("<II", m[pos + 8:pos + 16])
        elif cmd == LC_SEGMENT_64:
            nsects = struct.unpack("<I", m[pos + 64:pos + 68])[0]
            for j in range(nsects):
                s = pos + 72 + 80 * j
                sect, seg = m[s:s + 16].rstrip(b"\0"), m[s + 16:s + 32].rstrip(b"\0")
                ssize = struct.unpack("<Q", m[s + 40:s + 48])[0]
                soff = struct.unpack("<I", m[s + 48:s + 52])[0]
                sections[(seg, sect)] = m[soff:soff + ssize]
        pos += size
    settings = build_settings(m, sections)
    if settings is None:
        cgo = "not-go"
    elif settings == "unreadable":
        cgo, settings = "unreadable", {}
    else:
        cgo = settings.get("CGO_ENABLED", "none")
    ldflags = (settings or {}).get("-ldflags", "")
    external = "linkmode=external" in ldflags or "linkmode external" in ldflags or ntools > 0
    codesig = "unsigned" if sigcmd is None else verify_signature(m, *sigcmd)
    return "%s %s %s %s %s" % (cgo or "none", "external" if external else "internal",
                               ",".join(loads) or "-", platform, minos) + " " + codesig


def main(argv):
    trim = len(argv) == 3 and argv[1] == "--go-trimpath"
    if trim:
        argv = argv[:1] + argv[2:]
    if len(argv) != 2 or argv[1].startswith("--"):
        print("usage: macho-pure-go.py [--go-trimpath] FILE", file=sys.stderr)
        return 2
    try:
        with open(argv[1], "rb") as f:
            data = f.read()
    except OSError as e:
        print("macho-pure-go: %s" % e, file=sys.stderr)
        return 2
    slices = thin_slices(data)
    if not slices:
        return 1
    if trim:
        for ct, cs, m in slices:
            try:
                t = go_trimpath(m)
            except (struct.error, IndexError):
                t = "unreadable"
            if t:
                arch = ARCHS.get(ct, "cpu-%x" % ct)
                print("%s %s" % ("arm64e" if arch == "arm64" and cs == 2 else arch, t))
        return 0
    printed = False
    for ct, cs, m in slices:
        if ct != CPU_ARM64:
            continue
        try:
            line = judge(m)
        except (struct.error, IndexError):
            line = None
        arch = "arm64e" if cs == 2 else "arm64"
        print("%s %s" % (arch, line if line else "unreadable internal - none - unreadable"))
        printed = True
    return 0 if printed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
