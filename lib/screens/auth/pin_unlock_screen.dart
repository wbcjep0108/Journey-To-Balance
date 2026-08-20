import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/app_lock_provider.dart';
import '../../widgets/pin_digit_boxes.dart';
import '../../widgets/security_ui.dart';
import 'forgot_pin_screens.dart';

/// Returning-user unlock: PIN entry with optional fingerprint.
class PinUnlockScreen extends StatefulWidget {
  const PinUnlockScreen({super.key});

  @override
  State<PinUnlockScreen> createState() => _PinUnlockScreenState();
}

class _PinUnlockScreenState extends State<PinUnlockScreen>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String? _error;
  bool _busy = false;
  int _clearTrigger = 0;
  bool _biometricAttempted = false;

  late final AnimationController _shake;
  late final Animation<double> _shakeOffset;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shakeOffset = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shake, curve: Curves.easeOutCubic));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometricAuto();
    });
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _tryBiometricAuto() async {
    if (_biometricAttempted || !mounted) return;
    _biometricAttempted = true;

    final lock = context.read<AppLockProvider>();
    if (!lock.biometricEnabled || !lock.biometricsAvailable) return;

    await _unlockWithBiometric();
  }

  Future<void> _fail(String message) async {
    await HapticFeedback.mediumImpact();
    setState(() {
      _error = message;
      _pin = '';
      _clearTrigger++;
      _busy = false;
    });
    _shake.forward(from: 0);
  }

  Future<void> _submit([String? value]) async {
    final pin = value ?? _pin;
    if (pin.length != 4 || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await context.read<AppLockProvider>().unlockWithPin(pin);
    if (!mounted) return;
    if (!ok) {
      await _fail('Incorrect PIN. Try again.');
    }
  }

  Future<void> _unlockWithBiometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await context.read<AppLockProvider>().unlockWithBiometric();
    if (!mounted) return;
    if (!ok) {
      setState(() => _busy = false);
    }
  }

  void _onCancel() {
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    final showBiometric = lock.biometricEnabled && lock.biometricsAvailable;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: AnimatedBuilder(
              animation: _shakeOffset,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeOffset.value, 0),
                  child: child,
                );
              },
              child: SecurityCardShell(
                maxWidth: 340,
                padding: const EdgeInsets.fromLTRB(28, 36, 28, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Enter PIN',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 28),
                    PinDigitBoxes(
                      autoFocus: true,
                      enabled: !_busy,
                      hasError: _error != null,
                      clearTrigger: _clearTrigger,
                      onChanged: (value) {
                        setState(() {
                          _pin = value;
                          if (value.isNotEmpty) _error = null;
                        });
                      },
                      onCompleted: _submit,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE11D48),
                        ),
                      ),
                    ],
                    if (showBiometric) ...[
                      const SizedBox(height: 22),
                      TextButton.icon(
                        onPressed: _busy ? null : _unlockWithBiometric,
                        icon: const Icon(
                          Icons.fingerprint_rounded,
                          color: Colors.black,
                          size: 26,
                        ),
                        label: const Text(
                          'Unlock using fingerprint',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SecurityActionButton(
                      label: 'Continue',
                      isLoading: _busy,
                      onPressed: _pin.length == 4 ? () => _submit() : null,
                    ),
                    SecurityActionButton(
                      label: 'Cancel',
                      isPrimary: false,
                      onPressed: _busy ? null : _onCancel,
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const ForgotPinEmailScreen(),
                                ),
                              );
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                      ),
                      child: const Text(
                        'Forgot your PIN?',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
