import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../models/player_profile_model.dart';
import '../../api_service.dart';
import '../../services/player_service.dart';
import '../../widgets/common_widgets.dart';

class PlayerProfileFormPage extends StatefulWidget {
  const PlayerProfileFormPage({super.key, this.player});

  final PlayerProfile? player;

  @override
  State<PlayerProfileFormPage> createState() => _PlayerProfileFormPageState();
}

class _PlayerProfileFormPageState extends State<PlayerProfileFormPage> {
  late final TextEditingController nameController;
  late final TextEditingController heightController;
  late final TextEditingController weightController;
  late final TextEditingController positionController;
  late final TextEditingController teamController;
  late final TextEditingController categoryController;
  late final TextEditingController dominantFootController;
  late final TextEditingController notesController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.player?.name ?? '');
    heightController = TextEditingController(text: widget.player?.heightCm?.toString() ?? '');
    weightController = TextEditingController(text: widget.player?.weightKg?.toString() ?? '');
    positionController = TextEditingController(text: widget.player?.position ?? '');
    teamController = TextEditingController(text: widget.player?.team ?? '');
    categoryController = TextEditingController(text: widget.player?.category ?? '');
    dominantFootController = TextEditingController(text: widget.player?.dominantFoot ?? '');
    notesController = TextEditingController(text: widget.player?.injuryNotes ?? '');
  }

  @override
  void dispose() {
    nameController.dispose();
    heightController.dispose();
    weightController.dispose();
    positionController.dispose();
    teamController.dispose();
    categoryController.dispose();
    dominantFootController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          widget.player == null
              ? AppLocalizations.get('assessment_add_player')
              : AppLocalizations.get('assessment_edit_player'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            _buildInput(label: AppLocalizations.get('player_name_label'), controller: nameController),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildInput(label: AppLocalizations.get('player_height_label'), controller: heightController, keyboardType: TextInputType.number)),
                const SizedBox(width: 12),
                Expanded(child: _buildInput(label: AppLocalizations.get('player_weight_label'), controller: weightController, keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 12),
            _buildInput(label: AppLocalizations.get('player_position_label'), controller: positionController),
            const SizedBox(height: 12),
            _buildInput(label: AppLocalizations.get('player_team_label'), controller: teamController),
            const SizedBox(height: 12),
            _buildInput(label: AppLocalizations.get('player_category_label'), controller: categoryController),
            const SizedBox(height: 12),
            _buildInput(label: AppLocalizations.get('player_dominant_foot_label'), controller: dominantFootController),
            const SizedBox(height: 12),
            _buildInput(label: AppLocalizations.get('player_injury_notes_label'), controller: notesController, maxLines: 4),
            const SizedBox(height: 20),
            PrimaryButton(
              label: AppLocalizations.get('save_btn'),
              onTap: _saveProfile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surface2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            hintText: label,
            hintStyle: const TextStyle(color: Colors.white38),
          ),
        ),
      ],
    );
  }

  Future<void> _saveProfile() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('player_name_required'))),
      );
      return;
    }

    if (ApiService.token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.get('assessment_auth_required'))),
      );
      return;
    }

    final profile = PlayerProfile(
      id: widget.player?.id ?? '',
      name: name,
      heightCm: int.tryParse(heightController.text.trim()),
      weightKg: int.tryParse(weightController.text.trim()),
      position: positionController.text.trim().isEmpty ? null : positionController.text.trim(),
      team: teamController.text.trim().isEmpty ? null : teamController.text.trim(),
      category: categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
      dominantFoot: dominantFootController.text.trim().isEmpty ? null : dominantFootController.text.trim(),
      injuryNotes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      photoUrl: widget.player?.photoUrl,
    );

    await PlayerService.instance.savePlayer(profile);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

