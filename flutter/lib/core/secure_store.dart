// lib/core/secure_store.dart
//
// 持久化封装：SecureStore 接口 + Android 实现（基于 flutter_secure_storage → EncryptedSharedPreferences）。
//
// 接口方法（KB API-05-app-persistence.md）：
//   readCurrent / writeCurrent / readAll / writeAll / remove / activeName / setActive
//
// upsertAndActivate 放在 SpacesController（组合多步操作）。
// iOS/macOS 实现暂留 TODO，本期只跑 Android。

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'space.dart';

abstract class SecureStore {
  Future<Space?> readCurrent();
  Future<void> writeCurrent(Space s);
  Future<List<Space>> readAll();
  Future<void> writeAll(List<Space> spaces);
  Future<void> remove(String name);
  Future<String?> activeName();
  Future<void> setActive(String name);

  /// upsert 到 all + 写 current + setActive。
  Future<void> upsertAndActivate(Space s);
}

class AndroidSecureStore implements SecureStore {
  AndroidSecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static const _kAll = 'spaces.all.v1';
  static const _kCurrent = 'spaces.current.v1';
  static const _kActive = 'spaces.active.v1';

  @override
  Future<Space?> readCurrent() async {
    final raw = await _storage.read(key: _kCurrent);
    if (raw == null) return null;
    return Space.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> writeCurrent(Space s) async {
    await _storage.write(key: _kCurrent, value: jsonEncode(s.toJson()));
  }

  @override
  Future<List<Space>> readAll() async {
    final raw = await _storage.read(key: _kAll);
    if (raw == null) return <Space>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Space.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      // 数据损坏（JSON 格式错 / 字段缺失 / 类型不对）→ 清空后自愈，
      // 避免一次脏数据锁死后续 upsertAndActivate。
      debugPrint('[SecureStore] readAll 解码失败，已清空: $e\n$st');
      try {
        await _storage.delete(key: _kAll);
      } catch (_) {
        // 清不掉也无所谓，下次覆盖写入自然会顶掉。
      }
      return <Space>[];
    }
  }

  @override
  Future<void> writeAll(List<Space> spaces) async {
    final enc = jsonEncode(spaces.map((e) => e.toJson()).toList());
    await _storage.write(key: _kAll, value: enc);
  }

  @override
  Future<void> remove(String name) async {
    final all = await readAll();
    final kept = all.where((s) => s.name != name).toList();
    await writeAll(kept);

    final active = await activeName();
    if (active == name) {
      await _storage.delete(key: _kActive);
      await _storage.delete(key: _kCurrent);
    }
  }

  @override
  Future<String?> activeName() => _storage.read(key: _kActive);

  @override
  Future<void> setActive(String name) => _storage.write(key: _kActive, value: name);

  @override
  Future<void> upsertAndActivate(Space s) async {
    final all = await readAll();
    final idx = all.indexWhere((x) => x.name == s.name);
    if (idx >= 0) {
      all[idx] = s;
    } else {
      all.add(s);
    }
    await writeAll(all);
    await writeCurrent(s);
    await setActive(s.name);
  }
}