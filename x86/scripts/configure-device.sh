#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sdk="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
export PATH="$sdk/platform-tools:$PATH"
export ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-5554}"
keybox="${1:-}"
[[ -f "$keybox" ]] || { echo 'Usage: configure-device.sh /absolute/path/to/keybox.xml' >&2; exit 1; }
[[ "$(adb -s "$ANDROID_SERIAL" emu avd name | tr -d '\r' | head -1)" = "${AVD_NAME:-Pixel_9_Pro_XL_x86}" ]] || { echo 'Unexpected AVD.' >&2; exit 1; }
if ! python3 - "$keybox" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
if root.tag != 'AndroidAttestation' or not root.findall('.//Key') or not root.findall('.//Certificate'):
    raise SystemExit('Invalid keybox structure')
PY
then exit 1; fi
KEYBOX="$keybox" bash "$root/scripts/install-device-setup.sh"
adb -s "$ANDROID_SERIAL" shell su -c sync
echo 'Guest data synced. Reboot the guest, then run check-device.sh.'
