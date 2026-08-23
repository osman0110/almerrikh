import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../services/firebase_service.dart';
import '../widgets/common_widgets.dart';

class AIOnboardingPage extends StatefulWidget {
  const AIOnboardingPage({super.key});

  @override
  State<AIOnboardingPage> createState() => _AIOnboardingPageState();
}

class _AIOnboardingPageState extends State<AIOnboardingPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isGenerating = false;

  // Collected Data
  String _trainingPath = '';
  double _age = 22;
  double _height = 175;
  double _weight = 70;
  String _gender = 'Male';
  String _fitnessLevel = 'Beginner';
  String _trainingGoal = 'Improve skills';
  double _daysPerWeek = 3;
  double _duration = 30;
  String _injury = 'None';
  String _playerPosition = 'Midfielder';
  String _dominantFoot = 'Right';
  String _skillLevel = 'Amateur';

  void _nextStep() {
    if (_currentStep == 0 && _trainingPath.isEmpty) return;
    
    if (_currentStep == 3 || (_currentStep == 2 && _trainingPath == 'fitness_only')) {
      _generatePlan();
    } else {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentStep++);
    }
  }

  Future<void> _generatePlan() async {
    setState(() => _isGenerating = true);
    try {
      await FirebaseService().saveProfileAndGeneratePlan({
        'trainingPath': _trainingPath,
        'age': _age.toInt(),
        'height': _height.toInt(),
        'weight': _weight.toInt(),
        'gender': _gender,
        'fitnessLevel': _fitnessLevel,
        'trainingGoal': _trainingGoal,
        'daysPerWeek': _daysPerWeek.toInt(),
        'preferredTrainingDuration': _duration.toInt(),
        'injuryLimitations': _injury,
        if (_trainingPath != 'fitness_only') 'playerPosition': _playerPosition,
        if (_trainingPath != 'fitness_only') 'dominantFoot': _dominantFoot,
        if (_trainingPath != 'fitness_only') 'footballSkillLevel': _skillLevel,
      });
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isGenerating) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 24),
              Text('Creating your AI training plan...', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: RoundedProgress(value: (_currentStep + 1) / 4, dark: true),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildPathSelection(),
                  _buildBasicInfo(),
                  _buildPreferences(),
                  _buildFootballDetails(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: PrimaryButton(
                label: 'Next',
                onTap: _nextStep,
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildPathSelection() {
    return _StepContainer(
      title: 'Choose your path',
      child: Column(
        children: [
          _ChoiceCard(label: 'Football Only', selected: _trainingPath == 'football_only', onTap: () => setState(() => _trainingPath = 'football_only')),
          _ChoiceCard(label: 'Fitness Only', selected: _trainingPath == 'fitness_only', onTap: () => setState(() => _trainingPath = 'fitness_only')),
          _ChoiceCard(label: 'Football + Fitness', selected: _trainingPath == 'football_fitness', onTap: () => setState(() => _trainingPath = 'football_fitness')),
        ],
      ),
    );
  }

  Widget _buildBasicInfo() {
    return _StepContainer(
      title: 'About You',
      child: Column(
        children: [
          _SliderInput(label: 'Age: ${_age.toInt()}', value: _age, min: 10, max: 60, onChanged: (v) => setState(() => _age = v)),
          _SliderInput(label: 'Height: ${_height.toInt()} cm', value: _height, min: 120, max: 220, onChanged: (v) => setState(() => _height = v)),
          _SliderInput(label: 'Weight: ${_weight.toInt()} kg', value: _weight, min: 30, max: 150, onChanged: (v) => setState(() => _weight = v)),
        ],
      ),
    );
  }

  Widget _buildPreferences() {
    return _StepContainer(
      title: 'Training Preferences',
      child: Column(
        children: [
          _SliderInput(label: 'Days per week: ${_daysPerWeek.toInt()}', value: _daysPerWeek, min: 1, max: 7, onChanged: (v) => setState(() => _daysPerWeek = v)),
          _SliderInput(label: 'Session Duration: ${_duration.toInt()} min', value: _duration, min: 10, max: 90, onChanged: (v) => setState(() => _duration = v)),
          TextField(
            onChanged: (v) => _injury = v,
            decoration: const InputDecoration(labelText: 'Injuries/Limitations (Optional)', filled: true, fillColor: AppColors.surface2),
            style: const TextStyle(color: Colors.white),
          )
        ],
      ),
    );
  }

  Widget _buildFootballDetails() {
    return _StepContainer(
      title: 'Football Profile',
      child: Column(
        children: [
          _ChoiceCard(label: 'Right Footed', selected: _dominantFoot == 'Right', onTap: () => setState(() => _dominantFoot = 'Right')),
          _ChoiceCard(label: 'Left Footed', selected: _dominantFoot == 'Left', onTap: () => setState(() => _dominantFoot = 'Left')),
        ],
      ),
    );
  }
}

class _StepContainer extends StatelessWidget {
  const _StepContainer({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.2) : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : Colors.transparent),
        ),
        child: Center(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
      ),
    );
  }
}

class _SliderInput extends StatelessWidget {
  const _SliderInput({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
        Slider(value: value, min: min, max: max, activeColor: AppColors.primary, onChanged: onChanged),
      ],
    );
  }
}