import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../navigation/bottom_nav_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 150,
              ),

              const SizedBox(height: 40),

              const Text(
                "Journey to Balance",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF8F9FE),
                ),
              ),

              const SizedBox(height: 50),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  icon: Image.asset(
                    'assets/images/google.png', 
                    width: 24,
                  ),
      
                 label: const Text(
                  "Continue with Google",
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF121212),
                  ),
                ),
                  onPressed: () async {
                    final user =
                        await AuthService().signInWithGoogle();

                    if (user != null && context.mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BottomNavScreen(),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 