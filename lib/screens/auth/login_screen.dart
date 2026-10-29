import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/auth_service.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/security_ui.dart';

const _supportEmail = 'bcueva1217@gmail.com';

Future<void> _signInWithGoogle(BuildContext context) async {
  try {
    await AuthService().signInWithGoogle();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sign in failed. Please check your connection and try again.',
          ),
        ),
      );
    }
  }
}

Future<void> _showSignInHelp(BuildContext context) {
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
        content: const Column(
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
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showSupportEmailComposer(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF121212),
            ),
            icon: const Icon(Icons.mail_outline_rounded, size: 18),
            label: const Text('Email support'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF121212),
            ),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _signInWithGoogle(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF121212),
              foregroundColor: Colors.white,
            ),
            child: const Text('Try again'),
          ),
        ],
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

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const BrandMark(size: 150),

              const SizedBox(height: 40),

              const Text(
                "Journey to Balance",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF000000),
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                ),
              ),

              const SizedBox(height: 50),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: const Color(0xFF121212),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Image.asset('assets/images/google.png', width: 24),
                  label: const Text(
                    "Continue with Google",
                    style: TextStyle(fontSize: 16, color: Colors.black),
                  ),
                  onPressed: () => _signInWithGoogle(context),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _showSignInHelp(context),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                child: const Text(
                  'Having trouble signing in?',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
