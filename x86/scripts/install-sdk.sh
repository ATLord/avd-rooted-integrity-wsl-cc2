#!/usr/bin/env bash
set -euo pipefail
sdk="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
revision=15859902
checksum=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
command -v java >/dev/null || { echo 'Install a Java 17 or newer runtime first.' >&2; exit 1; }
command -v curl >/dev/null
command -v unzip >/dev/null
if [[ ! -x "$sdk/cmdline-tools/latest/bin/sdkmanager" ]]; then
  [[ ! -e "$sdk/cmdline-tools/latest" ]] || { echo 'Existing latest command-line tools are incomplete; resolve manually.' >&2; exit 1; }
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fL --retry 2 -o "$tmp/tools.zip" "https://dl.google.com/android/repository/commandlinetools-linux-${revision}_latest.zip"
  echo "$checksum  $tmp/tools.zip" | sha256sum -c -
  unzip -q "$tmp/tools.zip" -d "$tmp"
  mkdir -p "$sdk/cmdline-tools"
  mv "$tmp/cmdline-tools" "$sdk/cmdline-tools/latest"
fi
manager="$sdk/cmdline-tools/latest/bin/sdkmanager"
echo 'Review and accept the SDK licenses in the prompts if you wish to proceed.'
"$manager" --sdk_root="$sdk" --licenses
"$manager" --sdk_root="$sdk" 'platform-tools' 'emulator' 'system-images;android-36;google_apis_playstore;x86_64'
grep -qx 'Pkg.Revision=7' "$sdk/system-images/android-36/google_apis_playstore/x86_64/source.properties" || { echo 'SDK installed a system image other than revision 7; kernel compatibility is unverified.' >&2; exit 1; }
