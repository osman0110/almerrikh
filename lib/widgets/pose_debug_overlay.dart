import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/exercise_engine.dart';
import '../services/pose_quality_gate.dart';

/// Developer-only overlay that shows real-time pose detection diagnostics.
/// Only renders when [kDebugMode] is true AND [enabled] is true.
/// Always compiles to nothing in release builds.
class PoseDebugOverlay extends StatelessWidget {
  const PoseDebugOverlay({
    super.key,
    required this.enabled,
    required this.snapshot,
    this.engineName,
    this.engineStatus,
    this.engineFps,
    this.engineError,
    this.inferenceMs,
    this.gateResult,
  });

  final bool          enabled;
  final PoseSnapshot? snapshot;
  final String?       engineName;
  final String?       engineStatus;
  final double?       engineFps;
  final String?       engineError;
  final double?       inferenceMs;

  /// When set (jump tests), the breakdown from [PoseQualityGate] REPLACES
  /// the raw confidence/bodyFull lines below — those legacy PoseSnapshot
  /// fields use a much looser definition than the gate and showing both at
  /// once is what produced contradictory readings like "bodyFull: true"
  /// next to "feet outside frame".
  final PoseGateResult? gateResult;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || !enabled) return const SizedBox.shrink();

    final snap = snapshot;
    return Positioned(
      bottom: 60,
      left: 8,
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.yellow,
          fontSize: 9.5,
          fontFamily: 'monospace',
          height: 1.4,
        ),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('── POSE DEBUG ──────────────────'),
              Text('platform : ${kIsWeb ? "web" : defaultTargetPlatform.name}'),
              Text('engine   : ${engineName ?? "–"}'),
              Text('status   : ${engineStatus ?? "–"}'),
              if (engineFps != null)
                Text('fps      : ${engineFps!.toStringAsFixed(1)}'),
              if (inferenceMs != null)
                Text('infer ms : ${inferenceMs!.toStringAsFixed(1)}'),
              if (engineError != null) ...[
                Text('error    : $engineError',
                    style: const TextStyle(color: Colors.redAccent)),
              ],
              if (snap != null) ...[
                const Text('──────────────────────────────'),
                Text('landmarks  : ${snap.landmarkCount}'),
                if (gateResult != null) ...[
                  // Jump tests: the gate's weighted score is the ONLY
                  // quality signal shown — no raw confidence/bodyFull next
                  // to it that could disagree with it.
                  Text('Overall Quality : ${gateResult!.qualityScore.round()}%',
                      style: TextStyle(
                        color: gateResult!.frameValid ? Colors.greenAccent : Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                      )),
                  Text('Upper Body : ${gateResult!.upperBodyQuality.round()}%'),
                  Text('Lower Body : ${gateResult!.lowerBodyQuality.round()}%'),
                  Text('Pose Stable  : ${gateResult!.poseStable ? "YES" : "NO"}'),
                  Text('Feet Visible : ${gateResult!.feetVisible ? "YES" : "NO"}'),
                  Text('Head Visible : ${gateResult!.headVisible ? "YES" : "NO"}'),
                  Text('Body Full    : ${gateResult!.bodyFull ? "YES" : "NO"}'),
                  Text('Body Scale   : ${gateResult!.bodyScalePercent.round()}%'),
                  Text('Streak/Ratio : ${gateResult!.readyStreak} / ${(gateResult!.rejectedRatio * 100).round()}%'),
                  if (gateResult!.failReason.isNotEmpty)
                    Text('Reason : ${gateResult!.failReason}',
                        style: const TextStyle(color: Colors.amber)),
                ] else ...[
                  Text('confidence : ${snap.confidence.toStringAsFixed(2)}'),
                  Text('bodyFull   : ${snap.bodyFullyVisible}'),
                  Text('headVis    : ${snap.headVisible}'),
                  Text('shoulderVis: ${snap.shouldersVisible}'),
                  Text('hipsVis    : ${snap.hipsVisible}'),
                  Text('lowerVis   : ${snap.lowerBodyVisible}'),
                  Text('inGuide    : ${snap.insideGuideFrame}'),
                  Text('tooClose   : ${snap.tooClose}'),
                  Text('tooFar     : ${snap.tooFar}'),
                ],
                if (snap.bodyBox != null)
                  Text('bodyBox    : ${_rect(snap.bodyBox!)}'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _rect(Rect r) =>
      'L${r.left.toStringAsFixed(2)} T${r.top.toStringAsFixed(2)}'
      ' W${r.width.toStringAsFixed(2)} H${r.height.toStringAsFixed(2)}';
}
