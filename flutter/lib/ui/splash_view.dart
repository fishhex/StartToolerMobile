// lib/ui/splash_view.dart
//
// T2：splash 阶段读持久化 current space → health 验证 → 跳 /home 或 /connect。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/error_bus.dart';
import '../core/health_api.dart';
import '../core/spaces_controller.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // 给个最小 splash 时间，避免闪屏
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final spaces = context.read<SpacesController>();
    final health = context.read<HealthApi>();
    final errBus = context.read<AppErrorBus>();

    final active = spaces.active;
    if (active == null) {
      if (mounted) context.go('/connect');
      return;
    }

    final result = await health.check(active.ip, active.port);
    if (!mounted) return;

    result.when(
      ok: (_) => context.go('/home'),
      err: (e) {
        errBus.push(e);
        // 工作空间保留 → 仍然跳 /connect，让用户重新扫码
        context.go('/connect');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('StartTooler', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600)),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}