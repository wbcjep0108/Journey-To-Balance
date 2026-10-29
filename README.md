# Journey to Balance

Journey to Balance is a Flutter personal-finance app for recording income, bills, savings, and personal spending. It includes a budget planner, wallet and loan tracking, savings goals, local security controls, and cloud synchronization through Firebase.

## Features

- Email/password and Google sign-in, with account verification and password reset.
- PIN lock with optional biometric authentication and a PIN-reset flow.
- Income, balance, and percentage-based budget allocation for bills, savings, and personal spending.
- Add, edit, and delete categorized financial transactions with budget-limit checks.
- Savings goals and contributions from budget categories.
- Budget planner, daily and monthly spending views, and local notifications/reminders.
- Wallet tracking for cash, cards, currencies, and loans, synchronized across devices.
- Currency conversion using fetched exchange rates.

## Tech stack

| Area | Technology |
| --- | --- |
| Mobile app | Flutter with Dart SDK `^3.12.2` ([pubspec.yaml](pubspec.yaml)) |
| State management | `provider` for app, budget, wallet, planner, and security state |
| Authentication | Firebase Authentication with email/password and Google sign-in |
| Data | Cloud Firestore for user budgets, transactions, planner data, and wallet data |
| Notifications and device security | `flutter_local_notifications`, `timezone`, `local_auth`, and `flutter_secure_storage` |
| Networking | `http` for the Worker API and exchange-rate service |
| API | Cloudflare Worker with TypeScript, Firebase ID-token verification, Firestore REST access, and Durable Objects for rate limiting |
| Server functions | Firebase Functions v2 with TypeScript and Firebase Admin SDK; retained as an optional callable-functions implementation |

Other notable packages include `intl` for formatting, `crypto` for security-related helpers, `url_launcher` for external links, and `package_info_plus` for app metadata. `cloud_functions` is declared in the Flutter project, but the current app-side finance flow uses the Worker API.

## Folder structure

```text
.
├── .agents/                         Repository-local agent resources
├── .codex/                          Codex workspace configuration
├── .cursor/                         Cursor workspace configuration
├── .dart_tool/                      Generated Dart/Flutter tool state
├── .idea/                           IDE project settings
├── .wrangler/                       Wrangler local state
├── android/                         Flutter Android host project
├── assets/                          Bundled fonts and images
│   ├── fonts/                       Inter font files
│   └── images/                      Logo, Google image, bank, and wallet images
├── build/                           Generated build output
├── docs/                            Project documentation folder
├── functions/                       Optional Firebase Functions TypeScript project
│   ├── lib/                         Compiled JavaScript output
│   ├── scripts/                     Maintenance scripts
│   └── src/                         Callable finance functions and tests
├── ios/                             Flutter iOS host project
├── journey-to-balance-api/          Cloudflare Worker API project
│   └── src/                         Worker routes, finance logic, auth, rate limits, and tests
├── lib/                             Flutter application source
│   ├── models/                      Budget, transaction, loan, currency, and planner models
│   ├── providers/                   Application state and Firestore-backed providers
│   ├── screens/                     Feature screens
│   │   ├── account/                 Account, currency, notification, and security settings
│   │   ├── auth/                    Login, PIN, and forgot-PIN screens
│   │   ├── bills/                   Bills screen
│   │   ├── home/                    Home, planner, spending, and wallet screens
│   │   ├── loans/                   Loan screens
│   │   ├── navigation/              Bottom navigation
│   │   ├── personal/                Personal-spending screen
│   │   ├── savings/                 Savings and savings-goal screens
│   │   └── splash/                  Splash and welcome transition
│   ├── services/                    Firebase, Worker API, notifications, and device services
│   ├── widgets/                     Shared UI components and dialogs
│   ├── firebase_options.dart        Generated Firebase platform configuration
│   └── main.dart                    App entry point and provider setup
├── linux/                           Flutter Linux host project
├── macos/                           Flutter macOS host project
├── test/                            Flutter unit and widget tests
├── tool/                            Project tooling folder
├── web/                             Flutter web host project
├── windows/                         Flutter Windows host project
├── firebase.json                    Firebase CLI configuration for rules and Functions
├── firestore.rules                  Firestore access rules
└── pubspec.yaml                     Flutter dependencies, SDK constraint, and assets
```

## Architecture overview

The Flutter app initializes Firebase, observes Firebase Authentication state, and uses providers to coordinate UI and synced data. Users sign in with Firebase Authentication, then the app loads its budget, planner, and wallet state from Firestore. Financial mutations such as receiving salary, changing allocations, and managing transactions go through the Cloudflare Worker, which verifies the Firebase ID token, rate-limits operations with a Durable Object, and writes atomically to Firestore using a service account. The Worker also supports the authenticated PIN-reset flow and requires email-provider configuration for sending reset codes. Firestore rules let an owner read their data; direct client writes are limited to the planner and `users/{uid}/wallet/{docId}`, while transaction and budget writes are Worker-only. The Firestore layout includes `users/{uid}` for the budget and planner map, `users/{uid}/bills`, `users/{uid}/savings`, and `users/{uid}/personal` for financial entries, `users/{uid}/wallet/data` for wallet state, and a denied `users/{uid}/security` area. Firebase Functions contains a separate callable implementation of protected finance operations, but the current Flutter client calls the Worker instead.

