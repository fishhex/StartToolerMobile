// lib/main.dart
//
// v0.14 App 入口：组装 Provider 树 + go_router + 全局 banner。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/routes.dart';
import 'core/error_bus.dart';
import 'core/health_api.dart';
import 'core/projects_api.dart';
import 'core/secure_store.dart';
import 'core/spaces_controller.dart';
import 'core/strings.dart';

void main() {
  runApp(const StartToolerApp());
}

class StartToolerApp extends StatelessWidget {
  const StartToolerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SecureStore>(
          create: (_) => AndroidSecureStore(),
        ),
        ChangeNotifierProvider<SpacesController>(
          create: (ctx) => SpacesController(ctx.read<SecureStore>())..load(),
        ),
        Provider<HealthApi>(create: (_) => HealthApi()),
        Provider<ProjectsApi>(create: (_) => ProjectsApi()),
        ChangeNotifierProvider<AppErrorBus>(create: (_) => AppErrorBus()),
      ],
      child: const _AppShell(),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    final router = buildRouter();
    return MaterialApp.router(
      title: 'StartTooler',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      builder: (context, child) {
        final err = context.watch<AppErrorBus>().current;
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (err != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Material(
                    color: Colors.red.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          const Icon(Icons.error, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(child: Text(Strings.formatError(err))),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => context.read<AppErrorBus>().dismiss(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}