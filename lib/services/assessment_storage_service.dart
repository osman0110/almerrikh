import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../models/assessment_result_model.dart';
import '../api_service.dart';
import 'firebase_service.dart';

class AssessmentStorageService {
  AssessmentStorageService._internal();
  static final AssessmentStorageService instance = AssessmentStorageService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String? _currentUserPath() {
    if (!Firebase.apps.isNotEmpty) {
      return null;
    }
    final uid = FirebaseService().uid;
    if (uid == null) return null;
    return 'users/$uid';
  }

  Future<void> saveAssessment(AssessmentResult result) async {
    // 1. Save to Firebase (primary store)
    final base = _currentUserPath();
    if (base == null) {
      debugPrint('Firebase disabled, skipping saveAssessment');
    } else {
      await _firestore
          .collection('$base/players/${result.playerId}/assessments')
          .doc(result.id.isEmpty ? null : result.id)
          .set(result.toMap(), SetOptions(merge: true));
    }

    // 2. Sync to nextkick.me (fire-and-forget — does not block if offline)
    if (ApiService.token != null) {
      ApiService.saveAssessment(
        id: result.id,
        playerId: result.playerId,
        playerName: result.playerName,
        type: result.testType.id,
        overallScore: result.overallScore,
        movementQualityScore: result.movementQualityScore,
        stabilityScore: result.stabilityScore,
        symmetryScore: result.symmetryScore,
        controlScore: result.controlScore,
        qualityScore: result.qualityScore,
        issues: result.issues,
        correctionTips: result.correctionTips,
        recommendedDrills: result.recommendedDrills,
        angleMetrics: result.angleMetrics,
        coachNotes: result.coachNotes,
      ).then((r) {
        if (r.containsKey('error') && r['error'] != 'sync_failed') {
          debugPrint('nextkick.me assessment sync: ${r['error']}');
        }
      }).catchError((_) {});
    }
  }

  Stream<List<AssessmentResult>> streamAssessments(String playerId) {
    if (!Firebase.apps.isNotEmpty) {
      return Stream.value([]);
    }
    final base = _currentUserPath();
    return _firestore
        .collection('$base/players/$playerId/assessments')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => AssessmentResult.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  Future<AssessmentResult?> getLatestAssessment(String playerId) async {
    final base = _currentUserPath();
    if (base == null) return null;
    final query = await _firestore
        .collection('$base/players/$playerId/assessments')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    return AssessmentResult.fromMap(doc.id, doc.data());
  }
}
