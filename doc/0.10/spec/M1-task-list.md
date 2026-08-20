# M1 · 真实 UDP Discovery — 任务清单与验收标准

> **里程碑**：M1 / 4（[spec/05-mobile-app.md §七 M1](05-mobile-app.md#七实施计划plan--分阶段交付)）
> **范围**：D01 完整对接 — UDP 监听 9876、过滤、去重、手动输入兜底、平台权限（**本里程碑仅 Android**；iOS 留待后续阶段）
> **目标**：PC mock 启动 → App 1-3 s 内出现设备；Android 真机各跑通一次
> **估时**：约 4.5 d 原估；本里程碑仅 Android 部分 → 实际 **0.9 d**（[详见实施规划](M1-implementation-plan.md)）
> **关联需求**：[demand/D01-udp-discovery.md](../demand/demand/D01-udp-discovery.md) / [demand/D05-platform-permissions.md](../demand/demand/D05-platform-permissions.md)

---

## 目录

- [一、任务清单](#一任务清单)
- [二、M1 整体验收标准](#二m1-整体验收标准)
- [三、上游 / 下游依赖](#三上游--下游依赖)
- [四、风险登记](#四风险登记)
- [五、里程碑 Gate](#五里程碑-gate合并前-checklist)
- [六、变更记录](#六变更记录)

---

## 一、任务清单

> **任务命名规则**：`T-M1-N`（M1 第 N 项）
> **状态约定**：未开始 / 进行中 / 完成 / 阻塞

### T-M1-1 · `UdpAnnounce.tryParse` 校验补全

| 项 | 内容 |
|---|---|
| 文件 | `flutter/lib/features/discovery/udp_announce.dart` |
| 现状 | 已实现 service / port / name / token 长度校验 |
| 改动 | 补 `version` 严格校验（要求 `version.major == 0`）+ `currentProject` 空串 → null（已有）+ 非法 JSON 不抛异常（已 try/catch） |
| 工时 | 0.5 d |

**DoD**：

- [ ] `version` 缺失或非 string → 拒绝（返回 null + 打日志）
- [ ] `version.major != 0` → 拒绝（当前 v0.12 在范围内）
- [ ] `currentProject` 为空串 `""` → 转为 `null`（已有）
- [ ] 非法 JSON → 返回 null 不抛
- [ ] 所有拒绝分支有 `UdpLog.announce('tryParse rejected (...))` 日志

### T-M1-2 · DiscoveryView 接入 `UdpDiscoveryServiceImpl`

| 项 | 内容 |
|---|---|
| 文件 | `flutter/lib/features/discovery/discovery_view.dart` + 新增 `udp_discovery_adapter.dart` |
| 现状 | `DiscoveryView` 接 mock `DiscoveryMock`；`UdpDiscoveryServiceImpl`（监听 9876）已存在 |
| 改动 | 1) 新增 `UdpDiscoveryAdapter` 实现 `DiscoveryService` 接口包装 `UdpDiscoveryServiceImpl`；2) `main.dart` 默认走 `UdpDiscoveryAdapter(UdpDiscoveryServiceImpl())`；3) `DiscoveryView` 调用 `service.scan(onDiscovered: ...)`，5 s 窗口；4) 改 `discovered` 数据源为 `UdpAnnounce` |
| 工时 | 1 d |

**DoD**：

- [ ] `UdpDiscoveryAdapter` 实现 `DiscoveryService.scan()`：返回 `List<UdpAnnounce>`
- [ ] `UdpDiscoveryAdapter` 字段映射到 UI 层 `PC`（`name` / `ip` / `port` / `currentProject`）
- [ ] `main.dart` 默认走真实 UDP（移除默认 mock）
- [ ] `DiscoveryView` 5 s 扫描窗口结束自动停；不再 `simulateOffline()` 按钮
- [ ] 列表项展示 `name` + `currentProject`（空时显示"PC 未选择项目"）+ `ip:port`

### T-M1-3 · 手动输入兜底页 `ManualInputView`

| 项 | 内容 |
|---|---|
| 文件 | 新增 `flutter/lib/features/connection/manual_input_view.dart` |
| 改动 | 1) 表单：IP / Port / Token 三字段；2) 校验 IP 格式 + Port 范围（1-65535）+ Token 6 位数字；3) 提交后跳转 `TokenInputView` 走真实鉴权链路（M2 实现，**M1 阶段允许复用 mock `ConnectionMock`**）；4) 与 DiscoveryView「手动输入」入口联动 |
| 工时 | 0.5 d |

