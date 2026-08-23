import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import 'tasks_list_page.dart' show taskStatusColor, taskPriorityColor, taskLbl;

const List<String> _taskStatuses = [
  'new', 'accepted', 'in_progress', 'needs_review', 'completed', 'overdue', 'cancelled',
];

class TaskDetailPage extends StatefulWidget {
  const TaskDetailPage({super.key, required this.taskId});
  final String taskId;

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  Map<String, dynamic>? _task;
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _posting = false;
  final _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ApiService.getTaskDetail(widget.taskId);
    if (!mounted) return;
    setState(() {
      _task = res['task'] as Map<String, dynamic>?;
      _comments = (res['comments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _loading = false;
    });
  }

  bool get _isParticipant {
    final t = _task;
    if (t == null) return false;
    final uid = currentUserId?.toString();
    return t['assigned_to_user_id'] == uid || t['created_by_user_id'] == uid;
  }

  Future<void> _updateStatus(String status) async {
    final res = await ApiService.updateTaskStatus(id: widget.taskId, status: status);
    if (!mounted) return;
    if (res['success'] == true) _load();
  }

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    final res = await ApiService.addTaskComment(id: widget.taskId, comment: text);
    if (!mounted) return;
    setState(() => _posting = false);
    if (res['success'] == true) {
      _commentCtrl.clear();
      _load();
    }
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
          title: Text(AppLocalizations.get('tasks_title'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _task == null
                ? Center(
                    child: Text(AppLocalizations.get('error_load_failed'),
                        style: const TextStyle(color: AppColors.muted)),
                  )
                : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final t = _task!;
    final status = (t['status'] ?? '').toString();
    final priority = (t['priority'] ?? '').toString();
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('${t['title']}',
                  style: const TextStyle(
                      color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 8),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: taskPriorityColor(priority).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(taskLbl('task_priority_$priority'),
                      style: TextStyle(color: taskPriorityColor(priority), fontSize: 11, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: taskStatusColor(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(taskLbl('task_status_$status'),
                      style: TextStyle(color: taskStatusColor(status), fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ]),
              if ((t['description'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                Text('${t['description']}',
                    style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
              ],
              const SizedBox(height: 14),
              _metaRow(Icons.person_outline_rounded, '${t['assigned_to_name'] ?? ''}'),
              _metaRow(Icons.badge_outlined, '${t['created_by_name'] ?? ''}'),
              if ((t['linked_player_name'] as String?)?.isNotEmpty == true)
                _metaRow(Icons.sports_rounded, '${t['linked_player_name']}'),
              if ((t['due_date'] as String?)?.isNotEmpty == true)
                _metaRow(Icons.event_rounded, '${t['due_date']}'),
              if (_isParticipant) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _taskStatuses.map((s) {
                    final active = s == status;
                    return GestureDetector(
                      onTap: active ? null : () => _updateStatus(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: active ? taskStatusColor(s) : AppColors.card,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: active ? taskStatusColor(s) : AppColors.border),
                        ),
                        child: Text(taskLbl('task_status_$s'),
                            style: TextStyle(
                                color: active ? AppColors.foreground : AppColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 20),
              Text(AppLocalizations.get('task_comments_title'),
                  style: const TextStyle(
                      color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 8),
              ..._comments.map((c) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c['author_name']}',
                            style: const TextStyle(
                                color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('${c['comment']}',
                            style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                      ],
                    ),
                  )),
            ],
          ),
        ),
        if (_isParticipant) _buildCommentInput(),
      ],
    );
  }

  Widget _metaRow(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
    );
  }

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentCtrl,
              style: const TextStyle(color: AppColors.foreground, fontSize: 14),
              decoration: InputDecoration(
                hintText: AppLocalizations.get('task_comment_hint'),
                hintStyle: const TextStyle(color: AppColors.muted),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _posting
              ? const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                )
              : IconButton(
                  onPressed: _sendComment,
                  icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                ),
        ],
      ),
    );
  }
}
