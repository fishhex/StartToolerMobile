// lib/app/settings_view.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/tokens/colors.dart';
import '../ui/tokens/spacing.dart';
import '../ui/tokens/typography.dart';
import '../features/connection/connection_service.dart';
import 'app.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.connection});

  final ConnectionService connection;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  @override
  Widget build(BuildContext context) {
    final pc = widget.connection.connected;
    final activeToken = widget.connection.tokenStore.active?.token;
    return Scaffold(
      backgroundColor: AppColors.space900,
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.md,
          ),
          children: [
            const _SectionLabel(text: 'PC'),
            _SettingsTile(
              title: pc?.name ?? '未连接',
              subtitle: pc == null
                  ? null
                  : '${pc.displayAddress} · 当前已连接',
              trailing: TextButton(
                onPressed: () async {
                  // D03 §3.10：切换设备 → 清空 token store + active
                  await widget.connection.tokenStore.clearAll();
                  if (!context.mounted) return;
                  context.go('/connect');
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.nebula400,
                ),
                child: const Text('切换设备'),
              ),
            ),
            if (activeToken != null) ...[
              const SizedBox(height: AppSpace.sm),
              _SettingsTile(
                title: '当前 Token',
                // D03 §3.9：脱敏展示 12****56
                subtitle: activeToken.masked,
              ),
            ],
            const SizedBox(height: AppSpace.lg),
            const _SectionLabel(text: '缓存'),
            _SettingsTile(
              title: '清除本地缓存',
              subtitle: '项目列表、上传历史',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已清除（演示）')),
                );
              },
            ),
            const SizedBox(height: AppSpace.md),
            _SettingsTile(
              title: '演示：触发顶部错误条幅',
              subtitle: '验证 ErrorBanner 全局显示',
              onTap: () {
                StartToolerApp.apiOf(context).demoPushError();
              },
            ),
            const SizedBox(height: AppSpace.lg),
            const _SectionLabel(text: '关于'),
            const _SettingsTile(
              title: '版本',
              subtitle: '0.1.0',
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpace.xs,
        bottom: AppSpace.sm,
        top: AppSpace.xs,
      ),
      child: Text(text,
          style: AppTextStyle.bodyMd.copyWith(color: AppColors.star300)),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.space800,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border12),
      ),
      child: ListTile(
        title: Text(title,
            style: AppTextStyle.titleMd.copyWith(color: AppColors.star100)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!,
                style: AppTextStyle.bodyMd
                    .copyWith(color: AppColors.star300)),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}