#!/usr/bin/env bash
# Regression test for the upstream ARM (macOS Apple Silicon) launcher.
# Locks in the emulator arguments and the hw.wifi.enabled patch so x86 work
# cannot silently change the original flow. No real emulator or device needed.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.android/avd/Pixel_9_Pro_XL.avd" "$tmp/kernel"
touch "$tmp/kernel/Image.gz"
printf 'hw.keyboard = yes\n' > "$tmp/home/.android/avd/Pixel_9_Pro_XL.avd/config.ini"
cat > "$tmp/bin/adb" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat > "$tmp/emulator" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$EMU_ARGS"
MOCK
chmod +x "$tmp/bin/adb" "$tmp/emulator"

run() {
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" EMU_ARGS="$tmp/args" LOG="$tmp/boot.log" \
    KERNEL="$tmp/kernel/Image.gz" "$@" bash "$root/scripts/start_avd.sh" >/dev/null
}

# 1. Explicit EMULATOR override (upstream behaviour).
run env EMULATOR="$tmp/emulator"
expected="-avd
Pixel_9_Pro_XL
-kernel
$tmp/kernel/Image.gz
-no-snapshot-load
-no-snapshot-save
-verbose"
[[ "$(cat "$tmp/args")" == "$expected" ]] || { echo 'Emulator arguments changed:' >&2; cat "$tmp/args" >&2; exit 1; }
grep -qx 'hw.wifi.enabled = yes' "$tmp/home/.android/avd/Pixel_9_Pro_XL.avd/config.ini" || { echo 'hw.wifi.enabled was not added' >&2; exit 1; }

# 2. Re-running must not duplicate the Wi-Fi line.
run env EMULATOR="$tmp/emulator"
[[ "$(grep -c '^hw.wifi.enabled' "$tmp/home/.android/avd/Pixel_9_Pro_XL.avd/config.ini")" -eq 1 ]] || { echo 'hw.wifi.enabled duplicated' >&2; exit 1; }

# 3. ANDROID_SDK_ROOT resolution still works.
mkdir -p "$tmp/sdk/emulator"
cp "$tmp/emulator" "$tmp/sdk/emulator/emulator"
rm -f "$tmp/args"
run env -u EMULATOR ANDROID_SDK_ROOT="$tmp/sdk"
[[ -s "$tmp/args" ]] || { echo 'ANDROID_SDK_ROOT emulator was not used' >&2; exit 1; }

# 4. AVD override.
mkdir -p "$tmp/home/.android/avd/Other.avd"
touch "$tmp/home/.android/avd/Other.avd/config.ini"
run env AVD=Other EMULATOR="$tmp/emulator"
[[ "$(sed -n 2p "$tmp/args")" == Other ]] || { echo 'AVD override ignored' >&2; exit 1; }

echo 'ARM start_avd.sh regression test passed.'
