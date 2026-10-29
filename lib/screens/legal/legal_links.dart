import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'legal_document_page.dart';
import 'privacy_policy.dart';
import 'terms_of_service.dart';

/// Optional hosted destinations. Leave empty to use the bundled legal pages.
const termsOfServiceHostedUrl = '';
const privacyPolicyHostedUrl = '';

Future<void> openTermsOfService(BuildContext context) {
  return _openLegalDocument(
    context,
    hostedUrl: termsOfServiceHostedUrl,
    page: const LegalDocumentPage(
      title: 'Terms of Service',
      summary: termsOfServiceSummary,
      sections: termsOfServiceSections,
    ),
  );
}

Future<void> openPrivacyPolicy(BuildContext context) {
  return _openLegalDocument(
    context,
    hostedUrl: privacyPolicyHostedUrl,
    page: const LegalDocumentPage(
      title: 'Privacy Policy',
      summary: privacyPolicySummary,
      sections: privacyPolicySections,
    ),
  );
}

Future<void> _openLegalDocument(
  BuildContext context, {
  required String hostedUrl,
  required LegalDocumentPage page,
}) async {
  if (hostedUrl.isNotEmpty) {
    final opened = await launchUrl(
      Uri.parse(hostedUrl),
      mode: LaunchMode.externalApplication,
    );
    if (opened) return;
  }
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
}
