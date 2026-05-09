import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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
      debugPrint('Login Error: $e');
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
      debugPrint('SignUp Error: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> saveProfileAndGeneratePlan(Map<String, dynamic> profileData) async {
    if (uid == null) throw Exception('User not authenticated');
    
    if (!isInitialized) {
      throw Exception('Firebase is not initialized');
    }
    try {
      // 1. Save profile to Firestore
      profileData['onboardingCompleted'] = true;
      profileData['createdAt'] = FieldValue.serverTimestamp();
      profileData['updatedAt'] = FieldValue.serverTimestamp();
      profileData['xp'] = 0;
      profileData['streak'] = 0;
      
      await _firestore.collection('users').doc(uid).set(profileData, SetOptions(merge: true));

      // 2. Call Cloud Function to generate AI Plan
      final HttpsCallable callable = _functions.httpsCallable('generateWeeklyPlan');
      await callable.call({'trainingPath': profileData['trainingPath']});
      
    } catch (e) {
      debugPrint('Error generating plan: $e');
      rethrow;
    }
  }

  Future<void> adjustNextWeekPlan(String previousPlanId) async {
    try {
      final HttpsCallable callable = _functions.httpsCallable('adjustNextWeekPlan');
      await callable.call({'previousPlanId': previousPlanId});
    } catch (e) {
      debugPrint('Error adjusting next week plan: $e');
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
    try {
      final HttpsCallable callable = _functions.httpsCallable('submitSessionResult');
      final result = await callable.call({
        'planId': planId, 'drillId': drillId, 'accuracy': accuracy,
        'speed': speed, 'agility': agility, 'balance': balance,
        'calories': calories, 'reps': reps, 'durationMinutes': durationMinutes,
      });
      return Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      debugPrint('Error submitting session result: $e');
      rethrow;
    }
  }

  Stream<Map<String, dynamic>?> streamLatestPlan() async* {
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