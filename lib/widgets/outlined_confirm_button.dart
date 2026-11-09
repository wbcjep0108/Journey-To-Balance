import 'package:flutter/material.dart';

/// Full-width white pill with a black outline, used as the primary action in
/// small dialogs (for example "Edit Goal Title" and "Add Loan").
///
/// Shows a spinner while [isLoading] and is dimmed and inert when
/// [onPressed] is null.
class OutlinedConfirmButton extends StatefulWidget {
  const OutlinedConfirmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  State<OutlinedConfirmButton> createState() => _OutlinedConfirmButtonState();
}

class _OutlinedConfirmButtonState extends State<OutlinedConfirmButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
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
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.5,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: double.infinity,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black, width: 1.3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _pressed ? 0.04 : 0.08),
                  blurRadius: _pressed ? 8 : 14,
                  offset: Offset(0, _pressed ? 2 : 5),
                ),
              ],
            ),
            child: widget.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF121212),
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
