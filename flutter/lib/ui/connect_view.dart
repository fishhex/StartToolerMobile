// lib/ui/connect_view.dart
//
// /connect：QR 唯一入口（v0.14）。真相机扫码（mobile_scanner）。
// 流程：扫码 → QR 解析 → health 验证 → 写持久化 → 跳 /home。
// 解析失败不关闭扫码页（顶部 banner 提示「二维码无效」继续扫）。
// 权限被拒 / 设备无相机 → 顶部 banner 提示「需要相机权限才能扫码」+ 「去设置」按钮。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/app_error.dart';
import '../core/error_bus.dart';
import '../core/health_api.dart';
import '../core/qr_parser.dart';
import '../core/result.dart';
import '../core/space.dart';
import '../core/spaces_controller.dart';
import '../core/strings.dart';

class ConnectView extends StatefulWidget {
  const ConnectView({super.key});

  @override
  State<ConnectView> createState() => _ConnectViewState();
}

class _ConnectViewState extends State<ConnectView> {
  final MobileScannerController _scannerCtl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode],
  );

  PermissionStatus? _cameraStatus;
  bool _connecting = false;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _requestCamera();
  }

  @override
  void dispose() {
    _scannerCtl.dispose();
    super.dispose();
  }

  Future<void> _requestCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _cameraStatus = status);
    if (!status.isGranted) {
      context.read<AppErrorBus>().push(
            const UnknownError(Strings.errorCameraPermissionRequired),
          );
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  Future<void> _handleScan(String raw) async {
    if (_handled || _connecting) return;
    _handled = true;

    // 1. 解析 QR
    QrPayload payload;
    try {
      payload = parseQr(raw);
    } on QrError catch (e) {
      if (!mounted) return;
      context.read<AppErrorBus>().push(UnknownError(e.message));
      // 解析失败不关闭扫码页：短暂延迟后允许重新识别
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _handled = false;
      });
      return;
    }

    // 2. 暂停扫码 → 调 health
    debugPrint('[连接] 二维码解析成功 host=${payload.host} port=${payload.port}');
    setState(() => _connecting = true);
    debugPrint('[连接] 标记 connecting=true 准备暂停扫码');
    await _scannerCtl.stop();
    debugPrint('[连接] 扫码已暂停 调用 health.check');

    if (!mounted) return;
    final healthApi = context.read<HealthApi>();

    // 兜底：5 秒全局超时（health api 内部 3 秒 + 网络余量 + 写持久化 + 跳转）
    debugPrint('[连接] → 请求 http://${payload.host}:${payload.port}/api/v1/health');
    final result = await healthApi
        .check(payload.host, payload.port)
        .timeout(const Duration(seconds: 5), onTimeout: () {
      debugPrint('[连接] 超时（5 秒兜底）http://${payload.host}:${payload.port}/api/v1/health');
      return const Err(NetworkTimeout('PC 不可达，超时（兜底）'));
    });
    debugPrint('[连接] ← health.check 返回 ${result.runtimeType}');

    if (!mounted) {
      return;
    }

    await result.when<Future<void>>(
      ok: (h) async {
        debugPrint('[连接] 成功 name=${h.name} version=${h.version} project=${h.currentProject}');
        final s = Space(
          name: h.name,
          ip: payload.host,
          port: payload.port,
          secret: payload.secret,
          lastSeenAt: DateTime.now(),
        );
        await context.read<SpacesController>().upsertAndActivate(s);
        debugPrint('[连接] Space 已保存 name=${s.name} mounted={$mounted}');
        if (!mounted) return;
        context.go('/home');
        debugPrint('[连接] 已跳转到 /home');
      },
      err: (e) async {
        debugPrint('[连接] 失败 类型=${e.runtimeType} 消息=${e.message}');
        // health 失败 → 回到扫码页继续扫
        if (!mounted) return;
        context.read<AppErrorBus>().push(e);
        // 强制 setState，即使后续 start() 抛异常也确保 _connecting 归位
        if (mounted) setState(() => _connecting = false);
        try {
          await _scannerCtl.start();
        } catch (e) {
          // 忽略 start 失败，下次 onDetect 之前会重试
        }
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) _handled = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _cameraStatus;

    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码连接'),
        actions: [
          IconButton(
            tooltip: '切换闪光灯',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _scannerCtl.toggleTorch(),
          ),
          IconButton(
            tooltip: '切换摄像头',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _scannerCtl.switchCamera(),
          ),
        ],
      ),
      body: _buildBody(status),
    );
  }

  Widget _buildBody(PermissionStatus? status) {
    if (_connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在连接 PC…'),
          ],
        ),
      );
    }

    if (status == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!status.isGranted) {
      return _PermissionDeniedView(
        onRetry: _requestCamera,
        onOpenSettings: _openSettings,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scannerCtl,
          onDetect: (capture) {
            for (final code in capture.barcodes) {
              final raw = code.rawValue;
              if (raw != null && raw.isNotEmpty) {
                _handleScan(raw);
                break;
              }
            }
          },
          errorBuilder: (context, error, child) {
            return _PermissionDeniedView(
              onRetry: _requestCamera,
              onOpenSettings: _openSettings,
              message: '相机初始化失败：${error.errorCode.name}',
            );
          },
        ),
        // 顶部半透明提示
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: const Text(
                '将 PC 端二维码对准取景框',
                style: TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        // 底部扫码框（装饰）
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ScannerOverlayPainter()),
          ),
        ),
      ],
    );
  }
}

/// 权限被拒 / 设备无相机 时的占位视图。
class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView({
    required this.onRetry,
    required this.onOpenSettings,
    this.message,
  });

  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              message ?? Strings.errorCameraPermissionRequired,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('重新申请权限'),
                ),
                ElevatedButton(
                  onPressed: onOpenSettings,
                  child: const Text('去设置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 半透明遮罩 + 中央扫码框。
class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final boxSize = size.width * 0.7;
    final left = (size.width - boxSize) / 2;
    final top = (size.height - boxSize) / 2;
    final rect = Rect.fromLTWH(left, top, boxSize, boxSize);
    const radius = Radius.circular(16);

    // 半透明遮罩
    final overlay = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );

    // 四个角
    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    const cornerLen = 24.0;
    // 左上
    canvas.drawLine(rect.topLeft.translate(0, cornerLen),
        rect.topLeft, cornerPaint);
    canvas.drawLine(rect.topLeft,
        rect.topLeft.translate(cornerLen, 0), cornerPaint);
    // 右上
    canvas.drawLine(rect.topRight.translate(-cornerLen, 0),
        rect.topRight, cornerPaint);
    canvas.drawLine(rect.topRight,
        rect.topRight.translate(0, cornerLen), cornerPaint);
    // 左下
    canvas.drawLine(rect.bottomLeft.translate(0, -cornerLen),
        rect.bottomLeft, cornerPaint);
    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft.translate(cornerLen, 0), cornerPaint);
    // 右下
    canvas.drawLine(rect.bottomRight.translate(-cornerLen, 0),
        rect.bottomRight, cornerPaint);
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight.translate(0, -cornerLen), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) => false;
}