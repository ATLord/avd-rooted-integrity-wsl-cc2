#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sdk="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
export PATH="$sdk/platform-tools:$PATH"
export ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
if [[ "$(adb -s "$ANDROID_SERIAL" emu avd name 2>/dev/null | tr -d '\r' | head -1)" != "${AVD_NAME:-Pixel_9_Pro_XL_x86}" ]]; then
  echo 'Expected AVD is not running.' >&2; exit 1
fi
echo '== Root and boot =='
adb -s "$ANDROID_SERIAL" shell getprop sys.boot_completed
adb -s "$ANDROID_SERIAL" shell su -c id || true
echo '== Network =='
adb -s "$ANDROID_SERIAL" shell cmd wifi status | head -5 || true
adb -s "$ANDROID_SERIAL" shell ping -c 1 -W 3 1.1.1.1 || true
echo '== Project structural check (not a Play Integrity verdict) =='
bash "$root/scripts/verify-integrity.sh"
echo '== Native SUSFS tool (known ARM64-only limitation) =='
adb -s "$ANDROID_SERIAL" shell su -c '/data/adb/ksu/bin/ksu_susfs --help' 2>&1 | head -3 || true
echo 'Review the checks above. A Play Integrity request and its server verdict require separate testing.'
