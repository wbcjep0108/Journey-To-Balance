import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/currency_provider.dart';
import 'barrier_blur.dart';

/// Congrats popup with a short confetti burst when a savings goal is reached.
class SavingsGoalCompleteDialog {
  SavingsGoalCompleteDialog._();

  static Future<void> show({
    required BuildContext context,
    required String goalTitle,
    required double targetAmount,
  }) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final amountLabel =
        context.read<CurrencyProvider>().format(targetAmount);
    final title = goalTitle.trim().isEmpty ? 'savings goal' : goalTitle.trim();

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close congratulations',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, _, _) {
        return withBarrierBlur(
          SafeArea(
            child: _CongratsScaffold(
              goalTitle: title,
              amountLabel: amountLabel,
              reduceMotion: reduceMotion,
              onDismiss: () => Navigator.pop(dialogContext),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
            child: child,
          ),
        );
      },
    );
  }
}

class _CongratsScaffold extends StatefulWidget {
  const _CongratsScaffold({
    required this.goalTitle,
    required this.amountLabel,
    required this.reduceMotion,
    required this.onDismiss,
  });

  final String goalTitle;
  final String amountLabel;
  final bool reduceMotion;
  final VoidCallback onDismiss;

  @override
  State<_CongratsScaffold> createState() => _CongratsScaffoldState();
}

class _CongratsScaffoldState extends State<_CongratsScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (!widget.reduceMotion) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!widget.reduceMotion)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _ConfettiPainter(progress: _controller.value),
                    );
                  },
                ),
              ),
            ),
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF5CB450).withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.celebration_rounded,
                      size: 32,
                      color: Color(0xFF5CB450),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Congratulations!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF121212),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You reached your ${widget.goalTitle} goal of '
                    '${widget.amountLabel}.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: widget.onDismiss,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF121212),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: const Text(
                        'Got it',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPiece {
  const _ConfettiPiece({
    required this.x,
    required this.delay,
    required this.fallSpeed,
    required this.drift,
    required this.size,
    required this.color,
    required this.rotationSpeed,
    required this.isRect,
  });

  final double x;
  final double delay;
  final double fallSpeed;
  final double drift;
  final double size;
  final Color color;
  final double rotationSpeed;
  final bool isRect;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress})
      : _pieces = _buildPieces();

  final double progress;
  final List<_ConfettiPiece> _pieces;

  static final _colors = <Color>[
    const Color(0xFF5CB450),
    const Color(0xFFF4A261),
    const Color(0xFFE76F51),
    const Color(0xFF2A9D8F),
    const Color(0xFFE9C46A),
    const Color(0xFF457B9D),
    const Color(0xFFFF8FAB),
  ];

  static List<_ConfettiPiece> _buildPieces() {
    final random = math.Random(42);
    return List.generate(48, (index) {
      return _ConfettiPiece(
        x: random.nextDouble(),
        delay: random.nextDouble() * 0.35,
        fallSpeed: 0.55 + random.nextDouble() * 0.55,
        drift: (random.nextDouble() - 0.5) * 0.22,
        size: 5 + random.nextDouble() * 7,
        color: _colors[index % _colors.length],
        rotationSpeed: (random.nextDouble() - 0.5) * 10,
        isRect: index.isEven,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    for (final piece in _pieces) {
      final local = ((progress - piece.delay) / (1 - piece.delay * 0.5))
          .clamp(0.0, 1.0);
      if (local <= 0) continue;

      final eased = Curves.easeIn.transform(local);
      final dx = (piece.x + piece.drift * local) * size.width;
      final dy = -20 + eased * (size.height + 40) * piece.fallSpeed;
      final opacity = (1 - local).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = piece.color.withValues(alpha: opacity * 0.9);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(piece.rotationSpeed * local);

      if (piece.isRect) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: piece.size,
              height: piece.size * 0.55,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, piece.size * 0.38, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
