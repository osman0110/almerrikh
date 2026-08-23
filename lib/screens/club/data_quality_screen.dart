import 'package:flutter/material.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../services/club_service.dart';

class DataQualityScreen extends StatefulWidget {
  const DataQualityScreen({super.key});

  @override
  State<DataQualityScreen> createState() => _DataQualityScreenState();
}

class _DataQualityScreenState extends State<DataQualityScreen> {
  Map<String, dynamic>? _report;
  bool _loading = true;
  bool _error = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = false;
    });
    final report = await ClubService().getDataQualityReport();
    if (!mounted || generation != _generation) return;
    setState(() {
      _report = report;
      _loading = false;
      _error = report == null;
    });
  }

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
      : [];

  int _number(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          AppLocalizations.get('data_quality_title'),
          style: const TextStyle(
            color: AppColors.foreground,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error
              ? Center(
                  child: FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(AppLocalizations.get('retry_btn')),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _buildReport(),
                ),
    );
  }

  Widget _buildReport() {
    final report = _report!;
    final schema = _map(report['schema']);
    final summary = _map(report['summary']);
    final duplicates = _map(report['duplicates']);
    final orphans = _map(report['orphans']);
    final conflicts = _rows(report['session_conflicts']);
    final audit = _rows(report['recent_audit']);

    final missingTables = (schema['missing_tables'] as List? ?? const [])
        .map((item) => item.toString())
        .toList();
    final missingColumns = _rows(schema['missing_columns']);
    final missingIndexes = _rows(schema['missing_indexes']);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        _summaryCard(summary, schema['is_ready'] == true),
        if (report['generated_at'] != null) ...[
          const SizedBox(height: 6),
          Text(
            '${AppLocalizations.get('data_quality_generated_at')}: '
            '${report['generated_at']}',
            style: const TextStyle(color: AppColors.muted, fontSize: 10),
          ),
        ],
        const SizedBox(height: 10),
        _section(
          title: AppLocalizations.get('data_quality_schema'),
          icon: Icons.storage_rounded,
          children: [
            _schemaGroup(
              AppLocalizations.get('data_quality_missing_tables'),
              missingTables,
            ),
            _schemaGroup(
              AppLocalizations.get('data_quality_missing_columns'),
              missingColumns
                  .map((item) => '${item['table']}.${item['column']}')
                  .toList(),
            ),
            _schemaGroup(
              AppLocalizations.get('data_quality_missing_indexes'),
              missingIndexes
                  .map((item) => '${item['table']}.${item['index']}')
                  .toList(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _section(
          title: AppLocalizations.get('data_quality_duplicates'),
          icon: Icons.copy_all_rounded,
          children: [
            _issueRows('RPE', _rows(duplicates['rpe'])),
            _issueRows('Hooper', _rows(duplicates['hooper'])),
            _issueRows(
              AppLocalizations.get('assessments_label'),
              _rows(duplicates['assessments']),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _section(
          title: AppLocalizations.get('data_quality_orphans'),
          icon: Icons.link_off_rounded,
          children: [
            _issueRows(
              AppLocalizations.get('assessments_label'),
              _rows(orphans['assessments']),
            ),
            _issueRows(
              AppLocalizations.get('session_attendance_label'),
              _rows(orphans['attendance']),
            ),
            _issueRows('RPE', _rows(orphans['rpe'])),
            _issueRows('Hooper', _rows(orphans['hooper'])),
          ],
        ),
        const SizedBox(height: 10),
        _section(
          title: AppLocalizations.get('data_quality_session_conflicts'),
          icon: Icons.rule_rounded,
          children: [
            if (conflicts.isEmpty) _empty()
            else
              for (final conflict in conflicts.take(50))
                _detailRow(
                  conflict['title']?.toString() ??
                      conflict['session_id']?.toString() ??
                      '—',
                  '${conflict['date'] ?? ''} · '
                      '${conflict['stored_assessment_count'] ?? 0}/'
                      '${conflict['actual_assessed_players'] ?? 0}',
                  Icons.event_note_rounded,
                ),
          ],
        ),
        const SizedBox(height: 10),
        _section(
          title: AppLocalizations.get('data_quality_audit'),
          icon: Icons.history_rounded,
          children: [
            if (audit.isEmpty) _empty()
            else
              for (final item in audit.take(50))
                _detailRow(
                  item['operation']?.toString() ??
                      item['field_name']?.toString() ??
                      '—',
                  '${item['changed_by_name'] ?? item['changed_by_user_id'] ?? '—'}'
                  ' · ${item['player_id'] ?? item['entity_id'] ?? '—'}'
                  ' · ${item['created_at'] ?? ''}',
                  Icons.manage_history_rounded,
                ),
          ],
        ),
      ],
    );
  }

  Widget _summaryCard(Map<String, dynamic> summary, bool schemaReady) {
    final issues = _number(summary['issue_groups']);
    final color = issues == 0 && schemaReady
        ? AppColors.success
        : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(
            issues == 0 && schemaReady
                ? Icons.verified_rounded
                : Icons.warning_amber_rounded,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              issues == 0 && schemaReady
                  ? AppLocalizations.get('data_quality_no_issues')
                  : '${AppLocalizations.get('data_quality_issue_groups')}: $issues',
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.coachAccent, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _schemaGroup(String title, List<String> items) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title (${items.length})',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            if (items.isEmpty)
              _empty()
            else
              for (final item in items.take(30))
                _detailRow(item, '', Icons.error_outline_rounded),
          ],
        ),
      );

  Widget _issueRows(String title, List<Map<String, dynamic>> items) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(
        '$title (${items.length})',
        style: const TextStyle(
          color: AppColors.foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
      children: items.isEmpty
          ? [_empty()]
          : [
              for (final item in items.take(50))
                _detailRow(
                  item['player_id']?.toString() ??
                      item['identity_key']?.toString() ??
                      item['id']?.toString() ??
                      '—',
                  _issueSubtitle(item),
                  Icons.report_problem_outlined,
                ),
            ],
    );
  }

  String _issueSubtitle(Map<String, dynamic> item) {
    final values = <String>[
      if (item['session_id'] != null) 'session: ${item['session_id']}',
      if (item['training_session_id'] != null)
        'session: ${item['training_session_id']}',
      if (item['entry_date'] != null) item['entry_date'].toString(),
      if (item['duplicate_count'] != null)
        '×${item['duplicate_count']}',
    ];
    return values.join(' · ');
  }

  Widget _detailRow(String title, String subtitle, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.muted, size: 15),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          AppLocalizations.get('data_quality_no_issues'),
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      );
}
