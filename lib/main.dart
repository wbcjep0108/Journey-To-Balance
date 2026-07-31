import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/app_lock_provider.dart';
import 'providers/budget_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/pin_setup_screen.dart';
import 'screens/auth/pin_unlock_screen.dart';
import 'screens/navigation/bottom_nav_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'services/firestore_finance_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => FirestoreFinanceService()),
        ChangeNotifierProvider(
          create: (context) =>
              BudgetProvider(context.read<FirestoreFinanceService>()),
        ),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
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
            _boundUid = null;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              context.read<AppLockProvider>().clearUser();
            });
          }
          return const LoginScreen();
        }

        _boundUid = user.uid;
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
      context.read<AppLockProvider>().bindUser(widget.uid);
    });
  }

  @override
  void didUpdateWidget(covariant _SecurityGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      context.read<AppLockProvider>().bindUser(widget.uid);
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

class _UserDataGateState extends State<_UserDataGate> {
  late Future<void> _load;

  @override
  void initState() {
    super.initState();
    _load = context.read<BudgetProvider>().loadForUser(widget.uid);
  }

  void _retry() {
    setState(() {
      _load = context.read<BudgetProvider>().loadForUser(widget.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SplashScreen();
        }

        final error = context.read<BudgetProvider>().errorMessage;
        if (error != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _retry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return const BottomNavScreen();
      },
    );
  }
}
