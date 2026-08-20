import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/loan_provider.dart';
import '../../providers/notification_prefs_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/security_ui.dart';

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});

  Future<void> _setDaily(BuildContext context, bool value) async {
    await context.read<NotificationPrefsProvider>().setDailyEnabled(value);
    if (!context.mounted) return;
    await NotificationService.instance.syncDaily();
  }

  Future<void> _setLoan(BuildContext context, bool value) async {
    await context.read<NotificationPrefsProvider>().setLoanEnabled(value);
    if (!context.mounted) return;
    await NotificationService.instance.syncLoans(
      context.read<LoanProvider>().loans,
    );
  }

  Future<void> _pickTime({
    required BuildContext context,
    required ReminderClock current,
    required Future<void> Function(ReminderClock) onSave,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !context.mounted) return;
    await onSave(ReminderClock(hour: picked.hour, minute: picked.minute));
    if (!context.mounted) return;
    await NotificationService.instance.syncDaily();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<NotificationPrefsProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF1F2F4),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text(
          'Notifications',
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
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: const Text(
                    'Daily reminders',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${prefs.morning.label} check-in and ${prefs.evening.label} wrap-up',
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  value: prefs.dailyEnabled,
                  activeThumbColor: Colors.white,
                  activeTrackColor: Colors.black,
                  onChanged: (value) => _setDaily(context, value),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                _TimeTile(
                  title: 'Morning time',
                  subtitle: 'Ask if you are ready to budget',
                  timeLabel: prefs.morning.label,
                  enabled: prefs.dailyEnabled,
                  onTap: () => _pickTime(
                    context: context,
                    current: prefs.morning,
                    onSave: context.read<NotificationPrefsProvider>().setMorning,
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                _TimeTile(
                  title: 'Evening time',
                  subtitle: 'Ask if you finished tracking',
                  timeLabel: prefs.evening.label,
                  enabled: prefs.dailyEnabled,
                  onTap: () => _pickTime(
                    context: context,
                    current: prefs.evening,
                    onSave: context.read<NotificationPrefsProvider>().setEvening,
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE5E7EB)),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: const Text(
                    'Loan payment reminders',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Day before, due date, and missed monthly or final payments',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  value: prefs.loanEnabled,
                  activeThumbColor: Colors.white,
                  activeTrackColor: Colors.black,
                  onChanged: (value) => _setLoan(context, value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String timeLabel;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
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
      trailing: Text(
        timeLabel,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: enabled ? Colors.black : const Color(0xFF9CA3AF),
        ),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}
