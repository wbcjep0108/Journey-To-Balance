import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'models/loan_entry.dart';
import 'providers/app_lock_provider.dart';
import 'providers/budget_provider.dart';
import 'providers/currency_provider.dart';
import 'providers/loan_provider.dart';
import 'providers/notification_prefs_provider.dart';
import 'providers/wallet_cards_provider.dart';
import 'providers/wallet_cash_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/pin_setup_screen.dart';
import 'screens/auth/pin_unlock_screen.dart';
import 'screens/navigation/bottom_nav_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/splash/welcome_transition.dart';
import 'services/finance_api_service.dart';
import 'services/firestore_finance_service.dart';
import 'services/wallet_firestore_service.dart';
import 'services/wallet_migration_service.dart';
import 'services/notification_router.dart';
import 'services/notification_service.dart';
import 'widgets/app_privacy_blur.dart';
import 'widgets/rate_limit_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  NotificationService.instance.onNotificationTap = NotificationRouter.handle;
  try {
    await NotificationService.instance.init();
  } catch (_) {}

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => FirestoreFinanceService()),
        Provider(create: (_) => WalletFirestoreService()),
        Provider(
          create: (context) => WalletMigrationService(
            firestore: context.read<WalletFirestoreService>(),
          ),
        ),
        Provider(create: (_) => FinanceApiService()),
        ChangeNotifierProvider(
          create: (context) => BudgetProvider(
            context.read<FirestoreFinanceService>(),
            financeApi: context.read<FinanceApiService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              LoanProvider(service: context.read<WalletFirestoreService>()),
        ),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ChangeNotifierProvider(
          create: (context) =>
              CurrencyProvider(service: context.read<WalletFirestoreService>()),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationPrefsProvider()..load(),
        ),
        ChangeNotifierProvider(
          create: (context) => WalletCashProvider(
            service: context.read<WalletFirestoreService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => WalletCardsProvider(
            service: context.read<WalletFirestoreService>(),
          ),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: NotificationRouter.navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF222222),
          brightness: Brightness.light,
        ),
      ),
      builder: (context, child) {
        return AppPrivacyBlur(child: child ?? const SizedBox.shrink());
      },
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _boundUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        final user = snapshot.data;
        if (user == null) {
          if (_boundUid != null) {
            final previousUid = _boundUid;
            _boundUid = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              // Only clear if we are still signed out.
              if (_boundUid == null && previousUid != null) {
                context.read<AppLockProvider>().clearUser();
                // Stop wallet realtime listeners and reset synced state so the
                // next user doesn't briefly see the previous user's wallet.
                context.read<LoanProvider>().clear();
                context.read<CurrencyProvider>().clear();
                context.read<WalletCashProvider>().clear();
                context.read<WalletCardsProvider>().clear();
                NotificationService.instance.cancelAllReminders();
                PostLoginWelcome.resetSession();
              }
            });
          }
          return const LoginScreen();
        }

        if (_boundUid != user.uid) {
          _boundUid = user.uid;
        }
        return _SecurityGate(
          key: ValueKey('security_${user.uid}'),
          uid: user.uid,
        );
      },
    );
  }
}

class _SecurityGate extends StatefulWidget {
  const _SecurityGate({super.key, required this.uid});

  final String uid;

  @override
  State<_SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends State<_SecurityGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppLockProvider>().bindUser(widget.uid);
    });
  }

  @override
  void didUpdateWidget(covariant _SecurityGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AppLockProvider>().bindUser(widget.uid);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AppLockProvider>().status;

    switch (status) {
      case AppLockStatus.checking:
        return const SplashScreen();
      case AppLockStatus.needsSetup:
        return const PinSetupScreen();
      case AppLockStatus.locked:
        return const PinUnlockScreen();
      case AppLockStatus.unlocked:
        return _UserDataGate(key: ValueKey(widget.uid), uid: widget.uid);
    }
  }
}

class _UserDataGate extends StatefulWidget {
  const _UserDataGate({super.key, required this.uid});

  final String uid;

  @override
  State<_UserDataGate> createState() => _UserDataGateState();
}

/// Loads budget data after the first frame, then mounts [BottomNavScreen].
/// Once ready, BottomNav is kept mounted (never torn down by reload/retry
/// mid-notify), which avoids InheritedWidget `_dependents.isEmpty` crashes.
class _UserDataGateState extends State<_UserDataGate> {
  bool _started = false;
  bool _ready = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  @override
  void didUpdateWidget(covariant _UserDataGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _started = false;
      _ready = false;
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load();
      });
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    if (_started && _ready && _error == null) return;

    _started = true;
    _loading = true;

    if (mounted) {
      setState(() => _error = null);
    }

    // Let the splash frame commit before notifyListeners from loadForUser.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      _loading = false;
      return;
    }

    try {
      await context.read<BudgetProvider>().loadForUser(widget.uid);
      if (!mounted) return;
      // One-time migration of legacy local wallet data -> Firestore. MUST run
      // before the wallet providers attach realtime listeners below, otherwise
      // an empty remote snapshot could seed over the local values. Firestore is
      // the source of truth if it already has data; local data is never deleted
      // and is kept as a fallback. On failure this throws into the catch below,
      // surfacing the retry UI without touching local data.
      await context.read<WalletMigrationService>().migrateIfNeeded(widget.uid);
      if (!mounted) return;
      // Wallet data (cash, cards, currency, loans) now syncs from Firestore
      // under users/{uid}/wallet. Loaded in parallel; each provider also opens
      // a realtime listener so changes on another device appear automatically.
      await Future.wait<void>([
        context.read<LoanProvider>().loadForUser(widget.uid),
        context.read<CurrencyProvider>().loadForUser(widget.uid),
        context.read<WalletCashProvider>().loadForUser(widget.uid),
        context.read<WalletCardsProvider>().loadForUser(widget.uid),
      ]);
      if (!mounted) return;
      await context.read<NotificationPrefsProvider>().load();
      if (!mounted) return;
      final error = context.read<BudgetProvider>().errorMessage;
      final loans = context.read<LoanProvider>().loans;
      setState(() {
        _error = error;
        _ready = error == null;
      });
      if (error == null) {
        unawaited(_activateReminders(loans));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Saved data could not be loaded. Check your connection and retry.';
        _ready = false;
      });
    } finally {
      _loading = false;
    }
  }

  Future<void> _activateReminders(List<LoanEntry> loans) async {
    try {
      await NotificationService.instance.requestPermission();
      await NotificationService.instance.syncAll(loans: loans);
    } catch (_) {}
  }

  void _retry() {
    _started = false;
    _ready = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
    setState(() {
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep BottomNav mounted once ready — never swap it for Splash on reload.
    if (_ready) {
      return const RateLimitListener(
        child: PostLoginWelcome(child: BottomNavScreen()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loading ? null : _retry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const SplashScreen();
  }
}
