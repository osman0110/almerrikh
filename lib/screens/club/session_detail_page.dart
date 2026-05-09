import 'package:flutter/material.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';

class SessionDetailPage extends StatefulWidget {
  final String sessionId;

  const SessionDetailPage({Key? key, required this.sessionId}) : super(key: key);

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  TrainingSession? _session;
  Map<String, ClubPlayer> _players = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final session = await ClubService().getSession(widget.sessionId);
      if (session == null) return;

      final players = <String, ClubPlayer>{};
      for (final playerId in session.playerIds) {
        final player = await ClubService().getPlayer(playerId);
        if (player != null) {
          players[playerId] = player;
        }
      }

      setState(() {
        _session = session;
        _players = players;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Details'),
        elevation: 0,
      ),
      body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _session == null
                ? const Center(child: Text('Session not found'))
                : StreamBuilder<TrainingSession?>(
                    stream: ClubService().sessionsStream().map((sessions) {
                      try {
                        return sessions.firstWhere((s) => s.id == widget.sessionId);
                      } catch (e) {
                        return null;
                      }
                    }),
                    builder: (context, snapshot) {
                      final session = snapshot.data ?? _session!;

                      final progress = session.playerIds.isEmpty
                          ? 0.0
                          : session.completedPlayerIds.length / session.playerIds.length;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      session.name,
                                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${session.date.day}/${session.date.month}/${session.date.year}',
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(Icons.group, size: 16, color: Colors.grey[600]),
                                        const SizedBox(width: 8),
                                        Text(
                                          session.teamName ?? 'N/A',
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(Icons.sports_soccer, size: 16, color: Colors.grey[600]),
                                        const SizedBox(width: 8),
                                        Text(
                                          session.type.label,
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Progress',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Players Completed',
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: progress == 1.0 ? Colors.green : const Color(0xFFCC0A00),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Text(
                                            '${session.completedPlayerIds.length}/${session.playerIds.length}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 12,
                                        backgroundColor: Colors.grey[300],
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          progress == 1.0 ? Colors.green : const Color(0xFFCC0A00),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Players',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            ..._buildPlayerList(session),
                          ],
                        ),
                      );
                    },
                  ),
    );
  }

  List<Widget> _buildPlayerList(TrainingSession session) {
    return session.playerIds.map((playerId) {
      final player = _players[playerId];
      if (player == null) return const SizedBox.shrink();

      final isCompleted = session.completedPlayerIds.contains(playerId);

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[300],
                child: Text(player.initials),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.fullName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '${player.number} • ${player.position}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'Completed',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed(
                      '/club/assessment/camera',
                      arguments: {
                        'playerId': playerId,
                        'sessionId': widget.sessionId,
                        'sessionName': _session!.name,
                      },
                    );
                  },
                  icon: const Icon(Icons.videocam, size: 18),
                  label: const Text('Start'),
                )
            ],
          ),
        ),
      );
    }).toList();
  }
}
