#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/environment.sh"
python3 "$SUPARE_ROOT/tool/bootstrap_tools.py"
source "$SUPARE_ROOT/tool/environment.sh"
cd "$SUPARE_ROOT"
mkdir -p "$ANDROID_USER_HOME" "$GRADLE_USER_HOME" "$PUB_CACHE" tool/native-libs tool/dart-cli-state
if [[ ! -e "$HOME/.dart-tool" && ! -L "$HOME/.dart-tool" ]]; then
  ln -s "$SUPARE_ROOT/tool/dart-cli-state" "$HOME/.dart-tool"
fi
# adb uses its OS home config path. Keep the actual files within this project.
if [[ ! -e "$HOME/.android" && ! -L "$HOME/.android" ]]; then
  ln -s "$ANDROID_USER_HOME" "$HOME/.android"
fi
if [[ -f /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 ]]; then
  ln -sf /usr/lib/x86_64-linux-gnu/libsqlite3.so.0 tool/native-libs/libsqlite3.so
fi
if ! command -v javac >/dev/null; then
  printf '%s\n' 'A complete JDK 21 is required (the cloud image may contain only a JRE).' >&2
  exit 1
fi
if [[ ! -x tool/flutter/bin/flutter ]]; then
  git clone --depth 1 --branch 3.35.7 https://github.com/flutter/flutter.git tool/flutter
fi
# Official Flutter engine artifacts require storage.googleapis.com. TLS remains enabled.
flutter --disable-analytics
flutter --version
dart --disable-analytics
flutter precache --android
if [[ "$(uname -s)" == Darwin ]]; then flutter precache --ios; fi
flutter config --android-sdk "$ANDROID_HOME"
# Android command-line tools must be installed under tool/android-sdk/cmdline-tools/latest.
# Google download: commandlinetools-linux-11076708_latest.zip
# SHA256: 2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258
# Verify the published checksum before extracting a downloaded SDK archive.
if [[ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]]; then
  printf '%s\n' 'Install checksum-verified Android command-line tools in tool/android-sdk/cmdline-tools/latest, then rerun.' >&2
  exit 1
fi
python3 - <<'PY'
import os, subprocess, urllib.parse
sdk = os.environ['ANDROID_HOME']
args = [sdk + '/cmdline-tools/latest/bin/sdkmanager', '--sdk_root=' + sdk]
proxy = urllib.parse.urlparse(os.environ.get('HTTPS_PROXY', ''))
if proxy.hostname:
    args += ['--proxy=http', '--proxy_host=' + proxy.hostname, '--proxy_port=' + str(proxy.port or 80)]
# SDK manager verifies its repository checksums. User/app-build authorization includes SDK licenses.
subprocess.run(args + ['platform-tools', 'platforms;android-34', 'platforms;android-35', 'platforms;android-36', 'build-tools;35.0.0', 'ndk;27.0.12077973', 'cmake;3.22.1'],
               input='y\n' * 100, text=True, check=True)
PY
flutter pub get --enforce-lockfile
flutter doctor -v
