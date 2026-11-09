#!/usr/bin/env python3
"""Package only portable Supare source; never SDKs, app data or signing material."""
import argparse
import pathlib
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true', help='Check the source selection without writing an archive')
args = parser.parse_args()
selected = set()

for name in ['.gitignore', 'README.md', 'analysis_options.yaml', 'pubspec.yaml', 'pubspec.lock']:
    selected.add(root / name)
for name in ['lib', 'assets', 'test', 'integration_test', 'test_driver', 'docs', 'android/app/src',
             'ios/Runner', 'ios/RunnerTests', 'ios/Runner.xcodeproj', 'ios/Runner.xcworkspace']:
    directory = root / name
    if directory.exists():
        selected.update(file for file in directory.rglob('*') if file.is_file())
for name in ['android/.gitignore', 'android/build.gradle.kts', 'android/settings.gradle.kts',
             'android/gradle.properties', 'android/gradlew', 'android/gradlew.bat',
             'android/gradle/wrapper/gradle-wrapper.jar', 'android/gradle/wrapper/gradle-wrapper.properties',
             'android/app/build.gradle.kts', 'android/app/proguard-rules.pro', 'ios/.gitignore',
             'ios/Podfile', 'ios/Podfile.lock', 'ios/Flutter/AppFrameworkInfo.plist',
             'ios/Flutter/Debug.xcconfig', 'ios/Flutter/Release.xcconfig', 'releases/ios/README.md',
             'releases/android/README.md']:
    if (root / name).exists():
        selected.add(root / name)
for extension in ('*.sh', '*.py'):
    selected.update((root / 'tool').glob(extension))

files = []
for file in sorted(selected):
    relative = file.relative_to(root)
    if any(part in {'.git', '.gradle', '.dart_tool', 'build', 'Pods', 'xcuserdata', '__pycache__', '.symlinks'} for part in relative.parts):
        continue
    if file.name.startswith('GeneratedPluginRegistrant') or file.name == '.DS_Store':
        continue
    if file.suffix.lower() in {'.jks', '.keystore', '.p12', '.p8', '.mobileprovision'} or file.name in {'local.properties', 'key.properties'}:
        raise RuntimeError(f'Signing/local configuration cannot enter the source archive: {relative}')
    if file.is_symlink() or not file.resolve().is_relative_to(root):
        raise RuntimeError(f'Archive input must be a regular project file: {relative}')
    if (b'-----BEGIN ' + b'PRIVATE KEY-----') in file.read_bytes() or (b'-----BEGIN ' + b'RSA PRIVATE KEY-----') in file.read_bytes():
        raise RuntimeError(f'Private key material detected: {relative}')
    files.append(file)

print(f'Portable source selection: {len(files)} files, {sum(file.stat().st_size for file in files):,} bytes; SDKs, build caches, app data and signing keys excluded.')
if not args.check:
    output = root / 'releases/supare-source-1.0.0.zip'
    temporary = output.with_suffix('.zip.part')
    with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('supare/releases/android/', b'')
        for file in files:
            archive.write(file, pathlib.PurePosixPath('supare') / file.relative_to(root))
    temporary.replace(output)
    print(f'Created {output.relative_to(root)} ({output.stat().st_size:,} bytes).')
