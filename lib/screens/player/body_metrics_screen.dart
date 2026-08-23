import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/monitoring_models.dart';
import '../../services/player_monitoring_service.dart';
import '../../utils/metric_formatter.dart';

class BodyMetricsScreen extends StatefulWidget {
  const BodyMetricsScreen({super.key});

  @override
  State<BodyMetricsScreen> createState() => _BodyMetricsScreenState();
}

class _BodyMetricsScreenState extends State<BodyMetricsScreen> {
  late TextEditingController _weightCtrl, _heightCtrl, _fatCtrl;
  late TextEditingController _waistCtrl,
      _deviceCtrl,
      _measuredByCtrl,
      _specialistNotesCtrl;
  BodyMetric? latest;
  bool loading = true;
  double? _bmiDisplay;
  bool _submitting = false;
  String? _measurementMethod;

  static const _methods = {
    'caliper': 'كاليبر (Caliper)',
    'bia': 'تحليل المقاومة الكهربية (BIA)',
    'dexa': 'DEXA',
    'visual_estimate': 'تقدير بصري',
    'other': 'أخرى',
  };

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController();
    _heightCtrl = TextEditingController();
    _fatCtrl = TextEditingController();
    _waistCtrl = TextEditingController();
    _deviceCtrl = TextEditingController();
    _measuredByCtrl = TextEditingController();
    _specialistNotesCtrl = TextEditingController();
    _loadLatest();
  }

  void _loadLatest() async {
    try {
      final res = await PlayerMonitoringService.getLatestBodyMetrics();
      if (res['metric'] != null) {
        final m = BodyMetric.fromJson(res['metric']);
        setState(() {
          latest = m;
          _weightCtrl.text = m.weightKg?.toString() ?? '';
          _heightCtrl.text = m.heightCm?.toString() ?? '';
          _fatCtrl.text = m.bodyFatPercent?.toString() ?? '';
          _bmiDisplay = m.bmi;
        });
      }
    } catch (_) {}
    setState(() => loading = false);
  }

  void _updateBmi() {
    final w = double.tryParse(_weightCtrl.text);
    final h = double.tryParse(_heightCtrl.text);
    if (w != null && h != null && h > 0) {
      final hm = h / 100;
      final bmi = w / (hm * hm);
      setState(() => _bmiDisplay = double.parse(bmi.toStringAsFixed(1)));
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

  Future<void> _submit() async {
    final w = double.tryParse(_weightCtrl.text);
    final h = double.tryParse(_heightCtrl.text);
    final f = double.tryParse(_fatCtrl.text);

    if (w == null || h == null || f == null) {
      _snack('يرجى ملء جميع الحقول');
      return;
    }
    if (w < 20 || w > 300) {
      _snack('الوزن يجب أن يكون بين 20 و 300 كغ');
      return;
    }
    if (h < 100 || h > 250) {
      _snack('الطول يجب أن يكون بين 100 و 250 سم');
      return;
    }
    if (f < 1 || f > 60) {
      _snack('نسبة الدهون يجب أن تكون بين 1 و 60%');
      return;
    }

    final waist = double.tryParse(_waistCtrl.text);

    setState(() => _submitting = true);
    try {
      final res = await PlayerMonitoringService.saveBodyMetrics(
        weightKg: w,
        heightCm: h,
        bodyFatPercent: f,
        waistCm: waist,
        measurementMethod: _measurementMethod,
        deviceName: _deviceCtrl.text.isEmpty ? null : _deviceCtrl.text,
        measuredBy: _measuredByCtrl.text.isEmpty ? null : _measuredByCtrl.text,
        specialistNotes: _specialistNotesCtrl.text.isEmpty
            ? null
            : _specialistNotesCtrl.text,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        _snack('تم الحفظ بنجاح ✓');
        _loadLatest();
      } else {
        _snack(res['error']?.toString() ?? 'حدث خطأ');
      }
    } catch (_) {
      if (mounted) _snack('حدث خطأ في الاتصال');
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _fatCtrl.dispose();
    _waistCtrl.dispose();
    _deviceCtrl.dispose();
    _measuredByCtrl.dispose();
    _specialistNotesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
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
          title: const Text(
            'المقاييس الجسدية',
            style: TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ),
        body: loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Latest Record ──────────────────────────────────────
                    if (latest != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'آخر قياس',
                              style: TextStyle(
                                color: AppColors.foreground.withOpacity(0.5),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _StatTile(
                                  'الوزن',
                                  MetricFormatter.weight(latest!.weightKg),
                                ),
                                _StatTile(
                                  'الطول',
                                  MetricFormatter.height(latest!.heightCm),
                                ),
                                _StatTile(
                                  'الدهون',
                                  MetricFormatter.bodyFat(
                                    latest!.bodyFatPercent,
                                  ),
                                ),
                              ],
                            ),
                            Builder(
                              builder: (_) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Column(
                                    children: [
                                      _metricRow(
                                        'كتلة الدهون (Fat Mass)',
                                        MetricFormatter.fatMass(
                                          latest!.fatMassKg,
                                        ),
                                        AppColors.warning,
                                      ),
                                      const SizedBox(height: 8),
                                      _metricRow(
                                        'الكتلة الخالية من الدهون (FFM)',
                                        MetricFormatter.fatFreeMass(
                                          latest!.leanMassKg,
                                        ),
                                        AppColors.primary,
                                      ),
                                      if (latest!.waistCm != null) ...[
                                        const SizedBox(height: 8),
                                        _metricRow(
                                          'محيط الخصر',
                                          '${latest!.waistCm!.toStringAsFixed(1)} سم',
                                          AppColors.success,
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                            if (latest!.bmiForAgeCategory != null) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'BMI بحسب العمر (تقريبي)',
                                      style: TextStyle(
                                        color: AppColors.foreground.withOpacity(
                                          0.55,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      _bmiForAgeLabel(
                                        latest!.bmiForAgeCategory!,
                                      ),
                                      style: const TextStyle(
                                        color: AppColors.foreground,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (latest!.measurementMethod != null ||
                                latest!.measuredBy != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                [
                                  if (latest!.measurementMethod != null)
                                    _methods[latest!.measurementMethod] ??
                                        latest!.measurementMethod!,
                                  if (latest!.deviceName != null)
                                    latest!.deviceName!,
                                  if (latest!.measuredBy != null)
                                    'بواسطة ${latest!.measuredBy}',
                                ].join(' · '),
                                style: TextStyle(
                                  color: AppColors.foreground.withOpacity(0.35),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            if (latest!.specialistNotes != null &&
                                latest!.specialistNotes!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'ملاحظات المختص: ${latest!.specialistNotes}',
                                style: TextStyle(
                                  color: AppColors.foreground.withOpacity(0.5),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            if (latest!.bmi != null) ...[
                              const SizedBox(height: 14),
                              Divider(
                                color: AppColors.foreground.withOpacity(0.07),
                                height: 1,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Builder(
                                    builder: (_) {
                                      final (label, cat) = _bmiCategory(
                                        latest!.bmi!,
                                      );
                                      return Row(
                                        children: [
                                          Text(
                                            'BMI: ${latest!.bmi!.toStringAsFixed(1)}',
                                            style: TextStyle(
                                              color: cat,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: cat.withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                color: cat,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // ── Input Form ─────────────────────────────────────────
                    _inputLabel('الوزن (كغ)'),
                    const SizedBox(height: 6),
                    _TextField(
                      ctrl: _weightCtrl,
                      onChanged: (_) => _updateBmi(),
                    ),
                    const SizedBox(height: 14),
                    _inputLabel('الطول (سم)'),
                    const SizedBox(height: 6),
                    _TextField(
                      ctrl: _heightCtrl,
                      onChanged: (_) => _updateBmi(),
                    ),
                    const SizedBox(height: 14),
                    _inputLabel('نسبة الدهون %'),
                    const SizedBox(height: 6),
                    _TextField(ctrl: _fatCtrl),
                    const SizedBox(height: 14),
                    _inputLabel('محيط الخصر (سم) — اختياري'),
                    const SizedBox(height: 6),
                    _TextField(ctrl: _waistCtrl),
                    const SizedBox(height: 14),
                    _inputLabel('طريقة القياس — اختياري'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _measurementMethod,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      dropdownColor: AppColors.card,
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        ..._methods.entries.map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _measurementMethod = v),
                      style: const TextStyle(color: AppColors.foreground),
                    ),
                    const SizedBox(height: 14),
                    _inputLabel('اسم الجهاز — اختياري'),
                    const SizedBox(height: 6),
                    _TextField(ctrl: _deviceCtrl, isNumeric: false),
                    const SizedBox(height: 14),
                    _inputLabel('اسم/صفة من قام بالقياس — اختياري'),
                    const SizedBox(height: 6),
                    _TextField(ctrl: _measuredByCtrl, isNumeric: false),
                    const SizedBox(height: 14),
                    _inputLabel('ملاحظات المختص — اختياري'),
                    const SizedBox(height: 6),
                    _TextField(
                      ctrl: _specialistNotesCtrl,
                      isNumeric: false,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 18),

                    // ── BMI Preview ────────────────────────────────────────
                    if (_bmiDisplay != null)
                      Builder(
                        builder: (_) {
                          final (label, cat) = _bmiCategory(_bmiDisplay!);
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: cat.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: cat.withOpacity(0.28)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'مؤشر كتلة الجسم',
                                  style: TextStyle(
                                    color: AppColors.foreground.withOpacity(
                                      0.55,
                                    ),
                                    fontSize: 13,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      _bmiDisplay!.toStringAsFixed(1),
                                      style: TextStyle(
                                        color: cat,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: cat.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: cat.withOpacity(0.30),
                                        ),
                                      ),
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          color: cat,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
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
                            : const Text(
                                'حفظ القياسات',
                                style: TextStyle(
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

  Widget _inputLabel(String text) => Text(
    text,
    style: TextStyle(
      color: AppColors.foreground.withOpacity(0.65),
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _metricRow(String label, String value, Color color) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          color: AppColors.foreground.withOpacity(0.55),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    ],
  );

  String _bmiForAgeLabel(String category) {
    switch (category) {
      case 'underweight':
        return 'نقص وزن (للعمر)';
      case 'healthy':
        return 'طبيعي (للعمر)';
      case 'overweight':
        return 'زيادة وزن (للعمر)';
      case 'obese':
        return 'سمنة (للعمر)';
      default:
        return category;
    }
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.ctrl,
    this.onChanged,
    this.isNumeric = true,
    this.maxLines = 1,
  });
  final TextEditingController ctrl;
  final Function(String)? onChanged;
  final bool isNumeric;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
      maxLines: maxLines,
      keyboardType: isNumeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textAlign: TextAlign.start,
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

(String, Color) _bmiCategory(double bmi) {
  if (bmi < 18.5) return ('نقص الوزن', Colors.blue);
  if (bmi < 25.0) return ('طبيعي', AppColors.success);
  if (bmi < 30.0) return ('زيادة الوزن', AppColors.warning);
  return ('سمنة', AppColors.destructive);
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.foreground,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.foreground.withOpacity(0.5),
          ),
        ),
      ],
    );
  }
}
