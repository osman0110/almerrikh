import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_colors.dart';
import '../app_constants.dart';
import '../app_localizations.dart';
import '../models/onboard_slide.dart';
import '../storage.dart';
import '../widgets/onboarding_widgets.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  String? selectedLang;
  bool languageConfirmed = false;
  int slideIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    final savedLang = await OnboardingStore().getLanguage();
    if (savedLang != null) {
      setState(() {
        selectedLang = savedLang;
        languageConfirmed = true;
        setAppLanguage(savedLang);
      });
    }
  }

  Future<void> _saveLanguage(String lang) async {
    await OnboardingStore().setLanguage(lang);
    setAppLanguage(lang);
  }

  static const neonGreen = AppColors.primary;

  static const slides = [
    OnboardSlide(
      image: 'assets/images/onboard-feature-1.webp',
      titleKey: 'slide1_title',
      subtitleKey: 'slide1_desc',
      ctaKey: 'next_btn',
    ),
    OnboardSlide(
      image: 'assets/images/onboard-feature-2.webp',
      titleKey: 'slide2_title',
      subtitleKey: 'slide2_desc',
      ctaKey: 'next_btn',
    ),
    OnboardSlide(
      image: 'assets/images/onboard-feature-3.webp',
      titleKey: 'slide3_title',
      subtitleKey: 'slide3_desc',
      ctaKey: 'get_started_btn',
    ),
  ];

  Future<void> finish() async {
    await OnboardingStore().setSeenOnboarding();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/auth', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!languageConfirmed) {
      return _buildLanguageScreen();
    }
    return _buildOnboardingSlides();
  }

  Widget _buildLanguageScreen() {
    final isAr = selectedLang == 'ar';
    final textStyle = isAr ? GoogleFonts.cairo() : const TextStyle();
    final languages = [
      (code: 'ar', name: 'العربية', subName: 'Arabic', label: 'AR'),
      (code: 'en', name: 'English', subName: 'الإنجليزية', label: 'EN'),
      (code: 'fr', name: 'Français', subName: 'الفرنسية', label: 'FR'),
    ];

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // ── Language selection background ───────────────────────────
            Positioned.fill(
              child: Image.asset('assets/images/LANG-BG.webp', fit: BoxFit.cover),
            ),
          Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
            child: SafeArea(
              child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Brand row ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF9B1020), AppColors.maroonDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.50),
                              width: 1.5,
                            ),
                          ),
                          padding: const EdgeInsets.all(9),
                          child: Image.asset(logoAsset, fit: BoxFit.contain),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            AppLocalizations.get('club_brand_name'),
                            style: textStyle.copyWith(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // ── Card ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 48,
                            offset: const Offset(0, 16),
                          ),
                          BoxShadow(
                            color: AppColors.maroon.withOpacity(0.06),
                            blurRadius: 24,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLocalizations.get('choose_language'),
                            style: textStyle.copyWith(
                              color: AppColors.foreground,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppLocalizations.get('language_desc'),
                            style: textStyle.copyWith(
                              color: AppColors.muted,
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          // ── Language options ───────────────────────────
                          ...languages.map((lang) {
                            final isSelected = selectedLang == lang.code;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => selectedLang = lang.code);
                                  setAppLanguage(lang.code);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.background : AppColors.card,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected ? AppColors.foreground : AppColors.border,
                                      width: isSelected ? 2.0 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppColors.hero : AppColors.surface2,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          lang.label,
                                          style: TextStyle(
                                            color: isSelected ? neonGreen : AppColors.muted,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              lang.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 15,
                                                color: AppColors.foreground,
                                              ),
                                            ),
                                            Text(
                                              lang.subName,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: const BoxDecoration(
                                            color: neonGreen,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check_rounded,
                                            color: AppColors.hero,
                                            size: 14,
                                          ),
                                        )
                                      else
                                        Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(color: AppColors.border, width: 1.5),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          // ── Continue button ────────────────────────────
                          GestureDetector(
                            onTap: () {
                              if (selectedLang != null) {
                                _saveLanguage(selectedLang!).then((_) {
                                  if (!mounted) return;
                                  setState(() => languageConfirmed = true);
                                });
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 52,
                              decoration: BoxDecoration(
                                color: selectedLang != null
                                    ? AppColors.primary
                                    : AppColors.surface2,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: selectedLang != null ? [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.38),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ] : [],
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    AppLocalizations.get('continue_btn'),
                                    style: textStyle.copyWith(
                                      color: selectedLang != null
                                          ? const Color(0xFF1A1A1A)
                                          : AppColors.muted,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    color: selectedLang != null
                                        ? const Color(0xFF1A1A1A)
                                        : AppColors.muted,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
    );
  }

  Widget _buildOnboardingSlides() {
    final slide = slides[slideIndex];
    final isLast = slideIndex == slides.length - 1;
    final heroHeight = (MediaQuery.of(context).size.height * 0.75)
        .clamp(420.0, 620.0)
        .toDouble();
    final isAr = getAppLanguage() == 'ar';
    final textStyle = isAr ? GoogleFonts.cairo() : const TextStyle();

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
            child: Column(
              children: [
                // ── Full-bleed image section ─────────────────────────────
                GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if (details.velocity.pixelsPerSecond.dx > 300) {
                      if (slideIndex > 0) setState(() => slideIndex--);
                    } else if (details.velocity.pixelsPerSecond.dx < -300) {
                      if (slideIndex < 2) setState(() => slideIndex++);
                    }
                  },
                  child: SizedBox(
                    height: heroHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          child: OnboardingImageStage(
                            key: ValueKey(slide.image),
                            asset: slide.image,
                          ),
                        ),
                        // Gradient: transparent → cream (matching design)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, AppColors.background],
                              stops: const [0.48, 1.0],
                            ),
                          ),
                        ),
                        // Slide kicker label
                        Positioned(
                          top: 14,
                          left: 20,
                          right: 20,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.50),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.18),
                                  ),
                                ),
                                child: Text(
                                  '0${slideIndex + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.08,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (!isLast)
                                GestureDetector(
                                  onTap: finish,
                                  child: const Text(
                                    'تخطّي',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // ── Content section (cream bg) ───────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
                      child: Column(
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            child: Column(
                              key: ValueKey(slide.titleKey),
                              children: [
                                Text(
                                  AppLocalizations.get(slide.titleKey),
                                  textAlign: TextAlign.center,
                                  style: textStyle.copyWith(
                                    fontSize: isAr ? 25 : 24,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.foreground,
                                    height: 1.18,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  AppLocalizations.get(slide.subtitleKey),
                                  textAlign: TextAlign.center,
                                  style: textStyle.copyWith(
                                    fontSize: 14.5,
                                    color: AppColors.muted,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          // ── Page dots ──────────────────────────────────
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(3, (i) {
                              final active = i == slideIndex;
                              return GestureDetector(
                                onTap: () => setState(() => slideIndex = i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: active ? 28 : 8,
                                  height: 8,
                                  margin: const EdgeInsets.symmetric(horizontal: 3.5),
                                  decoration: BoxDecoration(
                                    color: active ? neonGreen : AppColors.border,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 22),
                          // ── CTA button ─────────────────────────────────
                          GestureDetector(
                            onTap: () {
                              if (isLast) finish();
                              else setState(() => slideIndex++);
                            },
                            child: Container(
                              width: double.infinity,
                              height: 54,
                              decoration: BoxDecoration(
                                color: isLast ? neonGreen : AppColors.maroon,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isLast ? AppColors.primary : AppColors.maroon)
                                        .withOpacity(0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  AppLocalizations.get(slide.ctaKey),
                                  style: textStyle.copyWith(
                                    fontSize: isAr ? 18 : 16,
                                    fontWeight: FontWeight.w800,
                                    color: isLast ? const Color(0xFF1A1A1A) : AppColors.onDark,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // ── Login shortcut — always visible, every slide ──
                          GestureDetector(
                            onTap: finish,
                            child: Text(
                              AppLocalizations.get('already_have_account_login'),
                              style: textStyle.copyWith(
                                color: AppColors.muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
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
