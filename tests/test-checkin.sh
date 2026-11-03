#!/usr/bin/env bash
# 12-checkin.sh: waits for this boot's network-ready marker when the Wi-Fi
# service is installed, ignores a stale marker, and always sends the check-in.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/device/data_adb/service.d/12-checkin.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\necho 1\n' > "$tmp/bin/getprop"
printf '#!/usr/bin/env bash\necho "NetworkAgentInfo VALIDATED"\n' > "$tmp/bin/dumpsys"
printf '#!/usr/bin/env bash\necho "am $*" >> "$TEST_DIR/am.log"\n' > "$tmp/bin/am"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/sleep"
chmod +x "$tmp/bin/"*
echo boot-1 > "$tmp/boot_id"
touch "$tmp/wlan-service.sh"
export TEST_DIR="$tmp" PATH="$tmp/bin:$PATH" AVD_CHECKIN_LOG="$tmp/checkin.log" \
  AVD_NET_READY="$tmp/ready" AVD_BOOT_ID_FILE="$tmp/boot_id" AVD_WLAN_SERVICE="$tmp/wlan-service.sh"

run() { rm -f "$tmp/am.log"; sh "$script"; grep -q 'android.server.checkin.CHECKIN' "$tmp/am.log" || { echo 'Check-in not sent' >&2; exit 1; }; }

echo boot-1 > "$tmp/ready"; run
grep -q 'wlan ready=yes' "$tmp/checkin.log" || { echo 'Current-boot marker not accepted' >&2; exit 1; }

echo boot-0 > "$tmp/ready"; run
grep -q 'wlan ready=timeout' "$tmp/checkin.log" || { echo 'Stale marker accepted' >&2; exit 1; }
[[ -f "$tmp/checkin.log.prev" ]] || { echo 'Previous log not kept' >&2; exit 1; }

rm -f "$tmp/wlan-service.sh"; run
grep -q 'wlan ready=skipped' "$tmp/checkin.log" || { echo 'Did not skip marker wait without the Wi-Fi service' >&2; exit 1; }

echo '12-checkin.sh waits for this boot'\''s marker and always sends the check-in.'
