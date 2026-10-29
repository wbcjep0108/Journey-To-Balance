// TODO: This text must be reviewed by a qualified professional before public release.

import 'legal_document_page.dart';

const termsOfServiceSummary =
    'Journey to Balance is a personal budgeting and planning tool. Keep your account password and device PIN private, enter only data you are allowed to use, and do not treat the app as professional financial advice.';

const termsOfServiceSections = <LegalSection>[
  LegalSection(
    heading: 'Using the app',
    body:
        'By creating an account or using Journey to Balance, you agree to these Terms and the Privacy Policy. You may use the app to record budgets, transactions, savings goals, wallet amounts, and loan reminders for your own planning.',
  ),
  LegalSection(
    heading: 'Your account and security',
    body:
        'You may sign in with an email address and password or with Google Sign-In. Keep your password, email reset codes, and four-digit app PIN private. You are responsible for activity performed through your account and device. Tell us at $legalSupportEmail if you believe someone has accessed your account without permission.',
  ),
  LegalSection(
    heading: 'Your data and content',
    body:
        'You choose the financial labels, amounts, dates, goals, wallet balances, card labels, and loan details you enter. You remain responsible for that content and for making sure you have the right to use it. The card feature stores only an app ID, a selected bank or wallet icon, and an amount. It does not ask for or store a full card number, CVV, bank password, or bank login.',
  ),
  LegalSection(
    heading: 'Planning tool, not professional advice',
    body:
        'Journey to Balance helps organize information you provide. It does not provide financial, legal, tax, accounting, or investment advice. Calculations, reminders, exchange rates, and projections may not fit your situation. Check important decisions with a qualified professional.',
  ),
  LegalSection(
    heading: 'Acceptable use',
    body:
        'Do not use the app to break the law, harm another person, access another user\'s account, bypass security or rate limits, disrupt the service, or upload content you do not have the right to use. Do not try to reverse engineer or misuse the service except where the law allows it.',
  ),
  LegalSection(
    heading: 'Availability and changes',
    body:
        'The app depends on internet access and services provided by Firebase, Google, Cloudflare, Brevo, and an exchange-rate service. Features may be unavailable, delayed, corrected, changed, or removed. We may update these Terms. When the legal version changes, the app can ask you to review and accept the new version.',
  ),
  LegalSection(
    heading: 'Ending your account',
    body:
        'You can stop using the app and sign out at any time. Signing out clears the current in-app session and scheduled reminders, but it does not delete your Firebase account, cloud data, local PIN settings, notification choices, or legacy wallet data kept on the device. The app does not currently include an account-deletion button. To ask about deletion, email $legalSupportEmail.',
  ),
  LegalSection(
    heading: 'Disclaimers and limits of liability',
    body:
        'The app is provided on an "as available" basis. We do not promise that it will always be available, error-free, or suitable for every purpose. To the fullest extent allowed by law, Journey to Balance is not responsible for indirect losses or decisions made from app calculations, reminders, exchange rates, or information you entered. Nothing in these Terms removes rights or responsibilities that cannot legally be excluded.',
  ),
  LegalSection(
    heading: 'Governing law',
    body:
        'These Terms are governed by the laws of the Philippines. Any rights you have under mandatory Philippine law continue to apply.',
  ),
  LegalSection(
    heading: 'Contact',
    body:
        'Questions about these Terms can be sent to the support email shown below.',
  ),
];
