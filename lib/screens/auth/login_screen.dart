import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../services/finance_api_service.dart';
import '../../services/legal_acceptance_service.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/security_ui.dart';
import '../legal/legal_agreement_text.dart';
import 'login_layout_constants.dart';
import 'password_reset_screen.dart';

const _supportEmail = 'bcueva1217@gmail.com';

Future<void> _showSignInHelp(
  BuildContext context, {
  required Future<void> Function() onTryAgain,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => withBarrierBlur(
      AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: Color(0xFF121212)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sign-in help',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 360,
            maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'If Google sign-in is not opening or completing:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 12),
                Text('• Check your internet connection.'),
                SizedBox(height: 6),
                Text('• Make sure a Google account is added to your device.'),
                SizedBox(height: 6),
                Text('• Close the account picker and try again.'),
                SizedBox(height: 18),
                Row(
                  children: [
                    Icon(Icons.mail_outline_rounded, color: Color(0xFF121212)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Still having trouble? Send our support team a message.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    key: const ValueKey('sign-in-help-email-support'),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _showSupportEmailComposer(context);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF121212),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.mail_outline_rounded, size: 18),
                    label: const Text(
                      'Email support',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          key: const ValueKey('sign-in-help-close'),
                          onPressed: () => Navigator.pop(dialogContext),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF121212),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton(
                          key: const ValueKey('sign-in-help-try-again'),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            onTryAgain();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF121212),
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'Try again',
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _showSupportEmailComposer(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => withBarrierBlur(const _SupportEmailDialog()),
  );
}

class _SupportEmailDialog extends StatefulWidget {
  const _SupportEmailDialog();

  @override
  State<_SupportEmailDialog> createState() => _SupportEmailDialogState();
}

class _SupportEmailDialogState extends State<_SupportEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController(
    text: 'Journey to Balance sign-in help',
  );
  final _messageController = TextEditingController();
  bool _openingEmailApp = false;
  String? _launchError;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _encodeQueryParameters(Map<String, String> parameters) {
    return parameters.entries
        .map(
          (entry) =>
              '${Uri.encodeComponent(entry.key)}='
              '${Uri.encodeComponent(entry.value)}',
        )
        .join('&');
  }

  Future<void> _openEmailApp() async {
    if (!_formKey.currentState!.validate() || _openingEmailApp) return;
    setState(() {
      _openingEmailApp = true;
      _launchError = null;
    });

    final emailUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: _encodeQueryParameters({
        'subject': _subjectController.text.trim(),
        'body': _messageController.text.trim(),
      }),
    );

    var opened = false;
    try {
      opened = await launchUrl(emailUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _openingEmailApp = false;
      if (!opened) {
        _launchError = 'No email app was found on this device.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(14)),
      borderSide: BorderSide(color: Color(0xFFD1D5DB)),
    );

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          CircleAvatar(
            backgroundColor: Color(0xFF121212),
            foregroundColor: Colors.white,
            child: Icon(Icons.mail_outline_rounded),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Email support',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.support_agent_rounded, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'To',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _supportEmail,
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _subjectController,
                  enabled: !_openingEmailApp,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    filled: true,
                    fillColor: Colors.white,
                    border: fieldBorder,
                    enabledBorder: fieldBorder,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(
                        color: Color(0xFF121212),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a subject.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _messageController,
                  enabled: !_openingEmailApp,
                  minLines: 5,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(color: Color(0xFF121212)),
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    labelStyle: TextStyle(color: Color(0xFF121212)),
                    floatingLabelStyle: TextStyle(color: Color(0xFF121212)),
                    alignLabelWithHint: true,
                    hintStyle: TextStyle(color: Color(0xFF121212)),
                    hintText:
                        'Tell us what happened when you tried to sign in…',
                    filled: true,
                    fillColor: Colors.white,
                    border: fieldBorder,
                    enabledBorder: fieldBorder,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                      borderSide: BorderSide(
                        color: Color(0xFF121212),
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a message.'
                      : null,
                ),
                if (_launchError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _launchError!,
                    style: const TextStyle(
                      color: Color(0xFFE11D48),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Gmail or your default email app will open so you can review and send the message.',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _openingEmailApp ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF121212)),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _openingEmailApp ? null : _openEmailApp,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF121212),
            foregroundColor: Colors.white,
          ),
          icon: _openingEmailApp
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.open_in_new_rounded, size: 18),
          label: Text(_openingEmailApp ? 'Opening' : 'Open Gmail'),
        ),
      ],
    );
  }
}

bool isValidAuthEmail(String value) {
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.authService,
    this.passwordResetApi,
    this.legalAcceptanceService,
  });

  final AuthService? authService;
  final PasswordResetApi? passwordResetApi;
  final LegalAcceptanceService? legalAcceptanceService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();
  late final AuthService _auth;
  LegalAcceptanceService? _createdLegalAcceptance;
  bool _isSignUp = false;
  bool _busy = false;
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _submitted = false;
  bool _termsAgreed = false;
  bool _termsError = false;
  bool _termsHighlighted = false;
  Timer? _termsHighlightTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = widget.authService ?? AuthService();
    _passwordController.addListener(_refresh);
    _confirmController.addListener(_refresh);
  }

  LegalAcceptanceService get _legalAcceptance {
    return widget.legalAcceptanceService ??
        (_createdLegalAcceptance ??= LegalAcceptanceService());
  }

  void _refresh() {
    if (mounted) setState(() => _error = null);
  }

  @override
  void dispose() {
    _termsHighlightTimer?.cancel();
    _emailController.dispose();
    _passwordController
      ..removeListener(_refresh)
      ..dispose();
    _confirmController
      ..removeListener(_refresh)
      ..dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _setMode(bool signUp) {
    if (_busy || signUp == _isSignUp) return;
    setState(() {
      _isSignUp = signUp;
      _submitted = false;
      _error = null;
      _termsAgreed = false;
      _termsError = false;
      _termsHighlighted = false;
      _confirmController.clear();
    });
  }

  void _setTermsAgreed(bool value) {
    setState(() {
      _termsAgreed = value;
      if (value) _termsError = false;
    });
  }

  void _showTermsRequired() {
    if (!_isSignUp || _termsAgreed) return;
    _termsHighlightTimer?.cancel();
    setState(() {
      _termsError = true;
      _termsHighlighted = true;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _termsHighlighted = false);
      return;
    }
    _termsHighlightTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _termsHighlighted = false);
    });
  }

  Future<void> _submit() async {
    if (_isSignUp && !_termsAgreed) {
      _showTermsRequired();
      return;
    }
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (_isSignUp) {
        final credential = await _auth.createAccount(email, password);
        final user = credential.user;
        if (user != null) {
          unawaited(_legalAcceptance.acceptCurrentVersion(user.uid));
        }
      } else {
        await _auth.signInWithEmail(email, password);
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleSignIn() async {
    if (_busy) return;
    if (_isSignUp && !_termsAgreed) {
      _showTermsRequired();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final credential = await _auth.signInWithGoogle();
      final user = credential?.user;
      if (_isSignUp && user != null) {
        unawaited(_legalAcceptance.acceptCurrentVersion(user.uid));
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PasswordResetScreen(
          initialEmail: _emailController.text.trim(),
          api: widget.passwordResetApi,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final animationDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: AutofillGroup(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              kLoginPaddingH,
              kLoginPaddingTop,
              kLoginPaddingH,
              kLoginPaddingBottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kLoginMaxWidth),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _submitted
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: BrandMark(size: kLoginLogoSize)),
                      const SizedBox(height: kLoginLogoTitleGap),
                      const Text(
                        'Journey to Balance',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF121212),
                        ),
                      ),
                      const SizedBox(height: kLoginTitleTaglineGap),
                      const Text(
                        'Sign in to sync your money everywhere.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF737983),
                        ),
                      ),
                      const SizedBox(height: kLoginTaglineToggleGap),
                      _ModeToggle(
                        isSignUp: _isSignUp,
                        enabled: !_busy,
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        onChanged: _setMode,
                      ),
                      const SizedBox(height: kLoginToggleFieldGap),
                      _AuthField(
                        key: const ValueKey('email-field'),
                        label: 'Email',
                        controller: _emailController,
                        focusNode: _emailFocus,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                        validator: (value) => isValidAuthEmail(value ?? '')
                            ? null
                            : 'Enter a valid email address.',
                      ),
                      const SizedBox(height: kLoginFieldFieldGap),
                      _AuthField(
                        key: const ValueKey('password-field'),
                        label: 'Password',
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        enabled: !_busy,
                        obscureText: !_showPassword,
                        textInputAction: _isSignUp
                            ? TextInputAction.next
                            : TextInputAction.done,
                        autofillHints: [
                          _isSignUp
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        suffixIcon: IconButton(
                          tooltip: _showPassword
                              ? 'Hide password'
                              : 'Show password',
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _showPassword = !_showPassword,
                                ),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                        onSubmitted: (_) => _isSignUp
                            ? _confirmFocus.requestFocus()
                            : _submit(),
                        validator: (value) => (value ?? '').length >= 8
                            ? null
                            : 'Password must be at least 8 characters.',
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 7, left: 14),
                        child: Text(
                          'Use at least 8 characters.',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _passwordController.text.length >= 8
                                ? const Color(0xFF16803A)
                                : const Color(0xFF737983),
                          ),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: animationDuration,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            alignment: Alignment.topLeft,
                            child: child,
                          ),
                        ),
                        child: _isSignUp
                            ? Padding(
                                key: const ValueKey('confirm-password-field'),
                                padding: const EdgeInsets.only(top: 16),
                                child: _AuthField(
                                  label: 'Confirm password',
                                  controller: _confirmController,
                                  focusNode: _confirmFocus,
                                  enabled: !_busy,
                                  obscureText: !_showConfirm,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  suffixIcon: IconButton(
                                    tooltip: _showConfirm
                                        ? 'Hide password'
                                        : 'Show password',
                                    onPressed: _busy
                                        ? null
                                        : () => setState(
                                            () => _showConfirm = !_showConfirm,
                                          ),
                                    icon: Icon(
                                      _showConfirm
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                  ),
                                  onSubmitted: (_) => _submit(),
                                  validator: (value) =>
                                      value == _passwordController.text
                                      ? null
                                      : 'Passwords do not match.',
                                ),
                              )
                            : Align(
                                key: const ValueKey('forgot-password-link'),
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _busy ? null : _forgotPassword,
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF25282D),
                                  ),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                      ),
                      AnimatedSwitcher(
                        duration: animationDuration,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SizeTransition(
                            sizeFactor: animation,
                            alignment: Alignment.topLeft,
                            child: child,
                          ),
                        ),
                        child: _isSignUp
                            ? Padding(
                                key: const ValueKey('terms-consent-row'),
                                padding: const EdgeInsets.only(top: 12),
                                child: _TermsConsentRow(
                                  agreed: _termsAgreed,
                                  highlighted: _termsHighlighted,
                                  showError: _termsError,
                                  onChanged: _setTermsAgreed,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      AnimatedSwitcher(
                        duration: animationDuration,
                        child: _error == null
                            ? const SizedBox.shrink()
                            : Padding(
                                key: ValueKey(_error),
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: kLoginFieldButtonGap),
                      Opacity(
                        opacity: _isSignUp && !_termsAgreed ? 0.5 : 1,
                        child: SizedBox(
                          height: kLoginPrimaryButtonHeight,
                          child: FilledButton(
                            key: const ValueKey('primary-auth-button'),
                            onPressed: _busy ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF121212),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0xFF4B4B4B),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  kLoginButtonRadius,
                                ),
                              ),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _isSignUp ? 'Create account' : 'Log in',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: kLoginButtonDividerGap),
                      const Row(
                        children: [
                          Expanded(child: Divider(color: Color(0xFFE2E4E8))),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: kLoginDividerLabelPadding,
                            ),
                            child: Text(
                              'or',
                              style: TextStyle(color: Color(0xFF737983)),
                            ),
                          ),
                          Expanded(child: Divider(color: Color(0xFFE2E4E8))),
                        ],
                      ),
                      const SizedBox(height: kLoginDividerGoogleGap),
                      Opacity(
                        opacity: _isSignUp && !_termsAgreed ? 0.5 : 1,
                        child: SizedBox(
                          height: kLoginGoogleButtonHeight,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _googleSignIn,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF121212),
                              side: const BorderSide(color: Color(0xFFCED1D6)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  kLoginButtonRadius,
                                ),
                              ),
                            ),
                            icon: Image.asset(
                              'assets/images/google.png',
                              width: 22,
                              height: 22,
                            ),
                            label: const Text(
                              'Continue with Google',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: kLoginGoogleTermsGap),
                      if (!_isSignUp)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: LegalAgreementText(
                            signUp: false,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (!_isSignUp) const SizedBox(height: 4),
                      Center(
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => _showSignInHelp(
                                  context,
                                  onTryAgain: _googleSignIn,
                                ),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF737983),
                          ),
                          child: const Text(
                            'Having trouble signing in?',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
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
        ),
      ),
    );
  }
}

