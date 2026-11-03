#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/sdk/platform-tools"
cat > "$tmp/sdk/platform-tools/adb" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ADB_TEST_LOG"
case "$*" in
  *'emu avd name'*) echo Pixel_9_Pro_XL_x86 ;;
  *'su -c id'*) echo 'uid=0(root)' ;;
  *'test -d /data/adb/modules/playintegrityfix'*) echo ok ;;
  *'sh /data/local/tmp/avd-setup/install.sh'*) printf 'OK\nAVD_SETUP_RC=0\n' ;;
esac
MOCK
chmod +x "$tmp/sdk/platform-tools/adb"
printf '%s\n' '<AndroidAttestation><Key><Certificate>test</Certificate></Key></AndroidAttestation>' > "$tmp/test-key.xml"
export ADB_TEST_LOG="$tmp/adb.log" ANDROID_SDK_ROOT="$tmp/sdk"
existing_keybox=no
[[ ! -e "$root/device/data_adb/tricky_store/keybox.xml" ]] || existing_keybox=yes
bash "$root/x86/scripts/configure-device.sh" "$tmp/test-key.xml" >/dev/null
grep -Fq "push $tmp/test-key.xml /data/local/tmp/avd-setup/tricky_store/keybox.xml" "$ADB_TEST_LOG"
if [[ "$existing_keybox" = no && -e "$root/device/data_adb/tricky_store/keybox.xml" ]]; then
  echo 'Unexpected project keybox file' >&2; exit 1
fi
echo 'External keybox staging test passed; no device was modified.'
