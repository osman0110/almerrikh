import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app_colors.dart';
import '../app_localizations.dart';
import '../app_state.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../storage.dart';
import '../utils/crash_reporter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Account deletion flow (App Store guideline 5.1.1(v)).
//
// Shared by the staff settings page and the player profile tab:
//   confirmation dialog (explains what is deleted, asks for the password)
//   → server-side permanent deletion
//   → success dialog
//   → back to the sign-in screen with all local session state cleared.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showDeleteAccountFlow(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);

  final password = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => const _DeleteAccountDialog(),
  );
  if (password == null || password.isEmpty) return;
  if (!context.mounted) return;

  // Progress dialog — the request can take a few seconds.
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Directionality(
        textDirection: _dir(),
        child: AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  AppLocalizations.get('delete_account_progress'),
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // Push token must be released while the bearer token is still valid.
  await NotificationService.unregisterPush();

  // Once the account is gone every in-flight dashboard refresh comes back
  // 401. The global handler would yank the navigator to onboarding and take
  // the success dialog with it, so it is suspended until this flow has
  // finished its own navigation.
  final globalUnauthorized = ApiService.onUnauthorized;
  ApiService.onUnauthorized = null;
  final result = await ApiService.deleteAccount(password: password);
  if (result['success'] != true) ApiService.onUnauthorized = globalUnauthorized;

  if (navigator.mounted) navigator.pop(); // close progress dialog

  if (result['success'] != true) {
    final raw = (result['error'] ?? '').toString();
    final message = raw.toLowerCase().contains('incorrect password')
        ? AppLocalizations.get('delete_account_wrong_password')
        : (raw.isNotEmpty
              ? raw
              : AppLocalizations.get('delete_account_failed'));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
    return;
  }

  // Server has destroyed the account — clear every trace locally.
  await FirebaseService().signOut();
  await OnboardingStore().clearSignedIn();
  CrashReporter.clearContext();
  currentUserName = 'Player';
  currentUserNameArabic = '';
  currentUserNameEnglish = '';
  currentUserAvatarUrl = '';

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => Directionality(
      textDirection: _dir(),
      child: AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppLocalizations.get('delete_account_success_title'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          AppLocalizations.get('delete_account_success_msg'),
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 13.5,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              AppLocalizations.get('ok'),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  if (navigator.mounted) {
    navigator.pushNamedAndRemoveUntil('/auth', (_) => false);
  }
  ApiService.onUnauthorized = globalUnauthorized;
}

TextDirection _dir() =>
    getAppLanguage() == 'ar' ? TextDirection.rtl : TextDirection.ltr;

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = _password.text.length >= 6;
    return Directionality(
      textDirection: _dir(),
      child: Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: AppColors.surface2),
        ),
        child: ConstrainedBox(
          // Keeps the dialog phone-sized on iPad instead of spanning the screen.
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: AppColors.danger,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppLocalizations.get('delete_account_title'),
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  AppLocalizations.get('delete_account_msg'),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.55,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.get(
                      'delete_account_password_hint',
                    ),
                    hintStyle: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: AppColors.surface2,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.muted,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.muted,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            AppLocalizations.get('cancel'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: canDelete
                            ? () => Navigator.of(context).pop(_password.text)
                            : null,
                        child: Opacity(
                          opacity: canDelete ? 1 : 0.45,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.danger,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              AppLocalizations.get('delete_account_btn'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
