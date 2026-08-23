import 'package:flutter/widgets.dart';

/// No capture video exists on web (see AssessmentVideoService).
class AssessmentFramePlayer extends StatelessWidget {
  const AssessmentFramePlayer({super.key, required this.framePaths});
  final List<String> framePaths;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
