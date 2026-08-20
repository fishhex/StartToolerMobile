// lib/ui/tokens/colors.dart
//
// 深色天文主题色板（对齐 D06 §4.1）。
// 命名贴近 spec/05 语义：space / star / nebula / aurora / comet。

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // 深空背景层级
  static const Color space900 = Color(0xFF070B1F);
  static const Color space800 = Color(0xFF0E1430);
  static const Color space700 = Color(0xFF161E45);
  static const Color space600 = Color(0xFF1F2960);

  // 星点 / 文字层级
  static const Color star100 = Color(0xFFEAF0FF);
  static const Color star200 = Color(0xFFB6C2E0);
  static const Color star300 = Color(0xFF6E7BA0);

  // 主题强调：星云紫
  static const Color nebula400 = Color(0xFF7C8CFF);
  static const Color nebula300 = Color(0xFFA5B1FF);

  // 成功：极光绿
  static const Color aurora500 = Color(0xFF41E0C8);
  static const Color aurora600 = Color(0xFF1FB59A);

  // 错误 / 警告：彗星橙
  static const Color comet600 = Color(0xFFFF6F61);
  static const Color comet500 = Color(0xFFFF8B7F);

  // 半透明覆盖
  static Color overlay60 = const Color(0xFF000000).withValues(alpha: 0.60);
  static Color border12 = star100.withValues(alpha: 0.12);
  static Color border08 = star100.withValues(alpha: 0.08);
}