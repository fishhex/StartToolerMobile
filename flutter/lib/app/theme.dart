// lib/app/theme.dart
//
// 全局 ThemeData：深色天文主题。
// Material 3，ColorScheme.fromSeed + 自定义覆盖。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/tokens/colors.dart';
import '../ui/tokens/radii.dart';
import '../ui/tokens/spacing.dart';
import '../ui/tokens/typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.space900,
        onSurface: AppColors.star100,
        primary: AppColors.nebula400,
        onPrimary: AppColors.space900,
        secondary: AppColors.aurora500,
        onSecondary: AppColors.space900,
        error: AppColors.comet600,
        onError: AppColors.space900,
      ),
      scaffoldBackgroundColor: AppColors.space900,
      fontFamily: null,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.space700,
        foregroundColor: AppColors.star100,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.star100,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      textTheme: TextTheme(
        displayLarge: AppTextStyle.displayLg.copyWith(color: AppColors.star100),
        displayMedium: AppTextStyle.displayMd.copyWith(color: AppColors.star100),
        titleLarge: AppTextStyle.titleLg.copyWith(color: AppColors.star100),
        titleMedium: AppTextStyle.titleMd.copyWith(color: AppColors.star100),
        bodyLarge: AppTextStyle.bodyLg.copyWith(color: AppColors.star100),
        bodyMedium: AppTextStyle.bodyMd.copyWith(color: AppColors.star200),
        bodySmall: AppTextStyle.caption.copyWith(color: AppColors.star300),
      ),
      dividerColor: AppColors.border12,
      iconTheme: const IconThemeData(color: AppColors.star100),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.nebula400,
        linearTrackColor: AppColors.space700,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.space800,
        modalBackgroundColor: AppColors.space800,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderLg),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.space800,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.space700,
        contentTextStyle: TextStyle(color: AppColors.star100),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 页面标准内边距常量，供各页面统一引用。
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: AppSpace.pagePaddingH,
    vertical: AppSpace.pagePaddingV,
  );
}