// lib/features/discovery/udp_log.dart
//
// 统一的 UDP 联调日志工具。
// 所有 UDP 链路上的关键节点都通过这里打印，方便排查网络通信问题。
//
// 设计：
//   - 统一前缀 [UDP] / [MLOCK] / [ANNOUNCE]，便于 adb logcat 过滤。
//   - 包含 ISO 时间戳 + 自增计数（同一毫秒内多次事件也能区分）。
//   - 总是输出：debug 模式打开（kDebugMode）才打印，避免 release 包噪声。
//   - 不破坏现有 API：仅提供静态方法。

import 'package:flutter/foundation.dart';

class UdpLog {
  UdpLog._();

  static int _seq = 0;

  /// 输出形如 `[UDP][T+123ms #4] hello` 的日志。
  static void emit(String tag, String message) {
    if (!kDebugMode) return;
    final n = ++_seq;
    final ms = DateTime.now().millisecondsSinceEpoch % 100000;
    debugPrint('[$tag][#${n.toString().padLeft(4, '0')} t=$ms] $message');
  }

  // 常用 tag 快捷方法
  static void udp(String message) => emit('UDP', message);
  static void mlock(String message) => emit('MLOCK', message);
  static void announce(String message) => emit('ANNOUNCE', message);
  static void adapter(String message) => emit('ADAPTER', message);
  static void view(String message) => emit('VIEW', message);
  static void raw(String message) => emit('UDP-RAW', message);
}