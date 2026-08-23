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
  int step = 0;
  bool _goingForward = true;
  bool isSubmitting = false;

  // Step 0 — Age + Gender
  int playerAge = 22;
  String? gender; // male | female

  // Step 1 — Physical Stats
  double heightCm = 175;
  double weightKg = 70;

  // Step 2 — Position
  final List<String> selectedPositions = [];

  // Step 3 — Dominant Foot
  String? selectedFoot;

  // Step 4 — Training Profile
  String fitnessLevel  = 'intermediate'; // beginner | intermediate | advanced | pro
  String skillLevel    = 'amateur';      // beginner | amateur | semi_pro | pro
  String trainingGoal  = 'improve_skills';
  int daysPerWeek      = 4;
  int preferredMin     = 60;
  String injuryNotes   = '';

  // Step 5 — Weaknesses
  List<String> selectedWeaknesses = [];

  static const int _totalSteps = 6;

  static const neonGreen = Color(0xFFF7B638); // Al Merrikh gold
  static const darkBg    = Color(0xff050508);

  static const _positions = [
    ('GK', 'Goalkeeper', 50, 92),
    ('LB', 'Left Back',  18, 75),
    ('CB', 'Center Back',50, 78),
    ('RB', 'Right Back', 82, 75),
    ('CDM','Defensive Mid',50,60),
    ('CM', 'Center Mid', 30, 48),
    ('CAM','Attacking Mid',50,38),
    ('LW', 'Left Winger',18, 22),
    ('RW', 'Right Winger',82,22),
    ('ST', 'Striker',    50, 12),
  ];

  static const _weaknesses = [
    ('weak-foot',  'Weak foot',       Icons.directions_run),
    ('first-touch','First touch',     Icons.pan_tool),
    ('shooting',   'Shooting',        Icons.track_changes),
    ('speed',      'Speed',           Icons.local_fire_department),
    ('stamina',    'Stamina',         Icons.favorite),
    ('strength',   'Strength',        Icons.security),
    ('reaction',   'Reaction time',   Icons.bolt),
    ('decisions',  'Decision making', Icons.psychology),
    ('vision',     'Vision',          Icons.visibility),
  ];

  bool get canNext {
    switch (step) {
      case 0: return gender != null;
      case 1: return heightCm > 0 && weightKg > 0;
      case 2: return selectedPositions.isNotEmpty;
      case 3: return selectedFoot != null;
      case 4: return true;
      case 5: return selectedWeaknesses.isNotEmpty;
      default: return false;
    }
  }

  void nextStep() {
    if (step < _totalSteps - 1) {
      setState(() { _goingForward = true; step++; });
    } else {
      _finish();
    }
  }

  void prevStep() {
    if (step > 0) {
      setState(() { _goingForward = false; step--; });
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _finish() async {
    setState(() => isSubmitting = true);
    try {
      final bmi = weightKg / ((heightCm / 100) * (heightCm / 100));
      final payload = {
        'player_name':         currentUserName,
        'age':                 playerAge,
        'gender':              gender,
        'height':              heightCm,
        'weight':              weightKg,
        'position':            selectedPositions.join(', '),
        'foot':                selectedFoot,
        'fitness_level':       fitnessLevel,
        'skill_level':         skillLevel,
        'goal':                trainingGoal,
        'days_per_week':       daysPerWeek,
        'preferred_duration':  preferredMin,
        'injury_limitations':  injuryNotes.trim().isEmpty ? null : injuryNotes.trim(),
        'weaknesses':          selectedWeaknesses,
        'bmi':                 double.parse(bmi.toStringAsFixed(1)),
      };

      if (ApiService.token != null) {
        await ApiService.saveFullProfile(payload);
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => isSubmitting = false);
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  // ── Step titles ─────────────────────────────────────────────────────────────

  static const _stepTitles = [
    'سنك ونوعك',
    'قياساتك الجسدية',
    'مركزك في الملعب',
    'قدمك المفضلة',
    'مسار تدريبك',
    'نقاط التطوير',
  ];

  static const _stepDescs = [
    'حتى نُعدّل الخطة حسب مرحلتك',
    'لحساب BMI ومتابعة التطور',
    'نُخصص التمارين حسب مركزك',
    'لتحسين أداء القدم الضعيفة',
    'نُحدد مستوى الشدة المناسب لك',
    'ركّز على ما تريد تحسينه',
  ];

  @override
  Widget build(BuildContext context) {
    final isAr  = getAppLanguage() == 'ar';
    final tStyle = isAr ? GoogleFonts.cairo() : const TextStyle();

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: darkBg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxPhoneWidth),
              child: LayoutBuilder(builder: (context, constraints) {
                final isSmall = constraints.maxHeight < 720;
                final h = isSmall ? 18.0 : 24.0;
                return Column(children: [
                  // ── Top bar ───────────────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, isSmall ? 8 : 12, 16, isSmall ? 10 : 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: prevStep,
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Icon(isAr ? Icons.arrow_forward : Icons.arrow_back,
                                color: Colors.white70, size: 18),
                          ),
                        ),
                        Text('${step + 1} / $_totalSteps',
                            style: tStyle.copyWith(
                                fontSize: 12,
                                color: Colors.white54,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                  // ── Progress bar ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: List.generate(_totalSteps, (i) => Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i < step
                                ? neonGreen
                                : i == step
                                    ? neonGreen.withOpacity(0.6)
                                    : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      )),
                    ),
                  ),
                  SizedBox(height: isSmall ? 12 : 20),
                  // ── Title ─────────────────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_stepTitles[step],
                            style: tStyle.copyWith(
                                fontSize: isSmall ? 21 : 24,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        const SizedBox(height: 6),
                        Text(_stepDescs[step],
                            style: tStyle.copyWith(
                                fontSize: 13, color: Colors.white54)),
                      ],
                    ),
                  ),
                  SizedBox(height: isSmall ? 12 : 20),
                  // ── Content ───────────────────────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: h),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, anim) {
                          final offset = _goingForward
                              ? const Offset(1.0, 0)
                              : const Offset(-1.0, 0);
                          return SlideTransition(
                            position: Tween(begin: offset, end: Offset.zero)
                                .animate(CurvedAnimation(
                                    parent: anim,
                                    curve: Curves.easeOutCubic)),
                            child: FadeTransition(opacity: anim, child: child),
                          );
                        },
                        child: SingleChildScrollView(
                          key: ValueKey(step),
                          child: _buildStep(tStyle, isSmall),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isSmall ? 12 : 16),
                  // ── Next button ───────────────────────────────────────────
                  Padding(
                    padding: EdgeInsets.fromLTRB(h, 0, h, isSmall ? 14 : 24),
                    child: GestureDetector(
                      onTap: canNext && !isSubmitting ? nextStep : null,
                      child: Container(
                        width: double.infinity, height: 52,
                        decoration: BoxDecoration(
                          gradient: canNext && !isSubmitting
                              ? const LinearGradient(
                                  colors: [neonGreen, Color(0xff20cc00)])
                              : LinearGradient(colors: [
                                  Colors.white.withOpacity(0.1),
                                  Colors.white.withOpacity(0.05),
                                ]),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: canNext && !isSubmitting
                              ? [BoxShadow(
                                  color: neonGreen.withOpacity(0.4),
                                  blurRadius: 20)]
                              : [],
                        ),
                        child: Center(
                          child: isSubmitting
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(neonGreen)))
                              : Text(
                                  step == _totalSteps - 1 ? 'إنهاء' : 'التالي',
                                  style: tStyle.copyWith(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: canNext && !isSubmitting
                                          ? Colors.black
                                          : Colors.white30)),
                        ),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(TextStyle ts, bool isSmall) {
    switch (step) {
      case 0: return _step0Age(ts);
      case 1: return _step1Physical(ts);
      case 2: return _step2Position(ts);
      case 3: return _step3Foot(ts);
      case 4: return _step4TrainingProfile(ts, isSmall);
      case 5: return _step5Weaknesses(ts);
      default: return const SizedBox();
    }
  }

  // ── Step 0: Age + Gender ──────────────────────────────────────────────────

  Widget _step0Age(TextStyle ts) {
    return Column(
      children: [
        // Age
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('العمر', style: ts.copyWith(color: Colors.white54)),
          Text('$playerAge',
              style: ts.copyWith(
                  fontSize: 32, fontWeight: FontWeight.w800, color: neonGreen)),
        ]),
        const SizedBox(height: 8),
        Slider(
          value: playerAge.toDouble(), min: 6, max: 60, divisions: 54,
          activeColor: neonGreen, inactiveColor: Colors.white12,
          onChanged: (v) => setState(() => playerAge = v.toInt()),
        ),
        const SizedBox(height: 24),
        // Gender
        Text(AppLocalizations.get('gender_label'),
            style: ts.copyWith(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 12),
        Row(
          children: [
            _GenderBtn(label: 'ذكر', value: 'male', selected: gender == 'male',
                ts: ts, onTap: () => setState(() => gender = 'male')),
            const SizedBox(width: 12),
            _GenderBtn(label: 'أنثى', value: 'female', selected: gender == 'female',
                ts: ts, onTap: () => setState(() => gender = 'female')),
          ],
        ),
      ],
    );
  }

  // ── Step 1: Height + Weight ───────────────────────────────────────────────

  Widget _step1Physical(TextStyle ts) {
    final bmi = weightKg / ((heightCm / 100) * (heightCm / 100));
    return Column(children: [
      Text('الطول (سم)', style: ts.copyWith(color: Colors.white54)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${heightCm.round()} سم',
            style: ts.copyWith(
                fontSize: 28, fontWeight: FontWeight.w800, color: neonGreen)),
        const SizedBox(),
      ]),
      Slider(
        value: heightCm, min: 140, max: 210, divisions: 70,
        activeColor: neonGreen, inactiveColor: Colors.white12,
        onChanged: (v) => setState(() => heightCm = v),
      ),
      const SizedBox(height: 20),
      Text('الوزن (كغ)', style: ts.copyWith(color: Colors.white54)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('${weightKg.round()} كغ',
            style: ts.copyWith(
                fontSize: 28, fontWeight: FontWeight.w800, color: neonGreen)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('BMI ${bmi.toStringAsFixed(1)}',
              style: ts.copyWith(color: Colors.white54, fontSize: 13)),
        ),
      ]),
      Slider(
        value: weightKg, min: 40, max: 130, divisions: 90,
        activeColor: neonGreen, inactiveColor: Colors.white12,
        onChanged: (v) => setState(() => weightKg = v),
      ),
    ]);
  }

  // ── Step 2: Position ─────────────────────────────────────────────────────

  Widget _step2Position(TextStyle ts) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xff0d3d0a), Color(0xff0a2808)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: neonGreen.withOpacity(0.3), width: 2),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          const sz = 44.0;
          final pw = constraints.maxWidth;
          final ph = constraints.maxHeight;
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
            ..._positions.map((p) {
              final sel = selectedPositions.contains(p.$1);
              return Positioned(
                left:  ((p.$3 / 100) * pw) - (sz / 2),
                top:   ((p.$4 / 100) * ph) - (sz / 2),
                child: GestureDetector(
                  onTap: () => setState(() {
                    if (sel) selectedPositions.remove(p.$1);
                    else selectedPositions.add(p.$1);
                  }),
                  child: Container(
                    width: sz, height: sz,
                    decoration: BoxDecoration(
                      color: sel ? neonGreen : Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: sel ? Colors.white : Colors.white60, width: 2),
                      boxShadow: sel
                          ? [BoxShadow(
                              color: neonGreen.withOpacity(0.6), blurRadius: 12)]
                          : [],
                    ),
                    child: Center(
                      child: Text(p.$1,
                          style: ts.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: sel ? Colors.black : const Color(0xff0d3d0a))),
                    ),
                  ),
                ),
              );
            }),
          ]);
        }),
      ),
    );
  }

  // ── Step 3: Dominant Foot ─────────────────────────────────────────────────

  Widget _step3Foot(TextStyle ts) {
    final opts = [
      ('left',  'left_foot',  'left_footed'),
      ('right', 'right_foot', 'right_footed'),
      ('both',  'both_feet',  'two_footed'),
    ];
    return Row(
      children: opts.map((o) {
        final sel = selectedFoot == o.$1;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => selectedFoot = o.$1),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: sel ? neonGreen.withOpacity(0.15) : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: sel ? neonGreen : Colors.white.withOpacity(0.1),
                    width: 1.5),
              ),
              child: Column(children: [
                Icon(Icons.directions_run,
                    color: sel ? neonGreen : Colors.white54, size: 32),
                const SizedBox(height: 8),
                Text(AppLocalizations.get(o.$2),
                    style: ts.copyWith(
                        fontWeight: FontWeight.w700,
                        color: sel ? neonGreen : Colors.white)),
                Text(AppLocalizations.get(o.$3),
                    style: ts.copyWith(
                        fontSize: 10,
                        color: sel ? neonGreen : Colors.white54)),
                if (sel) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(
                        color: neonGreen, shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: Colors.black, size: 12),
                  ),
                ],
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Step 4: Training Profile ──────────────────────────────────────────────

  Widget _step4TrainingProfile(TextStyle ts, bool isSmall) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _ProfileRow(
        label: 'المستوى البدني',
        child: _SegmentPicker(
          options: const [
            ('beginner',     'مبتدئ'),
            ('intermediate', 'متوسط'),
            ('advanced',     'متقدم'),
            ('pro',          'محترف'),
          ],
          selected: fitnessLevel,
          color: neonGreen,
          ts: ts,
          onChanged: (v) => setState(() => fitnessLevel = v),
        ),
      ),
      const SizedBox(height: 16),
      _ProfileRow(
        label: 'مستوى كرة القدم',
        child: _SegmentPicker(
          options: const [
            ('beginner', 'مبتدئ'),
            ('amateur',  'هاوي'),
            ('semi_pro', 'شبه محترف'),
            ('pro',      'محترف'),
          ],
          selected: skillLevel,
          color: neonGreen,
          ts: ts,
          onChanged: (v) => setState(() => skillLevel = v),
        ),
      ),
      const SizedBox(height: 16),
      _ProfileRow(
        label: 'هدفك التدريبي',
        child: _SegmentPicker(
          options: const [
            ('improve_skills',    'تطوير المهارات'),
            ('fitness',           'اللياقة البدنية'),
            ('injury_prevention', 'الوقاية من الإصابات'),
            ('performance',       'الأداء التنافسي'),
          ],
          selected: trainingGoal,
          color: const Color(0xff8B5CF6),
          ts: ts,
          onChanged: (v) => setState(() => trainingGoal = v),
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: _ProfileRow(
            label: 'أيام في الأسبوع',
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.white54),
                onPressed: daysPerWeek > 1
                    ? () => setState(() => daysPerWeek--)
                    : null,
              ),
              Text('$daysPerWeek',
                  style: ts.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: neonGreen)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: Colors.white54),
                onPressed: daysPerWeek < 7
                    ? () => setState(() => daysPerWeek++)
                    : null,
              ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ProfileRow(
            label: 'مدة الجلسة (دقيقة)',
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.white54),
                onPressed: preferredMin > 15
                    ? () => setState(() => preferredMin -= 15)
                    : null,
              ),
              Text('$preferredMin',
                  style: ts.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: neonGreen)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: Colors.white54),
                onPressed: preferredMin < 180
                    ? () => setState(() => preferredMin += 15)
                    : null,
              ),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Text('قيود الإصابة (اختياري)',
          style: ts.copyWith(color: Colors.white54, fontSize: 13)),
      const SizedBox(height: 8),
      TextField(
        style: ts.copyWith(color: Colors.white, fontSize: 14),
        maxLines: 2,
        onChanged: (v) => setState(() => injuryNotes = v),
        decoration: InputDecoration(
          hintText: 'مثال: ألم في الركبة اليسرى...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.30)),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: neonGreen.withOpacity(0.6)),
          ),
        ),
      ),
    ]);
  }

  // ── Step 5: Weaknesses ────────────────────────────────────────────────────

  Widget _step5Weaknesses(TextStyle ts) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 1.2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: _weaknesses.map((w) {
        final sel = selectedWeaknesses.contains(w.$1);
        return GestureDetector(
          onTap: () => setState(() {
            if (sel) selectedWeaknesses.remove(w.$1);
            else selectedWeaknesses.add(w.$1);
          }),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sel
                  ? neonGreen.withOpacity(0.15)
                  : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: sel ? neonGreen : Colors.white.withOpacity(0.1)),
            ),
            child: Stack(children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(w.$3,
                      color: sel ? neonGreen : Colors.white54, size: 20),
                  const SizedBox(height: 6),
                  Flexible(
                    child: Text(w.$2,
                        style: ts.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: sel ? neonGreen : Colors.white)),
                  ),
                ],
              ),
              if (sel)
                Positioned(
                  top: 4, right: 4,
                  child: Container(
                    width: 18, height: 18,
                    decoration: const BoxDecoration(
                        color: neonGreen, shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: Colors.black, size: 10),
                  ),
                ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _GenderBtn extends StatelessWidget {
  const _GenderBtn({
    required this.label, required this.value, required this.selected,
    required this.ts, required this.onTap,
  });
  final String label, value; final bool selected;
  final TextStyle ts; final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFF7B638); // gold
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.14) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? accent : Colors.white.withOpacity(0.1),
                width: 1.5),
          ),
          child: Center(
            child: Text(label,
                style: ts.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: selected ? accent : Colors.white70)),
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.child});
  final String label; final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
              fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      child,
    ]);
  }
}

class _SegmentPicker extends StatelessWidget {
  const _SegmentPicker({
    required this.options, required this.selected, required this.color,
    required this.ts, required this.onChanged,
  });
  final List<(String, String)> options;
  final String selected; final Color color;
  final TextStyle ts; final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: options.map((o) {
        final sel = selected == o.$1;
        return GestureDetector(
          onTap: () => onChanged(o.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? color.withOpacity(0.14) : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: sel ? color : Colors.white.withOpacity(0.1)),
            ),
            child: Text(o.$2,
                style: ts.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: sel ? color : Colors.white54)),
          ),
        );
      }).toList(),
    );
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1.2;
    final cx = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(
        Rect.fromLTWH(size.width * .1, size.height * .05,
            size.width * .8, size.height * .9),
        paint);
    canvas.drawLine(Offset(cx.dx, size.height * .05),
        Offset(cx.dx, size.height * .95), paint);
    canvas.drawCircle(cx, size.width * .15, paint);
    canvas.drawCircle(cx, 2, paint);
  }

  @override
  bool shouldRepaint(_PitchPainter _) => false;
}
