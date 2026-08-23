// lib/core/error_bus.dart
//
// AppErrorBus：统一错误展示。T1 仅占位实现（ChangeNotifier 持有当前 banner 错误），
// T4 接入全局 MaterialBanner / SnackBar 自动展示。

import 'package:flutter/foundation.dart';

class AppErrorBus extends ChangeNotifier {
  Object? _current;

  Object? get current => _current;

  void push(Object error) {
    _current = error;
    notifyListeners();
  }

  void dismiss() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}