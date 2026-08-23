import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_localizations.dart';
import '../widgets/common_widgets.dart';
import '../services/firebase_service.dart';

class OnboardingFlowPage extends StatefulWidget {
  const OnboardingFlowPage({super.key});

  @override
  State<OnboardingFlowPage> createState() => _OnboardingFlowPageState();
}

class _OnboardingFlowPageState extends State<OnboardingFlowPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isGenerating = false;

  // User Data State
  String _path = '';
  double _age = 22;
  double _height = 175;
  double _weight = 70;
  String _gender = '';
  String _fitnessLevel = '';
  String _skillLevel = '';
  String _goal = '';
  double _daysPerWeek = 3;
  double _duration = 30;
  String _injury = 'None';
  String _position = '';
  String _foot = '';

  void _nextPage() {
    // Skip Football Info page if path is "Fitness Only"
    if (_currentPage == 2 && _path == 'fitness') {
      _submitAndGeneratePlan();
      return;
    }
    
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _submitAndGeneratePlan();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _submitAndGeneratePlan() async {
    setState(() => _isGenerating = true);
    
    try {
      final payload = {
        'trainingPath': _path,
        'age': _age.toInt(),
        'height': _height,
        'weight': _weight,
        'gender': _gender,
        'fitnessLevel': _fitnessLevel,
        'footballSkillLevel': _path != 'fitness' ? _skillLevel : null,
        'trainingGoal': _goal,
        'daysPerWeek': _daysPerWeek.toInt(),
        'preferredTrainingDuration': _duration.toInt(),
        'injuryLimitations': _injury.isEmpty ? 'None' : _injury,
        'playerPosition': _path != 'fitness' ? _position : null,
        'dominantFoot': _path != 'fitness' ? _foot : null,
      };
      
      await FirebaseService().saveProfileAndGeneratePlan(payload);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate AI plan: $e')));
      }
    }
    
    if (!mounted) return;
    // Navigate to Home
    Navigator.of(context).pushReplacementNamed('/home');
  }

  bool get _canProceed {
    switch (_currentPage) {
      case 0: return _path.isNotEmpty;
      case 1: return _gender.isNotEmpty;
      case 2: return _fitnessLevel.isNotEmpty && _goal.isNotEmpty;
      case 3: return _skillLevel.isNotEmpty && _position.isNotEmpty && _foot.isNotEmpty;
      default: return true;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isGenerating) return _buildGeneratingScreen();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                children: [
                  _buildPathSelection(),
                  _buildBasicInfo(),
                  _buildGoalsAndFitness(),
                  _buildFootballSpecific(),
                ],
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          if (_currentPage > 0)
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
              onPressed: _previousPage,
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: RoundedProgress(
              value: (_currentPage + 1) / (_path == 'fitness' ? 3 : 4),
              dark: true,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: PrimaryButton(
        label: _currentPage == 3 || (_currentPage == 2 && _path == 'fitness')
            ? AppLocalizations.get('finish_btn')
            : AppLocalizations.get('next_btn'),
        onTap: _canProceed ? _nextPage : () {},
      ),
    );
  }

  // Step 1
  Widget _buildPathSelection() {
    return _FadeInStep(
      title: AppLocalizations.get('ob_path_title'),
      child: Column(
        children: [
          _SelectableCard(
            icon: Icons.sports_soccer_rounded,
            title: AppLocalizations.get('ob_path_football'),
            subtitle: 'Skill drills, ball control, and passing',
            isSelected: _path == 'football',
            onTap: () => setState(() => _path = 'football'),
          ),
          const SizedBox(height: 16),
          _SelectableCard(
            icon: Icons.fitness_center_rounded,
            title: AppLocalizations.get('ob_path_fitness'),
            subtitle: 'Stamina, speed, and agility training',
            isSelected: _path == 'fitness',
            onTap: () => setState(() => _path = 'fitness'),
          ),
          const SizedBox(height: 16),
          _SelectableCard(
            icon: Icons.bolt_rounded,
            title: AppLocalizations.get('ob_path_both'),
            subtitle: 'Complete AI-generated hybrid plan',
            isSelected: _path == 'both',
            onTap: () => setState(() => _path = 'both'),
          ),
        ],
      ),
    );
  }

  // Step 2
  Widget _buildBasicInfo() {
    return _FadeInStep(
      title: AppLocalizations.get('ob_basic_title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSlider(AppLocalizations.get('age'), _age, 10, 60, (v) => setState(() => _age = v), suffix: ' yrs'),
          _buildSlider(AppLocalizations.get('ob_height'), _height, 120, 220, (v) => setState(() => _height = v), suffix: ' cm'),
          _buildSlider(AppLocalizations.get('ob_weight'), _weight, 30, 150, (v) => setState(() => _weight = v), suffix: ' kg'),
          const SizedBox(height: 24),
          Text(AppLocalizations.get('ob_gender'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              _ChoiceChip(label: 'Male', isSelected: _gender == 'Male', onTap: () => setState(() => _gender = 'Male')),
              const SizedBox(width: 12),
              _ChoiceChip(label: 'Female', isSelected: _gender == 'Female', onTap: () => setState(() => _gender = 'Female')),
            ],
          ),
        ],
      ),
    );
  }

  // Step 3
  Widget _buildGoalsAndFitness() {
    return _FadeInStep(
      title: AppLocalizations.get('ob_goals_title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.get('ob_fitness_level'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: ['Beginner', 'Intermediate', 'Advanced'].map((level) => _ChoiceChip(
              label: level,
              isSelected: _fitnessLevel == level,
              onTap: () => setState(() => _fitnessLevel = level),
            )).toList(),
          ),
          const SizedBox(height: 24),
          Text(AppLocalizations.get('ob_goal'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: ['Lose Weight', 'Build Muscle', 'Increase Speed', 'Stamina', 'General Health'].map((goal) => _ChoiceChip(
              label: goal,
              isSelected: _goal == goal,
              onTap: () => setState(() => _goal = goal),
            )).toList(),
          ),
          const SizedBox(height: 24),
          _buildSlider(AppLocalizations.get('ob_days_week'), _daysPerWeek, 1, 7, (v) => setState(() => _daysPerWeek = v), suffix: ' days', divisions: 6),
          _buildSlider(AppLocalizations.get('ob_duration'), _duration, 15, 120, (v) => setState(() => _duration = v), suffix: ' min', divisions: 7),
        ],
      ),
    );
  }

  // Step 4
  Widget _buildFootballSpecific() {
    return _FadeInStep(
      title: AppLocalizations.get('ob_football_title'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.get('ob_skill_level'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: ['Amateur', 'Semi-Pro', 'Pro'].map((level) => _ChoiceChip(
              label: level,
              isSelected: _skillLevel == level,
              onTap: () => setState(() => _skillLevel = level),
            )).toList(),
          ),
          const SizedBox(height: 24),
          Text(AppLocalizations.get('profile_step2'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)), // Position
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: ['Forward', 'Midfielder', 'Defender', 'Goalkeeper'].map((pos) => _ChoiceChip(
              label: pos,
              isSelected: _position == pos,
              onTap: () => setState(() => _position = pos),
            )).toList(),
          ),
          const SizedBox(height: 24),
          Text(AppLocalizations.get('profile_step3'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)), // Foot
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: ['Left', 'Right', 'Both'].map((foot) => _ChoiceChip(
              label: foot,
              isSelected: _foot == foot,
              onTap: () => setState(() => _foot = foot),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80, height: 80,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 6,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              AppLocalizations.get('ob_generating'),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Text(
              'Mixing your stats, goals, and training data...',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, {String suffix = '', int? divisions}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              Text('${value.toInt()}$suffix', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppColors.primary,
            inactiveColor: Colors.white12,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({required this.label, required this.isSelected, required this.onTap});
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _SelectableCard extends StatelessWidget {
  const _SelectableCard({required this.icon, required this.title, required this.subtitle, required this.isSelected, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppColors.primary : Colors.white12, width: 2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white10,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isSelected ? Colors.black : Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FadeInStep extends StatelessWidget {
  const _FadeInStep({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 32),
          child,
        ],
      ),
    );
  }
}
