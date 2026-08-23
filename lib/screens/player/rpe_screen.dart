import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/session_models.dart';
import '../../services/player_monitoring_service.dart';
import 'session_widgets.dart';
import 'session_summary_screen.dart';

class RpeScreen extends StatefulWidget {
  const RpeScreen({
    super.key,
    required this.sessionId,
    this.sessionTitle,
    this.durationMinutes,
    this.hooperScore,
    this.preRpe,
    this.completeSession = false,
  });

  final String? sessionId;
  final String? sessionTitle;
  final int? durationMinutes;
  final int? hooperScore;
  final int? preRpe;
  final bool completeSession;

  @override
  State<RpeScreen> createState() => _RpeScreenState();
}

class _RpeScreenState extends State<RpeScreen> {
  int? _selectedRpe;
  bool? _painReported;
  bool _submitting = false;

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submit() async {
    if (_selectedRpe == null) {
      _snack(AppLocalizations.get('rpe_select_first'));
      return;
    }
    if (widget.sessionId == null || widget.sessionId!.isEmpty) {
      _snack(AppLocalizations.get('rpe_context_required'));
      return;
    }
    if (!widget.completeSession &&
        (widget.durationMinutes == null || widget.durationMinutes! <= 0)) {
      _snack(AppLocalizations.get('rpe_duration_missing'));
      return;
    }
    if (widget.completeSession && _painReported == null) {
      _snack(AppLocalizations.get('rpe_pain_required'));
      return;
    }

    setState(() => _submitting = true);
    final result = widget.completeSession
        ? await ApiService.savePostTrainingFeedback(
            sessionId: widget.sessionId!,
            postRpe: _selectedRpe!,
            durationMinutes: widget.durationMinutes,
            painReported: _painReported!,
          )
        : await PlayerMonitoringService.saveRpe(
            rpeScore: _selectedRpe!,
            durationMinutes: widget.durationMinutes,
            sessionId: widget.sessionId,
          );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result['success'] == true) {
      if (widget.completeSession) {
        final trainingLoad =
            (result['training_load'] as num?)?.round() ??
            (_selectedRpe! * (widget.durationMinutes ?? 0));
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SessionSummaryScreen(
              completion: SessionCompletionData(
                sessionId: widget.sessionId!,
                sessionTitle:
                    widget.sessionTitle ??
                    AppLocalizations.get('todays_session_label'),
                hoooperScore: widget.hooperScore,
                preRpe: widget.preRpe,
                postRpe: _selectedRpe!,
                painReported: _painReported!,
                trainingLoad: trainingLoad,
                durationMinutes: widget.durationMinutes ?? 0,
              ),
            ),
          ),
        );
        return;
      }
      _snack(
        result['updated'] == true
            ? AppLocalizations.get('rpe_updated')
            : AppLocalizations.get('rpe_submitted'),
      );
      Navigator.of(context).pop(true);
      return;
    }

    final error = result['error']?.toString();
    final message = switch (error) {
      'edit_window_expired' => AppLocalizations.get(
        'rpe_edit_window_expired',
      ),
      'rpe_not_available' => AppLocalizations.get('rpe_not_available'),
      'rpe_not_participated' => AppLocalizations.get('rpe_not_participated'),
      'participation_minutes_missing' =>
        AppLocalizations.get('rpe_participation_minutes_missing'),
      _ =>
        result['message']?.toString() ??
            error ??
            AppLocalizations.get('error_generic'),
    };
    _snack(message);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.foreground,
          elevation: 0,
          title: Text(
            AppLocalizations.get('rpe_screen_title'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppLocalizations.get('rpe_question'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.get('rpe_hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: 11,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final value = index;
                      final active = value == _selectedRpe;
                      final label = _ratingLabel(value);
                      return Semantics(
                        button: true,
                        selected: active,
                        label: '$value $label',
                        child: InkWell(
                          onTap: () => setState(() => _selectedRpe = value),
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primary.withOpacity(0.12)
                                  : AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: active
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: active ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: active
                                        ? AppColors.primary
                                        : AppColors.surface2,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$value',
                                    style: TextStyle(
                                      color: active
                                          ? Colors.white
                                          : AppColors.foreground,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: active
                                          ? AppColors.primary
                                          : AppColors.foreground,
                                      fontSize: 13.5,
                                      fontWeight: active
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (active)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (widget.completeSession) ...[
                  const SizedBox(height: 18),
                  Text(
                    AppLocalizations.get('rpe_pain_question'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SessionToggleBtn(
                          label: AppLocalizations.get('rpe_no_pain'),
                          selected: _painReported == false,
                          color: AppColors.success,
                          onTap: () => setState(() => _painReported = false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SessionToggleBtn(
                          label: AppLocalizations.get('rpe_has_pain'),
                          selected: _painReported == true,
                          color: AppColors.destructive,
                          onTap: () => setState(() => _painReported = true),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed:
                        _selectedRpe == null ||
                            (widget.completeSession && _painReported == null) ||
                            _submitting
                        ? null
                        : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.border,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            AppLocalizations.get('rpe_submit'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Modified Borg CR10 (Foster) scale used for session-RPE training load.
  String _ratingLabel(int value) => AppLocalizations.get('rpe_level_$value');
}
