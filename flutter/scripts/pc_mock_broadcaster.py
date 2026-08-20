#!/usr/bin/env python3
"""
pc_mock_broadcaster.py — 最小 PC 端 UDP 广播模拟器

用途：联调 Flutter App 的 UDP 发现链路，不依赖真实星助 PC 端。
严格按 doc/0.10/demand/04-mobile-lan-sync.md §3.1.1 协议广播。

用法：
  python3 pc_mock_broadcaster.py
  python3 pc_mock_broadcaster.py --port 9876 --name Hex-MacBook --project deepsky-2025

参数：
  --port        广播端口，默认 9876
  --name        机器名（UDP.name 字段），默认 Hex-MacBook
  --project     current_project，默认 deepsky-2025（设为空字符串表示 PC 无打开项目）
  --version     协议版本，默认 0.12
  --token       token 字段，默认 123456
  --interval    广播周期（秒），默认 2.0
  --packet-log  打印每个数据包的字节大小（默认开启）

退出：Ctrl-C
"""

import argparse
import datetime as _dt
import json
import socket
import sys
import time


def _ts() -> str:
    return _dt.datetime.now().strftime("%H:%M:%S.%f")[:-3]


def _log(tag: str, msg: str) -> None:
    sys.stdout.write(f"[{_ts()}][{tag}] {msg}\n")
    sys.stdout.flush()


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="StartTooler PC mock broadcaster")
    p.add_argument("--port", type=int, default=9876)
    p.add_argument("--name", default="Hex-MacBook")
    p.add_argument("--project", default="deepsky-2025")
    p.add_argument("--version", default="0.12")
    p.add_argument("--token", default="123456")
    p.add_argument("--interval", type=float, default=2.0)
    p.add_argument(
        "--packet-log",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="打印每个数据包的字节大小（默认开启，--no-packet-log 关闭）",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    payload = {
        "service": "starttooler",
        "version": args.version,
        "name": args.name,
        "port": 8765,
        "token": args.token,
        "current_project": args.project,
    }
    data = json.dumps(payload).encode("utf-8")

    _log("INIT", f"socket ready, broadcast=ON, SO_REUSEADDR=ON")
    _log(
        "INIT",
        f"target=255.255.255.255:{args.port} interval={args.interval}s "
        f"name={args.name!r} project={args.project!r}",
    )
    _log("INIT", f"payload size={len(data)}B json={payload!r}")

    seq = 0
    started = time.time()
    try:
        while True:
            seq += 1
            sent_bytes = sock.sendto(data, ("255.255.255.255", args.port))
            if args.packet_log:
                elapsed = time.time() - started
                _log(
                    "SEND",
                    f"#{seq} t={elapsed:6.2f}s sent={sent_bytes}B "
                    f"to 255.255.255.255:{args.port}",
                )
            time.sleep(args.interval)
    except KeyboardInterrupt:
        _log("STOP", f"interrupted, total sent={seq} packets")
    finally:
        try:
            sock.close()
        except OSError:
            pass


if __name__ == "__main__":
    main()