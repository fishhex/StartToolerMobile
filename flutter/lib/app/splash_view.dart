// lib/app/splash_view.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_state.dart';
import '../ui/components/starfield_bg.dart';
import '../ui/tokens/colors.dart';
import '../ui/tokens/spacing.dart';
import '../ui/tokens/typography.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      AppState.stage = AppStage.disconnected;
      context.go('/connect');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StarfieldBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.nebula400.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.nebula400, width: 2),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: AppColors.nebula400, size: 44),
              ),
              const SizedBox(height: AppSpace.lg),
              Text('StartTooler',
                  style: AppTextStyle.displayMd
                      .copyWith(color: AppColors.star100)),
              const SizedBox(height: AppSpace.sm),
              Text('星助 · 把手机的照片推到 PC',
                  style: AppTextStyle.bodyMd
                      .copyWith(color: AppColors.star300)),
              const SizedBox(height: AppSpace.xl),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.nebula400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}