#!/usr/bin/env bash
# scripts/dump_logs.sh
# 一键 dump App 启动后的所有相关日志（Kotlin + Dart + 错误）
#
# 用法：
#   bash scripts/dump_logs.sh
#   bash scripts/dump_logs.sh 8       # 指定等待秒数（默认 6）

set -euo pipefail

WAIT="${1:-6}"
PKG=com.example.starttooler_mobile

# adb 不在 PATH 时尝试常见路径
ADB="${ADB:-$(command -v adb || true)}"
if [[ -z "$ADB" ]]; then
  for p in \
    "$HOME/Library/Android/sdk/platform-tools/adb" \
    "/opt/homebrew/bin/adb" \
    "/usr/local/bin/adb"
  do
    [[ -x "$p" ]] && ADB="$p" && break
  done
fi
if [[ -z "$ADB" ]]; then
  echo "ERROR: adb not found. Install Android SDK platform-tools or set ADB env." >&2
  exit 1
fi
echo ">>> using adb: $ADB"
echo ">>> devices:"
$ADB devices

echo "=== 1) clear logcat ==="
$ADB logcat -c

echo "=== 2) force-stop + start $PKG ==="
$ADB shell am force-stop "$PKG"
sleep 1
$ADB shell am start -n "$PKG/.MainActivity"

echo "=== 3) waiting ${WAIT}s for scan window ==="
sleep "$WAIT"

echo "=== 4) dump logs (Kotlin + Dart + errors) ==="
$ADB logcat -d -s 'StartToolerNative:V' 'flutter:V' 'AndroidRuntime:E' '*:F' \
  | tail -200