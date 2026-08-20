// lib/ui/components/connection_progress.dart

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// 5 秒扫描倒计时环形进度 + 文字。
class ConnectionProgress extends StatelessWidget {
  const ConnectionProgress({
    super.key,
    required this.elapsed,
    required this.total,
    this.label = '正在扫描...',
  });

  final Duration elapsed;
  final Duration total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2.5,
            color: AppColors.nebula400,
            backgroundColor: AppColors.space700,
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Text(label,
            style: AppTextStyle.bodyMd.copyWith(color: AppColors.star200)),
        const Spacer(),
        Text(
          '${(total.inSeconds - elapsed.inSeconds).clamp(0, total.inSeconds)}s',
          style: AppTextStyle.bodyMd.copyWith(color: AppColors.star300),
        ),
      ],
    );
  }
}