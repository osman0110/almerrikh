import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../services/exercise_engine.dart';

class OverlayRenderer extends StatelessWidget {
  const OverlayRenderer({
    super.key,
    required this.state,
    required this.type,
    required this.showTarget,
    required this.showGuides,
  });

  final ExerciseFrameState state;
  final ExerciseType type;
  final bool showTarget;
  final bool showGuides;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _OverlayPainter(
            state: state,
            type: type,
            showTarget: showTarget,
            showGuides: showGuides,
          ),
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.state,
    required this.type,
    required this.showTarget,
    required this.showGuides,
  });

  final ExerciseFrameState state;
  final ExerciseType type;
  final bool showTarget;
  final bool showGuides;

  @override
  void paint(Canvas canvas, Size size) {
    if (showGuides) _paintGuides(canvas, size);
    if (!showTarget) return;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.primary;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.primary.withOpacity(0.20);

    if (type == ExerciseType.getInTheBox) {
      final rect = Rect.fromLTWH(
        state.targetRect.left * size.width,
        state.targetRect.top * size.height,
        state.targetRect.width * size.width,
        state.targetRect.height * size.height,
      );
      final target = RRect.fromRectAndRadius(rect, const Radius.circular(18));
      canvas.drawRRect(target, fill);
      canvas.drawRRect(target, stroke);
      return;
    }

    final target = state.targetCircle;
    if (target == null) return;
    final center = Offset(target.center.dx * size.width, target.center.dy * size.height);
    final radius = target.radius * size.shortestSide;
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius, stroke);
  }

  void _paintGuides(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(0.72);
    final marginX = size.width * 0.12;
    final marginY = size.height * 0.16;
    final length = size.shortestSide * 0.12;
    final points = [
      Offset(marginX, marginY),
      Offset(size.width - marginX, marginY),
      Offset(marginX, size.height - marginY),
      Offset(size.width - marginX, size.height - marginY),
    ];

    for (final point in points) {
      final sx = point.dx < size.width / 2 ? 1.0 : -1.0;
      final sy = point.dy < size.height / 2 ? 1.0 : -1.0;
      canvas.drawLine(point, point + Offset(length * sx, 0), paint);
      canvas.drawLine(point, point + Offset(0, length * sy), paint);
    }

    final frame = ExerciseEngine.guideFrame;
    final rect = Rect.fromLTWH(
      frame.left * size.width,
      frame.top * size.height,
      frame.width * size.width,
      frame.height * size.height,
    );
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withOpacity(0.88);
    final frameFill = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withOpacity(0.04);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    canvas.drawRRect(rrect, frameFill);
    canvas.drawRRect(rrect, framePaint);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => true;
}
