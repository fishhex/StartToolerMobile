// lib/core/token.dart
//
// D03 Token 状态机的核心抽象：覆盖式更新 + 持久化接口。
//
// 权威源：UDP 广播 payload["token"]，每次收到新广播都**无条件**覆盖内存。
// 持久化：抽象 TokenStore.save() 留给后续阶段（flutter_secure_storage）；
//         M2 阶段使用 InMemoryTokenStore（仅内存，不跨进程）。
//
// 脱敏：D03 §4「日志中 token 一律 12****56」。

import 'dart:async';

/// 6 位数字 token 的运行时表示。
/// 构造时校验格式，避免外部把空串/非数字传进 TokenStore。
class Token {
  Token._(this.value);

  /// 从字符串解析；不符合 6 位数字约束时返回 null。
  static Token? tryParse(String raw) {
    final s = raw.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(s)) return null;
    return Token._(s);
  }

  final String value;

  /// 脱敏展示：D03 §4 要求日志中 token 一律 `12****56`。
  String get masked {
    if (value.length != 6) return '******';
    return '${value.substring(0, 2)}****${value.substring(4, 6)}';
  }

  @override
  String toString() => 'Token($masked)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Token && other.value == value);

  @override
  int get hashCode => value.hashCode;
}

/// 已连接的 PC 信息（按 `name + port` 识别同一台设备）。
/// 对齐 D03 §3.5「IP 浮动时按 name + port 识别同一 PC」。
class ConnectedPC {
  const ConnectedPC({
    required this.name,
    required this.ip,
    required this.port,
    required this.token,
    this.currentProject,
  });

  /// 机器名（PC 端 Environment.MachineName）。
  final String name;

  /// PC HTTP 服务端口。
  final int port;

  /// 当前 IP（UDP 广播的 sender IP）。
  /// 同 name + port 但 IP 变化时按 D03 §3.5 视为同一 PC，覆盖 token。
  final String ip;

  /// 6 位数字 token。
  final Token token;

  /// 当前激活项目；null 表示 PC 未打开任何项目。
  final String? currentProject;

  ConnectedPC copyWith({
    String? name,
    String? ip,
    int? port,
    Token? token,
    String? currentProject,
    bool clearCurrentProject = false,
  }) {
    return ConnectedPC(
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      token: token ?? this.token,
      currentProject:
          clearCurrentProject ? null : (currentProject ?? this.currentProject),
    );
  }
}

/// Token 状态机抽象。
///
/// 实现要点（对齐 D03 §3.1 / §3.5）：
/// - **权威源是 UDP 广播**，本接口只暴露「写入」（来自广播 + 来自 health 响应校验回包）
///   和「读取」（HTTP 调用方读取当前 token）。
/// - **覆盖式更新**：写入新 token 时不与旧值比较，直接覆盖。
/// - **持久化由实现自行负责**：M2 阶段 InMemoryTokenStore 不落盘；后续阶段接
///   flutter_secure_storage 后转 Keychain / EncryptedSharedPreferences。
abstract class TokenStore {
  /// 注册一个 PC（D03 §3.4：name+ip+port+token+currentProject）。
  /// 同 name+port 视为同一 PC，无条件用 [pc] 覆盖（IP 浮动场景）。
  void register(ConnectedPC pc);

  /// 列出所有已注册 PC（设置页 / 调试用）。
  List<ConnectedPC> list();

  /// 按 (name, port) 取已注册的 PC；未找到返回 null。
  ConnectedPC? findByNameAndPort(String name, int port);

  /// 当前"活跃 PC"：D03 §3.4 约定 App 端一次只连一台 PC，
  /// 由 ConnectionService.connect() 时调用 [setActive]。
  ConnectedPC? get active;
  set active(ConnectedPC? pc);

  /// 清除所有已注册 PC（含 active），用于"切换 PC / 卸载"。
  Future<void> clearAll();

  /// 监听广播 token 更新；订阅者收到的是「最新 token」的值（非事件），
  /// 用于 [AuthenticatedHttpClient] 在 401 时等下一次广播。
  /// 返回当前快照 + 一个 Stream；subscribe 后每次更新都会推一个新值。
  TokenStream watch();

  /// 调试 / 日志用：导出当前所有 token（脱敏）。
  Map<String, String> debugSnapshot();
}

/// 广播 token 变化的流（脱敏后的字符串 + 真实 token 两路都暴露）。
class TokenStream {
  TokenStream(this._controller);

  final Stream<Token> _controller;

  Stream<Token> get stream => _controller;

  /// 取一次「等广播」动作：等待下一帧 token 或 [timeout]。
  /// D03 §3.7：401 → 等下一次广播（≤ 2 s）→ 拿到新 token → 重试一次。
  Future<Token?> awaitNext({
    required Duration timeout,
  }) async {
    final completer = _OnceCompleter<Token>();
    final sub = _controller.listen((t) {
      if (!completer.isCompleted) completer.complete(t);
    });
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      await sub.cancel();
    }
  }
}

/// 一次性 Future 工具，避免 completer 被多次 complete 抛异常。
class _OnceCompleter<T> {
  final _completer = Completer<T>();
  bool get isCompleted => _completer.isCompleted;
  void complete(T value) => _completer.complete(value);
  Future<T> get future => _completer.future;
}
