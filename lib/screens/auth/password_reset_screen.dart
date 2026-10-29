import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/finance_api_service.dart';
import '../../widgets/pin_digit_boxes.dart';
import '../../widgets/security_ui.dart';

enum _ResetStep { email, code, password, success }

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key, required this.initialEmail, this.api});

  final String initialEmail;
  final PasswordResetApi? api;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _emailKey = GlobalKey<FormState>();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  late final TextEditingController _email;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final PasswordResetApi _api;

  _ResetStep _step = _ResetStep.email;
  String _code = '';
  String? _resetToken;
  String? _error;
  bool _busy = false;
  bool _showPassword = false;
  bool _showConfirm = false;
  int _clearCode = 0;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? FinanceApiService();
    _email = TextEditingController(text: widget.initialEmail);
    _password.addListener(_refresh);
    _confirm.addListener(_refresh);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _password
      ..removeListener(_refresh)
      ..dispose();
    _confirm
      ..removeListener(_refresh)
      ..dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() => _error = null);
  }

  bool _validEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _resendIn = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
      } else if (_resendIn <= 1) {
        timer.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  String _friendlyError(Object error, {bool code = false}) {
    if (error is FinanceApiException) {
      if (error.isRateLimited) {
        return 'Too many attempts. Please try again later.';
      }
      if (error.code == 'unavailable') return 'No internet connection.';
      if (error.statusCode == 404 || error.statusCode == 503) {
        return 'Password reset is temporarily unavailable. Please try again later.';
      }
      if (code ||
          error.code == 'invalid_code' ||
          error.code == 'invalid_token') {
        return 'Wrong or expired code';
      }
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _send() async {
    if (!_emailKey.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? nextError;
    try {
      await _api.requestPasswordReset(email: _email.text.trim());
    } catch (error) {
      nextError = _friendlyError(error);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _ResetStep.code;
      _error = nextError;
    });
    _startCooldown();
  }

  Future<void> _resend() async {
    if (_busy || _resendIn > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.requestPasswordReset(email: _email.text.trim());
      if (mounted) _startCooldown();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify([String? value]) async {
    final code = value ?? _code;
    if (code.length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await _api.verifyPasswordResetCode(
        email: _email.text.trim(),
        code: code,
      );
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _resetToken = token;
        _step = _ResetStep.password;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passwordFocus.requestFocus();
      });
    } catch (error) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _error = _friendlyError(error, code: true);
        _code = '';
        _clearCode++;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeEmail() {
    _timer?.cancel();
    setState(() {
      _step = _ResetStep.email;
      _error = null;
      _code = '';
      _clearCode++;
      _resendIn = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  Future<void> _updatePassword() async {
    if (_busy || _password.text.length < 8) return;
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.confirmPasswordReset(
        email: _email.text.trim(),
        resetToken: _resetToken ?? '',
        newPassword: _password.text,
      );
      if (mounted) setState(() => _step = _ResetStep.success);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              children: [
                const BrandMark(),
                const SizedBox(height: 28),
                SecurityCardShell(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: _content(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    return switch (_step) {
      _ResetStep.email => _emailStep(),
      _ResetStep.code => _codeStep(),
      _ResetStep.password => _passwordStep(),
      _ResetStep.success => _successStep(),
    };
  }

  Widget _heading(
    String semantics,
    String title,
    String message,
    Widget child,
  ) {
    return Semantics(
      label: semantics,
      container: true,
      child: Column(
        key: ValueKey(semantics),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF121212),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: Color(0xFF6B7280),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              key: const ValueKey('reset-error'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
          const SizedBox(height: 28),
          child,
        ],
      ),
    );
  }

  Widget _emailStep() {
    return _heading(
      'Reset password email step',
      'Reset password',
      'Enter your email address and we\'ll send you a 6-digit code.',
      Form(
        key: _emailKey,
        child: Column(
          children: [
            _field(
              key: const ValueKey('reset-email-field'),
              controller: _email,
              focusNode: _emailFocus,
              label: 'Email address',
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              validator: (value) => _validEmail(value ?? '')
                  ? null
                  : 'Enter a valid email address.',
              onSubmitted: (_) => _send(),
            ),
            const SizedBox(height: 24),
            _button('Send code', _send, key: 'reset-send-button'),
            _cancelButton(),
          ],
        ),
      ),
    );
  }

  Widget _codeStep() {
    return _heading(
      'Reset password code step',
      'Enter the code',
      'If an account exists for that email, a code is on its way.',
      Column(
        children: [
          PinDigitBoxes(
            key: const ValueKey('reset-code-field'),
            length: 6,
            boxSize: 42,
            spacing: 6,
            enabled: !_busy,
            hasError: _error == 'Wrong or expired code',
            obscureText: false,
            clearTrigger: _clearCode,
            autofillHints: const [AutofillHints.oneTimeCode],
            onChanged: (value) => setState(() {
              _code = value;
              if (value.isNotEmpty) _error = null;
            }),
            onCompleted: _verify,
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const ValueKey('reset-resend-button'),
            onPressed: _busy || _resendIn > 0 ? null : _resend,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF121212),
            ),
            child: Text(
              _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                color: Color(0xFF121212),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _button(
            'Continue',
            _code.length == 6 ? () => _verify() : null,
            key: 'reset-verify-button',
          ),
          _cancelButton(),
        ],
      ),
    );
  }

  Widget _passwordStep() {
    final longEnough = _password.text.length >= 8;
    return _heading(
      'Reset password new password step',
      'Create a new password',
      'Choose a secure password for your account.',
      Column(
        children: [
          _field(
            key: const ValueKey('reset-new-password-field'),
            controller: _password,
            focusNode: _passwordFocus,
            label: 'New password',
            obscureText: !_showPassword,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showPassword = !_showPassword),
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
            ),
            onSubmitted: (_) => _confirmFocus.requestFocus(),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'At least 8 characters',
              key: const ValueKey('reset-password-hint'),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                color: longEnough
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF6B7280),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _field(
            key: const ValueKey('reset-confirm-password-field'),
            controller: _confirm,
            focusNode: _confirmFocus,
            label: 'Confirm password',
            obscureText: !_showConfirm,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _showConfirm = !_showConfirm),
              icon: Icon(
                _showConfirm ? Icons.visibility_off : Icons.visibility,
              ),
            ),
            onSubmitted: (_) => _updatePassword(),
          ),
          const SizedBox(height: 24),
          _button(
            'Update password',
            longEnough ? _updatePassword : null,
            key: 'reset-update-button',
          ),
          _cancelButton(),
        ],
      ),
    );
  }

  Widget _successStep() {
    return _heading(
      'Reset password success step',
      'Password updated',
      'You can now log in with your new password.',
      Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFF121212),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(height: 24),
          _button(
            'Back to log in',
            () => Navigator.of(context).pop(),
            key: 'reset-back-button',
          ),
        ],
      ),
    );
  }

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      enabled: !_busy,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: !obscureText,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        color: Color(0xFF121212),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF121212)),
        floatingLabelStyle: const TextStyle(color: Color(0xFF121212)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        border: _border(const Color(0xFFE2E4E8)),
        enabledBorder: _border(const Color(0xFFE2E4E8)),
        focusedBorder: _border(const Color(0xFF25282D), width: 1.2),
        errorBorder: _border(const Color(0xFFDC2626)),
        focusedErrorBorder: _border(const Color(0xFFDC2626), width: 1.2),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 17,
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget _button(String label, VoidCallback? onPressed, {required String key}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        key: ValueKey(key),
        onPressed: _busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF121212),
          foregroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  Widget _cancelButton() => TextButton(
    style: TextButton.styleFrom(foregroundColor: const Color(0xFF8A8F98)),
    onPressed: _busy ? null : () => Navigator.of(context).pop(),
    child: const Text(
      'Cancel',
      style: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        color: Color(0xFF8A8F98),
      ),
    ),
  );
}
