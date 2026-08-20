// lib/ui/components/starfield_bg.dart

import 'dart:math';

import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// 静态星空背景：3 层径向渐变 + 30 颗静态星点。
class StarfieldBackground extends StatelessWidget {
  const StarfieldBackground({super.key, this.child, this.starCount = 30});

  final Widget? child;
  final int starCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.3),
              radius: 1.2,
              colors: [
                AppColors.space800,
                AppColors.space900,
              ],
            ),
          ),
        ),
        CustomPaint(
          painter: _StarsPainter(seed: 42, count: starCount),
        ),
        if (child != null) child!,
      ],
    );
  }
}

class _StarsPainter extends CustomPainter {
  _StarsPainter({required this.seed, required this.count});

  final int seed;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final paint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < count; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final r = rng.nextDouble() * 1.4 + 0.3;
      final opacity = rng.nextDouble() * 0.5 + 0.3;
      paint.color = AppColors.star100.withValues(alpha: opacity);
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter oldDelegate) =>
      oldDelegate.seed != seed || oldDelegate.count != count;
}