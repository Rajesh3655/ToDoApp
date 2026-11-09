#!/usr/bin/env python3
"""Static privacy/release configuration assertions; not a runtime test."""
import pathlib
import plistlib
import re
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parent.parent
android = '{http://schemas.android.com/apk/res/android}'
manifest = ET.parse(root / 'android/app/src/main/AndroidManifest.xml').getroot()
permissions = {p.get(android + 'name') for p in manifest.findall('uses-permission')}
assert 'android.permission.INTERNET' not in permissions
assert not {'android.permission.READ_EXTERNAL_STORAGE', 'android.permission.WRITE_EXTERNAL_STORAGE', 'android.permission.MANAGE_EXTERNAL_STORAGE'} & permissions
app = manifest.find('application')
assert app is not None and app.get(android + 'allowBackup') == 'false'
assert app.get(android + 'fullBackupContent') == 'false'
assert app.get(android + 'usesCleartextTraffic') == 'false'
for kind in ['service', 'receiver', 'activity']:
    for node in app.findall(kind):
        name = node.get(android + 'name')
        if name not in {'.MainActivity', '.BootReceiver'}:
            assert node.get(android + 'exported') == 'false', name
assert app.find("service").get(android + 'foregroundServiceType') == 'mediaPlayback'
print('PASS: Android network/storage permissions, backup exclusions and component exposure')
with (root / 'ios/Runner/Info.plist').open('rb') as file:
    info = plistlib.load(file)
assert info['CFBundleDisplayName'] == 'Supare'
assert info['UIFileSharingEnabled'] is False
assert info['LSSupportsOpeningDocumentsInPlace'] is False
assert info.get('NSFaceIDUsageDescription') and info.get('NSCameraUsageDescription')
assert not info.get('NSAppTransportSecurity', {}).get('NSAllowsArbitraryLoads', False)
print('PASS: iOS app identity, protected-document exposure and permission explanations')
for file in (root / 'lib').rglob('*.dart'):
    source = file.read_text()
    assert not re.search(r'\b(HttpClient|WebSocket|Socket)\s*\(', source), file
    assert not re.search(r"import\s+['\"]package:(http|dio|firebase|supabase)", source), file
for extension in ('*.xml', '*.storyboard', '*.xcworkspacedata'):
    for file in root.glob('android/**/' + extension):
        ET.parse(file)
    for file in root.glob('ios/**/' + extension):
        ET.parse(file)
print('PASS: application source has no network clients; platform XML parses')
print('Static configuration checks passed. Flutter compilation and device checks are separate.')
