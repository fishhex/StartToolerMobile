# S05 · 移动端 App 端到端规划（Flutter 单端，对齐 PC v0.12）

> **状态**：从头重写的实施规划与技术规格（v0.1）
> **取代**：旧 05-mobile-app.md（iOS Swift + Android Kotlin 双原生方案，已作废）
> **关联需求**：[demand/README.md](../demand/README.md) 全部 6 篇需求稿（D01-D06）
> **关联协议**：[02-pc-udp-protocol.md](../../app/02-pc-udp-protocol.md) v0.12 权威
> **PC 端 spec**：[04-mobile-lan-sync.md](04-mobile-lan-sync.md)

---

## 〇、规划一句话

**用 Flutter 一份代码实现 iOS / macOS / Android 三端；按 PC v0.12 已实现的单向 UDP 广播（9876/2s）+ 明文 HTTP（health/projects/projects/{name}/upload）三件套对接；先把"零配置发现 → 输入 token → 选项目 → 批量上传"主链路打通，再补平台权限 / 错误兜底 / 持久化。**

---

## 一、范围与边界

### 1.1 包含

| 模块 | 说明 |
|---|---|
| UDP 监听 9876 | 单向，PC 端广播 → App 端解析（D01） |
| HTTP `GET /api/v1/health` | 首连可达性验证（D02 §3.1.1） |
| HTTP `GET /api/v1/projects` | 拉项目列表（D02 §3.1.2） |
| HTTP `POST /api/v1/projects/{name}/upload` | 批量 multipart 上传（D02 §3.1.3） |
| Token 鉴权状态机 | 广播为权威源 + 持久化 + 401 重试（D03） |
| 在线判定 + 后台回前台 | 6 s 离线阈值 + 重置计时（D04） |
| iOS / macOS / Android 平台权限 | Info.plist / ATS / `network_security_config`（D05） |
| 错误分层 + i18n | 网络层 / HTTP 状态 / 业务失败 + 中英文文案（D06） |
| 持久化 | Keychain (iOS/macOS) / EncryptedSharedPreferences (Android)（D03 §3.4） |

### 1.2 不包含

| 模块 | 理由 |
|---|---|
| PC 端代码 | 见 [04-mobile-lan-sync.md](04-mobile-lan-sync.md)，本 spec 不动 |
| X25519 / nonce / pair_code / mDNS | PC v0.12 未实现；v1.0 草案 [02-pc-udp-protocol-v1.0.draft.md](../../app/02-pc-udp-protocol-v1.0.draft.md) 不在 v0.12 范围内 |
| 后台持续 UDP 监听 | iOS / Android 系统限制（详见 D01 §7 + D05 §6） |
| HTTPS / 自签证书 | 家庭 LAN 风险可控（D06 §6） |
| 公网同步 / OSS | D02 范围，不在本 spec |
| AI / 修图 / 账号体系 | 不在 [demand/README.md](../demand/README.md) §一范围 |

### 1.3 与现状的关系

| 维度 | 现状 | 本 spec 走向 |
|---|---|---|
| 实现栈 | Flutter 3.19+（`flutter/lib/`），已存在 mock + 部分 UDP | 继续 Flutter；mock 替换为真实实现 |
| 协议版本 | 仓库并存 v0.12（9876）+ v1.0 草案（9001）；main 默认 v1 | **本 spec 锁定 v0.12**（与 demand 对齐）；v1.0 草案封存为备份实验分支 |
| 跨端策略 | 仓库已选 Flutter，弃用旧 iOS Swift + Android Kotlin 双原生方案 | 单一 Flutter 代码库，iOS/macOS/Android 三端共用 |

---

## 二、技术栈选型（Flutter 单栈，三端复用）

| 维度 | 选型 | 备注 |
|---|---|---|
| Flutter SDK | 3.19+（Dart 3.3+） | 与 `pubspec.yaml` 一致 |
| 状态管理 | `provider` 6.x（已引入）+ `ChangeNotifier` | 渐进迁移到 Riverpod 不在本 spec 范围 |
| 路由 | `go_router` 14.x（已引入） | 现有 `/splash /connect(/token) /home(/project-switcher) /settings` |
| 网络（HTTP） | `package:http` 1.x 或 `dio` 5.x | 推荐 `http`（更轻、官方背书）；multipart 上传必须支持 stream |
| UDP | `dart:io` `RawDatagramSocket`（已用） | 不引入第三方包 |
| 序列化 | `dart:convert` `jsonDecode` + 手写 `fromJson` | 不引入 `json_serializable`（避免 build_runner 复杂度） |
| 持久化（安全） | iOS/macOS Keychain → `flutter_secure_storage` 9.x；Android EncryptedSharedPreferences → 同库（封装 AndroidX Security Crypto） | 详见 §六 |
| 持久化（公开） | `shared_preferences` | 仅存非敏感偏好（语言 / 主题） |
| 平台通道 | `MethodChannel` 仅在必要时 | 见 §七 |
| i18n | Flutter 自带 `intl` + ARB | 中英两语 |
| 测试 | `flutter_test` + `integration_test` | mock + 真机端到端 |

