#!/usr/bin/env python3
# platform: host-agnostic
"""usage: pure-go-fixtures.py OUT [--cgo V] [--ldflags V] [--ntools N] [--load PATH]... [--platform N]
                              [--minos X.Y] [--unsigned] [--corrupt-page N] [--no-buildinfo] [--thin]
                              [--trimpath]

Writes OUT: a fat x86_64 + arm64 Mach-O whose arm64 slice is shaped the way Go's own linker shapes a
CGO_ENABLED=0 darwin/arm64 executable -- a __DATA,__go_buildinfo section, LC_LOAD_DYLIBs,
LC_BUILD_VERSION and an ad-hoc SHA-256 CodeDirectory over every 4096-byte page -- so
scripts/macho-pure-go.py is exercised on every host, Go or no Go. Each option bends one fact.
"""
import argparse
import hashlib
import struct

START = b"0w\xaf\x0c\x92t\x08\x02A\xe1\xc1\x07\xe6\xd6\x18\xe6"
END = b"\xf92C1\x86\x18 r\x00\x82B\x10A\x16\xd8\xf2"
PAGE = 4096


def uvarint(n):
    out = b""
    while n >= 0x80:
        out += bytes([n & 0x7F | 0x80])
        n >>= 7
    return out + bytes([n])


def buildinfo(cgo, ldflags, trimpath):
    text = "path\tfixture\nmod\tfixture\t(devel)\t\nbuild\t-buildmode=exe\nbuild\t-compiler=gc\n"
    if trimpath:
        text += "build\t-trimpath=true\n"
    if ldflags is not None:
        text += "build\t-ldflags=%s\n" % ldflags
    if cgo is not None:
        text += "build\tCGO_ENABLED=%s\n" % cgo
    text += "build\tGOARCH=arm64\nbuild\tGOOS=darwin\n"
    mod = START + text.encode() + END
    ver = b"go1.26.0"
    blob = b"\xff Go buildinf:" + bytes([8, 2]) + b"\0" * 16
    return blob + uvarint(len(ver)) + ver + uvarint(len(mod)) + mod


def arm64_slice(a):
    bi = b"" if a.no_buildinfo else buildinfo(a.cgo, a.ldflags, a.trimpath)
    loads = a.load if a.load else ["/usr/lib/libSystem.B.dylib"]
    cmds = []
    cmds.append([b"", None])
    for name in loads:
        raw = name.encode() + b"\0"
        size = (24 + len(raw) + 7) & ~7
        cmds.append([struct.pack("<IIIIII", 0xC, size, 24, 2, 0, 0) + raw.ljust(size - 24, b"\0"), None])
    if a.platform is not None:
        major, minor = (int(x) for x in a.minos.split("."))
        cmds.append([struct.pack("<IIIIII", 0x32, 24 + 8 * a.ntools, a.platform, major << 16 | minor << 8,
                                 major << 16 | minor << 8, a.ntools) + struct.pack("<II", 3, 0) * a.ntools, None])
    if not a.unsigned:
        cmds.append([b"", "sig"])
    ncmds = len(cmds)
    sizeofcmds = 152 + sum(len(c[0]) if c[1] is None else 16 for c in cmds)
    body_at = (32 + sizeofcmds + 15) & ~15
    bi_at = body_at
    code_end = bi_at + len(bi) + 3 * PAGE + 123
    code_end = (code_end + 15) & ~15
    seg_size = (code_end + PAGE - 1) & ~(PAGE - 1)
    cmds[0][0] = struct.pack("<II16sQQQQIIII", 0x19, 72 + 80, b"__DATA", 0, seg_size, 0, code_end, 3, 3, 1, 0)
    cmds[0][0] += struct.pack("<16s16sQQIIIIIIII", b"__go_buildinfo", b"__DATA", bi_at, len(bi), bi_at, 4, 0, 0, 0, 0, 0, 0)
    sig_size = 0
    if not a.unsigned:
        nslots = (code_end + PAGE - 1) // PAGE
        ident = b"fixture\0"
        cd_len = 48 + len(ident) + 32 * nslots
        sig_size = 20 + cd_len
        cmds[-1][0] = struct.pack("<IIII", 0x1D, 16, code_end, sig_size)
    head = struct.pack("<IIIIIIII", 0xFEEDFACF, 0x0100000C, 0, 2, ncmds, sizeofcmds, 0x200085, 0)
    lc = b"".join(c[0] for c in cmds)
    m = bytearray((head + lc).ljust(body_at, b"\0") + bi)
    m.extend(bytes((i * 7) & 0xFF for i in range(code_end - len(m))))
    if not a.unsigned:
        hashes = b"".join(hashlib.sha256(bytes(m[i:min(i + PAGE, code_end)])).digest()
                          for i in range(0, code_end, PAGE))
        cd = struct.pack(">IIIIIIIIIBBBBI", 0xFADE0C02, cd_len, 0x20100, 0x20002, 48 + len(ident), 48, 0,
                         nslots, code_end, 32, 2, 0, 12, 0) + struct.pack(">I", 0) + ident + hashes
        m.extend(struct.pack(">IIIII", 0xFADE0CC0, sig_size, 1, 0, 20) + cd)
    if a.corrupt_page is not None:
        m[a.corrupt_page * PAGE + 2000] ^= 0xFF
    return bytes(m)


def x86_slice():
    return struct.pack("<IIIIIIII", 0xFEEDFACF, 0x01000007, 3, 2, 0, 0, 0, 0).ljust(PAGE, b"\0")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("out")
    p.add_argument("--cgo", default="0")
    p.add_argument("--ldflags")
    p.add_argument("--ntools", type=int, default=0)
    p.add_argument("--load", action="append")
    p.add_argument("--platform", type=lambda v: None if v == "none" else int(v), default=1)
    p.add_argument("--minos", default="11.0")
    p.add_argument("--unsigned", action="store_true")
    p.add_argument("--corrupt-page", type=int)
    p.add_argument("--no-buildinfo", action="store_true")
    p.add_argument("--thin", action="store_true")
    p.add_argument("--trimpath", action="store_true")
    a = p.parse_args()
    if a.cgo == "absent":
        a.cgo = None
    arm = arm64_slice(a)
    if a.thin:
        data = arm
    else:
        x86 = x86_slice()
        x_at, a_at = 0x4000, 0x8000
        data = bytearray(struct.pack(">II", 0xCAFEBABE, 2))
        data += struct.pack(">IIIII", 0x01000007, 3, x_at, len(x86), 14)
        data += struct.pack(">IIIII", 0x0100000C, 0, a_at, len(arm), 14)
        data = bytes(data.ljust(x_at, b"\0") + x86).ljust(a_at, b"\0") + arm
    with open(a.out, "wb") as f:
        f.write(data)


if __name__ == "__main__":
    main()
