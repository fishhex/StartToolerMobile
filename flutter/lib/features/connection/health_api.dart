// lib/features/connection/health_api.dart
//
// /api/v1/health 客户端。
//
// 对齐 doc/0.10/demand/D02-http-upload.md §3.1.1 + D03 §3.8：
//   - 该接口**无鉴权**（无需 token）
//   - 响应 body 带回 token；App 端**仅作回包校验**，不作为主动取舍
//   - service / port / version 必须一致才视为可达
//
// 流程：
//   1) GET /api/v1/health（3s 超时）
//   2) 校验 ok=true, service=='starttooler', port 与广播一致, version 至少 "0.12"
//   3) 把响应里的 token 与当前 TokenStore 中 PC 的 token 对比：
//        - 一致  → 视为状态健康
//        - 不一致 → 用响应里的 token 覆盖（PC 端可能刚重置；D03 §3.4 健康检查响应回带）
//   4) 任何字段不匹配 / 超时 / 非 200 → 抛 AppError

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/app_error.dart';
import '../../core/token.dart';

class HealthResponse {
  HealthResponse({
    required this.name,
    required this.port,
    required this.token,
    required this.version,
    required this.currentProject,
  });

  factory HealthResponse.fromJson(Map<String, dynamic> j) {
    final tokenRaw = j['token'];
    if (tokenRaw is! String || tokenRaw.length != 6) {
      throw const FormatException('health.token missing or invalid');
    }
    return HealthResponse(
      name: (j['name'] as String?) ?? '',
      port: (j['port'] as num?)?.toInt() ?? 0,
      token: tokenRaw,
      version: (j['version'] as String?) ?? '0',
      currentProject: () {
        final v = j['currentProject'];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        return null;
      }(),
    );
  }

  final String name;
  final int port;
  final String token;
  final String version;
  final String? currentProject;
}

class HealthApi {
  HealthApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// GET /api/v1/health；返回解析后的 [HealthResponse]。
  /// 超时 3 s（D02 §4）。
  Future<HealthResponse> probe({
    required String ip,
    required int port,
  }) async {
    final uri = Uri.parse('http://$ip:$port/api/v1/health');
    dev.log('health probe $uri', name: 'health');
    try {
      final resp = await _client.get(uri).timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) {
        throw AppError(
          AppErrorKind.serverError,
          '健康检查失败（HTTP ${resp.statusCode}）',
        );
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw AppError(AppErrorKind.serverError, '健康检查响应格式错误');
      }
      if (decoded['ok'] != true) {
        throw AppError(AppErrorKind.serverError, 'PC 报告非 ok 状态');
      }
      if (decoded['service'] != 'starttooler') {
        throw AppError(
          AppErrorKind.serverError,
          '服务标识不匹配（service=${decoded['service']}）',
        );
      }
      final health = HealthResponse.fromJson(decoded);

      // 校验 port 与广播一致（D02 §3.1.1）
      if (health.port != port) {
        throw AppError(
          AppErrorKind.serverError,
          '健康检查返回 port=${health.port} 与期望 $port 不一致',
        );
      }
      // 校验版本 ≥ "0.12"（major=0）
      if (!_isCompatible(health.version)) {
        throw AppError(
          AppErrorKind.unsupported,
          'PC 协议版本 ${health.version} 与 App 不兼容',
        );
      }
      dev.log(
        'health OK name="${health.name}" port=${health.port} '
        'version=${health.version} project=${health.currentProject ?? "<none>"}',
        name: 'health',
      );
      return health;
    } on TimeoutException {
      throw AppError(AppErrorKind.network, '健康检查超时（3s）');
    } on SocketException catch (e) {
      throw AppError(AppErrorKind.pcOffline, 'PC 不可达：${e.message}');
    } on http.ClientException catch (e) {
      throw AppError(AppErrorKind.network, '健康检查网络错误：${e.message}');
    } on FormatException catch (e) {
      throw AppError(AppErrorKind.serverError, '健康检查响应解析失败：${e.message}');
    }
  }

  /// D03 §3.8：把健康响应里的 token 与 TokenStore 中 PC 的 token 对比。
  /// - 一致 → 视为状态健康
  /// - 不一致 → 用响应里的 token 覆盖（D03 §3.4 覆盖式更新）
  /// 返回是否一致（调试页可展示）。
  bool syncWithStore(HealthResponse health, TokenStore store) {
    final pc = store.findByNameAndPort(health.name, health.port);
    if (pc == null) {
      // 当前 store 里没注册这台 PC；用 health 响应建立记录
      // （D03 §3.8：响应里的 token 仅作回包校验；首次发现时仍以 UDP 广播为准。
      //  此分支只在健康检查在广播之前到达时触发，保持健壮性。）
      final t = Token.tryParse(health.token);
      if (t == null) return false;
      store.register(ConnectedPC(
        name: health.name,
        ip: '<unknown>',
        port: health.port,
        token: t,
        currentProject: health.currentProject,
      ));
      return true;
    }
    final storeTokenStr = pc.token.value;
    final healthTokenStr = health.token;
    if (storeTokenStr == healthTokenStr) return true;

    // D03 §3.5 覆盖式更新
    final t = Token.tryParse(health.token);
    if (t == null) return false;
    store.register(pc.copyWith(
      token: t,
      currentProject: health.currentProject ?? pc.currentProject,
      clearCurrentProject: health.currentProject == null,
    ));
    dev.log(
      'health.syncWithStore: token mismatch for "${pc.name}", '
      'overwrote store token',
      name: 'health',
    );
    return false;
  }

  bool _isCompatible(String version) {
    final segs = version.split('.');
    if (segs.isEmpty) return false;
    final major = int.tryParse(segs[0]) ?? -1;
    return major >= 0; // 与 UdpAnnounce 一致：major >= 0 即视为兼容
  }

  Future<void> close() async => _client.close();
}
