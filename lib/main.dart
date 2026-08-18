import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/app_lock_provider.dart';
import 'providers/budget_provider.dart';
import 'providers/currency_provider.dart';
import 'providers/loan_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/pin_setup_screen.dart';
import 'screens/auth/pin_unlock_screen.dart';
import 'screens/navigation/bottom_nav_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'services/finance_api_service.dart';
import 'services/firestore_finance_service.dart';
import 'widgets/app_privacy_blur.dart';
import 'widgets/rate_limit_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => FirestoreFinanceService()),
        Provider(create: (_) => FinanceApiService()),
        ChangeNotifierProvider(
          create: (context) => BudgetProvider(
            context.read<FirestoreFinanceService>(),
            financeApi: context.read<FinanceApiService>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => LoanProvider()),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ChangeNotifierProvider(create: (_) => CurrencyProvider()),
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
      final error = context.read<BudgetProvider>().errorMessage;
      setState(() {
        _error = error;
        _ready = error == null;
      });
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
      return const RateLimitListener(child: BottomNavScreen());
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
