// lib/features/discovery/v1/app_identity.dart
//
// App 端身份信息：
//   - appId    包名（固定值）
//   - appVer   pubspec.yaml 中的版本
//   - deviceId 16 字节随机 UUID Base64，每次启动生成 + 本地持久化
//
// 文档：doc/app/02-pc-udp-protocol.md §3.1

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../udp_log.dart';

class AppIdentity {
  AppIdentity._();

  /// 与 pubspec.yaml 的 name 对齐。
  static const String appId = 'com.starttooler.mobile';

  /// 启动时随机生成（生产环境应持久化到 Keychain / EncryptedSharedPreferences）。
  static String? _deviceId;

  /// 版本号从 pubspec.yaml 编译期注入（--dart-define=APP_VER=...）。
  static const String appVer = String.fromEnvironment('APP_VER', defaultValue: '0.1.0');

  /// 当前进程 deviceId；首次访问时生成并缓存。
  static String get deviceId {
    final cached = _deviceId;
    if (cached != null) return cached;
    final rnd = Random.secure();
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rnd.nextInt(256);
    }
    final id = base64UrlEncode(bytes);
    _deviceId = id;
    UdpLog.udp('AppIdentity.deviceId generated: $id');
    return id;
  }

  /// 调用方在重启后可从持久化层传入（与 deviceId 同值则继续使用）。
  static void seedDeviceId(String persisted) {
    _deviceId = persisted;
    UdpLog.udp('AppIdentity.deviceId restored: $persisted');
  }

  /// 平台标识（用于 caps 字段提示 PC 端）。
  static String get platform => Platform.operatingSystem;
}