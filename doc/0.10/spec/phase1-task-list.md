# 第一期 · 端到端最小链路（任务清单）

> 目标：**扫码 → 连接 PC → 获取项目（持久化）→ 上传** 一次性端到端打通。
> 平台：Android only（iOS/macOS 暂不考虑）。
> 上游：[v0.14-implementation-plan.md](./v0.14-implementation-plan.md) 第一期。

## 范围声明

- **UI**：不考虑设计。按最朴素 Material 默认组件实现（按钮 + 输入框 + 列表 + 文字提示）。
- **平台**：Android only。iOS 工程不生成、macOS 不考虑。
- **真实实现**：全部 HTTP 客户端直连 PC 端 `/api/v1/*`，**不使用 mock 数据**。测试用 `MockClient` 注入桩。
- **发现入口**：**真相机扫码（mobile_scanner）作为 QR 唯一入口**。不提供粘贴文本框 / 手动输入 IP 等兜底入口。
- **持久化**：Android EncryptedSharedPreferences（`flutter_secure_storage`）。

## Task 总览

| Task | 主题 | 前置 |
| --- | --- | --- |
| **T1** | 路由 + 4 页面骨架 + **扫码页（mobile_scanner）** + QR 解析 + health 客户端 | — |
| **T2** | projects 客户端 + 持久化 + 空间列表 + 启动续连 | T1 |
| **T3** | 上传流程（Photo Picker + multipart + 进度 + 失败分桶） | T1 + T2 |
| **T4** | 错误处理 + 状态机 + i18n + 端到端验收 | T1 + T2 + T3 |

---

## T1 · 路由 + 4 页面骨架 + 扫码页 + QR 解析 + health 客户端

### T1.1 依赖与路由骨架

- [ ] 添加 `go_router`、`provider`、`http`、`mobile_scanner` 到 pubspec.yaml
- [ ] AndroidManifest 加 `<uses-permission android:name="android.permission.CAMERA" />`
- [ ] 5 个路由：`/splash`、`/connect`（扫码页）、`/home`（含 `/home/project-switcher` 子）、`/settings`
- [ ] 路由守卫：splash 1.5s 后跳 `/connect`；当前空间非空时 `/connect` 重定向到 `/home`
- [ ] 顶层 `AppErrorBus`（Provider 注入，仅占位，T4 收敛全量错误码）

### T1.2 4 个页面骨架（朴素 Material）

- [ ] `SplashView` — `Center` + `Text('StartTooler')` + `CircularProgressIndicator` + 1.5s 跳转
- [ ] `ConnectView`（`/connect`，扫码页）— 调起相机 → `MobileScanner` 全屏覆盖 → 识别出 QR 文本后回调上层；首启动态申请相机权限；权限被拒 → 顶部 banner「需要相机权限才能扫码」+ 「去设置」按钮
- [ ] `HomeView`（`/home`）— `Scaffold` + `AppBar(空间名)` + 当前项目 `Card` + 其他项目 `ListView` + 「切换项目」/「上传」按钮（T3 接 Photo Picker）
- [ ] `ProjectSwitcherView`（`/home/project-switcher`）— 空间列表（T1 暂时内存里硬编码一个「当前空间」用于跳转演示，T2 接持久化）+ `+ 添加空间` 占位
- [ ] `SettingsView`（`/settings`）— 三个 `ListTile` 分组（PC / 缓存 / 关于）

### T1.3 扫码回调处理

- [ ] 扫码识别到 QR 文本 → 调 `QrParser.parse`
- [ ] 解析失败 → 顶部 banner「二维码无效」（不关闭扫码页，继续扫）
- [ ] 解析成功 → 关闭扫码层 → 调 health 验证

### T1.4 QR 解析（纯函数 + 单测）

- [ ] `core/qr_parser.dart` — 输入字符串，输出 `QrPayload { host, port, secret } | QrError`
- [ ] 校验：IPv4、port 1-65535、path == `/upload`、secret `\A[a-f0-9]{32}\z`
- [ ] 错误类型 `QrError.invalidFormat` / `QrError.invalidHost` / `QrError.invalidPort` / `QrError.missingSecret`
- [ ] 单测覆盖：合法 URL / IPv6 / port 越界 / secret 长度错 / 非 http 协议 / 缺 `?k=` / 多 `?k=` 取首个

### T1.5 Health 客户端（直连真实 PC）

- [ ] `core/health_api.dart` — `Future<Result<Health, AppError>> check(String host, int port, {Duration timeout = const Duration(seconds: 3)})`
- [ ] `Health` 模型：`{ name, version, port, secret, currentProject }`
- [ ] 网络层：`http.get('http://{host}:{port}/api/v1/health')`，无鉴权，3s 超时
- [ ] 错误映射：`SocketException → NetworkError.unreachable` / `TimeoutException → NetworkError.timeout` / `4xx/5xx → HttpError(status)`
- [ ] 单测：`MockClient` 注入桩，覆盖 200 / 404 / 500 / 超时 / DNS 失败