**DoD**：

- [ ] 三个字段非空 + 格式正确才能提交
- [ ] 提交后 `GoRouter` 跳到 `/connect/token`，extra 携带 `{ip, name}`（port 透传）
- [ ] DiscoveryView 扫描 5 s 无设备 → 自动显示「手动输入」入口按钮
- [ ] 「手动输入」按钮 → 跳转 `/connect/manual`
- [ ] 手动输入的设备走与 UDP 发现相同的 `TokenInputView` 流程

### T-M1-4 · iOS Info.plist 配置（⏸️ 暂缓，聚焦 Android）

| 项 | 内容 |
|---|---|
| 状态 | **本里程碑暂缓**；M1 范围仅 Android，iOS 工程（`flutter create -i swift` + Info.plist 配置）留待后续 iOS 计划阶段 |
| DoD | — |

### T-M1-5 · Android Manifest + `network_security_config.xml`

| 项 | 内容 |
|---|---|
| 文件 | `flutter/android/app/src/main/AndroidManifest.xml` + 新增 `flutter/android/app/src/main/res/xml/network_security_config.xml` |
| 现状 | 已存在 Manifest（需补权限）+ 已存在 `network_security_config.xml`（需检查） |
| 改动 | 1) Manifest 添加 `ACCESS_NETWORK_STATE` / `ACCESS_WIFI_STATE`；2) 确认 `<application android:networkSecurityConfig="@xml/network_security_config">` 引用；3) `network_security_config.xml` 启用 cleartext + trust-anchors |
| 工时 | 0.5 d |

**DoD**：

- [ ] Manifest 含 `INTERNET` / `ACCESS_NETWORK_STATE` / `ACCESS_WIFI_STATE` 三个权限
- [ ] `<application>` 标签引用 `@xml/network_security_config`
- [ ] `network_security_config.xml` `cleartextTrafficPermitted=true`
- [ ] Android 9+ 真机 HTTP 请求不再抛 `CleartextNotPermittedException`
- [ ] Android 13+ 真机可用 Photo Picker（系统 Photo Picker 自动启用）

### T-M1-6 · Android MulticastLock 原生桥

| 项 | 内容 |
|---|---|
| 文件 | `flutter/lib/features/discovery/multicast_lock_channel.dart`（已存在）+ `flutter/android/app/src/main/kotlin/.../MulticastLockPlugin.kt` |
| 现状 | Dart 侧 `MethodChannel` 调用已存在；需补 Kotlin 实现 |
| 改动 | 1) Kotlin 侧 `MulticastLockPlugin`：注册 `acquire` / `release`；2) `acquire` 调 `WifiManager.createMulticastLock("starttooler-mobile")` + `acquire()`；3) `release` 调 `release()`；4) App 启动 / 暂停时调用 |
| 工时 | 1 d |

**DoD**：

- [ ] `MulticastLockPlugin.kt` 注册到 `MainActivity.configureFlutterEngine()`
- [ ] `acquire` 调用 `WifiManager.MulticastLock` 并持有引用
- [ ] `release` 释放锁；重复 release 安全
- [ ] App 切后台自动 release；回前台重新 acquire
- [ ] 在小米/华为/OPPO 等品牌机型上验证 UDP 广播可接收

### T-M1-7 · 单元测试：`UdpAnnounce.tryParse`（⏭️ 由开发者自行 debug 验证）

| 项 | 内容 |
|---|---|
| 状态 | **不入实施规划**；T-M1-1 现有 `tryParse` 已覆盖所需校验，开发者按需手动 debug |
| 说明 | 移除 DoD 与工时估算 |

---

## 二、M1 整体验收标准

### 2.1 功能验收（与 D01 §8 + D04 §7 一一对应）

