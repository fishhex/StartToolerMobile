// lib/core/mock/seed_data.dart
//
// 集中存放第一步本地验证用的所有 Mock 数据。
// 严格对齐 doc/0.10/demand/06-mobile-app-ui-baseline.md §八。
//
// 用法：
//   import 'package:starttooler_mobile/core/mock/seed_data.dart';
//   for (final pc in mockPCs) print(pc.name);
//
// 替换计划（第二步接入真实协议时）：
//   - PC        <- DiscoveryMock 返回的 UDPAnnounce 解析结果
//   - Project   <- ProjectService.listProjects() 的 JSON DTO
//   - SelectedFile <- UploadService 接收的 URL/Uri

// ============================================================================
// 数据模型（最小化：final 字段 + 命名构造器 + 派生 getter）
// 后续接入 JSON 序列化时改为 fromJson / toJson。
// ============================================================================

/// 局域网内发现的 PC 设备。
class PC {
  const PC({
    required this.name,
    required this.ip,
    required this.port,
    required this.projectCount,
    required this.currentProject,
    required this.rssi,
  });

  final String name;
  final String ip;
  final int port;
  final int projectCount;

  /// 当前激活项目名；null 表示 PC 未打开任何项目。
  final String? currentProject;

  /// 信号强度（dBm），用于列表排序，越大越强。
  final int rssi;

  String get displayAddress => '$ip:$port';
}

/// PC 端项目（对应 ProjectConfig.RecentDirectories 中的一项）。
class Project {
  const Project({
    required this.name,
    required this.fileCount,
    required this.sizeMb,
    required this.isCurrent,
  });

  final String name;
  final int fileCount;
  final int sizeMb;
  final bool isCurrent;

  /// 人类可读的文件大小（MB / GB 自动切换）。
  String get sizeLabel {
    if (sizeMb >= 1024) {
      return '${(sizeMb / 1024).toStringAsFixed(1)} GB';
    }
    return '$sizeMb MB';
  }
}

/// 用户从相册选中的待上传文件（mock 阶段为本地假数据）。
class SelectedFile {
  const SelectedFile({
    required this.name,
    required this.sizeMb,
  });

  final String name;
  final double sizeMb;

  String get sizeLabel => '${sizeMb.toStringAsFixed(1)} MB';
}

// ============================================================================
// 种子数据（与 D06 §八.1 完全对齐）
// ============================================================================

/// 局域网扫描到的假 PC 列表。
const List<PC> mockPCs = <PC>[
  PC(
    name: 'Hex-MacBook',
    ip: '192.168.1.10',
    port: 8765,
    projectCount: 3,
    currentProject: 'deepsky-2025',
    rssi: -42,
  ),
  PC(
    name: 'Hex-Win11',
    ip: '192.168.1.20',
    port: 8765,
    projectCount: 1,
    currentProject: null,
    rssi: -58,
  ),
];

/// 假项目列表（含 1 个当前项目 + 2 个其他）。
const List<Project> mockProjects = <Project>[
  Project(
    name: 'deepsky-2025',
    fileCount: 234,
    sizeMb: 1234,
    isCurrent: true,
  ),
  Project(
    name: 'moon-2025',
    fileCount: 56,
    sizeMb: 320,
    isCurrent: false,
  ),
  Project(
    name: 'M31-test',
    fileCount: 12,
    sizeMb: 88,
    isCurrent: false,
  ),
];

/// 假"已选照片"列表（用于演示选择 + 上传流程）。
const List<SelectedFile> mockFiles = <SelectedFile>[
  SelectedFile(name: 'DSC001.jpg', sizeMb: 12.3),
  SelectedFile(name: 'DSC002.jpg', sizeMb: 14.1),
  SelectedFile(name: 'DSC003.jpg', sizeMb: 9.8),
  SelectedFile(name: 'DSC004.jpg', sizeMb: 22.0),
  SelectedFile(name: 'DSC005.jpg', sizeMb: 7.5),
];

// ============================================================================
// 辅助常量
// ============================================================================

/// 测试用 Token：与 spec/05 §4.2 ConnectionMock 行为对齐。
/// ConnectionMock.connect(ip, token) 仅当 token == '123456' 时通过。
const String mockValidToken = '123456';

/// DiscoveryService 扫描窗口（毫秒）。
const Duration discoveryWindow = Duration(seconds: 5);

/// 默认 HTTP 端口。
const int defaultHttpPort = 8765;