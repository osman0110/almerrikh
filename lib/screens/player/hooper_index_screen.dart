import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../services/player_monitoring_service.dart';

class HooperIndexScreen extends StatefulWidget {
  const HooperIndexScreen({super.key, this.sessionId});

  /// Optional club session/match id — links this check-in to that
  /// session/match instead of saving as a standalone daily entry.
  final String? sessionId;

  @override
  State<HooperIndexScreen> createState() => _HooperIndexScreenState();
}

class _HooperIndexScreenState extends State<HooperIndexScreen> {
  int sleep = 4, fatigue = 4, stress = 4, soreness = 4, mood = 4;
  double? sleepHours;
  String? notes;
  bool painToday = false;
  String? painLocation;
  bool _submitting = false;

  int get hooper => sleep + fatigue + stress + soreness;

  String get _status {
    if (hooper <= 10) return 'طبيعي';
    if (hooper <= 16) return 'متوسط';
    return 'خطر عالٍ';
  }

  Color get _statusColor {
    if (hooper <= 10) return AppColors.success;
    if (hooper <= 16) return AppColors.warning;
    return AppColors.destructive;
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final res = await PlayerMonitoringService.saveHooper(
        sleepQuality: sleep,
        fatigue: fatigue,
        stress: stress,
        muscleSoreness: soreness,
        sleepHours: sleepHours,
        mood: mood,
        painToday: painToday,
        painLocation: painToday ? painLocation : null,
        notes: notes,
        sessionId: widget.sessionId,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        _snack('تم حفظ الفحص بنجاح ✓');
        Navigator.pop(context);
      } else {
        final error = res['error']?.toString();
        _snack(error == 'hooper_not_available'
            ? AppLocalizations.get('hooper_not_available')
            : res['message']?.toString() ?? error ?? 'حدث خطأ');
      }
    } catch (_) {
      if (mounted) _snack('حدث خطأ في الاتصال');
    }
    if (mounted) setState(() => _submitting = false);
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.foreground, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('فحص الجاهزية قبل التدريب',
              style: TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ── Hooper Score Card ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 24, horizontal: 20),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _statusColor.withOpacity(0.4)),
                ),
                child: Column(
                  children: [
                    Text('مؤشر هوبر',
                        style: TextStyle(
                            color: _statusColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 10),
                    Text(
                      hooper.toString(),
                      style: TextStyle(
                          color: _statusColor,
                          fontSize: 52,
                          fontWeight: FontWeight.w900,
                          height: 1.0),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(_status,
                          style: TextStyle(
                              color: _statusColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusGuide,
                      style: TextStyle(
                          color: AppColors.foreground.withOpacity(0.38),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Sliders ────────────────────────────────────────────────
              _SliderGroup(
                label: 'جودة النوم',
                value: sleep,
                onChanged: (v) => setState(() => sleep = v),
                labels: const [
                  'ضعيف', '', '', '', 'طبيعي', '', 'ممتاز'
                ],
              ),
              const SizedBox(height: 18),
              _SliderGroup(
                label: 'مستوى الإجهاد',
                value: fatigue,
                onChanged: (v) => setState(() => fatigue = v),
                labels: const [
                  'نشيط', '', '', '', 'طبيعي', '', 'منهك'
                ],
              ),
              const SizedBox(height: 18),
              _SliderGroup(
                label: 'مستوى التوتر',
                value: stress,
                onChanged: (v) => setState(() => stress = v),
                labels: const [
                  'هادئ', '', '', '', 'طبيعي', '', 'متوتر'
                ],
              ),
              const SizedBox(height: 18),
              _SliderGroup(
                label: 'ألم العضلات',
                value: soreness,
                onChanged: (v) => setState(() => soreness = v),
                labels: const [
                  'لا يوجد', '', '', '', 'طبيعي', '', 'شديد'
                ],
              ),
              const SizedBox(height: 18),
              _SliderGroup(
                label: 'المزاج',
                value: mood,
                onChanged: (v) => setState(() => mood = v),
                labels: const [
                  'سيء', '', '', '', 'طبيعي', '', 'ممتاز'
                ],
              ),
              const SizedBox(height: 20),

              // ── Pain flag + location ───────────────────────────────────
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('هل تشعر بألم اليوم؟',
                            style: TextStyle(
                                color: AppColors.foreground,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        Switch(
                          value: painToday,
                          activeColor: AppColors.primary,
                          onChanged: (v) => setState(() {
                            painToday = v;
                            if (!v) painLocation = null;
                          }),
                        ),
                      ],
                    ),
                    if (painToday) ...[
                      const SizedBox(height: 8),
                      _inputLabel('مكان الألم'),
                      const SizedBox(height: 6),
                      _OptionalTextField(
                        onChanged: (v) => painLocation = v.isEmpty ? null : v,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Optional fields ────────────────────────────────────────
              _inputLabel('ساعات النوم (اختياري)'),
              const SizedBox(height: 6),
              _OptionalTextField(
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => sleepHours = double.tryParse(v),
              ),
              const SizedBox(height: 14),
              _inputLabel('ملاحظات (اختياري)'),
              const SizedBox(height: 6),
              _OptionalTextField(
                maxLines: 3,
                onChanged: (v) => notes = v.isEmpty ? null : v,
              ),
              const SizedBox(height: 28),

              // ── Submit ─────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.foreground,
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(AppColors.foreground)),
                        )
                      : const Text('إرسال الفحص',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  String get _statusGuide {
    if (hooper <= 10) return 'النطاق الطبيعي (4–10)';
    if (hooper <= 16) return 'تقدم بحذر (11–16)';
    return 'احتمال إجهاد عالٍ (17–28)';
  }

  Widget _inputLabel(String text) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(text,
            style: TextStyle(
                color: AppColors.foreground.withOpacity(0.65),
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      );
}

class _SliderGroup extends StatelessWidget {
  const _SliderGroup({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.labels,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    value.toString(),
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 1,
            max: 7,
            divisions: 6,
            onChanged: (v) => onChanged(v.toInt()),
            activeColor: AppColors.primary,
            inactiveColor: AppColors.foreground.withOpacity(0.1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (int i = 0; i < labels.length; i++)
                Expanded(
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 9,
                        color: AppColors.foreground.withOpacity(0.4)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionalTextField extends StatelessWidget {
  const _OptionalTextField({this.keyboardType, this.maxLines, required this.onChanged});
  final TextInputType? keyboardType;
  final int? maxLines;
  final Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      keyboardType: keyboardType,
      maxLines: maxLines ?? 1,
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.card,
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: AppColors.primary.withOpacity(0.5)),
        ),
      ),
      style: const TextStyle(color: AppColors.foreground),
    );
  }
}
