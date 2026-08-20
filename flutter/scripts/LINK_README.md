# PC ↔ App 联调指南

本指南覆盖**真实 UDP 发现链路**的端到端联调：PC 端广播 → Android App 扫描 → 列出 PC。

---

## 前置条件

| 项 | 要求 |
|---|---|
| PC 与 Android 设备 | **同一 WiFi 子网**（路由器不开 AP 隔离） |
| 协议版本 | PC `version` >= `0.12`（App 端 `minSupportedMajor = 0`） |
| Android 设备 | API 21+，已开启 WiFi，**未开飞行模式** |
| 路由器 | 不开 AP 隔离 / 客户端隔离，且允许 PC 端 UDP 广播到手机（部分企业 WiFi 禁用 `255.255.255.255` directed broadcast，需要 PC 端发子网定向广播或 unicast fallback） |

---

## 步骤

### 1. 启动 PC 端

按真实 PC 服务 `StartTooler/Services/UploadServerService.cs` 启动后，每 2 秒向 `255.255.255.255:9876` 广播 announce JSON：

```json
{"service":"starttooler","version":"0.12","name":"<PC_NAME>","port":8765,"token":"123456","currentProject":"<project_name>"}
```

字段约定：

- `service` 必须为 `"starttooler"`（大小写敏感）
- `version` 主版本号必须 >= 0
- `token` 长度恰好为 6
- `name` 为 PC 端机器名（Environment.MachineName），用于 UI 展示 + 去重 key
- `currentProject` 为 PC 端当前打开的项目 basename；空字符串表示无项目

> 备注：本仓库历史上曾提供 Python mock 广播器（`pc_mock_broadcaster.py`）用于在无真实 PC 端时验证链路，已移除。开发请直接用真实 PC 端。

### 2. 启动 App

```bash
cd flutter
flutter run                       # 默认走 PC v0.12 真实 UDP
```

### 3. 观察日志

**App 端**（一键诊断）：

```bash
bash flutter/scripts/dump_logs.sh 8
```

会清空 logcat → 重启 App → 等 8 秒 → dump `StartToolerNative:V` + `flutter:V` + 错误日志。

或直接抓：

```bash
adb logcat | grep -E "UDP|MLOCK|ANNOUNCE|ADAPTER|VIEW|StartTooler"
```

预期看到（详细日志前缀）：

```
[StartTooler] discovery = LegacyUDP(:9876)
[UDP][#0002 t=12345] scan() called, window=0:00:05.000000 port=9876 ...
[MLOCK][#0003 t=12350] acquire() called, current state acquired=false platform=android
[MLOCK][#0004 t=12351] invoking native acquire via MethodChannel
StartToolerNative I  acquire() isHeld=true            ← Kotlin 端
[MLOCK][#0005 t=12360] native acquire returned=true, _acquired=true
[UDP][#0006 t=12361] ensureSocket: MulticastLock acquired=true
[UDP][#0007 t=12362] RawDatagramSocket.bind success on 0.0.0.0:9876
[UDP][#0008 t=12363] listening, will auto-close after 0:00:05.000000
[UDP-RAW][#0010 t=13400] recv 142B from <PC_IP>:<ephemeral_port> hex=7b 22 73 65 72 ...
[UDP-RAW][#0011 t=13401] decoded text: {"service":"starttooler",...}
[ANNOUNCE][#0012 t=13401] parsed ip=<PC_IP>:8765 name="<PC_NAME>" project=<proj> version=0.12 compatible=true
[UDP][#0013 t=13401] new device name="<PC_NAME>" addr=<PC_IP>:8765 added (key=<PC_NAME>|8765|<PC_IP>)
[ADAPTER][#0014 t=13401] emit PC name="<PC_NAME>" addr=<PC_IP>:8765 currentProject=<proj>
[VIEW][#0015 t=13401] onDiscovered name="<PC_NAME>" ip=<PC_IP> isNew=true
[UDP][#0020 t=17363] window expired, seen=1 devices=[<PC_NAME>|8765|<PC_IP>]
```

