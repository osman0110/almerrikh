import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api_service.dart';
import '../app_constants.dart';
import '../app_localizations.dart';
import '../app_state.dart';

class ProfileOnboardingPage extends StatefulWidget {
  const ProfileOnboardingPage({super.key});

  @override
  State<ProfileOnboardingPage> createState() => _ProfileOnboardingPageState();
}

class _ProfileOnboardingPageState extends State<ProfileOnboardingPage> {
  static const bool _offlineProfileEnabled = true;

  int step = 0;
  bool _goingForward = true;
  int playerAge = 16;
  final List<String> selectedPositions = [];
  String? selectedFoot;
  List<String> selectedWeaknesses = [];
  bool isSubmitting = false;

  static const neonGreen = Color(0xff39ff14);
  static const darkBg = Color(0xff050508);
  static const stepTitleKeys = [
    'profile_step1',
    'profile_step2',
    'profile_step3',
    'profile_step4',
  ];
  static const stepDescKeys = [
    'profile_step1_desc',
    'profile_step2_desc',
    'profile_step3_desc',
    'profile_step4_desc',
  ];

  static const positions = [
    ('GK', 'Goalkeeper', 50, 92),
    ('LB', 'Left Back', 18, 75),
    ('CB', 'Center Back', 50, 78),
    ('RB', 'Right Back', 82, 75),
    ('CDM', 'Defensive Mid', 50, 60),
    ('CM', 'Center Mid', 30, 48),
    ('CAM', 'Attacking Mid', 50, 38),
    ('LW', 'Left Winger', 18, 22),
    ('RW', 'Right Winger', 82, 22),
    ('ST', 'Striker', 50, 12),
  ];

  static const weaknesses = [
    ('weak-foot', 'Weak foot', Icons.directions_run),
    ('first-touch', 'First touch', Icons.pan_tool),
    ('shooting', 'Shooting', Icons.track_changes),
    ('speed', 'Speed', Icons.local_fire_department),
    ('stamina', 'Stamina', Icons.favorite),
    ('strength', 'Strength', Icons.security),
    ('reaction', 'Reaction time', Icons.bolt),
    ('decisions', 'Decision making', Icons.psychology),
    ('vision', 'Vision', Icons.visibility),
  ];

  bool get canNext {
    switch (step) {
      case 0:
        return playerAge >= 6 && playerAge <= 60;
      case 1:
        return selectedPositions.isNotEmpty;
      case 2:
        return selectedFoot != null;
      case 3:
        return selectedWeaknesses.isNotEmpty;
      default:
        return false;
    }
  }

  void nextStep() {
    if (step < stepTitleKeys.length - 1) {
      setState(() {
        _goingForward = true;
        step++;
      });
    } else {
      finishProfile();
    }
  }

