"""
Download and extract MongoDB components.

Use '--help' for more information.
"""
import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import sqlite3
import tarfile
import tempfile
import urllib.error
import urllib.request
import zipfile
from collections import namedtuple
from contextlib import contextmanager
from fnmatch import fnmatch
from pathlib import Path, PurePath, PurePosixPath
import textwrap

DISTRO_ID_MAP = {
    'elementary': 'ubuntu',
    'fedora': 'rhel',
    'centos': 'rhel',
    'mint': 'ubuntu',
    'opensuse-leap': 'sles',
    'opensuse': 'sles',
    'redhat': 'rhel',
}

DISTRO_VERSION_MAP = {
    'elementary': {
        '6': '20.04'
    },
}

DISTRO_ID_TO_TARGET = {
    'ubuntu': {
        '20.*': 'ubuntu2004',
    },
    'debian': {
        '9': 'debian92',
        '10': 'debian10',
        '11': 'debian11',
    },
    'rhel': {
        '6': 'rhel62',
        '7': 'rhel73',
        '8': 'rhel81',
    },
    'sles': {
        '10.*': 'suse10',
        '11.*': 'suse11',
        '12.*': 'suse12',
        '13.*': 'suse13',
        '15.*': 'suse15',
    },
    'amzn': {
        '2018': 'amzn64',
        '2': 'amzn64',
    },
}


def infer_target():
    if os.name == 'nt':
        return 'windows'
    if os.name == 'darwin':
        return 'macos'
    # Now the tricky bit
    if Path('/etc/os-release').is_file():
        return _infer_target_os_rel()
    raise RuntimeError("Don't know yet how to find the default download "
                       "'--target' for this system. Please contribute!")


def _infer_target_os_rel():
    content = Path('/etc/os-release').read_text()
    id_re = re.compile(r'\bID=("?)(.*)\1')
    mat = id_re.search(content)
    assert mat, 'Unable to detect ID from [/etc/os-release] content:\n{}'.format(
        content)
    os_id = mat.group(2)
    ver_id_re = re.compile(r'VERSION_ID=("?)(.*?)\1')
    mat = ver_id_re.search(content)
    assert mat, 'Unable to detect VERSION_ID from [/etc/os-release] content:\n{}'.format(
        content)
    ver_id = mat.group(2)
    mapped_id = DISTRO_ID_MAP.get(os_id)
    if mapped_id:
        print('Mapping distro "{}" to "{}"'.format(os_id, mapped_id))
        ver_mapper = DISTRO_VERSION_MAP.get(os_id)
        if ver_mapper:
            mapped_version = ver_mapper[ver_id]
            print('Mapping version "{}" to "{}"'.format(
                ver_id, mapped_version))
            ver_id = mapped_version
        os_id = mapped_id
    os_id = os_id.lower()
    if os_id not in DISTRO_ID_TO_TARGET:
        raise RuntimeError("We don't know how to map '{}' to a distribution "
                           "download target. Please contribute!".format(os_id))
    ver_table = DISTRO_ID_TO_TARGET[os_id]
    for pattern, target in ver_table.items():
        if fnmatch(ver_id, pattern):
            return target
    raise RuntimeError(
        "We don't know how to map '{}' version '{}' to a distribution "
        "download target. Please contribute!".format(os_id, ver_id))


def caches_root():
    if os.name == 'nt':
        return Path(os.environ['LocalAppData'])
    if os.name == 'darwin':
        return Path('~/Library/Caches')
    xdg_cache = os.getenv('XDG_CACHE_HOME')
    if xdg_cache:
        return Path(xdg_cache)
    return Path('~/.cache').expanduser()


def cache_dir():
    return caches_root().joinpath('mongodl').absolute()


@contextmanager
def tmp_dir():
    tdir = tempfile.mkdtemp()
    try:
        yield Path(tdir)
    finally:
        shutil.rmtree(tdir)


def _update_dl_db(db, full_Json):
    with db:
        cur = db.cursor()
        cur.execute('begin')
        _import_json_data(cur, full_json, got_etag, got_modtime)


