# 第二期 · IP/端口变更重扫码更新（任务清单）

> 目标：PC 端 IP/端口变化后，App 端引导用户重新扫码，写持久化覆盖原条目。
> 平台：Android only（iOS/macOS 暂不考虑）。
> 上游：[v0.14-implementation-plan.md](./v0.14-implementation-plan.md) 第二期。

## 范围声明

- **UI**：不考虑设计。沿用第一期朴素 Material。
- **真实实现**：直连 PC 端真实 HTTP 接口，无 mock。
- **触发场景**：PC 端换网络 / 改端口 / 重启后 IP 变化（KB §六 IP 变 / Port 变）。

## 任务拆分

| Task | 主题 | 前置 |
| --- | --- | --- |
| **T5** | IP/Port 变更后重扫码更新 | 第一期 T1-T4 全部完成 |

---

## T5 · IP/Port 变更后重扫码更新

### 触发场景（KB §六）

| 场景 | 行为 |
| --- | --- |
| PC 端换网络 → 新 IP | App 端 health 失败 → 引导重扫码 |
| PC 端改端口 | 同上 |
| PC 端重启 → IP 可能变 | 同上 |
| PC 端密钥重置 | 401 → 提示「密钥已重置，请重新扫码」（v0.14 极少触发，保留持久化项） |

> T5 专注于「IP/Port 变」场景；密钥重置沿用第一期 T4 的 401 处理。

### T5.1 启动健康检查（已是第一期 T2.4）

- [ ] Splash 阶段调 health 验证当前 space
- [ ] 失败（`NetworkError.unreachable` / `TimeoutException` / 5xx）→ 跳 `/connect`，banner 提示「连不上 PC，工作空间保留」
- [ ] 401 → banner 提示「PC 端密钥已重置，请重新扫码」（保留持久化项，等用户主动重扫）

### T5.2 上传前健康检查（新增）

- [ ] `upload_api.upload` 之前先调一次 `health_api.check`
- [ ] 健康成功 → 继续上传
- [ ] 健康失败 → 弹窗「PC 网络信息已变更，请重新扫码」+ 跳 `/connect`

### T5.3 重扫码后写持久化覆盖

- [ ] `/connect` 粘贴新 QR 内容 → QR 解析 → health 验证
- [ ] 验证成功 → 根据 PC 端 `name` 查找持久化空间：
  - 找到 → 更新 ip/port/secret（覆盖原条目）
  - 没找到 → 视为新空间，追加
- [ ] 写持久化后跳 `/home`

### T5.4 边界（KB §十四）

- [ ] 同 `name` 同 `ip` 二次扫码 → 静默覆盖（重启场景）
- [ ] 同 `name` 不同 `ip` 二次扫码 → 视为同一 PC（覆盖 IP）
- [ ] 不同 `name` 二次扫码 → 新增空间（多 PC）
- [ ] PC 端改名 → `name` 变 → App 视为新空间（保留旧条目，等用户手动删）

### T5 验收

- [ ] 模拟 PC 端换 IP（修改路由器/PC 网络）→ App 端启动 → 自动跳 `/connect` + banner 提示
- [ ] 在 `/connect` 粘贴新 QR → 解析 → health → 写持久化（覆盖原 IP）→ 跳主页
- [ ] 健康重连后，上传功能正常工作
- [ ] 同名 PC 重启 IP 不变 → 健康成功，无感知
- [ ] 多 PC 切换 → 持久化空间列表正确管理
- [ ] PC 改名 → App 视为新空间（不覆盖旧条目）

## 范围外（明确不做）

- ❌ UI 设计改进
- ❌ 网络变化自动监听（KB §6.2 明令不做：❌ App 端订阅网络事件）
- ❌ mDNS / Bonjour 自动发现
- ❌ App 端主动轮询 / 探测
- ❌ iOS / macOS

## 交付物

1. `flutter/` 工程代码增量（含测试）
2. 1 个 commit：
   - `feat(flutter): T5 IP/Port 变更重扫码更新 — 上传前健康检查 + 覆盖写持久化`

## 起手顺序

1. T5.2 上传前 health 探活（必做）
2. T5.3 重扫码覆盖写持久化（必做）
3. T5.4 边界用例测试
4. T5.1 启动健康检查已由 T2.4 实现，T5 只需补 banner 文案