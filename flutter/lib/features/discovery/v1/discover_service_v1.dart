// lib/features/discovery/v1/discover_service_v1.dart
//
// V1.0 协议下的发现服务。
// 文档：doc/app/02-pc-udp-protocol.md + doc/app/01-lan-discovery-overview.md §6.2
//
// 行为对齐：
//   - 启动 socket
//   - 周期 1500ms 发 discover_req（broadcast + multicast）
//   - 收 discover_resp → 校验 nonce / msgId / ts / 源 IP = resp.ip
//   - 去重以 pcId 为 key
//   - 配对 + 心跳通过 [pairAndHeartbeat] 单独 API
//
// 暴露：
//   - scan()             : 跑一个时间窗，结果用 pcId 聚合
//   - pair()            : 发 pair_req + 等待 pair_ack / pair_reject
//   - startHeartbeat() : 周期 5s heartbeat
//   - stopHeartbeat()  : 停止

import 'dart:async';
import 'dart:convert';

import '../../../core/app_error.dart';
import '../../../core/mock/seed_data.dart';
import '../udp_log.dart';
import 'app_identity.dart';
import 'nonce_cache.dart';
import 'protocol_v1.dart';
import 'udp_transport.dart';

class V1Device {
  V1Device({
    required this.pcId,
    required this.name,
    required this.ip,
    required this.port,
    required this.ver,
    required this.cap,
    required this.pairState,
    required this.pubKey,
    required this.discoveredAt,
  });

  final String pcId;
  final String name;
  final String ip;
  final int port;
  final String ver;
  final List<String> cap;
  final String pairState; // paired | unpaired
  final String pubKey;
  final DateTime discoveredAt;

  /// 转换为现有 PC 模型（兼容 UI 层）。
  PC toPC() => PC(
        name: name,
        ip: ip,
        port: port,
        projectCount: 0,
        currentProject: null,
        rssi: -100,
      );
}

class DiscoverServiceV1 {
  DiscoverServiceV1({
    V1UdpTransport? transport,
    NonceCache? nonces,
  })  : _transport = transport ?? V1UdpTransportImpl(),
        _nonces = nonces ?? NonceCache();

  final V1UdpTransport _transport;
  final NonceCache _nonces;

  StreamSubscription<ReceivedV1Datagram>? _recvSub;
  Timer? _probeTimer;
  Timer? _heartbeatTimer;
  String? _activeHeartbeatPcId;

  final Map<String, V1Device> _devices = {};

  void Function(V1Device device)? onDeviceUpdated;

  /// §4 PC 端错误码回调（DiscoverResp.error 非空时触发）。
  void Function(AppErrorKind kind)? onErrorFromPc;

  /// 启动 transport + 接收循环 + 周期探测。
  Future<void> start() async {
    if (_transport.isRunning) return;
    await _transport.start();
    _recvSub = _transport.datagrams.listen(_onDatagram);
    _probeTimer ??= Timer.periodic(
      const Duration(milliseconds: ProtocolV1Const.probeIntervalMs),
      (_) => _sendProbe(),
    );
    UdpLog.udp('DiscoverServiceV1.start: probing every '
        '${ProtocolV1Const.probeIntervalMs}ms');
    // 立即发一帧。
    await _sendProbe();
  }

  Future<void> stop() async {
    _probeTimer?.cancel();
    _probeTimer = null;
    await stopHeartbeat();
    await _recvSub?.cancel();
    _recvSub = null;
    await _transport.stop();
    UdpLog.udp('DiscoverServiceV1.stop done');
  }

  Future<void> _sendProbe() async {
    final nonce = _nonces.generate();
    final msgId = newUuidv4Like();
    final ts = nowMs();
    final probe = DiscoverReq.fromAppIdentity(
      appId: AppIdentity.appId,
      appVer: AppIdentity.appVer,
      nonce: nonce,
      caps: const ['file'],
      msgId: msgId,
      ts: ts,
    );
    final json = jsonEncode(probe.toJson());
    await _transport.broadcast(json);
    _nonces.remember(nonce);
  }

