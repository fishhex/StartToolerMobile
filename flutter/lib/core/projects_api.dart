// lib/core/projects_api.dart
//
// /api/v1/projects 客户端（直连真实 PC，无 mock）。
//
// 协议参考 doc/knowledge-base/API-01-http-routes.md §3.2。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_error.dart';
import 'result.dart';

class Project {
  const Project({
    required this.name,
    required this.isCurrent,
    required this.fileCount,
    required this.sizeBytes,
  });

  final String name;
  final bool isCurrent;
  final int fileCount;
  final int sizeBytes;

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        name: j['name'] as String,
        isCurrent: j['isCurrent'] as bool,
        fileCount: j['fileCount'] as int,
        sizeBytes: j['sizeBytes'] as int,
      );
}

class ProjectsApi {
  ProjectsApi({http.Client? client, Duration? defaultTimeout})
      : _client = client ?? http.Client(),
        _defaultTimeout = defaultTimeout ?? const Duration(seconds: 3);

  final http.Client _client;
  final Duration _defaultTimeout;

  Future<Result<List<Project>, AppError>> list(
    String host,
    int port,
    String secret, {
    Duration? timeout,
  }) async {
    final t = timeout ?? _defaultTimeout;
    final uri = Uri.parse('http://$host:$port/api/v1/projects?k=$secret');
    try {
      final resp = await _client.get(uri).timeout(t);
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = (body['projects'] as List<dynamic>)
            .map((e) => Project.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
        return Ok(list);
      }
      if (resp.statusCode == 401) {
        return const Err(AuthError('PC 端密钥已重置，请重新扫码', reason: 'expired'));
      }
      return Err(HttpError('projects ${resp.statusCode}', status: resp.statusCode));
    } on SocketException catch (e) {
      return Err(NetworkUnreachable('连不上 PC', cause: e.message));
    } on TimeoutException catch (e) {
      return Err(NetworkTimeout('PC 不可达，超时', cause: e.message));
    } on http.ClientException catch (e) {
      return Err(NetworkUnreachable('连不上 PC', cause: e.message));
    } catch (e) {
      return Err(UnknownError('projects 未知错误', cause: e.toString()));
    }
  }
}