import 'package:cloud_firestore/cloud_firestore.dart';

/// The current consent revision. Bump this when either legal document changes.
const currentLegalVersion = '2026-10-29-v3';

String legalVersionDateLabel([String version = currentLegalVersion]) {
  final date = DateTime.tryParse(
    version.length >= 10 ? version.substring(0, 10) : version,
  );
  if (date == null) return version;
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

abstract class LegalAcceptanceStore {
  Future<bool> exists({required String userId, required String documentId});

  Future<void> create({
    required String userId,
    required String documentId,
    required String termsVersion,
    required String privacyVersion,
  });
}

class FirestoreLegalAcceptanceStore implements LegalAcceptanceStore {
  FirestoreLegalAcceptanceStore({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _document(
    String userId,
    String documentId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('legal')
        .doc(documentId);
  }

  @override
  Future<bool> exists({
    required String userId,
    required String documentId,
  }) async {
    return (await _document(userId, documentId).get()).exists;
  }

  @override
  Future<void> create({
    required String userId,
    required String documentId,
    required String termsVersion,
    required String privacyVersion,
  }) {
    return _document(userId, documentId).set({
      'termsAcceptedAt': FieldValue.serverTimestamp(),
      'termsVersion': termsVersion,
      'privacyVersion': privacyVersion,
    });
  }
}

class LegalAcceptanceService {
  LegalAcceptanceService({LegalAcceptanceStore? store})
    : _store = store ?? FirestoreLegalAcceptanceStore();

  final LegalAcceptanceStore _store;

  static final Set<String> _acknowledgedThisSession = <String>{};

  String get documentId => 'acceptance_$currentLegalVersion';

  void markAcknowledgedThisSession(String userId) {
    _acknowledgedThisSession.add(userId);
  }

  bool isAcknowledgedThisSession(String userId) {
    return _acknowledgedThisSession.contains(userId);
  }

  Future<bool> hasCurrentAcceptance(String userId) {
    return _store.exists(userId: userId, documentId: documentId);
  }

  /// Returns false on an unavailable/denied write so authentication can proceed.
  /// A later app start checks again and offers the current consent screen.
  Future<bool> acceptCurrentVersion(String userId) async {
    markAcknowledgedThisSession(userId);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (await hasCurrentAcceptance(userId)) return true;
        await _store.create(
          userId: userId,
          documentId: documentId,
          termsVersion: currentLegalVersion,
          privacyVersion: currentLegalVersion,
        );
        return true;
      } catch (_) {
        // Keep this non-sensitive: do not log a UID, email, or exception body.
        // The next attempt/app launch performs another existence check.
        // ignore: avoid_print
        print('Legal acceptance could not be saved; it will be retried later.');
      }
    }
    return false;
  }
}
