#!/usr/bin/env bash
# verify-integrity.sh builds root shell snippets and sends them through
# `adb shell "su -c ..."`. adb joins its arguments into one string that the
# device's outer shell parses before su runs. This test reproduces that: the
# mock adb hands the joined string to a real POSIX sh, and a mock su checks
# that the snippet it receives is (a) valid shell and (b) unmodified.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/adb" <<'MOCK'
#!/usr/bin/env bash
[[ "${1:-}" == shell ]] || exit 0
shift
joined="$*"
# shellcheck disable=SC2016
exec sh -c 'su() {
  [ "$1" = -c ] || { echo "unexpected su args: $*" >> "$SU_LOG"; return 9; }
  printf "%s\n" "$2" >> "$SU_LOG"
  sh -n -c "$2" 2>/dev/null || printf "SYNTAX_ERROR: %s\n" "$2" >> "$SU_LOG"
}
'"$joined"
MOCK
chmod +x "$tmp/adb"
export SU_LOG="$tmp/su.log"
: > "$SU_LOG"
ADB="$tmp/adb" bash "$root/scripts/verify-integrity.sh" >/dev/null 2>&1 || true

if grep -q '^SYNTAX_ERROR' "$SU_LOG"; then
  echo 'Snippets reached su with broken quoting:' >&2
  grep '^SYNTAX_ERROR' "$SU_LOG" >&2
  exit 1
fi
if grep -q '^unexpected su args' "$SU_LOG"; then
  grep '^unexpected su args' "$SU_LOG" >&2; exit 1
fi
# Snippets must arrive verbatim: not expanded or unquoted by the outer shell.
for needle in 'tr -d "\""' 'getprop ro$n.build.fingerprint' "name='android_id'" 'alias=.?integrity'; do
  grep -Fq -- "$needle" "$SU_LOG" || { echo "Snippet altered before reaching su: $needle" >&2; exit 1; }
done
[[ "$(grep -c . "$SU_LOG")" -ge 15 ]] || { echo 'Too few root snippets captured' >&2; exit 1; }
echo 'verify-integrity.sh root snippets reach su intact.'