> **不引入**：`flutter_udp_listener` / `multicast_lock` 等第三方 UDP 库——平台差异由原生存码处理，UDP 层自己写。

---

## 三、目录结构（实施时落地形态）

```
flutter/
├── lib/
│   ├── main.dart                              # 入口：选择 mock / v0.12 真实
│   ├── app/
│   │   ├── app.dart                           # MaterialApp + ErrorBus
│   │   ├── router.dart                        # go_router 路由表
│   │   ├── theme.dart
│   │   ├── settings_view.dart
│   │   └── splash_view.dart
│   ├── core/
│   │   ├── app_state.dart                     # AppStage 枚举 + 持久化恢复
│   │   ├── app_error.dart                     # AppError + AppErrorKind
│   │   ├── app_error_bus.dart                 # 全局错误 Bus
│   │   ├── secure_storage.dart                # Keychain / EncryptedSP 封装
│   │   ├── i18n/
│   │   │   ├── strings.dart                   # 字符串集中导出
│   │   │   └── strings_zh.arb / strings_en.arb
│   │   └── log/
│   │       └── sensitive_log.dart             # token / ip 脱敏
│   ├── features/
│   │   ├── discovery/                         # D01
│   │   │   ├── udp_discovery_service.dart     # RawDatagramSocket 监听（已有）
│   │   │   ├── udp_discovery_adapter.dart     # 适配 DiscoveryService 接口
│   │   │   ├── udp_announce.dart              # JSON 数据模型（已有）
│   │   │   ├── multicast_lock_channel.dart    # Android MulticastLock 原生桥
│   │   │   ├── udp_log.dart                   # [UDP]/[ANNOUNCE]/[MLOCK] 日志
│   │   │   ├── discovery_view.dart            # PC 列表 UI（已有）
│   │   │   ├── offline_judge.dart             # 6 s 离线判定（D04）
│   │   │   └── network_monitor.dart           # NWPathMonitor / NetworkCallback
│   │   ├── connection/                        # D03
│   │   │   ├── connection_service.dart        # HTTP health + token 持久化
│   │   │   ├── token_repository.dart          # 广播覆盖 + Keychain 持久化
│   │   │   ├── token_input_view.dart          # 6 位数字输入 UI（已有）
│   │   │   └── manual_input_view.dart         # 手动输入 IP/Port/Token 兜底
│   │   ├── project/                           # D02 §3.1.2
│   │   │   ├── project_service.dart           # HTTP /api/v1/projects
│   │   │   ├── project.dart                   # DTO
│   │   │   └── project_switcher.dart          # UI（已有）
│   │   └── upload/                            # D02 §3.1.3
│   │       ├── upload_service.dart            # HTTP multipart 上传
│   │       ├── upload_progress.dart           # 流式进度回调
│   │       └── upload_view.dart               # UI（已有）
│   └── ui/
│       ├── components/                        # 复用组件（已有）
│       │   ├── error_banner.dart
│       │   ├── progress_overlay.dart
│       │   ├── token_input.dart
│       │   └── ...
│       └── tokens/                            # 设计 token（颜色 / 间距）
├── test/
│   ├── discovery/                             # UDP 解析单元测试
│   ├── connection/                            # Token 状态机单元测试
│   ├── upload/                                # Multipart 上传 mock
│   └── integration/                           # 真机端到端
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml                # 加 ACCESS_WIFI_STATE / 配 network_security_config
│       └── res/xml/network_security_config.xml
├── ios/
│   └── Runner/Info.plist                      # 加 NSLocalNetworkUsageDescription + ATS
├── macos/
│   └── Runner/Info.plist                      # 同 iOS
└── scripts/
    ├── pc_mock_broadcaster.py                 # 现有：PC v0.12 mock
    └── smoke_test.sh                          # 端到端冒烟（curl + UDP）
```

---

## 四、模块详细规格

### 4.1 Discovery（D01 · UDP 监听）

**职责**：监听 UDP 9876 端口，过滤 `service == "starttooler"` 广播，解析字段、去重、展示给用户。

**核心流程**：

```
┌────────────────────────────────────────────────────┐
│ App 启动 / 回到前台                                  │
│   ↓                                                │
│ DiscoveryView.startScan()                          │
│   ↓                                                │
│ UdpDiscoveryServiceImpl.scan(window: 5s)           │
│   ├─ bind 0.0.0.0:9876                             │
│   ├─ 订阅 RawSocketEvent                           │
│   ├─ 每帧 → UdpAnnounce.tryParse(json, senderIp)  │
│   ├─ 过滤: service / version / name / token        │
│   ├─ 去重 key: "${name}|${port}|${ip}"             │
│   └─ 5s 后关闭 + 返回 DiscoveryResult              │
│   ↓                                                │
│ OfflineJudge.attach(announces)                     │
│   ├─ 每台 PC 一个 lastReceivedAt                   │
│   └─ 定时器：now - lastReceivedAt > 6s → offline   │
└────────────────────────────────────────────────────┘
```

**数据模型**（`udp_announce.dart` 已有，按 D01 §3.4 严格对齐）：

