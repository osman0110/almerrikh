import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../utils/app_logger.dart';
import 'package:image_picker/image_picker.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';

class AddEditPlayerPage extends StatefulWidget {
  const AddEditPlayerPage({super.key, this.player, this.teams = const []});
  final ClubPlayer? player;
  final List<ClubTeam> teams;
  @override
  State<AddEditPlayerPage> createState() => _AddEditPlayerPageState();
}

class _AddEditPlayerPageState extends State<AddEditPlayerPage> {
  final _name        = TextEditingController();
  final _nameAr      = TextEditingController();
  final _nameEn      = TextEditingController();
  final _nickname    = TextEditingController();
  final _number      = TextEditingController();
  final _position    = TextEditingController();
  final _height      = TextEditingController();
  final _weight      = TextEditingController();
  final _natl        = TextEditingController();
  final _injNotes    = TextEditingController();
  final _physNotes   = TextEditingController();
  final _medNotes    = TextEditingController();
  final _unavailNote = TextEditingController();
  final _email       = TextEditingController();
  final _password    = TextEditingController();
  bool _createLogin  = false;
  bool _obscurePassword = true;

  PlayerStatus _status = PlayerStatus.active;
  String _foot = 'right';
  DateTime? _dob;
  DateTime? _expectedReturn;
  bool _saving = false;
  XFile? _pickedImage;
  Uint8List? _pickedImageBytes;
  String? _photoUrl;
  List<ClubTeam> _teams = [];
  String? _selectedTeamId;
  bool _teamsLoading = true;
  final Set<String> _selectedPositions = <String>{};

  static const _positions = [
    'Goalkeeper','Centre-Back','Right-Back','Left-Back',
    'Defensive Mid','Central Mid','Attacking Mid',
    'Right Wing','Left Wing','Striker',
  ];

  bool get _isEdit => widget.player != null;
  bool get _alreadyHasLogin => _isEdit && (widget.player?.hasLogin ?? false);

  void _loadSelectedPositions(String value) {
    _selectedPositions
      ..clear()
      ..addAll(value
          .split(',')
          .map((position) => position.trim())
          .where(_positions.contains));
  }

  void _togglePosition(String position) {
    setState(() {
      if (_selectedPositions.contains(position)) {
        _selectedPositions.remove(position);
      } else {
        _selectedPositions.add(position);
      }
      _position.text = _positions
          .where(_selectedPositions.contains)
          .join(', ');
    });
  }

