import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';

String _lbl(String key) {
  final v = AppLocalizations.get(key);
  return v != key ? v : key;
}

Color _statusColor(String s) {
  switch (s) {
    case 'scheduled': return AppColors.risk;
    case 'completed': return AppColors.success;
    case 'cancelled':
    case 'no_show': return AppColors.destructive;
    default: return AppColors.muted;
  }
}

/// Read-only view of the player's own physiotherapy/massage sessions.
class MyPhysioSessionsScreen extends StatefulWidget {
  const MyPhysioSessionsScreen({super.key});

  @override
  State<MyPhysioSessionsScreen> createState() => _MyPhysioSessionsScreenState();
}

class _MyPhysioSessionsScreenState extends State<MyPhysioSessionsScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _sessions = await ApiService.getMyPhysioSessions();
    if (mounted) setState(() => _loading = false);
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
        title: Text(_lbl('physio_sessions_title'),
            style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              backgroundColor: AppColors.card,
              child: _sessions.isEmpty
                  ? ListView(children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 120),
                          child: Column(
                            children: [
                              Icon(Icons.spa_outlined, color: AppColors.muted, size: 48),
                              const SizedBox(height: 12),
                              Text(_lbl('no_physio_sessions'), style: TextStyle(color: AppColors.muted, fontSize: 14)),
                            ],
                          ),
                        ),
                      ),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final s = _sessions[i];
                        final status = (s['status'] ?? '').toString();
                        final reason = (s['session_reason'] ?? '').toString();
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _statusColor(status).withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (s['treatment_type'] as String?)?.isNotEmpty == true
                                          ? s['treatment_type']
                                          : _lbl('session_reason_$reason'),
                                      style: const TextStyle(
                                          color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status).withOpacity(0.10),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(_lbl('physio_status_$status'),
                                        style: TextStyle(
                                            color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${s['scheduled_at'] ?? ''} · ${(s['body_area'] as String?) ?? ''}',
                                style: TextStyle(color: AppColors.muted, fontSize: 11),
                              ),
                              if (s['recommendation'] != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_lbl('recommendation')}: ${_lbl('recommendation_${s['recommendation']}')}',
                                    style: const TextStyle(color: AppColors.foreground, fontSize: 11.5, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
      ),
    );
  }
}
