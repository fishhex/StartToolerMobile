// lib/app/router.dart
//
// 4 个路由：/splash / /connect（扫码） / /home / /home/project-switcher / /settings
//
// T2：路由参数从 queryParameters 改为不再依赖（HomeView 自己读 SpacesController.active）。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/splash_view.dart';
import '../ui/connect_view.dart';
import '../ui/home_view.dart';
import '../ui/project_switcher_view.dart';
import '../ui/settings_view.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashView()),
      GoRoute(
        path: '/connect',
        builder: (_, __) => const ConnectView(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeView(),
        routes: [
          GoRoute(
            path: 'project-switcher',
            builder: (_, __) => const ProjectSwitcherView(),
          ),
        ],
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsView()),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route error: ${state.error}')),
    ),
  );
}