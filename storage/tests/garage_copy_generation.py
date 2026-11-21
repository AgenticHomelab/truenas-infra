"""Offline Garage 2.4.1 + native crypt SYNC/WAL recovery regression probe.

Synthetic data/loopback only; never reads a user rclone config. Fixtures are
copied with the sole Garage process SIGSTOPped (or stopped), NOT ZFS snapshots
and NOT evidence of atomic filesystem capture. No production orchestration.
The legacy filename is retained for the existing CI entry point. COPY is tested
only as a historical negative control, not the desired operator architecture.
SYNC removes source-absent files after success, not transactionally on failure.
Run: python3 storage/tests/garage_copy_generation.py --garage /path/to/garage-v2.4.1
"""
import argparse
import hashlib
import itertools
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import socket
import subprocess
import tempfile
import time

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--garage', required=True)
ap.add_argument('--rclone', default='rclone')
ap.add_argument('--workdir')
a = ap.parse_args()
os.umask(0o077)
root = Path(a.workdir).resolve() if a.workdir else Path(tempfile.mkdtemp(prefix='sync-wal-recovery-', dir=os.environ['TMPDIR']))
if a.workdir:
    root.mkdir(mode=0o700, exist_ok=False)
BIN = str(Path(a.garage).resolve())
env = {k: v for k, v in os.environ.items() if not k.startswith(('RCLONE_', 'GARAGE_'))}
env['RUST_LOG'] = 'error'
rc = [a.rclone, '--config', '/dev/null']
results = {'fixture_capture': 'SIGSTOP-stable file copies, not atomic ZFS',
           'transfer_mode': 'SYNC', 'filename_encryption': 'off', 'tests': {}}
p = None

def run(args, e=None, ok=True):
    q = subprocess.run([str(x) for x in args], env=e or env, capture_output=True, text=True, timeout=120)
    if ok and q.returncode:
        raise RuntimeError(f'{Path(str(args[0])).name} rc={q.returncode}; private stderr suppressed')
    return q

def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]

def digest(f):
    return hashlib.sha256(Path(f).read_bytes()).hexdigest()

def manifest(d):
    return {str(f.relative_to(d)): digest(f) for f in sorted(d.rglob('*')) if f.is_file()}

def stop():
    global p
    if p is not None and p.poll() is None:
        p.send_signal(signal.SIGCONT)
        p.send_signal(signal.SIGINT)
        try:
            p.wait(timeout=25)
        except subprocess.TimeoutExpired:
            p.kill(); p.wait()
            raise RuntimeError('Garage required force stop')
    p = None

def start(c, logfile):
    global p
    with open(logfile, 'ab') as log:
        p = subprocess.Popen([BIN, '-c', str(c), 'server'], env=env, stdout=log, stderr=log)
    for _ in range(100):
        if p.poll() is not None:
            raise RuntimeError('Garage startup failed; private log retained')
        if run([BIN, '-c', c, 'status'], ok=False).returncode == 0:
            return
        time.sleep(.1)
    raise RuntimeError('Garage readiness timeout')

def capture(src, dst):
    assert p is not None
    p.send_signal(signal.SIGSTOP)
    try:
        for _ in range(100):
            states = [f.read_text().split('State:')[1].splitlines()[0] for f in Path(f'/proc/{p.pid}/task').glob('*/status')]
            if states and all('T' in s for s in states):
                break
            time.sleep(.02)
        else:
            raise RuntimeError('Could not confirm all Garage threads stopped')
        before = manifest(src)
        shutil.copytree(src, dst)
        assert before == manifest(dst) == manifest(src), 'fixture changed during stable copy'
    finally:
        p.send_signal(signal.SIGCONT)

def obscure_synthetic(raw):
    q = subprocess.run(rc + ['obscure', '-'], input=raw + '\n', env=env,
                       capture_output=True, text=True, timeout=15)
    if q.returncode:
        raise RuntimeError('Synthetic obscure failed; stderr suppressed')
    return q.stdout.strip()

def cryptenv(directory):
    return dict(cryptbase, RCLONE_CONFIG_TESTCRYPT_REMOTE=str(directory))

def sync(source, directory):
    return run(rc + ['sync', source, 'testcrypt:'], cryptenv(directory))

def check(source, directory, cmd='check', download=False, one=False, report=None):
    args = rc + [cmd, source, 'testcrypt:']
    if download:
        args += ['--download']
    if one:
        args += ['--one-way']
    if report:
        args += ['--combined', report]
    return run(args, cryptenv(directory), ok=False).returncode

