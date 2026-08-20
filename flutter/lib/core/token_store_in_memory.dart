// lib/core/token_store_in_memory.dart
//
// M2 阶段 TokenStore 实现：纯内存版。
// - 不落盘（App 进程被回收重启时 token 由 UDP 广播重新注入）
// - 后续阶段可换 SecureTokenStore（flutter_secure_storage → Keychain / EncryptedSharedPreferences）
//
// 对齐 D03 §3.5 覆盖式更新：每次 register() 都无条件覆盖。

import 'dart:async';
import 'dart:developer' as dev;

import 'token.dart';

class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore();

  /// dedupe key = "name|port"（D03 §3.5：name+port 识别同一 PC，IP 浮动）
  final Map<String, ConnectedPC> _pcs = {};

  ConnectedPC? _active;
  final _activeController = StreamController<Token>.broadcast();

  @override
  ConnectedPC? get active => _active;

  @override
  set active(ConnectedPC? pc) {
    _active = pc;
    if (pc != null) {
      // 切换 active 时推一次 token，方便订阅者感知
      _activeController.add(pc.token);
    }
  }

  String _key(String name, int port) => '$name|$port';

  @override
  void register(ConnectedPC pc) {
    final k = _key(pc.name, pc.port);
    final existed = _pcs[k];
    _pcs[k] = pc;
    // D03 §3.5：覆盖式更新，不比较 token 版本
    if (existed == null) {
      dev.log(
        'TokenStore.register new name="${pc.name}" '
        'addr=${pc.ip}:${pc.port} token=${pc.token.masked}',
        name: 'tokenstore',
      );
    } else if (existed.token != pc.token) {
      dev.log(
        'TokenStore.register overwrite name="${pc.name}" '
        'addr=${pc.ip}:${pc.port} '
        'oldToken=${existed.token.masked} '
        'newToken=${pc.token.masked}',
        name: 'tokenstore',
      );
      if (_active?.name == pc.name && _active?.port == pc.port) {
        _active = pc;
      }
    }
    // 通知订阅者：广播 token 来了（用于 401 重试）
    _activeController.add(pc.token);
  }

  @override
  List<ConnectedPC> list() => List.unmodifiable(_pcs.values);

  @override
  ConnectedPC? findByNameAndPort(String name, int port) =>
      _pcs[_key(name, port)];

  @override
  Future<void> clearAll() async {
    _pcs.clear();
    _active = null;
    dev.log('TokenStore.clearAll', name: 'tokenstore');
  }

  @override
  TokenStream watch() => TokenStream(_activeController.stream);

  @override
  Map<String, String> debugSnapshot() {
    return {for (final e in _pcs.entries) e.key: e.value.token.masked};
  }

  /// 测试 / 调试：让外部主动 push token（不通过 register）。
  void debugPush(Token t) => _activeController.add(t);
}