  void _onDatagram(ReceivedV1Datagram dg) {
    Map<String, dynamic>? map;
    try {
      map = jsonDecode(dg.text) as Map<String, dynamic>;
    } on Object catch (e) {
      UdpLog.udp('DiscoverServiceV1 json parse failed: $e');
      return;
    }
    if (map == null) return;

    final type = ProtocolV1Type.fromString(map['type'] as String?);
    if (type == ProtocolV1Type.unknown) return;

    if (type == ProtocolV1Type.discoverResp) {
      _handleDiscoverResp(dg, map);
    } else if (type == ProtocolV1Type.pairAck) {
      _handlePairAck(dg, map);
    } else if (type == ProtocolV1Type.pairReject) {
      _handlePairReject(dg, map);
    } else if (type == ProtocolV1Type.heartbeatAck) {
      UdpLog.udp('DiscoverServiceV1 heartbeat_ack from ${dg.sourceIp}');
    } else {
      UdpLog.udp('DiscoverServiceV1 ignored type=${type.wire} from ${dg.sourceIp}');
    }
  }

  void _handleDiscoverResp(ReceivedV1Datagram dg, Map<String, dynamic> map) {
    final resp = DiscoverResp.tryParse(map);
    if (resp == null) {
      UdpLog.udp('DiscoverServiceV1 discover_resp parse rejected from ${dg.sourceIp}');
      return;
    }

    // §4：PC 端返回错误码时直接上报 UI，不进入设备列表。
    if (resp.error != null) {
      UdpLog.udp('DiscoverServiceV1 discover_resp error=${resp.error} '
          'from ${dg.sourceIp}');
      _onErrorFromPc?.call(_mapServerError(resp.error!));
      return;
    }

    // 校验 ts 时间漂移（§2 允许 ±5min）。
    if (!isFreshTimestamp(resp.ts)) {
      UdpLog.udp('DiscoverServiceV1 discover_resp ts stale: ${resp.ts} '
          '(now=${nowMs()})');
      return;
    }

    // 校验回包源 IP（仅当 PC 端填写了 ip 字段时校验；§3.2 字段表标注「否」）。
    if (resp.ip.isNotEmpty && resp.ip != dg.sourceIp) {
      UdpLog.udp('DiscoverServiceV1 discover_resp IP mismatch: '
          'packet=${dg.sourceIp} resp.ip=${resp.ip}');
      return;
    }

    // 校验 nonce。
    if (!_nonces.verifyAndConsume(resp.nonce)) {
      UdpLog.udp('DiscoverServiceV1 discover_resp nonce rejected '
          '(replay or unknown)');
      return;
    }

    final device = V1Device(
      pcId: resp.pcId,
      name: resp.name,
      ip: resp.ip.isEmpty ? dg.sourceIp : resp.ip,
      port: resp.port,
      ver: resp.ver,
      cap: resp.cap,
      pairState: resp.pairState,
      pubKey: resp.pubKey,
      discoveredAt: DateTime.now(),
    );

    _devices[resp.pcId] = device;
    UdpLog.udp('DiscoverServiceV1 device stored pcId=${resp.pcId} '
        'name=${resp.name} pairState=${resp.pairState}');
    onDeviceUpdated?.call(device);
  }

  AppErrorKind _mapServerError(String code) {
    switch (code) {
      case 'unsupported_ver':
        return AppErrorKind.unsupported;
      case 'rate_limited':
        return AppErrorKind.serverError;
      case 'internal_error':
        return AppErrorKind.serverError;
      case 'invalid_msg':
      default:
        return AppErrorKind.unknown;
    }
  }

  // -------- pair + heartbeat --------

