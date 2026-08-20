// lib/features/discovery/v1/nonce_cache.dart
//
// Nonce 缓存：用于防 discover_req 重放。
// 文档：doc/app/02-pc-udp-protocol.md §3.2 + §6

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import '../udp_log.dart';
import 'protocol_v1.dart';

class NonceCache {
  NonceCache({
    Duration ttl = const Duration(milliseconds: 3000),
    int maxEntries = 256,
  })  : _ttl = ttl,
        _maxEntries = maxEntries;

  final Duration _ttl;
  final int _maxEntries;

  final HashMap<String, DateTime> _seen = HashMap();

  /// 生成一个 16 字节随机 nonce（Base64 URL-safe）。
  String generate() {
    final rnd = Random.secure();
    final raw = Uint8List(ProtocolV1Const.nonceBytes);
    for (var i = 0; i < raw.length; i++) {
      raw[i] = rnd.nextInt(256);
    }
    return B64.encode(raw);
  }

  /// 记住一个 nonce（发出 discover_req 后调用）。
  /// 超过 TTL 自动过期；超过 _maxEntries 触发 LRU 截断。
  void remember(String nonce) {
    _evictExpired();
    if (_seen.length >= _maxEntries) {
      // 简化：清掉最早 50%。
      final drop = _seen.length ~/ 2;
      final keys = _seen.keys.toList(growable: false);
      for (var i = 0; i < drop; i++) {
        _seen.remove(keys[i]);
      }
      UdpLog.udp('NonceCache truncated to ${_seen.length} entries');
    }
    _seen[nonce] = DateTime.now();
  }

  /// 校验：nonce 是我们发过的，且未过期。
  /// 校验成功后立刻消费（防止同一 resp 被多次接受）。
  bool verifyAndConsume(String nonce) {
    _evictExpired();
    final issuedAt = _seen.remove(nonce);
    if (issuedAt == null) {
      UdpLog.udp('NonceCache: nonce not found or already consumed: '
          '${nonce.substring(0, 8)}...');
      return false;
    }
    if (DateTime.now().difference(issuedAt) > _ttl) {
      UdpLog.udp('NonceCache: nonce expired: ${nonce.substring(0, 8)}...');
      return false;
    }
    return true;
  }

  void _evictExpired() {
    final now = DateTime.now();
    _seen.removeWhere((_, t) => now.difference(t) > _ttl);
  }

  void clear() {
    _seen.clear();
    UdpLog.udp('NonceCache cleared');
  }

  int get size => _seen.length;
}