// lib/core/strings.dart
//
// v0.14 中文 strings —— T4 起收敛所有错误 / UI 字符串。
// 协议参考 doc/knowledge-base/API-06-error-i18n.md。
//
// 本期范围：仅中文（无英文 fallback）；未来引入 flutter_localizations + arb。

import '../core/app_error.dart';

class Strings {
  static const appTitle = 'StartTooler';

  // 错误码
  static const errorUnauthorized = 'PC 端密钥已重置，请重新扫码';
  static const errorNetworkUnreachable = '连不上 PC，请检查网络';
  static const errorTimeout = 'PC 不可达，超时';
  static const errorQrInvalid = '二维码无效';
  static const errorHttpPrefix = 'PC 端返回错误';
  static const errorCameraPermissionRequired = '需要相机权限才能扫码';

  // 路由
  static const pageConnect = '扫码连接';
  static const pageHome = '首页';
  static const pageSwitchSpace = '切换空间';
  static const pageSettings = '设置';

  // 上传失败分桶 reason
  static String uploadFailureReason(String kindName, String? detail) {
    if (detail != null && detail.isNotEmpty) return detail;
    return kindName;
  }

  /// 把 AppError / Object 收敛到中文 banner 文本。
  static String formatError(Object? err) {
    if (err == null) return '';
    if (err is AuthError) return errorUnauthorized;
    if (err is NetworkUnreachable) return errorNetworkUnreachable;
    if (err is NetworkTimeout) return errorTimeout;
    if (err is HttpError) return '$errorHttpPrefix（${err.status}）';
    return err.toString();
  }
}