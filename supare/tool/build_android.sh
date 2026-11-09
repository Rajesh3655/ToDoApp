#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/environment.sh"
cd "$SUPARE_ROOT"
mkdir -p releases/android tool/test-signing
if [[ ! -f android/key.properties && ! -f tool/test-signing/debug.keystore ]]; then
  # Standard public Android TEST credentials, not a production signing identity.
  keytool -genkeypair -v -keystore tool/test-signing/debug.keystore -storepass android \
    -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 3650 \
    -dname 'CN=Supare Test Build,O=Development,C=IN'
fi
flutter pub get --enforce-lockfile
flutter analyze
flutter test --reporter expanded
flutter build apk --release
flutter build appbundle --release
suffix=test-key
if [[ -f android/key.properties ]]; then suffix=signed; fi
cp build/app/outputs/flutter-apk/app-release.apk "releases/android/supare-1.0.0-$suffix.apk"
cp build/app/outputs/bundle/release/app-release.aab "releases/android/supare-1.0.0-$suffix.aab"
"$ANDROID_HOME/build-tools/35.0.0/apksigner" verify --verbose "releases/android/supare-1.0.0-$suffix.apk"
(cd releases/android && sha256sum "supare-1.0.0-$suffix.apk" "supare-1.0.0-$suffix.aab" > SHA256SUMS)
