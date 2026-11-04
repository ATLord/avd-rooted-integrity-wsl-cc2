#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export ANDROID_SDK_ROOT="$tmp/sdk" ANDROID_USER_HOME="$tmp/android" ANDROID_AVD_HOME="$tmp/android/avd"
export AVD_NAME=TestPixel
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" "$ANDROID_SDK_ROOT/emulator" "$ANDROID_SDK_ROOT/system-images/android-36/google_apis_playstore/x86_64"
touch "$ANDROID_SDK_ROOT/system-images/android-36/google_apis_playstore/x86_64/package.xml"
echo Pkg.Revision=7 > "$ANDROID_SDK_ROOT/system-images/android-36/google_apis_playstore/x86_64/source.properties"
printf '#!/bin/sh\nexit 0\n' > "$ANDROID_SDK_ROOT/emulator/emulator"
cat > "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager" <<'MOCK'
#!/usr/bin/env bash
echo 'Error: Could not load devices from image/devices.xml'
[[ "$PROFILE_CASE" != error ]] || exit 7
mkdir -p "$ANDROID_AVD_HOME/$AVD_NAME.avd"
if [[ "$PROFILE_CASE" == correct ]]; then
  printf 'hw.device.name=pixel_9_pro_xl\nhw.lcd.width=1344\nhw.lcd.height=2992\n'
else
  echo hw.device.name=default
fi > "$ANDROID_AVD_HOME/$AVD_NAME.avd/config.ini"
MOCK
chmod +x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/avdmanager" "$ANDROID_SDK_ROOT/emulator/emulator"
for mode in correct wrong error; do
  export AVD_NAME="TestPixel_$mode"
  rc=0
  PROFILE_CASE="$mode" bash "$root/x86/scripts/create-avd.sh" >"$tmp/out" 2>&1 || rc=$?
  if [[ "$mode" == correct ]]; then
    [[ "$rc" == 0 ]]
    grep -q 'hw.wifi.enabled=yes' "$ANDROID_AVD_HOME/$AVD_NAME.avd/config.ini"
  else
    [[ "$rc" != 0 ]]
  fi
  grep -q 'devices.xml' "$tmp/out"
done
echo 'AVD creation preserves diagnostics and rejects missing device profile or manager failures.'
