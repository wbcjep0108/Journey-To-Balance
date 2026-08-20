import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/app_lock_provider.dart';
import '../../services/finance_api_service.dart';
import '../../widgets/pin_digit_boxes.dart';
import '../../widgets/security_ui.dart';

class ForgotPinEmailScreen extends StatefulWidget {
  const ForgotPinEmailScreen({super.key});

  @override
  State<ForgotPinEmailScreen> createState() => _ForgotPinEmailScreenState();
}

class _ForgotPinEmailScreenState extends State<ForgotPinEmailScreen> {
  final _email = TextEditingController();
  final _api = FinanceApiService();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (email.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.requestPinResetOtp(email: email);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ForgotPinOtpScreen(email: email)),
      );
    } on FinanceApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not send the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ForgotPinScaffold(
      title: 'Forgot PIN',
      subtitle: 'Enter the Gmail you use to sign in. We’ll send a 4-digit code.',
      error: _error,
      child: Column(
        children: [
          TextField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _sendCode(),
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Gmail address',
              hintStyle: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                color: Color(0xFF9CA3AF),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: _error != null
                      ? const Color(0xFFE11D48)
                      : const Color(0xFFE4E4E7),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: _error != null ? const Color(0xFFE11D48) : Colors.black,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          SecurityActionButton(
            label: 'Send code',
            isLoading: _busy,
            onPressed: _email.text.trim().isEmpty ? null : _sendCode,
          ),
          SecurityActionButton(
            label: 'Cancel',
            isPrimary: false,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class ForgotPinOtpScreen extends StatefulWidget {
  const ForgotPinOtpScreen({super.key, required this.email});

  final String email;

  @override
  State<ForgotPinOtpScreen> createState() => _ForgotPinOtpScreenState();
}

class _ForgotPinOtpScreenState extends State<ForgotPinOtpScreen> {
  final _api = FinanceApiService();
  String _otp = '';
  String? _error;
  bool _busy = false;
  int _clearOtp = 0;
  int _resendIn = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendIn <= 1) {
        timer.cancel();
        setState(() => _resendIn = 0);
        return;
      }
      setState(() => _resendIn -= 1);
    });
  }

  Future<void> _verify([String? value]) async {
    final otp = value ?? _otp;
    if (otp.length != 4 || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _api.verifyPinResetOtp(email: widget.email, otp: otp);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const ForgotPinNewPinScreen()),
      );
    } on FinanceApiException catch (error) {
      if (!mounted) return;
      await HapticFeedback.mediumImpact();
      setState(() {
        _error = error.message;
        _otp = '';
        _clearOtp++;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not verify the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || _resendIn > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.requestPinResetOtp(email: widget.email);
      if (!mounted) return;
      _startResendTimer();
    } on FinanceApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not send a new code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ForgotPinScaffold(
      title: 'Enter code',
      subtitle: 'We sent a 4-digit code to ${widget.email}.',
      error: _error,
      child: Column(
        children: [
          PinDigitBoxes(
            autoFocus: true,
            enabled: !_busy,
            hasError: _error != null,
            clearTrigger: _clearOtp,
            obscureText: false,
            onChanged: (value) {
              setState(() {
                _otp = value;
                if (value.isNotEmpty) _error = null;
              });
            },
            onCompleted: _verify,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _busy || _resendIn > 0 ? null : _resend,
            child: Text(
              _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SecurityActionButton(
            label: 'Continue',
            isLoading: _busy,
            onPressed: _otp.length == 4 ? () => _verify() : null,
          ),
          SecurityActionButton(
            label: 'Back',
            isPrimary: false,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class ForgotPinNewPinScreen extends StatefulWidget {
  const ForgotPinNewPinScreen({super.key});

  @override
  State<ForgotPinNewPinScreen> createState() => _ForgotPinNewPinScreenState();
}

class _ForgotPinNewPinScreenState extends State<ForgotPinNewPinScreen> {
  String _pin = '';
  String _confirm = '';
  String? _error;
  bool _busy = false;
  int _clearConfirm = 0;

  bool get _canContinue =>
      _pin.length == 4 && _confirm.length == 4 && !_busy;

  Future<void> _save() async {
    if (!_canContinue) return;

    if (_pin != _confirm) {
      await lightHaptic();
      setState(() {
        _error = 'PINs do not match. Try again.';
        _confirm = '';
        _clearConfirm++;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final lock = context.read<AppLockProvider>();
      final navigator = Navigator.of(context);
      await lock.changePin(_pin);
      navigator.popUntil((route) => route.isFirst);
      lock.unlock();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save PIN. Please try again.';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ForgotPinScaffold(
      title: 'Create a new PIN',
      subtitle: 'Choose a new 4-digit PIN to unlock the app.',
      error: _error,
      child: Column(
        children: [
          LabeledPinField(
            label: 'Enter PIN',
            autoFocus: true,
            enabled: !_busy,
            hasError: _error != null,
            onChanged: (value) {
              setState(() {
                _pin = value;
                if (value.isNotEmpty) _error = null;
              });
            },
            onCompleted: (value) => setState(() => _pin = value),
          ),
          const SizedBox(height: 22),
          LabeledPinField(
            label: 'Re-enter PIN',
            enabled: !_busy,
            clearTrigger: _clearConfirm,
            hasError: _error != null,
            onChanged: (value) {
              setState(() {
                _confirm = value;
                if (value.isNotEmpty) _error = null;
              });
            },
            onCompleted: (value) => setState(() => _confirm = value),
          ),
          const SizedBox(height: 28),
          SecurityActionButton(
            label: 'Continue',
            isLoading: _busy,
            onPressed: _canContinue ? _save : null,
          ),
          SecurityActionButton(
            label: 'Back',
            isPrimary: false,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _ForgotPinScaffold extends StatelessWidget {
  const _ForgotPinScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.error,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              children: [
                const BrandMark(),
                const SizedBox(height: 28),
                SecurityCardShell(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                          height: 1.4,
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE11D48),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      child,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
