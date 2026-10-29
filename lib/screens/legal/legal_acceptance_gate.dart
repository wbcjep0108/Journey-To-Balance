import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/legal_acceptance_service.dart';
import 'legal_agreement_text.dart';

class LegalAcceptanceGate extends StatefulWidget {
  const LegalAcceptanceGate({
    super.key,
    required this.userId,
    required this.child,
    this.service,
  });

  final String userId;
  final Widget child;
  final LegalAcceptanceService? service;

  @override
  State<LegalAcceptanceGate> createState() => _LegalAcceptanceGateState();
}

class _LegalAcceptanceGateState extends State<LegalAcceptanceGate> {
  late LegalAcceptanceService _service;
  bool _checking = true;
  bool _needsAcceptance = false;
  bool _accepted = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? LegalAcceptanceService();
    _check();
  }

  Future<void> _check() async {
    try {
      final needsAcceptance =
          !_service.isAcknowledgedThisSession(widget.userId) &&
          !await _service.hasCurrentAcceptance(widget.userId);
      if (mounted) {
        setState(() {
          _checking = false;
          _needsAcceptance = needsAcceptance;
        });
      }
    } catch (_) {
      // A transient read failure never prevents access or signing out.
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _continue() async {
    if (!_accepted || _saving) return;
    setState(() => _saving = true);
    await _service.acceptCurrentVersion(widget.userId);
    if (mounted) {
      setState(() {
        _saving = false;
        _needsAcceptance = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_needsAcceptance) return widget.child;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'We updated our Terms',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF121212),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Please review and accept the updated Terms of Service and Privacy Policy to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                      color: Color(0xFF737983),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _accepted,
                          onChanged: (value) =>
                              setState(() => _accepted = value ?? false),
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
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _accepted && !_saving ? _continue : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: const Color(0xFF121212),
                      foregroundColor: Colors.white,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Continue'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _saving ? null : () => AuthService().signOut(),
                    child: const Text('Sign out'),
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
