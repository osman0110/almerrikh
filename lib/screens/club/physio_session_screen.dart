import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import 'injury_case_screen.dart' show InjuryCaseScreen;
import 'nutrition_screen.dart' show NutritionScreen;

const List<String> _sessionReasons = [
  'recovery', 'pain', 'muscle_tightness', 'pre_match', 'post_match',
];
const List<String> _intensities = ['light', 'moderate', 'deep'];
const List<String> _recommendations = [
  'rest', 'modified_training', 'doctor_followup', 'another_session',
];
const List<String> _statuses = ['scheduled', 'completed', 'cancelled', 'no_show', 'late'];

String _lbl(String key) {
  final v = AppLocalizations.get(key);
  return v != key ? v : key;
}

Color _statusColor(String s) {
  switch (s) {
    case 'scheduled': return AppColors.risk;
    case 'completed': return AppColors.success;
    case 'late': return AppColors.warning;
    case 'cancelled':
    case 'no_show': return AppColors.destructive;
    default: return AppColors.muted;
  }
}

/// A "physio session" the coach sees as one unit: either a single row
/// (individually booked), or every row sharing a `session_group_id` from
/// the bulk booking flow — one shared time/room/reason/therapist with an
/// independent status per player.
class PhysioSessionEntry {
  PhysioSessionEntry(this.rows) : assert(rows.isNotEmpty);
  final List<Map<String, dynamic>> rows;

  bool get isGroup => rows.length > 1;
  Map<String, dynamic> get primary => rows.first;
  String get scheduledAt => (primary['scheduled_at'] as String?) ?? '';
}

/// The title to show for a physio session row: its free-text session_name
/// if the specialist gave it one, else the treatment type, else the
/// localized session reason.
String sessionDisplayTitle(Map<String, dynamic> s) {
  final name = (s['session_name'] as String?)?.trim();
  if (name != null && name.isNotEmpty) return name;
  final type = (s['treatment_type'] as String?)?.trim();
  if (type != null && type.isNotEmpty) return type;
  final reason = (s['session_reason'] as String?) ?? '';
  final key = 'session_reason_$reason';
  final v = AppLocalizations.get(key);
  return v != key ? v : '-';
}

/// Groups a flat list of physio_sessions rows (as returned by
/// getPhysioScheduleForDate / the daily schedule) into [PhysioSessionEntry]
/// units by `session_group_id`, preserving chronological order.
List<PhysioSessionEntry> groupPhysioSessions(List<Map<String, dynamic>> sessions) {
  final entries = <PhysioSessionEntry>[];
  final groupIndex = <String, int>{};
  for (final s in sessions) {
    final groupId = (s['session_id'] as String?) ?? '';
    if (groupId.isEmpty) {
      entries.add(PhysioSessionEntry([s]));
      continue;
    }
    final existingIndex = groupIndex[groupId];
    if (existingIndex == null) {
      groupIndex[groupId] = entries.length;
      entries.add(PhysioSessionEntry([s]));
    } else {
      entries[existingIndex].rows.add(s);
    }
  }
  entries.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return entries;
}

class PhysioSessionScreen extends StatefulWidget {
  const PhysioSessionScreen({super.key, required this.playerId, required this.playerName});
  final String playerId;
  final String playerName;

  @override
  State<PhysioSessionScreen> createState() => _PhysioSessionScreenState();
}