  /// 发 pair_req（单播），等待 pair_ack / pair_reject。
  /// 返回 PairAck on success；抛出 AppError on reject/timeout/invalid。
  Future<PairAck> pair({
    required String pcId,
    required String pcIp,
    required String pairCode,
    required String encryptedKey,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final msgId = newUuidv4Like();
    final ts = nowMs();
    final req = PairReq(
      msgId: msgId,
      ts: ts,
      pcId: pcId,
      deviceId: AppIdentity.deviceId,
      code: pairCode,
      encryptedKey: encryptedKey,
    );
    final json = jsonEncode(req.toJson());
    await _transport.sendUnicast(pcIp, ProtocolV1Const.udpPort, json);
    UdpLog.udp('DiscoverServiceV1 pair sent → $pcIp pcId=$pcId');

    final completer = Completer<PairAck>();
    final future = _recvSub!.asFuture<void>();

    void onDg(ReceivedV1Datagram dg) {
      Map<String, dynamic>? m;
      try {
        m = jsonDecode(dg.text) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      if (m == null) return;
      final t = ProtocolV1Type.fromString(m['type'] as String?);
      if (t == ProtocolV1Type.pairAck) {
        final ack = PairAck.tryParse(m);
        if (ack != null && ack.deviceId == AppIdentity.deviceId) {
          completer.complete(ack);
        }
      } else if (t == ProtocolV1Type.pairReject) {
        final rej = PairReject.tryParse(m);
        if (rej != null && rej.deviceId == AppIdentity.deviceId) {
          completer.completeError(
            AppError(
              _mapReject(rej.reason),
              'pair_reject: ${rej.reason}',
            ),
          );
        }
      }
    }

    final sub = _transport.datagrams.listen(onDg);
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      throw AppError(AppErrorKind.unknown, 'pair timeout (${timeout.inSeconds}s)');
    } finally {
      await sub.cancel();
    }
  }

  AppErrorKind _mapReject(String reason) {
    switch (reason) {
      case 'code_expired':
        return AppErrorKind.unknown;
      case 'code_invalid':
        return AppErrorKind.invalidToken;
      case 'device_blocked':
        return AppErrorKind.serverError;
      default:
        return AppErrorKind.unknown;
    }
  }

  void _handlePairAck(ReceivedV1Datagram dg, Map<String, dynamic> map) {
    UdpLog.udp('DiscoverServiceV1 pair_ack from ${dg.sourceIp}');
    // pair 的 await 由 .pair() 注册的 listener 处理；此处只记录。
  }

  void _handlePairReject(ReceivedV1Datagram dg, Map<String, dynamic> map) {
    UdpLog.udp('DiscoverServiceV1 pair_reject from ${dg.sourceIp}');
  }

  /// 启动心跳（5s 一次，单播）。
  void startHeartbeat(String pcId, String pcIp) {
    _activeHeartbeatPcId = pcId;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_activeHeartbeatPcId == null) return;
      final msgId = newUuidv4Like();
      final hb = HeartbeatMsg(
        msgId: msgId,
        ts: nowMs(),
        pcId: _activeHeartbeatPcId!,
        deviceId: AppIdentity.deviceId,
      );
      await _transport.sendUnicast(
        pcIp,
        ProtocolV1Const.udpPort,
        jsonEncode(hb.toJson()),
      );
      UdpLog.udp('DiscoverServiceV1 heartbeat → ${pcIp}:${ProtocolV1Const.udpPort} '
          'pcId=${hb.pcId}');
    });
    UdpLog.udp('DiscoverServiceV1 heartbeat started for pcId=$pcId ip=$pcIp');
  }

  Future<void> stopHeartbeat() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _activeHeartbeatPcId = null;
    UdpLog.udp('DiscoverServiceV1 heartbeat stopped');
  }

  List<V1Device> get devices => _devices.values.toList(growable: false);
  V1Device? deviceByPcId(String pcId) => _devices[pcId];
}

/// 把 V1Device 适配到现有 DiscoveryService 接口。
class V1DiscoveryAdapter implements DiscoveryService {
  V1DiscoveryAdapter(this._service, {this.onError});

  final DiscoverServiceV1 _service;

  /// PC 端协议错误回调（§4）。
  final void Function(AppErrorKind kind)? onError;

  @override
  Future<List<PC>> scan({
    required OnPCDiscovered onDiscovered,
  }) async {
    await _service.start();
    _service.onDeviceUpdated = (dev) => onDiscovered(dev.toPC());
    _service.onErrorFromPc = (kind) => onError?.call(kind);

    // D05 §3.1 5 秒扫描窗口。
    await Future<void>.delayed(const Duration(seconds: 5));
    final pcs = _service.devices.map((d) => d.toPC()).toList();
    pcs.sort((x, y) => x.name.compareTo(y.name));
    await _service.stop();
    return pcs;
  }

  @override
  void simulateOffline() {
    // 由调用方停止 service。
  }
}