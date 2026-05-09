import 'package:flutter/material.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';

class SessionFormPage extends StatefulWidget {
  final String? sessionId;

  const SessionFormPage({Key? key, this.sessionId}) : super(key: key);

  @override
  State<SessionFormPage> createState() => _SessionFormPageState();
}

class _SessionFormPageState extends State<SessionFormPage> {
  late TextEditingController _nameController;
  late TextEditingController _locationController;
  late TextEditingController _notesController;

  DateTime _selectedDate = DateTime.now();
  String? _selectedTeamId;
  SessionType _selectedType = SessionType.physicalAssessment;
  Set<String> _selectedPlayerIds = {};

  List<ClubTeam> _teams = [];
  List<ClubPlayer> _teamPlayers = [];
  TrainingSession? _existingSession;

  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _locationController = TextEditingController();
    _notesController = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final teams = await ClubService().getTeams();
      if (!mounted) return;
      setState(() => _teams = teams);

      if (widget.sessionId != null) {
        final session = await ClubService().getSession(widget.sessionId!);
        if (!mounted) return;
        if (session != null) {
          _existingSession = session;
          _nameController.text = session.name;
          _locationController.text = session.location ?? '';
          _notesController.text = session.notes ?? '';
          _selectedDate = session.date;
          _selectedTeamId = session.teamId;
          _selectedType = session.type;
          _selectedPlayerIds = Set.from(session.playerIds);
          await _loadTeamPlayers(session.teamId);
          if (!mounted) return;
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTeamPlayers(String teamId) async {
    final players = await ClubService().getPlayers(teamId: teamId);
    setState(() => _teamPlayers = players);
  }

  Future<void> _saveSession() async {
    if (_nameController.text.isEmpty || _selectedTeamId == null || _selectedPlayerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields and select at least one player')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final session = TrainingSession(
        id: widget.sessionId ?? '',
        name: _nameController.text.trim(),
        date: _selectedDate,
        teamId: _selectedTeamId!,
        teamName: _teams.firstWhere((t) => t.id == _selectedTeamId).name,
        type: _selectedType,
        location: _locationController.text.trim(),
        coachName: 'Coach',
        notes: _notesController.text.trim(),
        playerIds: _selectedPlayerIds.toList(),
        completedPlayerIds: _existingSession?.completedPlayerIds ?? [],
        createdAt: _existingSession?.createdAt ?? DateTime.now(),
      );

      bool success;
      if (widget.sessionId != null) {
        success = await ClubService().updateSession(session);
      } else {
        final id = await ClubService().addSession(session);
        success = id != null;
      }

      if (mounted) {
        if (success) {
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save session')),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionId == null ? 'New Session' : 'Edit Session'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Session Name',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.edit),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    title: const Text('Date'),
                    subtitle: Text(
                      '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedTeamId,
                    decoration: InputDecoration(
                      labelText: 'Team',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: _teams.map((team) {
                      return DropdownMenuItem(
                        value: team.id,
                        child: Text(team.name),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      if (value != null) {
                        setState(() {
                          _selectedTeamId = value;
                          _selectedPlayerIds.clear();
                        });
                        await _loadTeamPlayers(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<SessionType>(
                    value: _selectedType,
                    decoration: InputDecoration(
                      labelText: 'Session Type',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: SessionType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedType = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _locationController,
                    decoration: InputDecoration(
                      labelText: 'Location (Optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.location_on),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'Notes (Optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.note),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Select Players (${_selectedPlayerIds.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (_teamPlayers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'No players in this team',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                      ),
                    )
                  else
                    ..._teamPlayers.map((player) {
                      final isSelected = _selectedPlayerIds.contains(player.id);
                      return Card(
                        child: CheckboxListTile(
                          value: isSelected,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedPlayerIds.add(player.id);
                              } else {
                                _selectedPlayerIds.remove(player.id);
                              }
                            });
                          },
                          title: Text(player.fullName),
                          subtitle: Text('${player.number} • ${player.position}'),
                        ),
                      );
                    }).toList(),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveSession,
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Session'),
                  ),
                ],
              ),
            ),
    );
  }
}
