// lib/main.dart
//
// M1 入口：默认走 PC v0.12 协议的真实 UDP Discovery（端口 9876）。
// v1.0 实验分支（端口 9001）按 spec §十二「v1 封存」已下线，本里程碑不提供。
//
// PC 端 mock：
//   python3 scripts/pc_mock_broadcaster.py        # v0.12

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
  WidgetsFlutterBinding.ensureInitialized();

  final discovery = _buildDiscovery();

  if (true) {
    dev.log('[StartTooler] discovery = LegacyUDP(:9876)', name: 'starttooler');
  }

  runApp(
    StartToolerApp(
      discovery: discovery,
      connection: ConnectionMock(),
      projects: ProjectMock(),
      uploader: UploadMock(),
    ),
  );
}