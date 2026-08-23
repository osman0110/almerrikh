/// Unified auth user model.
/// Handles both naming conventions so the app works with local and live API:
///   role ↔ account_type   |   name ↔ full_name   |   club_user_id ↔ club_id
class AuthUser {
  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String role;         // 'club' | 'player'
  final String? orgRole;     // 'owner' | 'admin' | 'coach' | 'staff' — org members only
  final String? playerType;  // 'independent' | 'club'
  final String? linkedPlayerId;
  final int? clubUserId;
  final String? trialStartedAt;
  final String? trialEndsAt;
  final int? trialDaysRemaining;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatarUrl,
    required this.role,
    this.orgRole,
    this.playerType,
    this.linkedPlayerId,
    this.clubUserId,
    this.trialStartedAt,
    this.trialEndsAt,
    this.trialDaysRemaining,
  });

  factory AuthUser.fromMap(Map<String, dynamic> m) {
    // Accept both naming conventions
    final role = (m['role'] ?? m['account_type'] ?? 'club') as String;
    final name = (m['name'] ?? m['full_name'] ?? '') as String;
    final rawClubId = m['club_user_id'] ?? m['club_id'];
    final int? clubUserId = rawClubId == null
        ? null
        : rawClubId is int
            ? rawClubId
            : int.tryParse(rawClubId.toString());
    return AuthUser(
      id:                   (m['id'] as num).toInt(),
      name:                 name,
      email:                (m['email'] ?? '') as String,
      phone:                m['phone'] as String?,
      avatarUrl:            m['avatar_url'] as String?,
      role:                 role,
      orgRole:              m['org_role'] as String?,
      playerType:           m['player_type'] as String?,
      linkedPlayerId:       m['linked_player_id'] as String?,
      clubUserId:           clubUserId,
      trialStartedAt:       m['trial_started_at'] as String?,
      trialEndsAt:          m['trial_ends_at'] as String?,
      trialDaysRemaining:   m['trial_days_remaining'] is int
                               ? m['trial_days_remaining'] as int
                               : int.tryParse(
                                   m['trial_days_remaining']?.toString() ?? ''),
    );
  }
}
