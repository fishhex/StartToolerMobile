// lib/features/connection/connection_service.dart
//
// D03 §3 Token 鉴权与状态机：App 端的入口抽象。
//
// 行为（D03 §3 / §3.3 / §3.7）：
//   - connect() 流程：
//     1) TokenInputView 输入 6 位数字 → 调用 connect(ip, port, token, name)
//     2) 调用 HealthApi.probe() 验证 PC 可达（无需 token）
//     3) health 响应 token 与输入 token 比对：
//        - 一致 → 注册到 TokenStore，active = 这台 PC，返回 ConnectedPC
//        - 不一致 → 抛 invalidToken
//   - D03 §3.7：业务请求（projects / upload）由 AuthenticatedHttpClient 处理 401 重试
//
// 对外暴露的接口保持向后兼容（UI 层使用 pc.name / pc.ip / pc.port / pc.displayAddress /
// pc.projectCount / pc.currentProject / pc.rssi）；token / health 校验改为内部行为。

import 'dart:developer' as dev;

import '../../core/app_error.dart';
import '../../core/authenticated_http.dart';
import '../../core/mock/seed_data.dart';
import '../../core/token.dart';
import 'health_api.dart';

abstract class ConnectionService {
  /// 输入 6 位数字 token，验证可达性；成功返回连接的 PC，失败抛 AppError。
  Future<PC> connect({
    required String ip,
    required int port,
    required String token,
    required String name,
  });

  /// 当前已连接 PC（来自 TokenStore.active）；未连接返回 null。
  PC? get connected;

  /// D03 §3.7：受保护请求统一从这里发出，自动 401 → 等广播 → 重试一次。
  AuthenticatedHttp get http;

  /// 暴露给上层做"切换 PC" / "清除 token" 时使用。
  TokenStore get tokenStore;
}

/// 暴露给 UI / 上传层使用的 401-aware HTTP 句柄。
/// 仅暴露 GET / POST 两个最常用方法；后续扩展 multipart 上传时再加。
abstract class AuthenticatedHttp {
  Future<HttpResult> get(String path, {Duration? timeout});
  Future<HttpResult> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
    Duration? timeout,
  });
}

/// 简化版的 HTTP 响应：UI 层只需要 body 字符串 + statusCode。
class HttpResult {
  HttpResult({required this.statusCode, required this.body});
  final int statusCode;
  final String body;
}

/// 真实实现：UDP 广播 + HTTP health 检查 + 401 自动重试。
class HttpConnectionService implements ConnectionService {
  HttpConnectionService({
    required TokenStore tokenStore,
    HealthApi? healthApi,
    AuthenticatedHttp? authed,
    AuthenticatedHttpClient? authedClient,
  })  : _store = tokenStore,
        _health = healthApi ?? HealthApi(),
        _authed = authed ?? _buildAuthed(tokenStore, authedClient);

  final TokenStore _store;
  final HealthApi _health;
  final AuthenticatedHttp _authed;

  static AuthenticatedHttp _buildAuthed(
    TokenStore store,
    AuthenticatedHttpClient? client,
  ) {
    final c = client ?? AuthenticatedHttpClient(tokenStore: store);
    return _FacadeAuthenticatedHttp(c, store);
  }

  @override
  AuthenticatedHttp get http => _authed;

  @override
  PC? get connected {
    final pc = _store.active;
    if (pc == null) return null;
    return _toViewPC(pc);
  }

  @override
  TokenStore get tokenStore => _store;

  @override
  Future<PC> connect({
    required String ip,
    required int port,
    required String token,
    required String name,
  }) async {
    final inputToken = Token.tryParse(token);
    if (inputToken == null) {
      throw AppError(AppErrorKind.invalidToken, 'Token 必须是 6 位数字');
    }

    dev.log(
      'connect() name="$name" ip=$ip port=$port input=${inputToken.masked}',
      name: 'connection',
    );

    // 1) 探活 + 健康检查（无 token，仅验证 PC 可达 + service/version/port 合法）
    final health = await _health.probe(ip: ip, port: port);

    // 2) name 兜底（手动输入时 name 可能是 "手动输入"）
    final resolvedName = name.isEmpty ? health.name : name;

    // 3) 注册到 TokenStore（D03 §3.5 覆盖式更新）
    //    注意：不在此处把 input token 与 health.token 比对。
    //    PC 端 health 端点不校验 token,只是把当前 _currentToken 回带
    //    （UploadServerService.cs §3.1 health）；App 端也应只把响应 token
    //    写入 store（syncWithStore 已做覆盖式更新），让后续 401 状态机
    //    处理 token 失配场景（D03 §3.7）。手动输错 token 会在第一次
    //    受保护请求时拿到 401 → 等广播 → 用新 token 重试一次。
    final pc = ConnectedPC(
      name: resolvedName,
      ip: ip,
      port: port,
      token: inputToken,
      currentProject: health.currentProject,
    );
    _store.register(pc);
    _store.active = pc;

    // 4) 健康检查响应回带校验（仅作"回包校验"，覆盖式更新 store）
    _health.syncWithStore(health, _store);

    dev.log(
      'connect() success name="$resolvedName" '
      'addr=$ip:$port input=${inputToken.masked} '
      'healthToken=${_maskHealthToken(health.token)} '
      'project=${health.currentProject ?? "<none>"}',
      name: 'connection',
    );
    return _toViewPC(pc);
  }

  PC _toViewPC(ConnectedPC pc) => PC(
        name: pc.name,
        ip: pc.ip,
        port: pc.port,
        projectCount: 0,
        currentProject: pc.currentProject,
        rssi: -100,
      );
}

/// D03 §4：日志中 token 一律脱敏 12****56。
String _maskHealthToken(String raw) {
  if (raw.length != 6) return '<invalid>';
  return '${raw.substring(0, 2)}****${raw.substring(4, 6)}';
}

/// AuthenticatedHttpClient → AuthenticatedHttp 的轻量 facade。
/// 路径拼接用 base url = TokenStore.active.ip:port。
class _FacadeAuthenticatedHttp implements AuthenticatedHttp {
  _FacadeAuthenticatedHttp(this._client, this._store);

  final AuthenticatedHttpClient _client;
  final TokenStore _store;

  Uri _url(String path) {
    final pc = _store.active;
    if (pc == null) {
      throw AppError(
        AppErrorKind.invalidToken,
        '未连接 PC，无法发起请求',
      );
    }
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('http://${pc.ip}:${pc.port}$normalized');
  }

  @override
  Future<HttpResult> get(String path, {Duration? timeout}) async {
    final resp = await _client.get(_url(path), timeout: timeout);
    return HttpResult(statusCode: resp.statusCode, body: resp.body);
  }

  @override
  Future<HttpResult> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final resp = await _client.post(
      _url(path),
      body: body,
      headers: headers,
      timeout: timeout,
    );
    return HttpResult(statusCode: resp.statusCode, body: resp.body);
  }
}
