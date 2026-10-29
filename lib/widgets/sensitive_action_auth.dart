import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../services/auth_service.dart';
import 'barrier_blur.dart';
import 'pin_digit_boxes.dart';
import 'security_ui.dart';

/// Returns `true` when the user confirms with PIN or fingerprint.
Future<bool> showSensitiveActionAuth({
  required BuildContext context,
  required String title,
  required String description,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (context) => withBarrierBlur(
      _SensitiveActionAuthSheet(
        title: title,
        description: description,
      ),
      alignment: Alignment.bottomCenter,
    ),
  );
  return result == true;
}

/// Performs Firebase recent-login confirmation for destructive account
/// operations. Password accounts enter their password; Google-only accounts
/// keep using the Google account picker.
Future<bool> showFirebaseReauthentication({
  required BuildContext context,
  AuthService? authService,
}) async {
  final service = authService ?? AuthService();
  final result = await showDialog<bool>(
    context: context,
    builder: (context) =>
        withBarrierBlur(_FirebaseReauthenticationDialog(authService: service)),
  );
  return result == true;
}

class _FirebaseReauthenticationDialog extends StatefulWidget {
  const _FirebaseReauthenticationDialog({required this.authService});

  final AuthService authService;

  @override
  State<_FirebaseReauthenticationDialog> createState() =>
      _FirebaseReauthenticationDialogState();
}

class _FirebaseReauthenticationDialogState
    extends State<_FirebaseReauthenticationDialog> {
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    if (widget.authService.usesPasswordProvider &&
        _passwordController.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.authService.usesPasswordProvider) {
        await widget.authService.reauthenticateWithPassword(
          _passwordController.text,
        );
      } else {
        await widget.authService.reauthenticateWithGoogle();
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyAuthError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usePassword = widget.authService.usesPasswordProvider;
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text(
        'Confirm it is you',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              usePassword
                  ? 'Enter your password to continue.'
                  : 'Continue with Google to confirm your identity.',
              style: const TextStyle(color: Color(0xFF737983)),
            ),
            if (usePassword) ...[
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('reauth-password-field'),
                controller: _passwordController,
                enabled: !_busy,
                obscureText: !_showPassword,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _confirm(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  suffixIcon: IconButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('reauth-confirm-button'),
          onPressed: _busy ? null : _confirm,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF121212),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
          ),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(usePassword ? 'Confirm' : 'Continue with Google'),
        ),
      ],
    );
  }
}

class _SensitiveActionAuthSheet extends StatefulWidget {
  const _SensitiveActionAuthSheet({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  State<_SensitiveActionAuthSheet> createState() =>
      _SensitiveActionAuthSheetState();
}

class _SensitiveActionAuthSheetState extends State<_SensitiveActionAuthSheet> {
  String _pin = '';
  String? _error;
  bool _busy = false;
  int _clearTrigger = 0;
  bool _biometricTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometric();
    });
  }

  Future<void> _tryBiometric({bool manual = false}) async {
    if (_busy || !mounted) return;
    if (!manual && _biometricTried) return;
    _biometricTried = true;

    final lock = context.read<AppLockProvider>();
    if (!lock.biometricEnabled || !lock.biometricsAvailable) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await lock.confirmWithBiometric();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _busy = false);
  }

  Future<void> _submitPin([String? value]) async {
    final pin = value ?? _pin;
    if (pin.length != 4 || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await context.read<AppLockProvider>().verifyPin(pin);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _error = 'Incorrect PIN. Try again.';
      _pin = '';
      _clearTrigger++;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    final showBiometric = lock.biometricEnabled && lock.biometricsAvailable;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6B7280),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
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
                onCompleted: _submitPin,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _busy ? null : () => _tryBiometric(manual: true),
                  icon: const Icon(
                    Icons.fingerprint_rounded,
                    color: Colors.black,
                  ),
                  label: const Text(
                    'Use fingerprint',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SecurityActionButton(
                label: 'Confirm',
                isLoading: _busy,
                onPressed: _pin.length == 4 ? () => _submitPin() : null,
              ),
              SecurityActionButton(
                label: 'Cancel',
                isPrimary: false,
                onPressed: _busy ? null : () => Navigator.pop(context, false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
