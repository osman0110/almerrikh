import 'dart:async';

import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/survey_reminder_service.dart';
import 'player_dashboard.dart' show PlayerShell, PlayerPageHeader;
import 'session_widgets.dart' show WellnessDetailRow;

/// Unified read-only agenda for training and medical/treatment sessions.
class MySessionsScreen extends StatefulWidget {
  const MySessionsScreen({super.key});

  @override
  State<MySessionsScreen> createState() => _MySessionsScreenState();
}

bool _isSessionFinished(TrainingSession s) =>
    s.status == 'completed' || s.status == 'cancelled';

bool _isMedicalFinished(Map<String, dynamic> s) {
  final status = (s['status'] ?? '').toString();
  return status == 'completed' || status == 'cancelled' || status == 'no_show';
}

DateTime? _medicalSessionDate(Map<String, dynamic> s) =>
    DateTime.tryParse((s['scheduled_at'] ?? '').toString());

const int _kFinishedPageSize = 5;

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _MySessionsScreenState extends State<MySessionsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  List<TrainingSession> _sessions = [];
  List<Map<String, dynamic>> _medicalSessions = [];
  bool _loading = true;
  bool _loadFailed = false;
  DateTime? _finishedDateFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final results = await Future.wait([
        ApiService.getMyClubSessions(),
        ApiService.getMyPhysioSessions(),
      ]);
      if (!mounted) return;
      List<MatchModel> matches = [];
      try {
        matches = await ApiService.getMyMatches();
      } catch (_) {
        // Match loading is only needed here to refresh local reminders.
      }
      setState(() {
        _sessions = results[0] as List<TrainingSession>;
        _medicalSessions = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
      unawaited(SurveyReminderService.sync(
        sessions: results[0] as List<TrainingSession>,
        matches: matches,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  List<TrainingSession> get _upcomingSessions {
    final list = _sessions.where((s) => !_isSessionFinished(s)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  List<TrainingSession> get _finishedSessions {
    final list = _sessions.where(_isSessionFinished).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  List<Map<String, dynamic>> get _upcomingMedical {
    final list = _medicalSessions.where((s) => !_isMedicalFinished(s)).toList()
      ..sort((a, b) {
        final da = _medicalSessionDate(a);
        final db = _medicalSessionDate(b);
        if (da == null || db == null) return 0;
        return da.compareTo(db);
      });
    return list;
  }

  List<Map<String, dynamic>> get _finishedMedical {
    final list = _medicalSessions.where(_isMedicalFinished).toList()
      ..sort((a, b) {
        final da = _medicalSessionDate(a);
        final db = _medicalSessionDate(b);
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });
    return list;
  }

  Future<void> _pickFinishedDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _finishedDateFilter ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.primary, surface: AppColors.card),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _finishedDateFilter = picked);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return PlayerShell(
      currentIndex: 1,
      child: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          children: [
            PlayerPageHeader(title: AppLocalizations.get('my_sessions_agenda_title')),
            if (!_loading && !_loadFailed) _buildTabBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primary,
                backgroundColor: AppColors.card,
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _loadFailed
                        ? _PlayerListLoadError(onRetry: _load)
                        : TabBarView(
                            controller: _tab,
                            children: [
                              _buildUpcomingTab(),
                              _buildFinishedTab(),
                            ],
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Material(
      color: AppColors.background,
      child: TabBar(
        controller: _tab,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.primary,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        tabs: [
          Tab(text: AppLocalizations.get('tab_upcoming')),
          Tab(text: AppLocalizations.get('tab_finished')),
        ],
      ),
    );
  }

  Widget _buildUpcomingTab() {
    final sessions = _upcomingSessions;
    final medical = _upcomingMedical;
    if (sessions.isEmpty && medical.isEmpty) {
      return _EmptyState(label: AppLocalizations.get('my_sessions_empty'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (sessions.isNotEmpty) ...[
          _SectionTitle(AppLocalizations.get('my_training_sessions_section')),
          ...sessions.map((s) => _SessionTile(session: s, onChanged: _load)),
        ],
        if (medical.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionTitle(AppLocalizations.get('my_medical_sessions_section')),
          ...medical.map((s) => _MedicalSessionTile(session: s)),
        ],
      ],
    );
  }

  Widget _buildFinishedTab() {
    final finishedSessions = _finishedSessions;
    final finishedMedical = _finishedMedical;

    final filteredSessions = _finishedDateFilter == null
        ? finishedSessions
        : finishedSessions.where((s) => _sameDay(s.date, _finishedDateFilter!)).toList();
    final filteredMedical = _finishedDateFilter == null
        ? finishedMedical
        : finishedMedical.where((s) {
            final d = _medicalSessionDate(s);
            return d != null && _sameDay(d, _finishedDateFilter!);
          }).toList();

    final showingLimited = _finishedDateFilter == null &&
        (finishedSessions.length > _kFinishedPageSize || finishedMedical.length > _kFinishedPageSize);

    final visibleSessions = _finishedDateFilter == null
        ? filteredSessions.take(_kFinishedPageSize).toList()
        : filteredSessions;
    final visibleMedical = _finishedDateFilter == null
        ? filteredMedical.take(_kFinishedPageSize).toList()
        : filteredMedical;

    return Column(
      children: [
        _DateFilterBar(
          selectedDate: _finishedDateFilter,
          hint: showingLimited ? AppLocalizations.get('pick_date_for_more') : null,
          onPick: _pickFinishedDate,
          onClear: () => setState(() => _finishedDateFilter = null),
        ),
        Expanded(
          child: visibleSessions.isEmpty && visibleMedical.isEmpty
              ? _EmptyState(
                  label: AppLocalizations.get(
                      _finishedDateFilter != null ? 'no_results_for_date' : 'my_sessions_empty'),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (visibleSessions.isNotEmpty) ...[
                      _SectionTitle(AppLocalizations.get('my_training_sessions_section')),
                      ...visibleSessions.map((s) => _SessionTile(session: s, onChanged: _load)),
                    ],
                    if (visibleMedical.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _SectionTitle(AppLocalizations.get('my_medical_sessions_section')),
                      ...visibleMedical.map((s) => _MedicalSessionTile(session: s)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _DateFilterBar extends StatelessWidget {
  const _DateFilterBar({
    required this.selectedDate,
    required this.hint,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? selectedDate;
  final String? hint;
  final VoidCallback onPick;
  final VoidCallback onClear;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          InkWell(
            onTap: onPick,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month_rounded, size: 15, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    selectedDate != null ? _fmt(selectedDate!) : AppLocalizations.get('pick_date'),
                    style: const TextStyle(color: AppColors.foreground, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          if (selectedDate != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  AppLocalizations.get('clear_date_filter'),
                  style: const TextStyle(color: AppColors.destructive, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ] else if (hint != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint!,
                style: TextStyle(color: AppColors.foreground.withOpacity(0.5), fontSize: 11.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlayerListLoadError extends StatelessWidget {
  const _PlayerListLoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: AppColors.destructive,
                size: 36,
              ),
              const SizedBox(height: 10),
              Text(
                AppLocalizations.get('error_connection'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(AppLocalizations.get('retry_btn')),
              ),
            ],
          ),
        ),
      );
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onChanged});
  final TrainingSession session;
  // Refreshes the agenda after returning from the Hooper/RPE submit screens
  // so a just-submitted entry flips to its "done" state immediately.
  final Future<void> Function() onChanged;

  Color get _statusColor {
    switch (session.status) {
      case 'active':    return AppColors.success;
      case 'completed': return AppColors.muted;
      case 'cancelled': return AppColors.destructive;
      default:          return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = session.date;
    final dateStr = '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.name,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _statusColor.withOpacity(0.3)),
                ),
                child: Text(
                  session.statusLabel,
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.muted),
              const SizedBox(width: 6),
              Text(dateStr, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(width: 14),
              const Icon(Icons.access_time_rounded, size: 14, color: AppColors.muted),
              const SizedBox(width: 6),
              Text(session.startTime, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (session.teamName != null && session.teamName!.isNotEmpty) ...[
                const SizedBox(width: 14),
                const Icon(Icons.groups_rounded, size: 14, color: AppColors.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(session.teamName!,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          WellnessDetailRow(
            icon: Icons.self_improvement_rounded,
            label: AppLocalizations.get('before_session_label'),
            done: _hooperDoneChip,
            score: session.hooperScore,
            actionable: _showHooper,
            isRequired: session.wellnessRequired,
            onTap: () => Navigator.of(context)
                .pushNamed('/player/monitoring/hooper?sessionId=${session.id}')
                .then((_) => onChanged()),
          ),
          const SizedBox(height: 8),
          WellnessDetailRow(
            icon: Icons.speed_rounded,
            label: AppLocalizations.get('after_session_label'),
            done: _rpeDoneChip,
            score: session.rpeScore,
            actionable: _showRpe,
            isRequired: session.rpeRequired,
            onTap: () => Navigator.of(context)
                .pushNamed('/player/monitoring/rpe?sessionId=${session.id}'
                    '&durationMinutes=${session.durationMin}')
                .then((_) => onChanged()),
          ),
        ],
      ),
    );
  }

  /// RPE stays open through the session day plus one extra day, then locks.
  bool get _withinRpeWindow {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(session.date.year, session.date.month, session.date.day);
    final diff = today.difference(d).inDays;
    return diff >= 0 && diff <= 1;
  }

  bool get _showHooper =>
      session.wellnessRequired &&
      session.status != 'cancelled' &&
      session.status != 'completed' &&
      !session.wellnessDone &&
      _isHooperAvailable(_eventStart);

  bool get _showRpe =>
      session.rpeRequired &&
      session.status != 'cancelled' &&
      _withinRpeWindow &&
      DateTime.now().isAfter(_eventEnd) &&
      !session.rpeDone;

  DateTime get _eventStart => _combineDate(session.date, session.startTime);

  DateTime get _eventEnd =>
      _eventStart.add(Duration(minutes: session.durationMin));

  bool get _hooperDoneChip =>
      session.wellnessRequired && session.wellnessDone && session.status != 'cancelled';

  bool get _rpeDoneChip =>
      session.rpeRequired && session.rpeDone && session.status != 'cancelled';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
        child: Text(label,
            style: const TextStyle(
                color: AppColors.foreground,
                fontSize: 14,
                fontWeight: FontWeight.w900)),
      );
}

class _MedicalSessionTile extends StatelessWidget {
  const _MedicalSessionTile({required this.session});
  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final role = (session['therapist_role'] ?? '').toString();
    final isDoctor = role == 'doctor' || session['recommendation'] == 'doctor_followup';
    final treatment = (session['treatment_type'] ?? '').toString();
    final title = isDoctor
        ? AppLocalizations.get('doctor_session_title')
        : treatment.isNotEmpty
            ? treatment
            : AppLocalizations.get('physio_sessions_title');
    final room = (session['room'] ?? '').toString();
    final bodyArea = (session['body_area'] ?? '').toString();
    final scheduledAt = (session['scheduled_at'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (isDoctor ? AppColors.warning : AppColors.risk).withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isDoctor ? Icons.local_hospital_rounded : Icons.spa_rounded,
              color: isDoctor ? AppColors.warning : AppColors.risk, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800)),
                if (scheduledAt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(scheduledAt,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
                if (room.isNotEmpty || bodyArea.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text([if (room.isNotEmpty) room, if (bodyArea.isNotEmpty) bodyArea].join(' · '),
                      style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ],
            ),
          ),
          Text(_medicalStatus(session['status']),
              style: TextStyle(
                  color: _medicalStatusColor(session['status']),
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

String _medicalStatus(dynamic value) {
  final key = 'physio_status_${(value ?? '').toString()}';
  final label = AppLocalizations.get(key);
  return label == key ? (value ?? '').toString() : label;
}

Color _medicalStatusColor(dynamic value) {
  switch ((value ?? '').toString()) {
    case 'scheduled': return AppColors.risk;
    case 'completed': return AppColors.success;
    case 'cancelled':
    case 'no_show': return AppColors.destructive;
    default: return AppColors.muted;
  }
}

DateTime _combineDate(DateTime date, String time) {
  final parts = time.split(':');
  return DateTime(date.year, date.month, date.day,
      int.tryParse(parts.first) ?? 8,
      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0);
}

bool _isHooperAvailable(DateTime eventStart) {
  final now = DateTime.now();
  final dayBefore = DateTime(eventStart.year, eventStart.month, eventStart.day - 1);
  return !now.isBefore(dayBefore) && now.isBefore(eventStart);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
    );
  }
}
