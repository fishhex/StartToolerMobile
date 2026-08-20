// lib/core/app_error.dart

/// 全局错误类型（对齐 spec/05 §六）。
enum AppErrorKind {
  network,
  invalidToken,
  pcOffline,
  serverError,
  /// §4 unsupported_ver：协议版本不兼容
  unsupported,
  unknown,
}

class AppError implements Exception {
  AppError(this.kind, this.message);

  final AppErrorKind kind;
  final String message;

  @override
  String toString() => 'AppError($kind): $message';
}