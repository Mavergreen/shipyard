# platform: host-agnostic
#   usage: plist-facts.py <plist>
#          Prints one "<key-path>\t<value>" line per scalar in an XML or binary plist: dictionary keys
#          and list indexes joined by ":", so {outside: [a, b]} gives "outside:0\ta" and "outside:1\tb".
#          Booleans print as true or false, data as hex, and a tab or newline inside a value as a
#          space. Exits 4, naming the file, when the plist cannot be read.
# spec: claude-plugins/mavergreen/skills/mavergreen-conventions/SKILL.md "Artifact conformance" -- the
#       stand-in for PlistBuddy, which exists on no host but a Mac.
import plistlib
import sys


def scalar(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (bytes, bytearray)):
        return bytes(v).hex()
    if hasattr(v, "isoformat"):
        return v.isoformat()
    return str(v)


def walk(v, path, out):
    if isinstance(v, dict):
        for k, x in v.items():
            walk(x, path + [str(k)], out)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            walk(x, path + [str(i)], out)
    else:
        text = scalar(v).replace("\t", " ").replace("\r", " ").replace("\n", " ")
        out.append(":".join(path) + "\t" + text)


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: plist-facts.py <plist>\n")
        return 2
    try:
        with open(sys.argv[1], "rb") as f:
            data = plistlib.load(f)
    except Exception as e:
        sys.stderr.write("plist-facts: cannot read %s: %s\n" % (sys.argv[1], e))
        return 4
    out = []
    walk(data, [], out)
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    return 0


sys.exit(main())
