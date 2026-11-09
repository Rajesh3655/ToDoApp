#!/usr/bin/env python3
"""Install pinned development tools locally, retaining HTTPS/checksum checks."""
import hashlib
import pathlib
import shutil
import subprocess
import tarfile
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
tools = root / 'tool'
cache = tools / 'downloads'
cache.mkdir(exist_ok=True)

def download(name, url, expected):
    target = cache / name
    if not target.exists():
        subprocess.run(['curl', '--fail', '--location', '--retry', '2', '--output', str(target), url], check=True)
    actual = hashlib.file_digest(target.open('rb'), 'sha256').hexdigest()
    if actual != expected:
        raise RuntimeError(f'Checksum mismatch for {name}; remove the damaged download and retry.')
    return target

if not (tools / 'jdk-21/bin/javac').exists() and not shutil.which('javac'):
    archive = download('temurin-jdk-21.0.9.tar.gz',
        'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.9%2B10/OpenJDK21U-jdk_x64_linux_hotspot_21.0.9_10.tar.gz',
        '810d3773df7e0d6c4394e4e244b264c8b30e0b05a0acf542d065fd78a6b65c2f')
    output = tools / 'jdk-21'
    output.mkdir(exist_ok=True)
    with tarfile.open(archive) as source:
        for entry in source.getmembers():
            bits = entry.name.split('/', 1)
            if len(bits) == 2 and bits[1]:
                entry.name = bits[1]
                source.extract(entry, output, filter='data')
    print('Installed checksum-verified Temurin development JDK 21.0.9.')

if not (tools / 'android-sdk/cmdline-tools/latest/bin/sdkmanager').exists():
    archive = download('android-commandlinetools.zip',
        'https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip',
        '2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258')
    output = tools / 'android-sdk/cmdline-tools'
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as source:
        source.extractall(output)
        for entry in source.infolist():
            file = output / entry.filename
            mode = entry.external_attr >> 16
            if file.is_file() and mode:
                file.chmod(mode & 0o777)
    (output / 'cmdline-tools').rename(output / 'latest')
    print('Installed checksum-verified Android command-line tools.')
print('Local build tool prerequisites available.')