### 日志标签对照表

| Tag / 前缀 | 含义 | 典型内容 |
|---|---|---|
| `StartToolerNative` | Kotlin 端 | `MainActivity.onCreate / configureFlutterEngine / acquire() / release()` |
| `[StartTooler]` | Dart 入口 | `discovery = LegacyUDP(:9876)` |
| `[MLOCK]` | MulticastLock 桥接 | acquire / release 调用与结果 |
| `[UDP]` | socket 生命周期 | bind / listen / 关闭 / 设备新增 |
| `[UDP-RAW]` | 原始字节流 | 每个收到的数据包（hex + UTF-8） |
| `[ANNOUNCE]` | 协议解析 | 解析成功 / 各字段校验失败原因 |
| `[ADAPTER]` | 适配层 | UdpAnnounce → PC 转换 |
| `[VIEW]` | UI 层 | 收到 PC / 点击 / 手动输入 |

如果 5 秒内没有任何 `[UDP-RAW]` 记录，按下面的"故障排查"检查。

**App 界面**：

- 启动页 1.5s → 跳转扫描页
- 5s 倒计时环形进度
- 列表出现至少一台 PC（带 `name` + `IP:PORT`）
- 点选进入 Token 输入页

---

## 故障排查

### 1. socket 启动报错：UDP 端口占用

```
[UDP] socket bind failed: SocketException: ...
```

→ 检查本机是否有进程占用 9876 端口（一般不会出现）：

```bash
adb shell cat /proc/net/udp | awk '$2 ~ /:02694/{print}'
```

### 2. logcat 看到 socket bound 但 5 秒内无 announce

按顺序检查：

| 检查项 | 命令 / 方法 |
|---|---|
| PC 端 StartTooler 服务在跑？ | `ps aux \| grep -E 'StartTooler\|UploadServer'` |
| PC 与 Android 同 WiFi？ | Android 上 PING PC IP：`adb shell ping <PC_IP>` |
| 路由器开 AP 隔离？ | 换网络或启用 App 内「手动输入 IP」 |
| 路由器禁用 `255.255.255.255` 广播？ | 改 PC 端发子网定向广播（如 `192.168.x.255`）或 unicast 到手机 IP |
| PC 端 macOS 防火墙拦截？ | 系统设置→网络→防火墙→允许 StartTooler |
| Android 9+ 收不到广播？ | logcat 看 `StartToolerNative` 是否有 `acquire() isHeld=true`；`adb shell dumpsys wifi` 看 lock 是否持有 |

### 3. Announce 收到但 App 列表为空

- 检查 PC 端 `version` 字段。`0.x.y` 必须 major == 0。
- 检查 `service == "starttooler"`（大小写敏感）。
- 检查 `token` 长度恰好为 6。

### 4. logcat 完全没 `[UDP]` 日志

- 确认走的是真实 UDP：`[StartTooler] discovery = LegacyUDP(:9876)`
- 检查 manifest 4 条权限：`adb shell dumpsys package com.example.starttooler_mobile | grep permission`

---

## 当前联调范围

| 已验证 | 状态 |
|---|---|
| UDP socket 监听 `:9876` | ✅ |
| `service=starttooler` 过滤 | ✅ |
| `version` 主版本号校验 | ✅ |
| 多 PC 去重（`name\|port\|ip` 三元组）+ 排序 | ✅ |
| 5s 扫描窗口 | ✅ |
| 手动输入 IP + Port + Token 兜底 | ✅ |
| MulticastLock 持有 / 释放 | ✅ |
| **真实 `/health` HTTP 调用** | ❌ Mock |
| **真实 `/projects` HTTP 调用** | ❌ Mock |
| **真实 multipart 上传** | ❌ Mock |
| **持久化（重启后自动验证）** | ❌ 未实现 |

本轮仅验证"UDP 收到广播"。HTTP 闭环在 M2 之后联调。