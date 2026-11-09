#!/usr/bin/env python3
"""Local emulator smoke-test helper. Uses ordinary accessibility UI gestures only."""
import argparse
import pathlib
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADB = ROOT / 'tool/android-sdk/platform-tools/adb'
DEVICE = 'emulator-5554'

def adb(*args):
    return subprocess.run([str(ADB), '-s', DEVICE, *args], check=True, capture_output=True, text=True, timeout=45)

def nodes():
    adb('shell', 'uiautomator', 'dump', '/sdcard/supare-smoke.xml')
    local = ROOT / 'tool/supare-smoke.xml'
    adb('pull', '/sdcard/supare-smoke.xml', str(local))
    return list(ET.parse(local).getroot().iter('node'))

def center(bounds):
    values = list(map(int, re.findall(r'\d+', bounds)))
    return str((values[0]+values[2])//2), str((values[1]+values[3])//2)

parser=argparse.ArgumentParser()
parser.add_argument('action', choices=['list', 'tap', 'tap_contains', 'editables'])
parser.add_argument('label', nargs='?')
args=parser.parse_args()
items=nodes()
if args.action in ['list','editables']:
    for node in items:
        text=node.get('text') or node.get('content-desc')
        if args.action=='editables' and 'EditText' not in node.get('class',''):continue
        if text or args.action=='editables':print(repr(text), node.get('class'),node.get('bounds'))
else:
    for node in items:
        text=node.get('text') or node.get('content-desc') or ''
        match=text==args.label if args.action=='tap' else args.label in text
        if match:
            x,y=center(node.get('bounds',''))
            adb('shell','input','tap',x,y)
            print('Tapped',repr(text),'at',x,y)
            break
    else:raise SystemExit('No matching visible label: '+repr(args.label))
