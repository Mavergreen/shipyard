# platform: host-agnostic -- Python 3 standard library only
#   usage: icon-tool.py fingerprint FILE
#          icon-tool.py distance FINGERPRINT FINGERPRINT
#          icon-tool.py similar FINGERPRINT FINGERPRINT
#          icon-tool.py find FINGERPRINT ROOT
#          icon-tool.py cat ROOT PATH
#          What check-preset-icons.sh needs to tell whether two icons are the same picture, without
#          keeping either. A FINGERPRINT is one line:
#            sha256:<hex> dhash:<16 hex> <W>x<H> colour:<12 hex>
#          dhash is a 64-bit difference hash of the icon composited onto white and reduced to 9x8
#          grey: its Hamming distance is small for the same picture at any size and large for a
#          different one. colour is the alpha-weighted mean RGB of the icon's opaque part, then the
#          mean RGB of the whole icon on white: a recolour moves it when the shape does not.
#          distance prints "dhash:<bits> colour:<largest channel difference>"; similar exits 0 when
#          both are within SAME_DHASH and SAME_COLOUR (the same picture, not recoloured), else 1.
#          find prints "<path>\t<dhash distance>" for the PNG under ROOT closest to FINGERPRINT, paths
#          from ROOT with a leading /, a PNG inside an Electron asar as "<asar path>:<entry>".
#          cat writes such a path's bytes to stdout.
#          same-dhash prints the difference-hash threshold within which two icons are the same picture.
#          A PNG this can't decode (interlaced, truncated, larger than 2048 px, or 1024 px for find)
#          is refused by fingerprint and skipped by find, as are symlinks and unreadable archives.
# spec: .superpowers/specs/2026-11-21-preset-icon-provenance-design.md (tests/icon-tool-test.sh)
import hashlib, json, os, struct, sys, zlib

MAX_FIND = 1024
MAX_FINGERPRINT = 2048
# Calibrated 2026-11-20 on 1Password's icons against its package's 512 px icon: the same picture from
# another source scored dhash 4; a recoloured, similar shape scored dhash 15 / colour 80; the same
# picture on an opaque square scored dhash 34 / colour 23.
SAME_DHASH = 10
SAME_COLOUR = 40


class NotDecodable(Exception):
    pass