class _TermsConsentRow extends StatelessWidget {
  const _TermsConsentRow({
    required this.agreed,
    required this.highlighted,
    required this.showError,
    required this.onChanged,
  });

  final bool agreed;
  final bool highlighted;
  final bool showError;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFFFF1F2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: agreed,
                  onChanged: (value) => onChanged(value ?? false),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  side: const BorderSide(color: Color(0xFFC9CDD2)),
                  fillColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? const Color(0xFF121212)
                        : Colors.transparent,
                  ),
                  checkColor: Colors.white,
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: LegalAgreementText(
                    signUp: true,
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
          if (showError)
            const Padding(
              padding: EdgeInsets.only(left: 52, top: 3),
              child: Text(
                'Please agree to the Terms and Privacy Policy to continue.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.isSignUp,
    required this.enabled,
    required this.duration,
    required this.onChanged,
  });

  final bool isSignUp;
  final bool enabled;
  final Duration duration;
  final ValueChanged<bool> onChanged;

  void _select(bool signUp) {
    if (!enabled || signUp == isSignUp) return;
    HapticFeedback.selectionClick();
    onChanged(signUp);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('mode-toggle-track'),
      height: kLoginToggleHeight,
      clipBehavior: Clip.none,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F2F4),
        borderRadius: BorderRadius.circular(kLoginToggleRadius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final optionWidth = (constraints.maxWidth - 10) / 2;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedPositioned(
                duration: duration,
                curve: Curves.easeOutCubic,
                left: 5 + (isSignUp ? optionWidth : 0),
                top: 5,
                bottom: 5,
                width: optionWidth,
                child: DecoratedBox(
                  key: const ValueKey('selected-mode-pill'),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212),
                    borderRadius: BorderRadius.circular(23),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: _ModeOption(
                          key: const ValueKey('login-toggle'),
                          label: 'Log in',
                          selected: !isSignUp,
                          enabled: enabled,
                          duration: duration == Duration.zero
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          onTap: () => _select(false),
                        ),
                      ),
                      Expanded(
                        child: _ModeOption(
                          key: const ValueKey('signup-toggle'),
                          label: 'Sign up',
                          selected: isSignUp,
                          enabled: enabled,
                          duration: duration == Duration.zero
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          onTap: () => _select(true),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(28),
            child: Center(
              child: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Text(
                  label,
                  key: ValueKey(selected),
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : const Color(0xFF5B6270),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    super.key,
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.textInputAction,
    required this.autofillHints,
    required this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextInputAction textInputAction;
  final List<String> autofillHints;
  final Widget? suffixIcon;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(30)),
      borderSide: BorderSide(color: Color(0xFFE2E4E8)),
    );
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      autocorrect: false,
      enableSuggestions: !obscureText,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      style: const TextStyle(
        color: Color(0xFF121212),
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF737983)),
        filled: true,
        fillColor: Colors.white,
        suffixIcon: suffixIcon,
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Color(0xFF25282D), width: 1.2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(30)),
          borderSide: BorderSide(color: Color(0xFFDC2626), width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 17,
        ),
      ),
    );
  }
}
