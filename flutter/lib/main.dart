// lib/main.dart
//
// M1 入口：默认走 PC v0.12 协议的真实 UDP Discovery（端口 9876）。
//   --dart-define=PROTO=legacy   → v0.12 单向 UDP（端口 9876，默认）
//   --dart-define=PROTO=v1       → v1.0 实验分支（端口 9001；保留作为后续对比）
//
// PC 端 mock：
//   python3 scripts/pc_mock_broadcaster.py        # v0.12
//   python3 scripts/pc_mock_v1_broadcaster.py     # v1.0

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/connection/connection_service.dart';
import 'features/discovery/udp_discovery_adapter.dart';
import 'features/discovery/udp_discovery_service.dart';
import 'features/discovery/v1/discover_service_v1.dart';
import 'features/discovery/discovery_service.dart';
import 'features/project/project_service.dart';
import 'features/upload/upload_service.dart';

/// 协议版本：legacy（v0.12，默认） / v1（实验分支）
const String _kProto = String.fromEnvironment('PROTO', defaultValue: 'legacy');

DiscoveryService _buildDiscovery() {
  switch (_kProto) {
    case 'v1':
      return V1DiscoveryAdapter(DiscoverServiceV1());
    case 'legacy':
    default:
      return UdpDiscoveryAdapter(UdpDiscoveryServiceImpl());
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final discovery = _buildDiscovery();

  if (kDebugMode) {
    final mode = _kProto == 'v1' ? 'V1UDP(:9001)' : 'LegacyUDP(:9876)';
    debugPrint('[StartTooler] discovery = $mode');
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