// lib/ui/components/cards.dart

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// 卡片基类：space800 表面 + 1px 边框 + 12 圆角。
class _BaseCard extends StatelessWidget {
  const _BaseCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        color: AppColors.space800,
        borderRadius: AppRadius.borderMd,
        border: Border.all(color: AppColors.border12, width: 1),
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      child: child,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.borderMd,
        child: card,
      ),
    );
  }
}

/// PC 列表项：PC 名 + IP:端口 + 项目数 + 已连接标记。
class PCCard extends StatelessWidget {
  const PCCard({
    super.key,
    required this.name,
    required this.address,
    required this.projectCount,
    this.connected = false,
    this.onTap,
  });

  final String name;
  final String address;
  final int projectCount;
  final bool connected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _BaseCard(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(Icons.desktop_mac_outlined,
              color: AppColors.nebula400, size: 28),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyle.titleMd.copyWith(color: AppColors.star100),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  address,
                  style: AppTextStyle.bodyMd.copyWith(color: AppColors.star200),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '$projectCount 个项目',
                  style: AppTextStyle.caption.copyWith(color: AppColors.star300),
                ),
              ],
            ),
          ),
          if (connected)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.sm,
                vertical: AppSpace.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.aurora500.withValues(alpha: 0.15),
                borderRadius: AppRadius.borderSm,
              ),
              child: Text(
                '已连接',
                style: AppTextStyle.caption.copyWith(color: AppColors.aurora500),
              ),
            )
          else
            const Icon(Icons.chevron_right, color: AppColors.star300),
        ],
      ),
    );
  }
}

/// 项目列表项：项目名 + 文件数 + 大小 + 当前态标记。
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.name,
    required this.fileCount,
    required this.sizeLabel,
    this.isCurrent = false,
    this.onTap,
    this.trailing,
  });

  final String name;
  final int fileCount;
  final String sizeLabel;
  final bool isCurrent;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _BaseCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            isCurrent
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            color: isCurrent ? AppColors.nebula400 : AppColors.star300,
            size: 20,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyle.titleMd.copyWith(color: AppColors.star100),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '$fileCount 文件 · $sizeLabel',
                  style: AppTextStyle.bodyMd.copyWith(color: AppColors.star300),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}