| 字段 | 来源 | 用途 |
|---|---|---|
| `name` | `payload["name"]` | UI 列表主标题 |
| `ip` | `socket.receiveAddress.address` | HTTP 直连用 |
| `port` | `payload["port"]` | HTTP base URL 端口 |
| `token` | `payload["token"]` | **权威源**（D03 §3.1） |
| `version` | `payload["version"]` | 协议版本校验 |
| `currentProject` | `payload["currentProject"]` (空串 → null) | UI 副标题 |

**必做清单**（D01 §3.3-§3.7）：

- [x] **过滤**：`service == "starttooler"`，否则丢弃
- [x] **过滤**：`version.major >= "0"`，不识别时打日志（PC 端 v0.12 当前在范围）
- [x] **去重 key**：`name|port|ip` 三元组（IP 浮动时用 `name|port`）
- [x] **手动输入兜底**：5 s 扫描无设备 → 显示「手动输入 IP/Port/Token」入口
- [x] **后台回前台**：重置所有 PC 的 `lastReceivedAt = now`（D04 §3.4）
- [x] **网络事件**：监听 `NWPathMonitor` / `NetworkCallback`，网络恢复触发重新扫描（D04 §3.5）

**不做清单**（D01 §7）：
- 后台持续监听（系统限制）
- mDNS / Bonjour / 蓝牙 / NFC（v0.12 范围外）

**iOS / Android 关键差异**：

| 平台 | 处理 |
|---|---|
| iOS | Info.plist 加 `NSLocalNetworkUsageDescription`；模拟器不工作，必须真机 |
| Android | 部分设备需 `MulticastLock`（原生 `MethodChannel` 实现，见 [multicast_lock_channel.dart](../../../../flutter/lib/features/discovery/multicast_lock_channel.dart)） |
| macOS | 同 iOS；多网卡需遍历活跃接口（UDP `bind` 0.0.0.0 已覆盖） |

**验收**（D01 §8）：
- PC 启动 → App 1-3 s 内出现设备
- PC 关闭 → App 6 s 内标灰（联动 OfflineJudge）
- 同 LAN 多台 PC → 列表按机器名排序展示
- `service` 不匹配的广播不进入列表
- iOS 真机可抓 9876 UDP 流量

---

### 4.2 Connection（D03 · Token 状态机 + D02 §3.1.1 health）

**职责**：用户输入 6 位 token；调 `/api/v1/health` 验证可达；持久化 `{ip, port, token, name}` 到 Keychain/EncryptedSP；广播更新时**无条件覆盖**内存与持久化的 token。

**Token 状态机**（D03 §3.3）：

```
收到新广播 ──→ 内存 token = 广播 token
              └─→ 持久化 token = 广播 token  (异步写 Keychain)

请求返回 401 ──→ 等下一次广播 (≤ 2s)
                 ├─ 收到 → 重试当前请求一次
                 │         ├─ 成功 → 继续
                 │         └─ 仍 401 → 提示 + 跳连接页
                 └─ 2s 未到 → 强制跳连接页
```

**接口设计**：

```dart
abstract class ConnectionService {
  /// 输入 token 后调 health 验证。
  Future<PC> connect({required String ip, required int port, required String token});

  /// 进程启动时尝试用持久化 token 试探 health。
  Future<PC?> tryRestore();

  /// 收到新广播时调用：无条件覆盖内存 + 异步写持久化。
  void onAnnounce(UdpAnnounce a);

  /// 401 重试：等下次广播 + 重试一次。
  Future<T> withTokenRetry<T>(Future<T> Function(String token) action);
}
```

**健康检查**（D02 §3.1.1）：

- URL：`http://{ip}:{port}/api/v1/health`
- 超时：3 s
- 无鉴权
- 校验响应字段：`service == "starttooler"`、`port` 与广播一致、`version.major == 0`
- **响应里的 token 仅作回包校验**（D03 §3.8），不主动取值

**持久化**（D03 §3.4）：

| 字段 | 存储 | 说明 |
|---|---|---|
| `pc_ip` | Keychain/EncryptedSP | App 重启后直连用 |
| `pc_port` | 同上 | 同上 |
| `pc_token` | 同上 | 重启后继续业务 |
| `pc_name` | 同上 | 列表展示 |
| `last_current_project` | 同上 | 重启后默认选中 |
| `last_seen_at` | 同上 | 30 天清理提示用 |

**清除时机**（D03 §3.10）：

| 场景 | 清除范围 |
|---|---|
| 401 重试仍 401 | 清 token，保留 ip/port/name（让用户重输 token） |
| 用户主动「切换 PC」 | 清全部 |
| 30 天未连接 | 提示，不主动清 |
| 卸载 / 清 App 数据 | 系统自动清 |

**验收**（D03 §7）：
- 首次启动 → 输入 token → 进主页 → token 持久化
- PC 重置 token → App ≤ 2 s 内自动覆盖（不需用户重输）
- PC 重启（token 变 + IP 变）→ App 用 `name|port` 识别并覆盖
- 401 → 等广播 + 重试一次 → 成功
- 401 → 仍 401 → 提示 + 跳连接页
- 进程回收重启 → 用持久化 token 试探 health，无需等下次广播

