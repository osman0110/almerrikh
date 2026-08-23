import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';

Color _notificationColor(String type) {
  switch (type) {
    case 'injury_created': return AppColors.destructive;
    case 'readiness_alert': return AppColors.warning;
    case 'session_scheduled':
    case 'match_scheduled': return AppColors.primary;
    case 'physio_session_scheduled': return AppColors.risk;
    case 'task_comment': return AppColors.coachAccent;
    case 'coach_alert': return AppColors.coachAccent;
    default: return AppColors.primary; // task_assigned, etc.
  }
}

IconData _notificationIcon(String type) {
  switch (type) {
    case 'injury_created': return Icons.medical_information_rounded;
    case 'readiness_alert': return Icons.monitor_heart_rounded;
    case 'session_scheduled': return Icons.event_note_rounded;
    case 'match_scheduled': return Icons.sports_soccer_rounded;
    case 'physio_session_scheduled': return Icons.spa_rounded;
    case 'task_comment': return Icons.chat_bubble_outline_rounded;
    case 'coach_alert': return Icons.campaign_rounded;
    default: return Icons.checklist_rounded; // task_assigned, etc.
  }
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await ApiService.getNotifications();
    if (!mounted) return;
    setState(() {
      _notifications = list;
      _loading = false;
    });
  }

  Future<void> _markAllRead() async {
    await ApiService.markAllNotificationsRead();
    _load();
  }

  Future<void> _onTapNotification(Map<String, dynamic> n) async {
    if (n['is_read'] != true) {
      await ApiService.markNotificationRead(n['id'].toString());
    }
    if (!mounted) return;
    setState(() => n['is_read'] = true);

    final route = n['linked_route'] as String?;
    if (route == null || route.isEmpty) return;
    // '/club/players/{id}' already has a named-route handler in main.dart.
    // Task routes intentionally remain unlinked while the tasks page is
    // paused; the page and its direct route stay available in source only.
    if (route.startsWith('/club/players/')) {
      Navigator.of(context).pushNamed(route);
    } else if (route.startsWith('/session/') ||
        route.startsWith('/match/') ||
        route.startsWith('/physio-session/')) {
      Navigator.of(context).pushNamed(
          currentUserRole == UserRole.player ? '/player/sessions' : '/club/sessions');
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
          title: Text(AppLocalizations.get('notifications_title'),
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          actions: [
            TextButton(
              onPressed: _markAllRead,
              child: Text(AppLocalizations.get('mark_all_read'),
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _notifications.isEmpty
                ? Center(
                    child: Text(AppLocalizations.get('no_notifications'),
                        style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    backgroundColor: AppColors.card,
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      itemBuilder: (_, i) => _notificationCard(_notifications[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _notificationCard(Map<String, dynamic> n) {
    final type = (n['type'] ?? '').toString();
    final isRead = n['is_read'] == true;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _onTapNotification(n),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? AppColors.card : _notificationColor(type).withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isRead ? AppColors.border : _notificationColor(type).withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_notificationIcon(type), color: _notificationColor(type), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${n['title']}',
                      style: TextStyle(
                          color: AppColors.foreground,
                          fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                          fontSize: 13)),
                  if ((n['body'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    Text('${n['body']}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                  const SizedBox(height: 4),
                  Text('${n['created_at']}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                ],
              ),
            ),
            if (!isRead)
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: _notificationColor(type), shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}
