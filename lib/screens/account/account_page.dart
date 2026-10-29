import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../providers/app_lock_provider.dart';
import '../../providers/budget_provider.dart';
import '../../providers/currency_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/journey_about_dialog.dart';
import '../../widgets/journey_help_dialog.dart';
import 'currency_settings_page.dart';
import 'notification_settings_page.dart';
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
  bool _isResendingVerification = false;

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

  Future<void> _resendVerification() async {
    if (_isResendingVerification) return;
    setState(() => _isResendingVerification = true);
    try {
      await AuthService().resendVerificationEmail();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Verification email sent.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send the email. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isResendingVerification = false);
    }
  }

  void _openCurrency() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CurrencySettingsPage()),
    );
  }

  void _openSecurity() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SecuritySettingsPage()),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationSettingsPage(),
      ),
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
      builder: (context) => withBarrierBlur(
        const JourneyHelpDialog(),
      ),
    );
  }

  Future<void> _openAbout() async {
    final callback = widget.onAbout;
    if (callback != null) {
      callback();
      return;
    }

    var version = '3.0.0';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (_) => withBarrierBlur(
        JourneyAboutDialog(version: version),
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
              if (user != null && !user.emailVerified) ...[
                _VerificationBanner(
                  isSending: _isResendingVerification,
                  onResend: _resendVerification,
                ),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _AccountCard(
                        user: user,
                        isSigningOut: _isSigningOut,
                        currencyLabel: context.watch<CurrencyProvider>().code,
                        onSwitchProfile: _signOut,
                        onCurrency: _openCurrency,
                        onSecurity: _openSecurity,
                        onNotifications: _openNotifications,
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
                child: const Text('About Journey to Balance'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({required this.isSending, required this.onResend});

  final bool isSending;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Verify your email',
              style: TextStyle(
                color: Color(0xFF25282D),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: isSending ? null : onResend,
            child: isSending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Resend'),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.user,
    required this.isSigningOut,
    required this.currencyLabel,
    required this.onSwitchProfile,
    required this.onCurrency,
    required this.onSecurity,
    required this.onNotifications,
    required this.onHelp,
    required this.onSignOut,
  });

  final User? user;
  final bool isSigningOut;
  final String currencyLabel;
  final VoidCallback onSwitchProfile;
  final VoidCallback onCurrency;
  final VoidCallback onSecurity;
  final VoidCallback onNotifications;
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
            icon: Icons.attach_money_rounded,
            label: 'Currency',
            trailingLabel: currencyLabel,
            onTap: onCurrency,
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          _AccountLinkTile(
            icon: Icons.lock_outline_rounded,
            label: 'Security',
            onTap: onSecurity,
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          _AccountLinkTile(
            icon: Icons.notifications_none_rounded,
            label: 'Notifications',
            onTap: onNotifications,
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
    this.trailingLabel,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailingLabel;

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
            if (trailingLabel != null) ...[
              Text(
                trailingLabel!,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
            ],
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
