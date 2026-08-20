// lib/features/connection/connection_service.dart

import '../../core/app_error.dart';
import '../../core/mock/seed_data.dart';

abstract class ConnectionService {
  /// 验证 token，成功返回连接的 PC；失败抛 AppError。
  Future<PC> connect({required String ip, required String token});
}

class ConnectionMock implements ConnectionService {
  ConnectionMock();

  PC? _connected;

  PC? get connected => _connected;

  @override
  Future<PC> connect({required String ip, required String token}) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (token != mockValidToken) {
      throw AppError(AppErrorKind.invalidToken, 'Token 错误，请重试');
    }
    final pc = mockPCs.firstWhere(
      (p) => p.ip == ip,
      orElse: () => mockPCs.first,
    );
    _connected = pc;
    return pc;
  }
}