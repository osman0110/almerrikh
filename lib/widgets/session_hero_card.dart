import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/sessions_models.dart';
import '../models/club_models.dart' as cm;
import '../app_colors.dart';
import '../app_localizations.dart';

// ── Design tokens (Al Merrikh SC identity) ───────────────────────────────────
const _dark        = Color(0xFF4A000D);   // AppColors.maroonDark — deep maroon
const _lime        = Color(0xFFF7B638);   // AppColors.gold — premium gold
const _onDark      = Color(0xFFFFFFFF);   // AppColors.onDark — white on maroon
const _onDarkMuted = Color(0xFFF6F2E9);   // warm cream on maroon

TextStyle _cairoBold(double s, {FontWeight w = FontWeight.w700, Color? c}) =>
    GoogleFonts.cairo(fontSize: s, fontWeight: w, color: c ?? _onDark);

TextStyle _cairoSemiBold(double s, {FontWeight w = FontWeight.w600, Color? c}) =>
    GoogleFonts.cairo(fontSize: s, fontWeight: w, color: c ?? _onDark);

TextStyle _cairoMedium(double s, {FontWeight w = FontWeight.w500, Color? c}) =>
    GoogleFonts.cairo(fontSize: s, fontWeight: w, color: c ?? _onDarkMuted);

// ─────────────────────────────────────────────────────────────────────────────
// SessionHeroCard
// ─────────────────────────────────────────────────────────────────────────────

class SessionHeroCard extends StatelessWidget {
  const SessionHeroCard({
    super.key,
    required this.title,
    required this.startTime,
    required this.location,
    required this.durationMin,
    required this.playerCount,
    required this.onTap,
    this.isActive    = false,
    this.endTime,
    this.presentCount = 0,
    this.coachName = '',
    this.dashboardStyle = false,
    this.type        = SessionType.team_training,
    this.scope       = SessionScope.team,
    this.status      = SessionStatus.scheduled,
    this.aiEnabled   = false,
  });

  final String         title;
  final String         startTime;
  final String         location;
  final int            durationMin;
  final int            playerCount;
  final VoidCallback   onTap;
  final bool           isActive;
  final String?        endTime;
  final int            presentCount;
  final String         coachName;
  final bool           dashboardStyle;
  final SessionType    type;
  final SessionScope   scope;
  final SessionStatus  status;
  final bool           aiEnabled;

  // ── Factory helpers ───────────────────────────────────────────────────────

  /// Build from a full SessionModel (sessions screen)
  factory SessionHeroCard.fromSession({
    required SessionModel session,
    required VoidCallback onTap,
    Key? key,
  }) =>
      SessionHeroCard(
        key:          key,
        title:        session.title,
        startTime:    session.startTime,
        endTime:      session.endTime,
        location:     session.location,
        durationMin:  session.durationMin,
        playerCount:  session.playerCount,
        coachName:    session.coachName ?? '',
        isActive:     session.status == SessionStatus.active,
        type:         session.type,
        scope:        session.scope,
        status:       session.status,
        aiEnabled:    session.aiEnabled,
        onTap:        onTap,
      );

  /// Build from a TrainingSession (club_dashboard / session_list_page)
  factory SessionHeroCard.fromTrainingSession({
    required cm.TrainingSession session,
    required VoidCallback onTap,
    Key? key,
  }) {
    final mappedStatus = switch (session.status) {
      'active' => SessionStatus.active,
      'completed' => SessionStatus.completed,
      'cancelled' => SessionStatus.cancelled,
      _ => SessionStatus.scheduled,
    };
    return SessionHeroCard(
      key:         key,
      title:       session.name,
      // The actual time the coach set — session.date is just the calendar
      // day (always midnight), never the start time. Reading date.hour/
      // minute here was always 00:00, which is why every session used to
      // show the same fallback time regardless of what was entered.
      startTime:   session.startTime,
      endTime:     session.endTime,
      location:    session.location ?? AppLocalizations.get('location_not_set'),
      durationMin: session.durationMin,
      playerCount: session.playerIds.length,
      presentCount: session.completedPlayerIds.length,
      coachName:   session.coachName,
      isActive:    session.status == 'active',
      type:        _mapClubType(session.type),
      scope:       SessionScope.team,
      status:      mappedStatus,
      aiEnabled:   false,
      dashboardStyle: true,
      onTap:       onTap,
    );
  }

