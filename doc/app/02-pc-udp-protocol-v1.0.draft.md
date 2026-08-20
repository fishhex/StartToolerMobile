# PC UDP 发现协议 v1.0（草案）

> ⚠️ **本文档为草案（DRAFT）**——基于 Flutter 端 [discover_service_v1.dart](../../flutter/lib/features/discovery/v1/) 实现反推，**PC 端尚未确认**。内容需 PC 端 owner 联调 OK 后再正式落库、覆盖 `02-pc-udp-protocol.md`。
>
> 关联实现：
> - App 端：[discover_service_v1.dart](../../flutter/lib/features/discovery/v1/discover_service_v1.dart)、[protocol_v1.dart](../../flutter/lib/features/discovery/v1/protocol_v1.dart)、[udp_transport.dart](../../flutter/lib/features/discovery/v1/udp_transport.dart)、[nonce_cache.dart](../../flutter/lib/features/discovery/v1/nonce_cache.dart)、[app_identity.dart](../../flutter/lib/features/discovery/v1/app_identity.dart)
> - PC 端 mock：[pc_mock_v1_broadcaster.py](../../flutter/scripts/pc_mock_v1_broadcaster.py)
> - 旧文档：[02-pc-udp-protocol.md](file:///Users/hex/code/StartToolerMobile/doc/app/02-pc-udp-protocol.md)（v0.12 / 9876 / 6 位数字 Token，本文第 §九节给出迁移对照）

## 〇、v1.0 vs v0.12 一句话

| 维度 | v0.12（旧） | v1.0（本文） |
|---|---|---|
| 通信模式 | PC 单向广播 + App 被动监听 | **双向**：App 主动发 `discover_req`，PC 单播 `discover_resp` |
| 端口 | 9876 | **9001**（UDP） + 9000（TCP 业务） |
| 加密 | **无**（明文 6 位数字 Token） | **X25519 公钥** + 6 位 `pair_code` + 派生 token |
| 防重放 | 无 | **16 字节 nonce**（base64url）+ ±5min 时间戳窗口 |
| 配对 | App 用户手输 6 位 Token | App 用户手输 6 位 **pair_code**，PC 即时签发 token |
| 在线判定 | PC → App 周期性广播，App 监听超时 | App → PC **5s 周期 heartbeat** + 回 ack |
| 发现方式 | UDP 单点广播 | **广播 255.255.255.255 + 组播 224.0.0.251 双通道** |

---

## 一、协议基本信息

| 项 | 值 | 代码位置 |
|---|---|---|
| 协议 | UDP（IPv4） | `RawDatagramSocket` |
| 端口 | **9001**（control） / **9000**（business，未来） | `ProtocolV1Const.udpPort = 9001`、`tcpBusinessPort = 9000` |
| 目标地址 | App→PC：`255.255.255.255` 广播 + `224.0.0.251` 组播；PC→App：来源 IP 单播 | `udp_transport.dart#L161-L171` |
| 编码 | UTF-8 JSON | `utf8.encode` |
| 命名 | camelCase | 见各 DTO `toJson` |
| 单包大小限制 | ≤ **1400 B**（避免分片） | `ProtocolV1Const.maxDatagramBytes = 1400` |
| 心跳周期 | **5000 ms** | `Duration(seconds: 5)` |
| 探测周期 | **1500 ms**（`discover_req` 周期） | `ProtocolV1Const.probeIntervalMs = 1500` |
| 时间戳 | Unix 毫秒（int64） | `DateTime.now().millisecondsSinceEpoch` |
| 时间漂移容忍 | **±5 min**（`ts` 字段落此范围收包） | `ProtocolV1Const.tsSkewMs = 5 * 60 * 1000` |
| Nonce 大小 | **16 字节**（base64url 编码） | `ProtocolV1Const.nonceBytes = 16` |
| Nonce 缓存 TTL | **3000 ms** | `ProtocolV1Const.nonceCacheTtlMs = 3000` |
| 设备 ID | 16 字节随机 base64url（App 生命周期内持续） | `AppIdentity.deviceId` |
| 公钥算法 | **X25519**（PC 端持久私钥 + 公钥） | `DiscoverResp.pubKey` 字段 |

---

## 二、消息类型清单

| 类型 | 方向 | 用途 |
|---|---|---|
| `discover_req` | App → PC | App 主动探测，要求 PC 回应 |
| `discover_resp` | PC → App | PC 响应，包含 PC 身份 + 公钥 + 配对状态 |
| `pair_req` | App → PC | App 提交 pair_code + 用 PC 公钥加密的 deviceKey |
| `pair_ack` | PC → App | PC 接受配对，回签 token |
| `pair_reject` | PC → App | PC 拒绝配对（reason 枚举） |
| `heartbeat` | App → PC | App 定期心跳，证明在线 |
| `heartbeat_ack` | PC → App | PC 接收心跳的回包 |

所有消息共用骨架（[protocol_v1.dart#L91-L108](file:///Users/hex/code/StartToolerMobile/flutter/lib/features/discovery/v1/protocol_v1.dart#L91-L108)）：

```json
{
  "type": "<type>",
  "msgId": "<uuidv4-like>",
  "ts": 1700000000000
}
```

---

## 三、消息 DTO 详细定义

### 3.1 `discover_req`（App → PC）

```json
{
  "type": "discover_req",
  "msgId": "550e8400-e29b-41d4-a716-446655440000",
  "ts": 1700000000000,
  "appId": "com.starttooler.mobile",
  "appVer": "0.1.0",
  "nonce": "kZ6k8nQH5W_rKfZ3YgZx7w",
  "caps": ["file"]
}
```

| 字段 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `type` | string | ✅ | 固定 `"discover_req"` |
| `msgId` | string | ✅ | UUIDv4-like（hex 16B） |
| `ts` | int | ✅ | Unix 毫秒；接收方校验 ±5min |
| `appId` | string | ✅ | 包名，固定 `"com.starttooler.mobile"` |
| `appVer` | string | ❌ | App 版本（如 `"0.1.0"`） |
| `nonce` | string | ✅ | 16B 随机 base64url；PC 响应必须回传相同 nonce |
| `caps` | string[] | ❌ | App 能力声明（当前固定 `["file"]`） |

### 3.2 `discover_resp`（PC → App）

```json
{
  "type": "discover_resp",
  "msgId": "8b5c1e10-4a3f-4d29-bcaa-2a1f5c9e1d11",
  "ts": 1700000000100,
  "pcId": "PC-AB12CD34",
  "name": "Hex-MacBook",
  "ip": "192.168.1.10",
  "port": 9000,
  "ver": "1.0.0",
  "cap": ["file"],
  "nonce": "kZ6k8nQH5W_rKfZ3YgZx7w",
  "pubKey": "BmFiYzEyMzQ1Njc4OWFiY2RlZg",
  "pairState": "unpaired",
  "error": null
}
```

| 字段 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `type` | string | ✅ | 固定 `"discover_resp"` |
| `msgId` | string | ✅ | 必须回传触发本次响应的 `discover_req.msgId` |
| `ts` | string | ✅ | Unix 毫秒；App 校验 ±5min 漂移 |
| `pcId` | string | ✅ | PC 唯一稳定 ID（**不随 IP 变化**） |
| `name` | string | ✅ | PC 显示名（`Environment.MachineName`） |
| `ip` | string | ❌ | PC 主动填的 IP；App 校验与回包 IP 是否一致 |
| `port` | int | ✅ | PC 业务端口（当前 9000 占位） |
| `ver` | string | ✅ | PC 协议版本（如 `"1.0.0"`） |
| `cap` | string[] | ✅ | PC 能力声明（如 `["file"]`） |
| `nonce` | string | ✅ | **必须回传 discover_req.nonce**（防重放核心） |
| `pubKey` | string | ✅ | PC 端 X25519 公钥的 base64url 编码 |
| `pairState` | string | ✅ | `"paired"` 或 `"unpaired"` |
| `error` | string | ❌ | 错误码（见 §4）；如有则 App 不入库 |

> **校验规则**（[discover_service_v1.dart#L154-L206](file:///Users/hex/code/StartToolerMobile/flutter/lib/features/discovery/v1/discover_service_v1.dart#L154-L206)）：
> 1. `ts` 必须在 `now ± 5min` 内；
> 2. `resp.ip` 非空时必须等于 UDP 包源 IP（防 IP 伪造）；
> 3. `nonce` 必须命中 App 端 nonce 缓存（命中后立即消费，防重放）；
> 4. 任意一项校验失败 → 丢弃。

### 3.3 `pair_req`（App → PC）

```json
{
  "type": "pair_req",
  "msgId": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "ts": 1700000000200,
  "pcId": "PC-AB12CD34",
  "deviceId": "Y2QzZjE4ZWMtMjBlYS00MzdlLWJiZmItMTIzNA",
  "code": "123456",
  "encryptedKey": "BASE64URL_OPAQUE_BLOB"
}
```

| 字段 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `type` | string | ✅ | 固定 `"pair_req"` |
| `msgId` | string | ✅ | UUIDv4 |
| `ts` | int | ✅ | Unix 毫秒 |
| `pcId` | string | ✅ | 目标 PC ID |
| `deviceId` | string | ✅ | App 自身 ID（16B base64url） |
| `code` | string | ✅ | **6 位数字** pair_code（用户在 PC 端查看） |
| `encryptedKey` | string | ✅ | App 用 PC `pubKey`（X25519 ECDH）加密的 deviceKey |

> **加密边界**：本文档不定义 `encryptedKey` 内部格式（属于密钥派生协议）；
> 约定「PC 端必须能解密出原始 deviceKey 并用于后续会话派生」即可。
> App 端当前未实现加密逻辑（mock），正式实现时由 PC 端 owner 协商。

### 3.4 `pair_ack`（PC → App）

```json
{
  "type": "pair_ack",
  "msgId": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "ts": 1700000000300,
  "deviceId": "Y2QzZjE4ZWMtMjBlYS00MzdlLWJiZmItMTIzNA",
  "token": "<long-lived token>",
  "expiresIn": 2592000
}
```

| 字段 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `type` | string | ✅ | 固定 `"pair_ack"` |
| `msgId` | string | ✅ | 回传触发 `pair_req.msgId` |
| `ts` | int | ✅ | Unix 毫秒 |
| `deviceId` | string | ✅ | 给的是哪台 App 设备 |
| `token` | string | ✅ | 长生命周期 token（**非明文 6 位数字**） |
| `expiresIn` | int | ❌ | 过期秒数（默认 2592000 = 30 天） |

> **ACK 路由**：App 端在 `pair()` 调用里临时 register listener 等待
> `PairAck.deviceId == AppIdentity.deviceId` 的包；
> 收到即 `completer.complete(ack)`，超时 3s 抛 `AppError(unknown)`。

### 3.5 `pair_reject`（PC → App）

```json
{
  "type": "pair_reject",
  "msgId": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "ts": 1700000000300,
  "deviceId": "Y2QzZjE4ZWMtMjBlYS00MzdlLWJiZmItMTIzNA",
  "reason": "code_invalid"
}
```

| `reason` | 含义 | App 端映射 |
|---|---|---|
| `code_expired` | pair_code 已过期 | `AppErrorKind.unknown` |
| `code_invalid` | pair_code 错误 | `AppErrorKind.invalidToken` |
| `device_blocked` | PC 端黑名单 | `AppErrorKind.serverError` |

### 3.6 `heartbeat`（App → PC）

```json
{
  "type": "heartbeat",
  "msgId": "bb21e8a3-1f4c-4d99-9a3e-7d8b2f1c5e22",
  "ts": 1700000005000,
  "pcId": "PC-AB12CD34",
  "deviceId": "Y2QzZjE4ZWMtMjBlYS00MzdlLWJiZmItMTIzNA"
}
```

| 字段 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `type` | string | ✅ | 固定 `"heartbeat"` |
| `msgId` | string | ✅ | UUIDv4 |
| `ts` | int | ✅ | Unix 毫秒 |
| `pcId` | string | ✅ | 目标 PC |
| `deviceId` | string | ✅ | App 设备 ID |

### 3.7 `heartbeat_ack`（PC → App）

```json
{
  "type": "heartbeat_ack",
  "msgId": "bb21e8a3-1f4c-4d99-9a3e-7d8b2f1c5e22",
  "ts": 1700000005100,
  "deviceId": "Y2QzZjE4ZWMtMjBlYS00MzdlLWJiZmItMTIzNA"
}
```

| 字段 | 类型 | 必填 | 含义 |
|---|---|---|---|
| `type` | string | ✅ | 固定 `"heartbeat_ack"` |
| `msgId` | string | ✅ | 回传 `heartbeat.msgId` |
| `ts` | int | ✅ | Unix 毫秒 |
| `deviceId` | string | ✅ | App 设备 ID |

> App 当前只记录 `heartbeat_ack` 收到事件（[discover_service_v1.dart#L147-L148](file:///Users/hex/code/StartToolerMobile/flutter/lib/features/discovery/v1/discover_service_v1.dart#L147-L148)），
> 不基于 ack 做在线判定——**在线判定仍然依赖 nonce 缓存 + 周期探测收到的 `discover_resp`**。
> 实际心跳仅用于"PC 侧知道 App 在线"。

---

## 四、错误码（PC → App）

`discover_resp.error` 字段：

| code | 触发 | App 端行为 |
|---|---|---|
| `invalid_msg` | 协议解析失败 | 丢弃，不展示 |
| `unsupported_ver` | App 版本过低 | `AppErrorKind.unsupported` → 提示升级 |
| `rate_limited` | 探测频率超限 | `AppErrorKind.serverError` → 退避重试 |
| `internal_error` | PC 端异常 | `AppErrorKind.serverError` → 退避重试 |

> 不在白名单的 error code → 整体 `discover_resp` 视为无效（[protocol_v1.dart#L234-L241](file:///Users/hex/code/StartToolerMobile/flutter/lib/features/discovery/v1/protocol_v1.dart#L234-L241)）。

---

## 五、典型时序

### 5.1 发现（discover_req ↔ discover_resp）

```
App (Mobile)                              PC (StartTooler)
  |  进程启动 / 扫描触发                       |
  |  RawDatagramSocket.bind 0.0.0.0:9001     |
  |  MulticastLockChannel.acquire()          |
  |  ProbeTimer (1.5s)                       |
  |  ── UDP 255.255.255.255:9001 ───────────>|
  |  ── UDP 224.0.0.251:9001 ───────────────>|
  |  discover_req {nonce=N, ts, ...}         |
  |                                          | 解析 → 通过 → 准备 response
  | <── UDP unicast src-ip:9001 ─────────────|
  | discover_resp {nonce=N, pcId,            |
  |   pubKey, pairState, ...}                |
  | App 校验 nonce/ts/ip                    |
  | App 入库 _devices[pcId]                 |
  | ProbeTimer (1.5s) ↻                     |
  |  5s 扫描窗口结束 → scan() returns        |
```

### 5.2 配对（pair_req → pair_ack / pair_reject）

```
App                                   PC
  |  用户在 PC 端查看 pair_code     |
  |  用户在 App 端输入 6 位码      |
  |  EXP: 派生 deviceKey           |
  |  EXP: PC.pubKey ECDH → encKey  |
  |  ── UDP unicast pcIp:9001 ───>|
  |  pair_req {pcId, code,        |
  |    encryptedKey, deviceId}    |
  |                                | 校验 code → 成功
  |                                | 持久化 deviceId → token
  | <── UDP unicast ───────────────|
  | pair_ack {deviceId, token,    |
  |   expiresIn}                  |
  | App 持久化 token（Keychain）  |
  | 启动 startHeartbeat (5s)      |
```

### 5.3 心跳（heartbeat → heartbeat_ack）

```
App                                  PC
  |  Timer 5s                       |
  |  ── UDP unicast pcIp:9001 ─────>|
  |  heartbeat {pcId, deviceId}     |
  | <── UDP unicast ────────────────|
  | heartbeat_ack {deviceId}        |
  |  仅记录日志，不做在线判定       |
```

---

## 六、安全边界

| 威胁 | v1.0 防御 | 残余风险 |
|---|---|---|
| LAN 嗅探 | X25519 公钥 + 加密 deviceKey | 公开 `pubKey` / `pcId` 仍可见 |
| Discover 重放 | **16 字节 nonce + ±5min ts 双校验** | 5min 内重放同样 nonce 会被发现；超 5min 被 ts 拦截 |
| Pair Code 重放 | `code` 由 PC 端refresh 一次验证一次 | 用户输入错误码成功率 1/10⁶ |
| IP 伪造 | `discover_resp.ip` 必须与回包源 IP 一致 | App 端校验缺陷会被绕过 |
| 心跳泛洪 | `rate_limited` 错误码 | App 端背压策略可补 |
| 跨子网 | **不支持**（UDP 广播/组播不跨路由） | 走公网 relay |

---

## 七、App 端实现要点（与 v1.0 协议对齐）

- **端口**：App 绑 `0.0.0.0:9001`（`reuseAddress: true`），
  不要同时监听 9876，避免协议混用。
- **多通道发**：`broadcast()` 同时打 `255.255.255.255` 与 `224.0.0.251`（UDP send 各一次）。
- **平台注意**：
  - iOS：`Info.plist` 仍需 `NSLocalNetworkUsageDescription`（KB `API-03 §四.2`）；
  - Android：`DatagramSocket` 默认即可收广播，但发广播要 `MulticastLock`（v1.0 走 `MulticastLockChannel` 桥接）。
- **扫描窗口**：5s（`V1DiscoveryAdapter.scan` 第二段 `Future.delayed(5s)`）。
- **去重 key**：`pcId`（**不**用 `name + port + ip`——v1.0 的稳定 ID 已挪到 pcId）。
- **设备 ID 持久化**：当前 `AppIdentity._deviceId` 进程级缓存；
  真正的持久化（Keychain / EncryptedSharedPreferences）需后续 patch。
- **pair_code 输入**：当前在 [discover_service_v1.dart `pair()`](file:///Users/hex/code/StartToolerMobile/flutter/lib/features/discovery/v1/discover_service_v1.dart#L226-L285) 由调用方传入；
  UI 入口（pair_code 输入页 / 错误展示）尚未实现。

---

## 八、调试与自测

### 8.1 启动 PC mock

```bash
python3 flutter/scripts/pc_mock_v1_broadcaster.py \
  --port 9001 --pc-id PC-AB12CD34 \
  --pc-name "Hex-MacBook" --pair-code 123456

# 错误码模拟：
python3 flutter/scripts/pc_mock_v1_broadcaster.py --simulate-error unsupported_ver
```

### 8.2 抓包

```bash
sudo tcpdump -i en0 -n udp port 9001 -A
```

### 8.3 单元测试缺项

- [ ] `protocol_v1.dart` 各 DTO 的 `tryParse` happy path / 字段缺失 / 类型错
- [ ] `nonce_cache.dart` 过期 / LRU 截断 / 重放拒绝
- [ ] `isFreshTimestamp` 边界值（now ± 5min ± 1ms）
- [ ] `discover_service_v1.dart` 收包校验四问：service 字段 / ts 漂移 / IP 匹配 / nonce 命中

---

## 九、与 v0.12 协议迁移对照

| 移动端层 | v0.12 调用路径 | v1.0 调用路径 |
|---|---|---|
| 入口 | `main.dart:37` `legacy` → `UdpDiscoveryAdapter` | `main.dart:40` `v1`（默认）→ `V1DiscoveryAdapter` |
| 协议端口 | 9876 | 9001 |
| 协议模型 | `UdpAnnounce`（announce 包） | `DiscoverResp` / `PairAck` / `Heartbeat` |
| 鉴权 | 6 位数字 Token 从广播取 | `pair_code` 6 位 + token 从 `pair_ack` 取 |
| 公钥 | 无 | `DiscoverResp.pubKey` |
| 防重放 | 无 | nonce + ts |
| 在线判定 | 监听广播超时 | `discover_resp` 周期 + 心跳（仅 PC 侧可见） |
| PC 端实现 | 已存在（[UploadServerService.cs](../../../../StartTooler/Services/UploadServerService.cs) 头条路径） | **未确认**（需 PC 端 owner 联调） |

---

## 十、待 PC 端确认事项（Open Questions）

下列问题文档未明，需要 PC 端 owner 拍板：

1. **PC 端 `pcId` 生成策略**：是否持久化？是否跨重启稳定？
2. **PC 端 X25519 私钥存储**：是否落盘？落哪个路径？首次启动生成还是预设？
3. **`pair_code` 刷新周期**：多久刷新一次？是否支持手动刷新？
4. **`encryptedKey` 内部格式**：X25519 ECDH 后是否直接用 `crypto_secretbox`（NaCl / libsodium）？nonce 策略？
5. **`token` 字段格式**：长度？编码？是否与业务端口 9000 联动？
6. **业务端口 9000 的具体路由**：与 v0.12 的 `/api/v1/*` 完全一致？还是要另外设计？
7. **错误码枚举**：本文档给的 4 个是否完整？是否需要加 `app_blocked` / `pair_rate_limited` 等？
8. **PC 端 `discover_resp` 发送触发**：仅在收到 `discover_req` 时回？还是要周期性广播作为冗余？
9. **PC 端 `heartbeat` 失败处理**：连续 N 次未收到 → 是否主动给 App 推 `pair_reject`？
10. **旧 v0.12 协议是否共存**：PC 端是单协议（v1.0 only）还是双协议（两条 UDP 链路）？

---

## 十一、变更记录

| 日期 | 版本 | 变更人 | 内容 |
|---|---|---|---|
| 2026-08-20 | v1.0 DRAFT | - | 初稿，基于 Flutter 端 discovery/v1/ 实现反推；待 PC 端 owner 联调确认 |
