import 'dart:convert';
import '../utils/app_logger.dart';
import 'package:http/http.dart' as http;
import '../api_service.dart';
import '../app_config.dart';
import '../models/player_profile_model.dart';

const _baseUrl = kApiBase;

class PlayerService {
  PlayerService._internal();
  static final PlayerService instance = PlayerService._internal();

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (ApiService.token != null) 'Authorization': 'Bearer ${ApiService.token}',
      };

  // Returns a single-value stream so callers using StreamBuilder work unchanged.
  Stream<List<PlayerProfile>> streamPlayers() {
    return Stream.fromFuture(fetchPlayers());
  }

  Future<List<PlayerProfile>> fetchPlayers() async {
    if (ApiService.token == null) return [];
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/players.php'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = body['players'] as List<dynamic>? ?? [];
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return PlayerProfile.fromMap(m['id'] as String, m);
      }).toList();
    } catch (e) {
      AppLogger.e('PlayerService.fetchPlayers', 'Request failed', e);
      return [];
    }
  }

  Future<PlayerProfile> savePlayer(PlayerProfile profile) async {
    final id = profile.id.isEmpty
        ? 'player-${DateTime.now().millisecondsSinceEpoch}'
        : profile.id;
    final saved = profile.copyWith(id: id);

    if (ApiService.token == null) return saved;

    try {
      await http
          .post(
            Uri.parse('$_baseUrl/players.php'),
            headers: _headers,
            body: jsonEncode(saved.toMap()),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLogger.e('PlayerService.savePlayer', 'Request failed', e);
    }
    return saved;
  }

  Future<void> deletePlayer(String playerId) async {
    if (ApiService.token == null) return;
    try {
      await http
          .delete(
            Uri.parse('$_baseUrl/players.php?id=$playerId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLogger.e('PlayerService.deletePlayer', 'Request failed', e);
    }
  }

  // Kept for any legacy callers that used Firebase seedDefaultTeamsIfEmpty
  Future<void> seedDefaultTeamsIfEmpty() async {}
}
