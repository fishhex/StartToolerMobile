// lib/ui/components/token_input.dart
//
// 6 格独立方格 Token 输入。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/typography.dart';

class TokenInput extends StatefulWidget {
  const TokenInput({
    super.key,
    required this.onChanged,
    this.error = false,
    this.length = 6,
  });

  final ValueChanged<String> onChanged;
  final bool error;
  final int length;

  @override
  State<TokenInput> createState() => _TokenInputState();
}

class _TokenInputState extends State<TokenInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void didUpdateWidget(covariant TokenInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.length != widget.length) {
      // 长度变化：重建（实际不会发生）
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final code = _controllers.map((c) => c.text).join();
    widget.onChanged(code);
  }

  void _onChanged(int index, String value) {
    final filtered = value.replaceAll(RegExp(r'\D'), '');
    if (filtered != value) {
      _controllers[index].text = filtered;
      _controllers[index].selection = TextSelection.collapsed(
        offset: filtered.length,
      );
    }
    if (filtered.length == 1 && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    _emit();
  }

  KeyEventResult _onKey(KeyEvent event, int index) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      final prev = _controllers[index - 1];
      prev.text = '';
      _emit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        widget.error ? AppColors.comet600 : AppColors.space600;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(widget.length, (i) {
        return SizedBox(
          width: 44,
          height: 56,
          child: KeyboardListener(
            focusNode: FocusNode(),
            onKeyEvent: (e) => _onKey(e, i),
            child: TextField(
              controller: _controllers[i],
              focusNode: _focusNodes[i],
              onChanged: (v) => _onChanged(i, v),
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              maxLength: 1,
              style: AppTextStyle.mono.copyWith(color: AppColors.star100),
              cursorColor: AppColors.nebula400,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                counterText: '',
                contentPadding: EdgeInsets.zero,
                filled: true,
                fillColor: AppColors.space800,
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.borderSm,
                  borderSide: BorderSide(
                      color: borderColor, width: 1),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: AppRadius.borderSm,
                  borderSide: BorderSide(
                      color: AppColors.nebula400, width: 2),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}