def _import_json_data(db, json_file):
    db.execute('DELETE FROM meta')
    db.execute('DROP TABLE IF EXISTS components')
    db.execute('DROP TABLE IF EXISTS downloads')
    db.execute('DROP TABLE IF EXISTS versions')
    db.execute(r'''
        CREATE TABLE versions (
            version_id INTEGER PRIMARY KEY,
            date TEXT NOT NULL,
            version TEXT NOT NULL,
            githash TEXT NOT NULL
        )
    ''')
    db.execute(r'''
        CREATE TABLE downloads (
            download_id INTEGER PRIMARY KEY,
            version_id INTEGER NOT NULL REFERENCES versions,
            target TEXT NOT NULL,
            arch TEXT NOT NULL,
            edition TEXT NOT NULL,
            ar_url TEST NOT NULL,
            data TEXT NOT NULL
        )
    ''')
    db.execute(r'''
        CREATE TABLE components (
            component_id INTEGER PRIMARY KEY,
            key TEXT NOT NULL,
            download_id INTEGER NOT NULL REFERENCES downloads,
            data TEXT NOT NULL,
            UNIQUE(key, download_id)
        )
    ''')
    with json_file.open('r') as f:
        data = json.load(f)
    for ver in data['versions']:
        version = ver['version']
        githash = ver['githash']
        date = ver['date']
        db.execute(
            r'''
            INSERT INTO versions (date, version, githash)
            VALUES (?, ?, ?)
            ''',
            (date, version, githash),
        )
        version_id = db.lastrowid
        for dl in ver['downloads']:
            arch = dl.get('arch', 'null')
            target = dl.get('target', 'null')
            edition = dl['edition']
            ar_url = dl['archive']['url']
            db.execute(
                r'''
                INSERT INTO downloads (version_id, target, arch, edition, ar_url, data)
                VALUES (?, ?, ?, ?, ?, ?)
                ''',
                (version_id, target, arch, edition, ar_url, json.dumps(dl)),
            )
            dl_id = db.lastrowid
            for key, data in dl.items():
                if 'url' not in data:
                    continue
                db.execute(
                    r'''
                    INSERT INTO components (key, download_id, data)
                    VALUES (?, ?, ?)
                    ''',
                    (key, dl_id, json.dumps(data)),
                )


def get_dl_db():
    caches = cache_dir()
    caches.mkdir(exist_ok=True, parents=True)
    db = sqlite3.connect(str(caches / 'downloads.db'), isolation_level=None)
    db.executescript(r'''
        CREATE TABLE IF NOT EXISTS meta (
            etag TEXT,
            last_modified TEXT
        )
    ''')
    db.executescript(r'''
        CREATE TABLE IF NOT EXISTS past_downloads (
            url TEXT NOT NULL UNIQUE,
            etag TEXT,
            last_modified TEXT
        )
    ''')
    changed, full_json = _download_file(
        db, 'https://downloads.mongodb.org/full.json')
    if not changed:
        return db
    with db:
        print('Refreshing downloads manifest ...')
        cur = db.cursor()
        cur.execute("begin")
        _import_json_data(cur, full_json)
    return db


def _print_list(db, version, target, arch, edition, component):
    if version or target or arch or edition or component:
        matching = db.execute(
            r'''
            SELECT version, target, arch, edition, key, components.data
              FROM components,
                   downloads USING(download_id),
                   versions USING(version_id)
            WHERE (:component IS NULL OR key=:component)
              AND (:target IS NULL OR target=:target)
              AND (:arch IS NULL OR arch=:arch)
              AND (:edition IS NULL OR edition=:edition)
              AND (:version IS NULL OR version=:version)
            ''',
            dict(version=version,
                 target=target,
                 arch=arch,
                 edition=edition,
                 component=component),
        )
        found_any = False
        for version, target, arch, edition, comp_key, comp_data in matching:
            found_any = True
            print('Download: {}\n'
                  ' Version: {}\n'
                  '  Target: {}\n'
                  '    Arch: {}\n'
                  ' Edition: {}\n'
                  '    Info: {}\n'.format(comp_key, version, target, arch,
                                          edition, comp_data))
    arches, targets, editions, versions, components = next(
        iter(
            db.execute(r'''
        VALUES(
            (select group_concat(arch, ', ') from (select distinct arch from downloads)),
            (select group_concat(target, ', ') from (select distinct target from downloads)),
            (select group_concat(edition, ', ') from (select distinct edition from downloads)),
            (select group_concat(version, ', ') from (select distinct version from versions)),
            (select group_concat(key, ', ') from (select distinct key from components))
        )
        ''')))
    versions = '\n'.join(textwrap.wrap(versions, width=78, initial_indent='  ', subsequent_indent='  '))
    targets = '\n'.join(textwrap.wrap(targets, width=78, initial_indent='  ', subsequent_indent='  '))
    print('Architectures:\n'
          '  {}\n'
          'Targets:\n'
          '{}\n'
          'Editions:\n'
          '  {}\n'
          'Versions:\n'
          '{}\n'
          'Components:\n'
          '  {}\n'.format(arches, targets, editions, versions, components))


def infer_arch():
    a = platform.machine() or platform.processor()
    # Remap platform names to the names used for downloads
    return {
        'AMD64': 'x86_64',
    }.get(a, a)


DLRes = namedtuple('DLRes', ['is_changed', 'path'])


