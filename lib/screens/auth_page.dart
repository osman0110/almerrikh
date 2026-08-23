import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../app_colors.dart';
import '../app_constants.dart';
import '../app_localizations.dart';
import '../app_state.dart';
import '../models/auth_user_model.dart';
import '../storage.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with SingleTickerProviderStateMixin {
  static const bool _offlineAuthEnabled = false;

  // Only used in register mode — never sent or read during login
  bool isSignUp = false;
  bool showPassword = false;
  bool busy = false;

  final nameController        = TextEditingController();
  final emailController       = TextEditingController();
  final phoneController       = TextEditingController();
  final passwordController    = TextEditingController();
  final inviteCodeController  = TextEditingController();

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    inviteCodeController.dispose();
    super.dispose();
  }

  // Route from server role string — login always uses this
  String _routeFromServerRole(String serverRole) {
    switch (serverRole) {
      case 'player': return '/player';
      default:       return '/club'; // club, coach, unknown
    }
  }

  // Route for player role (hardcoded for this version)
  String _roleRoute() {
    return '/player';
  }

  Future<void> submit() async {
    final email        = emailController.text.trim();
    final phone        = phoneController.text.trim();
    final password     = passwordController.text;
    final name         = nameController.text.trim();
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+');
    final phoneDigits  = phone.replaceAll(RegExp(r'\D'), '');
    final loginDigits  = email.replaceAll(RegExp(r'\D'), '');
    final loginLooksLikePhone = loginDigits.length >= 8 && !email.contains('@');

    if (_offlineAuthEnabled) {
      setState(() => busy = true);
      final offlineName = name.isNotEmpty
          ? name
          : email.isNotEmpty ? email.split('@').first : 'User';
      await _continueOffline(offlineName);
      return;
    }

    // ── Validation ────────────────────────────────────────────────────────────
    if (isSignUp && !emailPattern.hasMatch(email)) {
      _showSnack(AppLocalizations.get('error_invalid_email'));
      return;
    }
    if (!isSignUp && !emailPattern.hasMatch(email) && !loginLooksLikePhone) {
      _showSnack(AppLocalizations.get('error_invalid_email_or_phone'));
      return;
    }
    if (password.length < 6) {
      _showSnack(AppLocalizations.get('error_password_short'));
      return;
    }

    // Register-only validations
    if (isSignUp) {
      if (name.isEmpty) {
        _showSnack(AppLocalizations.get('error_name_required'));
        return;
      }
      if (phoneDigits.length < 7 || phoneDigits.length > 15) {
        _showSnack(AppLocalizations.get('phone_invalid_length'));
        return;
      }
      if (inviteCodeController.text.trim().length < 6) {
        _showSnack(AppLocalizations.get('error_invite_code_required'));
        return;
      }
    }

    setState(() => busy = true);

    // ── Build register payload (login sends email+password only) ──────────────
    final playerTypeStr = isSignUp ? 'club' : null;
    final inviteCode = isSignUp ? inviteCodeController.text.trim() : null;

    try {
      final result = isSignUp
          ? await ApiService.register(
              name:        name,
              email:       email,
              phone:       phone,
              password:    password,
              role:        'player',
              playerType:  playerTypeStr,
              inviteCode:  inviteCode,
            )
          : await ApiService.login(email: email, password: password);
      // ↑ login sends ONLY email + password — no role field

      if (result.containsKey('error')) {
        // Never silently fabricate a fake local session on a real signup
        // failure (bad invite code, duplicate email/phone, etc.) — that
        // used to drop the user into a fake "offline demo" player account
        // instead of letting them see and fix the actual error, which is
        // how staff invited as doctor/massage/nutrition/etc. ended up
        // looking like plain player accounts.
        _showSnack(result['error'] as String);
        setState(() => busy = false);
        return;
      }

      final token   = result['token'] as String;
      final userMap = result['user']  as Map<String, dynamic>;
      final auth    = AuthUser.fromMap(userMap);

      currentUserName = auth.name;
      currentUserNameArabic = '';
      currentUserNameEnglish = '';
      currentUserAvatarUrl = auth.avatarUrl ?? '';
      await OnboardingStore().setSignedIn(token: token, userName: auth.name);
      await OnboardingStore().setUserAvatarUrl(auth.avatarUrl);
      await OnboardingStore().setUserId(auth.id);
      unawaited(ApiService.updateAccountLanguage(getAppLanguage()));

      // Always store and route based on server-returned role
      final serverRoleEnum = UserRole.values.firstWhere(
        (r) => r.name == auth.role,
        orElse: () => UserRole.club,
      );
      currentUserRole = serverRoleEnum;
      await OnboardingStore().setUserRole(currentUserRole);

      // Store org role (owner/admin/coach/staff) — defaults to staff (least privilege) if API doesn't return it
      final orgRole = orgRoleFromString(auth.orgRole);
      currentOrgRole = orgRole;
      await OnboardingStore().setOrgRole(orgRole);

      if (auth.playerType != null) {
        final pt = auth.playerType == 'independent'
            ? PlayerType.independent
            : PlayerType.club;
        currentPlayerType = pt;
        await OnboardingStore().setPlayerType(pt);
      }
      if (auth.linkedPlayerId != null && auth.linkedPlayerId!.isNotEmpty) {
        await OnboardingStore().setLinkedPlayerId(auth.linkedPlayerId);
      }
      if (auth.clubUserId != null) {
        await OnboardingStore().setClubUserId(auth.clubUserId!);
      }
      if (auth.trialEndsAt != null) {
        await OnboardingStore().setTrialEndsAt(auth.trialEndsAt);
      }

      if (!mounted) return;
      setState(() => busy = false);
      Navigator.of(context).pushNamedAndRemoveUntil(
        _routeFromServerRole(auth.role), (_) => false,
      );
    } catch (e) {
      _showSnack(AppLocalizations.get('error_connection'));
      setState(() => busy = false);
    }
  }

  Future<void> _continueOffline(String name) async {
    currentUserName = name.isNotEmpty ? name : 'User';
    currentUserNameArabic = '';
    currentUserNameEnglish = '';
    await OnboardingStore().setSignedIn(
      token: 'offline-demo-${DateTime.now().millisecondsSinceEpoch}',
      userName: currentUserName,
    );
    const offlineRole = UserRole.player;
    currentUserRole = offlineRole;
    await OnboardingStore().setUserRole(offlineRole);
    if (!mounted) return;
    setState(() => busy = false);
    Navigator.of(context).pushNamedAndRemoveUntil(_roleRoute(), (_) => false);
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildAnimatedSlideIn({required Widget child, required int index}) {
    final start     = 0.2 + (index * 0.08);
    final end       = (start + 0.35).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _animController,
      curve: Interval(start.clamp(0.0, 1.0), end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 30 * (1 - animation.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr    = getAppLanguage() == 'ar';
    final title   = isSignUp
        ? AppLocalizations.get('auth_title_signup')
        : AppLocalizations.get('auth_title_login');
    final subtitle = isSignUp
        ? AppLocalizations.get('auth_subtitle_signup')
        : AppLocalizations.get('auth_subtitle_login');

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Theme(
        data: Theme.of(context),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              // ── Login background with fallback ───────────────────────
              Container(color: AppColors.background),
              Positioned.fill(
                child: Image.asset(
                  'assets/images/login-bg.webp',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF3D2C27),
                            AppColors.background,
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // ── Overlay gradient for content readability ──────────────
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.background.withOpacity(0.65),
                        AppColors.background.withOpacity(0.8),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              // ── Logo ─────────────────────────────────────
                              TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 900),
                                curve: Curves.easeOutBack,
                                builder: (context, value, child) => Transform.scale(
                                  scale: value,
                                  child: Opacity(
                                    opacity: value.clamp(0.0, 1.0),
                                    child: child,
                                  ),
                                ),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 105,
                                  height: 105,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                              const SizedBox(height: 20),
                              // ── Title / Subtitle ─────────────────────────
                              _buildAnimatedSlideIn(
                                index: 0,
                                child: Column(
                                  children: [
                                    Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.maroon,
                                        fontSize: 27,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      subtitle,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              // ── Login / Register toggle ───────────────────
                              _buildAnimatedSlideIn(
                                index: 1,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: AppColors.card,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: AppColors.border,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _AuthModeButton(
                                          text: AppLocalizations.get('auth_sign_in'),
                                          active: !isSignUp,
                                          onTap: () => setState(() => isSignUp = false),
                                        ),
                                      ),
                                      Expanded(
                                        child: _AuthModeButton(
                                          text: AppLocalizations.get('auth_sign_up'),
                                          active: isSignUp,
                                          onTap: () => setState(() => isSignUp = true),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),

                              // ── REGISTER-ONLY section ─────────────────────
                              if (isSignUp) ...[
                                // Name + Phone + invite code
                                _buildAnimatedSlideIn(
                                  index: 2,
                                  child: Column(
                                    children: [
                                      _AuthField(
                                        controller:   nameController,
                                        hint:         AppLocalizations.get('your_name'),
                                        icon:         Icons.person_outline,
                                        keyboardType: TextInputType.name,
                                      ),
                                      const SizedBox(height: 12),
                                      _AuthField(
                                        controller:   phoneController,
                                        hint:         AppLocalizations.get('phone_number'),
                                        icon:         Icons.phone_outlined,
                                        keyboardType: TextInputType.phone,
                                      ),
                                      const SizedBox(height: 12),
                                      if (isSignUp) ...[
                                        _AuthField(
                                          controller:   inviteCodeController,
                                          hint:         AppLocalizations.get('invite_code_hint'),
                                          icon:         Icons.vpn_key_outlined,
                                          keyboardType: TextInputType.text,
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                    ],
                                  ),
                                ),
                              ],

                              // ── Email (always) ────────────────────────────
                              _buildAnimatedSlideIn(
                                index: 4,
                                child: _AuthField(
                                  controller:   emailController,
                                  hint:         isSignUp
                                      ? AppLocalizations.get('email')
                                      : AppLocalizations.get('email_or_phone'),
                                  icon:         Icons.mail_outline,
                                  keyboardType: TextInputType.emailAddress,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // ── Password (always) ─────────────────────────
                              _buildAnimatedSlideIn(
                                index: 5,
                                child: _AuthField(
                                  controller:  passwordController,
                                  hint:        AppLocalizations.get('auth_password'),
                                  icon:        Icons.lock_outline,
                                  obscureText: !showPassword,
                                  suffix: IconButton(
                                    onPressed:   () => setState(() => showPassword = !showPassword),
                                    splashRadius: 18,
                                    icon: Icon(
                                      showPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: const Color(0xff6F7368),
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              // ── Submit button ─────────────────────────────
                              _buildAnimatedSlideIn(
                                index: 6,
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: busy ? null : submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: const Color(0xFF1A1A1A),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      elevation: 5,
                                      shadowColor: AppColors.primary.withOpacity(0.42),
                                      padding: EdgeInsets.zero,
                                    ),
                                    child: busy
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.black,
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                isSignUp
                                                    ? AppLocalizations.get('auth_create_account')
                                                    : AppLocalizations.get('auth_sign_in_action'),
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.3,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              const Icon(Icons.arrow_forward_rounded, size: 20),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // ── Terms (pinned bottom) ─────────────────────────────
                      _buildAnimatedSlideIn(
                        index: 9,
                        child: Text(
                          AppLocalizations.get('auth_terms'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Auth Mode Toggle Button
// ─────────────────────────────────────────────────────────────────────────────

class _AuthModeButton extends StatelessWidget {
  const _AuthModeButton({
    required this.text,
    required this.active,
    required this.onTap,
  });
  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration:  const Duration(milliseconds: 180),
        height:    42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.maroon : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: active
              ? Border.all(color: AppColors.primary.withOpacity(0.50), width: 1)
              : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            color:      active ? AppColors.primary : AppColors.muted,
            fontSize:   14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text Field
// ─────────────────────────────────────────────────────────────────────────────

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText  = false,
    this.suffix,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String        hint;
  final IconData      icon;
  final bool          obscureText;
  final Widget?       suffix;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:   controller,
      obscureText:  obscureText,
      keyboardType: keyboardType,
      style:        const TextStyle(color: AppColors.foreground),
      decoration: InputDecoration(
        hintText:  hint,
        hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
        prefixIcon:  Icon(icon, color: AppColors.maroon.withOpacity(0.55), size: 20),
        suffixIcon:  suffix,
        filled:      true,
        fillColor:   AppColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:   const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          borderSide:   BorderSide(color: AppColors.primary, width: 1.8),
        ),
      ),
    );
  }
}
