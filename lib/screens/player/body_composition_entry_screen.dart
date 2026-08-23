import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/body_composition_models.dart';
import '../../services/body_composition_service.dart';
import '../../utils/body_composition_calculator.dart';
import '../../widgets/common_widgets.dart';

class BodyCompositionEntryScreen extends StatefulWidget {
  const BodyCompositionEntryScreen({super.key, this.playerId, this.assessment});
  final String? playerId; // coach recording on behalf of a roster player
  final BodyCompositionEntry? assessment;

  @override
  State<BodyCompositionEntryScreen> createState() =>
      _BodyCompositionEntryScreenState();
}

class _SkinfoldSite {
  _SkinfoldSite(this.key, this.labelKey);
  final String key; // biceps | triceps | subscapular | suprailiac
  final String labelKey;
  final List<TextEditingController> attempts = List.generate(
    1,
    (_) => TextEditingController(),
  );

  void dispose() {
    for (final c in attempts) c.dispose();
  }

  List<double?> get values =>
      attempts.map((c) => double.tryParse(c.text)).toList();
}

class _BodyCompositionEntryScreenState
    extends State<BodyCompositionEntryScreen> {
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  final List<_SkinfoldSite> _sites = [
    _SkinfoldSite('biceps', 'bc_site_biceps'),
    _SkinfoldSite('triceps', 'bc_site_triceps'),
    _SkinfoldSite('subscapular', 'bc_site_subscapular'),
    _SkinfoldSite('suprailiac', 'bc_site_suprailiac'),
  ];

  String _assessmentType = 'periodic';
  DateTime _assessmentDate = DateTime.now();
  bool _submitting = false;

  static const _types = [
    'periodic',
    'season_start',
    'season_end',
    'camp_start',
    'camp_end',
    'pre_injury',
    'post_injury',
  ];

  @override
  void initState() {
    super.initState();
    final assessment = widget.assessment;
    if (assessment == null) return;
    _weightCtrl.text = assessment.weightKg.toString();
    if (assessment.heightCm > 0) {
      _heightCtrl.text = assessment.heightCm.toString();
    }
    _notesCtrl.text = assessment.notes ?? '';
    _assessmentType = assessment.assessmentType;
    _assessmentDate =
        DateTime.tryParse(assessment.assessmentDate) ?? DateTime.now();
    final values = <String, double?>{
      'biceps': assessment.bicepsMm,
      'triceps': assessment.tricepsMm,
      'subscapular': assessment.subscapularMm,
      'suprailiac': assessment.suprailiacMm,
    };
    for (final site in _sites) {
      final value = values[site.key];
      if (value != null) site.attempts.first.text = value.toString();
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _notesCtrl.dispose();
    _reasonCtrl.dispose();
    for (final s in _sites) s.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool isError = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: isError
              ? AppColors.destructive.withOpacity(0.9)
              : AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

  double? get _skinfoldSum {
    double sum = 0;
    bool any = false;
    for (final s in _sites) {
      final avg = BodyCompositionCalculator.averageAttempts(s.values);
      if (avg != null) {
        sum += avg;
        any = true;
      }
    }
    return any ? double.parse(sum.toStringAsFixed(1)) : null;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _assessmentDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _assessmentDate = picked);
  }

  Future<void> _submit() async {
    final weight = double.tryParse(_weightCtrl.text);
    final height = double.tryParse(_heightCtrl.text);
    if (weight == null || weight < 20 || weight > 250) {
      _snack(AppLocalizations.get('bc_weight_kg'), isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final assessment = widget.assessment;
      if (assessment?.approvalStatus == 'approved' &&
          _reasonCtrl.text.trim().isEmpty) {
        _snack('سبب التعديل مطلوب للقياس المعتمد', isError: true);
        return;
      }
      final Map<String, dynamic> res;
      if (assessment == null) {
        res = await BodyCompositionService.saveAssessment(
          weightKg: weight,
          heightCm: height,
          assessmentDate: _assessmentDate.toIso8601String().substring(0, 10),
          assessmentType: _assessmentType,
          bicepsAttempts: _attemptsMap(_sites[0]),
          tricepsAttempts: _attemptsMap(_sites[1]),
          subscapularAttempts: _attemptsMap(_sites[2]),
          suprailiacAttempts: _attemptsMap(_sites[3]),
          notes: _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
          assessedBy: currentUserName.isNotEmpty ? currentUserName : null,
          playerId: widget.playerId,
        );
      } else {
        final fields = <String, dynamic>{
          'weight_kg': weight,
          if (height != null) 'height_cm': height,
          'assessment_date': _assessmentDate.toIso8601String().substring(0, 10),
          'assessment_type': _assessmentType,
          'notes': _notesCtrl.text,
          if (_reasonCtrl.text.trim().isNotEmpty)
            'reason': _reasonCtrl.text.trim(),
        };
        for (final site in _sites) {
          final initial = _initialSiteValue(assessment, site.key);
          final currentText = site.attempts.first.text.trim();
          final current = double.tryParse(currentText);
          if (current != initial &&
              !(current == null && initial == null && currentText.isEmpty)) {
            fields['${site.key}_attempt_1_mm'] = current;
          }
        }
        res = await BodyCompositionService.updateAssessment(
          assessment.id,
          fields,
        );
      }
      if (!mounted) return;
      if (res['success'] == true) {
        _snack(
          assessment == null
              ? AppLocalizations.get('bc_save_success')
              : 'تم حفظ التعديل وإعادة القياس إلى مسودة',
        );
        final warnings = (res['warnings'] as List?)?.cast<String>() ?? [];
        for (final w in warnings) {
          _snack(w, isError: true);
        }
        Navigator.pop(context, true);
      } else {
        _snack(res['error']?.toString() ?? 'Error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Map<String, double?> _attemptsMap(_SkinfoldSite s) {
    return {'attempt_1_mm': s.values[0]};
  }

  double? _initialSiteValue(BodyCompositionEntry assessment, String site) {
    switch (site) {
      case 'biceps':
        return assessment.bicepsMm;
      case 'triceps':
        return assessment.tricepsMm;
      case 'subscapular':
        return assessment.subscapularMm;
      case 'suprailiac':
        return assessment.suprailiacMm;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canManageBodyComposition) return const RoleAccessDeniedPage();
    final isAr = getAppLanguage() == 'ar';
    final sum = _skinfoldSum;

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.foreground,
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.assessment == null
                ? AppLocalizations.get('bc_new_assessment')
                : 'تعديل القياس',
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(AppLocalizations.get('bc_general_info')),
              const SizedBox(height: 10),
              _label(AppLocalizations.get('bc_assessment_type')),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _assessmentType,
                decoration: _fieldDecoration(),
                dropdownColor: AppColors.card,
                items: _types
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(AppLocalizations.get('bc_type_$t')),
                      ),
                    )
                    .toList(),
                onChanged: (v) =>
                    setState(() => _assessmentType = v ?? 'periodic'),
                style: const TextStyle(color: AppColors.foreground),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _assessmentDate.toIso8601String().substring(0, 10),
                        style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(
                        Icons.calendar_today_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _label(AppLocalizations.get('bc_weight_kg')),
              const SizedBox(height: 6),
              _numField(_weightCtrl, onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              _label(AppLocalizations.get('bc_height_cm')),
              const SizedBox(height: 6),
              _numField(_heightCtrl, onChanged: (_) => setState(() {})),

              const SizedBox(height: 24),
              _sectionLabel(AppLocalizations.get('bc_skinfolds_title')),
              const SizedBox(height: 10),
              ..._sites.map(_buildSiteCard),

              const SizedBox(height: 14),
              _label(AppLocalizations.get('bc_notes')),
              const SizedBox(height: 6),
              _numField(_notesCtrl, isNumeric: false, maxLines: 3),
              if (widget.assessment?.approvalStatus == 'approved') ...[
                const SizedBox(height: 14),
                _label('سبب تعديل القياس المعتمد'),
                const SizedBox(height: 6),
                _numField(_reasonCtrl, isNumeric: false, maxLines: 2),
              ],

              const SizedBox(height: 18),
              if (sum != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.28),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppLocalizations.get('bc_skinfold_sum'),
                        style: TextStyle(
                          color: AppColors.foreground.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${sum.toStringAsFixed(1)} mm',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.foreground,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(
                              AppColors.foreground,
                            ),
                          ),
                        )
                      : Text(
                          widget.assessment == null
                              ? AppLocalizations.get('bc_save_assessment')
                              : 'حفظ التعديل',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSiteCard(_SkinfoldSite site) {
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
          Text(
            AppLocalizations.get(site.labelKey),
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: site.attempts[0],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: AppLocalizations.get('bc_value_mm'),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            style: const TextStyle(color: AppColors.foreground),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: AppColors.foreground,
      fontWeight: FontWeight.w800,
      fontSize: 15,
    ),
  );

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      color: AppColors.foreground.withOpacity(0.65),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );

  InputDecoration _fieldDecoration() => InputDecoration(
    filled: true,
    fillColor: AppColors.card,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _numField(
    TextEditingController ctrl, {
    Function(String)? onChanged,
    bool isNumeric = true,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
      maxLines: maxLines,
      keyboardType: isNumeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary.withOpacity(0.5)),
        ),
      ),
      style: const TextStyle(
        color: AppColors.foreground,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    );
  }
}
