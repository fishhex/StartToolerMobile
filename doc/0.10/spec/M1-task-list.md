# M1 · 基础骨架（任务清单）

> 目标：从 Hello demo 进化到「可点击的 5 个页面 + QR 解析纯函数 + health 客户端 + projects 客户端直连 PC 端」。
> 平台：Android only（iOS/macOS 暂不考虑）。
> 上游：[v0.14-implementation-plan.md](./v0.14-implementation-plan.md) M1 行。

## 范围声明

- **UI**：Material 默认组件。无 design tokens、无自定义主题、无星空背景、无动效。
- **平台**：Android only。iOS 工程不生成、macOS 不考虑。
- **真实实现**：全部 HTTP 客户端直连 PC 端 `/api/v1/*`，**不使用 mock 数据**。测试用 `MockClient` 注入桩。

## 范围

### 1. 路由骨架（go_router）

- [ ] 添加依赖 `go_router`、`provider`、`http`（pubspec.yaml）
- [ ] 5 个路由：`/splash`、`/connect`（含 `/connect/manual` 子）、`/home`（含 `/home/project-switcher` 子）、`/settings`
- [ ] 路由守卫：splash 1.5s 后跳 `/connect`；连接后 `/connect` 系列重定向到 `/home`
- [ ] 顶层错误总线 `AppErrorBus`（Provider 注入，仅占位，M5 收敛）

### 2. 5 个页面骨架（Material 默认组件）

- [ ] `SplashView` — `Center` + `Text('StartTooler')` + `CircularProgressIndicator` + 1.5s 跳转
- [ ] `DiscoveryView`（`/connect`）— 倒计时 `Text` + 空列表占位 + 「手动输入 IP」按钮（M3 再改为「粘贴 QR 内容」）
- [ ] `ManualInputView`（`/connect/manual`）— 三个 `TextField`（IP + Port + secret）+ 「连接」按钮（直接调 health 验证）
- [ ] `UploadView`（`/home`）— `Scaffold` + `AppBar(空间名)` + 当前项目 `Card` + 其他项目 `ListView` + 「切换项目」/「上传」按钮（M4 接 Photo Picker）
- [ ] `ProjectSwitcherView`（`/home/project-switcher`）— 空间列表（M1 暂时内存里硬编码一个「当前空间」，M2 接入持久化）+ `+ 添加空间` 占位
- [ ] `SettingsView`（`/settings`）— 三个 `ListTile` 分组（PC / 缓存 / 关于）

### 3. QR 解析（纯函数 + 单测）

- [ ] `core/qr_parser.dart` — 输入字符串，输出 `QrPayload { host, port, secret } | QrError`
- [ ] 校验：IPv4、port 1-65535、path == `/upload`、secret `\A[a-f0-9]{32}\z`
- [ ] 单测覆盖：合法 URL / IPv6 / port 越界 / secret 长度错 / 非 http 协议 / 缺 `?k=` / 多 `?k=` 取首个
- [ ] 错误类型 `QrError.invalidFormat` / `QrError.invalidHost` / `QrError.invalidPort` / `QrError.missingSecret`

### 4. Health 客户端（直连真实 PC）

- [ ] `core/health_api.dart` — `Future<Result<Health, AppError>> check(String host, int port, {Duration timeout = const Duration(seconds: 3)})`
- [ ] `Health` 模型：`{ name, version, port, secret, currentProject }`
- [ ] 网络层：纯 `http.get('http://{host}:{port}/api/v1/health')`，无鉴权，3s 超时
- [ ] 错误映射：`SocketException → NetworkError.unreachable` / `TimeoutException → NetworkError.timeout` / `4xx/5xx → HttpError(status)`
- [ ] 单测：`MockClient` 注入桩，覆盖 200 / 404 / 500 / 超时 / DNS 失败

### 5. Projects 客户端（直连真实 PC）

