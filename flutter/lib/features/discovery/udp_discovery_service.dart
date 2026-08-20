// lib/features/discovery/udp_discovery_service.dart
//
// 真实 UDP Discovery：监听 9876 端口，解析 PC 端 announce 包。
//
// 协议参考：doc/0.10/demand/04-mobile-lan-sync.md §3.1.1
//   - PC 端每 2 秒向 255.255.255.255:9876 广播 JSON
//   - App 端持续监听 5 秒（D05 §3.1：5 秒扫描窗口）
//   - 字段约定：service == "starttooler"，version >= "0.12"
//
// 平台注意：
//   - iOS  需在 Info.plist 声明 NSLocalNetworkUsageDescription。
//     Flutter 默认模板未声明，D04 §5.3 已列出。
//   - Android 普通 RawDatagramSocket 收不到广播，
//     需要原生 MulticastLock（POC 阶段先用单播/手动 IP 兜底验证）。
//
// 联调日志：
//   所有 UDP 链路上的关键节点通过 [UdpLog] 输出，统一前缀：
//     [UDP]        bind / listen / 生命周期
//     [UDP-RAW]    收到的原始字节流（hex + UTF-8 尝试解码）
//     [ANNOUNCE]  协议解析成功的 announce
//     [MLOCK]     MulticastLock acquire / release

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/app_error.dart';
import 'multicast_lock_channel.dart';
import 'udp_announce.dart';
import 'udp_log.dart';

/// UDP 发现结果。
class DiscoveryResult {
  DiscoveryResult({required this.devices});

  /// 按 rssi 降序排好序的设备（D05 §3.1 协议规范：按信号强度排序）。
  /// 当前 UDP 监听不直接携带 RSSI，外部可在合并层补默认 -100。
  final List<UdpAnnounce> devices;
}

abstract class UdpDiscoveryService {
  /// 启动一次最长 [window] 的扫描；每收到一帧 announce 即回调 [onAnnounce]。
  /// 返回扫描结果（已去重）。
  Future<DiscoveryResult> scan({
    required Duration window,
    required void Function(UdpAnnounce announce) onAnnounce,
  });

  /// 主动关闭监听 socket；同一实例多次调用安全。
  Future<void> close();
}

class UdpDiscoveryServiceImpl implements UdpDiscoveryService {
  UdpDiscoveryServiceImpl({
    this.port = 9876,
    this.bindAddress,
  });

  /// UDP 监听端口（PC 端广播端口）。
  final int port;

  /// 绑定地址：默认 anyIPv4，便于接收广播包。
  /// Android 上部分设备需 bind 到 0.0.0.0 才能收到广播。
  final InternetAddress? bindAddress;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  bool _closed = false;

  @override
  Future<DiscoveryResult> scan({
    required Duration window,
    required void Function(UdpAnnounce announce) onAnnounce,
  }) async {
    UdpLog.udp('scan() called, window=$window port=$port '
        'bindAddress=${bindAddress?.address ?? "<auto>"}');

    try {
      await _ensureSocket();
    } on AppError catch (e) {
      UdpLog.udp('scan() aborted: ${e.kind} ${e.message}');
      rethrow;
    }

    final seen = <String, UdpAnnounce>{};
    final completer = Completer<DiscoveryResult>();

    _sub = _socket!.listen((event) {
      _onSocketEvent(event, seen, onAnnounce);
    }, onError: (Object e, StackTrace st) {
      UdpLog.udp('socket stream error: $e');
    }, onDone: () {
      UdpLog.udp('socket stream done (closed=${_socket?.port ?? "null"})');
    });

    UdpLog.udp('listening, will auto-close after $window');

    Timer(window, () async {
      await _sub?.cancel();
      _sub = null;
      UdpLog.udp('window expired, '
          'seen=${seen.length} devices=${seen.keys.toList()}');
      if (!completer.isCompleted) {
        completer.complete(DiscoveryResult(devices: seen.values.toList()));
      }
    });

    return completer.future;
  }

