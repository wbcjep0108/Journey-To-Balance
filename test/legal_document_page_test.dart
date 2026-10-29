import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/screens/legal/legal_document_page.dart';
import 'package:just_budget/screens/legal/privacy_policy.dart';
import 'package:just_budget/screens/legal/terms_of_service.dart';
import 'package:just_budget/services/legal_acceptance_service.dart';

Widget _app({
  required String title,
  required String summary,
  required List<LegalSection> sections,
  double textScale = 1,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: LegalDocumentPage(title: title, summary: summary, sections: sections),
  );
}

void main() {
  final documents =
      <({String title, String summary, List<LegalSection> sections})>[
        (
          title: 'Terms of Service',
          summary: termsOfServiceSummary,
          sections: termsOfServiceSections,
        ),
        (
          title: 'Privacy Policy',
          summary: privacyPolicySummary,
          sections: privacyPolicySections,
        ),
      ];

  for (final document in documents) {
    testWidgets('${document.title} renders legal navigation and contact', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          title: document.title,
          summary: document.summary,
          sections: document.sections,
        ),
      );

      expect(find.byKey(const ValueKey('legal-summary-card')), findsOneWidget);
      expect(find.text('The short version'), findsOneWidget);
      expect(find.byKey(const ValueKey('legal-jump-list')), findsOneWidget);
      expect(find.text(document.sections.first.heading), findsNWidgets(2));
      expect(find.text('1. ${document.sections.first.heading}'), findsNothing);
      expect(find.text('Last updated: October 29, 2026'), findsOneWidget);
      expect(find.text('Version: $currentLegalVersion'), findsOneWidget);

      final contact = find.byKey(const ValueKey('legal-contact-card'));
      await tester.dragUntilVisible(
        contact,
        find.byKey(const ValueKey('legal-document-scroll')),
        const Offset(0, -500),
      );
      await tester.pump();
      expect(contact, findsOneWidget);
      expect(find.text(legalSupportEmail), findsOneWidget);
      expect(find.byKey(const ValueKey('legal-copy-email')), findsOneWidget);
      expect(find.byKey(const ValueKey('legal-send-email')), findsOneWidget);
    });
  }

  testWidgets('jump list scrolls to the selected section', (tester) async {
    await tester.pumpWidget(
      _app(
        title: 'Privacy Policy',
        summary: privacyPolicySummary,
        sections: privacyPolicySections,
        disableAnimations: true,
      ),
    );

    final lastIndex = privacyPolicySections.length - 1;
    final jump = find.byKey(ValueKey('legal-jump-$lastIndex'));
    await tester.ensureVisible(jump);
    await tester.pump();
    await tester.tap(jump);
    await tester.pump();

    final target = find.byKey(ValueKey('legal-section-$lastIndex'));
    final top = tester.getTopLeft(target).dy;
    expect(top, greaterThanOrEqualTo(0));
    expect(top, lessThan(600));
  });

  testWidgets('copy puts the exact support email on the clipboard', (
    tester,
  ) async {
    MethodCall? clipboardCall;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCall = call;
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      _app(
        title: 'Terms of Service',
        summary: termsOfServiceSummary,
        sections: termsOfServiceSections,
      ),
    );
    final copy = find.byKey(const ValueKey('legal-copy-email'));
    await tester.dragUntilVisible(
      copy,
      find.byKey(const ValueKey('legal-document-scroll')),
      const Offset(0, -500),
    );
    await tester.pump();
    await tester.tap(copy);
    await tester.pump();

    expect(clipboardCall?.method, 'Clipboard.setData');
    expect(clipboardCall?.arguments, <String, dynamic>{
      'text': legalSupportEmail,
    });
    expect(find.text('Email copied'), findsOneWidget);
  });

  testWidgets('legal pages fit at 360px and 1.3x text scale', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    for (final document in documents) {
      await tester.pumpWidget(
        _app(
          title: document.title,
          summary: document.summary,
          sections: document.sections,
          textScale: 1.3,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  test(
    'documents contain no placeholders and keep professional review TODOs',
    () {
      final userFacing = <String>[
        termsOfServiceSummary,
        privacyPolicySummary,
        for (final section in termsOfServiceSections) ...[
          section.heading,
          section.body,
        ],
        for (final section in privacyPolicySections) ...[
          section.heading,
          section.body,
        ],
      ].join('\n');
      expect(userFacing, isNot(contains('PLACEHOLDER')));

      for (final path in <String>[
        'lib/screens/legal/terms_of_service.dart',
        'lib/screens/legal/privacy_policy.dart',
      ]) {
        final firstLine = File(path).readAsLinesSync().first;
        expect(firstLine, contains('reviewed by a qualified professional'));
      }
    },
  );
}