class _PhysioSessionScreenState extends State<PhysioSessionScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _sessions = await ApiService.getPhysioSessions(widget.playerId);
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Future<void> _createSession(Map<String, String> data) async {
    final res = await ApiService.createPhysioSession(
      playerId: widget.playerId,
      scheduledAt: data['scheduled_at']!,
      durationMinutes: int.tryParse(data['duration_minutes'] ?? '') ?? 30,
      room: data['room'],
      bodyArea: data['body_area'],
      sessionReason: data['session_reason'] ?? 'recovery',
      treatmentType: data['treatment_type'],
      intensity: data['intensity'] ?? 'moderate',
      contraindications: data['contraindications'],
      sessionName: (data['session_name']?.trim().isEmpty ?? true) ? null : data['session_name']!.trim(),
    );
    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.of(context).pop();
      _load();
    } else {
      _snack(res['message']?.toString() ?? res['error']?.toString() ?? AppLocalizations.get('error_generic'));
    }
  }

  void _showCreateSheet() {
    final sessionNameCtrl = TextEditingController();
    final dateTimeCtrl = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 16).replaceFirst('T', ' '));
    final durationCtrl = TextEditingController(text: '30');
    final roomCtrl = TextEditingController();
    final bodyAreaCtrl = TextEditingController();
    final treatmentCtrl = TextEditingController();
    final contraCtrl = TextEditingController();
    String reason = 'recovery';
    String intensity = 'moderate';

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
                Text(_lbl('new_physio_session'),
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 16),
                _field(sessionNameCtrl, _lbl('physio_session_name_hint')),
                const SizedBox(height: 10),
                _field(dateTimeCtrl, _lbl('scheduled_at')),
                const SizedBox(height: 10),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _lbl('physio_duration_minutes'),
                    hintStyle: const TextStyle(color: AppColors.muted),
                    suffixText: _lbl('unit_minutes_word'),
                    suffixStyle: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
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
                _field(roomCtrl, _lbl('room')),
                const SizedBox(height: 10),
                _field(bodyAreaCtrl, _lbl('body_area')),
                const SizedBox(height: 10),
                _dropdown(
                  value: reason,
                  items: _sessionReasons,
                  labelOf: (s) => _lbl('session_reason_$s'),
                  onChanged: (v) => setSheetState(() => reason = v),
                ),
                const SizedBox(height: 10),
                _field(treatmentCtrl, _lbl('treatment_type')),
                const SizedBox(height: 10),
                _dropdown(
                  value: intensity,
                  items: _intensities,
                  labelOf: (s) => _lbl('physio_intensity_$s'),
                  onChanged: (v) => setSheetState(() => intensity = v),
                ),
                const SizedBox(height: 10),
                _field(contraCtrl, _lbl('contraindications'), maxLines: 2),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => _createSession({
                      'session_name': sessionNameCtrl.text.trim(),
                      'scheduled_at': dateTimeCtrl.text.trim(),
                      'duration_minutes': durationCtrl.text.trim(),
                      'room': roomCtrl.text.trim(),
                      'body_area': bodyAreaCtrl.text.trim(),
                      'session_reason': reason,
                      'treatment_type': treatmentCtrl.text.trim(),
                      'intensity': intensity,
                      'contraindications': contraCtrl.text.trim(),
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.foreground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(_lbl('physio_create_session_cta'),
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

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.foreground, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.muted),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _dropdown({
    required String value,
    required List<String> items,
    required String Function(String) labelOf,
    required void Function(String) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.card,
          // DropdownButton wraps its items in a DefaultTextStyle built
          // straight from `style` (it replaces the ambient one rather than
          // merging), so basing it on Theme.textTheme keeps the app's Cairo
          // font instead of silently falling back to the platform default.
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.foreground, fontSize: 14),
          items: items
              .map((s) => DropdownMenuItem(value: s, child: Text(labelOf(s))))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
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
          title: Text(widget.playerName,
              style: const TextStyle(
                  color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          actions: [
            IconButton(
              icon: const Icon(Icons.event_note_rounded, color: AppColors.foreground, size: 20),
              tooltip: _lbl('daily_schedule_title'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const PhysioDailyScheduleScreen(),
              )),
            ),
            // Cross-link to the injury file — physiotherapist (covers
            // physio & massage) manages both, so this is their only entry
            // point into it since they land on this screen's roster, not
            // the full player profile.
            if (canManageInjuryCases)
              IconButton(
                icon: const Icon(Icons.medical_information_rounded, color: AppColors.foreground, size: 20),
                tooltip: _lbl('injury_file'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => InjuryCaseScreen(
                    playerId: widget.playerId,
                    playerName: widget.playerName,
                  ),
                )),
              ),
            // Cross-link to the nutrition file — only for roles that manage
            // both (doctor/admin), mirroring the reverse link in nutrition_screen.dart.
            if (canManageNutrition)
              IconButton(
                icon: const Icon(Icons.restaurant_menu_rounded, color: AppColors.foreground, size: 20),
                tooltip: _lbl('nutrition_title'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => NutritionScreen(
                    playerId: widget.playerId,
                    playerName: widget.playerName,
                  ),
                )),
              ),
            if (canManagePhysioSessions)
              TextButton.icon(
                onPressed: _showCreateSheet,
                icon: const Icon(Icons.add, color: AppColors.primary, size: 18),
                label: Text(_lbl('new_btn'),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primary,
                backgroundColor: AppColors.card,
                child: _sessions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.spa_outlined, color: AppColors.muted, size: 48),
                            const SizedBox(height: 12),
                            Text(_lbl('no_physio_sessions'),
                                style: TextStyle(color: AppColors.muted, fontSize: 14)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _sessions.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final s = _sessions[i];
                          final status = (s['status'] ?? '').toString();
                          final reason = (s['session_reason'] ?? '').toString();
                          return Container(
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _statusColor(status).withOpacity(0.25)),
                            ),
                            child: ListTile(
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => PhysioSessionDetailScreen(sessionId: s['id'].toString()),
                                ));
                                _load();
                              },
                              title: Text(
                                (s['treatment_type'] as String?)?.isNotEmpty == true
                                    ? s['treatment_type']
                                    : _lbl('session_reason_$reason'),
                                style: const TextStyle(
                                    color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              subtitle: Text(
                                '${s['scheduled_at'] ?? ''} · ${(s['body_area'] as String?) ?? ''}',
                                style: TextStyle(color: AppColors.muted, fontSize: 11),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(_lbl('physio_status_$status'),
                                    style: TextStyle(
                                        color: _statusColor(status),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
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

class PhysioSessionDetailScreen extends StatefulWidget {
  const PhysioSessionDetailScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<PhysioSessionDetailScreen> createState() => _PhysioSessionDetailScreenState();
}

class _PhysioSessionDetailScreenState extends State<PhysioSessionDetailScreen> {
  Map<String, dynamic>? _session;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ApiService.getPhysioSessionDetail(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _session = res['session'] as Map<String, dynamic>?;
      _loading = false;
    });
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  void _showUpdateSheet() {
    final notesCtrl = TextEditingController(text: (_session?['specialist_notes'] as String?) ?? '');
    final responseCtrl = TextEditingController(text: (_session?['player_response'] as String?) ?? '');
    final scheduledCtrl = TextEditingController(text: ((_session?['scheduled_at'] as String?) ?? '').replaceFirst(RegExp(r':\d{2}$'), ''));
    final durationCtrl = TextEditingController(text: '${_session?['duration_minutes'] ?? 30}');
    final roomCtrl = TextEditingController(text: (_session?['room'] as String?) ?? '');
    String status = (_session?['status'] as String?) ?? 'scheduled';
    String? recommendation = _session?['recommendation'] as String?;
    InputDecoration fieldDecoration(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.muted),
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        );

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
                Text(_lbl('update_session'),
                    style: const TextStyle(
                        color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 16),
                TextField(
                  controller: scheduledCtrl,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: fieldDecoration(_lbl('scheduled_at')),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: fieldDecoration(_lbl('physio_duration_minutes')),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: roomCtrl,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: fieldDecoration(_lbl('room')),
                ),
                const SizedBox(height: 10),
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
                      items: _statuses
                          .map((s) => DropdownMenuItem(value: s, child: Text(_lbl('physio_status_$s'))))
                          .toList(),
                      onChanged: (v) { if (v != null) setSheetState(() => status = v); },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _lbl('specialist_notes'),
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
                  controller: responseCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: _lbl('player_response'),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: recommendation,
                      hint: Text(_lbl('recommendation'), style: TextStyle(color: AppColors.muted)),
                      isExpanded: true,
                      dropdownColor: AppColors.card,
                      style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                      items: _recommendations
                          .map((s) => DropdownMenuItem(value: s, child: Text(_lbl('recommendation_$s'))))
                          .toList(),
                      onChanged: (v) => setSheetState(() => recommendation = v),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final res = await ApiService.updatePhysioSession(
                        id: widget.sessionId,
                        status: status,
                        recommendation: recommendation,
                        specialistNotes: notesCtrl.text.trim(),
                        playerResponse: responseCtrl.text.trim(),
                        scheduledAt: scheduledCtrl.text.trim(),
                        durationMinutes: int.tryParse(durationCtrl.text.trim()),
                        room: roomCtrl.text.trim(),
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
                    child: Text(_lbl('update_session'),
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
    final s = _session;
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
          title: Text(_lbl('physio_session_title'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          actions: [
            if (canManagePhysioSessions && !_loading && s != null)
              TextButton(
                onPressed: _showUpdateSheet,
                child: Text(_lbl('update_session'),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        body: _loading || s == null
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row(_lbl('scheduled_at'), (s['scheduled_at'] as String?) ?? '-'),
                        _row(_lbl('physio_duration_minutes'), '${s['duration_minutes'] ?? '-'}'),
                        _row(_lbl('room'), (s['room'] as String?) ?? '-'),
                        _row(_lbl('body_area'), (s['body_area'] as String?) ?? '-'),
                        _row(_lbl('session_reason'), _lbl('session_reason_${s['session_reason']}')),
                        _row(_lbl('treatment_type'), (s['treatment_type'] as String?) ?? '-'),
                        _row(_lbl('physio_intensity'), _lbl('physio_intensity_${s['intensity']}')),
                        _row(_lbl('physio_status_label'), _lbl('physio_status_${s['status']}')),
                        if (s['recommendation'] != null)
                          _row(_lbl('recommendation'), _lbl('recommendation_${s['recommendation']}')),
                        if ((s['contraindications'] as String?)?.isNotEmpty == true) ...[
                          const Divider(color: AppColors.border, height: 20),
                          Text(_lbl('contraindications'),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(s['contraindications'], style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                        ],
                        if ((s['specialist_notes'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 10),
                          Text(_lbl('specialist_notes'),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(s['specialist_notes'], style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                        ],
                        if ((s['player_response'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 10),
                          Text(_lbl('player_response'),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(s['player_response'], style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.foreground, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Daily schedule showing therapist/room workload across the whole club.
class PhysioDailyScheduleScreen extends StatefulWidget {
  const PhysioDailyScheduleScreen({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<PhysioDailyScheduleScreen> createState() => _PhysioDailyScheduleScreenState();
}

class _PhysioDailyScheduleScreenState extends State<PhysioDailyScheduleScreen> {
  late DateTime _date;
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate ?? DateTime.now();
    _load();
  }

  String get _dateStr =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    _sessions = await ApiService.getPhysioScheduleForDate(_dateStr);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group by therapist for a simple workload view; within each therapist,
    // rows from the same group-booking (session_group_id) collapse into one
    // line so a 5-player group session shows as one entry, not five.
    final Map<String, List<PhysioSessionEntry>> byTherapist = {};
    for (final entry in groupPhysioSessions(_sessions)) {
      final name = (entry.primary['therapist_name'] as String?) ?? _lbl('unassigned');
      byTherapist.putIfAbsent(name, () => []).add(entry);
    }

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
          title: Text(_lbl('daily_schedule_title'),
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
            : _sessions.isEmpty
                ? Center(
                    child: Text(_lbl('no_physio_sessions'),
                        style: TextStyle(color: AppColors.muted, fontSize: 14)),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: byTherapist.entries.map((entry) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(14),
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
                                Expanded(
                                  child: Text(entry.key,
                                      style: const TextStyle(
                                          color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
                                ),
                                Text('${entry.value.length} ${_lbl('physio_sessions_label')}',
                                    style: TextStyle(color: AppColors.muted, fontSize: 11)),
                              ],
                            ),
                            const Divider(color: AppColors.border, height: 18),
                            ...entry.value.map((sessionEntry) {
                              final s = sessionEntry.primary;
                              final status = (s['status'] ?? '').toString();
                              final time = ((s['scheduled_at'] as String?) ?? '').split(' ').last;
                              return InkWell(
                                onTap: sessionEntry.isGroup
                                    ? () async {
                                        final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
                                          builder: (_) => PhysioGroupSessionScreen(rows: sessionEntry.rows),
                                        ));
                                        if (changed == true) _load();
                                      }
                                    : null,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Text(time,
                                          style: const TextStyle(
                                              color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 12)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                            sessionEntry.isGroup
                                                ? '${sessionDisplayTitle(s)} · ${sessionEntry.rows.length} ${_lbl('nav_players')}'
                                                : (s['player_name'] as String?) ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: AppColors.foreground, fontSize: 12)),
                                      ),
                                      if ((s['room'] as String?)?.isNotEmpty == true)
                                        Text((s['room'] as String?) ?? '',
                                            style: TextStyle(color: AppColors.muted, fontSize: 11)),
                                      const SizedBox(width: 8),
                                      if (sessionEntry.isGroup)
                                        const Icon(Icons.chevron_left_rounded, color: AppColors.muted, size: 16)
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _statusColor(status).withOpacity(0.10),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(_lbl('physio_status_$status'),
                                              style: TextStyle(
                                                  color: _statusColor(status), fontSize: 9, fontWeight: FontWeight.w700)),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
      ),
    );
  }
}

/// One shared session ("group physio session") managed as a whole: common
/// time/room/reason at the top, a roster below where each player's
/// attendance (ready/late/absent) is set independently without leaving
/// this screen. Full per-player editing (notes, recommendation, etc.)
/// still goes through [PhysioSessionDetailScreen] via the row tap.
class PhysioGroupSessionScreen extends StatefulWidget {
  const PhysioGroupSessionScreen({super.key, required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  State<PhysioGroupSessionScreen> createState() => _PhysioGroupSessionScreenState();
}

class _PhysioGroupSessionScreenState extends State<PhysioGroupSessionScreen> {
  late List<Map<String, dynamic>> _rows;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _rows = List<Map<String, dynamic>>.from(widget.rows);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Future<void> _setStatus(Map<String, dynamic> row, String status, {String? note}) async {
    final res = await ApiService.updatePhysioSession(
      id: row['id'].toString(),
      status: status,
      specialistNotes: note,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        row['status'] = status;
        if (note != null) row['specialist_notes'] = note;
        _changed = true;
      });
    } else {
      _snack(res['message']?.toString() ?? AppLocalizations.get('error_generic'));
    }
  }

  Future<void> _markLate(Map<String, dynamic> row) async {
    final ctrl = TextEditingController();
    final minutes = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(_lbl('physio_attendance_late_minutes_title'),
            style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.foreground, fontSize: 16),
          decoration: InputDecoration(
            suffixText: _lbl('unit_minutes_word'),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_lbl('cancel'), style: const TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, int.tryParse(ctrl.text.trim()) ?? 0),
            child: Text(_lbl('confirm'), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (minutes == null) return;
    _setStatus(row, 'late', note: '${_lbl('physio_attendance_late')} — $minutes ${_lbl('unit_minutes_word')}');
  }

  Future<void> _confirmEndSession() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(_lbl('physio_end_session_title'),
            style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
        content: Text(_lbl('physio_end_session_body'),
            style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_lbl('cancel'), style: const TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_lbl('physio_end_session_cta'),
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final row in _rows) {
      final status = (row['status'] ?? '').toString();
      if (status == 'cancelled' || status == 'no_show' || status == 'completed') continue;
      await _setStatus(row, 'completed');
    }
    if (mounted) _snack(_lbl('physio_end_session_done'));
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11.5))),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: AppColors.foreground, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = _rows.first;
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
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: Text(sessionDisplayTitle(first),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          actions: [
            TextButton.icon(
              onPressed: _confirmEndSession,
              icon: const Icon(Icons.task_alt_rounded, color: AppColors.success, size: 18),
              label: Text(_lbl('physio_end_session_cta'),
                  style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(_lbl('scheduled_at'), (first['scheduled_at'] as String?) ?? '-'),
                  _row(_lbl('room'), (first['room'] as String?)?.isNotEmpty == true ? first['room'] : '-'),
                  _row(_lbl('session_reason'), _lbl('session_reason_${first['session_reason']}')),
                  if ((first['body_area'] as String?)?.isNotEmpty == true)
                    _row(_lbl('body_area'), first['body_area']),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('${_lbl('nav_players')} · ${_rows.length}',
                style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 10),
            ..._rows.map((row) => _playerRow(row)),
          ],
        ),
      ),
    );
  }

  Widget _playerRow(Map<String, dynamic> row) {
    final status = (row['status'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
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
              Expanded(
                child: Text((row['player_name'] as String?) ?? '-',
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(status).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(_lbl('physio_status_$status'),
                    style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left_rounded, color: AppColors.muted, size: 20),
                tooltip: _lbl('physio_session_title'),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PhysioSessionDetailScreen(sessionId: row['id'].toString()),
                  ));
                  final res = await ApiService.getPhysioSessionDetail(row['id'].toString());
                  final updated = res['session'] as Map<String, dynamic>?;
                  if (updated != null && mounted) {
                    setState(() {
                      row['status'] = updated['status'];
                      _changed = true;
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _attendanceButton(
                  label: _lbl('physio_attendance_ready'),
                  icon: Icons.check_circle_rounded,
                  color: AppColors.success,
                  active: status == 'scheduled',
                  onTap: () => _setStatus(row, 'scheduled'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _attendanceButton(
                  label: _lbl('physio_attendance_late'),
                  icon: Icons.schedule_rounded,
                  color: AppColors.warning,
                  active: status == 'late',
                  onTap: () => _markLate(row),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _attendanceButton(
                  label: _lbl('physio_attendance_absent'),
                  icon: Icons.cancel_rounded,
                  color: AppColors.destructive,
                  active: status == 'no_show',
                  onTap: () => _setStatus(row, 'no_show'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _attendanceButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.12) : AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? color : AppColors.border, width: active ? 1.4 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(color: active ? color : AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}
