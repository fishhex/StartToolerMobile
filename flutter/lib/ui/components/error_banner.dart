// lib/ui/components/error_banner.dart

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// 顶部错误条幅：4px 高条幅 + 文字 + 关闭按钮。
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    this.level = BannerLevel.warn,
    this.onClose,
    this.onAction,
    this.actionLabel,
  });

  final String message;
  final BannerLevel level;
  final VoidCallback? onClose;
  final VoidCallback? onAction;
  final String? actionLabel;

  Color get _bg => switch (level) {
        BannerLevel.info => AppColors.space700,
        BannerLevel.warn => AppColors.comet500.withValues(alpha: 0.20),
        BannerLevel.error => AppColors.comet600.withValues(alpha: 0.25),
      };

  Color get _accent => switch (level) {
        BannerLevel.info => AppColors.star200,
        BannerLevel.warn => AppColors.comet500,
        BannerLevel.error => AppColors.comet600,
      };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        color: _bg,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: _accent, size: 20),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                message,
                style: AppTextStyle.bodyMd.copyWith(color: AppColors.star100),
              ),
            ),
            if (onAction != null && actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: _accent),
                child: Text(actionLabel!),
              ),
            if (onClose != null)
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.star300,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }
}

enum BannerLevel { info, warn, error }