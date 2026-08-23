import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../app_localizations.dart';
import '../models/report_models.dart';

// ── Design tokens (shared across report screens) ─────────────────────────────
const _bg    = Color(0xFFFFFFFF);
const _lime  = Color(0xFF2DBF6C);
const _muted = Color(0xFF6F7368);
const _green = Color(0xff22C55E);
const _amber = Color(0xfff59e0b);
const _red   = Color(0xffef4444);

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        height: 120,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.show_chart_rounded, color: _muted, size: 28),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      );
}

// ── Hooper Line Chart ─────────────────────────────────────────────────────────

class HooperLineChart extends StatelessWidget {
  const HooperLineChart({super.key, required this.data, this.height = 140});
  final List<TrendPoint> data;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _EmptyChart(label: AppLocalizations.get('chart_empty_hooper'));
    final spots = List.generate(
      data.length,
      (i) => FlSpot(i.toDouble(), data[i].score.clamp(4, 28).toDouble()),
    );
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 4,
          maxY: 28,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: _lime,
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: _lime.withOpacity(0.08),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            show: true,
            bottomTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 7,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: const TextStyle(color: _muted, fontSize: 9)),
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 7,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.white.withOpacity(0.07), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

// ── RPE Line Chart (pre = dashed, post = solid) ───────────────────────────────

class RpeLineChart extends StatelessWidget {
  const RpeLineChart({super.key, required this.data, this.height = 140});
  final List<RpeTrendPoint> data;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _EmptyChart(label: AppLocalizations.get('chart_empty_rpe'));
    final preSpots = <FlSpot>[];
    final postSpots = <FlSpot>[];
    for (var i = 0; i < data.length; i++) {
      final p = data[i];
      if (p.preRpe != null)  preSpots.add(FlSpot(i.toDouble(), p.preRpe!.toDouble()));
      if (p.postRpe != null) postSpots.add(FlSpot(i.toDouble(), p.postRpe!.toDouble()));
    }
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 1,
          maxY: 10,
          lineBarsData: [
            if (postSpots.isNotEmpty)
              LineChartBarData(
                spots: postSpots,
                isCurved: true,
                color: _lime,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                    show: true, color: _lime.withOpacity(0.08)),
              ),
            if (preSpots.isNotEmpty)
              LineChartBarData(
                spots: preSpots,
                isCurved: true,
                color: _muted,
                barWidth: 1.5,
                dashArray: [4, 4],
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: false),
              ),
          ],
          titlesData: FlTitlesData(
            show: true,
            bottomTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 3,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: const TextStyle(color: _muted, fontSize: 9)),
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 3,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.white.withOpacity(0.07), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

// ── Assessment Score Line Chart ───────────────────────────────────────────────

class AssessmentScoreChart extends StatelessWidget {
  const AssessmentScoreChart({super.key, required this.data, this.height = 140});
  final List<FullAssessmentItem> data;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _EmptyChart(label: AppLocalizations.get('chart_empty_assessments'));
    final spots = List.generate(
      data.length,
      (i) => FlSpot(i.toDouble(), data[i].overallScore.toDouble()),
    );
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: _green,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                  radius: 3,
                  color: _green,
                  strokeWidth: 0,
                  strokeColor: Colors.transparent,
                ),
              ),
              belowBarData: BarAreaData(
                  show: true, color: _green.withOpacity(0.08)),
            ),
          ],
          titlesData: FlTitlesData(
            show: true,
            bottomTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 25,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: const TextStyle(color: _muted, fontSize: 9)),
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.white.withOpacity(0.07), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

// ── Weekly Load Bar Chart ─────────────────────────────────────────────────────

class WeeklyLoadBarChart extends StatelessWidget {
  const WeeklyLoadBarChart({super.key, required this.data, this.height = 120});
  final List<WeeklyLoadPoint> data;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _EmptyChart(label: AppLocalizations.get('chart_empty_load'));
    final maxVal = data
        .map((d) => d.totalLoad.toDouble())
        .fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxVal > 0 ? maxVal * 1.2 : 100.0;
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          barGroups: List.generate(
            data.length,
            (i) => BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].totalLoad.toDouble(),
                  color: _lime,
                  width: 12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= data.length) return const SizedBox();
                  final w = data[idx].week;
                  final label = w.length > 6 ? w.substring(w.length - 3) : w;
                  return Text(label,
                      style: const TextStyle(color: _muted, fontSize: 8));
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}

// ── Completion Rate Card ───────────────────────────────────────────────────────

class CompletionRateCard extends StatelessWidget {
  const CompletionRateCard({
    super.key,
    required this.completed,
    required this.assigned,
    required this.rate,
  });
  final int completed;
  final int assigned;
  final int rate;

  @override
  Widget build(BuildContext context) {
    final color = rate >= 70 ? _green : rate >= 40 ? _amber : _red;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$rate%',
                  style: TextStyle(
                      color: color,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      height: 1)),
              const SizedBox(width: 10),
              Text('معدل الإتمام',
                  style: TextStyle(
                      color: _muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: rate / 100,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 8),
          Text('$completed / $assigned جلسة',
              style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Score history chart (from AssessmentHistoryItem) ─────────────────────────

class AssessmentHistoryChart extends StatelessWidget {
  const AssessmentHistoryChart({super.key, required this.data, this.height = 120});
  final List<AssessmentHistoryItem> data;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return _EmptyChart(label: AppLocalizations.get('chart_empty_assessments'));
    final spots = List.generate(
      data.length,
      (i) => FlSpot(i.toDouble(), data[i].overallScore.toDouble()),
    );
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: _lime,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                  show: true, color: _lime.withOpacity(0.07)),
            ),
          ],
          titlesData: const FlTitlesData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 25,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}
