import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/club_models.dart';

/// All Firestore CRUD for club management.
/// Collection layout:
///   clubs/{clubId}/teams/{teamId}
///   clubs/{clubId}/players/{playerId}
///   clubs/{clubId}/sessions/{sessionId}
///   clubs/{clubId}/assessments/{assessmentId}
///   clubs/{clubId}/players/{playerId}/notes/{noteId}
class ClubService {
  static final ClubService _i = ClubService._();
  factory ClubService() => _i;
  ClubService._();

  static const _clubId = 'al_merrikh_sc';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _teams =>
      _db.collection('clubs').doc(_clubId).collection('teams');

  CollectionReference<Map<String, dynamic>> get _players =>
      _db.collection('clubs').doc(_clubId).collection('players');

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('clubs').doc(_clubId).collection('sessions');

  CollectionReference<Map<String, dynamic>> get _assessments =>
      _db.collection('clubs').doc(_clubId).collection('assessments');

  // ── Teams ──────────────────────────────────────────────────────────────────

  Stream<List<ClubTeam>> teamsStream() => _teams
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map((s) => s.docs.map((d) => ClubTeam.fromMap(d.id, d.data())).toList());

  Future<List<ClubTeam>> getTeams() async {
    try {
      final start = DateTime.now();
      final snap = await _teams.orderBy('createdAt').get();
      final ms = DateTime.now().difference(start).inMilliseconds;
      debugPrint('[Firestore] getTeams: ${snap.docs.length} teams in ${ms}ms');
      return snap.docs.map((d) => ClubTeam.fromMap(d.id, d.data())).toList();
    } catch (e) {
      debugPrint('ClubService.getTeams: $e');
      return [];
    }
  }

  Future<ClubTeam?> getTeam(String id) async {
    try {
      final doc = await _teams.doc(id).get();
      if (!doc.exists) return null;
      return ClubTeam.fromMap(doc.id, doc.data()!);
    } catch (e) {
      return null;
    }
  }

  Future<String?> addTeam(ClubTeam team) async {
    try {
      final ref = await _teams.add(team.toMap());
      return ref.id;
    } catch (e) {
      debugPrint('ClubService.addTeam: $e');
      return null;
    }
  }

  Future<bool> updateTeam(ClubTeam team) async {
    try {
      final data = team.toMap()..remove('createdAt');
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _teams.doc(team.id).update(data);
      return true;
    } catch (e) {
      debugPrint('ClubService.updateTeam: $e');
      return false;
    }
  }

