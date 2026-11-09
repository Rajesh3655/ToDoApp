#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/environment.sh"
unset ANDROID_SDK_HOME
export ANDROID_AVD_HOME="$SUPARE_ROOT/tool/android-user/avd"
export ANDROID_EMULATOR_HOME="$SUPARE_ROOT/tool/android-user"
export TMPDIR="$SUPARE_ROOT/tool/tmp"
mkdir -p "$ANDROID_AVD_HOME" "$ANDROID_EMULATOR_HOME" "$TMPDIR"
if [[ ! -f "$ANDROID_HOME/system-images/android-30/default/x86_64/package.xml" ]]; then
  printf '%s\n' 'Install official emulator and system-images;android-30;default;x86_64 with sdkmanager first.' >&2
  exit 1
fi
if [[ ! -f "$ANDROID_AVD_HOME/Supare_API30.ini" ]]; then
  printf 'no\n' | JAVA_OPTS="${JAVA_OPTS:-} -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts" \
    "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd \
    --name Supare_API30 --package 'system-images;android-30;default;x86_64' --device medium_phone \
    --path "$SUPARE_ROOT/tool/avd/Supare_API30.avd"
fi
python3 - "$SUPARE_ROOT/tool/avd/Supare_API30.avd/config.ini" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
settings = {}
for line in path.read_text().splitlines():
    if '=' in line:
        key, value = line.split('=', 1)
        settings[key] = value
settings.update({'hw.ramSize':'2048', 'hw.cpu.ncore':'2', 'hw.lcd.width':'480',
    'hw.lcd.height':'800', 'hw.lcd.density':'160', 'hw.keyboard':'yes',
    'showDeviceFrame':'no', 'hw.camera.back':'none', 'hw.camera.front':'none',
    'hw.audioInput':'no', 'hw.audioOutput':'no', 'fastboot.forceColdBoot':'yes'})
path.write_text(''.join(f'{key}={value}\n' for key, value in settings.items()))
PY
# TCG is intentional: this managed machine does not expose KVM.
exec "$ANDROID_HOME/emulator/emulator" -avd Supare_API30 -port 5554 \
  -accel off -gpu swiftshader -feature -Vulkan -cores 2 -memory 2048 \
  -no-window -no-audio -no-metrics -no-boot-anim -no-snapshot -skin 480x800 \
  -camera-back none -camera-front none -timezone Asia/Kolkata