  // Explicit date-picker theme — the app's ambient ColorScheme.fromSeed(seedColor:
  // AppColors.maroon) leaves `surfaceTint` unset here, which Material 3 defaults to a
  // clashing purple tone and applies as an elevation overlay on the dialog surface,
  // muddying the white calendar background. Pin every role explicitly instead of
  // relying on ColorScheme derivation.
  Widget _datePickerTheme(BuildContext ctx, Widget? child) {
    final base = Theme.of(ctx);
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.foreground,
          surface: AppColors.card,
          onSurface: AppColors.foreground,
          surfaceTint: AppColors.card,
          onSurfaceVariant: AppColors.muted,
          outline: AppColors.border,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: AppColors.card,
          surfaceTintColor: Colors.transparent,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: AppColors.card,
          surfaceTintColor: Colors.transparent,
          headerBackgroundColor: AppColors.primary,
          headerForegroundColor: AppColors.foreground,
          weekdayStyle: const TextStyle(
              color: AppColors.muted, fontWeight: FontWeight.w600),
          dayForegroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.foreground
                  : AppColors.foreground),
          dayBackgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : Colors.transparent),
          todayForegroundColor:
              const WidgetStatePropertyAll(AppColors.primary),
          todayBorder: const BorderSide(color: AppColors.primary, width: 1.2),
          yearForegroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.foreground
                  : AppColors.foreground),
          yearBackgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : Colors.transparent),
        ),
      ),
      child: child!,
    );
  }

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = widget.player!;
      _photoUrl        = p.profileImageUrl;
      _name.text      = p.fullName;
      _nameAr.text    = p.nameArabic;
      _nameEn.text    = p.nameEnglish;
      _nickname.text  = p.nickname ?? '';
      _number.text    = p.number;
      _position.text  = p.position;
      _loadSelectedPositions(p.position);
      _height.text    = p.height?.toString() ?? '';
      _weight.text    = p.weight?.toString() ?? '';
      _natl.text      = p.nationality;
      _injNotes.text  = p.injuryNotes ?? '';
      _physNotes.text = p.physicalNotes ?? '';
      _medNotes.text  = p.medicalNotes ?? '';
      _status          = p.status;
      _foot            = p.dominantFoot;
      _dob             = p.dateOfBirth;
      _expectedReturn  = p.expectedReturnDate;
      _unavailNote.text = p.unavailableReason ?? '';
    }
    _loadTeams();
  }

  @override
  void dispose() {
    for (final c in [_name,_nameAr,_nameEn,_nickname,_number,_position,_height,_weight,_natl,_injNotes,_physNotes,_medNotes,_unavailNote,_email,_password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 600,
      maxHeight: 800,
    );
    if (file != null) {
      // Check file size (if available)
      final fileSize = await file.length();
      const maxSizeBytes = 5 * 1024 * 1024; // 5 MB
      if (fileSize > maxSizeBytes) {
        _snack(AppLocalizations.get('image_too_large'));
        return;
      }
      setState(() => _pickedImage = file);
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _pickedImageBytes = bytes);
    }
  }

  Future<void> _loadTeams() async {
    final loaded = widget.teams.isNotEmpty
        ? widget.teams
        : await ClubService().getTeams();
    if (!mounted) return;

    final unique = <String, ClubTeam>{
      for (final team in loaded) team.id: team,
    }.values.toList();
    final player = widget.player;
    String? selectedId;
    if (player != null) {
      for (final team in unique) {
        if (team.id == player.teamId ||
            team.name == player.teamName ||
            team.name == player.teamId) {
          selectedId = team.id;
          break;
        }
      }
    }
    if (selectedId == null && currentTeamId.isNotEmpty) {
      for (final team in unique) {
        if (team.id == currentTeamId || team.name == currentTeamName) {
          selectedId = team.id;
          break;
        }
      }
    }
    selectedId ??= unique.isNotEmpty ? unique.first.id : null;

    setState(() {
      _teams = unique;
      _selectedTeamId = selectedId;
      _teamsLoading = false;
    });
  }

  ClubTeam? get _selectedTeam {
    for (final team in _teams) {
      if (team.id == _selectedTeamId) return team;
    }
    return null;
  }

  bool _validateInputs() {
    if (_name.text.trim().isEmpty) {
      _snack(AppLocalizations.get('player_name_required'));
      return false;
    }
    if (_teams.isNotEmpty && _selectedTeam == null) {
      _snack(AppLocalizations.get('select_team_required'));
      return false;
    }

    // Validate height if provided
    if (_height.text.isNotEmpty) {
      final h = double.tryParse(_height.text);
      if (h == null || h < 80 || h > 230) {
        _snack(AppLocalizations.get('height_invalid'));
        return false;
      }
    }

    // Validate weight if provided
    if (_weight.text.isNotEmpty) {
      final w = double.tryParse(_weight.text);
      if (w == null || w < 20 || w > 200) {
        _snack(AppLocalizations.get('weight_invalid'));
        return false;
      }
    }

    if (_createLogin) {
      final email = _email.text.trim();
      final emailOk = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
      if (!emailOk) {
        _snack(AppLocalizations.get('email_invalid'));
        return false;
      }
      if (_password.text.length < 6) {
        _snack(AppLocalizations.get('password_too_short'));
        return false;
      }
    }

    return true;
  }

  Future<void> _save() async {
    if (!_validateInputs()) return;

    final selectedTeam = _selectedTeam;
    final teamId = selectedTeam?.id ??
        widget.player?.teamId ??
        (currentTeamId.isNotEmpty ? currentTeamId : 'general');
    final teamName = selectedTeam?.name ??
        widget.player?.teamName ??
        (currentTeamName.isNotEmpty ? currentTeamName : null);

    setState(() => _saving = true);
    try {
      // Upload photo if selected — bytes-based so it works on Web and native.
      if (_pickedImageBytes != null) {
        final filename = _pickedImage?.name ?? 'photo.jpg';
        final uploaded = await ClubService().uploadPlayerPhotoBytes(
          _pickedImageBytes!,
          filename: filename,
        );
        if (uploaded != null) {
          _photoUrl = uploaded;
        } else {
          _snack(AppLocalizations.get('photo_upload_failed'));
          // Continue saving the player even if photo upload fails.
        }
      }

      if (_isEdit) {
        final p = widget.player!;
        p.profileImageUrl = _photoUrl;
        p.fullName      = _name.text.trim();
        p.nameArabic    = _nameAr.text.trim();
        p.nameEnglish   = _nameEn.text.trim();
        p.nickname      = _nickname.text.trim().isEmpty
            ? null
            : _nickname.text.trim();
        p.number        = _number.text.trim();
        p.position      = _position.text.trim();
        p.height        = double.tryParse(_height.text);
        p.weight        = double.tryParse(_weight.text);
        p.nationality   = _natl.text.trim();
        p.injuryNotes         = _injNotes.text.trim().isEmpty ? null : _injNotes.text.trim();
        p.physicalNotes       = _physNotes.text.trim().isEmpty ? null : _physNotes.text.trim();
        p.medicalNotes        = _medNotes.text.trim().isEmpty ? null : _medNotes.text.trim();
        p.status              = _status;
        p.dominantFoot        = _foot;
        p.dateOfBirth         = _dob;
        p.expectedReturnDate  = _expectedReturn;
        p.unavailableReason   = _unavailNote.text.trim().isEmpty ? null : _unavailNote.text.trim();
        p.teamId              = teamId;
        p.teamName            = teamName;
        final result = await ClubService().updatePlayer(
          p,
          email: _createLogin ? _email.text.trim() : null,
          password: _createLogin ? _password.text : null,
        );
        if (!mounted) return;
        final ok = result['success'] == true;
        _snack(ok
            ? AppLocalizations.get('player_updated')
            : (result['error'] as String? ?? AppLocalizations.get('player_update_failed')));
        if (ok && mounted) Navigator.of(context).pop(true);
      } else {
        final player = ClubPlayer(
          id: '', fullName: _name.text.trim(), number: _number.text.trim(),
          nameArabic: _nameAr.text.trim(),
          nameEnglish: _nameEn.text.trim(),
          nickname: _nickname.text.trim().isEmpty
              ? null
              : _nickname.text.trim(),
          position: _position.text.trim(), dateOfBirth: _dob,
          height: double.tryParse(_height.text), weight: double.tryParse(_weight.text),
          dominantFoot: _foot, teamId: teamId, teamName: teamName,
          nationality: _natl.text.trim(),
          profileImageUrl: _photoUrl,
          injuryNotes:    _injNotes.text.trim().isEmpty ? null : _injNotes.text.trim(),
          physicalNotes:  _physNotes.text.trim().isEmpty ? null : _physNotes.text.trim(),
          medicalNotes:   _medNotes.text.trim().isEmpty ? null : _medNotes.text.trim(),
          status: _status,
          expectedReturnDate: _expectedReturn,
          unavailableReason:  _unavailNote.text.trim().isEmpty ? null : _unavailNote.text.trim(),
          createdAt: DateTime.now(),
        );
        final result = await ClubService().addPlayer(
          player,
          email: _createLogin ? _email.text.trim() : null,
          password: _createLogin ? _password.text : null,
        );
        if (!mounted) return;
        final id = result['id'] as String?;
        if (id != null) {
          _snack(AppLocalizations.get('player_added'));
          Navigator.of(context).pop(true);
        } else {
          final err = result['error'] as String?;
          _snack(err ?? AppLocalizations.get('player_add_failed'));
        }
      }
    } catch (e) {
      AppLogger.e('AddPlayer', 'Save failed', e);
      if (mounted) _snack('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget _field(TextEditingController ctrl, String label, String hint,
      {TextInputType? kb, int maxLines = 1, TextDirection? textDirection}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: AppColors.muted,
                fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          keyboardType: kb,
          maxLines: maxLines,
          textDirection: textDirection,
          textAlign: textDirection == null
              ? TextAlign.start
              : (textDirection == TextDirection.rtl
                  ? TextAlign.right
                  : TextAlign.left),
          style: const TextStyle(color: AppColors.foreground, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
            filled: true, fillColor: AppColors.surface2,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _teamPicker() {
    if (_teamsLoading) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (_teams.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: AppColors.warning,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.get('no_teams_found'),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final safeValue = _teams.any((team) => team.id == _selectedTeamId)
        ? _selectedTeamId
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.get('player_team_label'),
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeValue,
              isExpanded: true,
              dropdownColor: AppColors.card,
              hint: Text(
                AppLocalizations.get('select_team_required'),
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                ),
              ),
              items: [
                for (final team in _teams)
                  DropdownMenuItem<String>(
                    value: team.id,
                    child: Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _selectedTeamId = value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(children: [
      Container(width: 3, height: 14,
          decoration: BoxDecoration(
              color: AppColors.primary, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(t, style: const TextStyle(
          color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              decoration: const BoxDecoration(
                color: AppColors.card,
                border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surface2, shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border)),
                      child: const Icon(Icons.close_rounded,
                          color: AppColors.foreground, size: 18),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _isEdit
                          ? AppLocalizations.get('edit_player')
                          : AppLocalizations.get('new_player'),
                      style: const TextStyle(color: AppColors.foreground,
                          fontWeight: FontWeight.w900, fontSize: 18)),
                  ),
                ],
              ),
            ),
            // Form
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Photo picker ─────────────────────────────────────────
                  Center(
                    child: GestureDetector(
                      onTap: _pickPhoto,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 88, height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surface2,
                              border: Border.all(color: AppColors.primary, width: 2),
                            ),
                            child: ClipOval(
                              child: _pickedImageBytes != null
                                  ? Image.memory(_pickedImageBytes!, fit: BoxFit.cover)
                                  : _photoUrl != null && _photoUrl!.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: _photoUrl!,
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => const SizedBox.shrink(),
                                          errorWidget: (_, __, ___) => const Icon(
                                              Icons.person_rounded, color: AppColors.muted, size: 36))
                                      : const Icon(Icons.person_rounded, color: AppColors.muted, size: 36),
                            ),
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.primary, shape: BoxShape.circle,
                                border: Border.all(color: AppColors.background, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt_rounded, color: AppColors.background, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(AppLocalizations.get('basic_information')),
                  _field(_name, AppLocalizations.get('full_name_label'),
                      AppLocalizations.get('full_name_hint')),
                  const SizedBox(height: 14),
                  _field(
                    _nameAr,
                    AppLocalizations.get('player_name_ar_label'),
                    AppLocalizations.get('player_name_ar_hint'),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    _nameEn,
                    AppLocalizations.get('player_name_en_label'),
                    AppLocalizations.get('player_name_en_hint'),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    _nickname,
                    AppLocalizations.get('player_nickname_label'),
                    AppLocalizations.get('player_nickname_hint'),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _field(_number,
                        AppLocalizations.get('jersey_number'), '10',
                        kb: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dob ?? DateTime(2000),
                            firstDate: DateTime(1970),
                            lastDate: DateTime.now(),
                            builder: _datePickerTheme,
                          );
                          if (picked != null) setState(() => _dob = picked);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppLocalizations.get('date_of_birth'),
                                style: TextStyle(
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w700, fontSize: 12)),
                            const SizedBox(height: 8),
                            Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(children: [
                                const Icon(Icons.cake_rounded,
                                    color: AppColors.muted, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  _dob == null
                                      ? AppLocalizations.get('pick_date')
                                      : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                                  style: TextStyle(
                                    color: _dob == null
                                        ? AppColors.muted
                                        : AppColors.foreground,
                                    fontSize: 14,
                                  ),
                                ),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  // Position chips
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.get('player_position_label'),
                          style: TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8, runSpacing: 8,
                        children: _positions.map((pos) {
                          final active = _selectedPositions.contains(pos);
                          return GestureDetector(
                            onTap: () => _togglePosition(pos),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: active ? AppColors.primary : AppColors.surface2,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: active ? AppColors.primary : AppColors.border),
                              ),
                              child: Text(AppLocalizations.positionLabel(pos),
                                  style: TextStyle(
                                    color: active ? AppColors.foreground : AppColors.muted,
                                    fontWeight: FontWeight.w700, fontSize: 12,
                                  )),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _field(_natl, AppLocalizations.get('nationality_label'), 'Sudan'),
                  const SizedBox(height: 20),
                  _sectionLabel(AppLocalizations.get('physical_data')),
                  Row(children: [
                    Expanded(child: _field(_height,
                        AppLocalizations.get('player_height_label'), '182',
                        kb: TextInputType.number)),
                    const SizedBox(width: 12),
                    Expanded(child: _field(_weight,
                        AppLocalizations.get('player_weight_label'), '75',
                        kb: TextInputType.number)),
                  ]),
                  const SizedBox(height: 14),
                  // Dominant foot
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.get('player_dominant_foot_label'),
                          style: TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 8),
                      Row(
                        children: ['right', 'left', 'both'].map((f) {
                          final active = _foot == f;
                          final label = f == 'right'
                              ? AppLocalizations.get('right_foot')
                              : f == 'left'
                                  ? AppLocalizations.get('left_foot')
                                  : AppLocalizations.get('both_feet');
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _foot = f),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: active ? AppColors.primary : AppColors.surface2,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: active ? AppColors.primary : AppColors.border),
                                ),
                                child: Text(label,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: active ? AppColors.foreground : AppColors.muted,
                                      fontWeight: FontWeight.w800, fontSize: 13,
                                    )),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel(AppLocalizations.get('assignment_label')),
                  _teamPicker(),
                  const SizedBox(height: 14),
                  // Status dropdown
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.get('status_label'),
                          style: TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w700, fontSize: 12)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButton<PlayerStatus>(
                          value: _status,
                          isExpanded: true,
                          dropdownColor: AppColors.card,
                          underline: const SizedBox(),
                          style: const TextStyle(
                              color: AppColors.foreground, fontSize: 14),
                          items: PlayerStatus.values.map((s) =>
                              DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                          onChanged: (v) => setState(() => _status = v!),
                        ),
                      ),
                    ],
                  ),
                  // ── Return date + unavailable reason (conditional) ──────────
                  if (_status == PlayerStatus.injured ||
                      _status == PlayerStatus.recovering ||
                      _status == PlayerStatus.suspended ||
                      _status == PlayerStatus.inactive) ...[
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _expectedReturn ??
                              DateTime.now().add(const Duration(days: 14)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          builder: _datePickerTheme,
                        );
                        if (picked != null) setState(() => _expectedReturn = picked);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.get('expected_return_date'),
                              style: const TextStyle(
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12)),
                          const SizedBox(height: 8),
                          Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(children: [
                              const Icon(Icons.event_rounded,
                                  color: AppColors.muted, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _expectedReturn == null
                                    ? AppLocalizations.get('pick_date_optional')
                                    : '${_expectedReturn!.day}/${_expectedReturn!.month}/${_expectedReturn!.year}',
                                style: TextStyle(
                                  color: _expectedReturn == null
                                      ? AppColors.muted
                                      : AppColors.foreground,
                                  fontSize: 14,
                                ),
                              ),
                              if (_expectedReturn != null) ...[
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => setState(() => _expectedReturn = null),
                                  child: const Icon(Icons.close_rounded,
                                      color: AppColors.muted, size: 16),
                                ),
                              ],
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_status == PlayerStatus.suspended ||
                      _status == PlayerStatus.inactive) ...[
                    const SizedBox(height: 14),
                    _field(_unavailNote, AppLocalizations.get('absence_reason_label'), AppLocalizations.get('absence_reason_hint'), maxLines: 2),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel(AppLocalizations.get('medical_notes_section')),
                  _field(_injNotes,
                      AppLocalizations.get('player_injury_notes_label'),
                      AppLocalizations.get('injury_notes_hint'), maxLines: 3),
                  const SizedBox(height: 14),
                  _field(_physNotes,
                      AppLocalizations.get('physical_notes_label'),
                      AppLocalizations.get('physical_notes_hint'), maxLines: 3),
                  const SizedBox(height: 14),
                  _field(_medNotes,
                      AppLocalizations.get('medical_restrictions_label'),
                      AppLocalizations.get('medical_restrictions_hint'),
                      maxLines: 3),
                  const SizedBox(height: 20),
                  _sectionLabel(AppLocalizations.get('player_login_section')),
                  if (_alreadyHasLogin)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppLocalizations.get('player_login_already_linked'),
                              style: const TextStyle(
                                  color: AppColors.foreground,
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    GestureDetector(
                      onTap: () => setState(() => _createLogin = !_createLogin),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.login_rounded,
                                color: _createLogin ? AppColors.primary : AppColors.muted,
                                size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                AppLocalizations.get('player_login_toggle'),
                                style: const TextStyle(
                                    color: AppColors.foreground,
                                    fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                            ),
                            Switch(
                              value: _createLogin,
                              activeColor: AppColors.primary,
                              onChanged: (v) => setState(() => _createLogin = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_createLogin) ...[
                      const SizedBox(height: 14),
                      _field(_email, AppLocalizations.get('email_label'),
                          AppLocalizations.get('email_hint'),
                          kb: TextInputType.emailAddress),
                      const SizedBox(height: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.get('password_label'),
                              style: const TextStyle(color: AppColors.muted,
                                  fontWeight: FontWeight.w700, fontSize: 12)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _password,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: AppLocalizations.get('password_hint'),
                              hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
                              filled: true, fillColor: AppColors.surface2,
                              suffixIcon: IconButton(
                                icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: AppColors.muted, size: 20),
                                onPressed: () =>
                                    setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: AppColors.border)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: AppColors.border)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: const Border(top: BorderSide(color: AppColors.border, width: 0.8)),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 20, offset: const Offset(0, -6))],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _saving ? null : () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(999)),
                alignment: Alignment.center,
                child: Text(AppLocalizations.get('cancel'),
                    style: const TextStyle(color: AppColors.foreground,
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _saving || _teamsLoading ? null : _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.maroon,
                  borderRadius: BorderRadius.circular(999)),
                alignment: Alignment.center,
                child: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(AppLocalizations.get('save_btn'),
                        style: const TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