  Future<bool> deleteTeam(String id) async {
    try {
      await _teams.doc(id).delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> seedDefaultTeamsIfEmpty() async {
    try {
      final existing = await _teams.limit(1).get();
      if (existing.docs.isNotEmpty) return;

      final now = Timestamp.now();
      final defaultTeams = [
        {
          'name': 'First Team',
          'category': 'firstTeam',
          'coachName': 'Head Coach',
          'physicalCoachName': 'Physical Coach',
          'season': '2024-2025',
          'playerIds': [],
          'createdAt': now,
        },
        {
          'name': 'U20',
          'category': 'u20',
          'coachName': 'Coach',
          'physicalCoachName': 'Physical Coach',
          'season': '2024-2025',
          'playerIds': [],
          'createdAt': now,
        },
        {
          'name': 'U17',
          'category': 'u17',
          'coachName': 'Coach',
          'physicalCoachName': 'Physical Coach',
          'season': '2024-2025',
          'playerIds': [],
          'createdAt': now,
        },
      ];

      for (final team in defaultTeams) {
        await _teams.add(team);
      }
    } catch (e) {
      debugPrint('ClubService.seedDefaultTeamsIfEmpty: $e');
    }
  }

  // ── Players ────────────────────────────────────────────────────────────────

  Stream<List<ClubPlayer>> playersStream({String? teamId}) {
    Query<Map<String, dynamic>> q = _players.orderBy('fullName');
    if (teamId != null) q = q.where('teamId', isEqualTo: teamId);
    return q.snapshots()
        .map((s) => s.docs.map((d) => ClubPlayer.fromMap(d.id, d.data())).toList());
  }

  Future<List<ClubPlayer>> getPlayers({String? teamId}) async {
    try {
      final start = DateTime.now();
      Query<Map<String, dynamic>> q = _players.orderBy('fullName');
      if (teamId != null) q = q.where('teamId', isEqualTo: teamId);
      final snap = await q.get();
      final ms = DateTime.now().difference(start).inMilliseconds;
      debugPrint('[Firestore] getPlayers: ${snap.docs.length} players in ${ms}ms');
      return snap.docs.map((d) => ClubPlayer.fromMap(d.id, d.data())).toList();
    } catch (e) {
      debugPrint('ClubService.getPlayers: $e');
      return [];
    }
  }

  Future<ClubPlayer?> getPlayer(String id) async {
    try {
      final doc = await _players.doc(id).get();
      if (!doc.exists) return null;
      return ClubPlayer.fromMap(doc.id, doc.data()!);
    } catch (e) {
      return null;
    }
  }

  Future<String?> addPlayer(ClubPlayer player) async {
    try {
      debugPrint('[ClubService.addPlayer] Starting - name: ${player.fullName}, teamId: ${player.teamId}');
      final ref = await _players.add(player.toMap());
      debugPrint('[ClubService.addPlayer] Player doc created: ${ref.id}');

      // Also add to team's playerIds
      await _teams.doc(player.teamId).update({
        'playerIds': FieldValue.arrayUnion([ref.id]),
      });
      debugPrint('[ClubService.addPlayer] Team updated with player ID');
      return ref.id;
    } catch (e, st) {
      debugPrint('ClubService.addPlayer ERROR: $e');
      debugPrint('ClubService.addPlayer STACKTRACE: $st');
      return null;
    }
  }

  Future<bool> updatePlayer(ClubPlayer player) async {
    try {
      final data = player.toMap()..remove('createdAt');
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _players.doc(player.id).update(data);
      return true;
    } catch (e) {
      debugPrint('ClubService.updatePlayer: $e');
      return false;
    }
  }

  Future<bool> deletePlayer(String id, String teamId) async {
    try {
      await _players.doc(id).delete();
      await _teams.doc(teamId).update({
        'playerIds': FieldValue.arrayRemove([id]),
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> updatePlayerScores(String playerId, {
    required double movement,
    required double stability,
    required double symmetry,
    required double control,
    required double overall,
  }) async {
    try {
      await _players.doc(playerId).update({
        'movementScore': movement,
        'stabilityScore': stability,
        'symmetryScore': symmetry,
        'controlScore': control,
        'latestScore': overall,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('ClubService.updatePlayerScores: $e');
    }
  }

  // ── Sessions ───────────────────────────────────────────────────────────────

  Stream<List<TrainingSession>> sessionsStream() => _sessions
      .orderBy('date', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => TrainingSession.fromMap(d.id, d.data())).toList());

  Future<List<TrainingSession>> getSessions({String? teamId}) async {
    try {
      Query<Map<String, dynamic>> q = _sessions.orderBy('date', descending: true);
      if (teamId != null) q = q.where('teamId', isEqualTo: teamId);
      final snap = await q.get();
      return snap.docs.map((d) => TrainingSession.fromMap(d.id, d.data())).toList();
    } catch (e) {
      debugPrint('ClubService.getSessions: $e');
      return [];
    }
  }

  Future<TrainingSession?> getSession(String id) async {
    try {
      final doc = await _sessions.doc(id).get();
      if (!doc.exists) return null;
      return TrainingSession.fromMap(doc.id, doc.data()!);
    } catch (e) {
      return null;
    }
  }

  Future<String?> addSession(TrainingSession session) async {
    try {
      final ref = await _sessions.add(session.toMap());
      return ref.id;
    } catch (e) {
      debugPrint('ClubService.addSession: $e');
      return null;
    }
  }

  Future<bool> updateSession(TrainingSession session) async {
    try {
      final data = session.toMap()..remove('createdAt');
      data['updatedAt'] = FieldValue.serverTimestamp();
      await _sessions.doc(session.id).update(data);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> markPlayerAssessed(String sessionId, String playerId) async {
    try {
      await _sessions.doc(sessionId).update({
        'completedPlayerIds': FieldValue.arrayUnion([playerId]),
        'assessmentCount': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('ClubService.markPlayerAssessed: $e');
    }
  }

  // ── Assessments ────────────────────────────────────────────────────────────

  Stream<List<PlayerAssessment>> assessmentsForPlayer(String playerId) => _assessments
      .where('playerId', isEqualTo: playerId)
      .orderBy('date', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => PlayerAssessment.fromMap(d.id, d.data())).toList());

  Future<List<PlayerAssessment>> getAssessmentsForPlayer(String playerId) async {
    try {
      final snap = await _assessments
          .where('playerId', isEqualTo: playerId)
          .orderBy('date', descending: true)
          .get();
      return snap.docs.map((d) => PlayerAssessment.fromMap(d.id, d.data())).toList();
    } catch (e) {
      debugPrint('ClubService.getAssessmentsForPlayer: $e');
      return [];
    }
  }

  Future<List<PlayerAssessment>> getLatestAssessments({int limit = 5}) async {
    try {
      final start = DateTime.now();
      final snap = await _assessments
          .orderBy('date', descending: true)
          .limit(limit)
          .get();
      final ms = DateTime.now().difference(start).inMilliseconds;
      debugPrint('[Firestore] getLatestAssessments: ${snap.docs.length} assessments in ${ms}ms');
      return snap.docs.map((d) => PlayerAssessment.fromMap(d.id, d.data())).toList();
    } catch (e) {
      debugPrint('ClubService.getLatestAssessments: $e');
      return [];
    }
  }

  Future<List<PlayerAssessment>> getAssessmentsForSession(String sessionId) async {
    try {
      final snap = await _assessments
          .where('sessionId', isEqualTo: sessionId)
          .orderBy('date', descending: true)
          .get();
      return snap.docs.map((d) => PlayerAssessment.fromMap(d.id, d.data())).toList();
    } catch (e) {
      return [];
    }
  }

  Future<String?> addAssessment(PlayerAssessment assessment) async {
    try {
      final ref = await _assessments.add(assessment.toMap());
      await markPlayerAssessed(assessment.sessionId, assessment.playerId);
      await updatePlayerScores(assessment.playerId,
        movement: assessment.movementQualityScore,
        stability: assessment.stabilityScore,
        symmetry: assessment.symmetryScore,
        control: assessment.controlScore,
        overall: assessment.overallScore,
      );
      return ref.id;
    } catch (e) {
      debugPrint('ClubService.addAssessment: $e');
      return null;
    }
  }

  // ── Coach Notes ────────────────────────────────────────────────────────────

  Future<List<CoachNote>> getNotesForPlayer(String playerId) async {
    try {
      final snap = await _players
          .doc(playerId)
          .collection('notes')
          .orderBy('date', descending: true)
          .get();
      return snap.docs.map((d) => CoachNote.fromMap(d.id, d.data())).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> addNote(CoachNote note) async {
    try {
      await _players.doc(note.playerId).collection('notes').add(note.toMap());
    } catch (e) {
      debugPrint('ClubService.addNote: $e');
    }
  }

  // ── Dashboard Stats ────────────────────────────────────────────────────────

  Future<DashboardStats> getDashboardStats() async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);

      // Run all Firestore queries in parallel
      final results = await Future.wait([
        getPlayers(),
        getTeams(),
        _sessions
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .get(),
        _assessments
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
            .get(),
      ]);

      final players = results[0] as List<ClubPlayer>;
      final teams = results[1] as List<ClubTeam>;
      final sessions = results[2] as QuerySnapshot<Map<String, dynamic>>;
      final todayAssessments = results[3] as QuerySnapshot<Map<String, dynamic>>;

      final active = players.where((p) => p.status == PlayerStatus.active).length;
      final injured = players.where((p) => p.status == PlayerStatus.injured).length;
      final needReview = players.where((p) =>
          p.latestScore != null && p.latestScore! < 65).length;

      final scores = players
          .where((p) => p.movementScore != null)
          .map((p) => p.movementScore!)
          .toList();
      final stab = players
          .where((p) => p.stabilityScore != null)
          .map((p) => p.stabilityScore!)
          .toList();

      return DashboardStats(
        totalPlayers: players.length,
        activePlayers: active,
        injuredPlayers: injured,
        totalTeams: teams.length,
        sessionsToday: sessions.docs.length,
        assessmentsToday: todayAssessments.docs.length,
        playersNeedingReview: needReview,
        avgMovementScore: scores.isEmpty ? 0 : scores.reduce((a, b) => a + b) / scores.length,
        avgStabilityScore: stab.isEmpty ? 0 : stab.reduce((a, b) => a + b) / stab.length,
      );
    } catch (e) {
      debugPrint('ClubService.getDashboardStats: $e');
      return DashboardStats();
    }
  }

  // ── Performance Benchmark ──────────────────────────────────────────────────

  Future<void> benchmarkFirestore() async {
    debugPrint('[Benchmark] Starting Firestore benchmark...');

    // Test 1: First Firestore access
    final first = DateTime.now();
    try {
      final snap = await _db.collection('clubs').limit(1).get();
      final ms = DateTime.now().difference(first).inMilliseconds;
      debugPrint('[Benchmark] First Firestore access: ${ms}ms (${snap.docs.length} docs)');
    } catch (e) {
      final ms = DateTime.now().difference(first).inMilliseconds;
      debugPrint('[Benchmark] First access error after ${ms}ms: $e');
    }

    // Test 2: getTeams() direct call
    final start2 = DateTime.now();
    final teams = await getTeams();
    final ms2 = DateTime.now().difference(start2).inMilliseconds;
    debugPrint('[Benchmark] getTeams(): ${ms2}ms (${teams.length} teams)');

    // Test 3: getPlayers() direct call
    final start3 = DateTime.now();
    final players = await getPlayers();
    final ms3 = DateTime.now().difference(start3).inMilliseconds;
    debugPrint('[Benchmark] getPlayers(): ${ms3}ms (${players.length} players)');

    // Test 4: Parallel queries
    final start4 = DateTime.now();
    await Future.wait([
      getTeams(),
      getPlayers(),
    ]);
    final ms4 = DateTime.now().difference(start4).inMilliseconds;
    debugPrint('[Benchmark] Parallel (teams + players): ${ms4}ms');

    debugPrint('[Benchmark] Complete');
  }
}
