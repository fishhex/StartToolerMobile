// lib/features/connection/token_input_view.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_error.dart';
import '../../core/app_state.dart';
import '../../ui/components/buttons.dart';
import '../../ui/components/token_input.dart';
import '../../ui/tokens/colors.dart';
import '../../ui/tokens/spacing.dart';
import '../../ui/tokens/typography.dart';
import 'connection_service.dart';

class TokenInputView extends StatefulWidget {
  const TokenInputView({
    super.key,
    required this.connection,
    required this.ip,
    required this.pcName,
  });

  final ConnectionService connection;
  final String ip;
  final String pcName;

  @override
  State<TokenInputView> createState() => _TokenInputViewState();
}

class _TokenInputViewState extends State<TokenInputView>
    with SingleTickerProviderStateMixin {
  String _token = '';
  bool _error = false;
  bool _verifying = false;
  Timer? _shakeTimer;
  late final AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _shakeTimer?.cancel();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _onChanged(String token) async {
    setState(() {
      _token = token;
      _error = false;
    });
    if (token.length == 6 && !_verifying) {
      await _verify();
    }
  }

  Future<void> _verify() async {
    setState(() => _verifying = true);
    try {
      await widget.connection.connect(ip: widget.ip, token: _token);
      if (!mounted) return;
      AppState.stage = AppStage.connected;
      context.go('/home');
    } on AppError catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _verifying = false;
      });
      _shakeCtrl.forward(from: 0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _verifying = false;
      });
      _shakeCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.space900,
      appBar: AppBar(title: Text(widget.pcName)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请输入 PC 端显示的',
                style: AppTextStyle.bodyMd.copyWith(color: AppColors.star200),
              ),
              Text(
                '6 位数字 Token',
                style: AppTextStyle.titleLg.copyWith(color: AppColors.star100),
              ),
              const SizedBox(height: AppSpace.xl),
              AnimatedBuilder(
                animation: _shakeCtrl,
                builder: (_, child) {
                  final dx = _error ? _shake(_shakeCtrl.value) * 12 : 0.0;
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  );
                },
                child: TokenInput(
                  error: _error,
                  onChanged: _onChanged,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                _error ? 'Token 错误，请重试' : '提示：演示阶段输入 123456 即可',
                style: AppTextStyle.bodyMd.copyWith(
                  color: _error ? AppColors.comet600 : AppColors.star300,
                ),
              ),
              const Spacer(),
              if (_verifying)
                const Center(
                  child: CircularProgressIndicator(color: AppColors.nebula400),
                )
              else
                PrimaryButton(
                  label: '验证',
                  onPressed: _token.length == 6 ? _verify : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 200ms 内 3 次衰减震荡。
  double _shake(double t) {
    if (t < 0.33) return -1;
    if (t < 0.66) return 1;
    if (t < 1.0) return -0.5;
    return 0;
  }
}