import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/assessment_result_model.dart';
import 'firebase_service.dart';

class AssessmentStorageService {
  AssessmentStorageService._internal();
  static final AssessmentStorageService instance = AssessmentStorageService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String _currentUserPath() {
    if (!Firebase.apps.isNotEmpty) {
      throw Exception('Firebase is not initialized');
    }
    final uid = FirebaseService().uid;
    if (uid == null) throw Exception('User not authenticated');
    return 'users/$uid';
  }

  Future<void> saveAssessment(AssessmentResult result) async {
    final base = _currentUserPath();
    await _firestore
        .collection('$base/players/${result.playerId}/assessments')
        .doc(result.id.isEmpty ? null : result.id)
        .set(result.toMap(), SetOptions(merge: true));
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
