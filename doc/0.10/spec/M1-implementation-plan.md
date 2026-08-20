# M1 · 实施代码规划（Implementation Plan）

> **范围**：M1 里程碑（[M1-task-list.md](M1-task-list.md)）— 真实 UDP Discovery
> **关联**：[spec/05-mobile-app.md §七 M1](05-mobile-app.md#七实施计划plan--分阶段交付) / [demand/D01](../demand/demand/D01-udp-discovery.md) / [demand/D05](../demand/demand/D05-platform-permissions.md)
> **基准日**：2026-08-20
> **关键原则**：每条任务都给出 **「现状盘点」** + **「改动点」** + **「代码片段」**；已有代码不重写，仅补缺 / 修缺

---

## 〇、现状盘点（实施前必读）

> 节省工时：M1 七个子任务中，**6 项已实质实现**，T-M1-7 单元测试由开发者自行 debug 验证（不入本规划）；本规划仅聚焦 **Android**（T-M1-4 iOS 暂缓）。

| T-M1-N | 任务 | 现状 | 增量 |
|---|---|---|---|
| **T-M1-1** | `UdpAnnounce.tryParse` 校验补全 | ✅ 已实现 service / port / name / token / currentProject；version 仅 major ≥ "0" 校验（非严格 v0.12） | 0 改动 |
| **T-M1-2** | DiscoveryView 接入 UDP | ✅ `UdpDiscoveryAdapter` 已实现；`main.dart` 默认走 `UdpDiscoveryAdapter` | 移除 mock 演示开关，验证 `udp_discovery_adapter.dart` 路径全通 |
| **T-M1-3** | 手动输入兜底页 | 🟡 `_ManualIPSheet` 已实现但只输入 IP，缺 Port / Token | 升级为完整 `ManualInputView`（IP + Port + Token 三字段） |
| **T-M1-4** | iOS Info.plist | ⏸️ 暂缓（聚焦 Android） | — |
| **T-M1-5** | Android Manifest + `network_security_config` | ✅ 已完整（INTERNET / ACCESS_NETWORK_STATE / ACCESS_WIFI_STATE / CHANGE_WIFI_MULTICAST_STATE + cleartextTrafficPermitted=true + 5 段私有 IP） | 0 改动（**已通过 P10/P12 验收**） |
| **T-M1-6** | Android MulticastLock 原生桥 | ✅ `MainActivity.kt` 已实现 `acquire` / `release` + `MulticastLockChannel.dart` Dart 端封装 | 在 `DiscoveryView.initState / dispose` 调用 acquire / release |
| **T-M1-7** | `UdpAnnounce.tryParse` 单元测试 | ⏭️ 由开发者自行 debug 验证 | — |

> **节省工时**：4 d → **实际 0.9 d**（仅 T-M1-3 升级 + T-M1-2 简化 + T-M1-6 联动 + Android 真机验证回归）。

---

## 一、目录结构（实施后）

```
flutter/
├── android/                                ← 已有，0 改动
│   └── app/src/main/
│       ├── AndroidManifest.xml               ← 已含 4 条权限
│       ├── kotlin/.../MainActivity.kt     ← 已含 multicast_lock 桥
│       └── res/xml/network_security_config.xml  ← 已配 cleartext
├── lib/
│   ├── features/
│   │   ├── discovery/                      ← 已有，0 改动
│   │   │   ├── udp_announce.dart
│   │   │   ├── udp_discovery_service.dart
│   │   │   ├── udp_discovery_adapter.dart
│   │   │   ├── multicast_lock_channel.dart
│   │   │   ├── udp_log.dart
│   │   │   └── discovery_view.dart         ← 改：手动输入跳新页 + initState/dispose 联动 MulticastLock
│   │   └── connection/
│   │       └── manual_input_view.dart       ← T-M1-3 新增
│   └── main.dart                           ← T-M1-2 移除 mock 演示
├── scripts/
│   ├── pc_mock_broadcaster.py              ← 已存在
│   └── smoke_test.sh                       ← 新增：冒烟脚本
└── README.md                               ← 改：M1 进度 + 限制说明（仅 Android）
```

---

## 二、T-M1-3 · `ManualInputView`（升级手动输入页）

### 2.1 现状问题

`discovery_view.dart` 内 `_ManualIPSheet` 只输入 IP，缺：

- Port（默认 8765，但 PC 端可配置）
- Token（首次 / 重置场景需用户手输）

### 2.2 文件改动

| 操作 | 文件 | 行数预估 |
|---|---|---|
| 新建 | `flutter/lib/features/connection/manual_input_view.dart` | ~150 行 |
| 修改 | `flutter/lib/features/discovery/discovery_view.dart` | -10 / +5 行 |
| 修改 | `flutter/lib/app/router.dart` | +8 行 |

### 2.3 代码：`manual_input_view.dart`

```dart
// lib/features/connection/manual_input_view.dart
//
// T-M1-3 · 手动输入兜底页（IP + Port + Token）
// 触发场景：扫描 5s 无设备 / 用户主动「手动输入」按钮。
// M1 阶段允许复用 mock ConnectionMock；M2 接入真实 /api/v1/health。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/mock/seed_data.dart';
import '../../ui/tokens/colors.dart';
import '../../ui/tokens/spacing.dart';
import '../../ui/tokens/typography.dart';
import '../../ui/components/buttons.dart';

class ManualInputView extends StatefulWidget {
  const ManualInputView({super.key, this.initialIp});
  final String? initialIp;

  @override
  State<ManualInputView> createState() => _ManualInputViewState();
}

class _ManualInputViewState extends State<ManualInputView> {
  late final TextEditingController _ip;
  late final TextEditingController _port;
  late final TextEditingController _token;

  String? _errIp;
  String? _errPort;
  String? _errToken;

  @override
  void initState() {
    super.initState();
    _ip = TextEditingController(text: widget.initialIp ?? '192.168.1.');
    _port = TextEditingController(text: '$defaultHttpPort');
    _token = TextEditingController();
  }

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  // 简单 IPv4 校验（不要求合法性极严，宽松即可）。
  bool _isValidIp(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  bool _isValidPort(String s) {
    final n = int.tryParse(s);
    return n != null && n > 0 && n <= 65535;
  }

  bool _isValidToken(String s) => RegExp(r'^\d{6}$').hasMatch(s);

  void _submit() {
    setState(() {
      _errIp = _isValidIp(_ip.text.trim())
          ? null
          : 'IP 格式错误（例 192.168.1.10）';
      _errPort = _isValidPort(_port.text.trim())
          ? null
          : '端口范围 1-65535';
      _errToken = _isValidToken(_token.text.trim())
          ? null
          : 'Token 为 6 位数字';
    });
    if (_errIp != null || _errPort != null || _errToken != null) return;

    // 走 TokenInputView 流程：携带 ip + name（手动输入无 name）。
    context.push(
      '/connect/token',
      extra: {
        'ip': _ip.text.trim(),
        'port': int.parse(_port.text.trim()),
        'name': '手动输入',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.space900,
      appBar: AppBar(title: const Text('手动输入')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                label: 'IP 地址',
                controller: _ip,
                hint: '192.168.1.10',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                error: _errIp,
              ),
              const SizedBox(height: AppSpace.md),
              _field(
                label: '端口',
                controller: _port,
                hint: '$defaultHttpPort',
                keyboardType: TextInputType.number,
                error: _errPort,
              ),
              const SizedBox(height: AppSpace.md),
              _field(
                label: 'Token（PC 端 6 位数字）',
                controller: _token,
                hint: '123456',
                keyboardType: TextInputType.number,
                obscureText: true,
                error: _errToken,
                maxLength: 6,
              ),
              const SizedBox(height: AppSpace.lg),
              PrimaryButton(label: '连接', onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required TextInputType keyboardType,
    String? error,
    bool obscureText = false,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyle.bodySm),
        const SizedBox(height: AppSpace.xs),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLength: maxLength,
          inputFormatters: maxLength != null
              ? [LengthLimitingTextInputFormatter(maxLength)]
              : null,
          style: AppTextStyle.titleMd.copyWith(color: AppColors.star100),
          decoration: InputDecoration(
            hintText: hint,
            errorText: error,
            filled: true,
            fillColor: AppColors.space700,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
```

### 2.4 代码：`router.dart` 新增路由

```dart
// lib/app/router.dart — 增量改动
import '../features/connection/manual_input_view.dart'; // ← 新增

// 在 routes 列表的 /connect 下追加：
GoRoute(
  path: 'manual',
  builder: (ctx, state) {
    final extra = state.extra as Map<String, String>?;
    return ManualInputView(initialIp: extra?['ip']);
  },
),
```

### 2.5 代码：`discovery_view.dart` 改动

把 `_showManualInput` 替换为跳转新路由（移除 `_ManualIPSheet` 整段类）：

```dart
// lib/features/discovery/discovery_view.dart
// 改动：_showManualInput() 改为跳转独立路由。
Future<void> _showManualInput() async {
  context.push('/connect/manual');
}
// 删除：_ManualIPSheet / _ManualIPSheetState 类（约 90 行）。
```

### 2.6 验收（与 DoD 对应）

- [ ] `ManualInputView` 接 `go_router` `/connect/manual`
- [ ] IP / Port / Token 三字段独立校验
- [ ] 提交后跳 `/connect/token`，extra 携带 `ip / port / name`
- [ ] `discovery_view.dart` 扫描 5 s 无设备 → 「手动输入 IP」按钮（保持）
- [ ] `_ManualIPSheet` 旧代码删除

---


## 三、T-M1-2 · `main.dart` 移除 mock 演示

### 3.1 现状

`main.dart` 含 `_kUseMock` 编译开关（演示用），默认 false。仍保留编译入口。

### 3.2 文件改动

| 操作 | 文件 |
|---|---|
| 修改 | `flutter/lib/main.dart` |

### 3.3 代码片段

```dart
// lib/main.dart — 改动：移除 mock 演示开关（保留 v1.0 实验通道）
//
// 实施后：默认走 v0.12 真实 UDP；v1.0 移到 PROTO=v1 显式打开。
const String _kProto = String.fromEnvironment('PROTO', defaultValue: 'v0');

DiscoveryService _buildDiscovery() {
  switch (_kProto) {
    case 'v1':
      return V1DiscoveryAdapter(DiscoverServiceV1()); // 实验通道
    case 'v0':
    default:
      return UdpDiscoveryAdapter(UdpDiscoveryServiceImpl());
  }
}
// 删除：_kUseMock / DiscoveryMock / 'USE_MOCK' define
```

---

## 四、T-M1-6 · AppLifecycleObserver 联动 MulticastLock

### 4.1 现状

`MulticastLockChannel.acquire()` / `release()` 已实现，但**没有任何调用方**。

### 4.2 接入位置

`MainActivity.kt` 已实现 acquire；Dart 侧需要在 `DiscoveryView.initState` 调 `acquire`、`dispose` 调 `release`。

### 4.3 文件改动

| 操作 | 文件 |
|---|---|
| 修改 | `flutter/lib/features/discovery/discovery_view.dart` |

### 4.4 代码片段

```dart
// discovery_view.dart initState：
@override
void initState() {
  super.initState();
  AppState.stage = AppStage.disconnected;
  UdpLog.view('initState → acquire MulticastLock + startScan');
  // T-M1-6 联动：扫描前 acquire MulticastLock（仅 Android 有效，其他平台 noop）。
  MulticastLockChannel.instance.acquire();
  _startScan();
}

// dispose：
@override
void dispose() {
  UdpLog.view('dispose → release MulticastLock + cancel timers');
  _ticker?.cancel();
  _countdown?.cancel();
  // T-M1-6 联动：释放锁。
  MulticastLockChannel.instance.release();
  super.dispose();
}
```

---

## 五、辅助产物

### 5.1 `scripts/smoke_test.sh`（冒烟脚本）

```bash
#!/usr/bin/env bash
# scripts/smoke_test.sh — M1 端到端冒烟
# 前置：PC mock 启动；App 未启动；tcpdump 可用。
set -euo pipefail

PORT="${PORT:-9876}"
LOG_DIR="${LOG_DIR:-./.smoke}"
mkdir -p "$LOG_DIR"

echo "[1/4] 启动 tcpdump 监听 9876..."
tcpdump -i any -n udp port "$PORT" -A -w "$LOG_DIR/udp.pcap" &
TCPDUMP_PID=$!
sleep 1

echo "[2/4] 启动 PC mock..."
python3 scripts/pc_mock_broadcaster.py > "$LOG_DIR/mock.log" 2>&1 &
MOCK_PID=$!
sleep 6
kill $MOCK_PID 2>/dev/null || true
kill $TCPDUMP_PID 2>/dev/null || true
wait 2>/dev/null || true

echo "[3/4] 验证 UDP 抓包..."
PACKETS=$(tcpdump -r "$LOG_DIR/udp.pcap" 2>/dev/null | wc -l | tr -d ' ')
echo "  抓到 $PACKETS 个 UDP 包（期望 ≥ 2）"
if [ "$PACKETS" -lt 2 ]; then
  echo "  ❌ UDP 包数不足"
  exit 1
fi

echo "[4/4] 验证 mock JSON 内容..."
if grep -q '"service":"starttooler"' "$LOG_DIR/mock.log"; then
  echo "  ✅ JSON 含 service=starttooler"
else
  echo "  ❌ 未找到 service=starttooler"
  exit 1
fi

echo ""
echo "✅ Smoke 通过"
```

### 5.2 `flutter/README.md`（最小改动）

替换默认内容为：

```markdown
# starttooler_mobile（Flutter App 端）

> 移动端 App — 与 PC v0.12 星助对接（UDP 发现 + HTTP 上传）。

## 进度

| Milestone | 状态 |
|---|---|
| M1 真实 UDP Discovery | ✅ |
| M2 Connection + Token 状态机 | ⬜ |
| M3 Project + Upload | ⬜ |
| M4 Offline + 错误兜底 | ⬜ |

## 限制

- **Android 后台限制**：华为 / 小米 / OPPO 等品牌需手动将 App 加入「自启动」+「电池优化白名单」。
- **App 不在后台持续监听**：Android 系统会暂停 UDP socket；回到前台立即重置计时并重扫。

## 开发

```bash
# PC 端 mock（联调必备）
python3 scripts/pc_mock_broadcaster.py

# 单元测试
flutter test

# 运行（默认走 v0.12 真实 UDP）
flutter run
flutter run --dart-define=PROTO=v1   # 实验通道
```

## 自测（详见 ../doc/0.10/spec/M1-task-list.md）

M1 范围仅 Android：A1-A8 / P10-P13 / C2-Android / T1-T4 / D1-D3。iOS 验收 P1-P9 / P7-P9 留待 iOS 计划阶段。
```

---

## 六、实施顺序（修订）

| 步骤 | 内容 | 工时 | 依赖 |
|---|---|---|---|
| 1 | T-M1-3 升级手动输入页（建 `ManualInputView` + router + discovery_view 改动） | 0.5 d | — |
| 2 | T-M1-2 简化 `main.dart`（移除 mock） | 0.1 d | — |
| 3 | T-M1-6 联动 MulticastLock（initState / dispose 调用） | 0.1 d | — |
| 4 | smoke 脚本 + README 更新（仅 Android 范围） | 0.1 d | 步骤 1-3 |
| 5 | Android 真机回归（A1-A8 / P10-P13 / C2-Android） | 0.1 d | 步骤 1-4 |

**总工时**：约 0.9 d（从原 4.5 d 节省约 80%；iOS 验收 P1-P9 暂缓）。

---

## 七、合并前 checklist

- [ ] T-M1-1 `UdpAnnounce.tryParse` 已有实现无回归（手动 debug 验证）
- [ ] T-M1-2 `main.dart` 移除 mock 演示
- [ ] T-M1-3 `ManualInputView` 三字段提交 + 跳转
- [ ] T-M1-5 Android Manifest + cleartext 已就位（0 改动，仅校验）
- [ ] T-M1-6 MulticastLock 在 initState / dispose 调用
- [ ] `flutter analyze` 无 error
- [ ] smoke 脚本抓包验证 UDP 包 ≥ 2
- [ ] README 更新 M1 进度 + Android 限制说明
- [ ] git tag: `m1-discovery-complete`

---

## 八、变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-08-20 | v0.1 | 初稿生成；盘点显示 M1 大部分已实现，工时从 4.5d 降到 2.4d |
| 2026-08-20 | v0.2 | 移除 T-M1-7 单元测试章节（开发者自行 debug 验证）；工时从 2.4d 降到 1.9d |
| 2026-08-20 | v0.3 | 移除 T-M1-4 iOS（聚焦 Android）；工时从 1.9d 降到 0.9d；iOS 验收 P1-P9 / P7-P9 暂缓 |