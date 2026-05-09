import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../models/plan_model.dart';
import '../services/firebase_service.dart';
import '../widgets/common_widgets.dart';

class WeeklyPlanScreen extends StatelessWidget {
  const WeeklyPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My AI Plan'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: FirebaseService().streamLatestPlan(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('No plan found. Generate one in settings.', style: TextStyle(color: AppColors.muted)));
          }

          final plan = AIPlan.fromJson(snapshot.data!);
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: plan.days.length,
            itemBuilder: (context, i) {
              final day = plan.days[i];
              return SoftCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${day.dayName} - ${day.title}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    Text('${day.durationMinutes} mins', style: const TextStyle(color: AppColors.primary)),
                    const SizedBox(height: 12),
                    ...day.drills.map((drill) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(drill.name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text('${drill.durationMinutes} mins', style: const TextStyle(color: AppColors.muted)),
                          trailing: const Icon(Icons.play_circle_fill, color: AppColors.primary),
                          onTap: () {
                            Navigator.of(context).pushNamed('/capture?drill=${drill.id}&plan=${plan.id}');
                          },
                        )),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}