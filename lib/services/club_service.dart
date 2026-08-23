import 'dart:convert';
import 'dart:typed_data';

import '../utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../api_service.dart';
import '../app_config.dart';
import '../models/club_models.dart';

const _base = kApiBase;
const _uuid = Uuid();

class ReportArchiveUnavailableException implements Exception {
  const ReportArchiveUnavailableException();
}

/// All club management data via PHP/MySQL API.
class ClubService {
  static final ClubService _i = ClubService._();
  factory ClubService() => _i;
  ClubService._();

  Map<String, String> get _h => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (ApiService.token != null) 'Authorization': 'Bearer ${ApiService.token}',
      };

  // ── Teams ──────────────────────────────────────────────────────────────────

  Future<List<ClubTeam>> getTeams() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/club/teams.php'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['teams'] is List) {
        return (body['teams'] as List)
            .map((j) => ClubTeam.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getTeams', 'Request failed', e);
    }
    return [];
  }

  Future<Map<String, dynamic>?> getPhysicalCoachDashboard() async {
    try {
      final res = await http
          .get(
            Uri.parse('$_base/club/physical-coach-dashboard.php'),
            headers: _h,
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        AppLogger.w(
          'ClubService.getPhysicalCoachDashboard',
          'Server returned HTTP ${res.statusCode}',
        );
        return null;
      }
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) {
        return Map<String, dynamic>.from(body);
      }
    } catch (e) {
      AppLogger.e(
        'ClubService.getPhysicalCoachDashboard',
        'Request failed',
        e,
      );
    }
    return null;
  }

  Future<Map<String, dynamic>?> getDataQualityReport() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/club/data-quality.php'), headers: _h)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        AppLogger.w(
          'ClubService.getDataQualityReport',
          'Server returned HTTP ${res.statusCode}',
        );
        return null;
      }
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) {
        return Map<String, dynamic>.from(body);
      }
    } catch (e) {
      AppLogger.e('ClubService.getDataQualityReport', 'Request failed', e);
    }
    return null;
  }

  // Teams stream — not supported with HTTP; return single-value stream
  Stream<List<ClubTeam>> teamsStream() =>
      Stream.fromFuture(getTeams());

  Future<String?> addTeam(ClubTeam team) async {
    try {
      final id = team.id.isEmpty ? const Uuid().v4() : team.id;
      final res = await http
          .post(Uri.parse('$_base/club/teams.php'),
              headers: _h, body: jsonEncode(team.toJson()..['id'] = id))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return body['id']?.toString() ?? id;
      AppLogger.w('ClubService.addTeam', 'Server returned error');
    } catch (e) {
      AppLogger.e('ClubService.addTeam', 'Request failed', e);
    }
    return null;
  }

  Future<bool> updateTeam(ClubTeam team) async {
    try {
      final res = await http
          .put(Uri.parse('$_base/club/teams.php'),
              headers: _h, body: jsonEncode(team.toJson()..['id'] = team.id))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return true;
      AppLogger.w(
        'ClubService.updateTeam',
        'Server rejected update (${res.statusCode})',
      );
    } catch (e) {
      AppLogger.e('ClubService.updateTeam', 'Request failed', e);
    }
    return false;
  }

  Future<bool> deleteTeam(String id) async {
    try {
      final res = await http
          .delete(Uri.parse('$_base/club/teams.php?id=${Uri.encodeComponent(id)}'),
              headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return true;
      AppLogger.w(
        'ClubService.deleteTeam',
        'Server rejected deletion (${res.statusCode})',
      );
    } catch (e) {
      AppLogger.e('ClubService.deleteTeam', 'Request failed', e);
    }
    return false;
  }

  Future<void> seedDefaultTeamsIfEmpty() async {}

  // ── Seasons ────────────────────────────────────────────────────────────────

  Future<List<ClubSeason>> getSeasons({int? teamId}) async {
    try {
      final url = teamId != null
          ? '$_base/club/seasons.php?team_id=$teamId'
          : '$_base/club/seasons.php';
      final res = await http.get(Uri.parse(url), headers: _h).timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['seasons'] is List) {
        return (body['seasons'] as List)
            .map((j) => ClubSeason.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getSeasons', 'Request failed', e);
    }
    return [];
  }

  Future<bool> saveSeason(ClubSeason season) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/club/seasons.php'), headers: _h, body: jsonEncode(season.toJson()))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.saveSeason', 'Request failed', e);
    }
    return false;
  }

  Future<bool> activateSeason(int id) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/club/seasons.php'),
              headers: _h, body: jsonEncode({'action': 'activate', 'id': id}))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.activateSeason', 'Request failed', e);
    }
    return false;
  }

  Future<bool> deleteSeason(int id) async {
    try {
      final res = await http
          .delete(Uri.parse('$_base/club/seasons.php?id=$id'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.deleteSeason', 'Request failed', e);
    }
    return false;
  }

  // ── Competitions ───────────────────────────────────────────────────────────

  Future<List<ClubCompetition>> getCompetitions() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/club/competitions.php'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['competitions'] is List) {
        return (body['competitions'] as List)
            .map((j) => ClubCompetition.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getCompetitions', 'Request failed', e);
    }
    return [];
  }

  Future<bool> saveCompetition(ClubCompetition competition) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/club/competitions.php'),
              headers: _h, body: jsonEncode(competition.toJson()))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.saveCompetition', 'Request failed', e);
    }
    return false;
  }

  Future<bool> deleteCompetition(int id) async {
    try {
      final res = await http
          .delete(Uri.parse('$_base/club/competitions.php?id=$id'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.deleteCompetition', 'Request failed', e);
    }
    return false;
  }

  // ── Players ────────────────────────────────────────────────────────────────

  Future<List<ClubPlayer>> getPlayers({
    String? teamId,
    bool archived = false,
    bool throwOnError = false,
  }) async {
    try {
      final query = <String, String>{
        if (teamId != null) 'team': teamId,
        if (archived) 'archived': '1',
      };
      final url = Uri.parse('$_base/players.php')
          .replace(queryParameters: query.isEmpty ? null : query)
          .toString();
      final res = await http
          .get(Uri.parse(url), headers: _h)
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['players'] is List) {
        final players = (body['players'] as List)
            .map((j) => ClubPlayer.fromJson(j as Map<String, dynamic>))
            .toList();
        AppLogger.i('ClubService.getPlayers',
            'HTTP ${res.statusCode}; players=${players.length}; nicknameRows=${players.where((p) => p.nickname?.trim().isNotEmpty == true).length}');
        if (teamId != null) {
          return players.where((p) => p.teamName == teamId || p.teamId == teamId).toList();
        }
        return players;
      }
      if (throwOnError) {
        throw StateError('Players response is unavailable');
      }
    } catch (e) {
      AppLogger.e('ClubService.getPlayers', 'Request failed', e);
      if (throwOnError) rethrow;
    }
    return [];
  }

  Future<ClubPlayer?> getPlayer(String id) async {
    final url = '$_base/players.php?id=${Uri.encodeComponent(id)}';
    try {
      final res = await http
          .get(Uri.parse(url), headers: _h)
          .timeout(const Duration(seconds: 8));
      AppLogger.i('ClubService.getPlayer', 'GET $url → ${res.statusCode}');
      final body = jsonDecode(res.body);
      if (body is Map && body['players'] is List) {
        final list = body['players'] as List;
        if (list.isNotEmpty) {
          final player = ClubPlayer.fromJson(list.first as Map<String, dynamic>);
          AppLogger.i('ClubService.getPlayer',
              'nicknameReturned=${player.nickname?.trim().isNotEmpty == true}');
          // Guard against backend returning wrong player (e.g. ignoring id param)
          if (player.id.isNotEmpty && player.id != id) {
            AppLogger.e('ClubService.getPlayer',
                'ID MISMATCH — requested=$id, got=${player.id}. Backend may not support ?id= filtering.',
                'mismatch');
            // Fall back: scan full list for the correct player
            for (final j in list) {
              final p = ClubPlayer.fromJson(j as Map<String, dynamic>);
              if (p.id == id) return p;
            }
            return null;
          }
          return player;
        }
      }
    } catch (e) {
      AppLogger.e('ClubService.getPlayer', 'Request failed for id=$id', e);
    }
    return null;
  }

  Future<ClubPlayerDetail?> getPlayerDetail(String playerId) async {
    try {
      // Use existing deployed endpoints — no new PHP file required
      final player = await getPlayer(playerId);
      if (player == null) {
        AppLogger.w('ClubService.getPlayerDetail', 'Player not found: $playerId');
        return null;
      }
      final assessments = await getAssessmentsForPlayer(playerId);
      Map<String, dynamic>? discipline;
      try {
        final detailRes = await http
            .get(Uri.parse('$_base/club/player.php?id=${Uri.encodeComponent(playerId)}'), headers: _h)
            .timeout(const Duration(seconds: 8));
        final detailBody = jsonDecode(detailRes.body);
        if (detailBody is Map && detailBody['discipline'] is Map) {
          discipline = (detailBody['discipline'] as Map).cast<String, dynamic>();
        }
      } catch (_) {}

      // Wellness: pull from team wellness summary and filter by playerId
      Map<String, dynamic>? wellness;
      try {
        final wRes = await http
            .get(Uri.parse('$_base/club/wellness_summary.php'), headers: _h)
            .timeout(const Duration(seconds: 8));
        if (wRes.statusCode == 200) {
          final wBody = jsonDecode(wRes.body);
          final list = wBody['players'];
          if (list is List) {
            final match = list
                .cast<Map<String, dynamic>>()
                .where((p) => p['id']?.toString() == playerId)
                .toList();
            if (match.isNotEmpty) wellness = match.first;
          }
        }
      } catch (_) {}

      return ClubPlayerDetail(
        player: player,
        assessments: assessments,
        wellness: wellness,
        discipline: discipline,
      );
    } catch (e) {
      AppLogger.e('ClubService.getPlayerDetail', 'Request failed for $playerId', e);
      return null;
    }
  }

  Stream<List<ClubPlayer>> playersStream({String? teamId}) =>
      Stream.fromFuture(getPlayers(teamId: teamId));

  /// Returns `{'id': ..., 'error': null}` on success, or `{'id': null, 'error': msg}` on failure.
  /// [email]/[password] optionally provision a direct login for this player
  /// (so they can sign in themselves without an invite code).
  Future<Map<String, dynamic>> addPlayer(
    ClubPlayer player, {
    String? email,
    String? password,
  }) async {
    try {
      final id = player.id.isEmpty ? _uuid.v4() : player.id;
      final json = player.toJson()
        ..['id'] = id
        ..addAll({
          if (email != null && email.isNotEmpty) 'email': email,
          if (password != null && password.isNotEmpty) 'password': password,
        });
      final res = await http
          .post(Uri.parse('$_base/players.php'),
              headers: _h, body: jsonEncode(json))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) {
        AppLogger.i('ClubService.addPlayer',
            'HTTP ${res.statusCode}; nicknameSent=${json['nickname'] != null}');
        return {'id': body['id']?.toString() ?? id, 'error': null};
      }
      final error = body is Map ? body['error']?.toString() : null;
      AppLogger.w('ClubService.addPlayer',
          'HTTP ${res.statusCode}; nicknameSent=${json['nickname'] != null}; error=${error ?? 'Invalid response'}');
      return {'id': null, 'error': error ?? 'Failed'};
    } catch (e) {
      AppLogger.e('ClubService.addPlayer', 'Request failed', e);
      return {'id': null, 'error': null};
    }
  }

  /// Returns `{'success': true, 'error': null}` on success, or
  /// `{'success': false, 'error': msg}` on failure.
  /// [email]/[password] optionally provision a login for a player who
  /// doesn't already have one (server rejects this if already linked).
  Future<Map<String, dynamic>> updatePlayer(ClubPlayer player, {String? email, String? password}) async {
    try {
      final json = player.toJson()
        ..addAll({
          if (email != null && email.isNotEmpty) 'email': email,
          if (password != null && password.isNotEmpty) 'password': password,
        });
      final res = await http
          .post(Uri.parse('$_base/players.php'),
              headers: _h, body: jsonEncode(json))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) {
        AppLogger.i('ClubService.updatePlayer',
            'HTTP ${res.statusCode}; nicknameSent=${json['nickname'] != null}');
        return {'success': true, 'error': null};
      }
      final error = body is Map ? body['error']?.toString() : null;
      AppLogger.w('ClubService.updatePlayer',
          'HTTP ${res.statusCode}; nicknameSent=${json['nickname'] != null}; error=${error ?? 'Invalid response'}');
      return {'success': false, 'error': error ?? 'Failed'};
    } catch (e) {
      AppLogger.e('ClubService.updatePlayer', 'Request failed', e);
      return {'success': false, 'error': null};
    }
  }

  /// Upload a player photo from raw bytes.
  /// Works on both Web and native — no dart:io required.
  Future<String?> uploadPlayerPhotoBytes(
    Uint8List bytes, {
    String filename = 'photo.jpg',
  }) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$_base/upload_photo.php'));
      if (ApiService.token != null) {
        req.headers['Authorization'] = 'Bearer ${ApiService.token}';
      }
      req.files.add(http.MultipartFile.fromBytes(
        'photo',
        bytes,
        filename: filename,
      ));
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final body = jsonDecode(await streamed.stream.bytesToString());
      if (body is Map && body['url'] != null) return body['url'] as String;
    } catch (e) {
      AppLogger.e('ClubService.uploadPlayerPhoto', 'Request failed', e);
    }
    return null;
  }

  /// Upload from a file path — kept for internal native use.
  /// Prefer uploadPlayerPhotoBytes() for new call sites.
  Future<String?> uploadPlayerPhoto(String filePath) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$_base/upload_photo.php'));
      if (ApiService.token != null) {
        req.headers['Authorization'] = 'Bearer ${ApiService.token}';
      }
      req.files.add(await http.MultipartFile.fromPath('photo', filePath));
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final body = jsonDecode(await streamed.stream.bytesToString());
      if (body is Map && body['url'] != null) return body['url'] as String;
    } catch (e) {
      AppLogger.e('ClubService.uploadPlayerPhoto', 'Request failed', e);
    }
    return null;
  }

  Future<bool> archivePlayer(String id) async {
    try {
      final res = await http
          .delete(Uri.parse('$_base/players.php?id=${Uri.encodeComponent(id)}'),
              headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.deletePlayer', 'Request failed', e);
    }
    return false;
  }

  Future<bool> restorePlayer(String id) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/players.php'),
            headers: _h,
            body: jsonEncode({'action': 'restore', 'id': id}),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.restorePlayer', 'Request failed', e);
    }
    return false;
  }

  Future<bool> deletePlayerPermanently(String id) async {
    try {
      final uri = Uri.parse('$_base/players.php').replace(
        queryParameters: {'id': id, 'permanent': '1'},
      );
      final res = await http
          .delete(uri, headers: _h)
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e(
        'ClubService.deletePlayerPermanently',
        'Request failed',
        e,
      );
    }
    return false;
  }

  Future<void> updatePlayerScores(String playerId, {
    required double movement,
    required double stability,
    required double symmetry,
    required double control,
    required double overall,
  }) async {
    try {
      await http.post(Uri.parse('$_base/players.php'),
          headers: _h,
          body: jsonEncode({
            'id':             playerId,
            'name':           '—', // required by API; won't overwrite if already set on UPDATE
            'movement_score': movement,
            'stability_score':stability,
            'symmetry_score': symmetry,
            'control_score':  control,
            'latest_score':   overall,
          })).timeout(const Duration(seconds: 8));
    } catch (e) {
      AppLogger.e('ClubService.updatePlayerScores', 'Request failed', e);
    }
  }

  // ── Sessions ───────────────────────────────────────────────────────────────

  Future<List<TrainingSession>> getSessions({
    String? teamId,
    bool throwOnError = false,
  }) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/sessions.php'), headers: _h)
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['sessions'] is List) {
        final sessions = (body['sessions'] as List)
            .map((j) => TrainingSession.fromJson(j as Map<String, dynamic>))
            .toList();
        if (teamId != null) {
          return sessions.where((s) => s.teamName == teamId || s.teamId == teamId).toList();
        }
        return sessions;
      }
      if (throwOnError) {
        throw StateError('Sessions response is unavailable');
      }
    } catch (e) {
      AppLogger.e('ClubService.getSessions', 'Request failed', e);
      if (throwOnError) rethrow;
    }
    return [];
  }

  Future<TrainingSession?> getSession(String id) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/sessions.php?id=${Uri.encodeComponent(id)}'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['session'] is Map) {
        return TrainingSession.fromJson(body['session'] as Map<String, dynamic>);
      }
    } catch (e) {
      AppLogger.e('ClubService.getSession', 'Request failed', e);
    }
    // Fallback: fetch full list and filter by id (handles older server without single-session endpoint)
    try {
      final all = await getSessions();
      return all.where((s) => s.id == id).firstOrNull;
    } catch (e) {
      AppLogger.e('ClubService.getSession', 'Fallback also failed', e);
    }
    return null;
  }

  Stream<List<TrainingSession>> sessionsStream() =>
      Stream.fromFuture(getSessions());

  /// Returns {player_id: 'present'|'absent'|'late'|'pending'} for a session's roster.
  Future<Map<String, String>> getSessionAttendance(String sessionId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/sessions.php?id=${Uri.encodeComponent(sessionId)}&roster=1'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      final participants = body is Map ? body['participants'] : null;
      if (participants is List) {
        return {
          for (final p in participants)
            if (p is Map && p['id'] != null)
              p['id'].toString(): (p['attendance_status'] ?? 'pending').toString(),
        };
      }
    } catch (e) {
      AppLogger.e('ClubService.getSessionAttendance', 'Request failed', e);
    }
    return {};
  }

  Future<bool> setSessionAttendance(String sessionId, Map<String, String> attendance) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/sessions.php'),
              headers: _h,
              body: jsonEncode({
                'action': 'attendance',
                'session_id': sessionId,
                'attendance': attendance,
              }))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      return body is Map && (body['success'] == true || body['ok'] == true);
    } catch (e) {
      AppLogger.e('ClubService.setSessionAttendance', 'Request failed', e);
    }
    return false;
  }

  Future<Map<String, Map<String, dynamic>>> getSessionPlayerClocks(
      String sessionId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/sessions.php?id=${Uri.encodeComponent(sessionId)}&roster=1'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      final participants = body is Map ? body['participants'] : null;
      if (participants is List) {
        return {
          for (final item in participants)
            if (item is Map && item['id'] != null)
              item['id'].toString(): {
                'running': item['clock_running'] == true || item['clock_running'] == 1,
                'elapsed_seconds': int.tryParse(item['elapsed_seconds'].toString()) ?? 0,
              },
        };
      }
    } catch (e) {
      AppLogger.e('ClubService.getSessionPlayerClocks', 'Request failed', e);
    }
    return {};
  }

  /// Returns null on success, otherwise the server/network error message.
  Future<String?> controlSessionClock(
    String sessionId,
    String operation, {
    String? playerId,
  }) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/sessions.php'),
              headers: _h,
              body: jsonEncode({
                'action': 'session_clock',
                'session_id': sessionId,
                'operation': operation,
                if (playerId != null) 'player_id': playerId,
              }))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return null;
      final error = body is Map ? body['error']?.toString() : null;
      AppLogger.w('ClubService.controlSessionClock',
          'HTTP ${res.statusCode}; body=${res.body}');
      return error ?? 'HTTP ${res.statusCode}';
    } catch (e) {
      AppLogger.e('ClubService.controlSessionClock', 'Request failed', e);
      return e.toString();
    }
  }

  Future<String?> addSession(TrainingSession session) async {
    try {
      final id = session.id.isEmpty ? _uuid.v4() : session.id;
      final json = session.toJson()..['id'] = id;
      final res = await http
          .post(Uri.parse('$_base/sessions.php'),
              headers: _h, body: jsonEncode(json))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return body['id']?.toString() ?? id;
    } catch (e) {
      AppLogger.e('ClubService.addSession', 'Request failed', e);
    }
    return null;
  }

  Future<bool> updateSession(TrainingSession session) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/sessions.php'),
              headers: _h, body: jsonEncode(session.toJson()))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.updateSession', 'Request failed', e);
    }
    return false;
  }

  Future<void> markPlayerAssessed(String sessionId, String playerId) async {
    try {
      final session = await getSession(sessionId);
      if (session == null) return;
      if (!session.completedPlayerIds.contains(playerId)) {
        session.completedPlayerIds.add(playerId);
        session.assessmentCount++;
        await updateSession(session);
      }
    } catch (e) {
      AppLogger.e('ClubService.markPlayerAssessed', 'Request failed', e);
    }
  }

  // ── Assessments ────────────────────────────────────────────────────────────

  /// Applies a coach's manual override to a test score. [reason] is required
  /// and is logged server-side (audit_logs) alongside the old/new score.
  Future<bool> overrideAssessmentScore({
    required String assessmentId,
    required int overrideScore,
    required String reason,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/assessments.php'),
            headers: _h,
            body: jsonEncode({
              'action': 'override',
              'id': assessmentId,
              'override_score': overrideScore,
              'override_reason': reason,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.overrideAssessmentScore', 'Request failed', e);
      return false;
    }
  }

  /// Coach certifies a (possibly edited) AI result. Only after this succeeds
  /// should the caller delete the locally-captured assessment video.
  Future<bool> approveAssessment(String assessmentId) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/assessments.php'),
            headers: _h,
            body: jsonEncode({'action': 'approve', 'id': assessmentId}),
          )
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.approveAssessment', 'Request failed', e);
      return false;
    }
  }

  Future<List<PlayerAssessment>> getAssessmentsForPlayer(String playerId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/assessments.php?player_id=${Uri.encodeComponent(playerId)}'),
              headers: _h)
          .timeout(const Duration(seconds: 8));

      AppLogger.i('ClubService.getAssessmentsForPlayer',
          'GET assessments for $playerId → ${res.statusCode}');

      dynamic body;
      try {
        body = jsonDecode(res.body);
      } catch (_) {
        AppLogger.w('ClubService.getAssessmentsForPlayer', 'Response body is not valid JSON');
        return [];
      }

      // Normalise: accept top-level List, or Map with 'assessments' key
      List<dynamic> raw = [];
      if (body is List) {
        raw = body;
      } else if (body is Map && body['assessments'] is List) {
        raw = body['assessments'] as List;
      } else {
        AppLogger.w('ClubService.getAssessmentsForPlayer',
            'Unexpected response shape: ${body.runtimeType}');
        return [];
      }

      // Parse each row defensively — one bad record must not crash the whole list
      final results = <PlayerAssessment>[];
      for (final j in raw) {
        try {
          if (j is Map) {
            // Use Map<String,dynamic>.from() instead of bare `as` cast
            results.add(PlayerAssessment.fromMap('', Map<String, dynamic>.from(j)));
          } else {
            AppLogger.w('ClubService.getAssessmentsForPlayer',
                'Skipping non-Map item: ${j.runtimeType}');
          }
        } catch (parseErr) {
          AppLogger.w('ClubService.getAssessmentsForPlayer',
              'Parse error for one assessment (skipped): $parseErr');
        }
      }

      AppLogger.i('ClubService.getAssessmentsForPlayer',
          'Loaded ${results.length} assessments for player $playerId');
      return results;
    } catch (e) {
      AppLogger.e('ClubService.getAssessmentsForPlayer', 'Request failed', e);
    }
    return [];
  }

  Stream<List<PlayerAssessment>> assessmentsForPlayer(String playerId) =>
      Stream.fromFuture(getAssessmentsForPlayer(playerId));

  Future<List<PlayerAssessment>> getLatestAssessments({int limit = 5}) async =>
      []; // not needed for current screens

  Future<List<PlayerAssessment>> getAssessmentsForSession(String sessionId) async {
    try {
      final uri = Uri.parse('$_base/club/session_assessments.php')
          .replace(queryParameters: {'session_id': sessionId});
      final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['assessments'] is List) {
        return (body['assessments'] as List)
            .map((j) => PlayerAssessment.fromMap('', j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getAssessmentsForSession', 'Request failed', e);
    }
    return [];
  }

  Future<String?> addAssessment(PlayerAssessment assessment) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/assessments.php'),
              headers: _h,
              body: jsonEncode({
                'id':                    assessment.id.isEmpty ? _uuid.v4() : assessment.id,
                'player_id':             assessment.playerId,
                'player_name':           assessment.playerName,
                'type':                  assessment.type.name,
                'overall_score':         assessment.overallScore.round(),
                'movement_quality_score':assessment.movementQualityScore.round(),
                'stability_score':       assessment.stabilityScore.round(),
                'symmetry_score':        assessment.symmetryScore.round(),
                'control_score':         assessment.controlScore.round(),
                'quality_score':         assessment.assessmentQuality.round(),
                'notes':                 assessment.coachNotes,
              }))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) {
        await markPlayerAssessed(assessment.sessionId, assessment.playerId);
        await updatePlayerScores(
          assessment.playerId,
          movement: assessment.movementQualityScore,
          stability: assessment.stabilityScore,
          symmetry: assessment.symmetryScore,
          control: assessment.controlScore,
          overall: assessment.overallScore,
        );
        return body['id']?.toString();
      }
    } catch (e) {
      AppLogger.e('ClubService.addAssessment', 'Request failed', e);
    }
    return null;
  }

  // ── Coach Notes ────────────────────────────────────────────────────────────

  Future<List<CoachNote>> getNotesForPlayer(String playerId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/club/player-notes.php?player_id=${Uri.encodeComponent(playerId)}'),
              headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true && body['notes'] is List) {
        return (body['notes'] as List)
            .map((j) => CoachNote.fromMap((j as Map<String, dynamic>)['id'] as String, j))
            .toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getNotesForPlayer', 'Request failed', e);
    }
    return [];
  }

  Future<void> addNote(CoachNote note) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/club/player-notes.php'),
              headers: _h,
              body: jsonEncode({
                'player_id': note.playerId,
                'author_name': note.authorName,
                'text': note.text,
              }))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is! Map || body['success'] != true) {
        AppLogger.w('ClubService.addNote', 'Server returned error');
      }
    } catch (e) {
      AppLogger.e('ClubService.addNote', 'Request failed', e);
    }
  }

  // ── Session Exercises ──────────────────────────────────────────────────────

  Future<List<ClubSessionExercise>> getSessionExercises(String sessionId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/sessions/exercises.php?session_id=${Uri.encodeComponent(sessionId)}'),
              headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['exercises'] is List) {
        return (body['exercises'] as List)
            .map((j) => ClubSessionExercise.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getSessionExercises', 'Request failed', e);
    }
    return [];
  }

  Future<bool> saveSessionExercises(String sessionId, List<ClubSessionExercise> exercises) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/sessions/exercises.php'),
              headers: _h,
              body: jsonEncode({
                'session_id': sessionId,
                'exercises': exercises.map((e) => e.toJson()).toList(),
              }))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.saveSessionExercises', 'Request failed', e);
    }
    return false;
  }

  // ── Matches ────────────────────────────────────────────────────────────────

  Future<List<MatchModel>> getMatches() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/matches.php'), headers: _h)
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['matches'] is List) {
        return (body['matches'] as List)
            .map((j) => MatchModel.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getMatches', 'Request failed', e);
    }
    return [];
  }

  Future<MatchModel?> getMatch(String id) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/matches.php?id=${Uri.encodeComponent(id)}'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['match'] is Map) {
        return MatchModel.fromJson(body['match'] as Map<String, dynamic>);
      }
    } catch (e) {
      AppLogger.e('ClubService.getMatch', 'Request failed', e);
    }
    return null;
  }

  /// Returns null on success, otherwise the server/network error message.
  Future<String?> controlMatchClock(
    String matchId,
    String operation, {
    String? playerId,
  }) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/matches.php'),
              headers: _h,
              body: jsonEncode({
                'action': 'clock',
                'match_id': matchId,
                'operation': operation,
                if (playerId != null) 'player_id': playerId,
              }))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return null;
      final error = body is Map ? body['error']?.toString() : null;
      AppLogger.w('ClubService.controlMatchClock',
          'HTTP ${res.statusCode}; body=${res.body}');
      return error ?? 'HTTP ${res.statusCode}';
    } catch (e) {
      AppLogger.e('ClubService.controlMatchClock', 'Request failed', e);
      return e.toString();
    }
  }

  Future<bool> setMatchStarter(
      String matchId, String playerId, bool starter) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/matches.php'),
              headers: _h,
              body: jsonEncode({
                'action': 'starter',
                'match_id': matchId,
                'player_id': playerId,
                'starter': starter,
              }))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.setMatchStarter', 'Request failed', e);
    }
    return false;
  }

  Future<bool> incrementMatchStat(
      String matchId, String playerId, String stat) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/matches.php'),
              headers: _h,
              body: jsonEncode({
                'action': 'stat',
                'match_id': matchId,
                'player_id': playerId,
                'stat': stat,
              }))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.incrementMatchStat', 'Request failed', e);
    }
    return false;
  }

  Future<String?> saveMatch(MatchModel match) async {
    try {
      final id = match.id.isEmpty ? _uuid.v4() : match.id;
      final json = match.toJson()..['id'] = id;
      final res = await http
          .post(Uri.parse('$_base/matches.php'), headers: _h, body: jsonEncode(json))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return body['id']?.toString() ?? id;
    } catch (e) {
      AppLogger.e('ClubService.saveMatch', 'Request failed', e);
    }
    return null;
  }

  Future<bool> deleteMatch(String id) async {
    try {
      final res = await http
          .delete(Uri.parse('$_base/matches.php?id=${Uri.encodeComponent(id)}'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.deleteMatch', 'Request failed', e);
    }
    return false;
  }

  /// Roster-level rollup of match minutes/cards over a date range, plus
  /// assigned and coach-evaluated sessions for the admin-facing player list.
  Future<List<PlayerManagementReportRow>> getManagementReport({
    int? teamId,
    String? from,
    String? to,
  }) async {
    try {
      final qp = <String, String>{
        if (teamId != null) 'team_id': '$teamId',
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      };
      final url = Uri.parse('$_base/club/management-report.php')
          .replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(url, headers: _h).timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['players'] is List) {
        return (body['players'] as List)
            .map((j) => PlayerManagementReportRow.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getManagementReport', 'Request failed', e);
    }
    return [];
  }

  /// Returns completed report periods. The endpoint also backfills any
  /// missing weekly, 28-day, and monthly archive rows from source data.
  Future<List<ReportArchiveEntry>> getReportArchive({
    bool throwOnError = false,
  }) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/club/report-archive.php'), headers: _h)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        AppLogger.w(
          'ClubService.getReportArchive',
          'Server returned HTTP ${res.statusCode}',
        );
        var unavailable = res.statusCode == 404;
        if (res.statusCode == 503) {
          try {
            final errorBody = jsonDecode(res.body);
            unavailable = errorBody is Map &&
                errorBody['error'] == 'REPORT_ARCHIVE_MIGRATION_REQUIRED';
          } catch (_) {
            unavailable = false;
          }
        }
        if (throwOnError) {
          if (unavailable) {
            throw const ReportArchiveUnavailableException();
          }
          throw StateError('Report archive HTTP ${res.statusCode}');
        }
        return [];
      }
      final body = jsonDecode(res.body);
      if (body is Map && body['reports'] is List) {
        return (body['reports'] as List)
            .map(
              (item) => ReportArchiveEntry.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
      }
      if (throwOnError) {
        throw StateError('Report archive response is unavailable');
      }
    } catch (e) {
      AppLogger.e('ClubService.getReportArchive', 'Request failed', e);
      if (throwOnError) rethrow;
    }
    return [];
  }

  /// Fetches yellow/red cards for a match (included in the single-match GET).
  Future<List<MatchCard>> getMatchCards(String matchId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/matches.php?id=${Uri.encodeComponent(matchId)}'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      final cards = body is Map && body['match'] is Map ? body['match']['cards'] : null;
      if (cards is List) {
        return cards.map((j) => MatchCard.fromJson(j as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getMatchCards', 'Request failed', e);
    }
    return [];
  }

  /// Replaces the full set of cards for a match.
  Future<bool> saveMatchCards(String matchId, List<MatchCard> cards) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/matches.php'),
              headers: _h,
              body: jsonEncode({
                'action': 'cards',
                'match_id': matchId,
                'cards': cards.map((c) => c.toJson()).toList(),
              }))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.saveMatchCards', 'Request failed', e);
    }
    return false;
  }

  Future<List<MatchParticipation>> getMatchParticipations(String matchId) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/matches.php?id=${Uri.encodeComponent(matchId)}'), headers: _h)
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      final parts = body is Map && body['match'] is Map ? body['match']['participations'] : null;
      if (parts is List) {
        return parts.map((j) => MatchParticipation.fromJson(j as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getMatchParticipations', 'Request failed', e);
    }
    return [];
  }

  /// Replaces the full set of participations for a match.
  Future<bool> saveMatchParticipations(String matchId, List<MatchParticipation> participations) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/matches.php'),
              headers: _h,
              body: jsonEncode({
                'action': 'participations',
                'match_id': matchId,
                'participations': participations.map((p) => p.toJson()).toList(),
              }))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.saveMatchParticipations', 'Request failed', e);
    }
    return false;
  }

  Future<Map<String, dynamic>?> getPlayerMatchStats(String playerId, {String? from, String? to}) async {
    try {
      final qp = <String, String>{
        'player_id': playerId,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      };
      final uri = Uri.parse('$_base/club/player-match-stats.php').replace(queryParameters: qp);
      final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['player_id'] != null) return body.cast<String, dynamic>();
    } catch (e) {
      AppLogger.e('ClubService.getPlayerMatchStats', 'Request failed', e);
    }
    return null;
  }

  Future<List<PlayerCompetitionStats>> getPlayerMatchStatsByCompetition(
    String playerId, {
    int? seasonId,
    int? competitionId,
    String? from,
    String? to,
  }) async {
    try {
      final qp = <String, String>{
        'player_id': playerId,
        if (seasonId != null) 'season_id': '$seasonId',
        if (competitionId != null) 'competition_id': '$competitionId',
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      };
      final uri = Uri.parse('$_base/club/player-match-stats-by-competition.php')
          .replace(queryParameters: qp);
      final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['competitions'] is List) {
        return (body['competitions'] as List)
            .map((e) => PlayerCompetitionStats.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getPlayerMatchStatsByCompetition', 'Request failed', e);
    }
    return [];
  }

  Future<Map<String, dynamic>?> getAdminDashboard({String? date}) async {
    try {
      final qp = <String, String>{if (date != null) 'date': date};
      final uri = Uri.parse('$_base/club/admin-dashboard.php')
          .replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return body.cast<String, dynamic>();
    } catch (e) {
      AppLogger.e('ClubService.getAdminDashboard', 'Request failed', e);
    }
    return null;
  }

  /// Match-level, per-player breakdown behind the admin dashboard's stat
  /// tiles — filterable by season/competition/date range so every number
  /// can be drilled into instead of shown as a flat total.
  Future<Map<String, dynamic>?> getAdminDashboardDetails({
    int? seasonId,
    int? competitionId,
    String? from,
    String? to,
  }) async {
    try {
      final qp = <String, String>{
        if (seasonId != null) 'season_id': '$seasonId',
        if (competitionId != null) 'competition_id': '$competitionId',
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      };
      final uri = Uri.parse('$_base/club/admin-dashboard-details.php')
          .replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return body.cast<String, dynamic>();
    } catch (e) {
      AppLogger.e('ClubService.getAdminDashboardDetails', 'Request failed', e);
    }
    return null;
  }

  /// The pieces of the admin "Team Executive Report" not already covered by
  /// [getAdminDashboard]/[getAdminDashboardDetails] — match record,
  /// standings position, attendance rate, and admin-decision alerts.
  Future<Map<String, dynamic>?> getAdminExecutiveReport({
    String? from,
    String? to,
  }) async {
    try {
      final qp = <String, String>{
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      };
      final uri = Uri.parse('$_base/club/admin-executive-report.php')
          .replace(queryParameters: qp.isEmpty ? null : qp);
      final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return body.cast<String, dynamic>();
    } catch (e) {
      AppLogger.e('ClubService.getAdminExecutiveReport', 'Request failed', e);
    }
    return null;
  }

  /// Non-clinical, management-facing report for one player — profile,
  /// composite readiness status, attendance, matches/minutes, discipline,
  /// and a coach-safe injury/physio summary, with a previous-period
  /// comparison. Per-competition stats come from
  /// [getPlayerMatchStatsByCompetition] instead of being duplicated here.
  Future<Map<String, dynamic>?> getAdminPlayerReport(
    String playerId, {
    String? from,
    String? to,
  }) async {
    try {
      final qp = <String, String>{
        'player_id': playerId,
        if (from != null) 'from': from,
        if (to != null) 'to': to,
      };
      final uri = Uri.parse('$_base/club/admin-player-report.php')
          .replace(queryParameters: qp);
      final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return body.cast<String, dynamic>();
    } catch (e) {
      AppLogger.e('ClubService.getAdminPlayerReport', 'Request failed', e);
    }
    return null;
  }

  Future<Map<String, dynamic>?> getPlayerFullReport(String playerId) async {
    try {
      final uri = Uri.parse('$_base/club/player-full-report.php')
          .replace(queryParameters: {'player_id': playerId});
      final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map && body['success'] == true) return body.cast<String, dynamic>();
    } catch (e) {
      AppLogger.e('ClubService.getPlayerFullReport', 'Request failed', e);
    }
    return null;
  }

  // ── Coach Evaluations ──────────────────────────────────────────────────────

  Future<List<CoachEvaluation>> getEvaluations({String? sessionId, String? matchId}) async {
    try {
      final params = <String, String>{};
      if (sessionId != null) params['session_id'] = sessionId;
      if (matchId   != null) params['match_id']   = matchId;
      final uri = Uri.parse('$_base/evaluations.php').replace(queryParameters: params);
      final res = await http.get(uri, headers: _h).timeout(const Duration(seconds: 8));
      final body = jsonDecode(res.body);
      if (body is Map && body['evaluations'] is List) {
        return (body['evaluations'] as List)
            .map((j) => CoachEvaluation.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      AppLogger.e('ClubService.getEvaluations', 'Request failed', e);
    }
    return [];
  }

  Future<bool> saveEvaluation(CoachEvaluation eval) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/evaluations.php'), headers: _h, body: jsonEncode(eval.toJson()))
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      return body is Map && body['success'] == true;
    } catch (e) {
      AppLogger.e('ClubService.saveEvaluation', 'Request failed', e);
    }
    return false;
  }

  // ── Dashboard Stats ────────────────────────────────────────────────────────

  Future<DashboardStats> getDashboardStats() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/coach/monitoring/dashboard.php'), headers: _h)
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic> && body['success'] == true) {
        return DashboardStats.fromJson(body);
      }
    } catch (e) {
      AppLogger.e('ClubService.getDashboardStats', 'Request failed', e);
    }
    return DashboardStats();
  }
}
