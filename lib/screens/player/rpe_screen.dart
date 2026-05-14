import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../services/player_monitoring_service.dart';

class RpeScreen extends StatefulWidget {
  const RpeScreen({super.key});

  @override
  State<RpeScreen> createState() => _RpeScreenState();
}

class _RpeScreenState extends State<RpeScreen> {
  int rpe = 5;
  late TextEditingController durationCtrl;
  String? sessionType;
  String? notes;
  bool _submitting = false;

  int get trainingLoad => rpe * (int.tryParse(durationCtrl.text) ?? 0);

  @override
  void initState() {
    super.initState();
    durationCtrl = TextEditingController();
  }

  @override
  void dispose() {
    durationCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final duration = int.tryParse(durationCtrl.text);
    if (duration == null || duration < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter duration')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await PlayerMonitoringService.saveRpe(
        rpeScore: rpe,
        durationMinutes: duration,
        sessionType: sessionType,
        notes: notes,
      );
      if (res['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session rated')));
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
        title: const Text('Post-Training RPE'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // RPE Slider with Emoji
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    'Rate Perceived Exertion',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    rpe.toString(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _rpeLabel(rpe),
                    style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // RPE Slider
            Slider(
              value: rpe.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (v) => setState(() => rpe = v.toInt()),
              activeColor: AppColors.primary,
              inactiveColor: Colors.white.withOpacity(0.1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('Easy', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  Text('Moderate', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  Text('Max', style: TextStyle(fontSize: 11, color: Colors.white54)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Duration
            TextField(
              controller: durationCtrl,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Duration (minutes)',
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

            // Training Load Display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Training Load',
                    style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                  ),
                  Text(
                    trainingLoad.toString(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Session Type
            DropdownButtonFormField<String>(
              value: sessionType,
              decoration: InputDecoration(
                labelText: 'Session Type (optional)',
                labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              dropdownColor: AppColors.card,
              items: const [
                DropdownMenuItem(value: null, child: Text('None')),
                DropdownMenuItem(value: 'Football', child: Text('Football')),
                DropdownMenuItem(value: 'Gym', child: Text('Gym')),
                DropdownMenuItem(value: 'Recovery', child: Text('Recovery')),
                DropdownMenuItem(value: 'Match', child: Text('Match')),
                DropdownMenuItem(value: 'Sprint', child: Text('Sprint')),
                DropdownMenuItem(value: 'Tactical', child: Text('Tactical')),
              ],
              onChanged: (v) => setState(() => sessionType = v),
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
                    : const Text('Log Session', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _rpeLabel(int v) {
    if (v <= 2) return '😌 Easy';
    if (v <= 4) return '🙂 Light';
    if (v <= 6) return '😐 Moderate';
    if (v <= 8) return '😤 Hard';
    return '🔥 Maximum';
  }
}
