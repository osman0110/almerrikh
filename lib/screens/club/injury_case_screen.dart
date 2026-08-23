import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';

const List<String> _severityLevels = ['mild', 'moderate', 'severe'];
const List<String> _rtpStages = [
  'rest', 'light_activity', 'running', 'noncontact_training', 'full_training', 'match_ready',
];
const List<String> _caseStatuses = ['open', 'in_treatment', 'rehab', 'graduated', 'closed'];

// Mirrors RTP_PHASES in api/club/rehab_phases.php — the 8-stage progression.
const Map<int, String> RTP_PHASE_KEYS = {
  1: 'pain_control',
  2: 'rom',
  3: 'strength',
  4: 'balance_control',
  5: 'running',
  6: 'football_specific',
  7: 'partial_training',
  8: 'full_return',
};

String _lbl(String key) {
  final v = AppLocalizations.get(key);
  return v != key ? v : key;
}

Color _severityColor(String s) {
  switch (s) {
    case 'severe': return AppColors.destructive;
    case 'moderate': return AppColors.warning;
    default: return AppColors.success;
  }
}

Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1}) {
  return TextField(
    controller: ctrl,
    maxLines: maxLines,
    style: const TextStyle(color: AppColors.foreground, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted),
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
        style: const TextStyle(color: AppColors.foreground, fontSize: 14),
        items: items
            .map((s) => DropdownMenuItem(value: s, child: Text(labelOf(s))))
            .toList(),
        onChanged: (v) { if (v != null) onChanged(v); },
      ),
    ),
  );
}

Color _caseStatusColor(String s) {
  switch (s) {
    case 'open': return AppColors.destructive;
    case 'in_treatment': return AppColors.warning;
    case 'rehab': return AppColors.risk;
    case 'graduated':
    case 'closed': return AppColors.success;
    default: return AppColors.muted;
  }
}

class InjuryCaseScreen extends StatefulWidget {
  const InjuryCaseScreen({super.key, required this.playerId, required this.playerName});
  final String playerId;
  final String playerName;

  @override
  State<InjuryCaseScreen> createState() => _InjuryCaseScreenState();
}

class _InjuryCaseScreenState extends State<InjuryCaseScreen> {
  List<Map<String, dynamic>> _cases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _cases = await ApiService.getInjuryCases(widget.playerId);
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

