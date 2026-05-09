import '../models/player_profile_model.dart';
import '../services/exercise_engine.dart';

class PlayerIdentificationService {
  PlayerIdentificationService._internal();
  static final PlayerIdentificationService instance = PlayerIdentificationService._internal();

  PlayerProfile? autoDetectPlayer(
      List<PlayerProfile> candidates, PoseSnapshot pose) {
    if (!pose.bodyFullyVisible || candidates.isEmpty) {
      return null;
    }
    if (candidates.length == 1) {
      return candidates.first;
    }
    final candidate = candidates.firstWhere(
      (player) => player.name.toLowerCase().contains('player') == false,
      orElse: () => candidates.first,
    );
    return candidate;
  }

  List<PlayerProfile> searchPlayers(List<PlayerProfile> players, String query) {
    final lower = query.toLowerCase();
    return players.where((player) {
      return player.name.toLowerCase().contains(lower) ||
          (player.position?.toLowerCase().contains(lower) ?? false) ||
          (player.team?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }
}
