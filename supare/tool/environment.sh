#!/usr/bin/env bash
# Source this from any working directory. Every mutable tool/cache stays in supare.
SUPARE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export SUPARE_ROOT
if [[ -x "$SUPARE_ROOT/tool/jdk-21/bin/javac" ]]; then
  export JAVA_HOME="$SUPARE_ROOT/tool/jdk-21"
  export PATH="$JAVA_HOME/bin:$PATH"
fi
# Current SDK tools reject conflicting deprecated home overrides.
unset ANDROID_SDK_HOME
export ANDROID_HOME="$SUPARE_ROOT/tool/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="$SUPARE_ROOT/tool/android-user"
export GRADLE_USER_HOME="$SUPARE_ROOT/tool/gradle-cache"
export ANALYZER_STATE_LOCATION_OVERRIDE="$SUPARE_ROOT/tool/analyzer-state"
export XDG_CONFIG_HOME="$SUPARE_ROOT/tool/config"
export XDG_CACHE_HOME="$SUPARE_ROOT/tool/cache"
export PUB_CACHE="$SUPARE_ROOT/tool/pub-cache"
export PATH="$SUPARE_ROOT/tool/flutter/bin:$ANDROID_HOME/platform-tools:$PATH"

# Gradle does not automatically use HTTP(S)_PROXY. Preserve the configured route.
if [[ -n "${HTTPS_PROXY:-}" ]]; then
  SUPARE_PROXY_JAVA="$(python3 - <<'PYPROXY'
import os, urllib.parse
proxy = urllib.parse.urlparse(os.environ['HTTPS_PROXY'])
if proxy.hostname:
    print('-Dhttps.proxyHost=' + proxy.hostname + ' -Dhttps.proxyPort=' + str(proxy.port or 80) +
          ' -Dhttp.proxyHost=' + proxy.hostname + ' -Dhttp.proxyPort=' + str(proxy.port or 80))
PYPROXY
)"
  export GRADLE_OPTS="${GRADLE_OPTS:-} $SUPARE_PROXY_JAVA -Dhttp.nonProxyHosts=localhost|127.*"
  export JAVA_OPTS="${JAVA_OPTS:-} $SUPARE_PROXY_JAVA"
  unset SUPARE_PROXY_JAVA
fi

# Debian runtime SQLite provides .so.0; FFI test tooling also needs its linker alias.
if [[ -d "$SUPARE_ROOT/tool/native-libs" ]]; then
  export LD_LIBRARY_PATH="$SUPARE_ROOT/tool/native-libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
# Retain the environment CA trust for checksum-verified downloaded JDKs.
if [[ -f /etc/ssl/certs/java/cacerts ]]; then
  export GRADLE_OPTS="${GRADLE_OPTS:-} -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts"
  export JAVA_OPTS="${JAVA_OPTS:-} -Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts"
fi
