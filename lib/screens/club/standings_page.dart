import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import 'standings_edit_page.dart';

/// Read-only league table — visible to every role (players, coaches, doctors,
/// all staff). Admin/management get an edit action; everyone else just reads.
class StandingsPage extends StatefulWidget {
  const StandingsPage({super.key});

  @override
  State<StandingsPage> createState() => _StandingsPageState();
}

class _StandingsPageState extends State<StandingsPage> {
  List<StandingCompetition> _competitions = [];
  List<StandingRow> _rows = [];
  int? _selectedCompetitionId;
  bool _loading = true;
  bool _loadingTable = false;

  String _t(String key) => AppLocalizations.get(key);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final competitions = await ApiService.getStandingsCompetitions();
    if (!mounted) return;
    final selected = competitions.isNotEmpty ? competitions.first.id : null;
    setState(() {
      _competitions = competitions;
      _selectedCompetitionId = selected;
      _loading = false;
    });
    if (selected != null) await _loadTable(selected);
  }

  Future<void> _loadTable(int competitionId) async {
    setState(() => _loadingTable = true);
    final rows = await ApiService.getStandingsTable(competitionId);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loadingTable = false;
    });
  }

  Future<void> _selectCompetition(int? id) async {
    if (id == null || id == _selectedCompetitionId) return;
    setState(() => _selectedCompetitionId = id);
    await _loadTable(id);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: getAppLanguage() == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: Text(_t('standings_title'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
          iconTheme: const IconThemeData(color: AppColors.foreground),
          actions: [
            if (canManageStandings && _selectedCompetitionId != null)
              IconButton(
                icon: const Icon(Icons.edit_rounded, color: AppColors.primary),
                onPressed: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => StandingsEditPage(
                        competitionId: _selectedCompetitionId!,
                        competitionName: _competitions
                            .firstWhere((c) => c.id == _selectedCompetitionId)
                            .name,
                        initialRows: _rows,
                      ),
                    ),
                  );
                  if (saved == true) await _loadTable(_selectedCompetitionId!);
                },
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _competitions.isEmpty
                ? _empty(_t('standings_no_competitions'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _competitionPicker(),
                      const SizedBox(height: 16),
                      if (_loadingTable)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                        )
                      else if (_rows.isEmpty)
                        _empty(_t('standings_empty'))
                      else
                        _table(),
                    ],
                  ),
      ),
    );
  }

  Widget _competitionPicker() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in _competitions) ...[
            _chip(c),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _chip(StandingCompetition c) {
    final selected = c.id == _selectedCompetitionId;
    return GestureDetector(
      onTap: () => _selectCompetition(c.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.13) : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          c.name,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.foreground,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _table() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 38,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 44,
          columnSpacing: 16,
          horizontalMargin: 12,
          headingTextStyle: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w800),
          dataTextStyle: const TextStyle(color: AppColors.foreground, fontSize: 12, fontWeight: FontWeight.w600),
          columns: [
            DataColumn(label: Text(_t('standings_pos'))),
            DataColumn(label: Text(_t('standings_team'))),
            DataColumn(label: Text(_t('standings_played')), numeric: true),
            DataColumn(label: Text(_t('standings_won')), numeric: true),
            DataColumn(label: Text(_t('standings_drawn')), numeric: true),
            DataColumn(label: Text(_t('standings_lost')), numeric: true),
            DataColumn(label: Text(_t('standings_gf')), numeric: true),
            DataColumn(label: Text(_t('standings_ga')), numeric: true),
            DataColumn(label: Text(_t('standings_gd')), numeric: true),
            DataColumn(label: Text(_t('standings_pts')), numeric: true),
          ],
          rows: _rows
              .map((r) => DataRow(
                    color: r.isOwnTeam
                        ? WidgetStateProperty.all(AppColors.primary.withOpacity(0.08))
                        : null,
                    cells: [
                      DataCell(Text('${r.position}')),
                      DataCell(Text(r.teamName,
                          style: TextStyle(
                              fontWeight: r.isOwnTeam ? FontWeight.w900 : FontWeight.w600,
                              color: r.isOwnTeam ? AppColors.primary : AppColors.foreground))),
                      DataCell(Text('${r.played}')),
                      DataCell(Text('${r.won}')),
                      DataCell(Text('${r.drawn}')),
                      DataCell(Text('${r.lost}')),
                      DataCell(Text('${r.goalsFor}')),
                      DataCell(Text('${r.goalsAgainst}')),
                      DataCell(Text('${r.goalDifference}')),
                      DataCell(Text('${r.points}', style: const TextStyle(fontWeight: FontWeight.w900))),
                    ],
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _empty(String message) => Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.emoji_events_outlined, color: AppColors.foreground.withOpacity(0.18), size: 48),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 14)),
          ],
        ),
      );
}
