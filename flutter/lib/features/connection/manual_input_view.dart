// lib/features/connection/manual_input_view.dart
//
// T-M1-3 · 手动输入兜底页（IP + Port + Token）
// 触发场景：
//   - 扫描 5s 无设备
//   - 用户主动「手动输入」按钮
//
// 行为：
//   - 三个字段独立校验（IP 格式 + Port 范围 + Token 6 位数字）
//   - 提交后跳 /connect/token，由 TokenInputView 走完整鉴权链路（M2 接入真实 /api/v1/health）
//
// 与 PC v0.12 协议对齐：port 默认 8765，token 6 位数字。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/mock/seed_data.dart';
import '../../ui/components/buttons.dart';
import '../../ui/tokens/colors.dart';
import '../../ui/tokens/spacing.dart';
import '../../ui/tokens/typography.dart';
import 'connection_service.dart';

class ManualInputView extends StatefulWidget {
  const ManualInputView({
    super.key,
    required this.connection,
    this.initialIp,
  });

  /// M2 接入真实 /api/v1/health 后使用；M1 阶段保留接口便于扩展。
  final ConnectionService connection;

  /// 可选：扫描时拿到的某台 PC IP 作为默认值（M1 暂未使用，留接口）。
  final String? initialIp;

  @override
  State<ManualInputView> createState() => _ManualInputViewState();
}

class _ManualInputViewState extends State<ManualInputView> {
  late final TextEditingController _ip;
  late final TextEditingController _port;
  late final TextEditingController _token;

  String? _errIp;
  String? _errPort;
  String? _errToken;

  @override
  void initState() {
    super.initState();
    _ip = TextEditingController(text: widget.initialIp ?? '192.168.1.');
    _port = TextEditingController(text: '$defaultHttpPort');
    _token = TextEditingController();
  }

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  // IPv4 校验：宽松，四段 0-255。
  bool _isValidIp(String s) {
    final parts = s.trim().split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  bool _isValidPort(String s) {
    final n = int.tryParse(s.trim());
    return n != null && n > 0 && n <= 65535;
  }

  bool _isValidToken(String s) => RegExp(r'^\d{6}$').hasMatch(s.trim());

  void _submit() {
    setState(() {
      _errIp = _isValidIp(_ip.text) ? null : 'IP 格式错误（例 192.168.1.10）';
      _errPort =
          _isValidPort(_port.text) ? null : '端口范围 1-65535';
      _errToken =
          _isValidToken(_token.text) ? null : 'Token 为 6 位数字';
    });
    if (_errIp != null || _errPort != null || _errToken != null) return;

    // 跳到 TokenInputView；当前 TokenInputView 只读 ip + name，
    // port 携带 extra 字段预留（M2 接入 ConnectionService 真实实现时使用）。
    context.push(
      '/connect/token',
      extra: {
        'ip': _ip.text.trim(),
        'name': '手动输入',
        'port': int.parse(_port.text.trim()),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.space900,
      appBar: AppBar(title: const Text('手动输入')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(
                label: 'IP 地址',
                controller: _ip,
                hint: '192.168.1.10',
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                error: _errIp,
              ),
              const SizedBox(height: AppSpace.md),
              _Field(
                label: '端口',
                controller: _port,
                hint: '$defaultHttpPort',
                keyboardType: TextInputType.number,
                error: _errPort,
              ),
              const SizedBox(height: AppSpace.md),
              _Field(
                label: 'Token（PC 端 6 位数字）',
                controller: _token,
                hint: '123456',
                keyboardType: TextInputType.number,
                obscureText: true,
                error: _errToken,
                maxLength: 6,
              ),
              const SizedBox(height: AppSpace.lg),
              PrimaryButton(label: '连接', onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    required this.keyboardType,
    this.error,
    this.obscureText = false,
    this.maxLength,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final TextInputType keyboardType;
  final String? error;
  final bool obscureText;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyle.caption.copyWith(color: AppColors.star300)),
        const SizedBox(height: AppSpace.xs),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLength: maxLength,
          inputFormatters: maxLength != null
              ? [LengthLimitingTextInputFormatter(maxLength)]
              : null,
          style: AppTextStyle.titleMd.copyWith(color: AppColors.star100),
          decoration: InputDecoration(
            hintText: hint,
            errorText: error,
            filled: true,
            fillColor: AppColors.space700,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}