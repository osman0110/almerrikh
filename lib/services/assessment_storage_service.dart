import '../models/assessment_result_model.dart';
import '../api_service.dart';
import '../services/club_service.dart';
import '../utils/app_logger.dart';

class AssessmentStorageService {
  AssessmentStorageService._internal();
  static final AssessmentStorageService instance = AssessmentStorageService._internal();

  /// Saves the assessment to the server and marks the player as assessed in
  /// the session (if sessionId is present). Awaits the API call so callers
  /// can rely on the data being persisted before they refresh the UI.
  Future<void> saveAssessment(AssessmentResult result) async {
    if (ApiService.token == null) {
      AppLogger.w('AssessmentStorage', 'No token — skipping sync');
      return;
    }
    try {
      final r = await ApiService.saveAssessment(
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
        sessionId: result.sessionId,
        coachNotes: result.coachNotes,
        attemptGroupId: result.attemptGroupId,
        attemptNumber: result.attemptNumber,
        invalidReason: result.invalidReason,
      );
      if (r.containsKey('error')) {
        AppLogger.w('AssessmentStorage', 'Save error: ${r['error']}');
        return;
      }
      AppLogger.i('AssessmentStorage', 'Saved assessment ${result.id} for player ${result.playerId}');

      // Mark player as assessed in their session so progress updates.
      final sid = result.sessionId;
      if (sid != null && sid.isNotEmpty) {
        ClubService().markPlayerAssessed(sid, result.playerId).catchError((_) {});
      }
    } catch (e) {
      AppLogger.e('AssessmentStorage', 'saveAssessment failed', e);
    }
  }

  /// Fetches assessment history for the authenticated player.
  /// Uses the dedicated player endpoint that enforces player_id from the server.
  /// Returns empty if [linkedPlayerId] is null — never fetches unscoped data.
  Stream<List<AssessmentResult>> streamAssessments(String? linkedPlayerId) {
    if (linkedPlayerId == null || linkedPlayerId.isEmpty) {
      AppLogger.w('AssessmentStorage', 'streamAssessments: no linked_player_id');
      return Stream.value([]);
    }
    return Stream.fromFuture(
      ApiService.getPlayerAssessments(linkedPlayerId: linkedPlayerId).then((list) =>
          list.map((m) => AssessmentResult.fromMap(m['id'] as String, m)).toList()),
    );
  }

  /// Returns the latest assessment for this player.
  /// REQUIRES a non-empty [linkedPlayerId].
  /// Returns null (not an error) if player has no assessments yet.
  /// Throws if [linkedPlayerId] is missing — caller must handle this.
  Future<AssessmentResult?> getLatestAssessment(String? linkedPlayerId) async {
    if (linkedPlayerId == null || linkedPlayerId.isEmpty) {
      AppLogger.w('AssessmentStorage', 'getLatestAssessment: no linked_player_id');
      return null;
    }
    final list = await ApiService.getPlayerAssessments(
        linkedPlayerId: linkedPlayerId, limit: 1);
    if (list.isEmpty) return null;
    return AssessmentResult.fromMap(list.first['id'] as String, list.first);
  }
}