### T1.6 主页接 health

- [ ] `HomeView` 接收 `host` / `port` 参数（T1 路由参数跳转；T2 改为从持久化读）
- [ ] `initState` 调 `health_api.check` → 顶栏显示 `name`
- [ ] 健康成功后才允许进入主页

### T1 验收

- [ ] 启动 App → 1.5s splash → `/connect`（相机自动打开）
- [ ] 相机权限申请弹窗正常；权限授予后实时显示取景画面
- [ ] 相机对准 PC 端 QR（Android 屏显示的 QR 也可）→ 识别 → 解析 → 调 health → 跳 `/home`，顶栏显示 PC 名
- [ ] 扫描非法 QR → 顶部 banner 提示「二维码无效」，扫码页不关闭
- [ ] 相机权限被拒 → banner 提示「需要相机权限才能扫码」+ 「去设置」按钮
- [ ] health 失败 → 顶部 banner 提示「连不上 PC」/「PC 不可达」
- [ ] `flutter analyze` + `flutter test` 通过
- [ ] 手动 `flutter run -d <android>` 验证端到端

---

## T2 · projects 客户端 + 持久化 + 空间列表 + 启动续连

### T2.1 Projects 客户端（直连真实 PC）

- [ ] `core/projects_api.dart` — `Future<Result<List<Project>, AppError>> list(String host, int port, String secret, {Duration timeout = const Duration(seconds: 3)})`
- [ ] `Project` 模型：`{ name, isCurrent, fileCount, sizeBytes }`
- [ ] 网络层：`http.get('http://{host}:{port}/api/v1/projects?k={secret}')`，3s 超时
- [ ] 错误映射：复用 T1.5 的网络/超时/4xx/5xx，额外 401 → `AuthError.expired`
- [ ] 单测：`MockClient` 注入桩，覆盖 200 / 401 / 500 / 超时

### T2.2 Space 模型 + 持久化封装

- [ ] `core/space.dart` — `Space { name, ip, port, secret, lastSeenAt }` + JSON 序列化
- [ ] `core/secure_store.dart` — `SecureStore` 接口 + `AndroidSecureStore`（EncryptedSharedPreferences 实现）
- [ ] 接口方法：`Future<Space?> readCurrent()` / `Future<void> writeCurrent(Space)` / `Future<List<Space>> readAll()` / `Future<void> writeAll(List<Space>)` / `Future<void> remove(String name)`
- [ ] 单测：覆盖读空 / 读写单条 / 读写多条 / 删除

### T2.3 空间列表 UI

- [ ] `ProjectSwitcherView`（`/home/project-switcher`）改为展示持久化空间列表
- [ ] 列表项：当前空间置顶 + 名称 + IP:port + 「切换」按钮
- [ ] 「+ 添加空间」跳 `/connect` 重新扫码
- [ ] 长按 / 左滑 → 确认弹窗 → 删除（同步清持久化）

### T2.4 启动续连

- [ ] Splash 阶段读持久化 current space
- [ ] 调 health 验证（3s 超时）
- [ ] 成功 → 跳 `/home`（带 ip/port/secret 路由参数）
- [ ] 失败 → 跳 `/connect`（保留持久化项 + banner 提示「连不上 PC，工作空间保留」）

### T2.5 主页接真实 projects

- [ ] `HomeView` 从路由参数 / 持久化取 ip/port/secret
- [ ] `initState` 调 `projects_api.list` → 显示当前项目 + 其他项目
- [ ] Loading / Error / Empty 三态正确切换
- [ ] 下拉刷新重新拉取

### T2.6 扫码结果接持久化

- [ ] 扫码成功 + health 通过 → 根据 PC 端 `name` 查找持久化空间：
  - 找到 → 更新 ip/port/secret（覆盖原条目）
  - 没找到 → 视为新空间，追加
- [ ] 写持久化后跳 `/home`

### T2 验收

- [ ] 首次扫码 → 健康 → 写持久化 → 跳主页 → 主页显示真实 projects 列表
- [ ] 杀掉 App 重新启动 → 读持久化 → 自动 health 验证 → 直接进主页（不需再扫码）
- [ ] 持久化删一条空间 → 重启 App 不再出现
- [ ] 401 → banner 提示「PC 端密钥已重置，请重新扫码」
- [ ] 跨 PC 切换 → space 列表正确切换 active 项
- [ ] 同 `name` 同 `ip` 二次扫码 → 静默覆盖
- [ ] 同 `name` 不同 `ip` 二次扫码 → 覆盖 IP（视为同一 PC）
- [ ] 不同 `name` 二次扫码 → 新增空间

---

## T3 · 上传流程

### T3.1 Upload 客户端（直连真实 PC）

