import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/monitoring_models.dart';
import '../../services/player_monitoring_service.dart';

class BodyMetricsScreen extends StatefulWidget {
  const BodyMetricsScreen({super.key});

  @override
  State<BodyMetricsScreen> createState() => _BodyMetricsScreenState();
}

class _BodyMetricsScreenState extends State<BodyMetricsScreen> {
  late TextEditingController _weightCtrl, _heightCtrl, _fatCtrl;
  BodyMetric? latest;
  bool loading = true;
  double? _bmiDisplay;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController();
    _heightCtrl = TextEditingController();
    _fatCtrl = TextEditingController();
    _loadLatest();
  }

  void _loadLatest() async {
    try {
      final res = await PlayerMonitoringService.getLatestBodyMetrics();
      if (res['metric'] != null) {
        final m = BodyMetric.fromJson(res['metric']);
        setState(() {
          latest = m;
          _weightCtrl.text = m.weightKg.toString();
          _heightCtrl.text = m.heightCm.toString();
          _fatCtrl.text = m.bodyFatPercent.toString();
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

  Future<void> _submit() async {
    final w = double.tryParse(_weightCtrl.text);
    final h = double.tryParse(_heightCtrl.text);
    final f = double.tryParse(_fatCtrl.text);
    if (w == null || h == null || f == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await PlayerMonitoringService.saveBodyMetrics(
        weightKg: w,
        heightCm: h,
        bodyFatPercent: f,
      );
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
        _loadLatest();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error']?.toString() ?? 'Error')));
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error')));
    }
    setState(() => _submitting = false);
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Body Metrics'),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (latest != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Latest Record', style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _StatTile('Weight', '${latest!.weightKg} kg'),
                              _StatTile('Height', '${latest!.heightCm} cm'),
                              _StatTile('Body Fat', '${latest!.bodyFatPercent}%'),
                            ],
                          ),
                          if (latest!.bmi != null) ...[
                            const SizedBox(height: 12),
                            _StatTile('BMI', '${latest!.bmi!.toStringAsFixed(1)}'),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  _TextField(label: 'Weight (kg)', ctrl: _weightCtrl, onChanged: (_) => _updateBmi()),
                  const SizedBox(height: 12),
                  _TextField(label: 'Height (cm)', ctrl: _heightCtrl, onChanged: (_) => _updateBmi()),
                  const SizedBox(height: 12),
                  _TextField(label: 'Body Fat %', ctrl: _fatCtrl),
                  const SizedBox(height: 16),
                  if (_bmiDisplay != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('BMI', style: TextStyle(color: Colors.white70)),
                          Text(
                            _bmiDisplay!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                            )
                          : const Text('Save Metrics', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({required this.label, required this.ctrl, this.onChanged});
  final String label;
  final TextEditingController ctrl;
  final Function(String)? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
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
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.6))),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
      ],
    );
  }
}
