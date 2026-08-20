# starttooler_mobile

Flutter 移动端（M0 → M4 渐进实现）。当前进度：**M1 真实 UDP Discovery 已完成**。

## 当前里程碑：M1（真实 UDP 发现）

按 PC v0.12 协议监听 UDP `9876`，过滤 `service=startooler-pc`，5 s 窗口去重。

### 运行

```bash
# 1. PC 端启动 mock 广播（与手机同 WiFi）
python3 scripts/pc_mock_broadcaster.py

# 2. Android 真机运行（默认走 PC v0.12 协议）
flutter run
```

### 完整流程自测

1. **扫描**：打开 App，自动进入 `/connect`，启动 UDP 监听。
2. **发现**：PC mock 启动 → 1-3 s 内设备列表出现「Mock-PC」。
3. **手动输入**：5 s 无设备 → 点击「手动输入 IP」→ 三字段（IP + Port + Token）→ 校验 → 跳 `/connect/token`。
4. **MulticastLock**：Android 真机进入 / 离开发现页，`adb logcat | grep MulticastLock` 应见 acquire / release。

### 限制

- **仅 Android**：本里程碑不含 iOS 工程（`flutter/ios/` 暂未生成；P1-P9 验收留待后续阶段）。
- **后台限制**：华为 / 小米 / OPPO 需手动加入「自启动」+「电池优化白名单」。
- **App 不在后台持续监听**：离开发现页即释放 MulticastLock，回到前台重新扫描。

### 冒烟脚本

```bash
bash scripts/smoke_m1.sh   # 监听 4s UDP :9876 抓包
```

### M1 验收

详细验收清单：[doc/0.10/spec/M1-task-list.md](../doc/0.10/spec/M1-task-list.md)。
实施规划：[doc/0.10/spec/M1-implementation-plan.md](../doc/0.10/spec/M1-implementation-plan.md)。