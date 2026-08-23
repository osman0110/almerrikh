import 'package:flutter/material.dart';

import 'rpe_screen.dart';

/// The guided-session flow reuses the RPE screen and enables its post-session
/// completion fields. Hooper remains a separate pre-session workflow.
class PostTrainingFeedbackScreen extends StatelessWidget {
  const PostTrainingFeedbackScreen({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return RpeScreen(
      sessionId: data['session_id']?.toString(),
      sessionTitle: data['session_title']?.toString(),
      durationMinutes: (data['duration_minutes'] as num?)?.round(),
      hooperScore: (data['hooper_score'] as num?)?.round(),
      preRpe: (data['pre_rpe'] as num?)?.round(),
      completeSession: true,
    );
  }
}
