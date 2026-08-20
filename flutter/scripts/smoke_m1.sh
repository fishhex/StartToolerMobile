#!/usr/bin/env bash
#
# scripts/smoke_m1.sh
# M1 阶段冒烟脚本：仅依赖 nc + Python3，不依赖 Flutter 工具链。
#
# 用途：在 PC 上快速验证 UDP 发现链路（Android 真机需与 PC 在同 WiFi）。
# 用法：bash scripts/smoke_m1.sh

set -euo pipefail

PORT=9876
TIMEOUT=4
ANNOUNCE='{
        "service":"startooler-pc",
        "version":"0.12.0",
        "name":"Smoke-PC",
        "port":8765,
        "token":"123456",
        "currentProject":"smoke"
}'

echo "[smoke-m1] listening on UDP :$PORT for ${TIMEOUT}s ..."
echo "[smoke-m1] expect payload like:"
echo "$ANNOUNCE"
echo "---"

# Linux 用 timeout -s INT，macOS 用 gtimeout（若未安装会直接 n秒后退出）。
if command -v gtimeout >/dev/null 2>&1; then
  gtimeout "$TIMEOUT" nc -u -l "$PORT" || true
elif command -v timeout >/dev/null 2>&1; then
  timeout "$TIMEOUT" nc -u -l "$PORT" || true
else
  echo "[smoke-m1] nc + timeout unavailable; falling back to python3"
  python3 - <<PY
import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("0.0.0.0", $PORT))
s.settimeout($TIMEOUT)
try:
    while True:
        data, addr = s.recvfrom(4096)
        print(f"[from {addr}] {data.decode(errors='replace')}")
except socket.timeout:
    pass
PY
fi