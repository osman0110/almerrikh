import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';

/// Admin/management-only editor — bulk replace of the league table for one
/// competition (backend: POST /api/club/standings.php deletes and
/// re-inserts all rows for the competition in one transaction).
class StandingsEditPage extends StatefulWidget {
  const StandingsEditPage({
    super.key,
    required this.competitionId,
    required this.competitionName,
    required this.initialRows,
  });

  final int competitionId;
  final String competitionName;
  final List<StandingRow> initialRows;

  @override
  State<StandingsEditPage> createState() => _StandingsEditPageState();
}

class _RowControllers {
  _RowControllers(StandingRow row)
      : isOwnTeam = row.isOwnTeam,
        team = TextEditingController(text: row.teamName),
        played = TextEditingController(text: '${row.played}'),
        won = TextEditingController(text: '${row.won}'),
        drawn = TextEditingController(text: '${row.drawn}'),
        lost = TextEditingController(text: '${row.lost}'),
        gf = TextEditingController(text: '${row.goalsFor}'),
        ga = TextEditingController(text: '${row.goalsAgainst}'),
        pts = TextEditingController(text: '${row.points}');

  bool isOwnTeam;
  final TextEditingController team;
  final TextEditingController played;
  final TextEditingController won;
  final TextEditingController drawn;
  final TextEditingController lost;
  final TextEditingController gf;
  final TextEditingController ga;
  final TextEditingController pts;

  void dispose() {
    team.dispose();
    played.dispose();
    won.dispose();
    drawn.dispose();
    lost.dispose();
    gf.dispose();
    ga.dispose();
    pts.dispose();
  }

  StandingRow toRow(int position) => StandingRow(
        position: position,
        teamName: team.text.trim(),
        played: int.tryParse(played.text.trim()) ?? 0,
        won: int.tryParse(won.text.trim()) ?? 0,
        drawn: int.tryParse(drawn.text.trim()) ?? 0,
        lost: int.tryParse(lost.text.trim()) ?? 0,
        goalsFor: int.tryParse(gf.text.trim()) ?? 0,
        goalsAgainst: int.tryParse(ga.text.trim()) ?? 0,
        points: int.tryParse(pts.text.trim()) ?? 0,
        isOwnTeam: isOwnTeam,
      );
}

class _StandingsEditPageState extends State<StandingsEditPage> {
  late List<_RowControllers> _rows;
  bool _saving = false;

  String _t(String key) => AppLocalizations.get(key);

  @override
  void initState() {
    super.initState();
    final sorted = [...widget.initialRows]..sort((a, b) => a.position.compareTo(b.position));
    _rows = sorted.map((r) => _RowControllers(r)).toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() => _rows.add(_RowControllers(StandingRow(position: _rows.length + 1, teamName: ''))));
  }

  void _removeRow(int index) {
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );

  Future<void> _save() async {
    final rows = <StandingRow>[];
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i].toRow(i + 1);
      if (row.teamName.isEmpty) continue;
      rows.add(row);
    }
    setState(() => _saving = true);
    final response = await ApiService.saveStandingsTable(
      competitionId: widget.competitionId,
      rows: rows,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (response['success'] == true) {
      _snack(_t('standings_saved_success'));
      Navigator.of(context).pop(true);
      return;
    }
    _snack(response['message']?.toString() ?? _t('standings_save_failed'));
  }

  InputDecoration _decoration(String hint, {bool numeric = false}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 11),
        filled: true,
        fillColor: AppColors.background,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      );

  Widget _numberField(TextEditingController c, String hint) => SizedBox(
        width: 46,
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.foreground, fontSize: 12, fontWeight: FontWeight.w700),
          decoration: _decoration(hint, numeric: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: getAppLanguage() == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: Text(_t('standings_edit_title'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          iconTheme: const IconThemeData(color: AppColors.foreground),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(widget.competitionName,
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _rows.length,
                itemBuilder: (_, i) => _rowCard(i),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addRow,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(_t('standings_add_row')),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_rounded),
                      label: Text(_t('standings_save_btn'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.foreground, elevation: 0),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowCard(int index) {
    final r = _rows[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                child: Text('${index + 1}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: r.team,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: _decoration(_t('standings_team_name_hint')),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _removeRow(index),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline_rounded, color: AppColors.destructive, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Checkbox(
                value: r.isOwnTeam,
                onChanged: (v) => setState(() => r.isOwnTeam = v ?? false),
                activeColor: AppColors.primary,
                visualDensity: VisualDensity.compact,
              ),
              Text(_t('standings_own_team'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _labeledField(_t('standings_played'), r.played),
                const SizedBox(width: 8),
                _labeledField(_t('standings_won'), r.won),
                const SizedBox(width: 8),
                _labeledField(_t('standings_drawn'), r.drawn),
                const SizedBox(width: 8),
                _labeledField(_t('standings_lost'), r.lost),
                const SizedBox(width: 8),
                _labeledField(_t('standings_gf'), r.gf),
                const SizedBox(width: 8),
                _labeledField(_t('standings_ga'), r.ga),
                const SizedBox(width: 8),
                _labeledField(_t('standings_pts'), r.pts),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _labeledField(String label, TextEditingController c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 9.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          _numberField(c, ''),
        ],
      );
}
