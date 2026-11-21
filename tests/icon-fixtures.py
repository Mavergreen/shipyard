# platform: host-agnostic
# Writes the icon fixtures tests/icon-tool-test.sh and tests/check-preset-icons-test.sh use: small
# generated pictures, never vendor art. usage: python3 icon-fixtures.py DIR
import json, os, struct, sys, zlib

def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

def png(path, w, h, px, mode="rgba", depth=8, interlace=0):
    """px(x, y) -> (r, g, b, a) in 0..255."""
    ctype = {"grey": 0, "rgb": 2, "pal": 3, "greya": 4, "rgba": 6}[mode]
    pal, raw = [], bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            r, g, b, a = px(x, y)
            if mode == "pal":
                if (r, g, b, a) not in pal: pal.append((r, g, b, a))
                raw.append(pal.index((r, g, b, a)))
            elif mode in ("grey", "greya"):
                v = (r * 299 + g * 587 + b * 114) // 1000
                vals = [v] + ([a] if mode == "greya" else [])
                for c in vals: raw += bytes([c, c]) if depth == 16 else bytes([c])
            else:
                vals = [r, g, b] + ([a] if mode == "rgba" else [])
                for c in vals: raw += bytes([c, c]) if depth == 16 else bytes([c])
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, depth, ctype, 0, 0, interlace))
    if mode == "pal":
        out += chunk(b"PLTE", b"".join(bytes(c[:3]) for c in pal)) + chunk(b"tRNS", bytes(c[3] for c in pal))
    out += chunk(b"IDAT", zlib.compress(bytes(raw))) + chunk(b"IEND", b"")
    open(path, "wb").write(out)

def disc(n, colour):            # a filled disc on transparency, with a light keyhole bar
    c = (n - 1) / 2
    def px(x, y):
        d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5
        if abs(x - c) < n / 10 and abs(y - c) < n / 4: return (240, 240, 240, 255)
        return colour + (255,) if d < n * 0.45 else (0, 0, 0, 0)
    return px

def bars(n):                    # a different picture: vertical stripes
    return lambda x, y: (200, 30, 30, 255) if (x * 6 // n) % 2 else (30, 30, 200, 255)

def asar(path, files):
    """An Electron asar: pickled JSON header, then the files' bytes."""
    data, tree, off = b"", {}, 0
    for name, blob in files:
        node = tree
        parts = name.split("/")
        for p in parts[:-1]: node = node.setdefault(p, {"files": {}})["files"]
        node[parts[-1]] = {"size": len(blob), "offset": str(off)}
        data += blob; off += len(blob)
    j = json.dumps({"files": tree}).encode()
    jp = j + b"\0" * ((4 - len(j) % 4) % 4)
    header = struct.pack("<II", len(jp) + 4, len(j)) + jp     # pickle: payload size, string length, string
    open(path, "wb").write(struct.pack("<II", 4, len(header)) + header + data)

if __name__ == "__main__":
    d = sys.argv[1]; os.makedirs(d, exist_ok=True)
    dark, blue = (40, 40, 45), (30, 110, 230)
    png(f"{d}/dark-64.png", 64, 64, disc(64, dark))
    png(f"{d}/dark-180.png", 180, 180, disc(180, dark))
    png(f"{d}/blue-180.png", 180, 180, disc(180, blue))
    png(f"{d}/bars-64.png", 64, 64, bars(64))
    png(f"{d}/dark-64-pal.png", 64, 64, disc(64, dark), mode="pal")
    png(f"{d}/dark-64-rgba16.png", 64, 64, disc(64, dark), mode="rgba", depth=16)
    png(f"{d}/dark-64-greya.png", 64, 64, disc(64, dark), mode="greya")
    png(f"{d}/dark-64-interlaced.png", 64, 64, disc(64, dark), interlace=1)
    open(f"{d}/not-a.png", "wb").write(b"<html/>")
    blob = open(f"{d}/dark-64.png", "rb").read()
    open(f"{d}/dark-64-trailing.png", "wb").write(blob + b"trailing junk after IEND")
    open(f"{d}/dark-64-truncated.png", "wb").write(blob[:len(blob) // 2])
    # transparency by colour key (tRNS on an RGB image): the corners are this exact colour
    png(f"{d}/dark-64-rgbkey.png", 64, 64, lambda x, y: disc(64, dark)(x, y)[:3] + (255,)
        if disc(64, dark)(x, y)[3] else (1, 2, 3, 255), mode="rgb")
    k = open(f"{d}/dark-64-rgbkey.png", "rb").read()
    i = k.index(b"IDAT") - 4
    open(f"{d}/dark-64-rgbkey.png", "wb").write(k[:i] + chunk(b"tRNS", b"\0\1\0\2\0\3") + k[i:])
    png(f"{d}/huge.png", 2100, 1, lambda x, y: (0, 0, 0, 255), mode="grey")
    open(f"{d}/bad.asar", "wb").write(struct.pack("<IIII", 4, 12, 8, 6) + b'["x"]   ')
    asar(f"{d}/app.asar", [("index.js", b"x" * 100),
                           ("images/logo.png", open(f"{d}/dark-64.png", "rb").read())])
