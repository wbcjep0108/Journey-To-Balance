import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pin_digit_boxes.dart';

/// Shared primary / secondary action buttons used by PIN screens.
class SecurityActionButton extends StatefulWidget {
  const SecurityActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isPrimary = true,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isLoading;

  @override
  State<SecurityActionButton> createState() => _SecurityActionButtonState();
}

class _SecurityActionButtonState extends State<SecurityActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.isPrimary) {
      return TextButton(
        onPressed: widget.isLoading ? null : widget.onPressed,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF8A8F98),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          widget.label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final enabled = widget.onPressed != null && !widget.isLoading;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.45,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: double.infinity,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _pressed ? 0.04 : 0.08),
                  blurRadius: _pressed ? 8 : 16,
                  offset: Offset(0, _pressed ? 2 : 6),
                ),
              ],
            ),
            child: widget.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.black,
                    ),
                  )
                : Text(
                    widget.label,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.18),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/logo.png',
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Icon(
          Icons.lock_outline_rounded,
          color: Colors.white,
          size: size * 0.42,
        ),
      ),
    );
  }
}

class SecurityCardShell extends StatelessWidget {
  const SecurityCardShell({
    super.key,
    required this.child,
    this.maxWidth = 380,
    this.padding = const EdgeInsets.fromLTRB(28, 32, 28, 24),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Labeled PIN row used on setup screens.
class LabeledPinField extends StatelessWidget {
  const LabeledPinField({
    super.key,
    required this.label,
    required this.onCompleted,
    this.onChanged,
    this.hasError = false,
    this.enabled = true,
    this.clearTrigger,
    this.autoFocus = false,
  });

  final String label;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final bool hasError;
  final bool enabled;
  final int? clearTrigger;
  final bool autoFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3F444C),
          ),
        ),
        const SizedBox(height: 10),
        PinDigitBoxes(
          onCompleted: onCompleted,
          onChanged: onChanged,
          hasError: hasError,
          enabled: enabled,
          clearTrigger: clearTrigger,
          autoFocus: autoFocus,
        ),
      ],
    );
  }
}

Future<void> lightHaptic() async {
  try {
    await HapticFeedback.lightImpact();
  } catch (_) {}
}
