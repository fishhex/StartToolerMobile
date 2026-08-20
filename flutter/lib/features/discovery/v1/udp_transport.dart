// lib/features/discovery/v1/udp_transport.dart
//
// UDP 传输层：监听 9001，可同时发包（discover_req / pair_req / heartbeat）。
// 文档：doc/app/02-pc-udp-protocol.md §1, §3
//
// 与旧版差异（对比 D04）：
//   - 端口固定 9001（不再 9876）
//   - 双工：App 主动发 discover_req / pair_req / heartbeat
//   - 单端口多类型：listen + send 同一 socket
//   - 支持组播 224.0.0.251 与广播 255.255.255.255 双通道

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/app_error.dart';
import '../multicast_lock_channel.dart';
import '../udp_log.dart';
import 'protocol_v1.dart';

/// UDP socket 收到一条 JSON 消息的封装。
class ReceivedV1Datagram {
  ReceivedV1Datagram({
    required this.raw,
    required this.text,
    required this.sourceIp,
    required this.sourcePort,
  });

  final Uint8List raw;
  final String text;
  final String sourceIp;
  final int sourcePort;
}

abstract class V1UdpTransport {
  Future<void> start();
  Future<void> stop();

  /// 组播 + 广播双通道发 discover_req。
  Future<int> broadcast(String jsonPayload);

  /// 单播给特定 IP。
  Future<int> sendUnicast(String ip, int port, String jsonPayload);

  Stream<ReceivedV1Datagram> get datagrams;
  bool get isRunning;
}

class V1UdpTransportImpl implements V1UdpTransport {
  V1UdpTransportImpl({
    this.bindPort = ProtocolV1Const.udpPort,
    this.bindAddress,
    InternetAddress? multicastGroup,
    int multicastTtl = 4,
  })  : _multicastGroup = multicastGroup ?? InternetAddress('224.0.0.251'),
        _multicastTtl = multicastTtl;

  final int bindPort;
  final InternetAddress? bindAddress;
  final InternetAddress _multicastGroup;
  final int _multicastTtl;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  final StreamController<ReceivedV1Datagram> _ctrl =
      StreamController<ReceivedV1Datagram>.broadcast();

  bool _running = false;

  @override
  Stream<ReceivedV1Datagram> get datagrams => _ctrl.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    if (_running) return;
    UdpLog.udp('V1UdpTransport.start: requesting MulticastLock');
    final lockOk = await MulticastLockChannel.instance.acquire();
    UdpLog.udp('V1UdpTransport.start: MulticastLock acquired=$lockOk');

    try {
      _socket = await RawDatagramSocket.bind(
        bindAddress ?? InternetAddress.anyIPv4,
        bindPort,
        reuseAddress: true,
      );
      try {
        _socket!.joinMulticast(_multicastGroup);
        UdpLog.udp(
            'V1UdpTransport joined multicast ${_multicastGroup.address}');
      } on Object catch (e) {
        UdpLog.udp('V1UdpTransport joinMulticast failed (non-fatal): $e');
      }
      try {
        _socket!.writeEventsEnabled = false;
      } on Object catch (_) {}

      final localAddr = _socket!.address.address;
      final localPort = _socket!.port;
      UdpLog.udp('V1UdpTransport socket bound on $localAddr:$localPort');

      _sub = _socket!.listen(_onEvent);
      _running = true;
    } on SocketException catch (e) {
      UdpLog.udp('V1UdpTransport.bind SocketException: '
          'errno=${e.osError?.errorCode} msg=${e.message}');
      await MulticastLockChannel.instance.release();
      throw AppError(
        AppErrorKind.network,
        'UDP ${bindPort} 端口占用：${e.message}',
      );
    } on Object catch (e) {
      UdpLog.udp('V1UdpTransport.start failed: $e');
      await MulticastLockChannel.instance.release();
      throw AppError(AppErrorKind.unknown, 'UDP 启动失败：$e');
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket!.receive();
    if (dg == null) return;

    String? text;
    try {
      text = utf8.decode(dg.data, allowMalformed: false);
    } on FormatException catch (e) {
      UdpLog.raw('V1UdpTransport utf8 decode failed: ${e.message}');
      return;
    }
    if (text == null) return;

    _ctrl.add(
      ReceivedV1Datagram(
        raw: Uint8List.fromList(dg.data),
        text: text,
        sourceIp: dg.address.address,
        sourcePort: dg.port,
      ),
    );
  }

  @override
  Future<int> broadcast(String jsonPayload) async {
    final sock = _socket;
    if (sock == null) {
      UdpLog.udp('V1UdpTransport.broadcast ignored: socket not started');
      return 0;
    }
    final bytes = utf8.encode(jsonPayload);
    if (bytes.length > ProtocolV1Const.maxDatagramBytes) {
      UdpLog.udp('V1UdpTransport.broadcast too large: ${bytes.length}B');
      return 0;
    }

    int sent = 0;
    try {
      sent += sock.send(
        bytes,
        InternetAddress('255.255.255.255'),
        bindPort,
      );
    } on Object catch (e) {
      UdpLog.udp('V1UdpTransport broadcast send failed: $e');
    }

    try {
      sent += sock.send(bytes, _multicastGroup, bindPort);
    } on Object catch (e) {
      UdpLog.udp('V1UdpTransport multicast send failed: $e');
    }
    UdpLog.udp('V1UdpTransport.broadcast sent=$sent bytes to '
        'broadcast + ${_multicastGroup.address}');
    return sent;
  }

  @override
  Future<int> sendUnicast(String ip, int port, String jsonPayload) async {
    final sock = _socket;
    if (sock == null) {
      UdpLog.udp('V1UdpTransport.sendUnicast ignored: socket not started');
      return 0;
    }
    final bytes = utf8.encode(jsonPayload);
    if (bytes.length > ProtocolV1Const.maxDatagramBytes) {
      UdpLog.udp('V1UdpTransport.sendUnicast too large: ${bytes.length}B');
      return 0;
    }
    try {
      final addr = InternetAddress(ip);
      final n = sock.send(bytes, addr, port);
      UdpLog.udp('V1UdpTransport.sendUnicast to $ip:$port bytes=${bytes.length}B '
          'sent=$n');
      return n;
    } on Object catch (e) {
      UdpLog.udp('V1UdpTransport.sendUnicast failed: $e');
      return 0;
    }
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    UdpLog.udp('V1UdpTransport.stop');
    await _sub?.cancel();
    _sub = null;
    try {
      _socket?.close();
      UdpLog.udp('V1UdpTransport socket closed');
    } on Object catch (e) {
      UdpLog.udp('V1UdpTransport socket close error: $e');
    }
    _socket = null;
    await _ctrl.close();
    await MulticastLockChannel.instance.release();
    UdpLog.udp('V1UdpTransport.stop done');
  }
}

/// 简单的 UUIDv4-ish 生成（基于 secure RNG）。
String newUuidv4Like() {
  final rnd = Random.secure();
  final bytes = Uint8List(16);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = rnd.nextInt(256);
  }
  // version 4 bits
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // variant bits
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

/// 当前 Unix 时间戳（毫秒）。
int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// 检查 `ts` 是否在当前时间 ±skewMs 内。
bool isFreshTimestamp(int ts, {int skewMs = ProtocolV1Const.tsSkewMs}) {
  final now = nowMs();
  return (ts >= now - skewMs) && (ts <= now + skewMs);
}