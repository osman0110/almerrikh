import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';

class PhysioBulkSessionPage extends StatefulWidget {
  const PhysioBulkSessionPage({super.key});

  @override
  State<PhysioBulkSessionPage> createState() => _PhysioBulkSessionPageState();
}

class _PhysioBulkSessionPageState extends State<PhysioBulkSessionPage> {
  final _sessionNameCtrl = TextEditingController();
  final _dateTimeCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '30');
  final _roomCtrl = TextEditingController();
  final _bodyAreaCtrl = TextEditingController();
  final _treatmentCtrl = TextEditingController();
  final _contraindicationsCtrl = TextEditingController();

  List<ClubPlayer> _players = [];
  Set<String> _excludedIds = {};
  String? _individualId;
  String _audience = 'all_active';
  String _reason = 'recovery';
  String _intensity = 'moderate';
  String _playerQuery = '';
  bool _loading = true;
  bool _saving = false;
  DateTime _scheduledDate = DateTime.now().add(const Duration(minutes: 30));

  String _t(String key) => AppLocalizations.get(key);

  @override
  void initState() {
    super.initState();
    _dateTimeCtrl.text = _formatDateTime(_scheduledDate);
    _load();
  }

  @override
  void dispose() {
    _sessionNameCtrl.dispose();
    _dateTimeCtrl.dispose();
    _durationCtrl.dispose();
    _roomCtrl.dispose();
    _bodyAreaCtrl.dispose();
    _treatmentCtrl.dispose();
    _contraindicationsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final players = (await ClubService().getPlayers())
        .where((p) => p.status == PlayerStatus.active)
        .toList();
    if (!mounted) return;
    setState(() {
      _players = players;
      _individualId = players.isEmpty ? null : players.first.id;
      _loading = false;
    });
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _formatDateTime(DateTime value) =>
      '${value.year}-${_two(value.month)}-${_two(value.day)} ${_two(value.hour)}:${_two(value.minute)}';

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(primary: AppColors.primary, surface: AppColors.card),
      ), child: child!),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledDate),
      builder: (context, child) => Theme(data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(primary: AppColors.primary, surface: AppColors.card),
      ), child: child!),
    );
    if (time == null) return;
    setState(() {
      _scheduledDate = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _dateTimeCtrl.text = _formatDateTime(_scheduledDate);
    });
  }

  List<String> get _selectedIds {
    if (_audience == 'individual') return _individualId == null ? [] : [_individualId!];
    return _players.where((p) => !_excludedIds.contains(p.id)).map((p) => p.id).toList();
  }

  List<ClubPlayer> get _visiblePlayers {
    final query = _playerQuery.trim().toLowerCase();
    if (query.isEmpty) return _players;
    return _players.where((p) => p.fullName.toLowerCase().contains(query)).toList();
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.muted),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  Widget _field(TextEditingController controller, String hint, {TextInputType? keyboard, int maxLines = 1}) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.foreground, fontSize: 14),
      decoration: _decoration(hint),
    );
  }

  Widget _dropdown<T>({required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.card,
          // DropdownButton wraps its items in a DefaultTextStyle built
          // straight from `style` (it replaces the ambient one rather than
          // merging), so basing it on Theme.textTheme keeps the app's Cairo
          // font instead of silently falling back to the platform default.
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.foreground, fontSize: 14),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );

  Future<void> _save() async {
    final selectedIds = _selectedIds;
    final duration = int.tryParse(_durationCtrl.text.trim());
    if (selectedIds.isEmpty) {
      _snack(_t('physio_no_selected_players'));
      return;
    }
    if (duration == null || duration < 5 || duration > 480) {
      _snack(_t('physio_duration_invalid'));
      return;
    }
    setState(() => _saving = true);
    final response = await ApiService.createPhysioSessionsBulk(
      audience: _audience == 'individual' ? 'individual' : 'all_active',
      playerId: _audience == 'individual' ? _individualId : null,
      excludedPlayerIds: _audience == 'all_active' ? _excludedIds.toList() : const [],
      // therapistUserId omitted — the backend auto-assigns the creating
      // user (createPhysioSessionsBulk's whole point per this feature request).
      scheduledAt: _dateTimeCtrl.text.trim(),
      durationMinutes: duration,
      room: _roomCtrl.text.trim(),
      bodyArea: _bodyAreaCtrl.text.trim(),
      sessionReason: _reason,
      treatmentType: _treatmentCtrl.text.trim(),
      intensity: _intensity,
      contraindications: _contraindicationsCtrl.text.trim(),
      sessionName: _sessionNameCtrl.text.trim().isEmpty ? null : _sessionNameCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (response['success'] == true) {
      _snack(AppLocalizations.format('physio_session_created_for_players',
          {'count': response['created_count'] ?? selectedIds.length}));
      Navigator.of(context).pop(true);
      return;
    }
    final conflicts = (response['conflicts'] as List?) ?? const [];
    final names = conflicts.map((item) => (item as Map)['player_name']?.toString()).whereType<String>().toList();
    _snack(names.isEmpty ? (response['message']?.toString() ?? _t('error_generic'))
        : '${_t('physio_conflict')}: ${names.join(', ')}');
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
          title: Text(_t('physio_bulk_title'), style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
          iconTheme: const IconThemeData(color: AppColors.foreground),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_players.isEmpty)
                    _empty(_t('physio_no_active_players'))
                  else ...[
                    Text(_t('physio_session_scope'), style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _dropdown<String>(
                      value: _audience,
                      items: [
                        DropdownMenuItem(value: 'all_active', child: Text(_t('physio_bulk_all'))),
                        DropdownMenuItem(value: 'exclude', child: Text(_t('physio_bulk_exclude'))),
                        DropdownMenuItem(value: 'individual', child: Text(_t('physio_bulk_individual'))),
                      ],
                      onChanged: (value) => setState(() => _audience = value ?? 'all_active'),
                    ),
                    const SizedBox(height: 8),
                    Text('${_t('physio_selected_count')}: ${_selectedIds.length}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    if (_audience == 'exclude') ...[
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (value) => setState(() => _playerQuery = value),
                        style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                        decoration: _decoration(_t('search_players')),
                      ),
                      const SizedBox(height: 8),
                      ..._visiblePlayers.map((player) => CheckboxListTile(
                            value: !_excludedIds.contains(player.id),
                            onChanged: (selected) => setState(() {
                              if (selected == true) {
                                _excludedIds.remove(player.id);
                              } else {
                                _excludedIds.add(player.id);
                              }
                            }),
                            title: Text(player.fullName, style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                            dense: true,
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          )),
                    ],
                    if (_audience == 'individual') ...[
                      const SizedBox(height: 8),
                      _dropdown<String>(
                        value: _individualId ?? _players.first.id,
                        items: _players.map((p) => DropdownMenuItem(value: p.id, child: Text(p.fullName))).toList(),
                        onChanged: (value) => setState(() => _individualId = value),
                      ),
                    ],
                  ],
                  const SizedBox(height: 16),
                  Text(_t('physio_session_name'), style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _field(_sessionNameCtrl, _t('physio_session_name_hint')),
                  const SizedBox(height: 16),
                  Text(_t('scheduled_at'), style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  InkWell(onTap: _pickDateTime, child: IgnorePointer(child: _field(_dateTimeCtrl, _t('select_date_time')))),
                  const SizedBox(height: 10),
                  _durationField(),
                  const SizedBox(height: 10),
                  _field(_roomCtrl, _t('room')),
                  const SizedBox(height: 10),
                  _field(_bodyAreaCtrl, _t('body_area')),
                  const SizedBox(height: 10),
                  _dropdown<String>(
                    value: _reason,
                    items: ['recovery', 'pain', 'muscle_tightness', 'pre_match', 'post_match']
                        .map((v) => DropdownMenuItem(value: v, child: Text(_t('session_reason_$v')))).toList(),
                    onChanged: (value) => setState(() => _reason = value ?? 'recovery'),
                  ),
                  const SizedBox(height: 10),
                  _field(_treatmentCtrl, _t('treatment_type')),
                  const SizedBox(height: 10),
                  _dropdown<String>(
                    value: _intensity,
                    items: ['light', 'moderate', 'deep']
                        .map((v) => DropdownMenuItem(value: v, child: Text(_t('physio_intensity_$v')))).toList(),
                    onChanged: (value) => setState(() => _intensity = value ?? 'moderate'),
                  ),
                  const SizedBox(height: 10),
                  _field(_contraindicationsCtrl, _t('contraindications'), maxLines: 3),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _saving || _players.isEmpty ? null : _save,
                      icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.event_available_rounded),
                      label: Text(_t('physio_create_session_cta'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.foreground, elevation: 0),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _durationField() => TextField(
        controller: _durationCtrl,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: AppColors.foreground, fontSize: 14),
        decoration: _decoration(_t('physio_duration_minutes')).copyWith(
          suffixText: _t('unit_minutes_word'),
          suffixStyle: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );

  Widget _empty(String message) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
      );
}