  void _onSocketEvent(
    RawSocketEvent event,
    Map<String, UdpAnnounce> seen,
    void Function(UdpAnnounce) onAnnounce,
  ) {
    if (event != RawSocketEvent.read) return;

    final datagram = _socket!.receive();
    if (datagram == null) {
      UdpLog.raw('RawSocketEvent.read but receive() returned null');
      return;
    }

    final senderIp = datagram.address.address;
    final senderPort = datagram.port;
    final bytes = datagram.data;
    final hex = _toHex(bytes, maxBytes: 32);

    UdpLog.raw('recv ${bytes.length}B from $senderIp:$senderPort hex=$hex');

    // 注意：datagram.port 是「发送方源端口」（如 51657，PC 端临时端口），
    // 不应与本机监听端口 (9876) 比较 —— 否则所有广播都会被误过滤。
    // 接收方正确性由 socket 绑定 port=9876 时的 UDP 内核栈保证。

    final text = _tryDecodeUtf8(bytes);
    if (text == null) {
      UdpLog.raw('filtered (invalid UTF-8)');
      return;
    }

    UdpLog.raw('decoded text: $text');

    final announce = UdpAnnounce.tryParse(text, senderIp: senderIp);
    if (announce == null) {
      UdpLog.raw('filtered (tryParse failed: not starttooler JSON)');
      return;
    }

    UdpLog.announce('parsed '
        'ip=${announce.ip}:${announce.port} '
        'name="${announce.name}" '
        'project=${announce.currentProject ?? "<none>"} '
        'version=${announce.version} '
        'token.len=${announce.token.length} '
        'compatible=${announce.isCompatibleVersion}');

    if (!announce.isCompatibleVersion) {
      UdpLog.announce('rejected by version policy '
          '(major=${announce.version.split(".").first} '
          '< minSupportedMajor=${UdpAnnounce.minSupportedMajor})');
      return;
    }

    // 去重：D01 §3.5 要求 `name + port + ip` 三元组（IP 视为浮动）。
    final key = announce.dedupeKey;
    final isNew = !seen.containsKey(key);
    seen[key] = announce;
    if (isNew) {
      UdpLog.udp('new device name="${announce.name}" addr=${announce.ip}:${announce.port} added (key=$key)');
    } else {
      UdpLog.udp('update existing device name="${announce.name}" addr=${announce.ip}:${announce.port} (key=$key)');
    }
    onAnnounce(announce);
  }

  Future<void> _ensureSocket() async {
    if (_socket != null) return;

    UdpLog.udp('ensureSocket: requesting MulticastLock');
    final lockOk = await MulticastLockChannel.instance.acquire();
    UdpLog.udp('ensureSocket: MulticastLock acquired=$lockOk');

    try {
      _socket = await RawDatagramSocket.bind(
        bindAddress ?? InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      final localAddr = _socket!.address.address;
      final localPort = _socket!.port;
      UdpLog.udp('RawDatagramSocket.bind success on $localAddr:$localPort');
    } on SocketException catch (e) {
      UdpLog.udp('RawDatagramSocket.bind SocketException: '
          'errno=${e.osError?.errorCode} msg=${e.message}');
      await MulticastLockChannel.instance.release();
      throw AppError(
        AppErrorKind.network,
        'UDP 端口占用：${e.message}（请关闭占用 $port 端口的应用）',
      );
    } on Object catch (e) {
      UdpLog.udp('RawDatagramSocket.bind failed: $e');
      await MulticastLockChannel.instance.release();
      throw AppError(AppErrorKind.unknown, 'UDP 监听启动失败：$e');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    UdpLog.udp('close() invoked, releasing resources');
    await _sub?.cancel();
    _sub = null;
    try {
      _socket?.close();
      UdpLog.udp('RawDatagramSocket closed');
    } on Object catch (e) {
      UdpLog.udp('socket close error: $e');
    }
    _socket = null;
    await MulticastLockChannel.instance.release();
    UdpLog.udp('close() done');
  }
}

/// 把字节转成可读 hex，超过 maxBytes 截断 + ...。
String _toHex(List<int> bytes, {required int maxBytes}) {
  final shown = bytes.length > maxBytes
      ? bytes.sublist(0, maxBytes)
      : bytes;
  final hex = shown
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(' ');
  return bytes.length > maxBytes ? '$hex ...(${bytes.length}B)' : hex;
}

/// 尝试 UTF-8 解码；失败返回 null。
String? _tryDecodeUtf8(List<int> bytes) {
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException catch (e) {
    UdpLog.raw('utf8 decode failed: ${e.message}');
    return null;
  }
}