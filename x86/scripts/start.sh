#!/bin/bash
set -eu
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kernel="${KERNEL:-$root/x86/out/bzImage-x86_64}"
avd="${AVD_NAME:-Pixel_9_Pro_XL_x86}"
[[ -f "$kernel" ]] || { echo "Kernel not found: $kernel" >&2; exit 1; }
if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
  echo 'KVM is unavailable. In Windows PowerShell run:'
  echo 'wsl -d Ubuntu-22.04 -u root -- sh -c "modprobe kvm_intel && chgrp kvm /dev/kvm && chmod 660 /dev/kvm"'
  exit 1
fi
if "$ANDROID_SDK_ROOT/platform-tools/adb" -s emulator-5554 emu avd name 2>/dev/null | tr -d '\r' | grep -qx "$avd"; then
  echo "$avd is already running."
  exit 0
fi
"$ANDROID_SDK_ROOT/emulator/emulator" -avd "$avd" -port 5554 \
  -kernel "$kernel" -no-snapshot -gpu swiftshader_indirect -accel on &
emulator_pid=$!
(
  adb="$ANDROID_SDK_ROOT/platform-tools/adb"
  sleep 20
  for ((i=0; i<120; i++)); do
    kill -0 "$emulator_pid" 2>/dev/null || exit 0
    if "$adb" -s emulator-5554 emu avd name 2>/dev/null | tr -d '\r' | grep -qx "$avd" &&
       [ "$("$adb" -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
      "$adb" -s emulator-5554 shell svc wifi enable >/dev/null 2>&1 || true
      sleep 5
      "$adb" -s emulator-5554 shell cmd wifi connect-network VirtWifi open >/dev/null 2>&1 || true
      exit 0
    fi
    sleep 3
  done
) &
wait "$emulator_pid"
