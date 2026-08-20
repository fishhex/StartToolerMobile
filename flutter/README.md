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

### 真机调试清单（仍「未发现 PC」时按此逐项排查）

**A. 系统层（用户手动）**

| 项 | 操作 |
|---|---|
| 1. 飞行模式 | 关闭；`adb shell settings get global airplane_mode_on` 应为 `0` |
| 2. VPN / 防火墙 | 关闭 AdGuard / NetGuard / SagerNet 等 |
| 3. 厂商后台保活 | 华为「启动管理→手动管理」、小米「自启动 + 关联启动」、OPPO「耗电保护关」、vivo「后台高耗电→允许」|
| 4. WiFi 随机 MAC | 设置→WiFi→当前网络→高级→MAC 地址→**使用设备 MAC** |
| 5. WiFi 省电模式 | 设置→WiFi→高级→关闭 |
| 6. WiFi 助理 / 智能切换 | 关闭（避免切到 4G 断 UDP） |

**B. 网络层（PC + Android 终端）**

```bash
# 1) PC 端跑 mock（与手机同 WiFi）
python3 scripts/pc_mock_broadcaster.py
# 2) 抓包验证 PC 端是否真的在广播
python3 scripts/smoke_m1.sh
# 3) Android 真机 logcat 看 UDP 链路
adb logcat -c && adb logcat | grep -E '\[MLOCK\]|\[UDP\]|\[ANNOUNCE\]|\[ADAPTER\]'
# 4) 确认 Android App bind 了 9876
adb shell cat /proc/net/udp | grep -i '2670'   # 9876 = 0x2694；查不到就是 socket 没起来
```

期望 logcat：`[MLOCK] native acquire returned=true` → `[UDP] RawDatagramSocket.bind success on 0.0.0.0:9876` → 2 s 后看到 `[UDP-RAW] recv 135B from <PC_IP>:<ephemeral>` → `[ANNOUNCE] parsed ... name="Hex-MacBook"` → `[UDP] new device added (key=Hex-MacBook|8765|<PC_IP>)`

**C. 常见故障对应表**

| 现象 | 原因 | 处理 |
|---|---|---|
| logcat 无 `[UDP]` | socket 没起来 | 检查 manifest 4 条权限 + MulticastLock 桥注册 |
| 有 `[UDP] bind success` 但无 `[UDP-RAW]` | 路由器 / 厂商拦截广播 | 关闭 WiFi 随机 MAC / 换路由器 / 关厂商防火墙 |
| 有 `[UDP-RAW]` 但无 `[ANNOUNCE]` | JSON 字段不匹配（snake_case vs camelCase）| 检查 PC 端是否输出 `currentProject` 而非 `current_project` |
| 列表出现又消失 | checklist #8「socket 没续命」| 当前实现已修：每次 scan 重置 sub + socket |
| 锁屏后再也收不到 | Doze 模式杀死 | 厂商白名单 + 后续 Foreground Service（M2+）|

### 冒烟脚本

```bash
bash scripts/smoke_m1.sh   # 监听 4s UDP :9876 抓包
```

### M1 验收

详细验收清单：[doc/0.10/spec/M1-task-list.md](../doc/0.10/spec/M1-task-list.md)。
实施规划：[doc/0.10/spec/M1-implementation-plan.md](../doc/0.10/spec/M1-implementation-plan.md)。