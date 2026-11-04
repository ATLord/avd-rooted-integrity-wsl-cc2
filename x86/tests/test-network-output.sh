#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/sdk/platform-tools"
cat > "$tmp/sdk/platform-tools/adb" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  *'emu avd name'*) echo Pixel_9_Pro_XL_x86 ;;
  *'cmd wifi status'*) echo 'Wifi is disabled' ;;
  *wget*)
    case "$PROBE" in
      silent) exit 0 ;;
      unusual) echo 'unrecognized diagnostic payload'; exit 0 ;;
      failure) exit 124 ;;
    esac ;;
esac
MOCK
chmod +x "$tmp/sdk/platform-tools/adb"
for probe in silent unusual failure; do
  PROBE="$probe" ANDROID_SDK_ROOT="$tmp/sdk" bash "$root/x86/scripts/check-network.sh" >"$tmp/out"
  grep -q 'eth0/QEMU NAT' "$tmp/out"
  case "$probe" in
    silent) [[ $(grep -c 'probe produced no output' "$tmp/out") == 4 ]]; [[ $(grep -c 'PASS:' "$tmp/out") == 4 ]] ;;
    unusual) [[ $(grep -c 'unrecognized diagnostic payload' "$tmp/out") == 4 ]] ;;
    failure) [[ $(grep -c 'exit 124' "$tmp/out") == 4 ]] ;;
  esac
done
echo 'Network probes report silent success, unfamiliar output and timeouts.'