def ihdr(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise NotDecodable("not a PNG")
    w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", data[16:29])
    return w, h, depth, ctype, interlace


def decode(data):
    """PNG bytes -> (w, h, [(r, g, b, a)] row-major, 8 bits per channel)."""
    w, h, depth, ctype, interlace = ihdr(data)
    if not w or not h:
        raise NotDecodable("a PNG with no pixels")
    if interlace:
        raise NotDecodable("interlaced PNG (Adam7) is not supported")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ctype)
    if channels is None:
        raise NotDecodable("unknown PNG colour type %d" % ctype)
    pos, idat, pal, trns = 8, b"", [], None
    while pos + 8 <= len(data):
        n, t = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if t == b"IEND": break
        if t == b"IDAT": idat += body
        elif t == b"PLTE": pal = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif t == b"tRNS": trns = body
        pos += 12 + n
    raw = zlib.decompress(idat)
    if ctype == 3 and not pal:
        raise NotDecodable("a palette PNG with no palette")
    if len(raw) < h * (1 + (w * channels * depth + 7) // 8):
        raise NotDecodable("truncated PNG data")
    bits = channels * depth
    bpp = max(1, bits // 8)
    stride = (w * bits + 7) // 8
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[i]; line = bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line); prev = line
    # tRNS on a grey or RGB image names one colour (16-bit samples) that is transparent
    key = None
    if trns and ctype in (0, 2) and len(trns) >= 2 * channels:
        raw_key = struct.unpack(">%dH" % channels, trns[:2 * channels])
        key = tuple(k >> 8 if depth == 16 else k * (255 // ((1 << depth) - 1)) if depth < 8 else k
                    for k in raw_key)
    px = []
    for line in rows:
        if depth < 8:
            vals = []
            for byte in line:
                for s in range(8 - depth, -1, -depth): vals.append((byte >> s) & ((1 << depth) - 1))
            samples = vals[:w * channels]
            scale = 255 // ((1 << depth) - 1) if ctype != 3 else 1
            samples = [v * scale for v in samples]
        elif depth == 16:
            samples = list(line[0::2])
        else:
            samples = list(line)
        for x in range(w):
            s = samples[x * channels:(x + 1) * channels]
            if ctype == 3:
                r, g, b = pal[s[0]]
                a = trns[s[0]] if trns and s[0] < len(trns) else 255
            elif ctype == 0: r = g = b = s[0]; a = 0 if key == (s[0],) else 255
            elif ctype == 4: r = g = b = s[0]; a = s[1]
            elif ctype == 2: r, g, b = s; a = 0 if key == tuple(s) else 255
            else: r, g, b, a = s
            px.append((r, g, b, a))
    return w, h, px


def fingerprint(data):
    w, h = ihdr(data)[:2]
    if w > MAX_FINGERPRINT or h > MAX_FINGERPRINT:
        raise NotDecodable("%dx%d is larger than %d px" % (w, h, MAX_FINGERPRINT))
    w, h, px = decode(data)
    cells = [[0.0] * 9 for _ in range(8)]
    count = [[0] * 9 for _ in range(8)]
    fg, fga, whole = [0.0, 0.0, 0.0], 0.0, [0.0, 0.0, 0.0]
    for y in range(h):
        cy = y * 8 // h
        for x in range(w):
            r, g, b, a = px[y * w + x]
            k = a / 255.0
            on = [c * k + 255 * (1 - k) for c in (r, g, b)]
            for j in range(3): whole[j] += on[j]; fg[j] += (r, g, b)[j] * k
            fga += k
            cx = x * 9 // w
            cells[cy][cx] += 0.299 * on[0] + 0.587 * on[1] + 0.114 * on[2]
            count[cy][cx] += 1
    grey = [[cells[r][c] / max(1, count[r][c]) for c in range(9)] for r in range(8)]
    bits = 0
    for r in range(8):
        for c in range(8):
            bits = (bits << 1) | (1 if grey[r][c] > grey[r][c + 1] else 0)
    n = float(w * h)
    colour = [round(v / fga) if fga else 255 for v in fg] + [round(v / n) for v in whole]
    return "sha256:%s dhash:%016x %dx%d colour:%s" % (
        hashlib.sha256(data).hexdigest(), bits, w, h, "".join("%02x" % c for c in colour))


def parse(fp):
    try:
        f = dict(p.split(":", 1) for p in fp.split() if ":" in p)
        d, c = int(f["dhash"], 16), bytes.fromhex(f["colour"])
    except (KeyError, ValueError):
        raise NotDecodable("not a fingerprint: %r" % fp)
    if len(c) != 6:
        raise NotDecodable("not a fingerprint: %r" % fp)
    return d, c


def distance(a, b):
    (da, ca), (db, cb) = parse(a), parse(b)
    return bin(da ^ db).count("1"), max(abs(x - y) for x, y in zip(ca, cb))


def asar_entries(path):
    """(entry name, bytes) for each .png inside an Electron asar."""
    with open(path, "rb") as f:
        head = f.read(16)
        if len(head) < 16: return
        _, hsize, _, jlen = struct.unpack("<IIII", head)
        tree = json.loads(f.read(jlen))
        base = 8 + hsize
        def walk(node, prefix):
            for name, n in node.get("files", {}).items():
                full = prefix + name
                if "files" in n: yield from walk(n, full + "/")
                elif name.lower().endswith(".png") and not n.get("unpacked"):
                    f.seek(base + int(n["offset"])); yield full, f.read(n["size"])
        yield from walk(tree, "")


def candidates(root):
    for d, _, files in os.walk(root):
        for name in sorted(files):
            p = os.path.join(d, name); rel = "/" + os.path.relpath(p, root)
            if os.path.islink(p): continue
            try:
                if name.lower().endswith(".png"):
                    with open(p, "rb") as f: yield rel, f.read()
                elif name.endswith(".asar"):
                    for entry, blob in list(asar_entries(p)): yield rel + ":" + entry, blob
            except (OSError, ValueError, KeyError, TypeError, AttributeError, struct.error):
                continue


def find(fp, root):
    best = None
    for rel, blob in candidates(root):
        try:
            w, h = ihdr(blob)[:2]
            if w > MAX_FIND or h > MAX_FIND: continue
            d = distance(fp, fingerprint(blob))
        except (NotDecodable, zlib.error, struct.error, IndexError, ValueError, KeyError, ZeroDivisionError):
            continue
        if best is None or d < best[0]: best = (d, rel)
    return best


def cat(root, path):
    asar, _, entry = path.partition(".asar:")
    if entry:
        for name, blob in asar_entries(os.path.join(root, asar.lstrip("/") + ".asar")):
            if name == entry: return blob
        raise FileNotFoundError(path)
    with open(os.path.join(root, path.lstrip("/")), "rb") as f: return f.read()


def main(argv):
    try:
        if len(argv) == 3 and argv[1] == "fingerprint":
            with open(argv[2], "rb") as f: print(fingerprint(f.read()))
        elif len(argv) == 4 and argv[1] == "distance":
            d, c = distance(argv[2], argv[3])
            print("dhash:%d colour:%d" % (d, c))
        elif len(argv) == 4 and argv[1] == "similar":
            d, c = distance(argv[2], argv[3])
            return 0 if d <= SAME_DHASH and c <= SAME_COLOUR else 1
        elif len(argv) == 4 and argv[1] == "find":
            best = find(argv[2], argv[3])
            if best is None: return 1
            print("%s\t%d" % (best[1], best[0][0]))
        elif len(argv) == 2 and argv[1] == "same-dhash":
            print(SAME_DHASH)
        elif len(argv) == 4 and argv[1] == "cat":
            sys.stdout.buffer.write(cat(argv[2], argv[3]))
        else:
            print(__doc__ or "usage: icon-tool.py fingerprint|distance|find|cat ...", file=sys.stderr)
            return 2
    except (NotDecodable, zlib.error, struct.error, OSError, IndexError, ValueError, KeyError,
            ZeroDivisionError) as e:
        print("icon-tool: %s" % e, file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
