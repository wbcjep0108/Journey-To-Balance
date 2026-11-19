import 'package:flutter/material.dart';

import '../../widgets/security_ui.dart';

/// Full-screen "no internet" page. Stateless: the caller owns the check.
class OfflineScreen extends StatelessWidget {
  const OfflineScreen({
    super.key,
    required this.checking,
    required this.onRetry,
  });

  /// True while a re-check is running (shows a spinner on the button).
  final bool checking;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF121212),
                        width: 1.4,
                      ),
                    ),
                    child: const Icon(
                      Icons.wifi_off_rounded,
                      size: 26,
                      color: Color(0xFF121212),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "You're offline",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF121212),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check your internet connection. Your saved progress is '
                    "safe, and we'll pick up where you left off.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SecurityActionButton(
                    label: 'Try again',
                    isLoading: checking,
                    onPressed: checking ? null : onRetry,
                  ),
                  SizedBox(
                    height: 36,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: checking ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: const Text(
                          'Checking your connection...',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ),
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
