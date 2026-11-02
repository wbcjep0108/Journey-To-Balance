import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/onboarding_state.dart';

class OnboardingService {
  OnboardingService({
    FirebaseFirestore? firestore,
    FlutterSecureStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? const FlutterSecureStorage();

  final FirebaseFirestore _firestore;
  final FlutterSecureStorage _storage;

  DocumentReference<Map<String, dynamic>> _record(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('wallet')
      .doc('onboarding');

  String _draftKey(String uid) => 'onboarding_draft_$uid';

  Future<OnboardingRecord?> loadRecord(String uid) async {
    final snapshot = await _record(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    final rawStatus = data['status'] as String?;
    final status = switch (rawStatus) {
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
    return _record(uid).set({
      'status': status.name,
      'completedAt': FieldValue.serverTimestamp(),
      'step': step,
    });
  }
}
