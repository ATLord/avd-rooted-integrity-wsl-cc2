#!/usr/bin/env bash
set -u
sdk="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
serial="${ANDROID_SERIAL:-emulator-5554}"
adb="$sdk/platform-tools/adb"
[[ "$("$adb" -s "$serial" emu avd name 2>/dev/null | tr -d '\r' | head -1)" = "${AVD_NAME:-Pixel_9_Pro_XL_x86}" ]] || { echo 'Expected AVD is not running.' >&2; exit 1; }
"$adb" -s "$serial" shell cmd wifi status | head -5 || true
echo '== IP reachability =='
"$adb" -s "$serial" shell ping -c 1 -W 3 1.1.1.1 || true
echo '== DNS and HTTPS probes (10 second limit each) =='
for url in https://www.baidu.com https://www.google.com https://connectivitycheck.gstatic.com/generate_204 https://android.googleapis.com/attestation/status; do
  echo "-- $url"
  output=$("$adb" -s "$serial" shell "su -c 'timeout 10 /data/adb/ksu/bin/busybox wget -S -O /dev/null $url'" 2>&1)
  status=$?
  printf '%s\n' "$output" | grep -E 'Connecting|HTTP/|timed out|failed|saved|error|not found' || true
  if [[ "$status" -ne 0 ]]; then echo "Probe failed or timed out (exit $status)."; fi
done
echo 'These probes test connectivity, not a Play Integrity verdict. Android traffic may use a different path from Windows apps.'