def decode(directory, dst):
    run(rc + ['copy', 'testcrypt:', dst], cryptenv(directory))

def integrity(source, label):
    dest = root / ('integrity-' + label)
    shutil.copytree(source / 'meta', dest)
    q = run(['sqlite3', dest / 'db.sqlite', 'PRAGMA integrity_check;'], ok=False)
    return {'rc': q.returncode, 'ok': q.returncode == 0 and q.stdout.strip() == 'ok'}

try:
    version = run([BIN, '--version']).stdout.strip()
    assert version.startswith('garage v2.4.1 '), version
    results['garage_version'] = version
    results['rclone_version'] = run([a.rclone, 'version']).stdout.splitlines()[0]
    src = root / 'source'; src.mkdir()
    rpc, s3 = port(), port()
    conf = root / 'source.toml'
    cfg = f'''metadata_dir = "{src}/meta"
data_dir = "{src}/data"
db_engine = "sqlite"
metadata_fsync = true
data_fsync = true
replication_factor = 1
rpc_secret = "{secrets.token_hex(32)}"
rpc_bind_addr = "127.0.0.1:{rpc}"
rpc_public_addr = "127.0.0.1:{rpc}"
[s3_api]
s3_region = "garage"
api_bind_addr = "127.0.0.1:{s3}"
'''
    conf.write_text(cfg)
    start(conf, root / 'source.log')
    def cli(*args):
        return run([BIN, '-c', conf, *args]).stdout
    node = cli('node', 'id', '--quiet').strip().split('@')[0]
    cli('layout', 'assign', '--zone', 'isolated-A', '--capacity', '1G', node)
    cli('layout', 'apply', '--version', '1')
    cli('bucket', 'create', 'synthetic')
    cli('key', 'create', 'isolated-key')
    info = cli('key', 'info', '--show-secret', 'isolated-key')
    key_match = re.search(r'Key ID:\s*(\S+)', info)
    secret_match = re.search(r'Secret key:\s*(\S+)', info)
    assert key_match is not None and secret_match is not None
    s3env = dict(env, RCLONE_CONFIG_TESTS3_TYPE='s3', RCLONE_CONFIG_TESTS3_PROVIDER='Other',
                 RCLONE_CONFIG_TESTS3_ACCESS_KEY_ID=key_match.group(1),
                 RCLONE_CONFIG_TESTS3_SECRET_ACCESS_KEY=secret_match.group(1),
                 RCLONE_CONFIG_TESTS3_ENDPOINT=f'http://127.0.0.1:{s3}', RCLONE_CONFIG_TESTS3_REGION='garage')
    cli('bucket', 'allow', '--read', '--write', 'synthetic', '--key', 'isolated-key')
    objects = root / 'objects'; objects.mkdir()
    def put(name, local):
        run(rc + ['copyto', local, 'tests3:synthetic/' + name], s3env)
    def get(name, local):
        run(rc + ['copyto', 'tests3:synthetic/' + name, local], s3env)
    old = objects / 'old.bin'; old.write_bytes(secrets.token_bytes(3 * 1024 * 1024))
    put('payload.bin', old)
    # Ensure A main DB has a meaningful base, then leave a committed A WAL.
    checkpoint = run(['sqlite3', src / 'meta/db.sqlite', 'PRAGMA wal_checkpoint(TRUNCATE);']).stdout.strip()
    assert checkpoint.startswith('0|'), checkpoint
    cli('bucket', 'create', 'a-wal-marker')
    A = root / 'A'; capture(src, A)
    assert (A / 'meta/db.sqlite-wal').stat().st_size > 32
    # B has both a different main DB and different WAL, plus a real changed layout.
    checkpoint = run(['sqlite3', src / 'meta/db.sqlite', 'PRAGMA wal_checkpoint(TRUNCATE);']).stdout.strip()
    assert checkpoint.startswith('0|'), checkpoint
    cli('layout', 'assign', '--zone', 'isolated-B', '--capacity', '2G', node)
    cli('layout', 'apply', '--version', '2')
    new = objects / 'new.bin'; new.write_bytes(secrets.token_bytes(3 * 1024 * 1024))
    extra = objects / 'extra.bin'; extra.write_bytes(secrets.token_bytes(2 * 1024 * 1024))
    put('payload.bin', new); put('extra.bin', extra)
    checkpoint = run(['sqlite3', src / 'meta/db.sqlite', 'PRAGMA wal_checkpoint(TRUNCATE);']).stdout.strip()
    assert checkpoint.startswith('0|'), checkpoint
    walonly = objects / 'wal-only.bin'; walonly.write_bytes(secrets.token_bytes(128))
    put('wal-only.bin', walonly)
    cli('bucket', 'create', 'b-wal-marker')
    B = root / 'B'; capture(src, B)
    newest = objects / 'newest.bin'; newest.write_bytes(secrets.token_bytes(2 * 1024 * 1024))
    put('c-only.bin', newest)
    cli('bucket', 'create', 'c-wal-marker')
    # C models later checkpointed source with absent WAL and GC-removed old blocks.
    stop()
    # Garage shutdown may leave a valid WAL. A native SQLite connection on the
    # stopped synthetic source checkpoints it; closing removes both sidecars.
    checkpoint = run(['sqlite3', src / 'meta/db.sqlite', 'PRAGMA wal_checkpoint(TRUNCATE);']).stdout.strip()
    assert checkpoint.startswith('0|'), checkpoint
    C = root / 'C'; shutil.copytree(src, C)
    for suffix in ('-wal', '-shm'):
        f = C / ('meta/db.sqlite' + suffix)
        assert not f.exists() or f.stat().st_size == 0, 'expected checkpointed C source'
        if f.exists():
            f.unlink()
    removed = []
    for f in (A / 'data').rglob('*.zst'):
        q = C / f.relative_to(A)
        if q.exists():
            removed.append(str(q.relative_to(C))); q.unlink()
    assert removed, 'no old source block fixture to remove'
    results['modeled_gc_source_removed_blocks'] = len(removed)
    # Distinct mtimes exercise normal native comparisons without --ignore-times.
    for index, d in enumerate((A, B, C)):
        for f in d.rglob('*'):
            if f.is_file():
                os.utime(f, (time.time() - 120 + index * 30, time.time() - 120 + index * 30))
    manifests = {name: manifest(root / name) for name in ('A', 'B', 'C')}
    for name, m in manifests.items():
        (root / (name + '-manifest.json')).write_text(json.dumps(m, indent=2))
    mutable = ['meta/db.sqlite', 'meta/db.sqlite-wal', 'meta/cluster_layout']
    assert all(manifests['A'][f] != manifests['B'][f] for f in mutable), 'required mutable file did not change'
    results['mutable_paths_changed'] = mutable
    results['fixture_integrity'] = {n: integrity(root / n, n) for n in ('A', 'B', 'C')}
    assert all(v['ok'] for v in results['fixture_integrity'].values())
    cryptbase = dict(env, RCLONE_CONFIG_TESTCRYPT_TYPE='crypt',
        RCLONE_CONFIG_TESTCRYPT_PASSWORD=obscure_synthetic(secrets.token_urlsafe(32)),
        RCLONE_CONFIG_TESTCRYPT_PASSWORD2=obscure_synthetic(secrets.token_urlsafe(32)),
        RCLONE_CONFIG_TESTCRYPT_FILENAME_ENCRYPTION='off')
    # Keep keys private for reproducibility; only results.json is sanitized.
    (root / 'private-crypt-env.json').write_text(json.dumps({k: v for k, v in cryptbase.items() if k.startswith('RCLONE_CONFIG_TESTCRYPT_')}))
    remote = root / 'encrypted'
    sync(A, remote)
    assert check(A, remote, 'cryptcheck') == 0 and check(A, remote, download=True) == 0
    encoded = {}
    for f in mutable:
        out = run(rc + ['cryptdecode', '--reverse', 'testcrypt:', f], cryptenv(remote)).stdout.strip()
        encoded[f] = out.split('\t')[-1].strip()
        assert (remote / encoded[f]).is_file(), 'cryptdecode path not found'
        assert encoded[f] == f + '.bin', 'filename_encryption=off must retain native paths'
        assert (remote / encoded[f]).read_bytes().startswith(b'RCLONE\x00\x00'), 'crypt content header missing'
        assert digest(remote / encoded[f]) != manifests['A'][f], 'plaintext was not encrypted'
    initial_cipher = {f: digest(remote / c) for f, c in encoded.items()}
    results['tests']['initial_complete_A_checks_pass'] = True
    results['tests']['visible_paths_with_encrypted_contents'] = True
    # Actual local rclone process kill: order is a controlled experimental factor,
    # not a suggested task correction or a claim about default traversal order.
    q = subprocess.Popen([*rc, 'sync', str(B), 'testcrypt:', '--transfers', '1', '--checkers', '1',
                          '--order-by', 'name,descending', '--bwlimit', '256k'],
                         env=cryptenv(remote), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 35
        while q.poll() is None and time.monotonic() < deadline:
            overwritten = [f for f, c in encoded.items() if (remote / c).exists() and digest(remote / c) != initial_cipher[f]]
            unchanged = [f for f, c in encoded.items() if (remote / c).exists() and digest(remote / c) == initial_cipher[f]]
            if overwritten and unchanged:
                q.kill(); q.wait(timeout=10)
                break
            time.sleep(.01)
        else:
            raise AssertionError('did not observe mixed mutable paths before controlled kill')
    finally:
        if q.poll() is None:
            q.kill(); q.wait(timeout=10)
    bad = root / 'interrupted-decoded'; decode(remote, bad)
    Acheck, Bcheck = check(A, remote, download=True), check(B, remote, download=True)
    bad_integrity = integrity(bad, 'interrupted')
    assert Acheck != 0 and Bcheck != 0, 'mixed image was not rejected'
    results['tests']['killed_SYNC'] = {'rclone_rc': q.returncode, 'overwritten_mutable_paths': overwritten,
        'unchanged_mutable_paths': unchanged, 'against_A_rc': Acheck, 'against_B_rc': Bcheck,
        'sqlite_integrity': bad_integrity, 'previous_A_not_preserved': True}
    # Every first-file ordering leaves a detectable mixed namespace. A successful
    # single-file operation is deliberately only a partial whole-tree fixture.
    order_results = []
    for i, order in enumerate(itertools.permutations(mutable)):
        d = root / f'order-{i}'
        sync(A, d)
        prefixes = []
        for f in order[:2]:
            run(rc + ['copyto', B / f, 'testcrypt:' + f], cryptenv(d))
            ca, cb = check(A, d, download=True), check(B, d, download=True)
            assert ca != 0 and cb != 0
            prefixes.append({'last_copied_file': f, 'against_A_rc': ca, 'against_B_rc': cb})
        order_results.append({'metadata_order': order, 'partial_prefix_checks': prefixes})
    results['tests']['partial_order_permutations'] = order_results
    # Recovery: normal full SYNC of the same frozen B, then two-way native checks.
    sync(B, remote)
    assert check(B, remote, 'cryptcheck') == 0 and check(B, remote, download=True) == 0
    encoded_again = {f: run(rc + ['cryptdecode', '--reverse', 'testcrypt:', f], cryptenv(remote)).stdout.strip().split('\t')[-1].strip() for f in mutable}
    assert encoded_again == encoded
    assert all(digest(remote / encoded[f]) != initial_cipher[f] for f in mutable)
    restoredB = root / 'restored-B'; decode(remote, restoredB)
    assert manifest(restoredB) == manifests['B']
    results['tests']['rerun_B_complete_cryptcheck_and_download_check'] = True
    results['tests']['deterministic_names_overwrite_same_cipher_paths'] = True
    # Historical negative control: COPY B then C leaves a union, unlike SYNC.
    # One-way checks tolerate its obsolete WAL/SHM and GC-removed blocks.
    historical = root / 'historical-copy-encrypted'
    run(rc + ['copy', B, 'testcrypt:'], cryptenv(historical))
    run(rc + ['copy', C, 'testcrypt:'], cryptenv(historical))
    assert check(C, historical, 'cryptcheck', one=True) == 0
    assert check(C, historical, download=True, one=True) == 0
    rawC = root / 'historical-copy-C-union'; decode(historical, rawC)
    extras = sorted(set(manifest(rawC)) - set(manifests['C']))
    assert 'meta/db.sqlite-wal' in extras and 'meta/db.sqlite-shm' in extras
    assert all(f in extras for f in removed)
    two_way = check(C, historical, download=True, report=root / 'historical-C-check-report.txt')
    assert two_way != 0
    results['tests']['historical_COPY_retains_stale_sidecars_and_source_removed_blocks'] = {
        'one_way_cryptcheck_rc': 0, 'one_way_check_download_rc': 0, 'two_way_check_rc': two_way,
        'extra_paths': extras, 'unfiltered_sqlite_integrity': integrity(rawC, 'unfiltered-C')}
    # Successful SYNC must remove all source-absent paths, not merely pass a
    # one-way check. Current B WAL remains valid until the selected C replaces it.
    sync(C, remote)
    assert check(C, remote, 'cryptcheck') == 0, 'SYNC left stale ciphertext membership'
    assert check(C, remote, download=True) == 0, 'SYNC failed two-way byte comparison'
    selectedC = root / 'restored-C'; decode(remote, selectedC)
    assert manifest(selectedC) == manifests['C'], 'SYNC restore is not exact selected-source membership'
    absent = ['meta/db.sqlite-wal', 'meta/db.sqlite-shm', *removed]
    assert all(not (selectedC / f).exists() for f in absent)
    results['tests']['SYNC_C_removes_stale_sidecars_and_source_removed_blocks'] = {
        'two_way_cryptcheck_rc': 0, 'two_way_check_download_rc': 0,
        'exact_source_membership': True, 'absent_paths': absent}
    # Independently retained native SHA-256 evidence remains usable after loss.
    hashfile = root / 'C.sha256'
    run(rc + ['hashsum', 'SHA256', C, '--output-file', hashfile])
    manifest_check = run(rc + ['check', '--checkfile', 'SHA256', hashfile, 'testcrypt:', '--download', '--one-way'], cryptenv(remote), ok=False)
    assert manifest_check.returncode == 0, 'native source-independent manifest check failed'
    results['tests']['native_manifest_check_and_unfiltered_SYNC_restore'] = True
    # Negative controls: never discard valid current WAL or install retained old
    # WAL merely because SQLite integrity passes. Historical COPY supplies old WAL.
    withoutWAL = root / 'B-without-WAL'; shutil.copytree(restoredB, withoutWAL)
    for suffix in ('-wal', '-shm'):
        f = withoutWAL / ('meta/db.sqlite' + suffix)
        if f.exists():
            f.unlink()
    # Old data_layout absolute paths must not permit false positive S3 reads.
    src.rename(root / 'unavailable-original')
    for label, tree, missing_name in [('B-without-current-WAL', withoutWAL, 'wal-only.bin'),
                                        ('C-with-retained-stale-WAL', rawC, 'c-only.bin')]:
        gate = integrity(tree, 'negative-' + label)
        assert gate['ok'], 'negative WAL control must pass SQLite integrity to test semantic loss'
        c = root / f'negative-{label}.toml'; c.write_text(cfg.replace(str(src), str(tree)))
        outcome: dict[str, object] = {'sqlite_integrity': gate}
        try:
            start(c, root / f'negative-{label}.log')
            out = root / ('negative-' + missing_name)
            q = run(rc + ['copyto', 'tests3:synthetic/' + missing_name, out], s3env, ok=False)
            outcome['S3_expected_current_object_rc'] = q.returncode
            outcome['S3_output_file_exists'] = out.is_file()
            outcome['S3_expected_current_object_missing'] = q.returncode != 0 or not out.is_file()
        finally:
            stop()
        assert outcome['S3_expected_current_object_missing'], 'negative fixture unexpectedly recovered its current-only object'
        results['tests'][label + '_rejected'] = outcome
    for label, tree, expected in [('A', A, [('payload.bin', old)]),
                                   ('B', restoredB, [('payload.bin', new), ('extra.bin', extra), ('wal-only.bin', walonly)]),
                                   ('C', selectedC, [('payload.bin', new), ('extra.bin', extra), ('wal-only.bin', walonly), ('c-only.bin', newest)])]:
        # Keep selected images pristine: SQLite/Garage can mutate working copies.
        work = root / ('working-' + label); shutil.copytree(tree, work); tree = work
        before = manifest(tree)
        gate = integrity(tree, 'restore-' + label)
        assert gate['ok'], f'integrity failed for {label}'
        c = root / f'restore-{label}.toml'; c.write_text(cfg.replace(str(src), str(tree)))
        start(c, root / f'restore-{label}.log')
        run([BIN, '-c', c, 'repair', '-a', '--yes', 'tables'])
        verified = []
        for name, expected_file in expected:
            out = root / f'{label}-got-{name}'; get(name, out)
            assert digest(out) == digest(expected_file), f'{label} S3 byte mismatch'
            verified.append(name)
        stop()
        results['tests'][f'actual_S3_restore_{label}'] = {'sqlite_integrity': gate, 'byte_identical_objects': verified,
            'wal_present_before_start': 'meta/db.sqlite-wal' in before}
    results['all_assertions_passed'] = True
finally:
    stop()
    (root / 'results.json').write_text(json.dumps(results, indent=2))
print(json.dumps({'workdir': str(root), **results}, indent=2))
