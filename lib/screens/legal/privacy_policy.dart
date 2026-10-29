// TODO: This text must be reviewed by a qualified professional before public release.

import 'legal_document_page.dart';

const privacyPolicySummary =
    'Journey to Balance uses the account and financial information you choose to provide so it can sign you in, sync your budget, and schedule reminders. Your PIN and biometric data stay under device control. The app has no advertising, analytics, or profiling SDK.';

const privacyPolicySections = <LegalSection>[
  LegalSection(
    heading: 'Who we are and how to contact us',
    body:
        'Journey to Balance is the name of this budgeting app. For privacy questions, requests, or concerns, use the support email in the contact card at the bottom of this page.',
  ),
  LegalSection(
    heading: 'Information we collect',
    body:
        'Account information: Firebase Authentication processes your user ID, email address, sign-in provider, email-verification status, and account credentials. Google Sign-In can also provide your display name and profile photo.\n\nFinancial entries you enter: We store titles, amounts, dates, refund status, optional category icons, and optional funding-source labels for bills, savings, and personal entries. Wallet data includes cash amount, currency, card or wallet icon labels and amounts, plus loan names, amounts, due dates, and paid-installment dates. The app does not ask for or store full card numbers, CVVs, bank passwords, or bank login credentials.\n\nBudget planner: We store salary and balance values, category percentages and remaining amounts, savings-goal details, plan periods, plan dates, enabled categories, planned amounts, and alert status.\n\nDevice and notification data: The app stores notification choices, reminder times, auto-lock choice, and local alert flags on the device. The device operating system also handles notification permission, alarms, and biometric checks.',
  ),
  LegalSection(
    heading: 'How we use information',
    body:
        'We use this information to sign you in, verify account ownership, show and sync your financial records, calculate budget balances, manage savings goals, display wallet and loan information, schedule local reminders, protect sensitive actions, prevent repeated requests, and record which legal version you accepted. The repository contains no advertising, analytics, or profiling code.',
  ),
  LegalSection(
    heading: 'Who processes information',
    body:
        'Firebase and Google process account sign-in and store cloud data in Firebase Authentication and Cloud Firestore. Google Sign-In processes Google account sign-in. Cloudflare runs the Worker that verifies Firebase tokens, performs protected financial changes, and keeps temporary rate-limit, lock, and idempotency records. Brevo receives an email address and one-time code to deliver PIN or password reset email. The open.er-api.com exchange-rate service supplies currency rates; the app does not send your entered financial amounts in that request.',
  ),
  LegalSection(
    heading: 'Data kept on your device only',
    body:
        'The app stores a hash of your four-digit PIN, whether biometric unlock is enabled, your auto-lock choice, notification settings, reminder times, and local alert flags in device storage. Your fingerprint or face template is controlled by the device operating system and is not received or stored by Journey to Balance. Older versions may also leave local wallet, card-label, currency, and loan data on the device after it is copied to Firestore.',
  ),
  LegalSection(
    heading: 'How long we keep information and deletion requests',
    body:
        'The app code does not set one general deletion period for account and financial data. Signing out does not delete your Firebase account, cloud records, local security choices, notification settings, or legacy wallet data. The app currently has no account-deletion button. To ask about access or deletion, use the support email below.\n\nPIN reset codes and password reset codes are valid for ten minutes. Only a hash of each code is stored. Reset records are removed after successful use and when an expired or over-attempt record is checked. Cloudflare idempotency records are treated as expired after 24 hours when they are next read.',
  ),
  LegalSection(
    heading: 'Security',
    body:
        'The app uses Firebase Authentication, owner-based Firestore access rules, verified Firebase ID tokens for protected Worker requests, hashed reset codes, rate limits, device secure storage, and device biometric checks. No system can guarantee complete security. Keep your password, PIN, device, and one-time codes private, and contact support if you believe your account has been misused.',
  ),
  LegalSection(
    heading: 'Your rights under the Philippine Data Privacy Act',
    body:
        'The Philippine Data Privacy Act of 2012 may give you rights over your personal data. These can include asking what data is held and how it is used, requesting access or correction, asking for erasure or blocking when allowed, objecting to certain processing, receiving portable data when applicable, and filing a complaint with the National Privacy Commission. Use the support email below to make a request. These rights can depend on the facts and applicable law.',
  ),
  LegalSection(
    heading: 'Changes to this policy',
    body:
        'We may update this Privacy Policy when the app or its data practices change. The page shows its current date and version. When the version changes, the app can ask signed-in users to review and accept it again.',
  ),
];