  Future<void> _createCase(Map<String, String> data) async {
    final res = await ApiService.createInjuryCase(
      playerId: widget.playerId,
      injuryDate: data['injury_date']!,
      bodyLocation: data['body_location'],
      injuryType: data['injury_type'],
      severity: data['severity'] ?? 'moderate',
      diagnosis: data['diagnosis'],
      examNotes: data['exam_notes'],
      expectedReturnDate: data['expected_return_date'],
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
    final dateCtrl = TextEditingController(text: DateTime.now().toIso8601String().split('T').first);
    final locationCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final diagnosisCtrl = TextEditingController();
    final examCtrl = TextEditingController();
    final returnCtrl = TextEditingController();
    String severity = 'moderate';

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
                Text(_lbl('new_injury_case'),
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 16),
                _field(dateCtrl, _lbl('injury_date')),
                const SizedBox(height: 10),
                _field(locationCtrl, _lbl('body_location')),
                const SizedBox(height: 10),
                _field(typeCtrl, _lbl('injury_type')),
                const SizedBox(height: 10),
                _dropdown(
                  value: severity,
                  items: _severityLevels,
                  labelOf: (s) => _lbl('severity_$s'),
                  onChanged: (v) => setSheetState(() => severity = v),
                ),
                const SizedBox(height: 10),
                _field(diagnosisCtrl, _lbl('diagnosis'), maxLines: 3),
                const SizedBox(height: 10),
                _field(examCtrl, _lbl('exam_notes'), maxLines: 2),
                const SizedBox(height: 10),
                _field(returnCtrl, _lbl('expected_return_date')),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => _createCase({
                      'injury_date': dateCtrl.text.trim(),
                      'body_location': locationCtrl.text.trim(),
                      'injury_type': typeCtrl.text.trim(),
                      'severity': severity,
                      'diagnosis': diagnosisCtrl.text.trim(),
                      'exam_notes': examCtrl.text.trim(),
                      'expected_return_date': returnCtrl.text.trim(),
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.foreground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(_lbl('new_injury_case'),
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
          title: Text(widget.playerName,
              style: const TextStyle(
                  color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          actions: [
            if (canManageInjuryCases)
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
                child: _cases.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.medical_information_outlined, color: AppColors.muted, size: 48),
                            const SizedBox(height: 12),
                            Text(_lbl('no_injury_cases'),
                                style: TextStyle(color: AppColors.muted, fontSize: 14)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _cases.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final c = _cases[i];
                          final status = (c['case_status'] ?? '').toString();
                          final severity = (c['severity'] ?? '').toString();
                          return Container(
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _caseStatusColor(status).withOpacity(0.25)),
                            ),
                            child: ListTile(
                              onTap: () async {
                                await Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => InjuryCaseDetailScreen(caseId: c['id'].toString()),
                                ));
                                _load();
                              },
                              title: Text(
                                (c['injury_type'] as String?)?.isNotEmpty == true
                                    ? c['injury_type']
                                    : _lbl('injury_file'),
                                style: const TextStyle(
                                    color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              subtitle: Text(
                                '${c['injury_date'] ?? ''} · ${(c['body_location'] as String?) ?? ''}',
                                style: TextStyle(color: AppColors.muted, fontSize: 11),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _caseStatusColor(status).withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(_lbl('case_status_$status'),
                                        style: TextStyle(
                                            color: _caseStatusColor(status),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(_lbl('severity_$severity'),
                                      style: TextStyle(color: _severityColor(severity), fontSize: 10)),
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

class InjuryCaseDetailScreen extends StatefulWidget {
  const InjuryCaseDetailScreen({super.key, required this.caseId});
  final String caseId;

  @override
  State<InjuryCaseDetailScreen> createState() => _InjuryCaseDetailScreenState();
}

class _InjuryCaseDetailScreenState extends State<InjuryCaseDetailScreen> {
  Map<String, dynamic>? _case;
  List<Map<String, dynamic>> _updates = [];
  List<Map<String, dynamic>> _phases = [];
  List<Map<String, dynamic>> _attachments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ApiService.getInjuryCaseDetail(widget.caseId),
      ApiService.getRehabPhases(widget.caseId),
      ApiService.getMedicalAttachments(widget.caseId),
    ]);
    if (!mounted) return;
    final res = results[0] as Map<String, dynamic>;
    setState(() {
      _case = res['case'] as Map<String, dynamic>?;
      _updates = (res['updates'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _phases = results[1] as List<Map<String, dynamic>>;
      _attachments = results[2] as List<Map<String, dynamic>>;
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
    final noteCtrl = TextEditingController();
    String? stage = _case?['rtp_stage'] as String?;
    String? status = _case?['case_status'] as String?;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_lbl('add_update'),
                  style: const TextStyle(
                      color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 16),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _lbl('add_update'),
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
                    value: stage,
                    hint: Text(_lbl('rtp_stage')),
                    isExpanded: true,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                    items: _rtpStages
                        .map((s) => DropdownMenuItem(value: s, child: Text(_lbl('rtp_stage_$s'))))
                        .toList(),
                    onChanged: (v) => setSheetState(() => stage = v),
                  ),
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
                    value: status,
                    hint: Text(_lbl('case_status_open')),
                    isExpanded: true,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                    items: _caseStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(_lbl('case_status_$s'))))
                        .toList(),
                    onChanged: (v) => setSheetState(() => status = v),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final res = await ApiService.addInjuryUpdate(
                      id: widget.caseId,
                      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                      rtpStage: stage,
                      caseStatus: status,
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
                  child: Text(_lbl('add_update'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _case;
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
          title: Text(_lbl('injury_cases_title'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          actions: [
            if (canManageInjuryCases &&
                !_loading && c != null && !['graduated', 'closed'].contains(c['case_status']))
              TextButton(
                onPressed: _showUpdateSheet,
                child: Text(_lbl('add_update'),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        body: _loading || c == null
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
                        _row(_lbl('injury_date'), (c['injury_date'] as String?) ?? '-'),
                        _row(_lbl('body_location'), (c['body_location'] as String?) ?? '-'),
                        _row(_lbl('injury_type'), (c['injury_type'] as String?) ?? '-'),
                        _row(_lbl('severity'), _lbl('severity_${c['severity']}')),
                        _row(_lbl('rtp_stage'), _lbl('rtp_stage_${c['rtp_stage']}')),
                        _row(_lbl('case_status_label'), _lbl('case_status_${c['case_status']}')),
                        _row(_lbl('expected_return_date'), (c['expected_return_date'] as String?) ?? '-'),
                        _row(_lbl('actual_return_date'), (c['actual_return_date'] as String?) ?? '-'),
                        if ((c['diagnosis'] as String?)?.isNotEmpty == true) ...[
                          const Divider(color: AppColors.border, height: 20),
                          Text(_lbl('diagnosis'),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(c['diagnosis'], style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                        ],
                        if ((c['exam_notes'] as String?)?.isNotEmpty == true) ...[
                          const SizedBox(height: 10),
                          Text(_lbl('exam_notes'),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(c['exam_notes'], style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRtpPhasesSection(),
                  const SizedBox(height: 16),
                  _buildAttachmentsSection(),
                  const SizedBox(height: 16),
                  Text(_lbl('case_timeline'),
                      style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 8),
                  ..._updates.map((u) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text((u['author_name'] as String?) ?? '',
                                      style: const TextStyle(
                                          color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 12)),
                                ),
                                Text((u['created_at'] as String?)?.split(' ').first ?? '',
                                    style: TextStyle(color: AppColors.muted, fontSize: 10)),
                              ],
                            ),
                            if ((u['note'] as String?)?.isNotEmpty == true) ...[
                              const SizedBox(height: 4),
                              Text(u['note'], style: const TextStyle(color: AppColors.foreground, fontSize: 12)),
                            ],
                            if (u['rtp_stage'] != null || u['case_status'] != null) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [
                                  if (u['rtp_stage'] != null)
                                    _chip(_lbl('rtp_stage_${u['rtp_stage']}'), AppColors.risk),
                                  if (u['case_status'] != null)
                                    _chip(_lbl('case_status_${u['case_status']}'), _caseStatusColor(u['case_status'])),
                                ],
                              ),
                            ],
                          ],
                        ),
                      )),
                ],
              ),
      ),
    );
  }

  // ── RTP Phases ────────────────────────────────────────────────────────────

  Widget _buildRtpPhasesSection() {
    final canEdit = canManageInjuryCases;
    final nextNumber = _phases.isEmpty ? 1 : (_phases.last['phase_number'] as int) + 1;
    final hasOpenPhase = _phases.isNotEmpty && _phases.last['status'] != 'completed';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(_lbl('rtp_phases_title'),
                  style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            if (canEdit && !hasOpenPhase && nextNumber <= 8)
              TextButton(
                onPressed: () => _openPhaseSheet(nextNumber),
                child: Text(
                    _phases.isEmpty ? _lbl('rtp_phase_start_first') : _lbl('rtp_phase_add_update'),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 8),
          ..._phases.map((p) => _phaseRow(p, canEdit)),
        ],
      ),
    );
  }

  Widget _phaseRow(Map<String, dynamic> p, bool canEdit) {
    final phaseNumber = p['phase_number'] as int;
    final phaseKey = p['phase_key'] as String;
    final status = p['status'] as String;
    final completion = p['completion_percent'] as int;
    final isOpen = status != 'completed';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isOpen ? AppColors.risk.withOpacity(0.4) : AppColors.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('$phaseNumber. ${_lbl('rtp_phase_$phaseKey')}',
                  style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            Text('$completion%',
                style: TextStyle(
                    color: isOpen ? AppColors.risk : AppColors.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ]),
          if (canEdit && isOpen) ...[
            const SizedBox(height: 6),
            Row(children: [
              TextButton(
                onPressed: () => _openPhaseSheet(phaseNumber, existing: p),
                child: Text(_lbl('rtp_phase_add_update'),
                    style: const TextStyle(color: AppColors.coachAccent, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () async {
                  final res = phaseNumber == 8
                      ? await ApiService.completeRehabPhase(injuryCaseId: widget.caseId, id: p['id'].toString())
                      : await ApiService.advanceRehabPhase(injuryCaseId: widget.caseId, id: p['id'].toString());
                  if (!mounted) return;
                  if (res['success'] == true) _load();
                },
                child: Text(_lbl('rtp_phase_advance'),
                    style: const TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  void _openPhaseSheet(int phaseNumber, {Map<String, dynamic>? existing}) {
    final goalsCtrl = TextEditingController(text: existing?['goals'] as String? ?? '');
    final exercisesCtrl = TextEditingController(text: existing?['exercises'] as String? ?? '');
    final notesCtrl = TextEditingController(text: existing?['specialist_notes'] as String? ?? '');
    double completion = (existing?['completion_percent'] as int?)?.toDouble() ?? 0;
    double pain = (existing?['pain_score'] as int?)?.toDouble() ?? 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
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
                Text('$phaseNumber. ${_lbl('rtp_phase_${RTP_PHASE_KEYS[phaseNumber]}')}',
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 16),
                _field(goalsCtrl, _lbl('rtp_phase_goals_hint'), maxLines: 2),
                const SizedBox(height: 10),
                _field(exercisesCtrl, _lbl('rtp_phase_exercises_hint'), maxLines: 3),
                const SizedBox(height: 10),
                Text('${_lbl('rtp_phase_completion_label')}: ${completion.round()}%',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Slider(
                  value: completion, min: 0, max: 100, divisions: 20,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setSheetState(() => completion = v),
                ),
                Text('${_lbl('rtp_phase_pain_label')}: ${pain.round()}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                Slider(
                  value: pain, min: 0, max: 10, divisions: 10,
                  activeColor: AppColors.destructive,
                  onChanged: (v) => setSheetState(() => pain = v),
                ),
                const SizedBox(height: 6),
                _field(notesCtrl, _lbl('rtp_phase_specialist_notes_hint'), maxLines: 2),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final res = await ApiService.upsertRehabPhase(
                        injuryCaseId: widget.caseId,
                        phaseNumber: phaseNumber,
                        goals: goalsCtrl.text.trim(),
                        exercises: exercisesCtrl.text.trim(),
                        completionPercent: completion.round(),
                        painScore: pain.round(),
                        specialistNotes: notesCtrl.text.trim(),
                      );
                      if (!mounted) return;
                      if (res['success'] == true) {
                        Navigator.of(context).pop();
                        _load();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.foreground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(_lbl('rtp_phase_add_update'),
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

  // ── Medical Attachments ───────────────────────────────────────────────────

  Widget _buildAttachmentsSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(_lbl('medical_attachments_title'),
                  style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            if (canManageInjuryCases)
              TextButton(
                onPressed: _openAttachmentSheet,
                child: Text(_lbl('attachment_add'),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 8),
          if (_attachments.isEmpty)
            Text(_lbl('no_attachments'), style: const TextStyle(color: AppColors.muted, fontSize: 12))
          else
            ..._attachments.map((a) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a['file_type'] == 'xray'
                        ? Icons.healing_rounded
                        : a['file_type'] == 'image'
                            ? Icons.image_rounded
                            : Icons.description_rounded,
                    color: AppColors.coachAccent,
                  ),
                  title: Text(_lbl('attachment_type_${a['file_type']}'),
                      style: const TextStyle(color: AppColors.foreground, fontSize: 12, fontWeight: FontWeight.w700)),
                  subtitle: Text((a['description'] as String?) ?? a['file_url'],
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: canManageInjuryCases
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: AppColors.destructive, size: 20),
                          onPressed: () async {
                            await ApiService.deleteMedicalAttachment(a['id'].toString());
                            _load();
                          },
                        )
                      : null,
                )),
        ],
      ),
    );
  }

  void _openAttachmentSheet() {
    final urlCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String type = 'other';
    const types = ['image', 'xray', 'report', 'other'];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 20, left: 20, right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_lbl('attachment_add'),
                  style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 16),
              _field(urlCtrl, _lbl('attachment_url_hint')),
              const SizedBox(height: 10),
              _dropdown(
                value: type,
                items: types,
                labelOf: (t) => _lbl('attachment_type_$t'),
                onChanged: (v) => setSheetState(() => type = v),
              ),
              const SizedBox(height: 10),
              _field(descCtrl, _lbl('attachment_description_hint')),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    if (urlCtrl.text.trim().isEmpty) return;
                    final res = await ApiService.addMedicalAttachment(
                      injuryCaseId: widget.caseId,
                      fileUrl: urlCtrl.text.trim(),
                      fileType: type,
                      description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    );
                    if (!mounted) return;
                    if (res['success'] == true) {
                      Navigator.of(context).pop();
                      _load();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.foreground,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(_lbl('attachment_add'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
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

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}