def _download_file(db, url):
    caches = cache_dir()
    info = list(
        db.execute(
            'SELECT etag, last_modified FROM past_downloads WHERE url=?',
            [url]))
    etag = None
    modtime = None
    if info:
        etag, modtime = info[0]
    headers = {}
    if etag:
        headers['If-None-Match'] = etag
    if modtime:
        headers['If-Modified-Since'] = modtime
    req = urllib.request.Request(url, headers=headers)
    digest = hashlib.md5(url.encode("utf-8")).hexdigest()[:4]
    dest = caches / 'files' / digest / PurePosixPath(url).name
    try:
        resp = urllib.request.urlopen(req)
    except urllib.error.HTTPError as e:
        if e.code != 304:
            raise
        return DLRes(False, dest)
    else:
        print('Downloading [{}] ...'.format(url))
        dest.parent.mkdir(exist_ok=True, parents=True)
        got_etag = resp.getheader("ETag")
        got_modtime = resp.getheader('Last-Modified')
        with dest.open('wb') as of:
            buf = resp.read(1024 * 1024 * 4)
            while buf:
                of.write(buf)
                buf = resp.read(1024 * 1024 * 4)
        db.execute(
            'INSERT OR REPLACE INTO past_downloads (url, etag, last_modified) VALUES (?, ?, ?)',
            (url, got_etag, got_modtime))
    return DLRes(True, dest)


def _dl_component(db, out_dir, version, target, arch, edition, component,
                  pattern, strip_components):
    print('Download {} v{}-{} for {}-{}'.format(component, version, edition,
                                                target, arch))
    matching = db.execute(
        r'''
        SELECT components.data
        FROM
            components,
            downloads USING(download_id),
            versions USING(version_id)
        WHERE
            target=:target
            AND arch=:arch
            AND edition=:edition
            AND version=:version
            AND key=:component
        ''',
        dict(version=version,
             target=target,
             arch=arch,
             edition=edition,
             component=component),
    )
    found = list(matching)
    if not found:
        raise ValueError(
            'No download for "{}" was found for '
            'the requested version+target+architecture+edition'.format(
                component))
    data = json.loads(found[0][0])
    cached = _download_file(db, data['url']).path
    _expand_archive(cached, out_dir, pattern, strip_components)


def pathjoin(items):
    'Return a path formed by joining the given path components'
    return PurePath('/'.join(items))


def _test_pattern(path, pattern):
    """
    Test whether the given 'path' string matches the globbing pattern 'pattern'.

    Supports the '**' pattern to match any number of intermediate directories.
    """
    if pattern is None:
        return True
    # Convert to path objects
    path = PurePath(path)
    pattern = PurePath(pattern)
    # Split pattern into parts
    pattern_parts = pattern.parts
    if not pattern_parts:
        # An empty pattern always matches
        return True
    path_parts = path.parts
    if not path_parts:
        # Non-empty pattern requires more path components
        return False
    pattern_head = pattern_parts[0]
    pattern_tail = pathjoin(pattern_parts[1:])
    if pattern_head == '**':
        # Special "**" pattern matches and suffix of the path
        # Generate each suffix:
        tails = (path_parts[i:] for i in range(len(path_parts)))
        # Test if any of the suffixes match the remainder of the pattern:
        return any(_test_pattern(pathjoin(t), pattern_tail) for t in tails)
    if not fnmatch(path.parts[0], pattern_head):
        # Leading path component cannot match
        return False
    # The first component matches. Test the remainder:
    return _test_pattern(pathjoin(path_parts[1:]), pattern_tail)


def _expand_archive(ar, dest, pattern, strip_components):
    '''
    Expand the archive members from 'ar' into 'dest'. If 'pattern' is not-None,
    only extracts members that match the pattern.
    '''
    print('Extract from: [{}]'.format(ar.name))
    print('        into: [{}]'.format(dest))
    if ar.suffix == '.zip':
        n_extracted = _expand_zip(ar, dest, pattern, strip_components)
    elif ar.suffix == '.tgz':
        n_extracted = _expand_tgz(ar, dest, pattern, strip_components)
    else:
        raise RuntimeError('Unknown archive file extension: ' + ar.suffix)
    if n_extracted == 0:
        if pattern and strip_components:
            print('NOTE: No files were extracted. Likely all files were '
                  'excluded by "--only={}" and/or "--strip-components={}"'.
                  format(pattern, strip_components))
        elif pattern:
            print('NOTE: No files were extracted. Likely all files were '
                  'excluded by the "--only={}" filter'.format(pattern))
        elif strip_components:
            print('NOTE: No files were extracted. Likely all files were '
                  'excluded by "--strip-components={}"'.format(
                      strip_components))
        else:
            print('NOTE: No files were extracted. Empty archive?')
    elif n_extracted == 1:
        print('One file extracted')
    else:
        print('{} files extracted'.format(n_extracted))


