// lib/core/authenticated_http.dart
//
// 401-aware HTTP client：D03 §3.7 鉴权状态机的核心。
//
// 流程：
//   1) 取出当前 active token
//   2) 发请求（受保护接口带 ?token=xxx 或 X-Token: xxx）
//   3) 401 → 等下一次广播（≤ 2 s）→ 拿到新 token 后**重试一次**
//   4) 仍 401 → 抛 TokenRejectedException（让 ConnectionService 走兜底）
//
// 注意：
//   - **不在 health 上加 401 重试**（health 无鉴权；调用方自己处理）
//   - 只对受保护接口（projects / upload）使用本 client
//   - 不重试非 401 错误（4xx/5xx 走业务层处理）

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_error.dart';
import 'token.dart';

/// 401 重试仍失败 → 抛此异常；ConnectionService 收到后跳"请重新发现"。
class TokenRejectedException implements Exception {
  TokenRejectedException(this.message);
  final String message;
  @override
  String toString() => 'TokenRejectedException: $message';
}

class AuthenticatedHttpClient {
  AuthenticatedHttpClient({
    required this.tokenStore,
    http.Client? inner,
    Duration retryWaitTimeout = const Duration(milliseconds: 2000),
  })  : _inner = inner ?? http.Client(),
        _retryWaitTimeout = retryWaitTimeout;

  final TokenStore tokenStore;
  final http.Client _inner;

  /// D03 §3.7：等下一次广播最长 2 s；不要超过 2.5 s（用户体验差）。
  final Duration _retryWaitTimeout;

  /// 发送受保护请求：带 token；401 → 等广播 → 重试一次。
  /// 已传 [overrideToken] 时跳过 store（用于 health 响应里带回的 token 主动比较）。
  Future<http.Response> get(
    Uri url, {
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    return _sendWithRetry(
      method: 'GET',
      url: url,
      query: query,
      timeout: timeout ?? const Duration(seconds: 5),
    );
  }

  Future<http.Response> post(
    Uri url, {
    Map<String, String>? query,
    Object? body,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    return _sendWithRetry(
      method: 'POST',
      url: url,
      query: query,
      body: body,
      headers: headers,
      timeout: timeout ?? const Duration(seconds: 60),
    );
  }

  Future<http.Response> _sendWithRetry({
    required String method,
    required Uri url,
    Map<String, String>? query,
    Object? body,
    Map<String, String>? headers,
    required Duration timeout,
  }) async {
    final token = tokenStore.active?.token;
    if (token == null) {
      throw AppError(
        AppErrorKind.invalidToken,
        '未连接 PC，无法发起请求',
      );
    }
    final q = Map<String, String>.of(query ?? const {});
    q['token'] = token.value;

    final uri = url.replace(queryParameters: q);

    dev.log(
      'http $method $uri (token=${token.masked}, timeout=$timeout)',
      name: 'authhttp',
    );

    final resp = await _tryRequest(
      method: method,
      url: uri,
      body: body,
      headers: headers,
      timeout: timeout,
    );

    if (resp.statusCode != 401) return resp;

    // ===== 401：等下一次广播 + 重试一次 =====
    dev.log(
      'http $method $uri returned 401, waiting for next broadcast '
      '(max ${_retryWaitTimeout.inMilliseconds}ms)',
      name: 'authhttp',
    );
    final newToken = await tokenStore.watch().awaitNext(
      timeout: _retryWaitTimeout,
    );
    if (newToken == null) {
      dev.log(
        'http $method $uri: no new broadcast within '
        '${_retryWaitTimeout.inMilliseconds}ms, giving up',
        name: 'authhttp',
      );
      throw TokenRejectedException('PC 已拒绝当前 Token（等广播超时）');
    }
    dev.log(
      'http $method $uri: got new broadcast token=${newToken.masked}, '
      'retrying once',
      name: 'authhttp',
    );

    final retryQ = Map<String, String>.of(query ?? const {});
    retryQ['token'] = newToken.value;
    final retryUri = url.replace(queryParameters: retryQ);
    final retry = await _tryRequest(
      method: method,
      url: retryUri,
      body: body,
      headers: headers,
      timeout: timeout,
    );
    if (retry.statusCode == 401) {
      dev.log(
        'http $method $retryUri: retry still 401, surfacing '
        'TokenRejectedException',
        name: 'authhttp',
      );
      throw TokenRejectedException(
          'PC 已拒绝当前 Token（重试仍 401），请重新发现');
    }
    return retry;
  }

  Future<http.Response> _tryRequest({
    required String method,
    required Uri url,
    Object? body,
    Map<String, String>? headers,
    required Duration timeout,
  }) async {
    final h = Map<String, String>.of(headers ?? const {});
    h.putIfAbsent('X-Token', () => _tokenFromUri(url));
    try {
      switch (method) {
        case 'GET':
          return await _inner.get(url, headers: h).timeout(timeout);
        case 'POST':
          return await _inner.post(url, headers: h, body: body).timeout(timeout);
        default:
          throw ArgumentError('unsupported method: $method');
      }
    } on TimeoutException {
      throw AppError(
        AppErrorKind.network,
        '请求超时（${timeout.inSeconds}s）',
      );
    } on SocketException catch (e) {
      throw AppError(
        AppErrorKind.pcOffline,
        'PC 不可达：${e.message}',
      );
    } on http.ClientException catch (e) {
      throw AppError(
        AppErrorKind.network,
        '网络错误：${e.message}',
      );
    }
  }

  String _tokenFromUri(Uri url) =>
      url.queryParameters['token'] ?? '';

  Future<void> close() async => _inner.close();
}
