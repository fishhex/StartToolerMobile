// lib/core/spaces_controller.dart
//
// 把 SecureStore + Space 串成一个高层 controller：
//   - 启动时 load()
//   - connect 成功 → upsertAndActivate
//   - 删除 → remove

import 'package:flutter/foundation.dart';

import 'secure_store.dart';
import 'space.dart';

class SpacesController extends ChangeNotifier {
  SpacesController(this._store);

  final SecureStore _store;

  List<Space> _spaces = [];
  String? _activeName;

  List<Space> get spaces => _spaces;
  String? get activeName => _activeName;
  Space? get active => _spaces.where((s) => s.name == _activeName).firstOrNull;

  Future<void> load() async {
    _spaces = await _store.readAll();
    _activeName = await _store.activeName();
    notifyListeners();
  }

  Future<void> upsertAndActivate(Space s) async {
    await _store.upsertAndActivate(s);
    await load();
  }

  Future<void> remove(String name) async {
    await _store.remove(name);
    await load();
  }

  Future<void> setActive(String name) async {
    await _store.setActive(name);
    final s = _spaces.where((x) => x.name == name).firstOrNull;
    if (s != null) {
      await _store.writeCurrent(s);
    }
    _activeName = name;
    notifyListeners();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}