def _expand_tgz(ar, dest, pattern, strip_components):
    'Expand a tar.gz archive'
    n_extracted = 0
    with tarfile.open(str(ar), 'r:*') as tf:
        for mem in tf.getmembers():
            n_extracted += _maybe_extract_member(
                dest,
                mem.name,
                pattern,
                strip_components,
                mem.isdir(),
                lambda: tf.extractfile(mem),
                mem.mode,
            )
    return n_extracted


def _expand_zip(ar, dest, pattern, strip_components):
    'Expand a .zip archive.'
    n_extracted = 0
    with zipfile.ZipFile(ar, 'r') as zf:
        for item in zf.infolist():
            n_extracted += _maybe_extract_member(
                dest,
                item.filename,
                pattern,
                strip_components,
                item.is_dir(),
                lambda: zf.open(item, 'r'),
                0o655,
            )
    return n_extracted


def _maybe_extract_member(out, relpath, pattern, strip, is_dir, opener,
                          modebits):
    relpath = PurePath(relpath)
    print('  │ {:┄<65} │'.format(str(relpath)+' '), end='')
    if len(relpath.parts) <= strip:
        # Not enough path components
        print(' (Excluded by --strip-components)')
        return 0
    if not _test_pattern(relpath, pattern):
        # Doesn't match our pattern
        print(' (excluded by pattern)')
        return 0
    stripped = pathjoin(relpath.parts[strip:])
    dest = Path(out) / stripped
    print('\n    -> [{}]'.format(dest))
    if is_dir:
        dest.mkdir(exist_ok=True, parents=True)
        return 1
    with opener() as infile:
        dest.parent.mkdir(exist_ok=True, parents=True)
        with dest.open('wb') as outfile:
            shutil.copyfileobj(infile, outfile)
        os.chmod(str(dest), modebits)
    return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    grp = parser.add_argument_group('List arguments')
    grp.add_argument('--list',
                     action='store_true',
                     help='List available components, targets, editions, and '
                     'architectures. Donwload arguments will act as filters.')
    dl_grp = parser.add_argument_group(
        'Download arguments',
        description='Select what to download and extract. '
        'Non-required arguments will be inferred '
        'based on the host system.')
    dl_grp.add_argument('--target',
                        '-T',
                        help='The target platform for which to download. '
                        'Use "--list" to list available targets.')
    dl_grp.add_argument('--arch',
                        '-A',
                        help='The architecture for which to download')
    dl_grp.add_argument(
        '--edition',
        '-E',
        help='The edition of the product to download (Default is "targeted"). '
        'Use "--list" to list available editions.')
    dl_grp.add_argument(
        '--out',
        '-o',
        help='The directory in which to download components. (Required)',
        type=Path)
    dl_grp.add_argument('--version',
                        '-V',
                        help='The product version to download (Required). '
                        'Use "--list" to list available versions.')
    dl_grp.add_argument('--component',
                        '-C',
                        help='The component to download (Required). '
                        'Use "--list" to list available components.')
    dl_grp.add_argument(
        '--only',
        help=
        'Restrict extraction to items that match the given globbing expression. '
        'The full archive member path is matched, so a pattern like "*.exe" '
        'will only match "*.exe" at the top level of the archive. To match '
        'recursively, use the "**" pattern to match any number of '
        'intermediate directories.')
    dl_grp.add_argument(
        '--strip-path-components',
        '-p',
        dest='strip_components',
        metavar='N',
        default=0,
        type=int,
        help=
        'Stip the given number of path components from archive members before '
        'extracting into the destination. The relative path of the archive '
        'member will be used to form the destination path. For example, a '
        'member named [bin/mongod.exe] will be extracted to [<out>/bin/mongod.exe]. '
        'Using --stip-components=1 will remove the first path component, extracting '
        'such an item to [<out>/mongod.exe]. If the path has fewer than N components, '
        'that archive member will be discarded.')
    args = parser.parse_args()
    db = get_dl_db()

    if args.list:
        _print_list(db, args.version, args.target, args.arch, args.edition,
                    args.component)
        return

    if args.version is None:
        raise argparse.ArgumentError(None, 'A "--version" is required')
    if args.component is None:
        raise argparse.ArgumentError(
            None, 'A "--component" name should be provided')
    if args.out is None:
        raise argparse.ArgumentError(None,
                                     'A "--out" directory should be provided')

    target = args.target or infer_target()
    arch = args.arch or infer_arch()
    edition = args.edition or 'targeted'
    out = args.out or Path.cwd()
    out = out.absolute()
    _dl_component(db, out, args.version, target, arch, edition, args.component,
                  args.only, args.strip_components)
    pass


if __name__ == '__main__':
    main()
