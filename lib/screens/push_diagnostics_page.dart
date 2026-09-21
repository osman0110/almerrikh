import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_service.dart';
import '../app_colors.dart';
import '../services/notification_service.dart';
import '../storage.dart';

/// Account + push diagnostics: runs every step live on this device and on
/// the server, and can send a real test push showing FCM's raw answer.
/// Reached from club settings and the player profile ("تشخيص الإشعارات").
class PushDiagnosticsPage extends StatefulWidget {
  const PushDiagnosticsPage({super.key});

  @override
  State<PushDiagnosticsPage> createState() => _PushDiagnosticsPageState();
}

class _PushDiagnosticsPageState extends State<PushDiagnosticsPage> {
  final Map<String, dynamic> _report = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _runChecks();
  }

  Future<T?> _safe<T>(Future<T> Function() f, String key) async {
    try {
      return await f().timeout(const Duration(seconds: 15));
    } catch (e) {
      _report['${key}_error'] = e.toString();
      return null;
    }
  }

  Future<void> _runChecks() async {
    setState(() {
      _busy = true;
      _report.clear();
    });
    _report['platform'] = Platform.isIOS ? 'ios' : 'android';
    _report['os'] = Platform.operatingSystemVersion;
    _report['checked_at'] = DateTime.now().toIso8601String();

    // 1) Session: local token + server says it's valid.
    _report['local_session'] = await OnboardingStore().isSignedIn();
    final me = await _safe(ApiService.getMe, 'server_session');
    final user = me?['user'];
    _report['server_session'] = user is Map ? 'valid' : 'invalid ${me ?? ''}';
    if (user is Map) {
      _report['user_id'] = user['id'];
      _report['user_role'] = user['role'];
    }

    // 2) Firebase on this device.
    _report['firebase_init_error'] = NotificationService.firebaseInitError;
    final messaging = FirebaseMessaging.instance;
    final settings = await _safe(messaging.getNotificationSettings, 'permission');
    _report['permission'] = settings?.authorizationStatus.name;
    if (Platform.isIOS) {
      _report['native_apns'] = await NotificationService.nativeApnsStatus();
      final apns = await _safe(messaging.getAPNSToken, 'apns');
      _report['apns_token'] = apns == null ? null : '${apns.substring(0, 12)}…';
    }
    final fcm = await _safe(messaging.getToken, 'fcm');
    _report['fcm_token'] = fcm == null ? null : '${fcm.substring(0, 12)}…';

    // 3) Server: which devices are registered for this user.
    final status = await ApiService.pushDiagnostics('status');
    _report['server_fcm_credentials'] = status['fcm_credentials'];
    final devices = (status['devices'] as List?) ?? [];
    _report['server_devices'] = devices;
    if (status['success'] != true) _report['server_status_error'] = status;
    _report['this_device_registered'] = fcm != null &&
        devices.any((d) => d is Map && d['token_prefix'] == '${fcm.substring(0, 12)}…');

    _report['last_registration'] = NotificationService.lastPushDiag;
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reRegister() async {
    setState(() => _busy = true);
    await NotificationService.registerPush(force: true);
    await _runChecks();
  }

  Future<void> _sendTest() async {
    setState(() => _busy = true);
    _report['test_push'] = await ApiService.pushDiagnostics('test');
    if (mounted) setState(() => _busy = false);
  }

  void _copy() {
    Clipboard.setData(ClipboardData(
      text: const JsonEncoder.withIndent('  ').convert(_report),
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ التقرير')),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  Widget _row(String label, Object? value, {bool? ok}) {
    final color = ok == null ? AppColors.muted : (ok ? AppColors.success : AppColors.risk);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok == null ? Icons.info_outline : (ok ? Icons.check_circle : Icons.error),
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Flexible(
            child: SelectableText(
              value == null ? '-' : '$value',
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> rows) => Card(
        color: AppColors.card,
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Divider(),
              ...rows,
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final perm = r['permission'];
    final test = r['test_push'] as Map<String, dynamic>?;
    final testResults = (test?['results'] as List?) ?? [];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('تشخيص الحساب والإشعارات'),
        actions: [
          IconButton(icon: const Icon(Icons.copy), onPressed: _copy, tooltip: 'نسخ التقرير'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          _card('الجلسة', [
            _row('جلسة محفوظة في الجهاز', r['local_session'], ok: r['local_session'] == true),
            _row('الجلسة على السيرفر', r['server_session'], ok: r['server_session'] == 'valid'),
            _row('User ID', r['user_id']),
            _row('Role', r['user_role']),
          ]),
          _card('Firebase على الجهاز', [
            _row('تهيئة Firebase', r['firebase_init_error'] ?? 'OK',
                ok: r['firebase_init_error'] == null),
            _row('إذن الإشعارات', perm, ok: perm == 'authorized' || perm == 'provisional'),
            if (Platform.isIOS) ...[
              _row('تسجيل Apple (native)', (r['native_apns'] as Map?)?['state'],
                  ok: (r['native_apns'] as Map?)?['state'] == 'registered'),
              if ((r['native_apns'] as Map?)?['error'] != null)
                _row('خطأ Apple', (r['native_apns'] as Map)['error'], ok: false),
              _row('aps-environment في البروفايل',
                  (r['native_apns'] as Map?)?['profile_aps_environment'],
                  ok: (r['native_apns'] as Map?)?['profile_aps_environment'] == 'production'),
              _row('APNs token', r['apns_token'] ?? r['apns_error'], ok: r['apns_token'] != null),
            ],
            _row('FCM token', r['fcm_token'] ?? r['fcm_error'], ok: r['fcm_token'] != null),
          ]),
          _card('السيرفر', [
            _row('مفتاح FCM على السيرفر', r['server_fcm_credentials'],
                ok: r['server_fcm_credentials'] == true),
            _row('هذا الجهاز مسجّل', r['this_device_registered'],
                ok: r['this_device_registered'] == true),
            for (final d in (r['server_devices'] as List? ?? []))
              _row('${d['platform']}', '${d['token_prefix']}  ${d['updated_at']}'),
            if (r['server_status_error'] != null) _row('خطأ', r['server_status_error'], ok: false),
          ]),
          _card('آخر تسجيل', [
            for (final e in (r['last_registration'] as Map? ?? {}).entries)
              _row('${e.key}', e.value),
          ]),
          if (test != null)
            _card('نتيجة الإشعار التجريبي', [
              if (test['message'] != null || test['error'] != null)
                _row('خطأ', test['message'] ?? test['error'], ok: false),
              _row('Firebase project', test['project_id']),
              if (test['success'] == true && testResults.isEmpty)
                _row('الأجهزة', 'لا يوجد جهاز مسجّل', ok: false),
              for (final t in testResults) ...[
                _row('${t['platform']} ${t['token_prefix']}', t['outcome'], ok: t['outcome'] == 'sent'),
                if (t['outcome'] != 'sent') _row('رد FCM', t['fcm_response']),
              ],
            ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _sendTest,
            icon: const Icon(Icons.notifications_active),
            label: const Text('إرسال إشعار تجريبي'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _reRegister,
            icon: const Icon(Icons.sync),
            label: const Text('إعادة تسجيل الجهاز'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _runChecks,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة الفحص'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