  static SessionType _mapClubType(cm.SessionType t) {
    switch (t) {
      case cm.SessionType.physicalAssessment: return SessionType.performance_test;
      case cm.SessionType.strength:           return SessionType.strength_gym;
      case cm.SessionType.mobility:           return SessionType.recovery;
      case cm.SessionType.recovery:           return SessionType.recovery;
      case cm.SessionType.injuryPrevention:   return SessionType.rehab;
      case cm.SessionType.goalkeeper:         return SessionType.goalkeeper;
      case cm.SessionType.positionSpecific:   return SessionType.position_specific;
      case cm.SessionType.individual:         return SessionType.individual;
      case cm.SessionType.rehab:              return SessionType.rehab;
      case cm.SessionType.match:              return SessionType.match;
      case cm.SessionType.preMatch:           return SessionType.pre_match_activation;
      case cm.SessionType.postMatch:          return SessionType.post_match_recovery;
      case cm.SessionType.tactical:           return SessionType.tactical;
      case cm.SessionType.technical:          return SessionType.technical;
      case cm.SessionType.fitness:            return SessionType.fitness;
      case cm.SessionType.speedAgility:       return SessionType.speed_agility;
      case cm.SessionType.teamTraining:       return SessionType.team_training;
      case cm.SessionType.custom:             return SessionType.team_training;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dashboardStyle) {
      return _buildDashboardCard(context);
    }

    final typeColor = getSessionTypeColor(type);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color:        _dark,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Eyebrow ──────────────────────────────────────────────────────
            Row(
              children: [
                if (isActive) ...[
                  const _PulseDot(),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.get('session_active_now_label'),
                      style: _cairoMedium(12, w: FontWeight.w700, c: _lime)),
                ] else ...[
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: typeColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.get('session_today_label'),
                      style: _cairoMedium(12, w: FontWeight.w600, c: _onDarkMuted)),
                ],
                const Spacer(),
                _StatusBadge(status: status, isActive: isActive),
              ],
            ),
            const SizedBox(height: 16),

            // ── Main content row ─────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type icon — first = RIGHT in RTL
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color:        typeColor.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(12),
                    border:       Border.all(color: typeColor.withOpacity(0.40)),
                  ),
                  child: Icon(
                      getSessionTypeIcon(type), color: typeColor, size: 24),
                ),
                const SizedBox(width: 14),

                // Title + tags
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: _cairoSemiBold(17, w: FontWeight.w700, c: _onDark),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _MiniTag(
                              label: getSessionTypeLabel(type),
                              color: typeColor),
                          _MiniTag(
                              label: getSessionScopeLabel(scope),
                              color: AppColors.success),
                          if (aiEnabled)
                            _MiniTag(label: 'AI', color: _lime),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Time — last = LEFT in RTL
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(AppLocalizations.get('starts_at_label'),
                        style: _cairoMedium(9.5, c: _onDarkMuted)),
                    const SizedBox(height: 2),
                    Text(startTime,
                        style: _cairoBold(26, w: FontWeight.w800, c: isActive ? _lime : _onDark)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Divider ───────────────────────────────────────────────────────
            Divider(color: Colors.white.withOpacity(0.09), height: 1),
            const SizedBox(height: 10),

            // ── Meta row ─────────────────────────────────────────────────────
            Row(
              children: [
                _MetaChip(
                    icon: Icons.timer_rounded,
                    label: '$durationMin ${AppLocalizations.get('minutes_unit_label')}'),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetaChip(
                      icon: Icons.location_on_rounded,
                      label: location,
                      clip:  true),
                ),
                const SizedBox(width: 10),
                _MetaChip(
                    icon: Icons.group_rounded,
                    label: '$playerCount ${AppLocalizations.get('players_unit_label')}'),
              ],
            ),
            const SizedBox(height: 14),

            // ── CTA Button ────────────────────────────────────────────────────
            _HeroActionButton(
              isActive: isActive,
              onTap:    onTap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard(BuildContext context) {
    final locationLabel = location.trim().isNotEmpty
        ? location
        : AppLocalizations.get('location_not_set');
    final timeRange = endTime != null && endTime!.trim().isNotEmpty
        ? '$startTime – $endTime'
        : startTime;

    final statusKey = switch (status) {
      SessionStatus.active => 'status_active',
      SessionStatus.completed => 'status_completed',
      SessionStatus.cancelled => 'status_cancelled',
      _ => 'status_scheduled',
    };
    final actionKey = switch (status) {
      SessionStatus.active => 'open_session_btn',
      SessionStatus.completed => 'view_report_btn',
      SessionStatus.cancelled => 'view_details_btn',
      _ => 'start_session_btn',
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.maroon,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  AppLocalizations.get('today_session'),
                  style: const TextStyle(
                    color: AppColors.onDarkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.18)),
                  ),
                  child: Text(
                    AppLocalizations.get(statusKey),
                    style: const TextStyle(
                      color: AppColors.onDark,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.onDark,
                fontWeight: FontWeight.w800,
                fontSize: 17,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _DashboardMeta(
                  icon: Icons.schedule_rounded,
                  label: timeRange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DashboardMeta(
                    icon: Icons.location_on_rounded,
                    label: locationLabel,
                    clip: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _DashboardMeta(
                  icon: Icons.group_rounded,
                  label:
                      '${AppLocalizations.get('expected_players')}: $playerCount',
                ),
                const SizedBox(width: 12),
                _DashboardMeta(
                  icon: Icons.check_circle_outline_rounded,
                  label:
                      '${AppLocalizations.get('present_players')}: $presentCount',
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _DashboardMeta(
                    icon: Icons.person_outline_rounded,
                    label: coachName.trim().isNotEmpty
                        ? coachName
                        : AppLocalizations.get('coach_label'),
                    clip: true,
                  ),
                ),
                const SizedBox(width: 12),
                _DashboardMeta(
                  icon: Icons.fitness_center_rounded,
                  label: getSessionTypeLabel(type),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: double.infinity,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppLocalizations.get(actionKey),
                      style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Directionality.of(context) == TextDirection.rtl
                          ? Icons.arrow_back_rounded
                          : Icons.arrow_forward_rounded,
                      color: AppColors.foreground,
                      size: 17,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DashboardMeta extends StatelessWidget {
  const _DashboardMeta({
    required this.icon,
    required this.label,
    this.clip = false,
  });

  final IconData icon;
  final String label;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.onDarkMuted, size: 11),
        const SizedBox(width: 4),
        if (clip)
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.onDarkMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          Text(
            label,
            style: const TextStyle(
              color: AppColors.onDarkMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.isActive});
  final SessionStatus status;
  final bool          isActive;

  @override
  Widget build(BuildContext context) {
    final label = getSessionStatusLabel(status);
    final c     = isActive ? AppColors.success : _onDarkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        c.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border:       Border.all(color: c.withOpacity(0.45), width: 1.2),
      ),
      child: Text(label,
          style: _cairoMedium(9, w: FontWeight.w700, c: c)),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color});
  final String label;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border:       Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label, style: _cairoMedium(9.5, w: FontWeight.w600, c: color)),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(
      {required this.icon, required this.label, this.clip = false});
  final IconData icon;
  final String   label;
  final bool     clip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _onDarkMuted, size: 13),
        const SizedBox(width: 5),
        if (clip)
          Flexible(
            child: Text(label,
                style: _cairoMedium(10.5, c: _onDarkMuted),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          )
        else
          Text(label, style: _cairoMedium(10.5, c: _onDarkMuted)),
      ],
    );
  }
}

