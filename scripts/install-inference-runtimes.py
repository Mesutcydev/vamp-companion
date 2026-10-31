#!/usr/bin/env python3
"""Install pinned runtimes without changing Homebrew or the app's MLX ABI.

Requires Apple Silicon. Source-built runtimes also need Xcode, git, cmake and uv.
No model is selected, no service is installed, and existing runtime entries and
settings are preserved. Bonsai weights currently need at least 24 GB RAM.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import posixpath
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DEST = Path.home() / 'Library/Application Support/VampCompanion/Runtimes'
BUILD = Path.home() / 'Library/Caches/VampRuntimeBuilds'
PINS = {
    'omlx': ('https://github.com/jundot/omlx.git', 'f0d8428acd3220c364177d1ea9593e4e15f94107', 'omlx-f0d8428'),
    'mlxfast': ('https://github.com/Layr-Labs/mlxfast-bonsai2-27b-engine.git', '831fae740de35a106e85768d8b0534b4af422b13', 'mlxfast-831fae7'),
    'llamaMetal': ('https://github.com/ggml-org/llama.cpp.git', '7fe450e19305b828c199d602c23a8337aaa1f03b', 'llama-metal-v0.5.0'),
}
LFM3_BUILD = 'b11960'
LFM3_ARCHIVE = f'llama-{LFM3_BUILD}-bin-macos-arm64.tar.gz'
LFM3_URL = f'https://github.com/ggml-org/llama.cpp/releases/download/{LFM3_BUILD}/{LFM3_ARCHIVE}'
LFM3_ARCHIVE_SHA256 = '58e5a5e1d7c2bf66cedd9c29e0323f3e570660a70a1e2156d32eed08f4cc1e3c'


def run(args, cwd=None, env=None):
    subprocess.run([str(x) for x in args], cwd=cwd, env=env, check=True)


def checkout(kind):
    remote, revision, folder = PINS[kind]
    source = BUILD / folder
    if not source.exists():
        run(['git', 'clone', '--filter=blob:none', '--no-checkout', remote, source],
            env=dict(os.environ, GIT_LFS_SKIP_SMUDGE='1'))
        run(['git', 'checkout', '--detach', revision], cwd=source,
            env=dict(os.environ, GIT_LFS_SKIP_SMUDGE='1'))
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    if actual != revision:
        raise RuntimeError(f'{source} is at another revision; move it aside before installing')
    return source, DEST / folder


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        if target.exists() or target.is_symlink(): target.unlink()
        target.symlink_to(source.readlink().name)
    elif source.is_dir():
        shutil.copytree(source, target, dirs_exist_ok=True)
    else:
        temporary = target.with_name(target.name + '.installing')
        shutil.copy2(source, temporary)
        temporary.replace(target)


def sha256_file(handle):
    digest = hashlib.sha256()
    for chunk in iter(lambda: handle.read(1024 * 1024), b''):
        digest.update(chunk)
    return digest.hexdigest()


def validate_archive_member(member):
    """Reject paths and links that could escape the expected release folder."""
    name = member.name.rstrip('/')
    root = f'llama-{LFM3_BUILD}'
    if (not name or name.startswith('/') or posixpath.normpath(name) != name
            or not (name == root or name.startswith(root + '/'))):
        raise RuntimeError(f'Unsafe runtime archive path: {member.name}')
    if member.issym():
        link = posixpath.normpath(posixpath.join(posixpath.dirname(name), member.linkname))
        if member.linkname.startswith('/') or not link.startswith(root + '/'):
            raise RuntimeError(f'Unsafe runtime archive link: {member.name}')
    elif not (member.isfile() or member.isdir()):
        raise RuntimeError(f'Unsupported runtime archive entry: {member.name}')


def verify_runtime_tree(archive, directory):
    for member in archive.getmembers():
        validate_archive_member(member)
        path = directory / member.name
        if member.isdir():
            valid = path.is_dir() and not path.is_symlink()
        elif member.issym():
            valid = path.is_symlink() and os.readlink(path) == member.linkname
        else:
            valid = path.is_file() and not path.is_symlink()
            if valid:
                with path.open('rb') as installed, archive.extractfile(member) as original:
                    valid = sha256_file(installed) == sha256_file(original)
        if not valid:
            raise RuntimeError(f'Existing runtime differs from the verified release: {path}')


def install_lfm3_compatibility():
    """Verify the official binary and register it only for LFM3 models."""
    target = DEST / f'llama-{LFM3_BUILD}'
    if target.is_symlink():
        raise RuntimeError(f'Refusing to install through a runtime symlink: {target}')
    with tempfile.TemporaryDirectory(prefix='.lfm3-install-', dir=DEST) as scratch:
        scratch = Path(scratch)
        archive_path = scratch / LFM3_ARCHIVE
        request = urllib.request.Request(LFM3_URL, headers={'User-Agent': 'VampCompanion-runtime-installer'})
        with urllib.request.urlopen(request, timeout=60) as response, archive_path.open('wb') as output:
            shutil.copyfileobj(response, output)
        with archive_path.open('rb') as handle:
            if sha256_file(handle) != LFM3_ARCHIVE_SHA256:
                raise RuntimeError('The LFM3 runtime archive checksum did not match the pinned release.')
        with tarfile.open(archive_path, 'r:gz') as archive:
            for member in archive.getmembers():
                validate_archive_member(member)
            if target.exists():
                verify_runtime_tree(archive, target)
            else:
                staging = scratch / 'runtime'
                staging.mkdir()
                if hasattr(tarfile, 'data_filter'):
                    archive.extractall(staging, filter='data')
                else:
                    archive.extractall(staging)
                verify_runtime_tree(archive, staging)
                staging.rename(target)
    executable = target / f'llama-{LFM3_BUILD}/llama-server'
    if not os.access(executable, os.X_OK):
        raise RuntimeError(f'The verified runtime is not executable: {executable}')
    return dict(kind='llamaCompatibility', revision=LFM3_BUILD,
                executable=str(executable.relative_to(DEST)), models=[], visionModels=[],
                architectures=['lfm3'])


def install(kind, with_weights):
    if kind == 'llamaCompatibility':
        return install_lfm3_compatibility()
    source, target = checkout(kind)
    target.mkdir(parents=True, exist_ok=True)
    if kind == 'omlx':
        if not (target / 'venv/bin/python').exists():
            run(['uv', 'venv', '--python', '3.13', target / 'venv'])
        run(['uv', 'pip', 'install', '--python', target / 'venv/bin/python', source,
             'torch==2.14.0', 'torchvision==0.29.0'])
        executable = target / 'venv/bin/omlx'
        models, vision = ['qwen3-0.6b-omlx', 'smolvlm2-500m-mlx'], ['smolvlm2-500m-mlx']
    elif kind == 'mlxfast':
        if with_weights and int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'])) < 24 * 1024**3:
            raise RuntimeError('Bonsai MLXFast currently requires 24 GB RAM. Install its runtime without --bonsai-weights on smaller Macs.')
        patch = ROOT / 'scripts/runtime-patches/mlxfast-vamp.patch'
        applied = subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=source,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        if not applied: run(['git', 'apply', patch], cwd=source)
        copy(ROOT / 'scripts/runtime-sources/VampBonsaiServerEngine.swift',
             source / 'Vendor/mlx-swift-lm/Libraries/MLXLMServer/Runtime/VampBonsaiServerEngine.swift')
        env = dict(os.environ, MLXFAST_SKIP_MACMON_INSTALL='1', MLXFAST_SKIP_DFLASH_DRAFTER='1',
                   MLXFAST_SKIP_MTP_HEAD='1')
        if not with_weights: env['MLXFAST_SKIP_WEIGHTS_DOWNLOAD'] = '1'
        run(['bash', 'setup.sh'], cwd=source, env=env)
        run(['swift', 'build', '-c', 'release', '--scratch-path', '.build-worker', '--product', 'mlx-server', '-j', '4'], cwd=source)
        products = source / '.build-worker/release'
        for name in ['mlx-server', 'mlx.metallib']:
            copy(products / name, target / name)
        for bundle in products.glob('*.bundle'): copy(bundle, target / bundle.name)
        executable = target / 'mlx-server'
        models, vision = ['Ternary-Bonsai-2-27B-MLXFast'], []
    else:
        build = source / 'build-vamp'
        run(['cmake', '-S', source, '-B', build, '-DCMAKE_BUILD_TYPE=Release', '-DGGML_METAL=ON',
             '-DGGML_METAL_EMBED_LIBRARY=ON', '-DLLAMA_BUILD_TESTS=OFF'])
        run(['cmake', '--build', build, '-j', '4', '--target', 'llama-server', 'llama-bench'])
        for file in (build / 'bin').iterdir():
            if file.name in ('llama-server', 'llama-bench') or file.name.endswith('.dylib'):
                copy(file, target / 'bin' / file.name)
        executable = target / 'bin/llama-server'
        models, vision = ['Huihui-Qwen3.8-27B-abliterated-Q2_K'], ['Huihui-Qwen3.8-27B-abliterated-Q2_K']
    copy(source / 'LICENSE', target / 'LICENSE')
    revision = PINS[kind][1] + ('+vamp1' if kind == 'mlxfast' else '')
    return dict(kind=kind, revision=revision, executable=str(executable.relative_to(DEST)),
                models=models, visionModels=vision)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    kinds = [*PINS, 'llamaCompatibility']
    parser.add_argument('--runtime', choices=[*kinds, 'all'], default='all')
    parser.add_argument('--bonsai-weights', action='store_true', help='Also download the pinned Bonsai pack; requires 24 GB RAM and 22 GiB free disk')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        parser.error('These runtimes require an Apple Silicon Mac.')
    DEST.mkdir(parents=True, exist_ok=True); BUILD.mkdir(parents=True, exist_ok=True)
    path = DEST / 'manifest.json'
    manifest = json.loads(path.read_text()) if path.exists() else {'version': 1, 'runtimes': []}
    if manifest.get('version') != 1: raise RuntimeError('Unknown existing runtime manifest version')
    for kind in kinds if args.runtime == 'all' else [args.runtime]:
        entry = install(kind, args.bonsai_weights)
        if kind == 'llamaCompatibility':
            # Other compatibility rules may target entirely different models.
            manifest['runtimes'] = [entry] + [r for r in manifest['runtimes']
                if not (r['kind'] == kind and r['executable'] == entry['executable'])]
        else:
            manifest['runtimes'] = [r for r in manifest['runtimes'] if r['kind'] != kind] + [entry]
        temporary = path.with_suffix('.json.pending')
        temporary.write_text(json.dumps(manifest, indent=2) + '\n'); temporary.replace(path)
    print('Installed. Model compatibility runtimes are selected automatically; experimental runtimes can be enabled in Settings → Agent.')


if __name__ == '__main__':
    main()
