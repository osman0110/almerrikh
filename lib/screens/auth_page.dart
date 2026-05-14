import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api_service.dart';
import '../app_colors.dart';
import '../app_constants.dart';
import '../app_localizations.dart';
import '../app_state.dart';
import '../storage.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with SingleTickerProviderStateMixin {
  static const bool _offlineAuthEnabled = false;

  UserRole? _selectedRole;
  bool isSignUp = false;
  bool showPassword = false;
  bool busy = false;

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  String _roleRoute() {
    switch (_selectedRole ?? UserRole.club) {
      case UserRole.club:     return '/club';
      case UserRole.academy:  return '/academy';
      case UserRole.player:   return '/player';
      case UserRole.parent:   return '/parent';
    }
  }

  Future<void> _saveRole() async {
    final role = _selectedRole ?? UserRole.club;
    currentUserRole = role;
    await OnboardingStore().setUserRole(role);
  }

  Future<void> submit() async {
    final email = emailController.text.trim();
    final phone = phoneController.text.trim();
    final password = passwordController.text;
    final name = nameController.text.trim();
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+');
    final phoneDigits = phone.replaceAll(RegExp(r'\D'), '');
    final loginDigits = email.replaceAll(RegExp(r'\D'), '');
    final loginLooksLikePhone = loginDigits.length >= 8 && !email.contains('@');

    if (_offlineAuthEnabled) {
      setState(() => busy = true);
      final offlineName = name.isNotEmpty
          ? name
          : email.isNotEmpty
              ? email.split('@').first
              : 'User';
      await _continueOffline(offlineName);
      return;
    }

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
    if (isSignUp && name.isEmpty) {
      _showSnack(AppLocalizations.get('error_name_required'));
      return;
    }
    if (isSignUp && phoneDigits.length < 8) {
      _showSnack(AppLocalizations.get('error_invalid_phone'));
      return;
    }

    setState(() => busy = true);
    try {
      final result = isSignUp
          ? await ApiService.register(
              name: name,
              email: email,
              phone: phone,
              password: password,
            )
          : await ApiService.login(email: email, password: password);

      if (result.containsKey('error')) {
        if (isSignUp) {
          await _continueOffline(name);
        } else {
          _showSnack(result['error'] as String);
          setState(() => busy = false);
        }
        return;
      }

      final token = result['token'] as String;
      final user = result['user'] as Map<String, dynamic>;
      final userName = user['name'] as String;

      currentUserName = userName;
      await OnboardingStore().setSignedIn(token: token, userName: userName);
      await _saveRole();

      if (!mounted) return;
      setState(() => busy = false);
      Navigator.of(context).pushNamedAndRemoveUntil(_roleRoute(), (_) => false);
    } catch (e) {
      if (isSignUp) {
        await _continueOffline(name);
      } else {
        _showSnack(AppLocalizations.get('error_connection'));
        setState(() => busy = false);
      }
    }
  }

  Future<void> _continueOffline(String name) async {
    currentUserName = name.isNotEmpty ? name : 'User';
    await OnboardingStore().setSignedIn(
      token: 'offline-demo-${DateTime.now().millisecondsSinceEpoch}',
      userName: currentUserName,
    );
    await _saveRole();
    if (!mounted) return;
    setState(() => busy = false);
    Navigator.of(context).pushNamedAndRemoveUntil(_roleRoute(), (_) => false);
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildAnimatedSlideIn({required Widget child, required int index}) {
    final start = 0.2 + (index * 0.08); // يبدأ بعد ظهور اللوجو
    final end = (start + 0.35).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _animController,
      curve: Interval(start.clamp(0.0, 1.0), end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Opacity(
          opacity: animation.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - animation.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedRole == null) {
      return _RolePickerPage(onSelect: (role) {
        setState(() => _selectedRole = role);
        _animController.forward(from: 0);
      });
    }

    final isAr = getAppLanguage() == 'ar';
    final title = isSignUp
        ? AppLocalizations.get('auth_title_signup')
        : AppLocalizations.get('auth_title_login');
    final subtitle = isSignUp
        ? AppLocalizations.get('auth_subtitle_signup')
        : AppLocalizations.get('auth_subtitle_login');

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Theme(
        data: isAr
            ? Theme.of(context).copyWith(
                textTheme: GoogleFonts.tajawalTextTheme(
                  Theme.of(context).textTheme,
                ),
              )
            : Theme.of(context),
        child: Scaffold(
        backgroundColor: const Color(0xff08090F),
        body: Center(
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
                            const SizedBox(height: 8),
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0.0, end: 1.0),
                              duration: const Duration(milliseconds: 900),
                              curve: Curves.easeOutBack,
                              builder: (context, value, child) {
                                return Transform.scale(
                                  scale: value,
                                  child: Opacity(
                                    opacity: value.clamp(0.0, 1.0),
                                    child: child,
                                  ),
                                );
                              },
                              child: Image.asset(
                                'assets/images/ssot-logo.png',
                                width: 88,
                                height: 88,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildAnimatedSlideIn(
                              index: 0,
                              child: Column(
                                children: [
                                  Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 27,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.68),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildAnimatedSlideIn(
                              index: 1,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xff150D1A),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _AuthModeButton(
                                        text: AppLocalizations.get(
                                          'auth_sign_in',
                                        ),
                                        active: !isSignUp,
                                        onTap: () =>
                                            setState(() => isSignUp = false),
                                      ),
                                    ),
                                    Expanded(
                                      child: _AuthModeButton(
                                        text: AppLocalizations.get(
                                          'auth_sign_up',
                                        ),
                                        active: isSignUp,
                                        onTap: () =>
                                            setState(() => isSignUp = true),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (isSignUp)
                              _buildAnimatedSlideIn(
                                index: 2,
                                child: Column(
                                  children: [
                                    _AuthField(
                                      controller: nameController,
                                      hint: AppLocalizations.get('your_name'),
                                      icon: Icons.person_outline,
                                      keyboardType: TextInputType.name,
                                    ),
                                    const SizedBox(height: 12),
                                    _AuthField(
                                      controller: phoneController,
                                      hint: AppLocalizations.get('phone_number'),
                                      icon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ),
                            _buildAnimatedSlideIn(
                              index: 3,
                              child: _AuthField(
                                controller: emailController,
                                hint: isSignUp
                                    ? AppLocalizations.get('email')
                                    : AppLocalizations.get('email_or_phone'),
                                icon: Icons.mail_outline,
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildAnimatedSlideIn(
                              index: 4,
                              child: _AuthField(
                                controller: passwordController,
                                hint: AppLocalizations.get('auth_password'),
                                icon: Icons.lock_outline,
                                obscureText: !showPassword,
                                suffix: IconButton(
                                  onPressed: () {
                                    setState(() => showPassword = !showPassword);
                                  },
                                  splashRadius: 18,
                                  icon: Icon(
                                    showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: Colors.white54,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildAnimatedSlideIn(
                              index: 5,
                              child: SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: busy ? null : submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xffCC0A00),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.black,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              isSignUp
                                                  ? AppLocalizations.get(
                                                      'auth_create_account',
                                                    )
                                                  : AppLocalizations.get(
                                                      'auth_sign_in_action',
                                                    ),
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Icon(
                                              Icons.arrow_forward,
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _buildAnimatedSlideIn(
                              index: 6,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: Colors.white.withOpacity(0.10),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      AppLocalizations.get('auth_or_continue'),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.58),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: Colors.white.withOpacity(0.10),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            _buildAnimatedSlideIn(
                              index: 7,
                              child: SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => _showSnack(
                                          AppLocalizations.get(
                                            'auth_google_soon',
                                          ),
                                        ),
                                  icon: const _GoogleGIcon(),
                                  label: Text(
                                    AppLocalizations.get('auth_google'),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: Colors.white.withOpacity(0.14),
                                    ),
                                    backgroundColor: const Color(0xff100F18),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildAnimatedSlideIn(
                      index: 8,
                      child: Text(
                        AppLocalizations.get('auth_terms'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
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
      ),
    ),
  );
  }
}

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
        duration: const Duration(milliseconds: 180),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xff150D1A) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.52),
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, color: Colors.white54, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xff100F18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: Color(0xffCC0A00), width: 1.2),
        ),
      ),
    );
  }
}

class _GoogleGIcon extends StatelessWidget {
  const _GoogleGIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: const Text(
        'G',
        style: TextStyle(
          color: Color(0xff1a73e8),
          fontWeight: FontWeight.w900,
          fontSize: 12,
          height: 1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Role Picker Page
// ─────────────────────────────────────────────────────────────────────────────

class _RolePickerPage extends StatelessWidget {
  const _RolePickerPage({required this.onSelect});
  final ValueChanged<UserRole> onSelect;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xff08090F);
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/ssot-logo.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'من أنت؟',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اختر نوع حسابك للمتابعة',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _RoleCard(
                    role: UserRole.club,
                    icon: Icons.sports_soccer_rounded,
                    title: 'نادي رياضي',
                    subtitle: 'مدرب بدني / إدارة النادي',
                    color: const Color(0xffCC0A00),
                    onTap: () => onSelect(UserRole.club),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    role: UserRole.academy,
                    icon: Icons.school_rounded,
                    title: 'أكاديمية',
                    subtitle: 'مدرب أكاديمية / مسؤول برامج',
                    color: const Color(0xff1565C0),
                    onTap: () => onSelect(UserRole.academy),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    role: UserRole.player,
                    icon: Icons.directions_run_rounded,
                    title: 'لاعب',
                    subtitle: 'تابع أداءك وتقييماتك',
                    color: const Color(0xff2E7D32),
                    onTap: () => onSelect(UserRole.player),
                  ),
                  const SizedBox(height: 12),
                  _RoleCard(
                    role: UserRole.parent,
                    icon: Icons.family_restroom_rounded,
                    title: 'ولي الأمر',
                    subtitle: 'تابع تقدم نجلك',
                    color: const Color(0xff6A1B9A),
                    onTap: () => onSelect(UserRole.parent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final UserRole role;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xff100F18),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.30), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.52),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.35), size: 22),
          ],
        ),
      ),
    );
  }
}
