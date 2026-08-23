import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';

/// Admin/coach sidebar action — write a free-text alert and push it to a
/// player, a set of players, or the whole club as an in-app + push
/// notification (backend: api/alerts/send.php).
class SendAlertPage extends StatefulWidget {
  const SendAlertPage({super.key});

  @override
  State<SendAlertPage> createState() => _SendAlertPageState();
}

class _SendAlertPageState extends State<SendAlertPage> {
  final _titleCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();

  List<ClubPlayer> _players = [];
  final Set<String> _selectedIds = {};
  String _target = 'individual';
  String _playerQuery = '';
  bool _loading = true;
  bool _sending = false;

  String _t(String key) => AppLocalizations.get(key);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final players = (await ClubService().getPlayers())
        .where((p) => p.status == PlayerStatus.active)
        .toList();
    if (!mounted) return;
    setState(() {
      _players = players;
      _loading = false;
    });
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

  Widget _field(TextEditingController controller, String hint, {int maxLines = 1}) {
    return TextField(
      controller: controller,
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

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final message = _messageCtrl.text.trim();
    if (title.isEmpty || message.isEmpty) {
      _snack(_t('error_generic'));
      return;
    }
    if (_target == 'individual' && _selectedIds.isEmpty) {
      _snack(_t('alert_no_players_selected'));
      return;
    }

    setState(() => _sending = true);
    final response = await ApiService.sendAlert(
      title: title,
      message: message,
      target: _target,
      playerIds: _selectedIds.toList(),
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (response['success'] == true) {
      _snack(_t('alert_sent_success'));
      Navigator.of(context).pop(true);
      return;
    }
    _snack(response['message']?.toString() ?? _t('alert_send_failed'));
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
          title: Text(_t('send_alert_title'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
          iconTheme: const IconThemeData(color: AppColors.foreground),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(_t('alert_recipients_label'),
                      style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _dropdown<String>(
                    value: _target,
                    items: [
                      DropdownMenuItem(value: 'individual', child: Text(_t('alert_target_individual'))),
                      DropdownMenuItem(value: 'club', child: Text(_t('alert_target_club'))),
                    ],
                    onChanged: (value) => setState(() => _target = value ?? 'individual'),
                  ),
                  if (_target == 'individual') ...[
                    const SizedBox(height: 8),
                    Text('${_t('alert_recipients_label')}: ${_selectedIds.length}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (value) => setState(() => _playerQuery = value),
                      style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                      decoration: _decoration(_t('search_players')),
                    ),
                    const SizedBox(height: 4),
                    if (_players.isEmpty)
                      _empty(_t('physio_no_active_players'))
                    else
                      ..._visiblePlayers.map((player) => CheckboxListTile(
                            value: _selectedIds.contains(player.id),
                            onChanged: (selected) => setState(() {
                              if (selected == true) {
                                _selectedIds.add(player.id);
                              } else {
                                _selectedIds.remove(player.id);
                              }
                            }),
                            title: Text(player.fullName, style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                            dense: true,
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          )),
                  ],
                  const SizedBox(height: 16),
                  Text(_t('alert_title_label'), style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _field(_titleCtrl, _t('alert_title_hint')),
                  const SizedBox(height: 16),
                  Text(_t('alert_message_label'), style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _field(_messageCtrl, _t('alert_message_hint'), maxLines: 5),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.campaign_rounded),
                      label: Text(_t('alert_send_btn'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.foreground, elevation: 0),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _empty(String message) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Text(message, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
      );
}
