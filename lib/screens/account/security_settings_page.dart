import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_lock_provider.dart';
import '../../services/auth_service.dart';
import '../../services/finance_api_service.dart';
import '../../services/security_service.dart';
import '../../services/user_session_cleanup.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/security_ui.dart';
import '../auth/fingerprint_enable_modal.dart';

class SecuritySettingsPage extends StatelessWidget {
  const SecuritySettingsPage({
    super.key,
    this.authService,
    this.financeApiService,
  });

  final AuthService? authService;
  final FinanceApiService? financeApiService;

  Future<void> _changePin(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => withBarrierBlur(
        const _ChangePinSheet(),
        alignment: Alignment.bottomCenter,
      ),
    );

    if (result == null || !context.mounted) return;

    await context.read<AppLockProvider>().changePin(result);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN updated successfully.')),
    );
  }

  Future<void> _toggleBiometric(BuildContext context, bool enable) async {
    final lock = context.read<AppLockProvider>();

    if (enable) {
      if (!lock.biometricsAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fingerprint is not available on this device.'),
          ),
        );
        return;
      }

      final confirmed = await showFingerprintEnableModal(context);
      if (confirmed != true || !context.mounted) return;
      await lock.enableBiometric(true);
      return;
    }

    await lock.enableBiometric(false);
  }

  Future<void> _pickAutoLock(BuildContext context) async {
    final lock = context.read<AppLockProvider>();
    final selected = await showModalBottomSheet<AutoLockOption>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return withBarrierBlur(
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Auto Lock Timer',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ...AutoLockOption.values.map((option) {
                      final isSelected = option == lock.autoLockOption;
                      return ListTile(
                        title: Text(
                          option.label,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded, color: Colors.black)
                            : null,
                        onTap: () => Navigator.pop(context, option),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
          alignment: Alignment.bottomCenter,
        );
      },
    );

    if (selected == null || !context.mounted) return;
    await lock.setAutoLockOption(selected);
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final auth = authService ?? AuthService();
    final finance = financeApiService ?? FinanceApiService();
    final user = auth.currentUser;
    if (user == null || user.email == null || user.email!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete account: No active signed-in user found.'),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => withBarrierBlur(
        _DeleteAccountSheet(
          authService: auth,
          financeApiService: finance,
          user: user,
        ),
        alignment: Alignment.bottomCenter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F2F4),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text(
          'Security',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SecurityCardShell(
            maxWidth: double.infinity,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              children: [
                _SecurityTile(
                  title: 'Change PIN',
                  subtitle: 'Update your 4-digit unlock PIN',
                  onTap: () => _changePin(context),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    title: const Text(
                      'Fingerprint Unlock',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      lock.biometricsAvailable
                          ? 'Use biometrics for faster access'
                          : 'Not available on this device',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    value: lock.biometricEnabled,
                    activeThumbColor: Colors.white,
                    activeTrackColor: Colors.black,
                    onChanged: lock.biometricsAvailable
                        ? (value) => _toggleBiometric(context, value)
                        : null,
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                _SecurityTile(
                  title: 'Auto Lock Timer',
                  subtitle: lock.autoLockOption.label,
                  onTap: () => _pickAutoLock(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SecurityCardShell(
            maxWidth: double.infinity,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: _SecurityTile(
              title: 'Delete Account',
              subtitle: 'Permanently remove your account and all financial data',
              isDestructive: true,
              onTap: () => _deleteAccount(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityTile extends StatelessWidget {
  const _SecurityTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDestructive ? const Color(0xFFDC2626) : Colors.black,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            color: Color(0xFF6B7280),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: isDestructive ? const Color(0xFFDC2626) : Colors.black,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ChangePinSheet extends StatefulWidget {
  const _ChangePinSheet();

  @override
  State<_ChangePinSheet> createState() => _ChangePinSheetState();
}

class _ChangePinSheetState extends State<_ChangePinSheet> {
  String _current = '';
  String _next = '';
  String _confirm = '';
  String? _error;
  bool _busy = false;
  int _clearCurrent = 0;
  int _clearConfirm = 0;

  Future<void> _save() async {
    if (_current.length != 4 || _next.length != 4 || _confirm.length != 4) {
      return;
    }

    if (_next != _confirm) {
      setState(() {
        _error = 'New PINs do not match.';
        _confirm = '';
        _clearConfirm++;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final verified = await context.read<AppLockProvider>().verifyPin(_current);
    if (!verified) {
      setState(() {
        _error = 'Current PIN is incorrect.';
        _current = '';
        _clearCurrent++;
        _busy = false;
      });
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, _next);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Change PIN',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 22),
              LabeledPinField(
                label: 'Current PIN',
                autoFocus: true,
                enabled: !_busy,
                clearTrigger: _clearCurrent,
                hasError: _error != null,
                onChanged: (v) => setState(() {
                  _current = v;
                  if (v.isNotEmpty) _error = null;
                }),
                onCompleted: (v) => setState(() => _current = v),
              ),
              const SizedBox(height: 18),
              LabeledPinField(
                label: 'New PIN',
                enabled: !_busy,
                hasError: _error != null,
                onChanged: (v) => setState(() {
                  _next = v;
                  if (v.isNotEmpty) _error = null;
                }),
                onCompleted: (v) => setState(() => _next = v),
              ),
              const SizedBox(height: 18),
              LabeledPinField(
                label: 'Confirm new PIN',
                enabled: !_busy,
                clearTrigger: _clearConfirm,
                hasError: _error != null,
                onChanged: (v) => setState(() {
                  _confirm = v;
                  if (v.isNotEmpty) _error = null;
                }),
                onCompleted: (v) => setState(() => _confirm = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFE11D48),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SecurityActionButton(
                label: 'Save',
                isLoading: _busy,
                onPressed:
                    _current.length == 4 &&
                        _next.length == 4 &&
                        _confirm.length == 4 &&
                        !_busy
                    ? _save
                    : null,
              ),
              SecurityActionButton(
                label: 'Cancel',
                isPrimary: false,
                onPressed: _busy ? null : () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteAccountSheet extends StatefulWidget {
  const _DeleteAccountSheet({
    required this.authService,
    required this.financeApiService,
    required this.user,
  });

  final AuthService authService;
  final FinanceApiService financeApiService;
  final User user;

  @override
  State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isEmailMatching {
    final expected = (widget.user.email ?? '').trim().toLowerCase();
    final entered = _emailController.text.trim().toLowerCase();
    return expected.isNotEmpty && entered == expected;
  }

  bool get _canSubmit {
    if (_busy || !_isEmailMatching) return false;
    if (widget.authService.usesPasswordProvider) {
      return _passwordController.text.isNotEmpty;
    }
    return true;
  }

  Future<void> _performDeletion() async {
    if (!_canSubmit) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // 1. Fresh reauthentication
      if (widget.authService.usesPasswordProvider) {
        await widget.authService.reauthenticateWithPassword(
          _passwordController.text,
        );
      } else {
        await widget.authService.reauthenticateWithGoogle();
      }

      // 2. Call Worker backend deletion endpoint with confirmation email
      await widget.financeApiService.deleteAccount(
        confirmationEmail: _emailController.text.trim(),
      );

      // 3. Clear local session, secure storage, and sign out
      if (!mounted) return;
      await clearUserSession(context);
      await SecurityService().clearAllForUser(widget.user.uid);
      await widget.authService.signOut();

      if (!mounted) return;
      Navigator.pop(context);
      Navigator.of(context).popUntil((route) => route.isFirst);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your account and all associated data have been permanently deleted.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e is FirebaseAuthException) {
          _error = friendlyAuthError(e);
        } else if (e is FinanceApiException) {
          _error = e.message;
        } else {
          _error = 'Failed to delete account. Please try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final registeredEmail = widget.user.email ?? '';

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEE2E2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFDC2626),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Delete Account',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF121212),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'This action is permanent and cannot be undone. All your budget data, transaction history, wallet items, and settings will be permanently erased.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  color: Color(0xFF4B5563),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'To confirm, type your registered email address ($registeredEmail):',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('delete-account-email-field'),
                controller: _emailController,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'Enter your email',
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF121212),
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (widget.authService.usesPasswordProvider) ...[
                const SizedBox(height: 14),
                const Text(
                  'Enter your password to verify identity:',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('delete-account-password-field'),
                  controller: _passwordController,
                  enabled: !_busy,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF121212),
                        width: 1.5,
                      ),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ] else ...[
                const SizedBox(height: 14),
                const Text(
                  'You will be prompted to reauthenticate with Google before your account is deleted.',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: const ValueKey('delete-account-confirm-button'),
                  onPressed: _canSubmit ? _performDeletion : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFFCA5A5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          widget.authService.usesPasswordProvider
                              ? 'Permanently Delete Account'
                              : 'Verify with Google & Delete',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4B5563),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
