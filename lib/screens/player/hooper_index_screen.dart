import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../services/player_monitoring_service.dart';

class HooperIndexScreen extends StatefulWidget {
  const HooperIndexScreen({super.key});

  @override
  State<HooperIndexScreen> createState() => _HooperIndexScreenState();
}

class _HooperIndexScreenState extends State<HooperIndexScreen> {
  int sleep = 4, fatigue = 4, stress = 4, soreness = 4;
  double? sleepHours;
  String? notes;
  bool _submitting = false;
  int get hooper => sleep + fatigue + stress + soreness;

  String get _status {
    if (hooper <= 10) return 'Normal';
    if (hooper <= 16) return 'Moderate';
    return 'High Risk';
  }

  Color get _statusColor {
    if (hooper <= 10) return AppColors.success;
    if (hooper <= 16) return AppColors.warning;
    return AppColors.destructive;
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final res = await PlayerMonitoringService.saveHooper(
        sleepQuality: sleep,
        fatigue: fatigue,
        stress: stress,
        muscleSoreness: soreness,
        sleepHours: sleepHours,
        notes: notes,
      );
      if (res['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wellness check saved')));
        Navigator.pop(context);
      }
    } catch (_) {}
    setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Pre-Training Wellness'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Hooper Score Display
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _statusColor.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  Text(
                    'Hooper Index',
                    style: TextStyle(color: _statusColor, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hooper.toString(),
                    style: TextStyle(color: _statusColor, fontSize: 42, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _status,
                    style: TextStyle(color: _statusColor, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Sleep Quality
            _SliderGroup(
              label: 'Sleep Quality',
              value: sleep,
              onChanged: (v) => setState(() => sleep = v),
              labels: const ['Poor', '', '', '', 'Normal', '', 'Excellent'],
            ),
            const SizedBox(height: 16),

            // Fatigue
            _SliderGroup(
              label: 'Fatigue Level',
              value: fatigue,
              onChanged: (v) => setState(() => fatigue = v),
              labels: const ['Fresh', '', '', '', 'Normal', '', 'Exhausted'],
            ),
            const SizedBox(height: 16),

            // Stress
            _SliderGroup(
              label: 'Stress Level',
              value: stress,
              onChanged: (v) => setState(() => stress = v),
              labels: const ['Calm', '', '', '', 'Normal', '', 'Very Stressed'],
            ),
            const SizedBox(height: 16),

            // Muscle Soreness
            _SliderGroup(
              label: 'Muscle Soreness',
              value: soreness,
              onChanged: (v) => setState(() => soreness = v),
              labels: const ['None', '', '', '', 'Normal', '', 'Severe'],
            ),
            const SizedBox(height: 16),

            // Sleep Hours
            TextField(
              onChanged: (v) => sleepHours = double.tryParse(v),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Sleep Hours (optional)',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),

            // Notes
            TextField(
              onChanged: (v) => notes = v.isEmpty ? null : v,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 24),

            // Submit
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text('Submit Check-In', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value.toString(),
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: value.toDouble(),
          min: 1,
          max: 7,
          divisions: 6,
          onChanged: (v) => onChanged(v.toInt()),
          activeColor: AppColors.primary,
          inactiveColor: Colors.white.withOpacity(0.1),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (int i = 0; i < labels.length; i++)
              Expanded(
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.4)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