---

### 4.3 Project（D02 §3.1.2 · 拉项目列表）

**职责**：调 `/api/v1/projects?token=xxx` 拉 PC 端 RecentDirectories，UI 展示供切换。

**请求**：

| 项 | 值 |
|---|---|
| URL | `http://{ip}:{port}/api/v1/projects?token={token}` |
| 超时 | 5 s |
| 鉴权 | token（query string） |

**响应 DTO**：

```dart
class ProjectListResponse {
  final List<ProjectItem> items;
}

class ProjectItem {
  final String name;         // 用于 URL 路径
  final String path;         // UI 副标题
  final String? projectName; // nullable → 显示 basename
  final int fileCount;       // 副标题 "1284 个文件"
  final int sizeMb;          // 副标题 "6.27 GB"
  final bool isCurrent;      // 默认勾选标记
}
```

**UI 行为**（D02 §3.6）：

- 主页「切换项目」弹窗展示列表
- `isCurrent == true` 置顶 + 默认勾选
- 切换后主页顶部项目名更新；后续上传 URL 用新 `name` 替换

**错误处理**：

| 状态码 | App 反应 |
|---|---|
| 200 + `items == []` | "PC 上还未添加任何项目"（空状态） |
| 401 | 触发 D03 状态机 |
| 404 | "项目列表请求失败，请重试"（理论上不会触发 404） |
| 500 | Toast + Retry |
| 超时 | "PC 端响应超时" + Retry |

**验收**：
- PC 端 RecentDirectories 有 N 项 → App 列表展示 N 项
- 切项目后再上传 → URL 中 `{name}` 正确切换
- `projectName` 为 null → UI 优雅降级（显示 basename）

---

### 4.4 Upload（D02 §3.1.3 · 批量上传）

**职责**：批量 multipart 上传到指定项目；流式进度回调；解析 `failed[]` 列表展示给用户。

**请求**：

| 项 | 值 |
|---|---|
| URL | `http://{ip}:{port}/api/v1/projects/{name}/upload?token={token}` |
| 超时 | 60 s |
| Content-Type | `multipart/form-data; boundary=...` |
| 字段 | 多个 `file` 字段，每段一个文件 |

**请求体构造**（流式）：

```dart
final boundary = 'Boundary-${Uuid.v4()}';
final request = http.MultipartRequest('POST', uri)
  ..fields['token'] = token; // 也可走 header
for (final file in files) {
  request.files.add(await http.MultipartFile.fromPath(
    'file', file.path, filename: file.name));
}
final streamed = await request.send().timeout(const Duration(seconds: 60));
```

**进度回调**：

```dart
streamed.stream.listen((bytes) {
  sentBytes += bytes.length;
  onProgress(sentBytes, totalBytes); // 单次请求级
});
```

UI 用「已传 N / total」数字显示，不显示百分比（D02 §3.5）。

**响应 DTO**：

```dart
class UploadResponse {
  final bool success;
  final int count;
  final List<UploadFile> files;   // 成功项（含最终落盘 name）
  final List<UploadFailed> failed; // 失败项（含 reason）
}

class UploadFile {
  final String name;  // PC 端最终落盘名（可能与上传名不同，重名加 _1/_2）
  final String path;  // 绝对路径
}

class UploadFailed {
  final String name;   // 原始上传名
  final String reason; // PC 端 i18n 文本
}
```

**错误处理**：

| 状态码 / 场景 | App 反应 |
|---|---|
| 200 + `success=true` | Toast "已上传 N 个文件" + 失败列表展示 |
| 200 + `failed[]` 含扩展名 | UI 标注「扩展名不支持」（D06 §3.3） |
| 200 + `failed[]` 含超大文件 | UI 标注「文件过大（500MB 上限）」 |
| 401 | 触发 D03 状态机（等广播 + 重试一次） |
| 404 | "项目已失效，请重新选择" + 自动刷新项目列表 |
| 400 | 客户端代码 bug，记日志；提示「上传格式错误」 |
| 405 | 客户端代码 bug，记日志 |
| 500 | Toast + Retry |
| 超时 | "上传超时，已传 N 个文件" + 列表保留 |
| 中断（Wi-Fi 切 / 飞行模式） | "网络中断，已传 N 个文件" + 列表保留 |

**重名策略**（D02 §3.4）：服务端可能返回 `DSC_0001_1.NEF`；UI 列表展示以响应 `files[].name` 为准。

**扩展名预校验**（D02 §3.3）：

```dart
const _allowed = {'.jpg','.jpeg','.png','.raw','.avi','.mp4','.mov',
                   '.mkv','.webm','.m4v','.mpg','.mpeg'};
```

客户端**可**过滤（节省用户时间）；不过滤时 fallback 到 `failed[]` 展示。**不**做客户端 500 MB 拦截，让服务端兜底（D02 §3.2）。

**验收**：
- 上传 1 张 .jpg → 成功
- 上传 .exe → `failed[]` 含 `unsupported extension .exe`，UI 弹窗
- 上传 600MB 单文件 → `failed[]` 含 `exceeds 500MB limit`
- 上传 2 张同名 → PC 端分别落原名 / `name_1.jpg`，UI 显示响应里的 name
- 上传 30 张混合照片 + 视频 → 全部成功
- 切项目后再上传 → URL 切换正确

