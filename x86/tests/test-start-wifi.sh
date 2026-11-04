#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/sdk/platform-tools" "$tmp/sdk/emulator" "$tmp/bin"
touch "$tmp/kernel" "$tmp/kvm"
export TEST_DIR="$tmp" ANDROID_SDK_ROOT="$tmp/sdk" KERNEL="$tmp/kernel" AVD_KVM_DEVICE="$tmp/kvm"
export http_proxy=http://127.0.0.1:1 HTTPS_PROXY=http://127.0.0.1:1 ALL_PROXY=socks5://127.0.0.1:1
cat > "$tmp/sdk/platform-tools/adb" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  *'emu avd name'*)
    if [[ -e "$TEST_DIR/seen" ]]; then echo Pixel_9_Pro_XL_x86; else touch "$TEST_DIR/seen"; fi ;;
  *'shell getprop sys.boot_completed'*)
    count=0; [[ ! -e "$TEST_DIR/count" ]] || read -r count < "$TEST_DIR/count"
    count=$((count + 1)); echo "$count" > "$TEST_DIR/count"
    [[ "$count" -eq 3 ]] || echo 1 ;;
  *'test -f /data/adb/service.d/10-wlan0-virtwifi.sh'*)
    [[ "${SERVICE_PRESENT:-0}" != 1 ]] || echo present ;;
  *'cat /proc/sys/kernel/random/boot_id'*) echo boot-1 ;;
  *'cat /data/adb/avd-net-ready'*) [[ -z "${MARKER:-}" ]] || echo "$MARKER" ;;
  *'shell svc wifi enable'*) echo enable >> "$TEST_DIR/wifi.log" ;;
  *'shell cmd wifi connect-network VirtWifi open'*) echo connect >> "$TEST_DIR/wifi.log" ;;
  *'shell cmd wifi status'*) echo 'Wifi is connected to "VirtWifi"' ;;
esac
MOCK
cat > "$tmp/sdk/emulator/emulator" <<'MOCK'
#!/usr/bin/env bash
if [[ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}${HTTPS_PROXY:-}${all_proxy:-}${ALL_PROXY:-}" ]]; then
  echo 'Unexpected inherited proxy environment' >&2
  exit 1
fi
# Count observed boot polls, not machine-dependent wall time (Git Bash is slower).
for ((attempt=0; attempt<600; attempt++)); do
  count=0; [[ ! -f "$TEST_DIR/count" ]] || read -r count < "$TEST_DIR/count"
  [[ "$count" -lt 12 ]] || exit 0
  /bin/sleep 0.05
done
echo 'Mock emulator timed out waiting for host polls' >&2
exit 1
MOCK
cat > "$tmp/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
/bin/sleep 0.05
MOCK
chmod +x "$tmp/sdk/platform-tools/adb" "$tmp/sdk/emulator/emulator" "$tmp/bin/sleep"
export PATH="$tmp/bin:$PATH"

run_case() { rm -f "$tmp/seen" "$tmp/count" "$tmp/wifi.log"; touch "$tmp/wifi.log"; bash "$root/x86/scripts/start.sh" > "$tmp/out"; }
count() { grep -c "^$1\$" "$tmp/wifi.log" || true; }

# 1. No device-side service (older install): host connects once per boot.
run_case
[[ $(count enable) -eq 2 ]]
[[ $(count connect) -eq 2 ]]
grep -q 'host fallback' "$tmp/out"

# 2. Device service present and ready for this boot: host never touches Wi-Fi.
SERVICE_PRESENT=1 MARKER=boot-1 run_case
[[ $(count enable) -eq 0 ]] || { echo 'Host ran Wi-Fi setup although the device service reported ready' >&2; exit 1; }
grep -q 'device service' "$tmp/out"

# 3. Device service present but its marker is stale: host falls back after the limit.
SERVICE_PRESENT=1 MARKER=boot-0 AVD_WIFI_FALLBACK_ITERATIONS=3 run_case
[[ $(count enable) -ge 1 ]] || { echo 'Host did not fall back when the device service never reported' >&2; exit 1; }

echo 'Wi-Fi setup ran once per simulated Android boot; device service preferred, host fallback kept.'
