// lib/core/space.dart
//
// Space = 用户曾经连过的 PC 的连接信息。
// T1 阶段：硬编码用于跳转演示。T2 阶段：JSON 序列化 + SecureStore。

class Space {
  const Space({
    required this.name,
    required this.ip,
    required this.port,
    required this.secret,
    required this.lastSeenAt,
  });

  final String name;
  final String ip;
  final int port;
  final String secret;
  final DateTime lastSeenAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'ip': ip,
        'port': port,
        'secret': secret,
        'lastSeenAt': lastSeenAt.toIso8601String(),
      };

  factory Space.fromJson(Map<String, dynamic> j) => Space(
        name: j['name'] as String,
        ip: j['ip'] as String,
        port: j['port'] as int,
        secret: j['secret'] as String,
        lastSeenAt: DateTime.parse(j['lastSeenAt'] as String),
      );
}