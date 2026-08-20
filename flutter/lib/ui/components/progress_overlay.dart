// lib/ui/components/progress_overlay.dart

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// 半透明遮罩 + 中心进度 + 文字。
class ProgressOverlay extends StatelessWidget {
  const ProgressOverlay({
    super.key,
    required this.label,
    this.subLabel,
  });

  final String label;
  final String? subLabel;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.overlay60,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: AppColors.space800,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.nebula400),
              const SizedBox(height: AppSpace.md),
              Text(label,
                  style: AppTextStyle.titleMd
                      .copyWith(color: AppColors.star100)),
              if (subLabel != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(subLabel!,
                    style: AppTextStyle.bodyMd
                        .copyWith(color: AppColors.star300)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}