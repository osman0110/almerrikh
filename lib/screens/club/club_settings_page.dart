// ignore_for_file: unused_element, unused_element_parameter
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../services/firebase_service.dart';
import '../../services/club_service.dart';
import '../../services/notification_service.dart';
import '../../storage.dart';
import '../../utils/crash_reporter.dart';
import 'club_dashboard.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Club Settings Page — Arabic RTL, dark theme, lime accent
// ─────────────────────────────────────────────────────────────────────────────

class ClubSettingsPage extends StatefulWidget {
  const ClubSettingsPage({super.key});

  @override
  State<ClubSettingsPage> createState() => _ClubSettingsPageState();
}

class _ClubSettingsPageState extends State<ClubSettingsPage> {
  String _clubName = '';
  String _accountName = currentUserName;
  String _userEmail = '';
  String _userPhone = '';
  String _avatarUrl = currentUserAvatarUrl;
  bool _savingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final response = await ApiService.getMe();
    if (!mounted || response['success'] != true) return;
    final me = Map<String, dynamic>.from(
      response['user'] as Map? ?? response,
    );
    final club = me['club_name']?.toString() ?? '';
    final name = me['name']?.toString() ?? currentUserName;
    final email = me['email']?.toString() ?? '';
    final phone = me['phone']?.toString() ?? '';
    final avatarUrl = me['avatar_url']?.toString() ?? '';
    currentUserName = name;
    currentUserAvatarUrl = avatarUrl;
    await OnboardingStore().setUserAvatarUrl(avatarUrl);
    setState(() {
      _clubName = club;
      _accountName = name;
      _userEmail = email;
      _userPhone = phone;
      _avatarUrl = avatarUrl;
    });
  }

  Future<void> _changeAccountPhoto() async {
    if (_savingPhoto) return;
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1400,
    );
    if (image == null || !mounted) return;
    setState(() => _savingPhoto = true);
    try {
      final uploaded = await ClubService().uploadPlayerPhotoBytes(
        await image.readAsBytes(),
        filename: image.name,
      );
      if (uploaded == null) {
        throw StateError('upload_failed');
      }
      final result = await ApiService.updateAccountProfile(
        name: _accountName.isNotEmpty ? _accountName : currentUserName,
        phone: _userPhone,
        avatarUrl: uploaded,
      );
      if (result['success'] != true) {
        throw StateError(result['error']?.toString() ?? 'save_failed');
      }
      currentUserAvatarUrl = uploaded;
      await OnboardingStore().setUserAvatarUrl(uploaded);
      if (mounted) {
        setState(() => _avatarUrl = uploaded);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.get('account_photo_updated')),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.get('account_photo_failed')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  void _showPasswordSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const _ChangePasswordSheet(),
    );
  }

  String _currentLangLabel() {
    switch (getAppLanguage()) {
      case 'ar': return 'العربية';
      case 'fr': return 'Français';
      default:   return 'English';
    }
  }

  void _showLogout() {
    showDialog(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: AppLocalizations.get('logout_title'),
        message: AppLocalizations.get('logout_msg'),
        confirmLabel: AppLocalizations.get('logout_btn'),
        isDanger: true,
        onConfirm: () async {
          Navigator.pop(ctx);
          await NotificationService.unregisterPush();
          await ApiService.logout();
          await FirebaseService().signOut();
          await OnboardingStore().clearSignedIn();
          CrashReporter.clearContext();
          currentUserName = 'Player';
          currentUserNameArabic = '';
          currentUserNameEnglish = '';
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
        },
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: getAppLanguage() == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(AppLocalizations.get('club_brand_name'),
              style: TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.get('app_subtitle'),
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              const Text('v1.0.0',
                  style: TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${AppLocalizations.get('club_brand_name')} — 2025/26',
                  style: TextStyle(color: AppColors.muted)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.get('ok'),
                  style: const TextStyle(
                      color: AppColors.foreground, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLangSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _LangSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _userEmail.isNotEmpty ? _userEmail : null;

    return ClubShell(
      currentIndex: 6,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // ── Premium Header ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.maroonDark, AppColors.maroon],
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.gold.withOpacity(0.35)),
                  ),
                  child: const Icon(Icons.manage_accounts_rounded, color: AppColors.gold, size: 22),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.get('settings'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800, fontSize: 20)),
                    const SizedBox(height: 2),
                    Text(AppLocalizations.get('settings_subtitle'),
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 11.5)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Profile Card ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ProfileCard(
              name: _accountName.isNotEmpty ? _accountName : currentUserName,
              email: email,
              phone: _userPhone,
              clubName: _clubName,
              orgRole: currentOrgRole,
              avatarUrl: _avatarUrl,
              savingPhoto: _savingPhoto,
              onPhotoTap: _changeAccountPhoto,
            ),
          ),
          const SizedBox(height: 4),

          // ── Quick Access ─────────────────────────────────────────────────────
          _SecHeader(
            AppLocalizations.get(
              isOrgAdmin ? 'admin_club_management' : 'quick_access',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _QuickAccessGrid(
              items: isOrgAdmin
                  ? [
                      _QuickItem(
                        Icons.account_tree_rounded,
                        AppLocalizations.get('team_management'),
                        AppColors.primary,
                        '/club/teams',
                      ),
                      _QuickItem(
                        Icons.groups_rounded,
                        AppLocalizations.get('manage_staff'),
                        AppColors.maroon,
                        '/club/staff',
                      ),
                      _QuickItem(
                        Icons.emoji_events_rounded,
                        AppLocalizations.get('competition_management_title'),
                        AppColors.warning,
                        '/club/classification',
                      ),
                    ]
                  : [
                      if (canViewClubPlayers) _QuickItem(
                        Icons.group_rounded,
                        AppLocalizations.get('players_title'),
                        AppColors.maroon,
                        '/club/players',
                      ),
                      if (canViewClubSessions) _QuickItem(
                        Icons.sports_rounded,
                        AppLocalizations.get('sessions_title'),
                        AppColors.coachAccent,
                        '/club/sessions',
                      ),
                      if (canViewClubReports) _QuickItem(
                        Icons.bar_chart_rounded,
                        AppLocalizations.get('nav_reports_tab'),
                        AppColors.risk,
                        '/club/reports',
                      ),
                    ],
            ),
          ),

          // ── Account ──────────────────────────────────────────────────────────
          _SecHeader(AppLocalizations.get('account')),
          _Group(children: [
            _Row(
              icon: Icons.lock_reset_rounded,
              title: AppLocalizations.get('change_password'),
              subtitle: AppLocalizations.get('account_details'),
              accent: AppColors.maroon,
              onTap: _showPasswordSheet,
            ),
            _DangerRow(
              icon: Icons.logout_rounded,
              title: AppLocalizations.get('sign_out'),
              subtitle: AppLocalizations.get('logout_msg'),
              onTap: _showLogout,
            ),
          ]),

          // ── Language ─────────────────────────────────────────────────────────
          _SecHeader(AppLocalizations.get('language_appearance')),
          _Group(children: [
            _Row(
              icon: Icons.language_rounded,
              title: AppLocalizations.get('language_label'),
              subtitle: AppLocalizations.get('language_interface'),
              accent: AppColors.primary,
              trailing: _Chip(_currentLangLabel()),
              onTap: _showLangSheet,
            ),
          ]),

          // ── About ────────────────────────────────────────────────────────────
          _SecHeader(AppLocalizations.get('app_section')),
          _Group(children: [
            _Row(
              icon: Icons.info_rounded,
              title: AppLocalizations.get('about_app'),
              subtitle: AppLocalizations.get('app_subtitle'),
              accent: AppColors.primary,
              trailing: const _Chip('v1.0.0'),
              onTap: _showAboutDialog,
            ),
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Card
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    this.email,
    required this.phone,
    required this.clubName,
    required this.orgRole,
    required this.avatarUrl,
    required this.savingPhoto,
    required this.onPhotoTap,
  });

  final String name;
  final String? email;
  final String phone;
  final String clubName;
  final OrgRole orgRole;
  final String avatarUrl;
  final bool savingPhoto;
  final VoidCallback onPhotoTap;

  String get _roleLabel {
    switch (orgRole) {
      case OrgRole.owner:
        return AppLocalizations.get('role_owner');
      case OrgRole.admin:
        return AppLocalizations.get('role_admin');
      case OrgRole.performanceManager:
        return AppLocalizations.get('role_performance_manager');
      case OrgRole.coach:
        return AppLocalizations.get('role_coach');
      case OrgRole.doctor:
        return AppLocalizations.get('role_doctor');
      case OrgRole.analyst:
        return AppLocalizations.get('role_analyst');
      case OrgRole.physiotherapist:
        return AppLocalizations.get('role_physiotherapist');
      case OrgRole.nutritionist:
        return AppLocalizations.get('role_nutritionist');
      case OrgRole.tacticalCoach:
        return AppLocalizations.get('role_tactical_coach');
      case OrgRole.staff:
        return AppLocalizations.get('role_staff');
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isNotEmpty
        ? name.trim().split(RegExp(r'\s+')).map((w) => w[0]).take(2).join()
        : '؟';
    final displayClub = clubName.isNotEmpty ? clubName : '—';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.maroonDark, AppColors.maroon],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: AppColors.maroon.withOpacity(0.22),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          GestureDetector(
            onTap: savingPhoto ? null : onPhotoTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.gold.withOpacity(0.55),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: savingPhoto
                      ? const CircularProgressIndicator(
                          color: AppColors.gold,
                          strokeWidth: 2,
                        )
                      : avatarUrl.isNotEmpty
                          ? Image.network(
                              avatarUrl,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _ProfileInitials(
                                initials: initials,
                              ),
                            )
                          : _ProfileInitials(initials: initials),
                ),
                Positioned(
                  left: -5,
                  bottom: -5,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.maroonDark, width: 2),
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      color: AppColors.maroonDark,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.gold.withOpacity(0.40)),
                      ),
                      child: Text(
                        _roleLabel,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayClub,
                        style: TextStyle(color: Colors.white.withOpacity(0.65),
                            fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  email ?? AppLocalizations.get('no_email_added'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.58),
                    fontSize: 11,
                    fontStyle: email == null ? FontStyle.italic : FontStyle.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    phone,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.58),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInitials extends StatelessWidget {
  const _ProfileInitials({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 22,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder (kept for Dart compilation)
// ─────────────────────────────────────────────────────────────────────────────

class _TrialBanner extends StatelessWidget {
  const _TrialBanner({required this.daysLeft});
  final int daysLeft;

  @override
  Widget build(BuildContext context) {
    final expired = daysLeft <= 0;
    final color = expired ? AppColors.destructive : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Icon(
            expired
                ? Icons.timer_off_rounded
                : Icons.timer_rounded,
            color: color,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              expired
                  ? AppLocalizations.get('trial_expired')
                  : AppLocalizations.format('trial_days_left', {'days': daysLeft}),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SecHeader extends StatelessWidget {
  const _SecHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(
        children: [
          Container(
            width: 3, height: 14,
            decoration: BoxDecoration(
              color: AppColors.maroon,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textSoft,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group Card
// ─────────────────────────────────────────────────────────────────────────────

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: children),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings Row
// ─────────────────────────────────────────────────────────────────────────────

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.trailing,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Widget? trailing;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final active = onTap != null && badge == null;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            _IconBox(icon: icon, color: accent, dimmed: !active && badge == null),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: badge != null ? AppColors.muted : AppColors.foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (badge != null)
              _BadgeChip(badge!)
            else if (trailing != null)
              trailing!
            else if (active)
              Icon(
                getAppLanguage() == 'ar'
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: AppColors.muted,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Switch Row
// ─────────────────────────────────────────────────────────────────────────────

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.value,
    required this.onChanged,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final disabled = onChanged == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          _IconBox(icon: icon, color: accent, dimmed: disabled),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: disabled ? AppColors.muted : AppColors.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (badge != null)
            _BadgeChip(badge!)
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.foreground,
              activeTrackColor: accent,
              inactiveThumbColor: AppColors.muted,
              inactiveTrackColor: AppColors.border,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Danger Row
// ─────────────────────────────────────────────────────────────────────────────

class _DangerRow extends StatelessWidget {
  const _DangerRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.destructive.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: AppColors.destructive, size: 18),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.destructive,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.destructive.withOpacity(0.52),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              getAppLanguage() == 'ar'
                  ? Icons.chevron_left_rounded
                  : Icons.chevron_right_rounded,
              color: AppColors.destructive.withOpacity(0.35),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscription Card
// ─────────────────────────────────────────────────────────────────────────────

class _SubCard extends StatelessWidget {
  const _SubCard({
    required this.plan,
    required this.daysLeft,
    required this.onUpgrade,
    required this.onBilling,
  });

  final String plan;
  final int daysLeft;
  final VoidCallback onUpgrade;
  final VoidCallback onBilling;

  @override
  Widget build(BuildContext context) {
    final isTrial = plan == 'trial';
    final expired = isTrial && daysLeft <= 0;
    final warn = isTrial && daysLeft > 0 && daysLeft <= 5;
    final statusColor = expired
        ? AppColors.destructive
        : warn
            ? AppColors.warning
            : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isTrial ? AppLocalizations.get('trial_plan') : 'Club Pro',
                          style: const TextStyle(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            expired
                                ? AppLocalizations.get('subscription_expired_label')
                                : isTrial
                                    ? AppLocalizations.get('subscription_trial_label')
                                    : AppLocalizations.get('active_label'),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isTrial
                          ? (expired
                              ? AppLocalizations.get('trial_expired_label')
                              : AppLocalizations.format('trial_days_left', {'days': daysLeft}))
                          : AppLocalizations.get('active_subscription'),
                      style: TextStyle(
                        color: statusColor.withOpacity(0.78),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onUpgrade,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.coachAccent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AppLocalizations.get('upgrade_plan'),
                    style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onBilling,
            child: Text(
              AppLocalizations.get('billing_link'),
              style: TextStyle(
                color: AppColors.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.foreground.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared micro-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _IconBox extends StatelessWidget {
  const _IconBox(
      {required this.icon, required this.color, this.dimmed = false});
  final IconData icon;
  final Color color;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(dimmed ? 0.07 : 0.13),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon,
          color: dimmed
              ? AppColors.muted
              : AppColors.textSoft,
          size: 18),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsetsDirectional.only(start: 65),
      color: AppColors.border,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.maroon.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.maroon.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.maroon,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.muted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final c = connected ? AppColors.success : AppColors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          connected ? AppLocalizations.get('connected_label') : AppLocalizations.get('disconnected_label'),
          style: TextStyle(
            color: c,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 5),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Confirm Dialog (logout / delete)
// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.isDanger,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool isDanger;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: getAppLanguage() == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Dialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: AppColors.surface2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          AppLocalizations.get('cancel'),
                          style: const TextStyle(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: onConfirm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isDanger
                              ? AppColors.destructive.withOpacity(0.12)
                              : AppColors.maroon,
                          borderRadius: BorderRadius.circular(12),
                          border: isDanger
                              ? Border.all(color: AppColors.destructive.withOpacity(0.30))
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          confirmLabel,
                          style: TextStyle(
                            color: isDanger ? AppColors.destructive : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Change Password Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_next.text.length < 6) {
      _snack(AppLocalizations.get('password_too_short'));
      return;
    }
    if (_next.text != _confirm.text) {
      _snack(AppLocalizations.get('password_mismatch'));
      return;
    }
    setState(() => _saving = true);
    final result = await ApiService.changePassword(
      currentPassword: _current.text,
      newPassword: _next.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result['success'] == true) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.get('password_changed_success'),
          ),
        ),
      );
      return;
    }
    final error = result['error']?.toString() ?? '';
    _snack(
      error == 'Current password is incorrect'
          ? AppLocalizations.get('current_password_incorrect')
          : error,
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        18,
        18,
        MediaQuery.of(context).viewInsets.bottom + 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.get('change_password'),
            style: const TextStyle(
              color: AppColors.foreground,
              fontWeight: FontWeight.w900,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 16),
          _passwordField(
            controller: _current,
            label: AppLocalizations.get('current_password'),
          ),
          const SizedBox(height: 10),
          _passwordField(
            controller: _next,
            label: AppLocalizations.get('new_password'),
          ),
          const SizedBox(height: 10),
          _passwordField(
            controller: _confirm,
            label: AppLocalizations.get('confirm_password'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.lock_reset_rounded),
              label: Text(AppLocalizations.get('save_changes')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Language Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _LangSheet extends StatelessWidget {
  const _LangSheet();

  static const _langs = [
    ('العربية', 'ar'),
    ('English', 'en'),
    ('Français', 'fr'),
  ];

  Future<void> _pick(BuildContext ctx, String code) async {
    setAppLanguage(code);
    await OnboardingStore().setLanguage(code);
    unawaited(ApiService.updateAccountLanguage(code));
    if (ctx.mounted) {
      Navigator.of(ctx).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              AppLocalizations.get('choose_language_title'),
              style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 16),
            for (final lang in _langs)
              GestureDetector(
                onTap: () => _pick(context, lang.$2),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: getAppLanguage() == lang.$2
                        ? AppColors.maroon.withOpacity(0.06)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: getAppLanguage() == lang.$2
                            ? AppColors.maroon.withOpacity(0.35)
                            : AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Text(
                        lang.$1,
                        style: TextStyle(
                          color: getAppLanguage() == lang.$2
                              ? AppColors.maroon
                              : AppColors.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      if (getAppLanguage() == lang.$2)
                        const Icon(Icons.check_rounded,
                            color: AppColors.maroon, size: 18),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Access Grid
// ─────────────────────────────────────────────────────────────────────────────

class _QuickItem {
  const _QuickItem(this.icon, this.label, this.color, this.route);
  final IconData icon;
  final String label;
  final Color color;
  final String route;
}

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid({required this.items});
  final List<_QuickItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.1,
      children: items.map((item) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pushNamed(item.route),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: item.color, size: 19),
                ),
                const SizedBox(height: 7),
                Text(
                  item.label,
                  style: const TextStyle(
                    color: AppColors.textSoft,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder Screen for unimplemented sub-settings
// ─────────────────────────────────────────────────────────────────────────────

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: GoogleFonts.cairoTextTheme(
              Theme.of(context).textTheme),
        ),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: AppColors.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: AppColors.foreground,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: AppColors.coachAccent
                                  .withOpacity(0.10),
                              borderRadius:
                                  BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.construction_rounded,
                              color: AppColors.foreground,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.foreground,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            description,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 14,
                              height: 1.55,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.coachAccent
                                  .withOpacity(0.10),
                              borderRadius:
                                  BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.coachAccent
                                    .withOpacity(0.22),
                              ),
                            ),
                            child: const Text(
                              'هذه الإعدادات ستتوفر قريباً',
                              style: TextStyle(
                                color: AppColors.foreground,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
