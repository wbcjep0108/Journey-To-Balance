import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable 4-digit PIN input with masked dots, auto-advance, and backspace.
class PinDigitBoxes extends StatefulWidget {
  const PinDigitBoxes({
    super.key,
    required this.onCompleted,
    this.onChanged,
    this.enabled = true,
    this.hasError = false,
    this.autoFocus = true,
    this.clearTrigger,
    this.obscureText = true,
  });

  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool hasError;
  final bool autoFocus;
  final bool obscureText;

  /// Increment to clear all digits from outside.
  final int? clearTrigger;

  @override
  State<PinDigitBoxes> createState() => PinDigitBoxesState();
}

class PinDigitBoxesState extends State<PinDigitBoxes> {
  static const int _length = 4;

  final List<TextEditingController> _controllers = List.generate(
    _length,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(_length, (_) => FocusNode());
  int? _lastClearTrigger;

  @override
  void initState() {
    super.initState();
    _lastClearTrigger = widget.clearTrigger;
    for (final node in _focusNodes) {
      node.addListener(_onFocusChange);
    }
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNodes.first.requestFocus();
      });
    }
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PinDigitBoxes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clearTrigger != null &&
        widget.clearTrigger != _lastClearTrigger) {
      _lastClearTrigger = widget.clearTrigger;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) clear();
      });
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.removeListener(_onFocusChange);
      node.dispose();
    }
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  String get pin => _controllers.map((c) => c.text).join();

  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    if (mounted) {
      setState(() {});
      _focusNodes.first.requestFocus();
    }
    widget.onChanged?.call('');
  }

  void _notify() {
    final value = pin;
    widget.onChanged?.call(value);
    if (value.length == _length) {
      widget.onCompleted(value);
    }
  }

  void _onChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _length; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final focusIndex = (digits.length.clamp(1, _length) - 1).clamp(
        0,
        _length - 1,
      );
      _focusNodes[focusIndex].requestFocus();
      setState(() {});
      _notify();
      return;
    }

    setState(() {});

    if (value.isNotEmpty && index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    _notify();
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      setState(() {});
      _notify();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_length, (index) {
        final hasFocus = _focusNodes[index].hasFocus;
        final filled = _controllers[index].text.isNotEmpty;

        return Padding(
          padding: EdgeInsets.only(right: index == _length - 1 ? 0 : 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.hasError
                    ? const Color(0xFFE11D48)
                    : hasFocus
                    ? Colors.black
                    : filled
                    ? const Color(0xFFD4D4D8)
                    : const Color(0xFFE4E4E7),
                width: hasFocus || widget.hasError ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: hasFocus
                      ? Colors.black.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.05),
                  blurRadius: hasFocus ? 14 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Focus(
              onKeyEvent: (node, event) => _onKey(index, event),
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                enabled: widget.enabled,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                obscureText: widget.obscureText,
                obscuringCharacter: '•',
                maxLength: 1,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.2,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) => _onChanged(index, value),
                onTap: () {
                  _controllers[index].selection = TextSelection.collapsed(
                    offset: _controllers[index].text.length,
                  );
                },
              ),
            ),
          ),
        );
      }),
    );
  }
}
