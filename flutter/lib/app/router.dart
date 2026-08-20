// lib/app/router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/app_state.dart';
import '../features/connection/connection_service.dart';
import '../features/connection/manual_input_view.dart';
import '../features/connection/token_input_view.dart';
import '../features/discovery/discovery_service.dart';
import '../features/discovery/discovery_view.dart';
import '../features/project/project_service.dart';
import '../features/project/project_switcher.dart';
import '../features/upload/upload_service.dart';
import '../features/upload/upload_view.dart';
import 'settings_view.dart';
import 'splash_view.dart';

GoRouter buildRouter({
  required DiscoveryService discovery,
  required ConnectionService connection,
  required ProjectService projects,
  required UploadService uploader,
}) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (ctx, state) {
      final loc = state.matchedLocation;
      if (loc == '/splash') return null;
      if (AppState.stage == AppStage.splash) return '/splash';
      // 已连接时不能访问 /connect 系列
      if (AppState.stage == AppStage.connected &&
          (loc == '/connect' || loc.startsWith('/connect/'))) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashView()),
      GoRoute(
        path: '/connect',
        builder: (_, __) => DiscoveryView(service: discovery),
        routes: [
          GoRoute(
            path: 'token',
            builder: (ctx, state) {
              final extra = state.extra as Map<String, String>?;
              return TokenInputView(
                connection: connection,
                ip: extra?['ip'] ?? '192.168.1.10',
                pcName: extra?['name'] ?? 'PC',
              );
            },
          ),
          // T-M1-3 · 手动输入兜底页（IP + Port + Token 三字段）。
          GoRoute(
            path: 'manual',
            builder: (ctx, state) {
              final extra = state.extra as Map<String, String>?;
              return ManualInputView(
                connection: connection,
                initialIp: extra?['ip'],
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => UploadView(
          connection: connection,
          projects: projects,
          uploader: uploader,
        ),
        routes: [
          GoRoute(
            path: 'project-switcher',
            pageBuilder: (_, state) => MaterialPage(
              fullscreenDialog: true,
              child: ProjectSwitcher(projects: projects),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => SettingsView(connection: connection),
      ),
    ],
  );
}