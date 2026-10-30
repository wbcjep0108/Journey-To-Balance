import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/rate_limit_info.dart';
import '../providers/budget_provider.dart';
import '../services/finance_api_service.dart';
import 'barrier_blur.dart';

/// Returns true when [error] is a Worker finance rate-limit response.
///
/// Call sites that show generic snackbars should skip them when this is true;
/// [RateLimitListener] owns the user-facing dialog.
bool isFinanceRateLimitError(Object error) =>
    FinanceApiException.isRateLimitError(error);

String rateLimitDialogMessage(RateLimitInfo info) {
  String? message;
  if (info.code == 'daily-rate-limit-exceeded') {
    message = 'You\'ve reached today\'s limit. Try again tomorrow.';
  } else if (info.code == 'temporarily-busy' || info.statusCode == 503) {
    message = 'The service is busy. Please try again later.';
  }
  if (message == null) return info.dialogMessage;

  final seconds = info.retryAfterSeconds;
  if (seconds == null || seconds <= 0) return message;
  final int value;
  final String unit;
  if (seconds < 60) {
    value = seconds;
    unit = 'second';
  } else if (seconds < 3600) {
    value = (seconds / 60).ceil();
    unit = 'minute';
  } else {
    value = (seconds / 3600).ceil();
    unit = 'hour';
  }
  final retry = '$value $unit${value == 1 ? '' : 's'}';
  return '$message Retry in $retry.';
}

Future<void> showRateLimitDialog(BuildContext context, RateLimitInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return withBarrierBlur(
        Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  info.dialogTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF121212),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  rateLimitDialogMessage(info),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF121212),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Watches [BudgetProvider.pendingRateLimit] and shows a single dialog.
///
/// Place once near the app shell so every Worker finance mutation shares the
/// same UX without per-screen 429 handling.
class RateLimitListener extends StatefulWidget {
  const RateLimitListener({super.key, required this.child});

  final Widget child;

  @override
  State<RateLimitListener> createState() => _RateLimitListenerState();
}

class _RateLimitListenerState extends State<RateLimitListener> {
  bool _dialogVisible = false;
  bool _presentScheduled = false;
  RateLimitInfo? _queued;

  @override
  Widget build(BuildContext context) {
    final pending = context.watch<BudgetProvider>().pendingRateLimit;

    if (pending != null && !_presentScheduled) {
      _presentScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _presentScheduled = false;
        if (!mounted) return;
        final info = context.read<BudgetProvider>().pendingRateLimit;
        if (info == null) return;
        context.read<BudgetProvider>().clearPendingRateLimit();
        _present(info);
      });
    }

    return widget.child;
  }

  Future<void> _present(RateLimitInfo info) async {
    if (!mounted) return;
    if (_dialogVisible) {
      _queued = info;
      return;
    }

    _dialogVisible = true;
    try {
      await showRateLimitDialog(context, info);
    } finally {
      _dialogVisible = false;
      final next = _queued;
      _queued = null;
      if (next != null && mounted) {
        await _present(next);
      }
    }
  }
}
