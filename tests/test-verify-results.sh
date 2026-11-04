#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/adb" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  *boot_id*|*avd-boot/*.boot*|*profile.boot*) echo 11111111-1111-1111-1111-111111111111 ;;
  *'echo enabled'*) echo enabled ;;
  *'test -s '*profile.env*) [[ "$CASE" == missing ]] || echo present ;;
  *DEVICE=*profile.env*) [[ "$CASE" == missing ]] || echo custom_device ;;
  *DEVICE=*custom.pif.prop*) echo custom_device ;;
  *SECURITY_PATCH=*profile.env*) [[ "$CASE" == missing ]] || echo 2026-05-05 ;;
  *security_patch.txt*) printf 'system=2026-05-05\nboot=%s\nvendor=2026-05-05\n' "${BOOT_PATCH:-2026-05-05}" ;;
  *'getprop ro.product.'*) echo custom_device ;;
  *'build.fingerprint'*) echo example/fingerprint ;;
  *'/vendor/build.prop'*) echo ro.product.vendor.device=custom_device ;;
  *implementer*) echo 0x41 ;;
  *ranchu*) echo 0 ;;
  *'pidof TEESimulator'*) echo 1234 ;;
  *'ls -l /data/adb/tricky_store/keybox.xml'*) echo '-rw-r--r-- root root keybox.xml' ;;
  *'cmd wifi status'*) echo 'Wifi is connected to "VirtWifi"' ;;
  *'logcat -d'*) echo 0 ;;
esac
MOCK
chmod +x "$tmp/adb"
run() {
  rc=0
  CASE="$1" ADB="$tmp/adb" bash "$root/scripts/verify-integrity.sh" >"$tmp/out" 2>&1 || rc=$?
  [[ "$rc" == "$2" ]] || { cat "$tmp/out"; echo "Expected $2, got $rc"; exit 1; }
}
run missing 1
grep -q 'SECURITY_PATCH missing' "$tmp/out"
! grep -q 'patch matches profile' "$tmp/out"
run present 2
grep -q 'INCOMPLETE' "$tmp/out"
BOOT_PATCH=2026-04-05 run present 1
grep -q "boot patch='2026-04-05'" "$tmp/out"
echo 'Verification rejects missing profiles, mismatched component patches and absent attestation evidence.'
