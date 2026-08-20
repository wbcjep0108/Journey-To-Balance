import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_lock_provider.dart';
import '../../providers/budget_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/security_ui.dart';
import 'fingerprint_enable_modal.dart';

/// First-time PIN creation: enter + re-enter, then optional biometric.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _pin = '';
  String _confirm = '';
  String? _error;
  bool _busy = false;
  int _clearConfirm = 0;

  bool get _canContinue =>
      _pin.length == 4 && _confirm.length == 4 && !_busy;

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    final budget = context.read<BudgetProvider>();
    final lock = context.read<AppLockProvider>();
    try {
      await AuthService().signOut();
      budget.reset();
      lock.clearUser();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not cancel. Please try again.')),
      );
      setState(() => _busy = false);
    }
  }

  Future<void> _continue() async {
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

    final lock = context.read<AppLockProvider>();
    try {
      await lock.completePinSetup(_pin);
      if (!mounted) return;

      final biometricsAvailable = lock.biometricsAvailable;
      var enableBiometric = false;

      if (biometricsAvailable) {
        final result = await showFingerprintEnableModal(context);
        enableBiometric = result == true;
      }

      if (!mounted) return;
      await lock.finishSetup(enableBiometric: enableBiometric);
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
                      const Text(
                        'Set a password',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Create a 4-digit PIN to secure your account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6B7280),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
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
                        onCompleted: (value) {
                          setState(() => _pin = value);
                        },
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
                        onCompleted: (value) {
                          setState(() => _confirm = value);
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
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
                      const SizedBox(height: 28),
                      SecurityActionButton(
                        label: 'Continue',
                        isLoading: _busy,
                        onPressed: _canContinue ? _continue : null,
                      ),
                      const SizedBox(height: 4),
                      SecurityActionButton(
                        label: 'Cancel',
                        isPrimary: false,
                        onPressed: _busy ? null : _cancel,
                      ),
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
