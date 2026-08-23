import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../app_colors.dart';
import '../../models/ai_plan_models.dart';
import 'ai_plan_preview_screen.dart';
import 'session_widgets.dart';

class IndependentAIPlanScreen extends StatefulWidget {
  const IndependentAIPlanScreen({super.key});

  @override
  State<IndependentAIPlanScreen> createState() =>
      _IndependentAIPlanScreenState();
}

class _IndependentAIPlanScreenState extends State<IndependentAIPlanScreen> {
  // ── Form state ──────────────────────────────────────────────────────────────
  String  _goal           = '';
  int     _availableDays  = 4;
  int     _duration       = 60;
  int     _numWeeks       = 4;
  String  _difficulty     = 'intermediate';
  final   _injuryCtrl     = TextEditingController();
  final   Set<String> _equipment = {'bodyweight', 'ball'};

  bool _generating = false;

  bool get _isValid => _goal.isNotEmpty;

  static const _goals = [
    ('speed',             Icons.bolt_rounded,              'Speed'),
    ('endurance',         Icons.favorite_rounded,          'Endurance'),
    ('strength',          Icons.fitness_center_rounded,    'Strength'),
    ('agility',           Icons.directions_run_rounded,    'Agility'),
    ('injury_prevention', Icons.health_and_safety_rounded, 'Injury Prevention'),
    ('recovery',          Icons.self_improvement_rounded,  'Recovery'),
    ('football_skill',    Icons.sports_soccer_rounded,     'Football Skills'),
  ];

  static const _equipmentOptions = [
    ('bodyweight',       'Bodyweight'),
    ('ball',             'Football'),
    ('cones',            'Cones'),
    ('gym',              'Gym'),
    ('resistance_bands', 'Bands'),
  ];

  static const _difficulties = [
    ('beginner',     'Beginner'),
    ('intermediate', 'Intermediate'),
    ('advanced',     'Advanced'),
  ];

  static const _durationOptions = [30, 45, 60, 75, 90];
  static const _weekOptions     = [2, 3, 4, 6, 8];

  @override
  void dispose() {
    _injuryCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!_isValid || _generating) return;

    setState(() => _generating = true);

    final req = AIPlanGenerateRequest(
      goal:                  _goal,
      availableDays:         _availableDays,
      preferredDuration:     _duration,
      numWeeks:              _numWeeks,
      equipment:             _equipment.toList(),
      difficultyPreference:  _difficulty,
      injuryLimitations:
          _injuryCtrl.text.trim().isEmpty ? null : _injuryCtrl.text.trim(),
    );

    final res = await ApiService.generateAIPlan(req);

    if (!mounted) return;
    setState(() => _generating = false);

