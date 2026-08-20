// lib/features/discovery/multicast_lock_channel.dart
//
// Android 端 MulticastLock 的 Flutter 桥接。
//
// 平台行为：
//   - Android: 调原生 `WifiManager.createMulticastLock`
//   - iOS / macOS / Windows / Linux: no-op（不需要 MulticastLock）
//
// 失败策略：
//   - acquire 失败 → 仍然尝试 bind socket（让用户感知到 UDP 收不到）
//     由调用方决定是否降级到手动输入 IP。
//
// 联调日志：[MLOCK] 前缀，详见 udp_log.dart。

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'udp_log.dart';

class MulticastLockChannel {
  MulticastLockChannel._();

  static final MulticastLockChannel instance = MulticastLockChannel._();

  static const MethodChannel _channel =
      MethodChannel('starttooler/multicast_lock');

  bool _acquired = false;

  bool get isAcquired => _acquired;

  /// 仅在 Android 上请求 MulticastLock。其他平台返回 true。
  Future<bool> acquire() async {
    UdpLog.mlock('acquire() called, current state acquired=$_acquired '
        'platform=${Platform.operatingSystem}');

    if (_acquired) {
      UdpLog.mlock('acquire() skip: already acquired');
      return true;
    }
    if (!Platform.isAndroid) {
      UdpLog.mlock('acquire() noop on ${Platform.operatingSystem}');
      _acquired = true;
      return true;
    }
    try {
      UdpLog.mlock('invoking native acquire via MethodChannel');
      final result = await _channel.invokeMethod<bool>('acquire');
      _acquired = result ?? false;
      UdpLog.mlock('native acquire returned=$result, _acquired=$_acquired');
      return _acquired;
    } on MissingPluginException catch (e) {
      // iOS 等平台可能没有注册 → 视为成功。
      UdpLog.mlock('acquire() MissingPluginException: ${e.message} '
          '(treating as success)');
      _acquired = true;
      return true;
    } on PlatformException catch (e) {
      UdpLog.mlock('acquire() PlatformException code=${e.code} '
          'message=${e.message}');
      _acquired = false;
      return false;
    }
  }

  Future<void> release() async {
    UdpLog.mlock('release() called, current state acquired=$_acquired '
        'platform=${Platform.operatingSystem}');
    if (!_acquired) {
      UdpLog.mlock('release() skip: not acquired');
      return;
    }
    if (!Platform.isAndroid) {
      UdpLog.mlock('release() noop on ${Platform.operatingSystem}');
      _acquired = false;
      return;
    }
    try {
      UdpLog.mlock('invoking native release via MethodChannel');
      await _channel.invokeMethod('release');
      UdpLog.mlock('native release ok');
    } on MissingPluginException catch (e) {
      UdpLog.mlock('release() MissingPluginException: ${e.message} (ignored)');
      // 忽略。
    } on PlatformException catch (e) {
      UdpLog.mlock('release() PlatformException code=${e.code} '
          'message=${e.message} (ignored)');
      // 忽略。
    } finally {
      _acquired = false;
    }
  }
}