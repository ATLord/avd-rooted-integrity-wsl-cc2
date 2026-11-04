#!/usr/bin/env bash
set -u
sdk="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
serial="${ANDROID_SERIAL:-emulator-5554}"
adb="$sdk/platform-tools/adb"
[[ "$("$adb" -s "$serial" emu avd name 2>/dev/null | tr -d '\r' | head -1)" = "${AVD_NAME:-Pixel_9_Pro_XL_x86}" ]] || { echo 'Expected AVD is not running.' >&2; exit 1; }
echo '== Android Wi-Fi framework (independent of IP connectivity over eth0/QEMU NAT) =='
"$adb" -s "$serial" shell cmd wifi status | head -5 || true
echo '== Interfaces, routes and Android default network =='
"$adb" -s "$serial" shell ip addr || true
"$adb" -s "$serial" shell ip route || true
"$adb" -s "$serial" shell dumpsys connectivity | grep -E 'Active default|VALIDATED|TRANSPORT' || true
echo '== IP reachability =='
"$adb" -s "$serial" shell ping -c 1 -W 3 1.1.1.1 || true
echo '== DNS and HTTPS probes (10 second limit each) =='
for url in https://www.baidu.com https://www.google.com https://connectivitycheck.gstatic.com/generate_204 https://android.googleapis.com/attestation/status; do
  echo "-- $url"
  output=$("$adb" -s "$serial" shell "su -c 'timeout 10 /data/adb/ksu/bin/busybox wget -S -O /dev/null $url'" 2>&1)
  status=$?
  if [[ -n "$output" ]]; then printf '%s\n' "$output"; else echo '(probe produced no output)'; fi
  if [[ "$status" -eq 0 ]]; then
    echo 'PASS: wget completed (exit 0); this does not validate attestation or Android framework connectivity.'
  else
    echo "FAIL: probe failed or timed out (exit $status); HTTP errors also produce failures."
  fi
done
echo 'These probes test connectivity, not a Play Integrity verdict. Android traffic may use a different path from Windows apps.'