## Getting started

### Prerequisites

- Flutter SDK compatible with Dart `^3.12.2`.
- Node.js 24 for [functions](functions/package.json); a current Node.js installation for the Worker.
- Firebase CLI for local emulators or Firebase deployments.
- A Firebase project with Firestore and Firebase Authentication enabled.

### Clone and install dependencies

```bash
git clone <repository-url>
cd journey_to_balance
flutter pub get
```

Install the server-side dependencies when working in either backend:

```bash
cd journey-to-balance-api
npm install
```

```bash
cd functions
npm install
```

### Firebase setup

1. Create or select the Firebase project used by this app.
2. In Firebase Authentication, enable **Email/Password** and **Google** sign-in.
3. Register the Android app and place its configuration file at [android/app/google-services.json](android/app/google-services.json).
4. Generate or update [lib/firebase_options.dart](lib/firebase_options.dart) for the Firebase project if needed.
5. Create a Firestore database and review [firestore.rules](firestore.rules) before applying them.

### Run the Flutter app

```bash
flutter run
```

### Run the Worker locally

```bash
cd journey-to-balance-api
npm run dev
```

The Worker’s finance routes need the Firebase-related Worker configuration listed below. Use a non-production Firebase project and non-production credentials for local development.

### Run tests

```bash
flutter test
```

## Configuration

| Name or file | Required | Purpose |
| --- | --- | --- |
| [android/app/google-services.json](android/app/google-services.json) | Yes for Android | Android Firebase configuration |
| [lib/firebase_options.dart](lib/firebase_options.dart) | Yes | Generated Firebase configuration used by the Flutter app |
| [firebase.json](firebase.json) | Yes for Firebase CLI work | Defines Firestore rules and the Functions source directory |
| [firestore.rules](firestore.rules) | Yes for Firestore deployment | Defines Firestore access control |
| [journey-to-balance-api/wrangler.jsonc](journey-to-balance-api/wrangler.jsonc) | Yes for Worker development/deployment | Worker entry point, Durable Object binding, and non-secret variables |
| `FIREBASE_PROJECT_ID` | Yes for Worker | Firebase project identifier available to the Worker |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | Yes for Worker finance and PIN-reset routes | Service-account JSON stored as a Worker secret |
| `BREVO_API_KEY` | Required for PIN-reset emails | Email-provider API secret |
| `BREVO_SENDER_EMAIL` | Required for PIN-reset emails | Sender address configuration |
| `BREVO_SENDER_NAME` | Required for PIN-reset emails | Sender display-name configuration |
| `GCLOUD_PROJECT` | Optional | Project selection for the Functions transaction-icon migration script |
| `FinanceApiService.defaultBaseUrl` in [lib/services/finance_api_service.dart](lib/services/finance_api_service.dart) | Required for a different Worker endpoint | App-side Worker base URL setting |

Do not commit service-account files, API keys, or deployment credentials.

## Deployment notes

- **Firestore rules:** [firebase.json](firebase.json) points to [firestore.rules](firestore.rules). Deploy or update rules only after reviewing their owner-only reads and Worker-only financial-write design.
- **Cloudflare Worker:** [journey-to-balance-api](journey-to-balance-api) defines an `npm run deploy` script. Its deployed endpoint is configured directly in the Flutter source, so a different Worker deployment requires updating the app configuration before release.
- **Firebase Functions:** [functions](functions) has `npm run deploy`, and Firebase Functions requires the Firebase **Blaze** plan. The Functions implementation is optional for the current Flutter client, which does not call its callable endpoints. This repository alone does not verify whether Functions are currently deployed.

## Testing

Run Flutter tests from the repository root:

```bash
flutter test
```

Run Worker tests and type checking:

```bash
cd journey-to-balance-api
npm test
npm run typecheck
```

Run Firebase Functions tests (the script builds first):

```bash
cd functions
npm test
```

## Known limitations and roadmap

- Firebase App Check is prepared in [functions/src/index.ts](functions/src/index.ts) but is currently not enforced; the code notes that provider setup is still needed before enabling enforcement.
- Several Flutter tests use placeholder `UnimplementedError` stubs for dependencies, so those test doubles need implementation before they exercise those paths end to end.
- The Worker route for probing the production `addMoney` rate-limit bucket is explicitly marked temporary in [journey-to-balance-api/src/index.ts](journey-to-balance-api/src/index.ts).
- No deployment-status record is kept in the repository, so deployed Worker and Functions state must be confirmed in their respective consoles.

## Author

Wilhem Bruce Cuevas, BSIT student, National University Manila.

## License

License: not yet specified
