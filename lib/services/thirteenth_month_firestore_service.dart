import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Saved 13th Month Pay calculator inputs.
class ThirteenthMonthInputs {
  const ThirteenthMonthInputs({
    required this.monthlySalaries,
    required this.otherBenefits,
  });

  final List<double> monthlySalaries;
  final double otherBenefits;
}

/// Reads stored calculator inputs leniently. Returns null when [raw] holds
/// nothing usable. A missing or malformed salary list becomes 12 zeros, and
/// salaries that are present are kept (extra entries ignored, short lists
/// padded), so a partially damaged record still shows what it has.
@visibleForTesting
ThirteenthMonthInputs? parseThirteenthMonthInputs(Object? raw) {
  if (raw is! Map) return null;
  double? money(Object? value) {
    if (value is! num) return null;
    final amount = value.toDouble();
    return amount.isFinite && amount >= 0 ? amount : null;
  }

  final rawSalaries = raw['monthlyBasicSalaries'];
  final rawBenefits = money(raw['otherBenefits']);
  List<double>? salaries;
  if (rawSalaries is List) {
    salaries = [
      for (var i = 0; i < 12; i++)
        i < rawSalaries.length ? money(rawSalaries[i]) ?? 0 : 0,
    ];
  }
  if (salaries == null && rawBenefits == null) return null;
  return ThirteenthMonthInputs(
    monthlySalaries: salaries ?? List<double>.filled(12, 0),
    otherBenefits: rawBenefits ?? 0,
  );
}

/// The full calculator document written on save. Exactly the fields the
/// Firestore rules allow for users/{uid}/calculators/thirteenthMonth.
@visibleForTesting
Map<String, Object?> thirteenthMonthDocData({
  required List<double> monthlySalaries,
  required double otherBenefits,
  required int year,
}) {
  if (monthlySalaries.length != 12) {
    throw ArgumentError('Exactly 12 monthly salaries are required.');
  }
  return {
    'year': year,
    'monthlyBasicSalaries': List<double>.from(monthlySalaries),
    'otherBenefits': otherBenefits,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Stores 13th Month Pay calculator inputs in their own document,
/// users/{uid}/calculators/thirteenthMonth, separate from the Budget Planner.
///
/// Older app versions kept these inputs in users/{uid}.planner.thirteenthMonth.
/// That copy is read only as a fallback when the new document does not exist
/// yet, and is never written or deleted here.
class ThirteenthMonthFirestoreService {
  ThirteenthMonthFirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _firestore.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _user(uid).collection('calculators').doc('thirteenthMonth');

  Future<ThirteenthMonthInputs?> load(String uid) async {
    final snapshot = await _doc(uid).get();
    if (snapshot.exists) {
      final current = parseThirteenthMonthInputs(snapshot.data());
      if (current != null) return current;
    }
    final legacy = await _user(uid).get();
    final planner = legacy.data()?['planner'];
    return parseThirteenthMonthInputs(
      planner is Map ? planner['thirteenthMonth'] : null,
    );
  }

  /// Replaces the calculator document. Never touches users/{uid}.
  Future<void> save(
    String uid, {
    required List<double> monthlySalaries,
    required double otherBenefits,
  }) {
    return _doc(uid).set(
      thirteenthMonthDocData(
        monthlySalaries: monthlySalaries,
        otherBenefits: otherBenefits,
        year: DateTime.now().year,
      ),
    );
  }
}
