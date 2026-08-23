// lib/core/health_api.dart
//
// /api/v1/health 客户端（直连真实 PC，无 mock）。
//
// 协议参考 doc/knowledge-base/API-01-http-routes.md §3.1。

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import 'app_error.dart';
import 'result.dart';

class Health {
  const Health({
    required this.name,
    required this.version,
    required this.port,
    required this.secret,
    required this.currentProject,
  });

  final String name;
  final String version;
  final int port;
  final String secret;
  final String currentProject;

  factory Health.fromJson(Map<String, dynamic> j) => Health(
        name: j['name'] as String,
        version: j['version'] as String,
        port: j['port'] as int,
        secret: j['secret'] as String,
        currentProject: j['currentProject'] as String,
      );
}

class HealthApi {
  HealthApi({http.Client? client, Duration? defaultTimeout})
      : _client = client ?? http.Client(),
        _defaultTimeout = defaultTimeout ?? const Duration(seconds: 3);

  final http.Client _client;
  final Duration _defaultTimeout;

  Future<Result<Health, AppError>> check(
    String host,
    int port, {
    Duration? timeout,
  }) async {
    final t = timeout ?? _defaultTimeout;
    final uri = Uri.parse('http://$host:$port/api/v1/health');
    dev.log('→ 请求 $uri 超时=$t', name: '健康检查');
    try {
      final resp = await _client.get(uri).timeout(t);
      debugPrint('[健康] ← 状态码 ${resp.statusCode} 响应体 ${resp.body}');
      dev.log('← 状态码 ${resp.statusCode} 响应体 ${resp.body}', name: '健康检查');
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        return Ok(Health.fromJson(body));
      }
      return Err(HttpError('health ${resp.statusCode}', status: resp.statusCode));
    } on SocketException catch (e) {
      dev.log('网络异常: ${e.message}', name: '健康检查', error: e);
      return Err(NetworkUnreachable('连不上 PC', cause: e.message));
    } on TimeoutException catch (e) {
      dev.log('请求超时: ${e.message}', name: '健康检查', error: e);
      return Err(NetworkTimeout('PC 不可达，超时', cause: e.message));
    } on http.ClientException catch (e) {
      dev.log('客户端异常: ${e.message}', name: '健康检查', error: e);
      return Err(NetworkUnreachable('连不上 PC', cause: e.message));
    } catch (e, st) {
      dev.log('未知错误: $e', name: '健康检查', error: e, stackTrace: st);
      return Err(UnknownError('health 未知错误', cause: e.toString()));
    }
  }
}