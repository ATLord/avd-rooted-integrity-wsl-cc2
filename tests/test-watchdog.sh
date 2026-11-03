#!/usr/bin/env bash
# 05-tee-watchdog.sh: alert-only by default (never relaunches TEESimulator),
# upstream auto-relaunch when the flag file exists. Runs the device script
# locally with stubbed Android commands and a sleep that ends the loop.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/device/data_adb/service.d/05-tee-watchdog.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/ts"
cat > "$tmp/bin/getprop" <<'MOCK'
#!/usr/bin/env bash
echo 1
MOCK
cat > "$tmp/bin/pidof" <<'MOCK'
#!/usr/bin/env bash
cat "$TEST_DIR/pid" 2>/dev/null
MOCK
cat > "$tmp/bin/log" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$TEST_DIR/logcat"
MOCK
# Each sleep counts one call; after MAX_SLEEPS the watchdog loop is stopped.
cat > "$tmp/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
n=$(( $(cat "$TEST_DIR/sleeps" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$TEST_DIR/sleeps"
if [ "$n" -ge "$MAX_SLEEPS" ]; then kill -TERM "$PPID"; fi
MOCK
cat > "$tmp/ts/service.sh" <<'MOCK'
echo relaunched >> "$TEST_DIR/relaunches"
echo 4242 > "$TEST_DIR/pid"
MOCK
chmod +x "$tmp/bin/"*
export TEST_DIR="$tmp" PATH="$tmp/bin:$PATH" MAX_SLEEPS=6 \
  TEE_WATCHDOG_LOG="$tmp/watchdog.log" TEE_WATCHDOG_TS_DIR="$tmp/ts" \
  TEE_WATCHDOG_FLAG="$tmp/relaunch-flag"

run() { rm -f "$tmp/sleeps" "$tmp/relaunches" "$tmp/watchdog.log" "$tmp/logcat"; ( sh "$script"; true ) 2>/dev/null || true; }

# 1. Default (no flag), daemon down: alert once, never relaunch.
rm -f "$tmp/pid" "$tmp/relaunch-flag"
run
[[ ! -e "$tmp/relaunches" ]] || { echo 'Relaunched without the flag' >&2; exit 1; }
grep -q 'mode: alert-only' "$tmp/watchdog.log" || { echo 'Mode not logged' >&2; exit 1; }
[[ "$(grep -c 'is NOT running' "$tmp/watchdog.log")" -eq 1 ]] || { echo 'Alert not logged exactly once' >&2; cat "$tmp/watchdog.log" >&2; exit 1; }
grep -q 'cold reboot' "$tmp/logcat" || { echo 'No logcat alert' >&2; exit 1; }

# 2. Daemon alive: nothing logged besides the start line.
echo 100 > "$tmp/pid"
run
[[ "$(grep -c . "$tmp/watchdog.log")" -eq 1 ]] || { echo 'Unexpected output while daemon alive' >&2; exit 1; }

# 3. Flag present, daemon down: upstream relaunch behaviour.
rm -f "$tmp/pid"; touch "$tmp/relaunch-flag"
run
sleep_wait=0; while [[ ! -e "$tmp/relaunches" && $sleep_wait -lt 50 ]]; do /bin/sleep 0.1; sleep_wait=$((sleep_wait + 1)); done
[[ "$(grep -c relaunched "$tmp/relaunches" 2>/dev/null)" -eq 1 ]] || { echo 'Expected exactly one relaunch with the flag' >&2; exit 1; }
grep -q 'mode: relaunch' "$tmp/watchdog.log" || { echo 'Relaunch mode not logged' >&2; exit 1; }

echo 'TEE watchdog: alert-only by default, upstream relaunch behind the flag.'
