// lib/features/discovery/discovery_view.dart
//
// ConnectPage：扫描中 + 设备列表 + 手动 IP 兜底。
//
// 联调日志：[VIEW] 前缀。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_error.dart';
import '../../core/app_error_bus.dart';
import '../../core/app_state.dart';
import '../../core/mock/seed_data.dart';
import '../../ui/components/buttons.dart';
import '../../ui/components/cards.dart';
import '../../ui/components/connection_progress.dart';
import '../../ui/components/empty_state.dart';
import '../../ui/components/starfield_bg.dart';
import '../../ui/tokens/colors.dart';
import '../../ui/tokens/spacing.dart';
import '../../ui/tokens/typography.dart';
import 'discovery_service.dart';
import 'multicast_lock_channel.dart';
import 'udp_log.dart';

class DiscoveryView extends StatefulWidget {
  const DiscoveryView({super.key, required this.service});

  final DiscoveryService service;

  @override
  State<DiscoveryView> createState() => _DiscoveryViewState();
}

class _DiscoveryViewState extends State<DiscoveryView> {
  final List<PC> _pcs = [];
  bool _scanning = true;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    AppState.stage = AppStage.disconnected;
    UdpLog.view('initState → startScan');
    // T-M1-6：进入发现页即持有 Android MulticastLock，保证 Doze/低功耗模式下 UDP 仍能接收。
    MulticastLockChannel.instance.acquire();
    _startScan();
  }

  void _startScan() {
    UdpLog.view('_startScan invoked, current _scanning=$_scanning '
        'known=${_pcs.length}');
    setState(() {
      _pcs.clear();
      _scanning = true;
      _elapsed = Duration.zero;
    });
    _ticker?.cancel();
    _countdown?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(milliseconds: 100));
    });
    final scanFuture = widget.service.scan(onDiscovered: (pc) {
      if (!mounted) return;
      final isNew = _pcs.indexWhere((p) => p.ip == pc.ip) < 0;
      UdpLog.view('onDiscovered name="${pc.name}" ip=${pc.ip} '
          'isNew=$isNew');
      setState(() {
        // 去重
        _pcs.removeWhere((p) => p.ip == pc.ip);
        _pcs.add(pc);
      });
    });
    scanFuture.then((_) {
      UdpLog.view('scan.then → end, final count=${_pcs.length}');
      _ticker?.cancel();
      _countdown?.cancel();
      if (!mounted) return;
      setState(() => _scanning = false);
    }).catchError((e, _) {
      // UDP socket 启动失败 → 走 ErrorBanner 提示 + 降级到手动输入。
      UdpLog.view('scan.catchError: $e');
      _ticker?.cancel();
      _countdown?.cancel();
      if (!mounted) return;
      setState(() => _scanning = false);
      final err = e is AppError
        ? e
        : AppError(AppErrorKind.unknown, '扫描失败：$e');
      context.read<AppErrorBus>().push(err);
    });
  }

  @override
  void dispose() {
    UdpLog.view('dispose → cancel timers');
    _ticker?.cancel();
    _countdown?.cancel();
    // T-M1-6：离开发现页必须释放 MulticastLock，避免持续耗电与被系统判定后台行为。
    MulticastLockChannel.instance.release();
    super.dispose();
  }

  void _onTapPC(PC pc) {
    UdpLog.view('tap PC name="${pc.name}" ip=${pc.ip} → /connect/token');
    context.push(
      '/connect/token',
      extra: {'ip': pc.ip, 'name': pc.name},
    );
  }

  Future<void> _showManualInput() async {
    // T-M1-3：跳转到独立的 ManualInputView（IP + Port + Token 三字段）。
    // 旧的 _ManualIPSheet 单 IP 输入已删除。
    UdpLog.view('manual input → /connect/manual');
    await context.push('/connect/manual');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.space900,
      appBar: AppBar(title: const Text('扫描局域网')),
      body: StarfieldBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.md,
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: AppColors.space800,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.aurora500, size: 18),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          '确保手机和 PC 在同一 WiFi 下',
                          style: AppTextStyle.bodyMd
                              .copyWith(color: AppColors.star200),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                if (_scanning)
                  ConnectionProgress(
                    elapsed: _elapsed,
                    total: discoveryWindow,
                  ),
                if (!_scanning && _pcs.isEmpty) ...[
                  const SizedBox(height: AppSpace.xxl),
                  EmptyState(
                    icon: Icons.wifi_off,
                    title: '未发现 PC',
                    description: '请确认 PC 端星助已运行',
                    action: PrimaryButton(
                      label: '重试',
                      onPressed: _startScan,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                Expanded(
                  child: ListView.separated(
                    itemCount: _pcs.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpace.sm),
                    itemBuilder: (context, i) {
                      final pc = _pcs[i];
                      return PCCard(
                        name: pc.name,
                        address: pc.displayAddress,
                        projectCount: pc.projectCount,
                        onTap: () => _onTapPC(pc),
                      );
                    },
                  ),
                ),
                SecondaryButton(
                  label: '手动输入 IP',
                  onPressed: _showManualInput,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}