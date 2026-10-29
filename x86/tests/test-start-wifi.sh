#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/sdk/platform-tools" "$tmp/sdk/emulator" "$tmp/bin"
touch "$tmp/kernel"
export TEST_DIR="$tmp" ANDROID_SDK_ROOT="$tmp/sdk" KERNEL="$tmp/kernel"
cat > "$tmp/sdk/platform-tools/adb" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  *'emu avd name'*)
    if [[ -e "$TEST_DIR/seen" ]]; then echo Pixel_9_Pro_XL_x86; else touch "$TEST_DIR/seen"; fi ;;
  *'shell getprop sys.boot_completed'*)
    count=0; [[ ! -e "$TEST_DIR/count" ]] || read -r count < "$TEST_DIR/count"
    count=$((count + 1)); echo "$count" > "$TEST_DIR/count"
    [[ "$count" -eq 3 ]] || echo 1 ;;
  *'shell svc wifi enable'*) echo enable >> "$TEST_DIR/wifi.log" ;;
  *'shell cmd wifi connect-network VirtWifi open'*) echo connect >> "$TEST_DIR/wifi.log" ;;
  *'shell cmd wifi status'*) echo 'Wifi is connected to "VirtWifi"' ;;
esac
MOCK
cat > "$tmp/sdk/emulator/emulator" <<'MOCK'
#!/usr/bin/env bash
/bin/sleep 3
MOCK
cat > "$tmp/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
/bin/sleep 0.05
MOCK
chmod +x "$tmp/sdk/platform-tools/adb" "$tmp/sdk/emulator/emulator" "$tmp/bin/sleep"
export PATH="$tmp/bin:$PATH"
bash "$root/x86/scripts/start.sh"
[[ $(grep -c '^enable$' "$tmp/wifi.log") -eq 2 ]]
[[ $(grep -c '^connect$' "$tmp/wifi.log") -eq 2 ]]
echo 'Wi-Fi setup ran once per simulated Android boot.'
