// lib/ui/components/buttons.dart

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';

/// 主按钮：nebula400 填充，高度 48，star100 文字。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.nebula400,
          disabledBackgroundColor: AppColors.nebula400.withValues(alpha: 0.5),
          foregroundColor: AppColors.space900,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.borderSm),
        ),
        child: loading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.space900,
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Text(loadingLabel ?? label),
                ],
              )
            : Text(label),
      ),
    );
  }
}

/// 次按钮：透明背景 + space600 边框。
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.star100,
          side: const BorderSide(color: AppColors.space600),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.borderSm),
        ),
        child: Text(label),
      ),
    );
  }
}