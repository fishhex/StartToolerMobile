// lib/main.dart
//
// ignore_for_file: avoid_print  // M1 debug 启动日志:用 print 抓 logcat 最稳
//
// M1 入口：默认走 PC v0.12 协议的真实 UDP Discovery（端口 9876）。
// v1.0 实验分支（端口 9001）按 spec §十二「v1 封存」已下线，本里程碑不提供。
//
// M2 接入真实 /api/v1/health + 401 自动重试（D03）：
//   - TokenStore 单一权威（广播为来源）
//   - HttpConnectionService 调真实 health 校验 token
//   - AuthenticatedHttpClient 401 → 等广播 → 重试一次
//
// 联调依赖：真实 PC 端（StartTooler/Services/UploadServerService.cs）必须运行。

import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:developer' as dev;

import 'app/app.dart';
import 'core/token.dart';
import 'core/token_store_in_memory.dart';
import 'features/connection/connection_service.dart';
import 'features/discovery/discovery_service.dart';
import 'features/discovery/udp_discovery_adapter.dart';
import 'features/discovery/udp_discovery_service.dart';
import 'features/project/project_service.dart';
import 'features/upload/upload_service.dart';

DiscoveryService _buildDiscovery(TokenStore tokenStore) {
  // M1 范围：仅 v0.12 协议；v1.0 实验分支已封存（spec/05 §十二）。
  // D03 §3.1：把广播 token 推入 TokenStore（唯一权威源）。
  return UdpDiscoveryAdapter(
    UdpDiscoveryServiceImpl(),
    tokenStore: tokenStore,
  );
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

    // D03：单一 TokenStore 实例，所有子模块共享
    final tokenStore = InMemoryTokenStore();

    final discovery = _buildDiscovery(tokenStore);
    print('[StartTooler] discovery = UDP(:9876) + TokenStore');

    final connection = HttpConnectionService(tokenStore: tokenStore);
    print('[StartTooler] connection = HttpConnectionService(health+401-retry)');

    runApp(
      StartToolerApp(
        discovery: discovery,
        connection: connection,
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
