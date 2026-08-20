// lib/features/discovery/v1/protocol_v1.dart
//
// PC 端 UDP 发现与配对协议 v1.0 — 数据模型层
// 文档：doc/app/02-pc-udp-protocol.md
//
// 设计原则：
//   - 严格按协议文档字段命名（type / msgId / ts / pcId / nonce / ...）
//   - 所有 ID/Token/Nonce 使用 Base64 (URL-safe, RFC 4648 §5)
//   - 时间戳使用毫秒级 Unix time
//   - toJson / fromJson 容错：未知字段保留，缺失字段返回 null

import 'dart:convert';
import 'dart:typed_data';

import '../udp_log.dart';

/// 协议消息类型。
enum ProtocolV1Type {
  discoverReq,
  discoverResp,
  pairReq,
  pairAck,
  pairReject,
  heartbeat,
  heartbeatAck,
  unknown;

  static ProtocolV1Type fromString(String? s) {
    switch (s) {
      case 'discover_req':
        return ProtocolV1Type.discoverReq;
      case 'discover_resp':
        return ProtocolV1Type.discoverResp;
      case 'pair_req':
        return ProtocolV1Type.pairReq;
      case 'pair_ack':
        return ProtocolV1Type.pairAck;
      case 'pair_reject':
        return ProtocolV1Type.pairReject;
      case 'heartbeat':
        return ProtocolV1Type.heartbeat;
      case 'heartbeat_ack':
        return ProtocolV1Type.heartbeatAck;
      default:
        return ProtocolV1Type.unknown;
    }
  }

  String get wire => switch (this) {
        ProtocolV1Type.discoverReq => 'discover_req',
        ProtocolV1Type.discoverResp => 'discover_resp',
        ProtocolV1Type.pairReq => 'pair_req',
        ProtocolV1Type.pairAck => 'pair_ack',
        ProtocolV1Type.pairReject => 'pair_reject',
        ProtocolV1Type.heartbeat => 'heartbeat',
        ProtocolV1Type.heartbeatAck => 'heartbeat_ack',
        ProtocolV1Type.unknown => 'unknown',
      };
}

/// 协议常量。
class ProtocolV1Const {
  static const int udpPort = 9001;
  static const int tcpBusinessPort = 9000;
  static const int probeIntervalMs = 1500;
  static const int probeTimeoutMs = 1500;
  static const int probeMaxRetries = 1;
  static const int nonceCacheTtlMs = 3000;
  static const int tsSkewMs = 5 * 60 * 1000; // §2 允许 ±5min 时钟漂移
  static const int nonceBytes = 16;
  static const int maxDatagramBytes = 1400;
}

/// Base64 URL-safe 工具。
class B64 {
  static String encode(Uint8List bytes) => base64UrlEncode(bytes);

  static Uint8List? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      return base64Url.decode(s);
    } catch (e) {
      UdpLog.udp('B64.decode failed: $e (input.len=${s.length})');
      return null;
    }
  }
}

/// 所有消息共用的骨架。
abstract class ProtocolV1Message {
  ProtocolV1Message({
    required this.type,
    required this.msgId,
    required this.ts,
  });

  final ProtocolV1Type type;
  final String msgId;
  final int ts;

  Map<String, dynamic> toBaseJson() => {
        'type': type.wire,
        'msgId': msgId,
        'ts': ts,
      };

  Map<String, dynamic> toJson();
}

/// App → PC：发现请求。
class DiscoverReq extends ProtocolV1Message {
  DiscoverReq({
    required super.msgId,
    required super.ts,
    required this.appId,
    this.appVer,
    required this.nonce,
    this.cap = const [],
  });

  final String appId;
  final String? appVer;
  final String nonce; // 16B Base64
  final List<String> cap;

  factory DiscoverReq.fromAppIdentity({
    required String appId,
    String? appVer,
    required String nonce,
    required List<String> caps,
    required String msgId,
    required int ts,
  }) =>
      DiscoverReq(
        msgId: msgId,
        ts: ts,
        appId: appId,
        appVer: appVer,
        nonce: nonce,
        cap: caps,
      );

  @override
  Map<String, dynamic> toJson() => {
        ...toBaseJson(),
        'appId': appId,
        if (appVer != null) 'appVer': appVer,
        'nonce': nonce,
        if (cap.isNotEmpty) 'caps': cap,
      };

