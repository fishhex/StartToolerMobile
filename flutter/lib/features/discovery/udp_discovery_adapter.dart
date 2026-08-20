// lib/features/discovery/udp_discovery_adapter.dart
//
// 把 UdpAnnounce（UDP 协议层）适配成现有 DiscoveryService 接口。
//
// 兼容策略：
//   - 保持 DiscoveryService.scan 签名不变，UI 层无感升级。
//   - UdpAnnounce 里没有 project_count / rssi，先用占位值（-1 / 0），
//     等真实 /api/v1/projects 接通后再补（D05 §11.6 待定）。
//   - 缓存 key：与 udp_discovery_service 一致使用 announce.dedupeKey
//     （name + port + ip 三元组，D01 §3.5）。
//
// D03 接入：
//   - 收到每个 announce → 无条件把 token 写入 TokenStore（D03 §3.1 权威源）
//   - 同 name+port 视为同一 PC，IP 浮动时按 D03 §3.5 覆盖
//
// 联调日志：[ADAPTER] 前缀。

import 'dart:async';

import '../../core/mock/seed_data.dart';
import '../../core/token.dart';
import 'discovery_service.dart';
import 'udp_announce.dart';
import 'udp_discovery_service.dart';
import 'udp_log.dart';

class UdpDiscoveryAdapter implements DiscoveryService {
  UdpDiscoveryAdapter(this._udp, {TokenStore? tokenStore})
      : _tokenStore = tokenStore;

  final UdpDiscoveryService _udp;

  /// 可选：注入 TokenStore 把广播 token 推入（D03 §3.1 权威源）。
  /// 未注入时仅走发现路径，不写 token。
  final TokenStore? _tokenStore;

  // 临时缓存：announce.dedupeKey -> 已发现的 PC（供后续合并 projectCount 用）。
  final Map<String, PC> _cache = {};

  @override
  Future<List<PC>> scan({
    required OnPCDiscovered onDiscovered,
  }) async {
    UdpLog.adapter('scan() called');
    final result = await _udp.scan(
      window: discoveryWindow,
      onAnnounce: (UdpAnnounce announce) {
        // 不识别版本 → 跳过，但通过 UI 提醒用户（D04 §7 / D05 §9.3）
        if (!announce.isCompatibleVersion) {
          UdpLog.adapter('skip announce from ${announce.ip} '
              '(incompatible version=${announce.version})');
          return;
        }

        // D03 §3.1 / §3.5：UDP 广播是 token 的唯一权威源；
        // 每次收到广播都无条件把 token 写入 TokenStore（覆盖式更新）。
        final t = Token.tryParse(announce.token);
        if (t != null && _tokenStore != null) {
          _tokenStore.register(ConnectedPC(
            name: announce.name,
            ip: announce.ip,
            port: announce.port,
            token: t,
            currentProject: announce.currentProject,
          ));
        }

        final pc = PC(
          name: announce.name,
          ip: announce.ip,
          port: announce.port,
          // 当前 UDP 包未携带 project_count，先占位为 0。
          // 真实实现里会在 /api/v1/projects 返回后回填。
          projectCount: 0,
          currentProject: announce.currentProject,
          // UDP 协议层未携带 RSSI，给一个默认值。
          // 多网卡/同子网情形下 RSSI 排序意义不大，这里按发现顺序即可。
          rssi: -100,
        );
        _cache[announce.dedupeKey] = pc;
        UdpLog.adapter('emit PC name="${pc.name}" '
            'addr=${pc.displayAddress} currentProject=${pc.currentProject} '
            'token=${t?.masked ?? "<invalid>"}');
        onDiscovered(pc);
      },
    );

    // 去重 + 按 name 排序（保持稳定顺序，便于 UI 渲染）。
    final pcs = <PC>[];
    for (final a in result.devices) {
      if (!a.isCompatibleVersion) {
        UdpLog.adapter('final list skip ${a.ip} (incompatible version)');
        continue;
      }
      pcs.add(
        PC(
          name: a.name,
          ip: a.ip,
          port: a.port,
          projectCount: 0,
          currentProject: a.currentProject,
          rssi: -100,
        ),
      );
    }
    pcs.sort((x, y) => x.name.compareTo(y.name));
    UdpLog.adapter('scan() returning ${pcs.length} PCs: '
        '${pcs.map((p) => "${p.name}@${p.ip}").toList()}');
    return pcs;
  }

  @override
  void simulateOffline() {
    // 真实 UDP 没有 mock 开关；保留接口签名便于上层兼容。
    // 物理层断网由系统 socket error 体现。
    UdpLog.adapter('simulateOffline() called (no-op for real UDP)');
  }
}
