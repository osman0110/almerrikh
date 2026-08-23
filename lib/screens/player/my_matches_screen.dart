import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import 'player_dashboard.dart' show PlayerShell, PlayerPageHeader;
import 'session_widgets.dart' show WellnessDetailRow;

/// Read-only list of the club matches the player is part of.
class MyMatchesScreen extends StatefulWidget {
  const MyMatchesScreen({super.key});

  @override
  State<MyMatchesScreen> createState() => _MyMatchesScreenState();
}

bool _isMatchFinished(MatchModel m) => m.status == 'completed' || m.status == 'cancelled';

const int _kFinishedPageSize = 5;

class _MyMatchesScreenState extends State<MyMatchesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  List<MatchModel> _matches = [];
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
      final matches = await ApiService.getMyMatches();
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  List<MatchModel> get _upcoming {
    final list = _matches.where((m) => !_isMatchFinished(m)).toList()
      ..sort((a, b) => a.matchDate.compareTo(b.matchDate));
    return list;
  }

  List<MatchModel> get _finished {
    final list = _matches.where(_isMatchFinished).toList()
      ..sort((a, b) => b.matchDate.compareTo(a.matchDate));
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
      currentIndex: 2,
      child: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          children: [
            PlayerPageHeader(title: AppLocalizations.get('my_matches_title')),
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
                              _buildMatchList(_upcoming, AppLocalizations.get('my_matches_empty')),
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

  Widget _buildMatchList(List<MatchModel> matches, String emptyLabel) {
    if (matches.isEmpty) return _EmptyState(label: emptyLabel);
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: matches.length,
      itemBuilder: (_, i) => _MatchTile(match: matches[i]),
    );
  }

  Widget _buildFinishedTab() {
    final finished = _finished;
    final filtered = _finishedDateFilter == null
        ? finished
        : finished.where((m) => _sameDay(m.matchDate, _finishedDateFilter!)).toList();
    final showingLimited = _finishedDateFilter == null && finished.length > _kFinishedPageSize;
    final visible = _finishedDateFilter == null
        ? filtered.take(_kFinishedPageSize).toList()
        : filtered;

    return Column(
      children: [
        _DateFilterBar(
          selectedDate: _finishedDateFilter,
          hint: showingLimited ? AppLocalizations.get('pick_date_for_more') : null,
          onPick: _pickFinishedDate,
          onClear: () => setState(() => _finishedDateFilter = null),
        ),
        Expanded(
          child: visible.isEmpty
              ? _EmptyState(
                  label: AppLocalizations.get(
                      _finishedDateFilter != null ? 'no_results_for_date' : 'my_matches_empty'),
                )
              : _buildMatchList(visible, AppLocalizations.get('my_matches_empty')),
        ),
      ],
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match});
  final MatchModel match;

  Color get _statusColor {
    switch (match.status) {
      case 'completed': return AppColors.muted;
      case 'cancelled':  return AppColors.destructive;
      default:           return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = match.matchDate;
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
                  AppLocalizations.format('match_vs', {'opponent': match.opponent}),
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
                  match.statusLabel,
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
              Text(match.matchTime, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (match.location != null && match.location!.isNotEmpty) ...[
                const SizedBox(width: 14),
                const Icon(Icons.location_on_rounded, size: 14, color: AppColors.muted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(match.location!,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
          if (match.competitionName != null && match.competitionName!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(match.competitionName!, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
          ],
          if (match.myYellowCards > 0 || match.myRedCards > 0) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (match.myYellowCards > 0) Text('🟨 ${match.myYellowCards}', style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w800)),
              if (match.myRedCards > 0) Text('🟥 ${match.myRedCards}', style: const TextStyle(color: AppColors.destructive, fontWeight: FontWeight.w800)),
            ]),
          ],
          const SizedBox(height: 12),
          WellnessDetailRow(
            icon: Icons.self_improvement_rounded,
            label: AppLocalizations.get('before_match_label'),
            done: _hooperDoneChip,
            score: match.hooperScore,
            actionable: _showHooper,
            isRequired: match.wellnessRequired,
            onTap: () => Navigator.of(context).pushNamed(
                '/player/monitoring/hooper?sessionId=${match.id}'),
          ),
          const SizedBox(height: 8),
          WellnessDetailRow(
            icon: Icons.speed_rounded,
            label: AppLocalizations.get('after_match_label'),
            done: _rpeDoneChip,
            score: match.rpeScore,
            actionable: _showRpe,
            isRequired: match.rpeRequired,
            onTap: () => Navigator.of(context).pushNamed(
                '/player/monitoring/rpe?sessionId=${match.id}'
                '&durationMinutes=${match.myMinutes}'),
          ),
        ],
      ),
    );
  }

  /// RPE stays open through the match day plus one extra day, then locks.
  bool get _withinRpeWindow {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(match.matchDate.year, match.matchDate.month, match.matchDate.day);
    final diff = today.difference(d).inDays;
    return diff >= 0 && diff <= 1;
  }

  bool get _showHooper =>
      match.wellnessRequired &&
      match.status != 'cancelled' &&
      match.status != 'completed' &&
      !match.wellnessDone &&
      _isHooperAvailable(_eventStart);

  bool get _showRpe =>
      match.rpeRequired &&
      match.status != 'cancelled' &&
      match.myMinutes != null &&
      match.myMinutes! > 0 &&
      _withinRpeWindow &&
      DateTime.now().isAfter(_eventEnd) &&
      !match.rpeDone;

  DateTime get _eventStart => _combineDate(match.matchDate, match.matchTime);

  DateTime get _eventEnd => _eventStart.add(const Duration(minutes: 105));

  bool get _hooperDoneChip =>
      match.wellnessRequired && match.wellnessDone && match.status != 'cancelled';

  bool get _rpeDoneChip =>
      match.rpeRequired && match.rpeDone && match.status != 'cancelled';
}

DateTime _combineDate(DateTime date, String time) {
  final parts = time.split(':');
  return DateTime(date.year, date.month, date.day,
      int.tryParse(parts.first) ?? 16,
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
