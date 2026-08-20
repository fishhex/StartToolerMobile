// lib/ui/tokens/spacing.dart
//
// 8pt 间距系统（对齐 D06 §4.3）。

class AppSpace {
  AppSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// 页面标准内边距：水平 md，垂直 lg。
  static const double pagePaddingH = md;
  static const double pagePaddingV = lg;
}