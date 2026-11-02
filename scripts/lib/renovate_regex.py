# platform: host-agnostic
import re

LINE2 = re.compile(r'# renovate: datasource=\S+ depName=\S+(?: versioning=\S+)?(?: extractVersion=\S+)?[ \t]*')


def js(rx):
    out, i, cls = [], 0, False
    while i < len(rx):
        c = rx[i]
        if c == '\\':
            out.append(rx[i:i + 2]); i += 2; continue
        if cls:
            cls = c != ']'
        elif c == '[':
            cls = True
        elif c == '$':
            c = r'\Z'
        elif rx.startswith('(?<', i) and rx[i + 3:i + 4] not in ('=', '!'):
            c = '(?P<'; i += 2
        out.append(c); i += 1
    return ''.join(out)