  void prevStep() {
    if (step > 0) {
      setState(() {
        _goingForward = false;
        step--;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> finishProfile() async {
    setState(() => isSubmitting = true);
    if (_offlineProfileEnabled) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      setState(() => isSubmitting = false);
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      return;
    }

    try {
      final result = await ApiService.saveProfile(
        playerName: currentUserName,
        age: playerAge,
        position: selectedPositions.join(', '),
        foot: selectedFoot!,
        weaknesses: selectedWeaknesses,
      );

      if (result.containsKey('error')) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result['error'] as String)));
        if (mounted) setState(() => isSubmitting = false);
        return;
      }

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Connection error: $e')));
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void toggleWeakness(String id) {
    setState(() {
      if (selectedWeaknesses.contains(id)) {
        selectedWeaknesses.remove(id);
      } else {
        selectedWeaknesses.add(id);
      }
    });
  }

  void togglePosition(String code) {
    setState(() {
      if (selectedPositions.contains(code)) {
        selectedPositions.remove(code);
      } else {
        selectedPositions.add(code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAr = getAppLanguage() == 'ar';
    final textStyle = isAr ? GoogleFonts.tajawal() : const TextStyle();

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: darkBg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isSmall = constraints.maxHeight < 720;
                  final horizontal = isSmall ? 18.0 : 24.0;
                  return Column(
                    children: [
                  // Top bar
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, isSmall ? 8 : 12, 16, isSmall ? 10 : 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: prevStep,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Icon(
                              isAr ? Icons.arrow_forward : Icons.arrow_back,
                              color: Colors.white70,
                              size: 18,
                            ),
                          ),
                        ),
                        Text(
                          AppLocalizations.format('step_counter', {
                            'current': step + 1,
                            'total': stepTitleKeys.length,
                          }),
                          style: textStyle.copyWith(
                            fontSize: 12,
                            color: Colors.white54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                  // Progress dots
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: List.generate(
                        stepTitleKeys.length,
                        (i) => Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i < step
                                  ? neonGreen
                                  : i == step
                                  ? neonGreen.withOpacity(0.6)
                                  : Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isSmall ? 12 : 20),
                  // Title and description
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontal),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.get(stepTitleKeys[step]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(
                            fontSize: isSmall ? 21 : 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          AppLocalizations.get(stepDescKeys[step]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle.copyWith(
                            fontSize: 13,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isSmall ? 12 : 24),
                  // Content
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: horizontal),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, animation) {
                          final offset = _goingForward
                              ? const Offset(1.0, 0.0)
                              : const Offset(-1.0, 0.0);
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: offset,
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            )),
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: SingleChildScrollView(
                          key: ValueKey(step),
                          child: step == 0
                              ? _buildStep0(textStyle)
                              : step == 1
                              ? _buildStep1(textStyle)
                              : step == 2
                              ? _buildStep2(textStyle)
                              : _buildStep3(textStyle),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isSmall ? 12 : 20),
                  // Next button
                  Padding(
                    padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, isSmall ? 14 : 24),
                    child: GestureDetector(
                      onTap: canNext && !isSubmitting ? nextStep : null,
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: canNext && !isSubmitting
                              ? const LinearGradient(
                                  colors: [neonGreen, Color(0xff20cc00)],
                                )
                              : LinearGradient(
                                  colors: [
                                    Colors.white.withOpacity(0.1),
                                    Colors.white.withOpacity(0.05),
                                  ],
                                ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: canNext && !isSubmitting
                              ? [
                                  BoxShadow(
                                    color: neonGreen.withOpacity(0.4),
                                    blurRadius: 20,
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      neonGreen,
                                    ),
                                  ),
                                )
                              : Text(
                                  step == stepTitleKeys.length - 1
                                      ? AppLocalizations.get('finish_btn')
                                      : AppLocalizations.get('next_btn'),
                                  style: textStyle.copyWith(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: canNext && !isSubmitting
                                        ? Colors.black
                                        : Colors.white30,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep0(TextStyle textStyle) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppLocalizations.get('age'),
              style: textStyle.copyWith(color: Colors.white54),
            ),
            Text(
              '$playerAge',
              style: textStyle.copyWith(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: neonGreen,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Slider(
          value: playerAge.toDouble(),
          min: 6,
          max: 60,
          divisions: 54,
          activeColor: neonGreen,
          inactiveColor: Colors.white.withOpacity(0.1),
          onChanged: (value) => setState(() => playerAge = value.toInt()),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '6',
              style: textStyle.copyWith(fontSize: 11, color: Colors.white30),
            ),
            Text(
              'U-12',
              style: textStyle.copyWith(fontSize: 11, color: Colors.white30),
            ),
            Text(
              'U-17',
              style: textStyle.copyWith(fontSize: 11, color: Colors.white30),
            ),
            Text(
              AppLocalizations.get('pro_label'),
              style: textStyle.copyWith(fontSize: 11, color: Colors.white30),
            ),
            Text(
              '60',
              style: textStyle.copyWith(fontSize: 11, color: Colors.white30),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep1(TextStyle textStyle) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xff0d3d0a), Color(0xff0a2808)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: neonGreen.withOpacity(0.3), width: 2),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const buttonSize = 44.0;
                final pitchWidth = constraints.maxWidth;
                final pitchHeight = constraints.maxHeight;

                double leftFor(int percent) {
                  return ((percent / 100) * pitchWidth) - (buttonSize / 2);
                }

                double topFor(int percent) {
                  return ((percent / 100) * pitchHeight) - (buttonSize / 2);
                }

                return Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: PitchPainter())),
                    ...positions.map((p) {
                      final isSelected = selectedPositions.contains(p.$1);
                      return Positioned(
                        left: leftFor(p.$3),
                        top: topFor(p.$4),
                        child: GestureDetector(
                          onTap: () => togglePosition(p.$1),
                          child: Container(
                            width: buttonSize,
                            height: buttonSize,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? neonGreen
                                  : Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    isSelected ? Colors.white : Colors.white60,
                                width: 2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: neonGreen.withOpacity(0.6),
                                        blurRadius: 12,
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: Text(
                                p.$1,
                                style: textStyle.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? Colors.black
                                      : const Color(0xff0d3d0a),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                );
              },
            ),
          ),
        ),
        if (selectedPositions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: neonGreen.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: selectedPositions.map((code) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: neonGreen.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        code,
                        style: textStyle.copyWith(
                          fontWeight: FontWeight.w800,
                          color: neonGreen,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Text(
                  selectedPositions
                      .map((code) => positions.firstWhere((p) => p.$1 == code).$2)
                      .join(', '),
                  style: textStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  AppLocalizations.get('role_adapt_hint'),
                  style: textStyle.copyWith(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStep2(TextStyle textStyle) {
    final options = [
      ('left', 'left_foot', 'left_footed'),
      ('right', 'right_foot', 'right_footed'),
      ('both', 'both_feet', 'two_footed'),
    ];

    return Row(
      children: options.map((opt) {
        final isSelected = selectedFoot == opt.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => selectedFoot = opt.$1),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? neonGreen.withOpacity(0.15)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? neonGreen : Colors.white.withOpacity(0.1),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.directions_run,
                    color: isSelected ? neonGreen : Colors.white54,
                    size: 32,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.get(opt.$2),
                    style: textStyle.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isSelected ? neonGreen : Colors.white,
                    ),
                  ),
                  Text(
                    AppLocalizations.get(opt.$3),
                    style: textStyle.copyWith(
                      fontSize: 10,
                      color: isSelected ? neonGreen : Colors.white54,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: neonGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.black,
                        size: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStep3(TextStyle textStyle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.get('pick_at_least_one'),
                style: textStyle.copyWith(
                  fontSize: 12,
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: neonGreen.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  AppLocalizations.format('selected_count', {
                    'count': selectedWeaknesses.length,
                  }),
                  style: textStyle.copyWith(
                    fontSize: 11,
                    color: neonGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: 2,
          childAspectRatio: 1.2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: weaknesses.map((w) {
            final isSelected = selectedWeaknesses.contains(w.$1);
            return GestureDetector(
              onTap: () => toggleWeakness(w.$1),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? neonGreen.withOpacity(0.15)
                      : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? neonGreen
                        : Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          w.$3,
                          color: isSelected ? neonGreen : Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(height: 6),
                        Flexible(
                          child: Text(
                            w.$2,
                            style: textStyle.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? neonGreen : Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isSelected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: neonGreen,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.black,
                            size: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1.2;

    final center = Offset(size.width / 2, size.height / 2);

    // Outer lines
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.1,
        size.height * 0.05,
        size.width * 0.8,
        size.height * 0.9,
      ),
      paint,
    );

    // Center line
    canvas.drawLine(
      Offset(center.dx, size.height * 0.05),
      Offset(center.dx, size.height * 0.95),
      paint,
    );

    // Center circle
    canvas.drawCircle(center, size.width * 0.15, paint);
    canvas.drawCircle(center, 2, paint);
  }

  @override
  bool shouldRepaint(PitchPainter oldDelegate) => false;
}
