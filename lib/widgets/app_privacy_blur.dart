import 'dart:ui';

import 'package:flutter/material.dart';

/// Blurs the UI while the app is inactive/backgrounded so the system
/// app-switcher preview does not expose financial content.
class AppPrivacyBlur extends StatefulWidget {
  const AppPrivacyBlur({super.key, required this.child});

  final Widget child;

  @override
  State<AppPrivacyBlur> createState() => _AppPrivacyBlurState();
}

class _AppPrivacyBlurState extends State<AppPrivacyBlur>
    with WidgetsBindingObserver {
  bool _obscure = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final shouldObscure =
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden;
    if (shouldObscure == _obscure) return;
    setState(() => _obscure = shouldObscure);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_obscure)
          Positioned.fill(
            child: AbsorbPointer(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  color: const Color(0xCCF3F3F3),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.lock_outline_rounded,
                    size: 40,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