| # | 验收项 | 来源 | 通过条件 |
|---|---|---|---|
| A1 | PC 启动 → App 1-3 s 内出现设备 | D01 §8 / D04 §7 | 真机启动 PC mock，3 s 内列表出现 ≥ 1 项 |
| A2 | PC 关闭 → App 6 s 内标灰 | D01 §8 / D04 §7 | 关闭 PC mock，6 s 内该项 UI 灰显（依赖 M4 OfflineJudge；M1 阶段可仅"无新广播"） |
| A3 | 同 LAN 收到 2 台 PC → 列表展示 2 项 | D01 §8 | 起 2 个 mock（不同 IP），列表出现 2 项，按 `name` 排序 |
| A4 | `service` 不匹配的广播不进入列表 | D01 §8 | 抓 SSDP/NetBIOS 验证；或用 `nc -u -b 255.255.255.255 9876` 发 `{"service":"upnp"}` 包，验证被丢弃 |
| A5 | `currentProject=""` 时显示"PC 未选择项目" | D01 §8 | mock payload 设 `currentProject=""`，UI 显示降级文案 |
| A6 | iOS 真机可抓 9876 流量 | D01 §8 | `sudo tcpdump -i en0 -n udp port 9876 -A` 能看到 PC mock JSON |
| A7 | Android 真机可 PCAP 抓包 | D01 §8 | 真机 + tcpdump 或 `Wireshark` 能抓到 9876 |
| A8 | 手动输入入口在 5 s 无设备时自动出现 | D01 §8 | 不开 PC mock，启动 App，5 s 后「手动输入」按钮可见 |

### 2.2 平台权限验收（与 D05 §7 对应）

| # | 验收项 | 来源 | 通过条件 |
|---|---|---|---|
| P1 | iOS Info.plist 含 `NSLocalNetworkUsageDescription` 字符串 | D05 §7.1 | `plutil -p ios/Runner/Info.plist \| grep NSLocalNetworkUsageDescription` 输出非空 |
| P2 | iOS Info.plist 含 ATS 例外 | D05 §7.1 | `plutil -p ios/Runner/Info.plist \| grep NSAllowsArbitraryLoads` 输出 `true` |
| P3 | iOS 真机首次启动触发本地网络权限弹窗 | D05 §7.1 | 全新安装首次启动看到弹窗 |
| P4 | iOS 用户拒绝后引导到「设置 → 隐私 → 本地网络」 | D05 §7.1 | 拒绝后 App 显示引导文案（可用 `app_settings` 跳转设置） |
| P5 | iOS 真机调试可抓 UDP 9876 + HTTP 流量 | D05 §7.1 | `tcpdump` 双流量均可抓 |
| P6 | iOS 模拟器不要求 UDP 工作 | D05 §7.1 | 已知限制，文档 / README 说明 |
| P7 | macOS `.app/Contents/Info.plist` 含 `NSLocalNetworkUsageDescription` | D05 §7.2 | 同 P1，路径 `macos/Runner/Info.plist` |
| P8 | macOS 首次启动触发系统弹窗（非静默） | D05 §7.2 | macOS 13+ 真机首次启动弹窗可见 |
| P9 | macOS 用户拒绝后引导到「系统设置 → 隐私与安全性 → 本地网络」 | D05 §7.2 | 同 P4 逻辑 |
| P10 | AndroidManifest.xml 含 INTERNET / ACCESS_NETWORK_STATE / ACCESS_WIFI_STATE | D05 §7.3 | `aapt dump permissions ...` 含三条 |
| P11 | 不在业务层直接持有 MulticastLock（Dart/Kotlin 侧封装内） | D05 §7.3 | T-M1-6 落地前确认；落地后仅在 Kotlin 侧持有锁（封装内） |
| P12 | `network_security_config.xml` 放行私有 IP 段 | D05 §7.3 | `cleartextTrafficPermitted=true` 已配 |
| P13 | Android 真机可 PCAP 抓包 | D05 §7.3 | 真机 + tcpdump 可见 9876 流量 |

### 2.3 跨平台验收

| # | 验收项 | 来源 | 通过条件 |
|---|---|---|---|
| C1 | README 显式说明"App 不在后台持续监听" | D05 §7.4 | `flutter/README.md` 加一段说明 |
| C2 | iOS 真机 + Android 真机各跑通一次端到端扫描 | 本 spec | iPhone 真机 + Android 真机均看到 PC mock 设备 |

### 2.4 测试验收

| # | 验收项 | 通过条件 |
|---|---|---|
| T1 | `flutter test` 全绿（仅 `widget_test.dart`） | `flutter test` 命令退出码 0 |
| T2 | `flutter analyze` 无 error | `flutter analyze` 命令退出码 0 |
| T3 | UDP parse 各分支手动 debug 验证（⏭️ 由开发者负责） | 真机 + mock 验证合法 / 异常 payload 各分支处理 |
| T4 | smoke 脚本 `scripts/smoke_test.sh` UDP 抓包段绿 | `nc -u -l 9876` 能收到 mock JSON |

