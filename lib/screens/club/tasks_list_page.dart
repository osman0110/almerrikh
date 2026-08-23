import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import 'club_dashboard.dart' show ClubShell;
import 'club_widgets.dart';
import 'task_detail_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tasks — cross-department task list. Every org role can view (tasks.view);
// creating/updating requires tasks.manage (all roles except analyst);
// assigning to someone else requires tasks.assign_others (owner/admin/coach/
// doctor/performance manager) — see api/includes/club_auth.php clubStaffCan().
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _taskPriorities = ['low', 'normal', 'high', 'urgent'];

String taskLbl(String key) {
  final v = AppLocalizations.get(key);
  return v != key ? v : key;
}

Color taskStatusColor(String s) {
  switch (s) {
    case 'new': return AppColors.risk;
    case 'accepted':
    case 'in_progress': return AppColors.coachAccent;
    case 'needs_review': return AppColors.warning;
    case 'completed': return AppColors.success;
    case 'overdue': return AppColors.destructive;
    default: return AppColors.muted;
  }
}

Color taskPriorityColor(String p) {
  switch (p) {
    case 'urgent': return AppColors.destructive;
    case 'high': return AppColors.warning;
    default: return AppColors.muted;
  }
}

class TasksListPage extends StatefulWidget {
  const TasksListPage({super.key});

  @override
  State<TasksListPage> createState() => _TasksListPageState();
}

class _TasksListPageState extends State<TasksListPage> {
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _directory = [];
  bool _loading = true;
  bool _loadError = false;
  String _filter = 'mine';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final results = await Future.wait([
        ApiService.getTasks(filter: _filter),
        ApiService.getTaskAssigneeDirectory(),
      ]);
      if (!mounted) return;
      setState(() {
        _tasks = results[0];
        _directory = results[1];
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _setFilter(String f) {
    setState(() => _filter = f);
    _load();
  }

  void _openCreateSheet() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final dueCtrl = TextEditingController();
    String priority = 'normal';
    String assigneeId = currentUserId?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 20, left: 20, right: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(taskLbl('task_new'),
                    style: const TextStyle(
                        color: AppColors.foreground,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 16),
                _field(titleCtrl, taskLbl('task_title_hint')),
                const SizedBox(height: 10),
                _field(descCtrl, taskLbl('task_description_hint'), maxLines: 3),
                const SizedBox(height: 10),
                if (canAssignTasksToOthers) ...[
                  _assigneeDropdown(
                    value: assigneeId,
                    onChanged: (v) => setSheetState(() => assigneeId = v),
                  ),
                  const SizedBox(height: 10),
                ],
                _priorityDropdown(
                  value: priority,
                  onChanged: (v) => setSheetState(() => priority = v),
                ),
                const SizedBox(height: 10),
                _field(dueCtrl, taskLbl('task_due_date_label')),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (titleCtrl.text.trim().isEmpty) return;
                      final res = await ApiService.createTask(
                        title: titleCtrl.text.trim(),
                        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                        assignedToUserId: int.tryParse(assigneeId),
                        priority: priority,
                        dueDate: dueCtrl.text.trim().isEmpty ? null : dueCtrl.text.trim(),
                      );
                      if (!mounted) return;
                      if (res['success'] == true) {
                        Navigator.of(context).pop();
                        _load();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.foreground,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: Text(taskLbl('task_new'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.foreground, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.muted),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _assigneeDropdown({required String value, required void Function(String) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _directory.any((s) => s['user_id'] == value) ? value : null,
          hint: Text(taskLbl('task_assignee_label'), style: const TextStyle(color: AppColors.muted)),
          isExpanded: true,
          dropdownColor: AppColors.card,
          style: const TextStyle(color: AppColors.foreground, fontSize: 14),
          items: _directory
              .map((s) => DropdownMenuItem(
                    value: s['user_id'] as String,
                    child: Text('${s['name']}'),
                  ))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  Widget _priorityDropdown({required String value, required void Function(String) onChanged}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.card,
          style: const TextStyle(color: AppColors.foreground, fontSize: 14),
          items: _taskPriorities
              .map((p) => DropdownMenuItem(value: p, child: Text(taskLbl('task_priority_$p'))))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClubShell(
      currentIndex: 5,
      child: Column(
        children: [
          ClubAppHeader(
            title: taskLbl('tasks_title'),
            trailing: canManageTasks
                ? GestureDetector(
                    onTap: _openCreateSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.add_rounded, color: AppColors.foreground, size: 18),
                        const SizedBox(width: 6),
                        Text(taskLbl('task_new'),
                            style: const TextStyle(
                                color: AppColors.foreground,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ]),
                    ),
                  )
                : null,
          ),
          _buildFilters(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _loadError
                    ? ClubErrorState(
                        title: AppLocalizations.get('error_load_failed'),
                        description: AppLocalizations.get('error_check_internet'),
                        retryLabel: AppLocalizations.get('retry_btn'),
                        onRetry: _load,
                      )
                    : _tasks.isEmpty
                        ? Center(
                            child: Text(taskLbl('no_tasks_found'),
                                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                          )
                        : RefreshIndicator(
                            color: AppColors.primary,
                            backgroundColor: AppColors.card,
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                              itemCount: _tasks.length,
                              itemBuilder: (_, i) => _taskCard(_tasks[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final filters = [
      ('mine', taskLbl('task_filter_mine')),
      ('created', taskLbl('task_filter_created')),
      ('all', taskLbl('task_filter_all')),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        children: filters.map((f) {
          final active = _filter == f.$1;
          return GestureDetector(
            onTap: () => _setFilter(f.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surface2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? AppColors.primary : AppColors.border),
              ),
              child: Text(f.$2,
                  style: TextStyle(
                      color: active ? AppColors.foreground : AppColors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _taskCard(Map<String, dynamic> t) {
    final status = (t['status'] ?? '').toString();
    final priority = (t['priority'] ?? '').toString();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TaskDetailPage(taskId: t['id'].toString()),
        ));
        _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
              children: [
                Expanded(
                  child: Text('${t['title']}',
                      style: const TextStyle(
                          color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: taskPriorityColor(priority).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(taskLbl('task_priority_$priority'),
                      style: TextStyle(color: taskPriorityColor(priority), fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if ((t['linked_player_name'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text('${t['linked_player_name']}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person_outline_rounded, size: 14, color: AppColors.muted),
                const SizedBox(width: 4),
                Text('${t['assigned_to_name'] ?? ''}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                const Spacer(),
                if ((t['due_date'] as String?)?.isNotEmpty == true) ...[
                  const Icon(Icons.event_rounded, size: 14, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text('${t['due_date']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  const SizedBox(width: 10),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: taskStatusColor(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(taskLbl('task_status_$status'),
                      style: TextStyle(color: taskStatusColor(status), fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
