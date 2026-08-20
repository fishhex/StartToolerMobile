// lib/ui/tokens/typography.dart
//
// 字体系统（对齐 D06 §4.2）。
// iOS / Android 使用系统字体，中文回退系统默认。

import 'package:flutter/material.dart';

class AppTextStyle {
  AppTextStyle._();

  static const TextStyle displayLg = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const TextStyle displayMd = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const TextStyle titleLg = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle titleMd = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle bodyLg = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle bodyMd = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// 用于 Token 6 格输入，等宽。
  static const TextStyle mono = TextStyle(
    fontSize: 28,
    fontFamily: 'monospace',
    fontWeight: FontWeight.w600,
    height: 1.0,
  );
}