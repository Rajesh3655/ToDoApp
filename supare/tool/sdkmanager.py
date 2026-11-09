#!/usr/bin/env python3
"""Run official sdkmanager through the inherited proxy without exposing credentials."""
import os
import pathlib
import subprocess
import sys
import urllib.parse
sdk = pathlib.Path(os.environ['ANDROID_HOME'])
args = [str(sdk / 'cmdline-tools/latest/bin/sdkmanager'), '--sdk_root=' + str(sdk)]
proxy = urllib.parse.urlparse(os.environ.get('HTTPS_PROXY', ''))
if proxy.hostname:
    args += ['--proxy=http', '--proxy_host=' + proxy.hostname, '--proxy_port=' + str(proxy.port or 80)]
subprocess.run(args + sys.argv[1:], input='y\n' * 100, text=True, check=True)