---

### 4.5 Persistence（D03 §3.4 + §4）

**实现**：`flutter_secure_storage` 9.x

```dart
class SecureStore {
  static const _k = 'pc.conn';

  Future<void> saveConnection({
    required String ip, required int port, required String token,
    required String name, String? lastProject}) async {
    final json = jsonEncode({
      'ip': ip, 'port': port, 'token': token, 'name': name,
      'lastProject': lastProject, 'lastSeenAt': DateTime.now().toIso8601String(),
    });
    await _storage.write(key: _k, value: json, aOptions: _iosOpts);
  }

  Future<ConnectionRecord?> loadConnection() async { /* 反向 */ }
  Future<void> clear() async => _storage.delete(key: _k);
}
```

| 平台 | 底层 | 备注 |
|---|---|---|
| iOS | Keychain (`kSecAttrAccessibleAfterFirstUnlock`) | 不启用 iCloud 同步 |
| macOS | 同 iOS | 同包 |
| Android | EncryptedSharedPreferences (AES256_GCM) | `flutter_secure_storage` 内部封装 |

**日志脱敏**（D03 §4 + D06 §3.7）：

```dart
String maskToken(String t) =>
  t.length == 6 ? '${t.substring(0, 2)}****${t.substring(4)}' : '******';
```

---

### 4.6 Offline Judge（D04 · 在线判定）

**职责**：每台 PC 一个 `lastReceivedAt` 时间戳；6 s 未刷新 → 标记离线。

**状态机**（D04 §3.3）：

```
        收到广播                  6 s 未收广播
  ┌────────┐ ──────────→ ┌────────┐ ─────────→ ┌────────┐
  │  Unknown│             │  Online│            │ Offline│
  └────────┘              └────────┘            └────────┘
       ▲                                              │
       └──────────────── 收到广播 ─────────────────────┘
```

**关键不变量**：

- 阈值严格 **6 s**（3 个广播周期）；不要更精确（UDP 不可靠）
- 后台切回前台立即重置 `lastReceivedAt = now`（D04 §3.4）
- 网络从无到有 → 触发重新扫描（D04 §3.5）
- 网络断开 → 全部 PC 标 offline
- **5 s UX 节奏 vs 6 s 离线判定严格区分**（D06 §1.2）：
  - 5 s 用于「首屏无设备 → 显示手动输入入口」（UX）
  - 6 s 用于「在线 PC 突然消失 → 标灰」（技术判定）

**实现**：

```dart
class OfflineJudge {
  final _lastSeen = <String, DateTime>{}; // key: name|port
  Timer? _ticker;

  void onReceived(String key) => _lastSeen[key] = DateTime.now();

  void resetAll() => _lastSeen.clear(); // 后台回前台 / 网络恢复

  void start(void Function(String key, bool online) onChange) {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      _lastSeen.forEach((key, t) {
        final online = now.difference(t) < const Duration(seconds: 6);
        onChange(key, online);
      });
    });
  }
}
```

**验收**：
- PC 启动 → App 1-2 s 内显示 online
- PC 关闭 → App 6 s 后显示 offline
- App 切后台 → 立刻暂停判定；回前台立即重置
- 切 Wi-Fi → 飞行 → 恢复 Wi-Fi → 自动重新发现

---

### 4.7 Network Monitor（D04 §3.5 · 网络事件）

| 平台 | API | Flutter 接入 |
|---|---|---|
| iOS / macOS | `NWPathMonitor` | `connectivity_plus` 6.x（含 NWPathMonitor 封装） |
| Android | `ConnectivityManager.NetworkCallback` | 同上 |

事件 → 动作：

| 事件 | 动作 |
|---|---|
| 网络从无到有 | 触发重新扫描 + reset OfflineJudge |
| 网络从 A 切到 B | reset 所有 PC 状态为 Unknown，重新发现 |
| 网络断开 | 全部 PC 标 offline |

---

### 4.8 Error Handling（D06 · 三层错误 + i18n）

**三层错误模型**：

```dart
sealed class AppError {
  AppErrorKind kind; // network / http / business / ux
  String get message; // i18n 文案
  int? get httpStatus;
  String? get pcReason; // PC 端 failed[] reason（业务层透传）
}

class NetworkError extends AppError { ... }  // DNS / 连接拒绝 / 超时 / 中断
class HttpError extends AppError { ... }     // 401 / 404 / 405 / 500
class BusinessError extends AppError { ... } // failed[] 中的某一项
```

**i18n 文案 Key**（D06 §3.6）：

