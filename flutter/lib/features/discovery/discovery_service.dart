// lib/features/discovery/discovery_service.dart

import 'dart:async';

import '../../core/mock/seed_data.dart';

/// UDP 扫描得到的 PC 信息（与 PC 模型字段一致，但携带发现时间戳）。
typedef OnPCDiscovered = void Function(PC pc);

abstract class DiscoveryService {
  /// 开始扫描；返回扫描结束的 Future。
  Future<List<PC>> scan({required OnPCDiscovered onDiscovered});

  /// 手动触发"模拟断网"（演示用）。
  void simulateOffline();
}

class DiscoveryMock implements DiscoveryService {
  DiscoveryMock();

  bool _offline = false;
  final List<PC> _found = [];

  @override
  Future<List<PC>> scan({required OnPCDiscovered onDiscovered}) async {
    _found.clear();
    final completer = Completer<List<PC>>();

    // 200ms 后 emit 第一台 PC
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_offline) return;
      final pc = mockPCs[0];
      _found.add(pc);
      onDiscovered(pc);
    });

    // 1.2s 后 emit 第二台 PC
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (_offline) return;
      final pc = mockPCs[1];
      _found.add(pc);
      onDiscovered(pc);
    });

    // 5 秒扫描结束
    Timer(discoveryWindow, () {
      completer.complete(List.unmodifiable(_found));
    });

    return completer.future;
  }

  @override
  void simulateOffline() {
    _offline = true;
  }
}