### 2.5 文档验收

| # | 验收项 | 通过条件 |
|---|---|---|
| D1 | README 说明 iOS 模拟器 UDP 不工作 | `flutter/README.md` 加提示 |
| D2 | README 说明 Android 厂商后台限制 + 加白名单指引 | `flutter/README.md` 加提示 |
| D3 | 提交信息含 M1 关键字 + 子任务编号 | git commit message 含 `M1` 与对应 `T-M1-N` |

---

## 三、上游 / 下游依赖

### 3.1 上游（前置）

- **需求稿**：[D01-udp-discovery.md](../demand/demand/D01-udp-discovery.md) — 全部字段与边界以此为准
- **PC 端 spec**：[04-mobile-lan-sync.md](04-mobile-lan-sync.md) §3.9 — UDP 广播字段定义
- **协议权威**：[02-pc-udp-protocol.md](../../app/02-pc-udp-protocol.md) §二 — 广播 payload

### 3.2 下游（被 M1 阻塞）

| 模块 | 依赖点 | 阻塞项 |
|---|---|---|
| M2 (Connection) | `UdpAnnounce.token` 字段 | M2 用广播 token 触发 health |
| M3 (Project) | `UdpAnnounce.ip` + `.port` | M3 拼 base URL |
| M4 (OfflineJudge) | `UdpDiscoveryServiceImpl.scan()` 返回值 | M4 监听 `lastReceivedAt` |

### 3.3 与 M1 平行的工具

- **PC mock**：`scripts/pc_mock_broadcaster.py`（已存在）— 本里程碑验收用
- **真机抓包**：`tcpdump` / Wireshark — 验收 A6 / A7 / P5 / P13 用

---

## 四、风险登记

| ID | 风险 | 缓解 | 触发条件 |
|---|---|---|---|
| R1 | iOS 真机调试首次启动无弹窗 | 检查 Info.plist 是否被 Xcode 编译覆盖；用 `plutil` 验证 embedded.mobileprovision | P3 不通过 |
| R2 | Android 厂商机型收不到广播 | 启用 MulticastLock；若仍失败加 `WifiManager.startLocalOnlyHotspot` 探测 | A7 / P13 不通过 |
| R3 | `flutter_secure_storage` iOS Keychain 失败（M2 提前暴露） | 不在本里程碑；M1 仅 mock 即可 | — |
| R4 | UDP 端口被占用（macOS 上偶发） | `bind` 失败时捕获 + 提示"请检查是否有其他 App 占用 9876" | T-M1-2 跑通时 |

---

## 五、里程碑 Gate（合并前 checklist）

> 完成所有 T-M1-* 任务且下方 Gate 全部勾选后，M1 视为结束，可启动 M2。

- [ ] T-M1-1 至 T-M1-6 全部 DoD 通过（T-M1-7 由开发者自行 debug 验证）
- [ ] §二.1 8 项功能验收全部通过
- [ ] §二.2 13 项平台权限验收全部通过
- [ ] §二.3 2 项跨平台验收全部通过
- [ ] §二.4 4 项测试验收全部通过
- [ ] §二.5 3 项文档验收全部通过
- [ ] §四 风险登记无未关闭 R1-R4
- [ ] git tag：`m1-discovery-complete`
- [ ] PR 描述含 "Closes M1" 或 "M1 收尾"
- [ ] 主仓库 README「进度」段更新为 `M1 ✅ / M2 ⬜ / M3 ⬜ / M4 ⬜`

---

## 六、变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-08-20 | v0.1 | 初稿生成；从 [spec/05-mobile-app.md](05-mobile-app.md) §七 M1 展开 7 个子任务 + 26 项验收 |
| 2026-08-20 | v0.2 | 整理为标准 Markdown：加目录 ToC、统一标题层级、状态 emoji 改为文字、修复跳转链接锚点、补充 D05 §7.4 跨平台编号一致 |
| 2026-08-20 | v0.3 | T-M1-7 单元测试任务标记为「由开发者自行 debug 验证」，从实施规划移除；对应 T3 验收改为手动 debug 验证 |
| 2026-08-20 | v0.4 | 范围调整为 **仅 Android**；T-M1-4 iOS Info.plist 标记暂缓；iOS 验收 P1-P9 / P7-P9 留待后续阶段 |