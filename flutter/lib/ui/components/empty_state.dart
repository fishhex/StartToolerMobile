// lib/ui/components/empty_state.dart

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// 空状态：居中图标 + 文案 + CTA。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.star300),
            const SizedBox(height: AppSpace.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyle.displayMd.copyWith(color: AppColors.star100),
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: AppTextStyle.bodyMd.copyWith(color: AppColors.star200),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpace.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}