import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/legal_acceptance_service.dart';

const legalSupportEmail = 'bcueva1217@gmail.com';

class LegalSection {
  const LegalSection({required this.heading, required this.body});

  final String heading;
  final String body;
}

class LegalDocumentPage extends StatefulWidget {
  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.summary,
    required this.sections,
  });

  final String title;
  final String summary;
  final List<LegalSection> sections;

  @override
  State<LegalDocumentPage> createState() => _LegalDocumentPageState();
}

class _LegalDocumentPageState extends State<LegalDocumentPage> {
  late final List<GlobalKey> _sectionKeys = List<GlobalKey>.generate(
    widget.sections.length,
    (_) => GlobalKey(),
  );

  Future<void> _jumpTo(int index) async {
    final target = _sectionKeys[index].currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      alignment: 0.05,
    );
  }

  Future<void> _copyEmail() async {
    await Clipboard.setData(const ClipboardData(text: legalSupportEmail));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Email copied')));
  }

  Future<void> _sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: legalSupportEmail,
      queryParameters: {'subject': 'Journey to Balance ${widget.title}'},
    );
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    await _copyEmail();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF121212),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SelectionArea(
          child: SingleChildScrollView(
            key: const ValueKey('legal-document-scroll'),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF121212),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Last updated: ${legalVersionDateLabel()}',
                  style: _metaStyle,
                ),
                Text('Version: $currentLegalVersion', style: _metaStyle),
                const SizedBox(height: 20),
                Container(
                  key: const ValueKey('legal-summary-card'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F2F4),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'The short version',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF121212),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(widget.summary, style: _bodyStyle),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Jump to a section',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF121212),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  key: const ValueKey('legal-jump-list'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var index = 0; index < widget.sections.length; index++)
                      ActionChip(
                        key: ValueKey('legal-jump-$index'),
                        onPressed: () => _jumpTo(index),
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFC9CDD2)),
                        shape: const StadiumBorder(),
                        label: Text(
                          widget.sections[index].heading,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF25282D),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                for (
                  var index = 0;
                  index < widget.sections.length;
                  index++
                ) ...[
                  Column(
                    key: _sectionKeys[index],
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.sections[index].heading,
                        key: ValueKey('legal-section-$index'),
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF121212),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(widget.sections[index].body, style: _bodyStyle),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
                _ContactCard(onCopy: _copyEmail, onSendEmail: _sendEmail),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _metaStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.6,
    color: Color(0xFF737983),
  );

  static const _bodyStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.6,
    color: Color(0xFF25282D),
  );
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.onCopy, required this.onSendEmail});

  final VoidCallback onCopy;
  final VoidCallback onSendEmail;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('legal-contact-card'),
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
            legalSupportEmail,
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
                child: OutlinedButton(
                  key: const ValueKey('legal-copy-email'),
                  onPressed: onCopy,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: const Color(0xFF121212),
                    side: const BorderSide(color: Color(0xFF121212)),
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
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('legal-send-email'),
                  onPressed: onSendEmail,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: const Color(0xFF121212),
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
            ],
          ),
        ],
      ),
    );
  }
}
