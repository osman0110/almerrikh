import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../utils/app_logger.dart';

class FirebaseService {
  // Singleton instance to persist cache throughout the app lifecycle
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseFunctions get _functions => FirebaseFunctions.instance;

  bool get isInitialized => Firebase.apps.isNotEmpty;
  String? get uid => isInitialized ? _auth.currentUser?.uid : null;

  // Caching mechanism
  String? _cachedUid;
  Map<String, dynamic>? _cachedPlan;
  bool _hasFetchedPlan = false;
  StreamController<Map<String, dynamic>?>? _planController;
  StreamSubscription? _firestoreSub;

  // --- دوال المصادقة (Authentication) ---

  Future<UserCredential> signInWithEmail(String email, String password) async {
    if (!isInitialized) {
      throw Exception('Firebase is not initialized');
    }
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      AppLogger.e('FirebaseService.signIn', 'Auth failed', e);
      rethrow;
    }
  }

  Future<UserCredential> signUpWithEmail(String email, String password) async {
    if (!isInitialized) {
      throw Exception('Firebase is not initialized');
    }
    try {
      return await _auth.createUserWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      AppLogger.e('FirebaseService.signUp', 'Auth failed', e);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _firestoreSub?.cancel();
    _firestoreSub = null;
    await _planController?.close();
    _planController = null;
    _cachedPlan = null;
    _hasFetchedPlan = false;
    _cachedUid = null;
    if (!isInitialized) return;
    try {
      await _auth.signOut();
    } catch (e) {
      // Best-effort — the app-level logout (token clear + redirect to /auth)
      // must proceed even if Firebase itself fails to sign out.
      AppLogger.w('FirebaseService.signOut', 'Firebase signOut failed (${e.runtimeType})');
    }
  }

  Future<void> saveProfileAndGeneratePlan(Map<String, dynamic> profileData) async {
    if (uid == null || !isInitialized) {
      AppLogger.w('FirebaseService.saveProfile', 'Firebase disabled or not authenticated — skipped');
      return;
    }
    try {
      profileData['onboardingCompleted'] = true;
      profileData['createdAt'] = FieldValue.serverTimestamp();
      profileData['updatedAt'] = FieldValue.serverTimestamp();
      profileData['xp'] = 0;
      profileData['streak'] = 0;

      await _firestore.collection('users').doc(uid).set(profileData, SetOptions(merge: true));

      final HttpsCallable callable = _functions.httpsCallable('generateWeeklyPlan');
      await callable.call({'trainingPath': profileData['trainingPath']});
    } catch (e) {
      AppLogger.e('FirebaseService.saveProfile', 'Failed', e);
      rethrow;
    }
  }

  Future<void> adjustNextWeekPlan(String previousPlanId) async {
    if (!isInitialized) {
      AppLogger.w('FirebaseService.adjustNextWeekPlan', 'Firebase disabled — skipped');
      return;
    }
    try {
      final HttpsCallable callable = _functions.httpsCallable('adjustNextWeekPlan');
      await callable.call({'previousPlanId': previousPlanId});
    } catch (e) {
      AppLogger.e('FirebaseService.adjustNextWeekPlan', 'Failed', e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> submitSessionResult({
    required String planId,
    required String drillId,
    required double accuracy,
    required double speed,
    required double agility,
    required double balance,
    required int calories,
    required int reps,
    required int durationMinutes,
  }) async {
    if (!isInitialized) {
      AppLogger.w('FirebaseService.submitSessionResult', 'Firebase disabled — returning mock');
      return {
        'success': true,
        'earnedXp': (accuracy * 2).round(),
        'leveledUp': false,
      };
    }
    try {
      final HttpsCallable callable = _functions.httpsCallable('submitSessionResult');
      final result = await callable.call({
        'planId': planId, 'drillId': drillId, 'accuracy': accuracy,
        'speed': speed, 'agility': agility, 'balance': balance,
        'calories': calories, 'reps': reps, 'durationMinutes': durationMinutes,
      });
      return Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      AppLogger.e('FirebaseService.submitSessionResult', 'Failed', e);
      rethrow;
    }
  }

  Stream<Map<String, dynamic>?> streamLatestPlan() async* {
    if (!isInitialized) {
      yield null;
      return;
    }
    final currentUid = uid;
    if (currentUid == null) {
      yield null;
      return;
    }

    // Reset cache if the signed-in user has changed
    if (_cachedUid != currentUid) {
      _cachedPlan = null;
      _hasFetchedPlan = false;
      _cachedUid = currentUid;

      await _firestoreSub?.cancel();
      _firestoreSub = null;

      await _planController?.close();
      _planController = null;
    }

    // 1. Yield immediately from in-memory cache for instant UI load
    if (_hasFetchedPlan) {
      yield _cachedPlan;
    }

    // 2. Initialize a persistent Firestore listener if not already active
    if (_planController == null) {
      _planController = StreamController<Map<String, dynamic>?>.broadcast();

      _firestoreSub = _firestore
          .collection('users')
          .doc(currentUid)
          .collection('plans')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots()
          .listen((snapshot) {
        _hasFetchedPlan = true;
        _cachedPlan = snapshot.docs.isEmpty ? null : {'id': snapshot.docs.first.id, ...snapshot.docs.first.data()};
        _planController?.add(_cachedPlan);
      }, onError: (error) {
        _planController?.addError(error);
      });
    }

    // 3. Yield all subsequent updates
    yield* _planController!.stream;
  }
}