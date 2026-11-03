import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/onboarding_state.dart';

abstract interface class OnboardingPersistence {
  Future<OnboardingRecord?> loadRecord(String uid);
  Future<bool> createPendingIfAbsent(String uid);
  Future<void> writeStatus(
    String uid,
    OnboardingStatus status, {
    required int step,
  });
}

abstract interface class OnboardingRetryStore {
  Future<bool> hasPendingRetry(String uid);
  Future<void> setPendingRetry(String uid, bool pending);
}

bool shouldCreatePendingOnboarding({
  required bool emailAccountCreated,
  bool? googleIsNewUser,
}) {
  return emailAccountCreated || googleIsNewUser == true;
}

class OnboardingService {
  OnboardingService({
    FirebaseFirestore? firestore,
    FlutterSecureStorage? storage,
    OnboardingPersistence? persistence,
    OnboardingRetryStore? retryStore,
  }) : _persistence =
           persistence ??
           FirestoreOnboardingPersistence(
             firestore: firestore ?? FirebaseFirestore.instance,
           ),
       _retryStore =
           retryStore ??
           SecureOnboardingRetryStore(
             storage: storage ?? const FlutterSecureStorage(),
           ),
       _storage = storage ?? const FlutterSecureStorage();

  static const pendingRetryWindow = Duration(hours: 24);

  final OnboardingPersistence _persistence;
  final OnboardingRetryStore _retryStore;
  final FlutterSecureStorage _storage;
  final Set<String> _pendingRetries = <String>{};

  String _draftKey(String uid) => 'onboarding_draft_$uid';

  Future<OnboardingRecord?> loadRecord(String uid) =>
      _persistence.loadRecord(uid);

  Future<void> markNewUser(String uid) async {
    if (uid.isEmpty) return;
    _pendingRetries.add(uid);
    try {
      await _retryStore.setPendingRetry(uid, true);
    } catch (_) {}
    await _createPendingWithRetry(uid);
  }

  Future<void> retryPendingForRecentUser(
    String uid,
    DateTime? creationTime, {
    DateTime? now,
  }) async {
    if (uid.isEmpty || creationTime == null) return;

    final age = (now ?? DateTime.now()).difference(creationTime);
    if (age.isNegative || age > pendingRetryWindow) {
      await _clearPendingRetry(uid);
      return;
    }

    var shouldRetry = _pendingRetries.contains(uid);
    if (!shouldRetry) {
      try {
        shouldRetry = await _retryStore.hasPendingRetry(uid);
      } catch (_) {
        return;
      }
    }
    if (shouldRetry) await _createPendingWithRetry(uid);
  }

  Future<void> _createPendingWithRetry(String uid) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _persistence.createPendingIfAbsent(uid);
        await _clearPendingRetry(uid);
        return;
      } catch (_) {
        if (attempt == 1) return;
      }
    }
  }

  Future<void> _clearPendingRetry(String uid) async {
    _pendingRetries.remove(uid);
    try {
      await _retryStore.setPendingRetry(uid, false);
    } catch (_) {}
  }

  Future<OnboardingDraft?> loadDraft(String uid) async {
    try {
      final raw = await _storage.read(key: _draftKey(uid));
      if (raw == null || raw.isEmpty) return null;
      return OnboardingDraft.decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDraft(String uid, OnboardingDraft draft) {
    return _storage.write(key: _draftKey(uid), value: draft.encode());
  }

  Future<void> clearDraft(String uid) {
    return _storage.delete(key: _draftKey(uid));
  }

  Future<void> complete(String uid, {required int step}) async {
    await _writeStatus(uid, OnboardingStatus.completed, step: step);
    await clearDraft(uid);
  }

  Future<void> dismiss(String uid, {required int step}) async {
    await _writeStatus(uid, OnboardingStatus.dismissed, step: step);
    await clearDraft(uid);
  }

  Future<void> _writeStatus(
    String uid,
    OnboardingStatus status, {
    required int step,
  }) {
    return _persistence.writeStatus(uid, status, step: step);
  }
}

class FirestoreOnboardingPersistence implements OnboardingPersistence {
  FirestoreOnboardingPersistence({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _record(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('wallet')
      .doc('onboarding');

  @override
  Future<OnboardingRecord?> loadRecord(String uid) async {
    final snapshot = await _record(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    final status = switch (data['status'] as String?) {
      'pending' => OnboardingStatus.pending,
      'completed' => OnboardingStatus.completed,
      'dismissed' => OnboardingStatus.dismissed,
      _ => null,
    };
    if (status == null) return null;
    return OnboardingRecord(
      status: status,
      step: (data['step'] as num?)?.toInt(),
    );
  }

  @override
  Future<bool> createPendingIfAbsent(String uid) {
    return _firestore.runTransaction((transaction) async {
      final reference = _record(uid);
      final snapshot = await transaction.get(reference);
      if (snapshot.exists) return false;
      transaction.set(reference, {
        'status': OnboardingStatus.pending.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  @override
  Future<void> writeStatus(
    String uid,
    OnboardingStatus status, {
    required int step,
  }) {
    return _record(uid).set({
      'status': status.name,
      'completedAt': FieldValue.serverTimestamp(),
      'step': step,
    });
  }
}

class SecureOnboardingRetryStore implements OnboardingRetryStore {
  SecureOnboardingRetryStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(String uid) => 'onboarding_pending_retry_$uid';

  @override
  Future<bool> hasPendingRetry(String uid) async {
    return await _storage.read(key: _key(uid)) == 'true';
  }

  @override
  Future<void> setPendingRetry(String uid, bool pending) {
    if (pending) {
      return _storage.write(key: _key(uid), value: 'true');
    }
    return _storage.delete(key: _key(uid));
  }
}
