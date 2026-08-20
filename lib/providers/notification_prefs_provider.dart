import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ReminderClock {
  const ReminderClock({required this.hour, required this.minute});

  final int hour;
  final int minute;

  static const morningDefault = ReminderClock(hour: 8, minute: 0);
  static const eveningDefault = ReminderClock(hour: 20, minute: 0);

  int get minutesSinceMidnight => hour * 60 + minute;

  String get label {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  factory ReminderClock.fromMinutes(int? minutes, ReminderClock fallback) {
    if (minutes == null) return fallback;
    final clamped = minutes.clamp(0, 24 * 60 - 1);
    return ReminderClock(hour: clamped ~/ 60, minute: clamped % 60);
  }
}

class NotificationPrefsProvider extends ChangeNotifier {
  NotificationPrefsProvider({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const dailyKey = 'notif_daily_enabled';
  static const loanKey = 'notif_loan_enabled';
  static const morningMinutesKey = 'notif_morning_minutes';
  static const eveningMinutesKey = 'notif_evening_minutes';

  final FlutterSecureStorage _storage;

  bool _dailyEnabled = true;
  bool _loanEnabled = true;
  ReminderClock _morning = ReminderClock.morningDefault;
  ReminderClock _evening = ReminderClock.eveningDefault;
  bool _loaded = false;

  bool get dailyEnabled => _dailyEnabled;
  bool get loanEnabled => _loanEnabled;
  ReminderClock get morning => _morning;
  ReminderClock get evening => _evening;
  bool get isLoaded => _loaded;

  static Future<bool> readDailyEnabled({
    FlutterSecureStorage? storage,
  }) async {
    return _readBool(
      storage ?? const FlutterSecureStorage(),
      dailyKey,
      fallback: true,
    );
  }

  static Future<bool> readLoanEnabled({
    FlutterSecureStorage? storage,
  }) async {
    return _readBool(
      storage ?? const FlutterSecureStorage(),
      loanKey,
      fallback: true,
    );
  }

  static Future<ReminderClock> readMorning({
    FlutterSecureStorage? storage,
  }) {
    return _readClock(
      storage ?? const FlutterSecureStorage(),
      morningMinutesKey,
      ReminderClock.morningDefault,
    );
  }

  static Future<ReminderClock> readEvening({
    FlutterSecureStorage? storage,
  }) {
    return _readClock(
      storage ?? const FlutterSecureStorage(),
      eveningMinutesKey,
      ReminderClock.eveningDefault,
    );
  }

  static Future<bool> _readBool(
    FlutterSecureStorage storage,
    String key, {
    required bool fallback,
  }) async {
    try {
      final raw = await storage.read(key: key);
      if (raw == null) return fallback;
      return raw != '0';
    } catch (_) {
      return fallback;
    }
  }

  static Future<ReminderClock> _readClock(
    FlutterSecureStorage storage,
    String key,
    ReminderClock fallback,
  ) async {
    try {
      final raw = await storage.read(key: key);
      if (raw == null) return fallback;
      return ReminderClock.fromMinutes(int.tryParse(raw), fallback);
    } catch (_) {
      return fallback;
    }
  }

  Future<void> load() async {
    _dailyEnabled = await readDailyEnabled(storage: _storage);
    _loanEnabled = await readLoanEnabled(storage: _storage);
    _morning = await readMorning(storage: _storage);
    _evening = await readEvening(storage: _storage);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDailyEnabled(bool value) async {
    if (_dailyEnabled == value) return;
    _dailyEnabled = value;
    notifyListeners();
    await _write(dailyKey, value ? '1' : '0');
  }

  Future<void> setLoanEnabled(bool value) async {
    if (_loanEnabled == value) return;
    _loanEnabled = value;
    notifyListeners();
    await _write(loanKey, value ? '1' : '0');
  }

  Future<void> setMorning(ReminderClock value) async {
    if (_morning.minutesSinceMidnight == value.minutesSinceMidnight) return;
    _morning = value;
    notifyListeners();
    await _write(morningMinutesKey, '${value.minutesSinceMidnight}');
  }

  Future<void> setEvening(ReminderClock value) async {
    if (_evening.minutesSinceMidnight == value.minutesSinceMidnight) return;
    _evening = value;
    notifyListeners();
    await _write(eveningMinutesKey, '${value.minutesSinceMidnight}');
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }
}
