import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../models/club_models.dart';

/// Returns the semantic color for a [PlayerStatus].
/// Single source of truth — replaces duplicated _statusColor helpers
/// in club_dashboard, player_management, and club_player_profile_page.
Color clubStatusColor(PlayerStatus s) {
  switch (s) {
    case PlayerStatus.active:     return AppColors.success;
    case PlayerStatus.injured:    return AppColors.destructive;
    case PlayerStatus.recovering: return AppColors.warning;
    case PlayerStatus.inactive:   return AppColors.muted;
    case PlayerStatus.suspended:  return const Color(0xFFf59e0b);
  }
}
