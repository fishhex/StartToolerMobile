// lib/main.dart
//
// M1 入口：默认走 PC v0.12 协议的真实 UDP Discovery（端口 9876）。
// v1.0 实验分支（端口 9001）按 spec §十二「v1 封存」已下线，本里程碑不提供。
//
// 联调依赖：真实 PC 端（StartTooler/Services/UploadServerService.cs）必须运行。

import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:developer' as dev;

import 'app/app.dart';
import 'features/connection/connection_service.dart';
import 'features/discovery/discovery_service.dart';
import 'features/discovery/udp_discovery_adapter.dart';
import 'features/discovery/udp_discovery_service.dart';
import 'features/project/project_service.dart';
import 'features/upload/upload_service.dart';

DiscoveryService _buildDiscovery() {
  // M1 范围：仅 v0.12 协议；v1.0 实验分支已封存（spec/05 §十二）。
  return UdpDiscoveryAdapter(UdpDiscoveryServiceImpl());
}

void main() {
  // [DEBUG] 最早可观察点：确认 main() 真的被调到。
  // 如果 logcat 没看到这一行 → AndroidManifest / 包名 / activity 入口配置错
  print('!! DART MAIN START !!');
  dev.log('!! DART MAIN START (via dev.log) !!', name: 'starttooler');

  // 顶层 try/catch 把启动期所有异常打到 logcat，避免被 framework 静默吞掉。
  // 用 print() 而非 dev.log —— Android logcat 抓 print 稳定（tag='flutter'），
  // dev.log 的 Android 行为不稳定（部分版本被 SELinux/ring buffer 过滤）。
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    print('[StartTooler] binding initialized');

    final discovery = _buildDiscovery();
    print('[StartTooler] discovery = LegacyUDP(:9876)');

    runApp(
      StartToolerApp(
        discovery: discovery,
        connection: ConnectionMock(),
        projects: ProjectMock(),
        uploader: UploadMock(),
      ),
    );
    print('[StartTooler] runApp() returned');
  }, (e, st) {
    print('!! DART UNCAUGHT EXCEPTION: $e');
    print('StackTrace: $st');
  });
}