import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/loan_entry.dart';
import '../providers/notification_prefs_provider.dart';

class NotificationPayloads {
  static const dailyMorning = 'daily_morning';
  static const dailyEvening = 'daily_evening';
  static const loan = 'loan';
}

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  void Function(String? payload)? onNotificationTap;

  static const _morningId = 1001;
  static const _eveningId = 1002;
  static const _loanHour = 8;

  static const _dailyChannel = AndroidNotificationChannel(
    'daily_reminders',
    'Daily reminders',
    description: 'Morning and evening budgeting reminders',
    importance: Importance.high,
  );

  static const _loanChannel = AndroidNotificationChannel(
    'loan_payments',
    'Loan payments',
    description: 'Upcoming and missed loan payment reminders',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  final Set<int> _loanNotificationIds = <int>{};

  static bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> init() async {
    if (_initialized || !isSupported) return;

    tzdata.initializeTimeZones();
    await _configureLocalTimeZone();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: (response) {
        onNotificationTap?.call(response.payload);
      },
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_dailyChannel);
    await androidPlugin?.createNotificationChannel(_loanChannel);

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      onNotificationTap?.call(launch!.notificationResponse?.payload);
    }

    _initialized = true;
  }

  Future<void> requestPermission() async {
    if (!isSupported) return;
    await init();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> syncAll({required List<LoanEntry> loans}) async {
    if (isSupported) {
      await init();
      await _plugin.cancelAll();
      _loanNotificationIds.clear();
    }
    await syncDaily();
    await syncLoans(loans);
  }

  Future<void> syncDaily() async {
    if (!isSupported) return;
    await init();

    await _plugin.cancel(_morningId);
    await _plugin.cancel(_eveningId);

    if (!await NotificationPrefsProvider.readDailyEnabled()) return;

    final morning = await NotificationPrefsProvider.readMorning();
    final evening = await NotificationPrefsProvider.readEvening();

    await _zonedSchedule(
      id: _morningId,
      title: 'Journey to Balance',
      body: "Ready to budget today's expenses?",
      when: _nextClock(morning),
      channel: _dailyChannel,
      payload: NotificationPayloads.dailyMorning,
      match: DateTimeComponents.time,
    );

    await _zonedSchedule(
      id: _eveningId,
      title: 'Journey to Balance',
      body: "Did you finish tracking today's expenses?",
      when: _nextClock(evening),
      channel: _dailyChannel,
      payload: NotificationPayloads.dailyEvening,
      match: DateTimeComponents.time,
    );
  }

  Future<void> syncLoans(List<LoanEntry> loans) async {
    if (!isSupported) return;
    await init();
    await _cancelLoanNotifications();

    if (!await NotificationPrefsProvider.readLoanEnabled()) return;

    for (final loan in loans) {
      if (loan.isFullyPaid) continue;
      final dates = loan.installmentDates;
      if (dates.isEmpty) continue;

      final finalDue = dates.last;
      final next = loan.nextActionableDue;
      if (next == null) continue;

      final nextIsFinal =
          LoanEntry.dayKey(next) == LoanEntry.dayKey(finalDue);
      if (loan.installmentStatus(next) == LoanStatus.late) {
        await _scheduleMissed(loan, next, isFinal: nextIsFinal);
      }

      for (final due in dates) {
        if (loan.isInstallmentPaid(due)) continue;
        if (loan.installmentStatus(due) == LoanStatus.late) continue;
        final isFinal = LoanEntry.dayKey(due) == LoanEntry.dayKey(finalDue);
        await _scheduleBefore(loan, due, isFinal: isFinal);
        await _scheduleDue(loan, due, isFinal: isFinal);
      }
    }
  }

  Future<void> cancelAllReminders() async {
    if (!isSupported) return;
    await init();
    await _plugin.cancelAll();
    _loanNotificationIds.clear();
  }

  Future<void> _scheduleBefore(
    LoanEntry loan,
    DateTime due, {
    required bool isFinal,
  }) async {
    final remindOn = DateTime(
      due.year,
      due.month,
      due.day,
    ).subtract(const Duration(days: 1));
    final when = _atHourOn(remindOn, _loanHour);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;

    await _zonedSchedule(
      id: _loanId('before', loan.id, due),
      title: 'Payment reminder',
      body: isFinal
          ? 'Final ${loan.name} payment is due tomorrow'
          : '${loan.name} payment is due tomorrow',
      when: when,
      channel: _loanChannel,
      payload: NotificationPayloads.loan,
    );
  }

  Future<void> _scheduleDue(
    LoanEntry loan,
    DateTime due, {
    required bool isFinal,
  }) async {
    final dueDay = DateTime(due.year, due.month, due.day);
    final when = _atHourOn(dueDay, _loanHour);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;

    await _zonedSchedule(
      id: _loanId('due', loan.id, due),
      title: 'Payment reminder',
      body: isFinal
          ? 'Ready to pay the final ${loan.name} payment?'
          : 'Ready to pay ${loan.name}?',
      when: when,
      channel: _loanChannel,
      payload: NotificationPayloads.loan,
    );
  }

  Future<void> _scheduleMissed(
    LoanEntry loan,
    DateTime due, {
    required bool isFinal,
  }) async {
    await _zonedSchedule(
      id: _loanId('missed', loan.id, due),
      title: 'Payment reminder',
      body: isFinal
          ? 'Final ${loan.name} payment is still pending'
          : '${loan.name} payment is still pending',
      when: _nextHour(_loanHour),
      channel: _loanChannel,
      payload: NotificationPayloads.loan,
      match: DateTimeComponents.time,
    );
  }

  Future<void> _zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    required AndroidNotificationChannel channel,
    required String payload,
    DateTimeComponents? match,
  }) async {
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
        matchDateTimeComponents: match,
      );
      if (id != _morningId && id != _eveningId) {
        _loanNotificationIds.add(id);
      }
    } catch (_) {}
  }

  Future<void> _cancelLoanNotifications() async {
    for (final id in _loanNotificationIds) {
      await _plugin.cancel(id);
    }
    _loanNotificationIds.clear();
  }

  int _loanId(String stage, String loanId, DateTime due) {
    final key = '$stage|$loanId|${LoanEntry.dayKey(due)}';
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    if (hash == _morningId || hash == _eveningId || hash == 0) {
      hash = (hash + 17) & 0x7fffffff;
    }
    return hash;
  }

  tz.TZDateTime _atHourOn(DateTime day, int hour, [int minute = 0]) {
    return tz.TZDateTime(
      tz.local,
      day.year,
      day.month,
      day.day,
      hour,
      minute,
    );
  }

  tz.TZDateTime _nextHour(int hour, [int minute = 0]) {
    return _nextClock(ReminderClock(hour: hour, minute: minute));
  }

  tz.TZDateTime _nextClock(ReminderClock clock) {
    final now = tz.TZDateTime.now(tz.local);
    final today = DateTime(now.year, now.month, now.day);
    var candidate = _atHourOn(today, clock.hour, clock.minute);
    if (!candidate.isAfter(now)) {
      candidate = _atHourOn(
        today.add(const Duration(days: 1)),
        clock.hour,
        clock.minute,
      );
    }
    return candidate;
  }

  Future<void> _configureLocalTimeZone() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Manila'));
      } catch (_) {
        tz.setLocalLocation(tz.UTC);
      }
    }
  }
}
