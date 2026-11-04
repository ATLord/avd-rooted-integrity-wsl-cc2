#!/usr/bin/env bash
# install-device-setup.sh must (1) succeed when every device step succeeds,
# (2) exit non-zero and name the failing step when one fails, and (3) always
# remove the staged copy (which holds the keybox). The device-side script is
# executed locally against stub commands; nothing touches a real device.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/device-bin"
printf '%s\n' '<AndroidAttestation><Key><Certificate>test</Certificate></Key></AndroidAttestation>' > "$tmp/keybox.xml"

cat > "$tmp/bin/adb" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  wait-for-device) ;;
  "shell su -c id") echo 'uid=0(root)' ;;
  *'test -d /data/adb/modules/playintegrityfix'*) echo ok ;;
  push*/install.sh) cp "$2" "$TEST_DIR/install.sh" ;;
  push*) ;;
  *"sh /data/local/tmp/avd-setup/install.sh"*)
    PATH="$TEST_DIR/device-bin:$PATH" sh "$TEST_DIR/install.sh" ;;
  shell*) ;;
esac
MOCK
# Device-side stubs: log every call; cp fails when its args match FAIL_MATCH.
for cmd in cp chmod chown mkdir chattr rm; do
  cat > "$tmp/device-bin/$cmd" <<MOCK
#!/usr/bin/env bash
printf '%s %s\n' "$cmd" "\$*" >> "\$TEST_DIR/device.log"
if [[ "$cmd" == cp && -n "\${FAIL_MATCH:-}" && "\$*" == *"\$FAIL_MATCH"* ]]; then exit 1; fi
exit 0
MOCK
done
chmod +x "$tmp/bin/adb" "$tmp/device-bin/"*
export TEST_DIR="$tmp" KEYBOX="$tmp/keybox.xml" PATH="$tmp/bin:$PATH"

# 1. All steps succeed.
: > "$tmp/device.log"
out="$(bash "$root/scripts/install-device-setup.sh" 2>&1)" || { echo "$out" >&2; echo 'Expected success' >&2; exit 1; }
grep -q '==> done' <<<"$out" || { echo 'Missing completion message' >&2; exit 1; }
grep -q '^FILES_STAGED:' <<<"$out" || { echo 'Missing device OK' >&2; exit 1; }
grep -Fq 'chmod 644 /data/adb/tricky_store/keybox.xml' "$tmp/device.log" || { echo 'Keybox mode not set' >&2; exit 1; }
grep -Fq 'rm -rf /data/local/tmp/avd-setup' "$tmp/device.log" || { echo 'Stage not removed' >&2; exit 1; }

# 2. Keybox copy fails: script must fail, report it, and still clean up.
: > "$tmp/device.log"
if out="$(FAIL_MATCH=keybox.xml bash "$root/scripts/install-device-setup.sh" 2>&1)"; then
  echo "$out" >&2; echo 'Expected failure when keybox copy fails' >&2; exit 1
fi
grep -q 'FAILED: cp -f /data/local/tmp/avd-setup/tricky_store/keybox.xml' <<<"$out" || { echo "$out" >&2; echo 'Failing step not reported' >&2; exit 1; }
! grep -q '==> done' <<<"$out" || { echo 'Reported done after failure' >&2; exit 1; }
grep -Fq 'cp -f /data/local/tmp/avd-setup/tricky_store/tee_status.txt' "$tmp/device.log" || { echo 'Later steps were skipped after failure' >&2; exit 1; }
grep -Fq 'rm -rf /data/local/tmp/avd-setup' "$tmp/device.log" || { echo 'Stage (with keybox) not removed after failure' >&2; exit 1; }

echo 'install-device-setup.sh reports device-side failures and always cleans up.'