- [ ] `core/upload_api.dart` — `Stream<UploadProgress> upload({required String host, required int port, required String projectName, required String secret, required List<File> files, Duration perRequestTimeout = const Duration(seconds: 60)})`
- [ ] multipart 构造：单次请求最多 50 张，串行（按顺序）
- [ ] 进度流：`UploadProgress { sent, total }`（每文件上传完递增）
- [ ] 响应解析：`{ success, count, files[], failed[] }` → 返回结构化结果
- [ ] 客户端扩展名预过滤：`.jpg .jpeg .png .raw .avi .mp4 .mov .mkv .webm .m4v .mpg .mpeg`，不符合的放进 `failed[]` 不上传
- [ ] 单文件 500MB 限制检查（超过的放进 `failed[]` 不上传）
- [ ] 单测：`MockClient` 注入桩，覆盖 200/全部成功 / 200/部分失败 / 401 / 500 / 超时 / 扩展名过滤 / 500MB 过滤

### T3.2 Photo Picker

- [ ] `pubspec.yaml` 加 `image_picker`
- [ ] AndroidManifest 加图片读取权限（T3 引入）
- [ ] `HomeView`「上传」按钮 → 系统 Photo Picker → 选 1-50 张

### T3.3 上传进度 UI

- [ ] 主页底部 `LinearProgressIndicator` + 「已传 N/M」
- [ ] 完成弹 SnackBar 列出成功数 + 失败列表（含 reason 中文提示）

### T3 验收

- [ ] 主页点「上传」→ Photo Picker → 选图 → 进度条动 → 完成提示
- [ ] 选非白名单扩展名 → 不上传，进失败列表
- [ ] 选 50+ 张 → 截断到 50
- [ ] 上传中途 PC 断网 → 失败列表展示「上传超时，可重试」
- [ ] 上传成功后 PC 端项目文件数 +1（PC 端验证）

---

## T4 · 错误处理 + 状态机 + i18n + 端到端验收

### T4.1 错误总线收敛

- [ ] `AppError` 类型扩展：`NetworkError` / `HttpError` / `AuthError` / `QrError` / `UnknownError`
- [ ] `AppErrorBus.push(AppError)` → 顶部 banner 自动显示 + 用户可关闭
- [ ] 收敛 T1-T3 散落的 try/catch，全部走 `AppErrorBus`

### T4.2 状态机重整

- [ ] 状态：`未添加空间` / `待扫码` / `验证中` / `已连接` / `扫码失败` / `连接失败` / `上传中`
- [ ] 状态转移：splash 自动读持久化决定初始状态
- [ ] UI 反映：每个页面仅在合法状态出现

### T4.3 i18n

- [ ] `flutter_localizations` 加依赖
- [ ] 中文 strings 文件：`error.unauthorized` / `error.network` / `error.timeout` / `error.qr_invalid` / `error.pc_unreachable` / `error.qr_secret_expired` / `error.unknown` / 失败列表 reason
- [ ] 失败分桶 reason → 中文映射（KB §7.3）

### T4.4 端到端验收清单（KB §十八）

- [ ] 18.1 全部 13 项（首启/扫码/重连/401/切换 PC/30 天未用不自动清理/health 失败提示/failed 列表展示/进度条/扩展名预过滤/主页顶栏/删除空间同步清持久化）
- [ ] 18.2 跨端 6 项（QR 字段校验/扫码一次续连/PC 重启免扫/重置密钥触发 401/多 PC 切换/IP 变重扫码）
- [ ] §十六性能：扫码到进主页 ≤ 3s（含扫码识别 + health 验证）
- [ ] §十四边界：同名 PC、PC 改名、PC 端 `name` 含特殊字符等

### T4 验收

- [ ] 所有状态切换在 UI 上可观察
- [ ] 错误码全部走 i18n，中文显示正确
- [ ] `flutter analyze` + `flutter test` 全绿
- [ ] 手动 + Python mock server 跑通端到端

---

## 范围外（明确不做）

- ❌ UI 设计（无 design tokens / 无主题 / 无动效 / 无背景）
- ❌ 粘贴文本框、手动输入 IP、QR 兜底入口
- ❌ iOS / macOS 工程
- ❌ App 代码库内 mock 数据、mock 服务
- ❌ IP/Port 自动发现/订阅（第二期做）

## 交付物

1. `flutter/` 工程代码（含 T1-T4 全部测试）
2. 4 个 commit（每个 task 一个）：
   - `feat(flutter): T1 骨架 — 路由 + 4 页面 + 扫码 + QR 解析 + health 客户端`
   - `feat(flutter): T2 projects + 持久化 + 空间列表 + 启动续连`
   - `feat(flutter): T3 上传流程 — Photo Picker + multipart + 进度`
   - `feat(flutter): T4 错误处理 + 状态机 + i18n + 验收`

## 起手顺序

按 T1 → T2 → T3 → T4 顺序执行；每个 task 内 commit 可细分（如 T1 内拆「加依赖」「扫码页」「QR 解析」「health 客户端」「页面骨架」等）。