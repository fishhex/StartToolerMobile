#!/usr/bin/env python3
"""
pc_mock_v1_broadcaster.py — PC 端 v1.0 协议 mock

响应 doc/app/02-pc-udp-protocol.md：
  - 监听 UDP 9001
  - 收到 discover_req → 单播 discover_resp（含回传 nonce）
  - 收到 pair_req     → 校验 code + 单播 pair_ack（含 token）
  - 收到 heartbeat    → 单播 heartbeat_ack

用法：
  python3 pc_mock_v1_broadcaster.py
  python3 pc_mock_v1_broadcaster.py --port 9001 --pc-id PC-AB12CD34 \
      --pc-name "Hex-MacBook" --pair-code 123456

退出：Ctrl-C
"""

from __future__ import annotations

import argparse
import base64
import datetime as _dt
import json
import os
import random
import socket
import sys
import threading
import time
from typing import Optional


def _ts() -> str:
    return _dt.datetime.now().strftime("%H:%M:%S.%f")[:-3]


def _log(tag: str, msg: str) -> None:
    sys.stdout.write(f"[{_ts()}][{tag}] {msg}\n")
    sys.stdout.flush()


def now_ms() -> int:
    return int(time.time() * 1000)


def new_uuid() -> str:
    return os.urandom(16).hex()  # 简化版：32 hex；足够做 msgId


def b64u(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


class V1PCMock:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.sock.bind(("0.0.0.0", args.port))
        self.sock.settimeout(0.5)

        # 生成 PC 端"持久"密钥（mock 简化：每次启动随机生成）
        self._pc_priv = os.urandom(32)
        self._pc_pub = b64u(self._pc_priv)  # 真实场景用 X25519，这里仅占位

        self._known_devices: dict[str, str] = {}  # deviceId -> token
        self._token_seq = 0

        # §4 模拟错误码（联调时打开）：--simulate-error unsupported_ver
        self._simulate_error: Optional[str] = args.simulate_error

    # ---- helpers ----

    def _local_ip(self) -> str:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"
        finally:
            s.close()

    def _issue_token(self) -> str:
        self._token_seq += 1
        return b64u(os.urandom(48))

    def _send(self, addr: tuple[str, int], payload: dict) -> None:
        data = json.dumps(payload).encode("utf-8")
        if len(data) > 1400:
            _log("WARN", f"packet too large: {len(data)}B")
        try:
            self.sock.sendto(data, addr)
        except OSError as e:
            _log("ERR", f"send to {addr} failed: {e}")

    # ---- handlers ----

    def on_discover_req(self, pkt: dict, addr: tuple[str, int]) -> None:
        nonce = pkt.get("nonce", "")
        msg_id = pkt.get("msgId", new_uuid())
        resp = {
            "type": "discover_resp",
            "msgId": msg_id,
            "ts": now_ms(),
            "pcId": self.args.pc_id,
            "name": self.args.pc_name,
            "ip": self._local_ip(),
            "port": 9000,
            "ver": "1.0.0",
            "cap": ["file"],
            "nonce": nonce,
            "pubKey": self._pc_pub,
            "pairState": "unpaired",
        }
        if self._simulate_error:
            resp["error"] = self._simulate_error
        self._send(addr, resp)
        _log(
            "DISCOVER_RESP",
            f"→ {addr} pcId={self.args.pc_id} nonce8={nonce[:8]}..."
            + (f" error={self._simulate_error}" if self._simulate_error else ""),
        )

    def on_pair_req(self, pkt: dict, addr: tuple[str, int]) -> None:
        code = pkt.get("code", "")
        device_id = pkt.get("deviceId", "")
        msg_id = pkt.get("msgId", new_uuid())

        if code != self.args.pair_code:
            self._send(addr, {
                "type": "pair_reject",
                "msgId": msg_id,
                "ts": now_ms(),
                "deviceId": device_id,
                "reason": "code_invalid",
            })
            _log("PAIR_REJECT", f"← {addr} reason=code_invalid")
            return

        token = self._issue_token()
        self._known_devices[device_id] = token
        self._send(addr, {
            "type": "pair_ack",
            "msgId": msg_id,
            "ts": now_ms(),
            "deviceId": device_id,
            "token": token,
            "expiresIn": 2592000,
        })
        _log("PAIR_ACK", f"→ {addr} deviceId={device_id[:12]}...")

    def on_heartbeat(self, pkt: dict, addr: tuple[str, int]) -> None:
        device_id = pkt.get("deviceId", "")
        msg_id = pkt.get("msgId", new_uuid())
        self._send(addr, {
            "type": "heartbeat_ack",
            "msgId": msg_id,
            "ts": now_ms(),
            "deviceId": device_id,
        })
        _log("HEARTBEAT_ACK", f"→ {addr} deviceId={device_id[:12]}...")

    # ---- main loop ----

    def serve(self) -> None:
        _log("INIT", f"listening 0.0.0.0:{self.args.port}")
        _log(
            "INIT",
            f"pcId={self.args.pc_id} name={self.args.pc_name!r} "
            f"pairCode={self.args.pair_code} pubKey8={self._pc_pub[:8]}...",
        )
        try:
            while True:
                try:
                    data, addr = self.sock.recvfrom(4096)
                except socket.timeout:
                    continue
                except OSError as e:
                    _log("ERR", f"recvfrom: {e}")
                    break
                try:
                    pkt = json.loads(data.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError) as e:
                    _log("WARN", f"invalid packet from {addr}: {e}")
                    continue
                t = pkt.get("type", "")
                if t == "discover_req":
                    self.on_discover_req(pkt, addr)
                elif t == "pair_req":
                    self.on_pair_req(pkt, addr)
                elif t == "heartbeat":
                    self.on_heartbeat(pkt, addr)
                else:
                    _log("WARN", f"unknown type={t!r} from {addr}")
        except KeyboardInterrupt:
            _log("STOP", "interrupted")
        finally:
            try:
                self.sock.close()
            except OSError:
                pass


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="StartTooler PC v1.0 mock")
    p.add_argument("--port", type=int, default=9001)
    p.add_argument("--pc-id", default="PC-AB12CD34")
    p.add_argument("--pc-name", default="Hex-MacBook")
    p.add_argument("--pair-code", default="123456")
    p.add_argument(
        "--simulate-error",
        choices=["invalid_msg", "unsupported_ver", "rate_limited", "internal_error"],
        help="§4 PC 端错误码模拟（联调 App 错误处理时用）",
    )
    return p.parse_args()


def main() -> None:
    args = parse_args()
    mock = V1PCMock(args)
    mock.serve()


if __name__ == "__main__":
    main()