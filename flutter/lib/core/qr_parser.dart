// lib/core/qr_parser.dart
//
// 纯函数：QR 文本 → QrPayload | QrError
//
// 协议参考 doc/knowledge-base/API-04-qr-protocol.md
//   形如: http://192.168.1.10:9527/upload?k=<32位hex>

sealed class QrError implements Exception {
  const QrError(this.message);
  final String message;
  @override
  String toString() => 'QrError: $message';
}

class QrInvalidFormat extends QrError {
  const QrInvalidFormat(super.message);
}

class QrInvalidHost extends QrError {
  const QrInvalidHost(super.message);
}

class QrInvalidPort extends QrError {
  const QrInvalidPort(super.message);
}

class QrMissingSecret extends QrError {
  const QrMissingSecret(super.message);
}

class QrPayload {
  const QrPayload({required this.host, required this.port, required this.secret});
  final String host;
  final int port;
  final String secret;
}

/// 解析 QR 文本，失败抛出 [QrError]。
QrPayload parseQr(String input) {
  final raw = input.trim();
  if (raw.isEmpty) {
    throw const QrInvalidFormat('QR 内容为空');
  }

  final uri = Uri.tryParse(raw);
  if (uri == null) {
    throw const QrInvalidFormat('QR 内容不是合法 URI');
  }
  if (uri.scheme != 'http') {
    throw const QrInvalidFormat('QR 协议必须是 http');
  }
  if (uri.path != '/upload') {
    throw const QrInvalidFormat('QR 路径必须是 /upload');
  }

  final host = uri.host;
  if (host.isEmpty) {
    throw const QrInvalidHost('QR 缺少 host');
  }
  if (!_isValidIp(host)) {
    throw const QrInvalidHost('QR host 不是合法 IPv4/IPv6');
  }

  final port = uri.port;
  if (port <= 0 || port > 65535) {
    throw const QrInvalidPort('QR port 必须在 1-65535');
  }

  // secret: ?k=<32位hex>（取第一个出现的；多个 ?k= 时忽略其余）
  String? secret;
  if (uri.query.isNotEmpty) {
    for (final part in uri.query.split('&')) {
      final kv = part.split('=');
      if (kv.length == 2 && kv[0] == 'k') {
        secret = Uri.decodeQueryComponent(kv[1]);
        break;
      }
    }
  }
  if (secret == null || secret.isEmpty) {
    throw const QrMissingSecret('QR 缺少 ?k= secret');
  }
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(secret)) {
    throw const QrMissingSecret('QR secret 必须是 32 位十六进制');
  }

  return QrPayload(host: host, port: port, secret: secret);
}

bool _isValidIp(String host) {
  if (host.contains(':')) {
    // IPv6 粗校验：不能为空段，且不含非 hex / : 字符
    return RegExp(r'^[0-9a-fA-F:]+$').hasMatch(host) && host.split(':').length >= 3;
  }
  // IPv4: 4 段，每段 0-255
  final parts = host.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    if (p.isEmpty) return false;
    final n = int.tryParse(p);
    if (n == null) return false;
    if (n < 0 || n > 255) return false;
  }
  return true;
}