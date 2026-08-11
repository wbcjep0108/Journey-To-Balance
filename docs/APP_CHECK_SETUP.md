# Firebase App Check (manual setup)

Cloud Functions are prepared with `enforceAppCheck: false` so local development keeps working.

When you are ready to enforce App Check:

## 1. Firebase Console

1. Open [App Check](https://console.firebase.google.com/project/journey-to-balance/appcheck)
2. Register Android (Play Integrity) and iOS (DeviceCheck / App Attest) apps
3. For debug builds, create debug tokens and register them in App Check → Manage debug tokens

## 2. Flutter

Add dependency:

```yaml
firebase_app_check: ^0.4.0
```

Activate in `main.dart` **after** `Firebase.initializeApp`:

```dart
await FirebaseAppCheck.instance.activate(
  androidProvider: kDebugMode
      ? AndroidProvider.debug
      : AndroidProvider.playIntegrity,
  appleProvider: kDebugMode
      ? AppleProvider.debug
      : AppleProvider.appAttest,
);
```

## 3. Cloud Functions

In `functions/src/index.ts`, change:

```ts
enforceAppCheck: false,
```

to:

```ts
enforceAppCheck: true,
```

Then redeploy functions.

**Do not enable enforcement until debug tokens work on your devices**, or signed-in financial calls will fail with `failed-precondition` / App Check errors.