| Key | 中文 | 英文 |
|---|---|---|
| `err.network.timeout` | 网络超时 | Network timeout |
| `err.network.refused` | PC 端服务未启动 | PC service not running |
| `err.http.401` | PC 已拒绝当前 Token | PC rejected current token |
| `err.http.404.project` | 项目已失效 | Project no longer exists |
| `err.http.500` | PC 服务异常 | PC service error |
| `err.upload.exceeds_limit` | 文件过大（500MB 上限） | File exceeds 500MB limit |
| `err.upload.unsupported_ext` | 扩展名不支持 | Unsupported file extension |
| `err.upload.network_lost` | 网络中断，已上传 {n} 个 | Network lost, {n} files uploaded |
| `ux.no_device_found` | 未找到 PC，请检查 Wi-Fi | No PC found, check Wi-Fi |
| `ux.offline` | PC 已离线 | PC is offline |
| `ux.token_reset` | PC 已重置 Token，请重输 | PC reset token, please re-enter |

**实现**：`AppErrorBus`（已存在）将错误推给全局 ErrorBanner；Detail 页展开失败列表。

---

## 五、平台权限适配（D05 · iOS / macOS / Android）

### 5.1 iOS — `ios/Runner/Info.plist`

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>用于在家庭网络中自动发现 PC 端的星助</string>

<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key>
  <true/>
</dict>
```

### 5.2 macOS — `macos/Runner/Info.plist`

同上（macOS 13+ 对未沙盒二进制同样有 Local Network 权限）。注意沙盒选项在 `*.entitlements` 文件，不在 Info.plist。

### 5.3 Android — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>

<application
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```

`android/app/src/main/res/xml/network_security_config.xml`：

```xml
<network-security-config>
    <base-config cleartextTrafficPermitted="true">
        <trust-anchors>
            <certificates src="system"/>
            <certificates src="user"/>
        </trust-anchors>
    </base-config>
</network-security-config>
```

### 5.4 通用

- **照片选择**：iOS 用 `image_picker`（内部 `PHPickerViewController`）；Android 13+ 用系统 Photo Picker
- **网络事件**：`connectivity_plus`
- **加密存储**：`flutter_secure_storage`

### 5.5 验收（D05 §7）

- iOS Info.plist 含 `NSLocalNetworkUsageDescription` + ATS
- 真机首次启动触发本地网络权限弹窗
- Android `network_security_config` 放行私有 IP
- 真机可 PCAP 抓包

---

## 六、HTTP 客户端（D02 / D03 通用）

**选型**：`package:http` 1.x（推荐）或 `dio` 5.x。**优先 `http`**：更轻、官方背书、易于流式读取进度。

**核心封装**：

```dart
class HttpClient {
  HttpClient();

  Future<dynamic> get(String url, {String? token, Duration? timeout}) async {
    final req = http.Request('GET', Uri.parse(url));
    if (token != null) req.headers['X-Token'] = token;
    final streamed = await req.send().timeout(
        timeout ?? const Duration(seconds: 5));
    final resp = await http.Response.fromStream(streamed);
    _checkStatus(resp); // 200/401/404/405/500 → AppError
    return resp.body.isEmpty ? null : jsonDecode(resp.body);
  }

  Future<dynamic> postMultipart(String url, {
    required String token,
    required List<File> files,
    void Function(int sent, int total)? onProgress,
    Duration timeout = const Duration(seconds: 60),
  }) async { /* ... */ }
}
```

**超时分级**（D02 §4）：

| 接口 | 超时 |
|---|---|
| `/api/v1/health` | 3 s |
| `/api/v1/projects` | 5 s |
| `/api/v1/projects/{name}/upload` | 60 s |

**错误映射**：

```dart
void _checkStatus(http.Response r) {
  switch (r.statusCode) {
    case >= 200 && < 300: return;
    case 401: throw HttpError(401, ...);
    case 404: throw HttpError(404, ...);
    case 405: throw HttpError(405, ...);
    case 500: throw HttpError(500, ...);
    default: throw HttpError(r.statusCode, ...);
  }
}
```

---

## 七、实施计划（Plan · 分阶段交付）

> **目标**：在 Flutter 既有 mock + 部分 UDP 基础上，分 4 个里程碑落地完整 v0.12 对接能力。

### M1 · 真实 UDP Discovery（D01 完整）

| 任务 | 内容 | 工期估时 |
|---|---|---|
| 1.1 | `UdpAnnounce.tryParse` 校验：`service` / `version` / `name` / `token` 长度（已有，需补 `version` 校验） | 0.5 d |
| 1.2 | DiscoveryView 接入 `UdpDiscoveryServiceImpl`（替换 mock）；5s 窗口收包 | 1 d |
| 1.3 | 手动输入兜底页 `manual_input_view.dart` | 0.5 d |
| 1.4 | iOS Info.plist 加 `NSLocalNetworkUsageDescription` + ATS | 0.5 d |
| 1.5 | Android `network_security_config.xml` + Manifest 权限 | 0.5 d |
| 1.6 | Android `MulticastLockChannel` 原生桥（多机型兼容） | 1 d |
| 1.7 | 单元测试：`UdpAnnounce.tryParse` 各分支 | 0.5 d |

**M1 验收**：PC mock 启动 → App 1-3 s 内出现设备；iOS 真机 + Android 真机各跑通一次。

### M2 · Connection + Token 状态机（D03 + D02 §3.1.1）