- [ ] `core/projects_api.dart` — `Future<Result<List<Project>, AppError>> list(String host, int port, String secret, {Duration timeout = const Duration(seconds: 3)})`
- [ ] `Project` 模型：`{ name, isCurrent, fileCount, sizeBytes }`
- [ ] 网络层：`http.get('http://{host}:{port}/api/v1/projects?k={secret}')`，3s 超时
- [ ] 错误映射：复用 §4 的网络/超时/4xx/5xx 映射，额外 401 → `AuthError.expired`
- [ ] 单测：`MockClient` 注入桩，覆盖 200 / 401 / 500 / 超时

### 6. 主页接真实 projects

- [ ] `UploadView` 接收 `host` / `port` / `secret` 参数（M2 改从持久化读）
- [ ] `initState` 调 `projects_api.list` → 显示当前项目 + 其他项目
- [ ] Loading / Error / Empty 三态正确切换（用 `AppErrorBus` 顶部 banner）
- [ ] 下拉刷新重新拉取

### 7. 单元/Widget 测试

- [ ] `test/qr_parser_test.dart` — QR 解析覆盖（见 §3）
- [ ] `test/health_api_test.dart` — health 客户端覆盖（见 §4）
- [ ] `test/projects_api_test.dart` — projects 客户端覆盖（见 §5）
- [ ] `test/widget_test.dart` — 5 个页面骨架可启动 + 渲染首屏

## 验收（§十八最小子集）

- [ ] App 启动 1.5s 后进入 `/connect`，显示「手动输入 IP」按钮
- [ ] 「手动输入 IP」页输入 IP/Port/secret 后点击「连接」能调通真实 PC health
- [ ] `/home` 页面顶栏显示 health 响应里的 PC 端 `name`
- [ ] `/home` 显示 `/api/v1/projects` 返回的项目列表（当前项目优先）
- [ ] health 401 → 顶部 banner 提示「PC 端密钥已重置，请重新扫码」
- [ ] health 超时 → 顶部 banner 提示「PC 不可达」
- [ ] `/home/project-switcher` 显示一个占位空间（M2 接持久化）
- [ ] `/settings` 三个分组（PC / 缓存 / 关于）渲染正确
- [ ] `flutter analyze` 通过（无 warning）
- [ ] `flutter test` 通过（QR + health + projects + widget 四套）
- [ ] 手动跑 `flutter run -d <android>`，APK 可启动，5 个页面可跳转

## 联调要求（开发期）

- PC 端 v0.14 服务运行；或本地 Python `aiohttp` mock server 实现三端点（`/api/v1/health` + `/api/v1/projects` + `/api/v1/projects/{name}/upload`）。
- 该 mock server 仅作为开发联调工具，**不进 App 代码库**（不进 git）。

## 范围外（明确不做）

- ❌ 自定义 UI 主题 / design tokens / 星空背景 / 动效
- ❌ 真相机扫码（M3 改为粘贴文本框）
- ❌ 持久化（M2）
- ❌ 真实 PC QR 联调（M3/M7）
- ❌ 上传流程（M4）
- ❌ iOS / macOS 工程
- ❌ 完整错误码 i18n（M5）
- ❌ App 代码库内的 mock 数据、mock 服务

## 交付物

1. `flutter/` 工程代码（含测试）
2. 提交 commit：`chore(flutter): M1 基础骨架 — 路由 + 5 页面 + QR 解析 + health/projects 客户端`
3. 简短的"实施记录"段落追加到本文件末尾（commit 里写）

## 起手顺序建议

1. 加依赖 + 路由骨架 + Material 默认主题
2. 5 个空页面（先 splash + connect + home，settings 和 project-switcher 后补）
3. QR 解析（纯函数先写完，独立可测）
4. Health 客户端 + 单测
5. Projects 客户端 + 单测
6. 主页接真实 projects（Loading/Error/Empty 三态）
7. Settings 完整化 + Widget 测试
8. `flutter analyze` + `flutter test` 全跑一遍

预计 commit 数量：5-8 个（每个起手步骤一个），按主题分。