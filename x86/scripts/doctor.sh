#!/usr/bin/env bash
set -u
sdk="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
missing=0
check() { if "$@"; then printf 'OK   %s\n' "$*"; else printf 'FAIL %s\n' "$*"; missing=1; fi; }
echo "Host: $(uname -sm)"
check test "$(uname -m)" = x86_64
check test -x "$sdk/platform-tools/adb"
check test -x "$sdk/emulator/emulator"
check test -x "$sdk/cmdline-tools/latest/bin/avdmanager"
check test -f "$sdk/system-images/android-36/google_apis_playstore/x86_64/package.xml"
check test -r /dev/kvm
check test -w /dev/kvm
check test -f "$root/x86/out/bzImage-x86_64"
if [[ -x "$sdk/emulator/emulator" ]]; then "$sdk/emulator/emulator" -accel-check || missing=1; fi
if [[ -x "$sdk/platform-tools/adb" ]]; then "$sdk/platform-tools/adb" devices -l; fi
echo 'Kernel build also requires Docker Desktop and Git on Windows; run x86/build.ps1 in PowerShell.'
exit "$missing"
