// lib/main.dart
//
// 真实实现入口（按 doc/app/02-pc-udp-protocol.md v1.0）。
//   - discovery: V1.0 双向 UDP（discover_req ↔ discover_resp + pair + heartbeat）
//   - connection / projects / uploader: 仍是 Mock（P0-2/3/5 后续替换）
//
// 运行：
//   flutter run                                 # 默认真实 v1.0
//   flutter run --dart-define=USE_MOCK=true     # 强制 Mock（演示 UI）
//   flutter run --dart-define=PROTO=legacy      # 旧版 D04 (port 9876)
//
// PC 端 mock：
//   python3 scripts/pc_mock_v1_broadcaster.py

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'features/connection/connection_service.dart';
import 'features/discovery/discovery_service.dart';
import 'features/discovery/udp_discovery_adapter.dart';
import 'features/discovery/udp_discovery_service.dart';
import 'features/discovery/v1/discover_service_v1.dart';
import 'features/project/project_service.dart';
import 'features/upload/upload_service.dart';

/// Mock 开关。
const bool _kUseMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);

/// 协议版本：v1（默认）/ legacy（D04 旧端口 9876）
const String _kProto = String.fromEnvironment('PROTO', defaultValue: 'v1');

DiscoveryService _buildDiscovery() {
  if (_kUseMock) return DiscoveryMock();
  switch (_kProto) {
    case 'legacy':
      return UdpDiscoveryAdapter(UdpDiscoveryServiceImpl());
    case 'v1':
    default:
      return V1DiscoveryAdapter(DiscoverServiceV1());
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final discovery = _buildDiscovery();

  if (kDebugMode) {
    final mode = _kUseMock ? 'Mock' : (_kProto == 'legacy' ? 'LegacyUDP(:9876)' : 'V1UDP(:9001)');
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