class _HeroActionButton extends StatefulWidget {
  const _HeroActionButton({required this.isActive, required this.onTap});
  final bool         isActive;
  final VoidCallback onTap;

  @override
  State<_HeroActionButton> createState() => _HeroActionButtonState();
}

class _HeroActionButtonState extends State<_HeroActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.isActive
        ? AppLocalizations.get('continue_session_label')
        : AppLocalizations.get('start_session_label');
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale:    _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Container(
          width:   double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color:        _lime,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _lime.withOpacity(0.20),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Label — first in RTL = RIGHT
              Text(label, style: _cairoBold(14, w: FontWeight.w700, c: _dark)),
              const SizedBox(width: 8),
              // Maroon circle icon — last in RTL = LEFT
              Container(
                width: 26, height: 26,
                decoration: const BoxDecoration(
                    color: _dark, shape: BoxShape.circle),
                child: Icon(
                  widget.isActive
                      ? Icons.play_arrow_rounded
                      : Icons.play_circle_rounded,
                  color: _lime, size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pulse dot animation ───────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width:  8,
        height: 8,
        decoration: BoxDecoration(
          shape:     BoxShape.circle,
          color:     _lime,
          boxShadow: [
            BoxShadow(
              color:      _lime.withOpacity(0.25 + 0.45 * _ctrl.value),
              blurRadius: 5 + 5 * _ctrl.value,
            ),
          ],
        ),
      ),
    );
  }
}
