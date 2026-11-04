#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
adb="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/platform-tools/adb"
serial="${ANDROID_SERIAL:-emulator-5554}"
downloads="$root/x86/downloads"
mkdir -p "$downloads"
fetch() {
  local name="$1" url="$2" digest="$3" tmp="$downloads/$1.part"
  if [[ ! -f "$downloads/$name" ]] || ! echo "$digest  $downloads/$name" | sha256sum -c --status; then
    curl -fL --retry 2 --connect-timeout 15 --max-time 120 -o "$tmp" "$url"
    echo "$digest  $tmp" | sha256sum -c -
    mv "$tmp" "$downloads/$name"
  fi
}
fetch KernelSU.apk 'https://github.com/KernelSU-Next/KernelSU-Next/releases/download/v3.2.0/KernelSU_Next_v3.2.0_33129-release.apk' 96c2bbbf1b973461fe82dd1ed17f89deb86a6a5a9d7c4cf079bd32091131ef57
fetch rezygisk.zip 'https://github.com/PerformanC/ReZygisk/releases/download/v1.0.0/ReZygisk-v1.0.0-release.zip' 7904649b8dcaf2b060c3432df4fee302aeb1258da199d2b425335e82d49510e6
fetch pif.zip 'https://github.com/osm0sis/PlayIntegrityFork/releases/download/v16/PlayIntegrityFork-v16.zip' 3bd4d59fde43e1def793012415d1af544fd0d94ad91dbcfd4c79c4f939ebe412
fetch tee.zip 'https://github.com/JingMatrix/TEESimulator/releases/download/v3.2/TEESimulator-v3.2-67-Release.zip' af8d38e427d6f8893305d9dba00256e0ba6e1afbadf32aab5ca8afc785404aab
if [[ "${1:-}" == '--download-only' ]]; then
  echo 'Download checksums verified; no device was modified.'
  exit 0
fi
[[ "$("$adb" -s "$serial" emu avd name | tr -d '\r' | head -1)" = "${AVD_NAME:-Pixel_9_Pro_XL_x86}" ]] || { echo 'Unexpected AVD; refusing to install.' >&2; exit 1; }
"$adb" -s "$serial" install -r "$downloads/KernelSU.apk"
"$adb" -s "$serial" shell am start -n com.rifsxd.ksunext/.ui.MainActivity >/dev/null
for ((attempt=0; attempt<30; attempt++)); do
  if "$adb" -s "$serial" shell su -c id 2>/dev/null | grep -q 'uid=0'; then break; fi
  sleep 1
done
if ! "$adb" -s "$serial" shell su -c id 2>/dev/null | grep -q 'uid=0'; then
  echo 'ADB Shell 自动 Root 未成功：请用本版本的 start.sh 启动已编译内核后重试。' >&2
  exit 1
fi
echo 'ADB Shell Root 已自动启用。'
# Install the daemon from the checksum-verified APK, not an assumed existing
# bin/ksud. init executes /data/adb/ksud; root alone proves neither its presence
# nor that the manager finished its asynchronous userspace installation.
unzip -p "$downloads/KernelSU.apk" lib/x86_64/libksud.so > "$downloads/ksud-x86_64"
[[ -s "$downloads/ksud-x86_64" ]] || { echo 'APK lacks x86_64 ksud' >&2; exit 1; }
"$adb" -s "$serial" push "$downloads/ksud-x86_64" /data/local/tmp/avd-ksud
"$adb" -s "$serial" shell "su -c 'chmod 755 /data/local/tmp/avd-ksud && /data/local/tmp/avd-ksud install && test -x /data/adb/ksud && /data/adb/ksud --version'"
"$adb" -s "$serial" shell "su -c 'rm -f /data/local/tmp/avd-ksud'"
echo 'SKIP: bundled SUSFS userspace module is ARM64-only. Kernel SUSFS support remains available.'
# Disable a previously installed incompatible module; keep its files for review.
"$adb" -s "$serial" shell "su -c 'for d in /data/adb/modules/susfs4ksu /data/adb/modules_update/susfs4ksu; do if [ -d \"\$d\" ]; then touch \"\$d/disable\" || exit 1; fi; done'"
for name in rezygisk pif tee; do
  "$adb" -s "$serial" push "$downloads/$name.zip" "/data/local/tmp/avd-$name.zip"
  "$adb" -s "$serial" shell "su -c '/data/adb/ksud module install /data/local/tmp/avd-$name.zip'"
done
echo 'Installing lifecycle probes.'
for stage in post-fs-data service; do
  directory="$stage.d"
  "$adb" -s "$serial" push "$root/device/data_adb/$directory/00-boot-probe.sh" /data/local/tmp/avd-boot-probe.sh
  "$adb" -s "$serial" shell "su -c 'mkdir -p /data/adb/$directory && cp /data/local/tmp/avd-boot-probe.sh /data/adb/$directory/00-boot-probe.sh && chmod 755 /data/adb/$directory/00-boot-probe.sh && rm -f /data/local/tmp/avd-boot-probe.sh'"
done
echo 'Installing VirtWifi boot service.'
wifi_stage="/data/local/tmp/avd-wifi-service-$$.sh"
"$adb" -s "$serial" push "$root/device/data_adb/service.d/10-wlan0-virtwifi.sh" "$wifi_stage"
"$adb" -s "$serial" shell "su -c 'mkdir -p /data/adb/service.d && cp $wifi_stage /data/adb/service.d/10-wlan0-virtwifi.sh && chmod 755 /data/adb/service.d/10-wlan0-virtwifi.sh && rm -f $wifi_stage'"
"$adb" -s "$serial" shell su -c sync
echo 'Files installed; activation PENDING. adb emu kill, wait for launcher exit, restart start-x11.sh, then run scripts/check-boot.sh before configure-device.sh.'