| 任务 | 内容 | 工期估时 |
|---|---|---|
| 2.1 | `ConnectionService` 真实实现：调 health（3 s 超时） | 0.5 d |
| 2.2 | `TokenRepository`：广播覆盖 + Keychain 持久化（`flutter_secure_storage`） | 1 d |
| 2.3 | `withTokenRetry` 包装：401 → 等广播 ≤ 2 s → 重试一次 | 1 d |
| 2.4 | App 启动 `tryRestore`：持久化 token 试探 health | 0.5 d |
| 2.5 | `TokenInputView` 接入真实 ConnectionService（替换 mock） | 0.5 d |
| 2.6 | 单元测试：Token 状态机各路径（收到广播 / 401 重试 / 仍 401） | 1 d |

**M2 验收**：首次启动进主页、PC 重置 token 不需用户介入、401 重试链路通。

### M3 · Project + Upload（D02 §3.1.2 + §3.1.3）

| 任务 | 内容 | 工期估时 |
|---|---|---|
| 3.1 | `ProjectService` 真实实现：调 `/api/v1/projects` | 0.5 d |
| 3.2 | `ProjectSwitcher` UI 接入真实数据；`isCurrent` 置顶 | 0.5 d |
| 3.3 | `UploadService` 真实实现：multipart 流式上传 + 进度回调 | 1.5 d |
| 3.4 | `UploadView` 接入真实数据；`failed[]` 弹窗 | 1 d |
| 3.5 | 客户端扩展名预校验（12 种白名单） | 0.5 d |
| 3.6 | 单元 + 集成测试：上传 / 上传失败 / 重名 / 切项目 | 1 d |

**M3 验收**：上传 30 张混合照片 + 视频 → 全部成功；扩展名错误走 `failed[]`。

### M4 · 离线判定 + 网络事件 + 错误兜底（D04 + D06）

| 任务 | 内容 | 工期估时 |
|---|---|---|
| 4.1 | `OfflineJudge`：6 s 阈值 + 定时器 | 0.5 d |
| 4.2 | 接入 Discovery / Connection：online/offline 状态切换 | 0.5 d |
| 4.3 | 后台回前台 reset（`WidgetsBindingObserver.didChangeAppLifecycleState`） | 0.5 d |
| 4.4 | `connectivity_plus` 接入：网络事件 → reset + 重扫 | 0.5 d |
| 4.5 | `AppErrorBus` 完善三层错误映射 + i18n 文案 | 1 d |
| 4.6 | 单元测试：OfflineJudge / 错误映射 | 1 d |
| 4.7 | 端到端 smoke（PC mock + 真机） | 1 d |

**M4 验收**：PC 关 → 6 s 后离线；切 Wi-Fi → 自动恢复；网络中断 → 已传文件保留。

> **总估时**：约 14 个工程日（含测试）。单人节奏约 3-4 周。

---

## 八、测试计划

### 8.1 单元测试（`flutter/test/`）

| 模块 | 关键用例 |
|---|---|
| `UdpAnnounce.tryParse` | service 不匹配 / version 缺失 / token 长度 ≠ 6 / currentProject 空串 → null |
| `OfflineJudge` | 6 s 阈值边界（5.999 s online / 6.001 s offline） |
| `TokenRepository` | 广播覆盖 / 401 重试 / 仍 401 / 持久化往返 |
| `HttpClient` | 超时抛 NetworkError / 401/404/405/500 抛 HttpError / multipart 进度回调 |
| `AppErrorMapper` | PC 端 reason → i18n key |

### 8.2 集成测试（`integration_test/`）

- 真机 + PC mock（`scripts/pc_mock_broadcaster.py`）
- 完整链路：发现 → 连接 → 选项目 → 上传 5 张图 → 验证 PC 端文件落盘

### 8.3 真机矩阵

| 平台 | 设备 |
|---|---|
| iOS | iPhone 14 / iPad mini 6（iOS 16+） |
| macOS | MacBook Air M1（macOS 13+） |
| Android | Pixel 6 / 三星 S23（Android 13+） |

### 8.4 端到端冒烟（`scripts/smoke_test.sh`）

```bash
# 1. 启动 PC mock
python3 scripts/pc_mock_broadcaster.py &

# 2. UDP 抓包验证广播
nc -u -l 9876 &  # 期望 2s 收到一帧 JSON

# 3. health 验证
curl -s http://localhost:8765/api/v1/health | jq .

# 4. 项目列表
curl -s "http://localhost:8765/api/v1/projects?token=123456" | jq .

# 5. 上传
curl -s -X POST "http://localhost:8765/api/v1/projects/test/upload?token=123456" \
     -F "file=@/tmp/test.jpg" | jq .
```

---

## 九、CI / CD

### 9.1 GitHub Actions（最小骨架）

```yaml
name: Mobile CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
      - run: flutter build apk --debug
  ios-build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter build ios --no-codesign --debug
```

### 9.2 发布

| 阶段 | 工具 |
|---|---|
| iOS TestFlight | `flutter build ipa` + Xcode → TestFlight |
| Android Play Console | `flutter build appbundle` |
| macOS | `flutter build macos` + 签名公证 |

---

## 十、依赖（最终 pubspec.yaml）