  static DiscoverReq? tryParse(Map<String, dynamic> m) {
    final t = ProtocolV1Type.fromString(m['type'] as String?);
    if (t != ProtocolV1Type.discoverReq) return null;
    final nonce = (m['nonce'] as String?) ?? '';
    final appId = (m['appId'] as String?) ?? '';
    final msgId = (m['msgId'] as String?) ?? '';
    final ts = (m['ts'] as num?)?.toInt() ?? 0;
    if (nonce.isEmpty || appId.isEmpty || msgId.isEmpty || ts <= 0) {
      return null;
    }
    return DiscoverReq(
      msgId: msgId,
      ts: ts,
      appId: appId,
      appVer: m['appVer'] as String?,
      nonce: nonce,
      cap: (m['caps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

/// PC → App：发现响应。
class DiscoverResp extends ProtocolV1Message {
  DiscoverResp({
    required super.msgId,
    required super.ts,
    required this.pcId,
    required this.name,
    required this.ip,
    required this.port,
    required this.ver,
    required this.cap,
    required this.nonce,
    required this.pubKey,
    required this.pairState,
    this.error,
  });

  final String pcId;
  final String name;
  final String ip;
  final int port;
  final String ver;
  final List<String> cap;
  final String nonce;
  final String pubKey;
  final String pairState; // "paired" | "unpaired"
  /// §4 PC 端错误码：invalid_msg | unsupported_ver | rate_limited | internal_error
  final String? error;

  @override
  Map<String, dynamic> toJson() => {
        ...toBaseJson(),
        'pcId': pcId,
        'name': name,
        'ip': ip,
        'port': port,
        'ver': ver,
        'cap': cap,
        'nonce': nonce,
        'pubKey': pubKey,
        'pairState': pairState,
        if (error != null) 'error': error,
      };

  static DiscoverResp? tryParse(Map<String, dynamic> m) {
    final t = ProtocolV1Type.fromString(m['type'] as String?);
    if (t != ProtocolV1Type.discoverResp) return null;
    final msgId = (m['msgId'] as String?) ?? '';
    final ts = (m['ts'] as num?)?.toInt() ?? 0;
    final pcId = (m['pcId'] as String?) ?? '';
    final name = (m['name'] as String?) ?? '';
    final ip = (m['ip'] as String?) ?? '';
    final port = (m['port'] as num?)?.toInt() ?? 0;
    final ver = (m['ver'] as String?) ?? '';
    final capRaw = (m['cap'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final nonce = (m['nonce'] as String?) ?? '';
    final pubKey = (m['pubKey'] as String?) ?? '';
    final pairState = (m['pairState'] as String?) ?? '';
    final error = m['error'] as String?;

    // §4 错误码白名单。
    if (error != null &&
        error != 'invalid_msg' &&
        error != 'unsupported_ver' &&
        error != 'rate_limited' &&
        error != 'internal_error') {
      UdpLog.udp('DiscoverResp.tryParse rejected unknown error code: $error');
      return null;
    }

    if (msgId.isEmpty ||
        ts <= 0 ||
        pcId.isEmpty ||
        name.isEmpty ||
        port <= 0 ||
        port > 65535 ||
        ver.isEmpty ||
        capRaw.isEmpty ||
        nonce.isEmpty ||
        pubKey.isEmpty ||
        (pairState != 'paired' && pairState != 'unpaired')) {
      return null;
    }
    return DiscoverResp(
      msgId: msgId,
      ts: ts,
      pcId: pcId,
      name: name,
      ip: ip,
      port: port,
      ver: ver,
      cap: capRaw,
      nonce: nonce,
      pubKey: pubKey,
      pairState: pairState,
      error: error,
    );
  }
}

/// App → PC：配对请求。
class PairReq extends ProtocolV1Message {
  PairReq({
    required super.msgId,
    required super.ts,
    required this.pcId,
    required this.deviceId,
    required this.code,
    required this.encryptedKey,
  });

  final String pcId;
  final String deviceId;
  final String code; // 6 位
  final String encryptedKey; // PC 公钥加密

  @override
  Map<String, dynamic> toJson() => {
        ...toBaseJson(),
        'pcId': pcId,
        'deviceId': deviceId,
        'code': code,
        'encryptedKey': encryptedKey,
      };

  static PairReq? tryParse(Map<String, dynamic> m) {
    final t = ProtocolV1Type.fromString(m['type'] as String?);
    if (t != ProtocolV1Type.pairReq) return null;
    final pcId = (m['pcId'] as String?) ?? '';
    final deviceId = (m['deviceId'] as String?) ?? '';
    final code = (m['code'] as String?) ?? '';
    final encryptedKey = (m['encryptedKey'] as String?) ?? '';
    if (pcId.isEmpty || deviceId.isEmpty || code.length != 6 || encryptedKey.isEmpty) {
      return null;
    }
    return PairReq(
      msgId: (m['msgId'] as String?) ?? '',
      ts: (m['ts'] as num?)?.toInt() ?? 0,
      pcId: pcId,
      deviceId: deviceId,
      code: code,
      encryptedKey: encryptedKey,
    );
  }
}

/// PC → App：配对成功。
class PairAck extends ProtocolV1Message {
  PairAck({
    required super.msgId,
    required super.ts,
    required this.deviceId,
    required this.token,
    this.expiresIn = 2592000,
  });

  final String deviceId;
  final String token;
  final int expiresIn;

  @override
  Map<String, dynamic> toJson() => {
        ...toBaseJson(),
        'deviceId': deviceId,
        'token': token,
        'expiresIn': expiresIn,
      };

  static PairAck? tryParse(Map<String, dynamic> m) {
    final t = ProtocolV1Type.fromString(m['type'] as String?);
    if (t != ProtocolV1Type.pairAck) return null;
    final deviceId = (m['deviceId'] as String?) ?? '';
    final token = (m['token'] as String?) ?? '';
    if (deviceId.isEmpty || token.isEmpty) return null;
    return PairAck(
      msgId: (m['msgId'] as String?) ?? '',
      ts: (m['ts'] as num?)?.toInt() ?? 0,
      deviceId: deviceId,
      token: token,
      expiresIn: (m['expiresIn'] as num?)?.toInt() ?? 2592000,
    );
  }
}

/// PC → App：配对拒绝。
class PairReject extends ProtocolV1Message {
  PairReject({
    required super.msgId,
    required super.ts,
    required this.deviceId,
    required this.reason,
  });

  final String deviceId;
  final String reason; // code_expired | code_invalid | device_blocked

  @override
  Map<String, dynamic> toJson() => {
        ...toBaseJson(),
        'deviceId': deviceId,
        'reason': reason,
      };

  static PairReject? tryParse(Map<String, dynamic> m) {
    final t = ProtocolV1Type.fromString(m['type'] as String?);
    if (t != ProtocolV1Type.pairReject) return null;
    final deviceId = (m['deviceId'] as String?) ?? '';
    final reason = (m['reason'] as String?) ?? '';
    if (deviceId.isEmpty || reason.isEmpty) return null;
    return PairReject(
      msgId: (m['msgId'] as String?) ?? '',
      ts: (m['ts'] as num?)?.toInt() ?? 0,
      deviceId: deviceId,
      reason: reason,
    );
  }
}

/// App → PC：心跳。
class HeartbeatMsg extends ProtocolV1Message {
  HeartbeatMsg({
    required super.msgId,
    required super.ts,
    required this.pcId,
    required this.deviceId,
  });

  final String pcId;
  final String deviceId;

  @override
  Map<String, dynamic> toJson() => {
        ...toBaseJson(),
        'pcId': pcId,
        'deviceId': deviceId,
      };

  static HeartbeatMsg? tryParse(Map<String, dynamic> m) {
    final t = ProtocolV1Type.fromString(m['type'] as String?);
    if (t != ProtocolV1Type.heartbeat) return null;
    final pcId = (m['pcId'] as String?) ?? '';
    final deviceId = (m['deviceId'] as String?) ?? '';
    if (pcId.isEmpty || deviceId.isEmpty) return null;
    return HeartbeatMsg(
      msgId: (m['msgId'] as String?) ?? '',
      ts: (m['ts'] as num?)?.toInt() ?? 0,
      pcId: pcId,
      deviceId: deviceId,
    );
  }
}

/// PC → App：心跳应答。
class HeartbeatAck extends ProtocolV1Message {
  HeartbeatAck({
    required super.msgId,
    required super.ts,
    required this.deviceId,
  });

  final String deviceId;

  @override
  Map<String, dynamic> toJson() => {
        ...toBaseJson(),
        'deviceId': deviceId,
      };

  static HeartbeatAck? tryParse(Map<String, dynamic> m) {
    final t = ProtocolV1Type.fromString(m['type'] as String?);
    if (t != ProtocolV1Type.heartbeatAck) return null;
    final deviceId = (m['deviceId'] as String?) ?? '';
    if (deviceId.isEmpty) return null;
    return HeartbeatAck(
      msgId: (m['msgId'] as String?) ?? '',
      ts: (m['ts'] as num?)?.toInt() ?? 0,
      deviceId: deviceId,
    );
  }
}

/// 通用消息解析入口。
ProtocolV1Message? parseV1Message(Map<String, dynamic> m) {
  final t = ProtocolV1Type.fromString(m['type'] as String?);
  switch (t) {
    case ProtocolV1Type.discoverReq:
      return DiscoverReq.tryParse(m);
    case ProtocolV1Type.discoverResp:
      return DiscoverResp.tryParse(m);
    case ProtocolV1Type.pairReq:
      return PairReq.tryParse(m);
    case ProtocolV1Type.pairAck:
      return PairAck.tryParse(m);
    case ProtocolV1Type.pairReject:
      return PairReject.tryParse(m);
    case ProtocolV1Type.heartbeat:
      return HeartbeatMsg.tryParse(m);
    case ProtocolV1Type.heartbeatAck:
      return HeartbeatAck.tryParse(m);
    case ProtocolV1Type.unknown:
      return null;
  }
}