    if (res.containsKey('error')) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['error'] as String),
        backgroundColor: AppColors.destructive,
        duration: const Duration(seconds: 5),
      ));
      return;
    }

    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => AIPlanPreviewScreen(
        planId:    res['plan_id'] as String,
        planTitle: res['plan_title'] as String? ?? 'My AI Plan',
      ),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.foreground.withOpacity(0.70), size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Generate AI Plan',
            style: TextStyle(
                color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 17)),
        centerTitle: false,
      ),
      body: _generating ? _buildLoading() : _buildForm(),
    );
  }

  // ── Loading state ──────────────────────────────────────────────────────────
  Widget _buildLoading() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
              width: 56, height: 56,
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            const Text('Generating your plan...',
                style: TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
            const SizedBox(height: 8),
            Text('Claude AI is building a personalised\n${_numWeeks}-week plan for you.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.50), fontSize: 13)),
            const SizedBox(height: 12),
            Text('This may take 15–30 seconds.',
                style: TextStyle(
                    color: AppColors.foreground.withOpacity(0.30), fontSize: 11)),
          ]),
        ),
      );

  // ── Form ───────────────────────────────────────────────────────────────────
  Widget _buildForm() => Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Promo banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.20),
                        AppColors.primary.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.25)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.auto_awesome_rounded,
                        color: AppColors.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('Powered by Claude AI',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                        Text(
                            'Personal plan based on your fitness level,'
                            ' body metrics, and monitoring data.',
                            style: TextStyle(
                                color: AppColors.foreground.withOpacity(0.50),
                                fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),

                // ── Goal ──────────────────────────────────────────────────
                _label('What is your goal? *'),
                const SizedBox(height: 12),
                _GoalSelector(
                  selected: _goal,
                  goals: _goals,
                  onChanged: (v) => setState(() => _goal = v),
                ),
                const SizedBox(height: 24),

                // ── Training days ──────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _label('Days per week'),
                    Text('$_availableDays days',
                        style: TextStyle(
                            color: AppColors.primary.withOpacity(0.80),
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 10),
                SessionNumberSelector(
                  value: _availableDays,
                  count: 7,
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => _availableDays = v),
                ),
                const SizedBox(height: 24),

                // ── Session duration ───────────────────────────────────────
                _label('Session duration'),
                const SizedBox(height: 10),
                _ChipRow(
                  options: _durationOptions
                      .map((d) => ('$d', '${d}min'))
                      .toList(),
                  selected: '$_duration',
                  onChanged: (v) => setState(() => _duration = int.parse(v)),
                ),
                const SizedBox(height: 24),

                // ── Number of weeks ────────────────────────────────────────
                _label('Plan duration'),
                const SizedBox(height: 10),
                _ChipRow(
                  options: _weekOptions
                      .map((w) => ('$w', '$w wks'))
                      .toList(),
                  selected: '$_numWeeks',
                  onChanged: (v) => setState(() => _numWeeks = int.parse(v)),
                ),
                const SizedBox(height: 24),

                // ── Equipment ──────────────────────────────────────────────
                _label('Available equipment'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _equipmentOptions.map((opt) {
                    final (key, label) = opt;
                    final sel = _equipment.contains(key);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (sel) _equipment.remove(key);
                        else _equipment.add(key);
                      }),
                      child: _chip(label, sel, AppColors.primary),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // ── Difficulty ─────────────────────────────────────────────
                _label('Current level'),
                const SizedBox(height: 10),
                Row(
                  children: _difficulties.map((opt) {
                    final (key, label) = opt;
                    final sel = _difficulty == key;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          onTap: () => setState(() => _difficulty = key),
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 11),
                            decoration: BoxDecoration(
                              color: sel
                                  ? AppColors.primary.withOpacity(0.18)
                                  : AppColors.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: sel ? 1.5 : 1,
                              ),
                            ),
                            child: Text(label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: sel
                                      ? AppColors.primary
                                      : AppColors.foreground.withOpacity(0.45),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                )),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // ── Injury limitations ─────────────────────────────────────
                _label('Injury limitations (optional)'),
                const SizedBox(height: 10),
                TextField(
                  controller: _injuryCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                  decoration: sessionInputDecoration(
                      'e.g. right knee pain, avoid running...'),
                ),
              ],
            ),
          ),
        ),

        // ── Generate button ─────────────────────────────────────────────────
        SessionSubmitBar(
          label: '✨  Generate My Plan',
          enabled: _isValid,
          loading: false,
          onTap: _generate,
        ),
      ]);

  static Widget _label(String t) => Text(t,
      style: const TextStyle(
          color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 14));

  static Widget _chip(String label, bool sel, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? color.withOpacity(0.18) : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: sel ? color : AppColors.border,
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: sel ? color : AppColors.foreground.withOpacity(0.50),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            )),
      );
}

// ── Goal selector grid ────────────────────────────────────────────────────────

class _GoalSelector extends StatelessWidget {
  const _GoalSelector({
    required this.selected,
    required this.goals,
    required this.onChanged,
  });
  final String selected;
  final List<(String, IconData, String)> goals;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.1,
        ),
        itemCount: goals.length,
        itemBuilder: (_, i) {
          final (key, icon, label) = goals[i];
          final sel = selected == key;
          return GestureDetector(
            onTap: () => onChanged(key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: sel
                    ? AppColors.primary.withOpacity(0.18)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sel
                      ? AppColors.primary
                      : AppColors.border,
                  width: sel ? 1.5 : 1,
                ),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(icon,
                    color: sel
                        ? AppColors.primary
                        : AppColors.foreground.withOpacity(0.40),
                    size: 26),
                const SizedBox(height: 6),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: sel
                          ? AppColors.primary
                          : AppColors.foreground.withOpacity(0.50),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    )),
              ]),
            ),
          );
        },
      );
}

// ── Horizontal chip row ───────────────────────────────────────────────────────

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: options.map((opt) {
          final (key, label) = opt;
          final sel = selected == key;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () => onChanged(key),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppColors.primary.withOpacity(0.18)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel
                          ? AppColors.primary
                          : AppColors.border,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: sel
                            ? AppColors.primary
                            : AppColors.foreground.withOpacity(0.50),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      )),
                ),
              ),
            ),
          );
        }).toList(),
      );
}
