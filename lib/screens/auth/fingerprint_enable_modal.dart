import 'package:flutter/material.dart';

import '../../widgets/barrier_blur.dart';
import '../../widgets/security_ui.dart';

/// Returns `true` if Enable was pressed, `false` if Skip, `null` if dismissed.
Future<bool?> showFingerprintEnableModal(BuildContext context) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Fingerprint',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, animation, secondaryAnimation) {
      return withBarrierBlur(const FingerprintEnableModal());
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class FingerprintEnableModal extends StatefulWidget {
  const FingerprintEnableModal({super.key});

  @override
  State<FingerprintEnableModal> createState() =>
      _FingerprintEnableModalState();
}

class _FingerprintEnableModalState extends State<FingerprintEnableModal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        final t = _pulse.value;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            _RippleRing(progress: t, maxScale: 1.55),
                            _RippleRing(
                              progress: (t + 0.5) % 1,
                              maxScale: 1.35,
                            ),
                            child!,
                          ],
                        );
                      },
                      child: const Icon(
                        Icons.fingerprint_rounded,
                        size: 72,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Enable Fingerprint Unlock',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Use your fingerprint for faster and secure access.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SecurityActionButton(
                    label: 'Enable',
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  SecurityActionButton(
                    label: 'Skip for now',
                    isPrimary: false,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RippleRing extends StatelessWidget {
  const _RippleRing({required this.progress, required this.maxScale});

  final double progress;
  final double maxScale;

  @override
  Widget build(BuildContext context) {
    final scale = 1 + (maxScale - 1) * progress;
    final opacity = (1 - progress).clamp(0.0, 1.0) * 0.28;

    return Transform.scale(
      scale: scale,
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.black.withValues(alpha: opacity),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
