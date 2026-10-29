import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _supportEmail = 'bcueva1217@gmail.com';

class JourneyHelpDialog extends StatefulWidget {
  const JourneyHelpDialog({super.key, this.versionLoader});

  final Future<String> Function()? versionLoader;

  @override
  State<JourneyHelpDialog> createState() => _JourneyHelpDialogState();
}

class _JourneyHelpDialogState extends State<JourneyHelpDialog> {
  String _versionLabel = 'Version loading...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final version =
          await (widget.versionLoader?.call() ??
              PackageInfo.fromPlatform().then((info) => info.version));
      if (!mounted) return;
      setState(() {
        _versionLabel = version.isEmpty
            ? 'Version unavailable'
            : 'Version $version';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionLabel = 'Version unavailable');
    }
  }

  Future<void> _copyEmail() async {
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Email copied')));
  }

  Future<void> _sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: const {'subject': 'Journey to Balance support'},
    );
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    await _copyEmail();
  }

  @override
  Widget build(BuildContext context) {
    final dialog = Semantics(
      label: 'Help and support',
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 360,
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.fromBorderSide(
                              BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                          ),
                          child: const Icon(
                            Icons.support_agent_outlined,
                            size: 28,
                            color: Color(0xFF121212),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Help & Support',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF121212),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Questions or problems? We\'re happy to help.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                            color: Color(0xFF121212),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F2F4),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'EMAIL SUPPORT',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: Color(0xFF737983),
                                ),
                              ),
                              const SizedBox(height: 7),
                              const Text(
                                _supportEmail,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF121212),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 44,
                                      child: OutlinedButton(
                                        onPressed: _copyEmail,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xFF121212,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFF121212),
                                          ),
                                          shape: const StadiumBorder(),
                                        ),
                                        child: const Text(
                                          'Copy',
                                          style: TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SizedBox(
                                      height: 44,
                                      child: FilledButton(
                                        onPressed: _sendEmail,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF121212,
                                          ),
                                          foregroundColor: Colors.white,
                                          shape: const StadiumBorder(),
                                        ),
                                        child: const FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'Send email',
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontFamily: 'Inter',
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                            ),
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
                        const SizedBox(height: 14),
                        const Text(
                          'Tell us what happened and which screen you were on.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF737983),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _versionLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF737983),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF121212),
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (MediaQuery.disableAnimationsOf(context)) return dialog;
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      tween: Tween(begin: 0.96, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: ((value - 0.96) / 0.04).clamp(0.0, 1.0),
        child: Transform.scale(scale: value, child: child),
      ),
      child: dialog,
    );
  }
}
