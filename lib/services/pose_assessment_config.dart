/// Centralizes all configurable thresholds for pose-based assessments.
/// Use this instead of magic numbers scattered across screens and services.
class PoseAssessmentConfig {
  const PoseAssessmentConfig._();

  // ── Frame capture ──────────────────────────────────────────────────────────
  static const int targetFrameCount       = 90;
  static const int webTickIntervalMs      = 40; // ~25 fps synthetic tick
  static const int mobileFrameThrottleMs  = 33; // floor on inference cadence (~30fps max)

  // ── Landmark visibility ────────────────────────────────────────────────────
  static const double minLandmarkVisibility   = 0.30; // discard below this
  static const double minFrameConfidence      = 0.45; // frame validation gate
  static const int    minLandmarkCount        = 10;   // frame validation gate

  // ── Calibration streaks ────────────────────────────────────────────────────
  static const int readyStreakRequired    = 2;  // consecutive valid frames → go (squat flow)
  static const int cancelStreakRequired   = 8;  // sustained loss → cancel countdown
  static const int seriousStreakRequired  = 3;  // catastrophic loss → instant cancel

  // ── Jump-test READY gate (PoseQualityGate) ─────────────────────────────────
  static const int gateReadyConsecutiveRequired = 20;   // consecutive valid frames → ready
  static const int gateWindowSize               = 30;   // rolling rejection window
  static const double gateMaxRejectedRatio       = 0.30; // block READY above this ratio
  static const double gateMinLandmarkLikelihood  = 0.75; // required-joint likelihood floor
  static const double gateBodyHeightMin          = 0.55; // body box height ratio (too far below)
  static const double gateBodyHeightMax          = 0.85; // body box height ratio (too close above)
  static const double gateEdgeMargin             = 0.03; // head/feet must stay this far from edge
  static const double gateStabilityMaxDrift      = 0.02; // max mean inter-frame landmark drift
  // Weighted quality score (0-100: fullBody 25, feet 20, knees 15, hips 10,
  // head 10, stability 10, lighting 5, no-blur 5) must reach this to count
  // as a valid frame — the single source of truth for bodyFull/legQ/READY.
  static const double gateReadyQualityThreshold  = 80.0;
  static const Set<String> gateRequiredLandmarks = {
    'leftHip', 'rightHip',
    'leftKnee', 'rightKnee',
    'leftAnkle', 'rightAnkle',
    'leftHeel', 'rightHeel',
    'leftFootIndex', 'rightFootIndex',
  };

  // ── Calibration soft checks ───────────────────────────────────────────────
  static const double brightnessThreshold = 70.0; // Y-plane luminance [0,255]
  static const double tooCloseBoundH      = 0.85; // body height > this → too close
  static const double tooCloseBoundW      = 0.75;
  static const double tooFarBoundH        = 0.35; // body height < this → too far

  // ── EMA smoothing (squat tests only — jump tests use PoseSmoothingService) ─
  static const double emaAlphaLower  = 0.22; // hips/knees/ankles (heavy smoothing)
  static const double emaAlphaUpper  = 0.45; // shoulders/head (lighter smoothing)
  static const Set<String> lowerBodyKeys = {
    'leftHip', 'rightHip',
    'leftKnee', 'rightKnee',
    'leftAnkle', 'rightAnkle',
  };

  // ── One Euro smoothing (PoseSmoothingService — jump tests, mobile only) ────
  static const double oneEuroMinCutoff = 1.0;
  static const double oneEuroBeta      = 0.02;
  static const double oneEuroDCutoff   = 1.0;
  static const double smoothingMinLikelihood     = 0.50; // below this: not fed to filter
  static const int    smoothingHoldMaxFrames     = 3;    // hold last output this many frames
  static const double smoothingMaxJumpTorsoRatio = 0.12; // reject single-frame jumps above this

  // ── Squat assessment ──────────────────────────────────────────────────────
  static const double squat_standingKneeAngleMin = 155.0; // fully standing
  static const double squat_depthAngleThreshold  = 120.0; // sufficient depth
  static const double squat_poorDepthThreshold   = 140.0; // too shallow
  static const double squat_maxTrunkLean         = 35.0;  // critical lean
  static const double squat_warnTrunkLean        = 20.0;  // warn lean
  static const double squat_kneeValgusWarn       = 0.70;  // knee alignment score
  static const double squat_kneeValgusCritical   = 0.50;
  static const double squat_asymmetryWarn        = 12.0;  // degrees L/R diff
  static const double squat_varianceWarn         = 18.0;  // movement variance

  // ── Single leg balance ────────────────────────────────────────────────────
  static const double balance_minDurationSec     = 3.0;
  static const double balance_maxSwayThreshold   = 0.08;  // normalised units

  // ── Jump assessment ───────────────────────────────────────────────────────
  static const double jump_flightMinFrames       = 3.0;
  static const double jump_crouchDepthAngle      = 120.0;
  static const double jump_landingMaxAsymmetry   = 15.0;  // degrees

  // ── Jump state machine (JumpStateMachine — jump tests only) ────────────────
  static const int medianWindowFrames    = 5;   // median-of-N window for angles/hipY
  static const int stabilizingMinMs      = 700; // hold before freezing baseline
  static const int squatHoldMinMs        = 300; // SJ: static hold before takeoff check
  static const int takeoffConfirmFrames  = 2;   // consecutive frames to confirm takeoff
  static const int landingConfirmFrames  = 3;   // consecutive frames to confirm landing/completed
  static const int jumpInvalidGapMs      = 500; // tracking-loss gap mid-flight → invalid
  static const double jumpSquatEnterKneeAngle = 120.0; // knee angle to enter squatHold
  static const double jumpSquatExitKneeAngle  = 130.0; // knee angle to abandon squatHold

  // ── Web / performance ─────────────────────────────────────────────────────
  static const double lowFpsWarning  = 15.0; // warn below this FPS on web
  static const double minFpsForRep   = 10.0; // reject rep counting below this

  // ── Guide frame (screen-normalised rect where body should stand) ──────────
  // Must match ExerciseEngine.guideFrame
  static const double guideLeft   = 0.18;
  static const double guideTop    = 0.12;
  static const double guideRight  = 0.82; // left + 0.64
  static const double guideBottom = 0.88; // top + 0.76
  static const double insideGuideRatio = 0.60; // body must be ≥60% inside
}
