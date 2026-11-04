#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/adb" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  *random/boot_id*) echo 11111111-1111-1111-1111-111111111111 ;;
  *avd-boot/*.boot*) echo "${EVIDENCE:-11111111-1111-1111-1111-111111111111}" ;;
  *'echo enabled'*) echo enabled ;;
esac
MOCK
chmod +x "$tmp/adb"
ADB="$tmp/adb" bash "$root/scripts/check-boot.sh" >"$tmp/out"
if EVIDENCE=old-boot ADB="$tmp/adb" bash "$root/scripts/check-boot.sh" >"$tmp/out" 2>&1; then
  echo 'Accepted stale lifecycle evidence' >&2; exit 1
fi
grep -q 'no current-boot evidence' "$tmp/out"
echo 'Lifecycle check rejects stale boot evidence.'
