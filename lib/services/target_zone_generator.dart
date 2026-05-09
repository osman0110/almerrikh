import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Generates target positions that are visually inside the player's reachable
/// area, based on the current normalised body bounding box.
///
/// Safe margins prevent targets from appearing:
/// - too close to the screen edges (avoid UI controls)
/// - below the player's waist (unreachable for hand reaction)
/// - in the extreme corners
class TargetZoneGenerator {
  TargetZoneGenerator() : _rng = math.Random();

  static const double _marginH  = 0.06;  // left/right screen edge margin
  static const double _marginTop = 0.10;  // top screen edge margin
  static const double _marginBot = 0.16;  // bottom margin (avoids Exit button)
  static const double _minGap   = 0.18;  // minimum distance from last target

  final math.Random _rng;
  Offset? _last;

  /// Returns a new target centre in normalised [0,1]×[0,1] screen space.
  ///
  /// [bodyBox] is the player's normalised bounding box (already in screen coords).
  /// If [bodyBox] is null or implausible, falls back to a generic upper-body zone.
  Offset next(Rect? bodyBox) {
    // Determine the reachable zone from the player's body.
    final zone = _reachableZone(bodyBox);

    // Keep trying until we get a point far enough from the last target
    // (avoids boring consecutive hits in the same spot).
    for (int attempt = 0; attempt < 20; attempt++) {
      final candidate = Offset(
        zone.left + _rng.nextDouble() * zone.width,
        zone.top  + _rng.nextDouble() * zone.height,
      );
      if (_last == null || (candidate - _last!).distance >= _minGap) {
        _last = candidate;
        return candidate;
      }
    }
    // Fallback: just use the zone centre with a small random offset.
    final fb = zone.center + Offset(
      (_rng.nextDouble() - 0.5) * zone.width * 0.5,
      (_rng.nextDouble() - 0.5) * zone.height * 0.5,
    );
    _last = fb;
    return fb;
  }

  void reset() => _last = null;

  // ── Private ────────────────────────────────────────────────────────────

  Rect _reachableZone(Rect? body) {
    if (body == null || body.isEmpty || body.height < 0.15) {
      // No body data — use a conservative upper-body band.
      return const Rect.fromLTRB(0.15, 0.15, 0.85, 0.62);
    }

    // Horizontal reach: arm span ≈ 1.5× shoulder-to-shoulder width.
    // We use the full body box width as a proxy (body box typically spans
    // shoulder width). Allow ±1.0× that on each side, clamped to margins.
    final reachHalf = (body.width * 1.2).clamp(0.22, 0.45);
    final cx = body.center.dx.clamp(0.5 - reachHalf * 0.5, 0.5 + reachHalf * 0.5);

    final xMin = (cx - reachHalf).clamp(_marginH, 0.50);
    final xMax = (cx + reachHalf).clamp(0.50, 1.0 - _marginH);

    // Vertical reach: target from head (~top of box) to ≈70% down the body
    // (roughly chest/belly level — avoid forcing the player to crouch).
    final yMin = (body.top + body.height * 0.00).clamp(_marginTop, 0.45);
    final yMax = (body.top + body.height * 0.68).clamp(yMin + 0.10, 1.0 - _marginBot);

    return Rect.fromLTRB(
      xMin.clamp(0.0, 1.0),
      yMin.clamp(0.0, 1.0),
      xMax.clamp(0.0, 1.0),
      yMax.clamp(0.0, 1.0),
    );
  }
}
