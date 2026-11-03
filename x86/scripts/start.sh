#!/bin/bash
set -eu
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
# Use Windows routing/TUN rather than inheriting a stale HTTP proxy from WSL.
# Set AVD_KEEP_PROXY=1 to pass the current proxy variables to the emulator.
if [ "${AVD_KEEP_PROXY:-0}" != 1 ]; then
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
kernel="${KERNEL:-$root/x86/out/bzImage-x86_64}"
avd="${AVD_NAME:-Pixel_9_Pro_XL_x86}"
kvm="${AVD_KVM_DEVICE:-/dev/kvm}"
# ANDROID_SERIAL=emulator-<port> picks the console port; default emulator-5554.
serial="${ANDROID_SERIAL:-emulator-5554}"
port="${serial#emulator-}"
[[ "$serial" == emulator-* && "$port" =~ ^[0-9]+$ ]] || { echo "ANDROID_SERIAL must look like emulator-5554 (got $serial)." >&2; exit 1; }
[[ -f "$kernel" ]] || { echo "Kernel not found: $kernel" >&2; exit 1; }
if [ ! -r "$kvm" ] || [ ! -w "$kvm" ]; then
  # Intel VT-x reports "vmx", AMD-V reports "svm".
  kvm_module=kvm_intel
  if grep -qw svm /proc/cpuinfo 2>/dev/null; then kvm_module=kvm_amd; fi
  if [ -n "${WSL_DISTRO_NAME:-}" ]; then
    echo 'KVM is unavailable. In Windows PowerShell run:'
    echo "wsl -d $WSL_DISTRO_NAME -u root -- sh -c \"modprobe $kvm_module && chgrp kvm /dev/kvm && chmod 660 /dev/kvm\""
  else
    echo 'KVM is unavailable. Enable virtualization in firmware, then run:'
    echo "sudo modprobe $kvm_module && sudo usermod -aG kvm \"\$USER\"   # log out and back in afterwards"
  fi
  exit 1
fi
if "$ANDROID_SDK_ROOT/platform-tools/adb" -s "$serial" emu avd name 2>/dev/null | tr -d '\r' | grep -qx "$avd"; then
  echo "$avd is already running."
  exit 0
fi
"$ANDROID_SDK_ROOT/emulator/emulator" -avd "$avd" -port "$port" \
  -kernel "$kernel" -no-snapshot -gpu swiftshader_indirect -accel on \
  -qemu -append kernelsu.allow_shell=1 &
emulator_pid=$!
(
  adb="$ANDROID_SDK_ROOT/platform-tools/adb"
  # The device-side service (device/data_adb/service.d/10-wlan0-virtwifi.sh,
  # installed by install-modules.sh) owns Wi-Fi setup and writes this boot's
  # boot_id to the marker. When it is present the host only waits; it falls
  # back to connecting itself if the service is missing (older installs) or
  # has not reported after fallback_after loop iterations (~10 minutes).
  service=/data/adb/service.d/10-wlan0-virtwifi.sh
  marker=/data/adb/avd-net-ready
  fallback_after="${AVD_WIFI_FALLBACK_ITERATIONS:-200}"
  sleep 20
  configured=0
  waited=0
  while kill -0 "$emulator_pid" 2>/dev/null; do
    if "$adb" -s "$serial" emu avd name 2>/dev/null | tr -d '\r' | grep -qx "$avd" &&
       [ "$("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
      if [ "$configured" -eq 1 ]; then sleep 3; continue; fi
      if [ "$waited" -lt "$fallback_after" ] &&
         "$adb" -s "$serial" shell "su -c 'test -f $service && echo present'" 2>/dev/null | tr -d '\r' | grep -qx present; then
        boot_id="$("$adb" -s "$serial" shell cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\r')"
        ready="$("$adb" -s "$serial" shell "su -c 'cat $marker 2>/dev/null'" 2>/dev/null | tr -d '\r')"
        if [ -n "$boot_id" ] && [ "$ready" = "$boot_id" ]; then
          configured=1
          echo 'Wi-Fi connected to VirtWifi (device service).'
        else
          waited=$((waited + 1))
        fi
      else
        "$adb" -s "$serial" shell svc wifi enable >/dev/null 2>&1 || true
        sleep 5
        "$adb" -s "$serial" shell cmd wifi connect-network VirtWifi open >/dev/null 2>&1 || true
        sleep 5
        if "$adb" -s "$serial" shell cmd wifi status 2>/dev/null | grep -q 'Wifi is connected to "VirtWifi"'; then
          configured=1
          echo 'Wi-Fi connected to VirtWifi (host fallback).'
        fi
      fi
    else
      configured=0
      waited=0
    fi
    sleep 3
  done
) &
wait "$emulator_pid"
