// lib/features/discovery/udp_announce.dart
//
// UDP 广播包数据模型 —— 严格对齐 D04 §3.1.1 的 PC 端 JSON 协议。
//
//   {
//     "service": "starttooler",
//     "version": "0.12",
//     "name": "Hex-MacBook",
//     "port": 8765,
//     "token": "123456",
//     "currentProject": "deepsky-2025"   // 可空字符串
//   }

import 'dart:convert';

import 'udp_log.dart';

/// PC 端在 9876 端口广播的 announce 包。
class UdpAnnounce {
  const UdpAnnounce({
    required this.name,
    required this.ip,
    required this.port,
    required this.token,
    required this.version,
    required this.currentProject,
  });

  /// 机器名（PC 端 Environment.MachineName）。
  final String name;

  /// 发送方 IP（来自 Datagram 自身的 sender.address）。
  final String ip;

  /// PC HTTP 服务端口。
  final int port;

  /// 6 位数字 token。
  final String token;

  /// 协议版本，例如 "0.12"。
  final String version;

  /// 当前激活项目；null 表示 PC 未打开任何项目。
  final String? currentProject;

  /// 去重 key：D01 §3.5 要求「同 LAN 多台 PC 可能重名；用 `name + port + ip`
  /// 三元组去重，IP 视为浮动（同 name + port 不同 IP 视为同一设备）」。
  /// 使用 `|` 分隔避免 name 自身含 `|` 时撞键（罕见但理论上可能）。
  String get dedupeKey => '$name|$port|$ip';

  /// 仅识别主版本号相同或更新的协议。
  /// D05 §9.3：App 端看到 version 不识别 → 提示升级 PC 端。
  static const String minSupportedMajor = '0';

  bool get isCompatibleVersion {
    // 简单策略：major 段 >= minSupportedMajor 即视为兼容。
    final segs = version.split('.');
    if (segs.isEmpty) return false;
    final major = int.tryParse(segs[0]) ?? -1;
    return major >= int.parse(minSupportedMajor);
  }

  /// 从 Datagram 收到的 JSON 文本反序列化。
  /// 失败（含 service 不匹配 / 字段缺失 / 类型错）返回 null 并打印原因。
  static UdpAnnounce? tryParse(String json, {required String senderIp}) {
    Object? jsonErr;
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) {
        jsonErr = 'top-level not object (${decoded.runtimeType})';
      } else {
        map = decoded;
      }
    } catch (e) {
      jsonErr = e;
    }

    if (map == null) {
      UdpLog.announce('tryParse rejected (json decode failed) sender=$senderIp'
          ' err=$jsonErr');
      return null;
    }

    if (map['service'] != 'starttooler') {
      UdpLog.announce('tryParse rejected (service != starttooler, '
          'got=${map['service']}) sender=$senderIp');
      return null;
    }

    final portRaw = map['port'];
    final port = portRaw is num ? portRaw.toInt() : null;
    if (port == null || port <= 0 || port > 65535) {
      UdpLog.announce('tryParse rejected (invalid port=$portRaw) '
          'sender=$senderIp');
      return null;
    }

    final nameRaw = map['name'];
    final name = nameRaw is String ? nameRaw.trim() : '';
    if (name.isEmpty) {
      UdpLog.announce('tryParse rejected (empty name=$nameRaw) '
          'sender=$senderIp');
      return null;
    }

    final tokenRaw = map['token'];
    final token = tokenRaw is String ? tokenRaw.trim() : '';
    if (token.length != 6) {
      UdpLog.announce('tryParse rejected (token length '
          '${token.length} != 6, raw=$tokenRaw) sender=$senderIp');
      return null;
    }

    final versionRaw = map['version'];
    final version = versionRaw is String && versionRaw.trim().isNotEmpty
        ? versionRaw.trim()
        : '0';

    final curRaw = map['currentProject'];
    String? cur;
    if (curRaw is String) {
      final t = curRaw.trim();
      cur = t.isEmpty ? null : t;
    }

    return UdpAnnounce(
      name: name,
      ip: senderIp,
      port: port,
      token: token,
      version: version,
      currentProject: cur,
    );
  }
}