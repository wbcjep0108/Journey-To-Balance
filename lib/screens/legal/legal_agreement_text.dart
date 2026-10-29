import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'legal_links.dart';

class LegalAgreementText extends StatefulWidget {
  const LegalAgreementText({
    super.key,
    required this.signUp,
    required this.textAlign,
  });

  final bool signUp;
  final TextAlign textAlign;

  @override
  State<LegalAgreementText> createState() => _LegalAgreementTextState();
}

class _LegalAgreementTextState extends State<LegalAgreementText> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => openTermsOfService(context);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => openPrivacyPolicy(context);
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.signUp
        ? const Color(0xFF25282D)
        : const Color(0xFF737983);
    final size = widget.signUp ? 13.0 : 12.0;
    final prefix = widget.signUp
        ? 'I agree to the '
        : 'By continuing, you agree to our ';
    return RichText(
      key: ValueKey(
        widget.signUp ? 'signup-legal-agreement' : 'login-legal-agreement',
      ),
      textAlign: widget.textAlign,
      text: TextSpan(
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size,
          fontWeight: FontWeight.w500,
          height: 1.5,
          color: color,
        ),
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: 'Terms of Service',
            recognizer: _termsRecognizer,
            style: const TextStyle(
              color: Color(0xFF121212),
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            recognizer: _privacyRecognizer,
            style: const TextStyle(
              color: Color(0xFF121212),
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}
