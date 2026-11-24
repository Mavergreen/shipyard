#!/usr/bin/env python3
# platform: host-agnostic
"""Validate a pinned product archive before extracting or reusing its cache."""
import hashlib
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import tarfile
import tempfile

STAMP = '.mavergreen-archive-sha256'
TRUST = '.mavergreen-tree-verified'


def sha(stream):
    h = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        h.update(chunk)
    return h.hexdigest()


def identity(root):
    h = hashlib.sha256()
    for here, dirs, files in os.walk(root):
        dirs.sort()
        here = Path(here)
        for name in sorted(dirs + files):
            if name == TRUST and here == root:
                continue
            st = os.lstat(here / name)
            target = os.readlink(here / name) if stat.S_ISLNK(st.st_mode) else ''
            size, mtime = (st.st_size, st.st_mtime_ns) if stat.S_ISREG(st.st_mode) else (0, 0)
            h.update(f'{(here / name).relative_to(root)}\0{st.st_mode}\0{size}\0{mtime}\0{target}\n'.encode('utf-8', 'surrogateescape'))
    return h.hexdigest()


def trusted(root, digest):
    stamp = root / TRUST
    if root.is_symlink() or not root.is_dir() or not stamp.is_file() or stamp.is_symlink():
        return False
    try:
        return stamp.read_text() == f'{digest}\n{identity(root)}\n'
    except OSError:
        return False


def trust(root, digest):
    temporary = root / f'{TRUST}.{os.getpid()}'
    temporary.write_text(f'{digest}\n{identity(root)}\n')
    temporary.rename(root / TRUST)


def members(archive, short):
    prefix = PurePosixPath('opt/mavergreen') / short
    selected = {}
    seen = set()
    for m in archive.getmembers():
        name = PurePosixPath(m.name)
        if name.is_absolute() or '..' in name.parts or str(name) in seen:
            raise ValueError(f'unsafe or duplicate archive entry: {m.name}')
        seen.add(str(name))
        if m.isdir() and name in prefix.parents:
            continue
        try:
            relative = name.relative_to(prefix)
        except ValueError:
            raise ValueError(f'entry outside product prefix: {m.name}')
        if str(relative) == '.' and not m.isdir():
            raise ValueError('product prefix is not a directory')
        if str(relative) == STAMP or not (m.isfile() or m.isdir() or m.issym()):
            raise ValueError(f'unsupported archive entry: {m.name}')
        if m.mode & 0o7000:
            raise ValueError(f'special permission bits: {m.name}')
        if m.issym() and PurePosixPath(m.linkname).is_absolute():
            raise ValueError(f'absolute symlink: {m.name}')
        selected[str(name)] = (relative, m)
    if not selected:
        raise ValueError('empty product archive')
    symlinks = {PurePosixPath(n) for n, (_, m) in selected.items() if m.issym()}
    for n in selected:
        if any(parent in symlinks for parent in PurePosixPath(n).parents):
            raise ValueError(f'entry beneath a symlink: {n}')
    return list(selected.values())


def check_links(root, entries):
    for rel, m in entries:
        p = root / str(rel)
        if m.issym():
            resolved = p.resolve(strict=True)
            if not resolved.is_relative_to(root.resolve()):
                raise ValueError(f'symlink escapes product: {rel}')


def compare(archive, root, entries):
    for rel, m in entries:
        p = root / str(rel)
        for parent in p.parents:
            if parent == root:
                break
            if parent.is_symlink():
                raise ValueError(f'cached parent became a symlink: {rel}')
        if m.issym():
            if not p.is_symlink() or os.readlink(p) != m.linkname:
                raise ValueError(f'cached link changed: {rel}')
        elif m.isdir():
            if not p.is_dir() or p.is_symlink():
                raise ValueError(f'cached directory changed: {rel}')
        else:
            if not p.is_file() or p.is_symlink() or stat.S_IMODE(p.stat().st_mode) != m.mode:
                raise ValueError(f'cached file type/mode changed: {rel}')
            # spec: implicit parent directories must also stay inside the product tree
            if not p.resolve().is_relative_to(root.resolve()):
                raise ValueError(f'cached parent escapes product: {rel}')
            with archive.extractfile(m) as expected, p.open('rb') as actual:
                if sha(expected) != sha(actual):
                    raise ValueError(f'cached file contents changed: {rel}')
    check_links(root, entries)


def install(archive_path, short, digest, destination):
    if destination.is_symlink():
        raise ValueError('destination must not be a symlink')
    destination = Path(os.path.realpath(destination.parent)) / destination.name
    with tarfile.open(archive_path, 'r:gz') as archive:
        entries = members(archive, short)
        stamp = destination / STAMP
        if stamp.is_file() and not stamp.is_symlink() and stamp.read_text() == digest + '\n':
            compare(archive, destination, entries)
            trust(destination, digest)
            return
        with tempfile.TemporaryDirectory(prefix=destination.name+'.tmp.', dir=destination.parent) as scratch:
            root = Path(scratch)/'product'; root.mkdir()
            for rel, m in entries:
                p = root/str(rel)
                p.parent.mkdir(parents=True, exist_ok=True)
                if m.isdir():
                    p.mkdir(exist_ok=True)
                elif m.isfile():
                    with archive.extractfile(m) as source, p.open('xb') as output:
                        shutil.copyfileobj(source, output)
                    p.chmod(m.mode)
            for rel, m in entries:
                if m.issym():
                    (root/str(rel)).symlink_to(m.linkname)
            check_links(root, entries)
            compare(archive, root, entries)
            (root/STAMP).write_text(digest+'\n')
            old = Path(scratch)/'old'
            if destination.exists():
                destination.rename(old)
            try:
                root.rename(destination)
            except BaseException:
                if old.exists(): old.rename(destination)
                raise
        trust(destination, digest)


if __name__ == '__main__':
    try:
        if sys.argv[1] == '--trusted':
            sys.exit(0 if trusted(Path(sys.argv[3]), sys.argv[2]) else 1)
        install(Path(sys.argv[1]), sys.argv[2], sys.argv[3], Path(sys.argv[4]))
    except (OSError, ValueError, RuntimeError, tarfile.TarError) as error:
        sys.exit(f'product-tar: {error}')
