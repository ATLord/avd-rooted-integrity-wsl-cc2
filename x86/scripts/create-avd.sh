#!/usr/bin/env bash
set -euo pipefail
sdk="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}"
name="${AVD_NAME:-Pixel_9_Pro_XL_x86}"
android_home="${ANDROID_USER_HOME:-$HOME/.android}"
avd_home="${ANDROID_AVD_HOME:-$android_home/avd}"
manager="$sdk/cmdline-tools/latest/bin/avdmanager"
image='system-images;android-36;google_apis_playstore;x86_64'
[[ -x "$manager" && -x "$sdk/emulator/emulator" ]] || { echo 'Android SDK command-line tools and emulator are required.' >&2; exit 1; }
[[ -f "$sdk/system-images/android-36/google_apis_playstore/x86_64/package.xml" ]] || { echo "Install $image using sdkmanager first." >&2; exit 1; }
grep -qx 'Pkg.Revision=7' "$sdk/system-images/android-36/google_apis_playstore/x86_64/source.properties" || { echo 'This kernel config was validated with system image revision 7 only.' >&2; exit 1; }
if [[ -e "$avd_home/$name.ini" || -d "$avd_home/$name.avd" ]]; then
  echo "AVD $name already exists; leaving it unchanged." >&2
  exit 1
fi
features="$android_home/advancedFeatures.ini"
if [[ -e "$features" ]]; then
  for setting in 'Wifi = on' 'VirtioWifi = off'; do
    key="${setting%% *}"
    if grep -qiE "^[[:space:]]*$key[[:space:]]*=" "$features" && ! grep -qiE "^[[:space:]]*$key[[:space:]]*=[[:space:]]*${setting##* }[[:space:]]*$" "$features"; then
      echo "Conflict in $features: $key. Resolve it before creating the AVD." >&2; exit 1
    fi
  done
fi
echo no | "$manager" create avd -n "$name" -k "$image" -d pixel_9_pro_xl
cfg="$avd_home/$name.avd/config.ini"
sed -i 's/^hw.keyboard[[:space:]]*=.*/hw.keyboard=yes/' "$cfg"
grep -q '^hw.keyboard=' "$cfg" || echo 'hw.keyboard=yes' >> "$cfg"
sed -i 's/^hw\.wifi\.enabled[[:space:]]*=.*/hw.wifi.enabled=yes/' "$cfg"
grep -q '^hw\.wifi\.enabled=' "$cfg" || echo 'hw.wifi.enabled=yes' >> "$cfg"
mkdir -p "$(dirname "$features")"
touch "$features"
grep -qiE '^\s*Wifi\s*=' "$features" || echo 'Wifi = on' >> "$features"
grep -qiE '^\s*VirtioWifi\s*=' "$features" || echo 'VirtioWifi = off' >> "$features"
echo "Created $name. Keyboard and Wi-Fi settings are enabled."
