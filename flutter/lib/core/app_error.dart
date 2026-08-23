// lib/core/app_error.dart
//
// 统一错误类型 —— T1 先放占位实现，T4 收敛全量错误码 + i18n。

sealed class AppError implements Exception {
  const AppError(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

class NetworkError extends AppError {
  const NetworkError(super.message, {this.cause});
  final String? cause;
}

class NetworkUnreachable extends NetworkError {
  const NetworkUnreachable(super.message, {super.cause});
}

class NetworkTimeout extends NetworkError {
  const NetworkTimeout(super.message, {super.cause});
}

class HttpError extends AppError {
  const HttpError(super.message, {required this.status});
  final int status;
}

class AuthError extends AppError {
  const AuthError(super.message, {this.reason});
  final String? reason;
}

class UnknownError extends AppError {
  const UnknownError(super.message, {this.cause});
  final String? cause;
}