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
fetch susfs.zip 'https://github.com/sidex15/susfs4ksu-module/releases/download/v1.5.2%2B_R27/ksu_module_susfs_1.5.2%2B.zip' 0e5d86aaa36f8ff71a67c189d3469fb9d9468327e7b7eb173781c91fd00dc366
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
for name in susfs rezygisk pif tee; do
  "$adb" -s "$serial" push "$downloads/$name.zip" "/data/local/tmp/avd-$name.zip"
  "$adb" -s "$serial" shell "su -c '/data/adb/ksu/bin/ksud module install /data/local/tmp/avd-$name.zip'"
done
echo 'Installing VirtWifi boot service.'
wifi_stage="/data/local/tmp/avd-wifi-service-$$.sh"
"$adb" -s "$serial" push "$root/device/data_adb/service.d/10-wlan0-virtwifi.sh" "$wifi_stage"
"$adb" -s "$serial" shell "su -c 'mkdir -p /data/adb/service.d && cp $wifi_stage /data/adb/service.d/10-wlan0-virtwifi.sh && chmod 755 /data/adb/service.d/10-wlan0-virtwifi.sh && rm -f $wifi_stage'"
"$adb" -s "$serial" shell su -c sync
echo 'Modules installed. Reboot the guest, wait for boot, then run configure-device.sh.'
