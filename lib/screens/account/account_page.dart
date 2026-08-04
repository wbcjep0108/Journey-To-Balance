import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_lock_provider.dart';
import '../../providers/budget_provider.dart';
import '../../services/auth_service.dart';
import 'security_settings_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, this.onHelpAndSupport, this.onAbout});

  final VoidCallback? onHelpAndSupport;
  final VoidCallback? onAbout;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _isSigningOut = false;

  Future<void> _signOut() async {
    if (_isSigningOut) return;

    setState(() => _isSigningOut = true);
    final budget = context.read<BudgetProvider>();
    final lock = context.read<AppLockProvider>();

    try {
      await AuthService().signOut();
      budget.reset();
      lock.clearUser();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign out failed. Please try again.')),
      );
      setState(() => _isSigningOut = false);
    }
  }

  void _openSecurity() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SecuritySettingsPage()),
    );
  }

  void _openHelp() {
    final callback = widget.onHelpAndSupport;
    if (callback != null) {
      callback();
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Help & Support'),
        content: const Text(
          'For help with Journey to Balance, contact the application support (bcueva1217@gmail.com) '
          'team for the latest support information.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }

  void _openAbout() {
    final callback = widget.onAbout;
    if (callback != null) {
      callback();
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'About us',
          style: TextStyle(
            color: Color(0xFF25282D),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Journey to Balance is a personal finance application designed '
            'to help users take control of their financial well-being. It '
            'provides simple tools to track income, manage bills, monitor '
            'savings, and organize personal financial information in one '
            'secure place. With cloud synchronization through Firebase, '
            'users can securely access their financial data anytime, '
            'anywhere, making it easier to build healthy financial habits '
            'and achieve long-term financial stability.\n\n'
            'This application was developed by Wilhem Bruce Cuevas, a '
            'Bachelor of Science in Information Technology (BSIT) student '
            'specializing in Mobile and Web Application at National '
            'University Manila, as part of his commitment to creating '
            'practical and user-centered digital solutions.',
            style: TextStyle(
              color: Color(0xFF3F444C),
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF3F444C),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 108),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _AccountCard(
                        user: user,
                        isSigningOut: _isSigningOut,
                        onSwitchProfile: _signOut,
                        onSecurity: _openSecurity,
                        onHelp: _openHelp,
                        onSignOut: _signOut,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _openAbout,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: const Text('About us'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.user,
    required this.isSigningOut,
    required this.onSwitchProfile,
    required this.onSecurity,
    required this.onHelp,
    required this.onSignOut,
  });

  final User? user;
  final bool isSigningOut;
  final VoidCallback onSwitchProfile;
  final VoidCallback onSecurity;
  final VoidCallback onHelp;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProfileAvatar(photoUrl: user?.photoURL),
          const SizedBox(height: 20),
          Text(
            user?.displayName?.trim().isNotEmpty == true
                ? user!.displayName!
                : 'User',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            user?.email ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF60646C),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: isSigningOut ? null : onSwitchProfile,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 28),
              ),
              child: const Text(
                'Switch Profile',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 30),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          _AccountLinkTile(
            icon: Icons.lock_outline_rounded,
            label: 'Security',
            onTap: onSecurity,
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          _AccountLinkTile(
            icon: Icons.help_outline,
            label: 'Help & Support',
            onTap: onHelp,
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 22),
          TextButton(
            onPressed: isSigningOut ? null : onSignOut,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8A8F98),
            ),
            child: isSigningOut
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Sign Out',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AccountLinkTile extends StatelessWidget {
  const _AccountLinkTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: Colors.white,
              child: Icon(icon, size: 22, color: Colors.black),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black, size: 24),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final imageUrl = photoUrl;

    return Container(
      width: 132,
      height: 132,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: ClipOval(
        child: imageUrl == null || imageUrl.isEmpty
            ? const ColoredBox(
                color: Color(0xFFF1F2F4),
                child: Icon(Icons.person, size: 58, color: Color(0xFF6B7280)),
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFFF1F2F4),
                  child: Icon(Icons.person, size: 58, color: Color(0xFF6B7280)),
                ),
              ),
      ),
    );
  }
}