```yaml
dependencies:
  flutter:
    sdk: flutter
  go_router: ^14.6.2          # 路由（已有）
  provider: ^6.1.2            # 状态管理（已有）
  http: ^1.2.0                # HTTP 客户端（新增）
  flutter_secure_storage: ^9.2.2  # Keychain / EncryptedSP（新增）
  connectivity_plus: ^6.0.5   # 网络事件（新增）
  image_picker: ^1.1.2        # 照片选择（新增）
  intl: any                   # i18n（已有 flutter 自带）

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  integration_test:
    sdk: flutter
```

> **不引入**：`dio`（与 `http` 二选一即可）、`riverpod`（沿用 `provider`）、`json_serializable`（手写 `fromJson`）。

---

## 十一、版本号与兼容

| 维度 | 编号 |
|---|---|
| App 端 | semver（0.1.0 → 1.0.0） |
| 协议版本 | 严格 `0.12.x`；`version.major == 0` 即视为兼容 |
| PC 端要求 | v0.12 及以上；旧版 PC 显示「请升级 PC 端」 |

**字段扩展兼容**：PC 端新增字段 App 端忽略；PC 端删除字段 → major version bump + App 端升级。

---

## 十二、不做清单

| 内容 | 理由 |
|---|---|
| iOS Swift + Android Kotlin 双原生 | 已被 Flutter 取代；不再维护 |
| mDNS / Bonjour / X25519 / pair_code | v0.12 范围外（见 v1.0 草案） |
| 后台持续 UDP | 系统限制 |
| HTTPS / 自签证书 | LAN 风险可控 |
| 公网同步 / OSS 触发 | D02 范围外 |
| AI / 修图 | 不在需求范围 |
| 多账号 / 登录 | 不在需求范围 |
| 文件秒传 / 断点续传 | MVP 阶段 |
| 客户端 500 MB 拦截 | 让服务端兜底 |

---

## 十三、风险与缓解

| 风险 | 缓解 |
|---|---|
| iOS 模拟器不能测 UDP | 强制真机；CI 用 `flutter test` + 真机冒烟脚本 |
| Android 厂商后台限制 | README 说明 + 加白名单引导弹窗 |
| Flutter `RawDatagramSocket` 跨平台差异 | 原生 `MethodChannel` 处理 MulticastLock 等系统能力 |
| `flutter_secure_storage` iOS 钥匙串访问失败 | fallback 到 `shared_preferences` + 显式提示「安全存储不可用」 |
| PC mock 与真机 PC 行为差异 | smoke 脚本先用 mock，端到端测试接真 PC |
| main.dart 默认走 v1.0 草案 | 本 spec 落地时改默认走 v0.12 真实，v1.0 移到 `--dart-define=PROTO=v1` 实验通道 |

---

## 十四、需求 ↔ 模块 ↔ 验收映射（追溯表）

| 需求 | 模块 | 关键验收 |
|---|---|---|
| **D01** UDP 监听 9876 / 过滤 / 去重 / 手动输入 | §4.1 Discovery | PC 启动 → App 1-3 s 内出现设备 |
| **D02** health / projects / upload 3 个 HTTP | §4.2/4.3/4.4 + §六 | 上传 30 张混合文件全部成功 |
| **D03** Token 状态机 + 持久化 + 401 重试 | §4.2 Connection + §4.5 Persistence | PC 重置 token → App ≤ 2 s 自动覆盖 |
| **D04** 6 s 离线判定 + 后台回前台 + 网络事件 | §4.6 Offline Judge + §4.7 Network Monitor | PC 关 → App 6 s 后标灰 |
| **D05** iOS/macOS Local Network + ATS / Android Cleartext | §五 平台权限 | 真机触发权限弹窗 + 抓包可验证 |
| **D06** 三层错误 + i18n + 5s/6s 严格区分 | §4.8 Error Handling + §七 计划 M4 | 所有错误文案有中英；5 s 引导手动输入、6 s 标灰不重叠 |

---

## 十五、参考与变更记录

### 关联文档

- 需求（6 篇）：[demand/README.md](../demand/README.md) 索引
- PC 端 spec：[04-mobile-lan-sync.md](04-mobile-lan-sync.md)
- 协议权威：[02-pc-udp-protocol.md](../../app/02-pc-udp-protocol.md)
- 自测清单：[03-mobile-checklist.md](../../app/03-mobile-checklist.md)
- 知识库：[knowledge-base/API-01-http-routes.md](../../knowledge-base/API-01-http-routes.md) + [API-03-udp-broadcast.md](../../knowledge-base/API-03-udp-broadcast.md) + [API-06-error-i18n.md](../../knowledge-base/API-06-error-i18n.md)

### 变更记录

| 日期 | 变更 | 内容 |
|---|---|---|
| 2026-08-20 | v0.1（重写） | 完全重写 spec：弃用 iOS Swift + Android Kotlin 双原生方案，改为 Flutter 单栈；按 [demand](../demand/README.md) 6 篇需求稿拆分 §4.1-§4.8 模块；新增 §七 实施计划 M1-M4 四个里程碑；§十四 需求-模块-验收追溯表覆盖 D01-D06 全部条款 |