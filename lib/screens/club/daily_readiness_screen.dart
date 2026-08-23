import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';

const List<String> _participationOptions = ['fully_available', 'modified_training', 'unavailable'];

String _lbl(String key) {
  final v = AppLocalizations.get(key);
  return v != key ? v : key;
}

Color _riskColor(String level) {
  switch (level) {
    case 'high_risk': return AppColors.destructive;
    case 'moderate': return AppColors.warning;
    case 'normal': return AppColors.success;
    default: return AppColors.muted;
  }
}

Color _participationColor(String? status) {
  switch (status) {
    case 'fully_available': return AppColors.success;
    case 'modified_training': return AppColors.warning;
    case 'unavailable': return AppColors.destructive;
    default: return AppColors.muted;
  }
}

/// Unified Daily Readiness & Intervention Dashboard (roadmap item 6).
/// Player questionnaire -> readiness check -> alert to coach/medical staff
/// -> intervention -> participation decision, in one club-wide daily view.
class DailyReadinessScreen extends StatefulWidget {
  const DailyReadinessScreen({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<DailyReadinessScreen> createState() => _DailyReadinessScreenState();
}

class _DailyReadinessScreenState extends State<DailyReadinessScreen> {
  late DateTime _date;
  List<Map<String, dynamic>> _players = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? DateTime.now();
    _load();
  }

  String get _dateStr =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> get _filteredPlayers {
    final query = _query.trim().toLowerCase();
    return _players.where((player) {
      final name = (player['player_name'] ?? '').toString().toLowerCase();
      if (query.isNotEmpty && !name.contains(query)) return false;
      if (_filter == 'missing' && player['checked_in'] == true) return false;
      if (_filter == 'risk' &&
          !['high_risk', 'moderate'].contains((player['risk_level'] ?? '').toString())) {
        return false;
      }
      return true;
    }).toList();
  }

  Widget _buildSearchFilters() {
    final filters = [
      ('all', AppLocalizations.get('category_all')),
      ('missing', AppLocalizations.get('doctor_readiness_missing_short')),
      ('risk', AppLocalizations.get('doctor_urgent_followup')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: (value) => setState(() => _query = value),
          style: const TextStyle(color: AppColors.foreground, fontSize: 13),
          decoration: InputDecoration(
            hintText: AppLocalizations.get('search_players'),
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.muted, size: 19),
            filled: true,
            fillColor: AppColors.card,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filters.map((item) {
              final selected = _filter == item.$1;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(item.$2, style: TextStyle(
                    color: selected ? AppColors.maroon : AppColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  )),
                  selected: selected,
                  onSelected: (_) => setState(() => _filter = item.$1),
                  selectedColor: AppColors.primarySoft,
                  backgroundColor: AppColors.card,
                  side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
        ),
        if (_filteredPlayers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text(_lbl('no_filter_match'),
                style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final res = await ApiService.getDailyReadiness(_dateStr);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _players = (res['players'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message']?.toString() ?? res['error']?.toString() ?? AppLocalizations.get('error_generic');
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _load();
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  void _showDecisionSheet(Map<String, dynamic> player) {
    final existing = player['decision'] as Map<String, dynamic>?;
    String status = (existing?['participation_status'] as String?) ?? 'fully_available';
    final durationCtrl = TextEditingController(text: existing?['allowed_duration_minutes']?.toString() ?? '');
    final restrictionsCtrl = TextEditingController(text: (existing?['restrictions'] as String?) ?? '');

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 20, left: 20, right: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player['player_name'] ?? '',
                    style: const TextStyle(
                        color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(_lbl('participation_decision'),
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: status,
                      isExpanded: true,
                      dropdownColor: AppColors.card,
                      style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                      items: _participationOptions
                          .map((s) => DropdownMenuItem(value: s, child: Text(_lbl('participation_$s'))))
                          .toList(),
                      onChanged: (v) { if (v != null) setSheetState(() => status = v); },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _lbl('allowed_duration_minutes'),
                    hintStyle: TextStyle(color: AppColors.muted),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: restrictionsCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _lbl('restrictions'),
                    hintStyle: TextStyle(color: AppColors.muted),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final res = await ApiService.setDailyDecision(
                        playerId: player['player_id'].toString(),
                        decisionDate: _dateStr,
                        participationStatus: status,
                        allowedDurationMinutes: int.tryParse(durationCtrl.text.trim()),
                        restrictions: restrictionsCtrl.text.trim(),
                      );
                      if (!mounted) return;
                      if (res['success'] == true) {
                        Navigator.of(context).pop();
                        _load();
                      } else {
                        _snack(res['message']?.toString() ?? AppLocalizations.get('error_generic'));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.foreground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(_lbl('save_decision'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.foreground, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(_lbl('monitoring_title'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          actions: [
            TextButton(
              onPressed: _pickDate,
              child: Text(_dateStr,
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? Center(child: Text(_error!, style: TextStyle(color: AppColors.muted, fontSize: 13)))
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    backgroundColor: AppColors.card,
                    child: _players.isEmpty
                        ? ListView(children: [
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 120),
                                child: Text(_lbl('no_players_today'),
                                    style: TextStyle(color: AppColors.muted, fontSize: 14)),
                              ),
                            ),
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredPlayers.length + 1,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              if (i == 0) return _buildSearchFilters();
                              final p = _filteredPlayers[i - 1];
                              final risk = (p['risk_level'] ?? 'unknown').toString();
                              final decision = p['decision'] as Map<String, dynamic>?;
                              final participationStatus = decision?['participation_status'] as String?;
                              final physioToday = p['physio_today'] as String?;
                              final nutritionToday = p['nutrition_status_today'] as String?;

                              return InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: canSetDailyDecision ? () => _showDecisionSheet(p) : null,
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.card,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: _riskColor(risk).withOpacity(0.25)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(p['player_name'] ?? '',
                                                style: const TextStyle(
                                                    color: AppColors.foreground,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13)),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: _riskColor(risk).withOpacity(0.10),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(_lbl('risk_level_$risk'),
                                                style: TextStyle(
                                                    color: _riskColor(risk),
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 4,
                                        children: [
                                          if (p['checked_in'] == true)
                                            Text('${_lbl('hooper_short')}: ${p['hooper_score']}',
                                                style: TextStyle(color: AppColors.muted, fontSize: 11))
                                          else
                                            Text(_lbl('not_checked_in'),
                                                style: TextStyle(color: AppColors.muted, fontSize: 11)),
                                          if (physioToday != null)
                                            Text('${_lbl('physio_sessions_title')}: ${_lbl('physio_status_$physioToday')}',
                                                style: TextStyle(color: AppColors.muted, fontSize: 11)),
                                          if (nutritionToday != null)
                                            Text('${_lbl('nutrition_title')}: ${_lbl('compliance_status_$nutritionToday')}',
                                                style: TextStyle(color: AppColors.muted, fontSize: 11)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: _participationColor(participationStatus).withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                              color: _participationColor(participationStatus).withOpacity(0.25)),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.shield_rounded,
                                                color: _participationColor(participationStatus), size: 14),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                participationStatus != null
                                                    ? _lbl('participation_$participationStatus')
                                                    : _lbl('no_decision_yet'),
                                                style: TextStyle(
                                                    color: _participationColor(participationStatus),
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                            if (canSetDailyDecision)
                                              Icon(Icons.edit_rounded, color: AppColors.muted, size: 14),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
      ),
    );
  }
}
