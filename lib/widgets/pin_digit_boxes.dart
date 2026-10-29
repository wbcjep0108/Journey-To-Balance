import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable numeric code input with auto-advance, paste, and backspace.
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
    this.length = 4,
    this.boxSize = 56,
    this.spacing = 12,
    this.autofillHints,
  });

  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool hasError;
  final bool autoFocus;
  final bool obscureText;
  final int length;
  final double boxSize;
  final double spacing;
  final Iterable<String>? autofillHints;

  /// Increment to clear all digits from outside.
  final int? clearTrigger;

  @override
  State<PinDigitBoxes> createState() => PinDigitBoxesState();
}

class PinDigitBoxesState extends State<PinDigitBoxes> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  int? _lastClearTrigger;

  @override
  void initState() {
    super.initState();
    assert(widget.length > 0);
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
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
    if (value.length == widget.length) {
      widget.onCompleted(value);
    }
  }

  void _onChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < widget.length; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final focusIndex = (digits.length.clamp(1, widget.length) - 1).clamp(
        0,
        widget.length - 1,
      );
      _focusNodes[focusIndex].requestFocus();
      setState(() {});
      _notify();
      return;
    }

    setState(() {});

    if (value.isNotEmpty && index < widget.length - 1) {
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
      children: List.generate(widget.length, (index) {
        final hasFocus = _focusNodes[index].hasFocus;
        final filled = _controllers[index].text.isNotEmpty;

        return Padding(
          padding: EdgeInsets.only(
            right: index == widget.length - 1 ? 0 : widget.spacing,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: widget.boxSize,
            height: widget.boxSize,
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
                autofillHints: widget.autofillHints,
                obscureText: widget.obscureText,
                obscuringCharacter: '•',
                // Allow a complete code to reach _onChanged so paste and
                // platform one-time-code autofill can distribute the digits.
                maxLength: widget.length,
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
