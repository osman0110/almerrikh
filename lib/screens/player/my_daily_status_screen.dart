import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';

String _lbl(String key) {
  final v = AppLocalizations.get(key);
  return v != key ? v : key;
}

Color _participationColor(String? status) {
  switch (status) {
    case 'fully_available': return AppColors.success;
    case 'modified_training': return AppColors.warning;
    case 'unavailable': return AppColors.destructive;
    default: return AppColors.muted;
  }
}

/// Read-only view of the player's own daily participation decision, the
/// output of the unified daily readiness workflow (roadmap item 6).
class MyDailyStatusScreen extends StatefulWidget {
  const MyDailyStatusScreen({super.key});

  @override
  State<MyDailyStatusScreen> createState() => _MyDailyStatusScreenState();
}

class _MyDailyStatusScreenState extends State<MyDailyStatusScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ApiService.getMyDailyStatus();
    if (!mounted) return;
    setState(() {
      _data = res['error'] == null ? res : null;
      _loading = false;
    });
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
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.foreground, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(_lbl('participation_decision'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primary,
                backgroundColor: AppColors.card,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: _buildContent(),
                ),
              ),
      ),
    );
  }

  List<Widget> _buildContent() {
    final d = _data;
    final decision = d?['decision'] as Map<String, dynamic>?;
    final participationStatus = decision?['participation_status'] as String?;
    final color = _participationColor(participationStatus);

    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_rounded, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    participationStatus != null
                        ? _lbl('participation_$participationStatus')
                        : _lbl('no_decision_yet'),
                    style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (decision?['allowed_duration_minutes'] != null) ...[
              const SizedBox(height: 10),
              Text('${_lbl('allowed_duration_minutes')}: ${decision!['allowed_duration_minutes']}',
                  style: const TextStyle(color: AppColors.foreground, fontSize: 12.5)),
            ],
            if ((decision?['restrictions'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('${_lbl('restrictions')}: ${decision!['restrictions']}',
                  style: const TextStyle(color: AppColors.foreground, fontSize: 12.5)),
            ],
          ],
        ),
      ),
      if (d?['physio_today'] != null) ...[
        const SizedBox(height: 12),
        _infoRow(Icons.spa_rounded, AppColors.risk, _lbl('physio_sessions_title'),
            _lbl('physio_status_${d!['physio_today']}')),
      ],
      if (d?['nutrition_status_today'] != null) ...[
        const SizedBox(height: 12),
        _infoRow(Icons.restaurant_menu_rounded, AppColors.warning, _lbl('nutrition_title'),
            _lbl('compliance_status_${d!['nutrition_status_today']}')),
      ],
    ];
  }

  Widget _infoRow(IconData icon, Color color, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
          Text(value, style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}
