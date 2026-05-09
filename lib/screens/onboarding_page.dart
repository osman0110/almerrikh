import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_constants.dart';
import '../app_localizations.dart';
import '../models/onboard_slide.dart';
import '../storage.dart';
import '../widgets/looping_video_background.dart';
import '../widgets/onboarding_widgets.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  String? selectedLang;
  bool languageConfirmed = false;
  bool showLanguageChooser = true;
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

  static const neonGreen = Color(0xff39ff14);
  static const darkBg = Color(0xff050508);

  static const slides = [
    OnboardSlide(
      image: 'assets/images/onboard-feature-1.png',
      titleKey: 'slide1_title',
      subtitleKey: 'slide1_desc',
      ctaKey: 'next_btn',
    ),
    OnboardSlide(
      image: 'assets/images/onboard-feature-2.png',
      titleKey: 'slide2_title',
      subtitleKey: 'slide2_desc',
      ctaKey: 'next_btn',
    ),
    OnboardSlide(
      image: 'assets/images/onboard-feature-3.png',
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
    final textStyle = isAr ? GoogleFonts.tajawal() : const TextStyle();
    final languages = [
      (code: 'en', name: 'English', label: 'EN', icon: Icons.translate_rounded),
      (code: 'ar', name: 'العربية', label: 'AR', icon: Icons.language_rounded),
      (code: 'fr', name: 'Français', label: 'FR', icon: Icons.public_rounded),
    ];

    return _buildVideoLanguageScreen(isAr, textStyle, languages);

  }

  Widget _buildVideoLanguageScreen(
    bool isAr,
    TextStyle textStyle,
    List<
      ({
        String code,
        String name,
        String label,
        IconData icon,
      })
    > languages,
  ) {
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: darkBg,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const LoopingVideoBackground(
                  asset: languageVideoAsset,
                ),
                Opacity(
                  opacity: 0.10,
                  child: CustomPaint(painter: GridPainter()),
                ),
                IgnorePointer(
                  ignoring: !showLanguageChooser,
                  child: AnimatedOpacity(
                    opacity: showLanguageChooser ? 1 : 0,
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    child: AnimatedSlide(
                      offset: showLanguageChooser
                          ? Offset.zero
                          : const Offset(0, 0.04),
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeOutCubic,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 26, 24, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.62),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: neonGreen.withOpacity(0.70),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: neonGreen.withOpacity(0.28),
                                          blurRadius: 28,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Image.asset('logo.png'),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 13,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.48),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.12),
                                      ),
                                    ),
                                    child: Text(
                                      'NextKick',
                                      style: textStyle.copyWith(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.58),
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.12),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.46),
                                      blurRadius: 42,
                                      offset: const Offset(0, 18),
                                    ),
                                    BoxShadow(
                                      color: neonGreen.withOpacity(0.10),
                                      blurRadius: 36,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      AppLocalizations.get('choose_language'),
                                      textAlign: TextAlign.start,
                                      style: textStyle.copyWith(
                                        fontSize: 30,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        height: 1.08,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      AppLocalizations.get('language_desc'),
                                      textAlign: TextAlign.start,
                                      style: textStyle.copyWith(
                                        fontSize: 14,
                                        color: Colors.white.withOpacity(0.70),
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    ...languages.map((lang) {
                                      final isSelected =
                                          selectedLang == lang.code;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: LanguageOptionTile(
                                          name: lang.name,
                                          label: lang.label,
                                          icon: lang.icon,
                                          selected: isSelected,
                                          textStyle: lang.code == 'ar'
                                              ? GoogleFonts.tajawal()
                                              : const TextStyle(),
                                          onTap: () {
                                            setState(
                                              () => selectedLang = lang.code,
                                            );
                                            setAppLanguage(lang.code);
                                          },
                                        ),
                                      );
                                    }),
                                    const SizedBox(height: 12),
                                    LanguageContinueButton(
                                      enabled: selectedLang != null,
                                      text: AppLocalizations.get(
                                        'continue_btn',
                                      ),
                                      textStyle: textStyle,
                                      onTap: () {
                                        if (selectedLang != null) {
                                          _saveLanguage(selectedLang!).then((_) {
                                            if (!mounted) return;
                                            setState(
                                              () => languageConfirmed = true,
                                            );
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildOnboardingSlides() {
    final slide = slides[slideIndex];
    final isLast = slideIndex == slides.length - 1;
    final heroHeight = (MediaQuery.of(context).size.height * 0.75)
        .clamp(420.0, 620.0)
        .toDouble();
    final isAr = getAppLanguage() == 'ar';
    final textStyle = isAr ? GoogleFonts.tajawal() : const TextStyle();

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0EEE7),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
            child: Column(
              children: [
                GestureDetector(
                  onHorizontalDragEnd: (details) {
                    // Swipe right to go back
                    if (details.velocity.pixelsPerSecond.dx > 300) {
                      if (slideIndex > 0) {
                        setState(() => slideIndex--);
                      }
                    }
                    // Swipe left to go next
                    else if (details.velocity.pixelsPerSecond.dx < -300) {
                      if (slideIndex < 2) {
                        setState(() => slideIndex++);
                      }
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
                        // Bottom fade
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0xFFF0EEE7)],
                              stops: [0.6, 1],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(32, 22, 32, 36),
                      child: Column(
                        children: [
                          const SizedBox(height: 20),
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
                                    color: const Color(0xff0a0a0a),
                                    height: 1.2,
                                    letterSpacing: 0,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  AppLocalizations.get(slide.subtitleKey),
                                  textAlign: TextAlign.center,
                                  style: textStyle.copyWith(
                                    fontSize: 15,
                                    color: const Color(0xff666666),
                                    height: 1.65,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                          // Dots
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
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? neonGreen
                                        : const Color(0xffc8f5b0),
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: active
                                        ? [
                                            BoxShadow(
                                              color: neonGreen.withOpacity(0.6),
                                              blurRadius: 8,
                                            ),
                                          ]
                                        : [],
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 28),
                          GestureDetector(
                            onTap: () {
                              if (isLast) {
                                finish();
                              } else {
                                setState(() => slideIndex++);
                              }
                            },
                            child: Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [neonGreen, Color(0xff20cc00)],
                                ),
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: neonGreen.withOpacity(0.45),
                                    blurRadius: 28,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  AppLocalizations.get(slide.ctaKey),
                                  style: textStyle.copyWith(
                                    fontSize: isAr ? 19 : 17,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
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
