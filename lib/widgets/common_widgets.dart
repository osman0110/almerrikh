import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_localizations.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.width,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          elevation: 8,
          shadowColor: AppColors.primary.withOpacity(0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22),
              const SizedBox(width: 8),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.border,
    this.icon,
    this.small = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final IconData? icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 9 : 12,
        vertical: small ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: border != null ? Border.all(color: border!) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: small ? 12 : 15, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w900,
              fontSize: small ? 10 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

class RoundedProgress extends StatelessWidget {
  const RoundedProgress({
    super.key,
    required this.value,
    this.dark = false,
    this.height = 8,
  });

  final double value;
  final bool dark;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: height,
        backgroundColor: dark
            ? Colors.white.withOpacity(0.10)
            : AppColors.surface2,
        valueColor: const AlwaysStoppedAnimation(AppColors.primary),
      ),
    );
  }
}

class AvatarCircle extends StatelessWidget {
  const AvatarCircle({super.key, required this.size, required this.iconSize});

  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.hero2,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primary.withOpacity(0.68),
          width: size > 80 ? 4 : 2,
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.35), blurRadius: 24),
        ],
      ),
      child: Icon(Icons.person_rounded, color: Colors.white70, size: iconSize),
    );
  }
}

class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x09000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SoftCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class RoundIconButton extends StatelessWidget {
  const RoundIconButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.38),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

class DarkMetric extends StatelessWidget {
  const DarkMetric({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primaryGlow, size: 18),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.55),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    this.soft,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final Color? soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: soft ?? color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color == AppColors.primary
                        ? AppColors.primary
                        : AppColors.foreground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.muted,
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  RingPainter(this.value, {this.color = AppColors.primary});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - 3;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color.withOpacity(0.15);
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3
      ..color = color;
    canvas.drawCircle(center, radius, base);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value.clamp(0, 1),
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

class ScoreRingPainter extends CustomPainter {
  ScoreRingPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 14;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = Colors.white.withOpacity(0.10);
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10
      ..color = AppColors.primary;
    canvas.drawCircle(center, radius, base);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant ScoreRingPainter oldDelegate) =>
      oldDelegate.value != value;
}

class BigProgressRing extends CustomPainter {
  BigProgressRing(this.value, this.color);
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 10;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white.withOpacity(0.22);
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4
      ..color = color;
    canvas.drawCircle(center, radius, base);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant BigProgressRing oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}

class ThirdsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height * 2 / 3),
      Offset(size.width, size.height * 2 / 3),
      paint,
    );
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 2 / 3, 0),
      Offset(size.width * 2 / 3, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TiltPainter extends CustomPainter {
  TiltPainter({required this.tilt, required this.ok});

  final double tilt;
  final bool ok;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.18);
    canvas.drawCircle(center, 34, base);

    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(0.55);
    for (final deg in [-30, -15, 0, 15, 30]) {
      final angle = (deg - 90) * math.pi / 180;
      final p1 = center + Offset(math.cos(angle), math.sin(angle)) * 30;
      final p2 =
          center +
          Offset(math.cos(angle), math.sin(angle)) * (deg == 0 ? 23 : 26);
      tickPaint.color = deg == 0
          ? AppColors.accentGreen
          : Colors.white.withOpacity(0.55);
      tickPaint.strokeWidth = deg == 0 ? 2 : 1.2;
      canvas.drawLine(p1, p2, tickPaint);
    }

    final horizon = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.6
      ..color = ok ? AppColors.accentGreen : AppColors.warning;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(tilt * math.pi / 180);
    canvas.drawLine(const Offset(-28, 0), const Offset(28, 0), horizon);
    canvas.restore();
    canvas.drawCircle(
      center,
      3,
      Paint()..color = ok ? AppColors.accentGreen : AppColors.warning,
    );
  }

  @override
  bool shouldRepaint(covariant TiltPainter oldDelegate) =>
      oldDelegate.tilt != tilt || oldDelegate.ok != ok;
}

class AreaChartPainter extends CustomPainter {
  final data = const [4.0, 12, 24, 31, 28, 33, 22, 14];

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    const bottom = 22.0;
    final chart = Rect.fromLTWH(
      left,
      6,
      size.width - left - 6,
      size.height - bottom - 10,
    );
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    final maxV = data.reduce(math.max);
    final points = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final x = chart.left + chart.width * i / (data.length - 1);
      final y = chart.bottom - (data[i] / maxV) * chart.height;
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    final fill = Path.from(path)
      ..lineTo(points.last.dx, chart.bottom)
      ..lineTo(points.first.dx, chart.bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withOpacity(0.45),
            AppColors.primary.withOpacity(0),
          ],
        ).createShader(chart),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BarChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bars = [
      (AppLocalizations.get('angle_hip'), 102.0),
      (AppLocalizations.get('angle_knee'), 118.0),
      (AppLocalizations.get('angle_ankle'), 96.0),
      (AppLocalizations.get('angle_spine'), 12.0),
    ];
    const left = 28.0;
    const bottom = 26.0;
    final chart = Rect.fromLTWH(
      left,
      6,
      size.width - left - 6,
      size.height - bottom - 8,
    );
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = chart.top + chart.height * i / 3;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), gridPaint);
    }
    final maxV = bars.map((b) => b.$2).reduce(math.max);
    final gap = 16.0;
    final width = (chart.width - gap * (bars.length + 1)) / bars.length;
    final labelPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    for (var i = 0; i < bars.length; i++) {
      final leftX = chart.left + gap + i * (width + gap);
      final h = (bars[i].$2 / maxV) * chart.height;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(leftX, chart.bottom - h, width, h),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
      );
      canvas.drawRRect(rect, Paint()..color = AppColors.primary);
      labelPainter.text = TextSpan(
        text: bars[i].$1,
        style: const TextStyle(color: AppColors.muted, fontSize: 11),
      );
      labelPainter.layout(maxWidth: width + 12);
      labelPainter.paint(
        canvas,
        Offset(leftX + width / 2 - labelPainter.width / 2, chart.bottom + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
