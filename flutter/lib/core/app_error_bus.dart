// lib/core/app_error_bus.dart
//
// 全局错误总线：任何页面可 push，根布局订阅显示 ErrorBanner。

import 'package:flutter/foundation.dart';

import 'app_error.dart';

class AppErrorBus extends ChangeNotifier {
  AppError? _current;
  AppError? get current => _current;

  void push(AppError error) {
    _current = error;
    notifyListeners();
  }

  void clear() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}