import 'package:flutter/material.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import 'club_dashboard.dart';

class SessionListPage extends StatefulWidget {
  const SessionListPage({Key? key}) : super(key: key);

  @override
  State<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage> {
  late DateTime _loadStart;

  @override
  void initState() {
    super.initState();
    _loadStart = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final start = _loadStart;
    return ClubShell(
      currentIndex: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Training Sessions'),
          elevation: 0,
        ),
        body: StreamBuilder<List<TrainingSession>>(
          stream: ClubService().sessionsStream(),
          builder: (context, snapshot) {
            // Show loading skeleton immediately while data arrives
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading sessions...',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              );
            }

            // Handle Firestore errors
            if (snapshot.hasError) {
              debugPrint('[Sessions] Stream error: ${snapshot.error}');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading sessions',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final sessions = snapshot.data ?? [];

            if (sessions.isEmpty) {
              final ms = DateTime.now().difference(start).inMilliseconds;
              debugPrint('[Sessions] No sessions found in ${ms}ms');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No sessions yet',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the button below to create one',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            final ms = DateTime.now().difference(start).inMilliseconds;
            debugPrint('[Sessions] Loaded ${sessions.length} sessions in ${ms}ms');

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length,
              itemBuilder: (context, index) => _SessionCard(
                session: sessions[index],
                onTap: () => Navigator.of(context).pushNamed('/club/sessions/${sessions[index].id}'),
              ),
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.of(context).pushNamed('/club/sessions/new'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final TrainingSession session;
  final VoidCallback onTap;

  const _SessionCard({
    required this.session,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = session.playerIds.isEmpty
        ? 0.0
        : session.completedPlayerIds.length / session.playerIds.length;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${session.date.day}/${session.date.month}/${session.date.year} • ${session.teamName ?? 'N/A'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      session.type.label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Progress',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                            ),
                            Text(
                              '${session.completedPlayerIds.length}/${session.playerIds.length}',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progress == 1.0 ? Colors.green : const Color(0xFFCC0A00),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
