import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_lock_provider.dart';
import '../../services/security_service.dart';
import '../../widgets/barrier_blur.dart';
import '../../widgets/security_ui.dart';
import '../auth/fingerprint_enable_modal.dart';

class SecuritySettingsPage extends StatelessWidget {
  const SecuritySettingsPage({super.key});

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
                SwitchListTile(
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
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                _SecurityTile(
                  title: 'Auto Lock Timer',
                  subtitle: lock.autoLockOption.label,
                  onTap: () => _pickAutoLock(context),
                ),
              ],
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
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w700,
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
      trailing: const Icon(Icons.chevron_right, color: Colors.black),
      onTap: onTap,
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
