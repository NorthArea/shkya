#!/usr/bin/env python3
"""Create and verify a complete, relocatable local repository snapshot."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import time

MANIFEST = '__transfer_manifest__.json'


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def signature(path):
    value = path.lstat()
    return (value.st_mode, value.st_size, value.st_mtime_ns, value.st_ctime_ns)


def snapshot(root, destination):
    root = root.resolve()
    destination = destination.absolute()
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination = destination.parent.resolve() / destination.name
    if destination.is_relative_to(root):
        raise ValueError('Destination must be outside the repository (avoid recursive backups).')
    if not (root / '.git').is_dir():
        raise ValueError('Requires a standalone repository with its own .git directory.')
    if (root / '.git/objects/info/alternates').exists():
        raise ValueError('Git object alternates require a separate backup; snapshot refused.')
    partial = destination.with_name(destination.name + '.partial')
    checksum = destination.with_name(destination.name + '.sha256')
    if any(p.exists() for p in (destination, partial, checksum)):
        raise ValueError('Destination, partial file, or checksum already exists; choose a new name.')
    entries = []
    originals = []
    total = 0
    last_progress = 0

    def walk(path, name, ancestors=frozenset()):
        nonlocal total, last_progress
        before = signature(path)
        originals.append((path, before))
        info = archive.gettarinfo(str(path), arcname=name)
        if info.issym():
            target = path.resolve(strict=True)
            if target.is_relative_to(root):
                info.linkname = os.path.relpath(target, path.parent)
            elif path == root / 'tools/local/Godot.app':
                print('Materializing external tools/local/Godot.app', flush=True)
                walk(target, name, ancestors)
                return
            else:
                raise ValueError(f'Unbundled external symlink: {path} -> {target}')
        if info.isdir():
            identity = (path.stat().st_dev, path.stat().st_ino)
            if identity in ancestors:
                raise ValueError(f'Directory cycle: {path}')
            archive.addfile(info)
            entries.append({'name': name, 'type': 'directory'})
            for child in sorted(path.iterdir()):
                walk(child, name + '/' + child.name, ancestors | {identity})
        elif info.isfile():
            digest = hashlib.sha256()

            class Reader:
                def read(self, size):
                    block = source.read(size)
                    digest.update(block)
                    return block

            with path.open('rb') as source:
                archive.addfile(info, Reader())
            total += info.size
            entries.append({'name': name, 'type': 'file', 'size': info.size,
                            'sha256': digest.hexdigest()})
            if total - last_progress >= 512 * 1024 * 1024:
                print(f'Packed {total / 1024**3:.2f} GiB; {len(entries)} entries', flush=True)
                last_progress = total
        elif info.issym():
            archive.addfile(info)
            entries.append({'name': name, 'type': 'symlink', 'target': info.linkname})
        else:
            raise ValueError(f'Unsupported special file: {path}')
        if signature(path) != before:
            raise ValueError(f'Source changed while packing: {path}; stop writers and retry.')

    print('Stop editors, Godot, tests, and Git mutations until packing finishes.', flush=True)
    state = {'head': git(root, 'rev-parse', 'HEAD'),
             'status': git(root, 'status', '--porcelain=v1', '--untracked-files=all'),
             'refs': git(root, 'for-each-ref', '--format=%(refname) %(objectname)'),
             'stash': git(root, 'stash', 'list')}
    with partial.open('xb') as output:
        with tarfile.open(fileobj=output, mode='w:gz', compresslevel=1,
                          format=tarfile.PAX_FORMAT, dereference=False) as archive:
            walk(root, root.name)
            for path, before in originals:
                if signature(path) != before:
                    raise ValueError(f'Source changed during snapshot: {path}; retry with writers stopped.')
            payload = json.dumps({'format': 1, 'root': root.name, 'created_unix': time.time(),
                                  'git': state, 'entries': entries}, ensure_ascii=False,
                                 indent=2).encode('utf-8')
            import io
            info = tarfile.TarInfo(MANIFEST)
            info.size = len(payload)
            info.mode = 0o600
            archive.addfile(info, io.BytesIO(payload))
    # Publish only after every source stability check has passed.
    if destination.exists():
        raise ValueError('Destination appeared while packing; preserved .partial file.')
    partial.rename(destination)
    print('Computing archive SHA-256…', flush=True)
    with checksum.open('x') as output:
        output.write(f'{sha256(destination)}  {destination.name}\n')
    print(f'Created {destination} ({destination.stat().st_size / 1024**3:.2f} GiB)', flush=True)
    print(f'Next: python3 tools/prepare_transfer.py --verify {destination}', flush=True)


def verify(path):
    path = path.resolve(strict=True)
    expected = path.with_name(path.name + '.sha256').read_text().split()[0]
    if sha256(path) != expected:
        raise ValueError('Archive SHA-256 mismatch.')
    actual = []
    manifest = None
    total = 0
    progress = 0
    with tarfile.open(path, 'r|gz') as archive:
        for member in archive:
            if member.name == MANIFEST:
                manifest = json.load(archive.extractfile(member))
                continue
            item = {'name': member.name}
            if member.isfile():
                digest = hashlib.sha256()
                stream = archive.extractfile(member)
                for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b''):
                    digest.update(chunk)
                item.update(type='file', size=member.size, sha256=digest.hexdigest())
                total += member.size
                if total - progress >= 512 * 1024 * 1024:
                    print(f'Verified {total / 1024**3:.2f} GiB', flush=True)
                    progress = total
            elif member.isdir():
                item['type'] = 'directory'
            elif member.issym():
                item.update(type='symlink', target=member.linkname)
            else:
                raise ValueError(f'Unexpected archive entry: {member.name}')
            actual.append(item)
    if manifest is None or actual != manifest['entries']:
        raise ValueError('Archive contents differ from the embedded manifest.')
    print(f'PASS: SHA-256, gzip, and {len(actual)} entries verified.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', nargs='?', type=Path, help='New .tar.gz outside repository')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--verify', type=Path, metavar='ARCHIVE')
    args = parser.parse_args()
    try:
        if args.verify:
            if args.destination:
                parser.error('Use destination or --verify, not both.')
            verify(args.verify)
        elif args.destination:
            snapshot(args.root, args.destination)
        else:
            parser.error('Supply destination or --verify ARCHIVE.')
    except (OSError, ValueError, tarfile.TarError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'ERROR: {error}\nIncomplete .partial files are retained; choose a new destination after fixing the cause.\n')


if __name__ == '__main__':
    main()
