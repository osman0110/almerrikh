import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/session_models.dart';
import 'session_widgets.dart';

class PreTrainingWellnessScreen extends StatefulWidget {
  const PreTrainingWellnessScreen({super.key, required this.session});
  final PlayerSessionData session;

  @override
  State<PreTrainingWellnessScreen> createState() =>
      _PreTrainingWellnessScreenState();
}

class _PreTrainingWellnessScreenState
    extends State<PreTrainingWellnessScreen> {
  int  _fatigue      = 0;
  int  _stress       = 0;
  int  _soreness     = 0;
  int  _sleepQuality = 0;
  int  _preRpe       = 0;
  bool _painToday    = false;
  final _notesCtrl   = TextEditingController();
  bool _submitting   = false;

  int get _hoooperIndex =>
      _fatigue + _stress + _soreness + _sleepQuality;

  bool get _isValid =>
      _fatigue > 0 && _stress > 0 && _soreness > 0 &&
      _sleepQuality > 0 && _preRpe > 0;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid || _submitting) return;
    setState(() => _submitting = true);
    final res = await ApiService.saveSessionPreCheck(
      sessionId:      widget.session.id,
      sleepQuality:   _sleepQuality,
      fatigue:        _fatigue,
      stress:         _stress,
      muscleSoreness: _soreness,
      preRpe:         _preRpe,
      painToday:      _painToday,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.containsKey('error')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['error'] as String),
        backgroundColor: AppColors.destructive,
      ));
      return;
    }
    Navigator.of(context).pushReplacementNamed(
      '/player/session/run',
      arguments: widget.session,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.foreground.withOpacity(0.70), size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(AppLocalizations.get('pre_training'),
            style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 17)),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SessionChip(session: widget.session),
                  const SizedBox(height: 16),
                  if (_isValid) ...[
                    _HooperBadge(score: _hoooperIndex),
                    const SizedBox(height: 16),
                  ],
                  _buildField(
                    label: AppLocalizations.get('fatigue_label'),
                    hint: AppLocalizations.get('wellness_fatigue_hint'),
                    value: _fatigue,
                    count: 7,
                    color: const Color(0xffef4444),
                    onChanged: (v) => setState(() => _fatigue = v),
                  ),
                  _buildField(
                    label: AppLocalizations.get('stress_label'),
                    hint: AppLocalizations.get('wellness_stress_hint'),
                    value: _stress,
                    count: 7,
                    color: const Color(0xfff59e0b),
                    onChanged: (v) => setState(() => _stress = v),
                  ),
                  _buildField(
                    label: AppLocalizations.get('muscle_soreness'),
                    hint: AppLocalizations.get('wellness_soreness_hint'),
                    value: _soreness,
                    count: 7,
                    color: const Color(0xffF97316),
                    onChanged: (v) => setState(() => _soreness = v),
                  ),
                  _buildField(
                    label: AppLocalizations.get('sleep_quality'),
                    hint: AppLocalizations.get('wellness_sleep_hint'),
                    value: _sleepQuality,
                    count: 7,
                    color: const Color(0xff8B5CF6),
                    onChanged: (v) => setState(() => _sleepQuality = v),
                  ),
                  _buildField(
                    label: AppLocalizations.get('wellness_expected_rpe'),
                    hint: AppLocalizations.get('wellness_rpe_hint'),
                    value: _preRpe,
                    count: 10,
                    color: AppColors.primary,
                    onChanged: (v) => setState(() => _preRpe = v),
                  ),
                  const SizedBox(height: 20),
                  _label(AppLocalizations.get('pain_today_question')),
                  const SizedBox(height: 10),
                  SessionPainToggle(
                    value: _painToday,
                    noPainLabel: AppLocalizations.get('rpe_no_pain'),
                    painLabel: AppLocalizations.get('rpe_has_pain'),
                    onChanged: (v) => setState(() => _painToday = v),
                  ),
                  const SizedBox(height: 20),
                  _label(AppLocalizations.get('notes_optional')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                    decoration: sessionInputDecoration(
                        AppLocalizations.get('pretraining_notes_hint')),
                  ),
                ],
              ),
            ),
          ),
          SessionSubmitBar(
            label: AppLocalizations.get('start_training'),
            enabled: _isValid,
            loading: _submitting,
            onTap: _submit,
          ),
        ]),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required int value,
    required int count,
    required Color color,
    required ValueChanged<int> onChanged,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(label),
        const SizedBox(height: 10),
        SessionNumberSelector(
            value: value, count: count, activeColor: color, onChanged: onChanged),
        _RangeHint(hint),
        const SizedBox(height: 4),
      ]);

  static Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(t,
            style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w700,
                fontSize: 14)),
      );
}

// ── Screen-local widgets ──────────────────────────────────────────────────────

class _SessionChip extends StatelessWidget {
  const _SessionChip({required this.session});
  final PlayerSessionData session;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.fitness_center_rounded,
              color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(session.title,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
          Text(
              '${session.durationMinutes} ${AppLocalizations.get('min_suffix')}',
              style: TextStyle(
                  color: AppColors.foreground.withOpacity(0.45), fontSize: 12)),
        ]),
      );
}

class _HooperBadge extends StatelessWidget {
  const _HooperBadge({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    if (score <= 10) {
      color = AppColors.success;
      label = AppLocalizations.get('wellness_ready');
    } else if (score <= 16) {
      color = AppColors.warning;
      label = AppLocalizations.get('wellness_reduce_intensity');
    } else {
      color = AppColors.destructive;
      label = AppLocalizations.get('wellness_recovery_recommended');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(children: [
        Icon(Icons.monitor_heart_rounded, color: color, size: 18),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${AppLocalizations.get('hooper_index')}: $score',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 14)),
          Text(label,
              style:
                  TextStyle(color: color.withOpacity(0.75), fontSize: 12)),
        ]),
      ]),
    );
  }
}

class _RangeHint extends StatelessWidget {
  const _RangeHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(text,
            style: TextStyle(
                color: AppColors.foreground.withOpacity(0.35), fontSize: 11)),
      );
}
