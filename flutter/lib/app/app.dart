// lib/app/app.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart' as p;
import 'package:go_router/go_router.dart';

import '../core/app_error.dart';
import '../core/app_error_bus.dart';
import '../features/connection/connection_service.dart';
import '../features/discovery/discovery_service.dart';
import '../features/project/project_service.dart';
import '../features/upload/upload_service.dart';
import '../ui/components/error_banner.dart';
import 'router.dart';
import 'theme.dart';

/// 暴露给后代 Widget 调用的调试 / 演示接口。
abstract class StartToolerAppApi {
  void demoPushError();
}

class StartToolerApp extends StatefulWidget {
  const StartToolerApp({
    super.key,
    required this.discovery,
    required this.connection,
    required this.projects,
    required this.uploader,
  });

  final DiscoveryService discovery;
  final ConnectionService connection;
  final ProjectService projects;
  final UploadService uploader;

  /// 后代 Widget 调用根 State 的入口。
  static StartToolerAppApi apiOf(BuildContext context) =>
      _StartToolerAppScope.of(context);

  @override
  State<StartToolerApp> createState() => _StartToolerAppState();
}

class _StartToolerAppState extends State<StartToolerApp>
    implements StartToolerAppApi {
  late final AppErrorBus _bus = AppErrorBus();
  late final GoRouter _router = buildRouter(
    discovery: widget.discovery,
    connection: widget.connection,
    projects: widget.projects,
    uploader: widget.uploader,
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  void demoPushError() {
    _bus.push(AppError(AppErrorKind.network, '当前网络不稳定，已切换到离线模式'));
  }

  @override
  void dispose() {
    _bus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _StartToolerAppScope(
      api: this,
      child: p.ChangeNotifierProvider<AppErrorBus>.value(
        value: _bus,
        child: MaterialApp.router(
          title: 'StartTooler',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          routerConfig: _router,
          builder: (ctx, child) {
            return p.Consumer<AppErrorBus>(
              builder: (_, bus, __) {
                return Stack(
                  children: [
                    Positioned.fill(child: child ?? const SizedBox.shrink()),
                    if (bus.current != null)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: ErrorBanner(
                          message: bus.current!.message,
                          level: bus.current!.kind == AppErrorKind.network
                              ? BannerLevel.warn
                              : BannerLevel.error,
                          onClose: bus.clear,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// InheritedWidget 暴露 StartToolerAppApi。
class _StartToolerAppScope extends InheritedWidget {
  const _StartToolerAppScope({required this.api, required super.child});

  final StartToolerAppApi api;

  static StartToolerAppApi of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_StartToolerAppScope>();
    assert(scope != null, 'No _StartToolerAppScope found in context');
    return scope!.api;
  }

  @override
  bool updateShouldNotify(_StartToolerAppScope oldWidget) =>
      oldWidget.api != api;
}