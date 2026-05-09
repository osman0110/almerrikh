import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_colors.dart';
import '../data/mock_data.dart';
import '../models/drill_result_model.dart';
import '../services/camera_service.dart';
import '../services/firebase_service.dart';
import '../services/exercise_engine.dart';
import '../services/hand_reaction_engine.dart';
import '../services/pose_service.dart';
import '../services/sound_manager.dart';
import '../widgets/common_widgets.dart';

const bool showPoseDebug = kDebugMode;

enum ExerciseScreenState {
  initializingCamera,
  cameraReady,
  searchingBody,
  partialBody,
  tooClose,
  tooFar,
  offCenter,
  poorLight,
  readyToStart,
  countdown,
  training,
  completed,
  error,
  handsNotVisible,
}

class ExerciseStateInfo {
  const ExerciseStateInfo({
    required this.title,
    required this.subtitle,
    required this.instruction,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final String instruction;
  final IconData icon;
  final Color color;
}

class ExerciseStateMachine {
  ExerciseStateInfo info(ExerciseScreenState state) {
    const neonGreen = Color(0xff39ff14);
    return switch (state) {
      ExerciseScreenState.initializingCamera => const ExerciseStateInfo(
          title: 'نجهز الكاميرا...',
          subtitle: 'ثبت الموبايل بالعرض',
          instruction: 'انتظر لحظة حتى تفتح الكاميرا',
          icon: Icons.videocam_rounded,
          color: Colors.white70,
        ),
      ExerciseScreenState.cameraReady || ExerciseScreenState.searchingBody =>
        const ExerciseStateInfo(
          title: 'البحث عن الجسم r    ...',
          subtitle: 'قف داخل الإطار الأخضر',
          instruction: 'ما شايفك، قف أمام الكاميرا',
          icon: Icons.radar_rounded,
          color: Colors.white,
        ),
      ExerciseScreenState.partialBody => const ExerciseStateInfo(
          title: 'جزء من الجسم  ظاهر    ',
          subtitle: 'نحتاج نشوف جسمك كامل',
          instruction: 'ارجع للخلف حتى تظهر القدمين',
          icon: Icons.accessibility_new_rounded,
          color: Colors.white,
        ),
      ExerciseScreenState.tooClose => const ExerciseStateInfo(
          title: 'أنت قريب جدًا',
          subtitle: 'الجسم كبير داخل الإطار',
          instruction: 'ارجع خطوتين للخلف',
          icon: Icons.zoom_out_map_rounded,
          color: Colors.white,
        ),
      ExerciseScreenState.tooFar => const ExerciseStateInfo(
          title: 'أنت بعيد جدًا',
          subtitle: 'الجسم صغير داخل الإطار',
          instruction: 'اقترب قليلًا',
          icon: Icons.zoom_in_rounded,
          color: Colors.white,
        ),
      ExerciseScreenState.offCenter => const ExerciseStateInfo(
          title: 'جسمك خارج الإطار',
          subtitle: 'خليك في المنتصف',
          instruction: 'تحرك إلى منتصف الإطار',
          icon: Icons.center_focus_strong_rounded,
          color: Colors.white,
        ),
      ExerciseScreenState.poorLight => const ExerciseStateInfo(
          title: 'الإضاءة ضعيفة',
          subtitle: 'الكاميرا لا ترى الجسم بوضوح',
          instruction: 'حسّن الإضاءة وخلي النور أمامك',
          icon: Icons.light_mode_rounded,
          color: Colors.white,
        ),
      ExerciseScreenState.readyToStart => const ExerciseStateInfo(
          title: 'جاهز للبدء',
          subtitle: 'تم اكتشاف الجسم بنجاح',
          instruction: 'جاهز للتمرين',
          icon: Icons.check_circle_rounded,
          color: neonGreen,
        ),
      ExerciseScreenState.countdown => const ExerciseStateInfo(
          title: 'استعد',
          subtitle: 'التمرين سيبدأ الآن',
          instruction: 'خليك ثابت داخل الإطار',
          icon: Icons.timer_rounded,
          color: neonGreen,
        ),
      ExerciseScreenState.training => const ExerciseStateInfo(
          title: 'التدريب شغال',
          subtitle: 'تابع الهدف على الشاشة',
          instruction: 'تحرك بسرعة ودقة',
          icon: Icons.directions_run_rounded,
          color: neonGreen,
        ),
      ExerciseScreenState.completed => const ExerciseStateInfo(
          title: 'Training Complete',
          subtitle: 'انتهى التمرين',
          instruction: 'راجع النتيجة',
          icon: Icons.emoji_events_rounded,
          color: neonGreen,
        ),
      ExerciseScreenState.error => const ExerciseStateInfo(
          title: 'مشكلة في الكاميرا',
          subtitle: 'تعذر فتح الكاميرا',
          instruction: 'ارجع وحاول مرة أخرى',
          icon: Icons.error_outline_rounded,
          color: Colors.white70,
        ),
      ExerciseScreenState.handsNotVisible => const ExerciseStateInfo(
          title: 'أظهر يديك',
          subtitle: 'نحتاج نشوف يديك بوضوح',
          instruction: 'ارفع يديك أمام الكاميرا',
          icon: Icons.pan_tool_rounded,
          color: Colors.white,
        ),
    };
  }
}

class LiveExercisePage extends CameraExerciseScreen {
  const LiveExercisePage({super.key, super.drillId, super.planId});
}

class CameraExerciseScreen extends StatefulWidget {
  const CameraExerciseScreen({super.key, this.drillId, this.planId});

  final String? drillId;
  final String? planId;
  @override
  State<CameraExerciseScreen> createState() => _CameraExerciseScreenState();
}

class _CameraExerciseScreenState extends State<CameraExerciseScreen> {
  final _camera = CameraService();
  final _pose = PoseService();
  final _machine = ExerciseStateMachine();
  late final ExerciseEngine _engine;
  HandReactionEngine? _handEngine;
  bool _isHandReaction = false;

  StreamSubscription<CameraFrame>? _frames;
  Timer? _clock;
  Timer? _demoTimer;
  Timer? _autoStartTimer;

  ExerciseScreenState _screenState = ExerciseScreenState.initializingCamera;
  ExerciseFrameState? _frameState;
  PoseSnapshot? _lastPose;
  bool _permissionGranted = false;
  bool _safetyAccepted = false;
  bool _isDetecting = false;
  bool _manualBypass = false;
  DateTime? _stableSince;
  DateTime _lastDetectionAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _duration = 30;
  int _remaining = 30;
  int _countdown = 3;
  int? _earnedXp;
  bool _leveledUp = false;
  bool _isHitFlash = false;
  bool _completingEarly = false;

  Drill get drill => drillById(widget.drillId);

  @override
  void initState() {
    super.initState();
    _engine = ExerciseEngine(type: _typeFor(drill.id), drillId: drill.id);
    _isHandReaction = _typeFor(drill.id) == ExerciseType.handReaction;
    if (_isHandReaction) _handEngine = HandReactionEngine(drillId: drill.id);
    _enterCameraMode();
  }

  @override
  void dispose() {
    _autoStartTimer?.cancel();
    _clock?.cancel();
    _demoTimer?.cancel();
    _frames?.cancel();
    _camera.dispose();
    _pose.dispose();
    _restoreSystemUi();
    super.dispose();
  }

  Future<void> _enterCameraMode() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await _initializeCamera();
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  Future<void> _initializeCamera() async {
    final granted = await _camera.requestPermission();
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted;
      _screenState = granted ? ExerciseScreenState.cameraReady : ExerciseScreenState.error;
    });
    if (!granted) return;
    await _camera.initialize();
    if (!mounted) return;
    _frames = _camera.frames.listen(_handleFrame);
    await _camera.startImageStream(landscapeLeft: true);
    if (_camera.isDemoMode) _startDemoFrames();
    setState(() => _screenState = ExerciseScreenState.searchingBody);
  }

  void _startDemoFrames() {
    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(milliseconds: 140), (_) {
      _handleFrame(const CameraFrame(image: null, width: 1280, height: 720, rotation: 0));
    });
  }

  // Pose detection is throttled and guarded so only one frame is processed at a
  // time. Frames are never stored or sent to a server.
  Future<void> _handleFrame(CameraFrame frame) async {
    if (_isDetecting || _screenState == ExerciseScreenState.completed) return;
    // 100ms (~10fps) for high accuracy during active training, 300ms for battery saving otherwise.
    final throttleMs = _screenState == ExerciseScreenState.training ? 100 : 300;
    if (DateTime.now().difference(_lastDetectionAt) < Duration(milliseconds: throttleMs)) {
      return;
    }
    _isDetecting = true;
    _lastDetectionAt = DateTime.now();
    try {
      final pose = await _pose.detect(frame);
      if (!mounted || pose == null) return;
      final next = _stateFromPose(pose);
      final running = _screenState == ExerciseScreenState.training;
      final exerciseState = (_isHandReaction && _handEngine != null)
          ? _handEngine!.evaluate(pose, running)
          : _engine.evaluate(pose, running);

      final hitScored = _frameState != null && exerciseState.reps > _frameState!.reps;
      if (hitScored) {
        SoundManager.instance.play(SoundEvent.targetHit);
        HapticFeedback.lightImpact();
        setState(() => _isHitFlash = true);
        Future.delayed(const Duration(milliseconds: 380), () {
          if (mounted) setState(() => _isHitFlash = false);
        });
      }

      final missScored = _frameState != null && exerciseState.misses > _frameState!.misses;
      if (missScored) {
        SoundManager.instance.play(SoundEvent.targetMiss);
      }

      // End exercise when all targets are collected (before timer expires).
      if (_screenState == ExerciseScreenState.training &&
          !_completingEarly &&
          exerciseState.reps >= exerciseState.totalTargets) {
        _completingEarly = true;
        _completeTraining();
        return;
      }

      setState(() {
        _lastPose = pose;
        _frameState = exerciseState;
        if (_screenState != ExerciseScreenState.training &&
            _screenState != ExerciseScreenState.countdown) {
          _screenState = next;
        }
      });
      _maybeAutoStart(next);
    } finally {
      _isDetecting = false;
    }
  }

  // State machine: converts pose quality and position into the exact user-facing
  // camera guidance state shown in the overlay.
  ExerciseScreenState _stateFromPose(PoseSnapshot pose) {
    if (_manualBypass) return ExerciseScreenState.readyToStart;
    if (pose.detectionScore == 0 || pose.bodyBox == null) {
      _stableSince = null;
      return ExerciseScreenState.searchingBody;
    }
    if (pose.detectionScore >= 1 && pose.detectionScore <= 4) {
      _stableSince = null;
      return ExerciseScreenState.partialBody;
    }
    if (pose.confidence < 0.30 || pose.lowLight) {
      _stableSince = null;
      return ExerciseScreenState.poorLight;
    }
    if (pose.tooClose) {
      _stableSince = null;
      return ExerciseScreenState.tooClose;
    }
    if (pose.tooFar) {
      _stableSince = null;
      return ExerciseScreenState.tooFar;
    }
    if (!pose.insideGuideFrame) {
      _stableSince = null;
      return ExerciseScreenState.offCenter;
    }
    _stableSince ??= DateTime.now();
    final stable = DateTime.now().difference(_stableSince!) >= const Duration(seconds: 2);
    if (!stable) return ExerciseScreenState.partialBody;

    // For hand-reaction: also require hands to be visible before readyToStart.
    if (_isHandReaction && _handEngine != null &&
        !_handEngine!.lastHands.anyHandVisible) {
      return ExerciseScreenState.handsNotVisible;
    }

    return ExerciseScreenState.readyToStart;
  }

  void _maybeAutoStart(ExerciseScreenState next) {
    if (next != ExerciseScreenState.readyToStart || _autoStartTimer != null) return;
    _autoStartTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _screenState == ExerciseScreenState.readyToStart) {
        _startCountdown();
      }
    });
  }

  Future<void> _startCountdown() async {
    if (_screenState != ExerciseScreenState.readyToStart) return;
    _autoStartTimer?.cancel();
    _autoStartTimer = null;
    setState(() {
      _screenState = ExerciseScreenState.countdown;
      _countdown = 3;
    });
    for (var i = 3; i >= 1; i--) {
      if (!mounted) return;
      SoundManager.instance.play(SoundEvent.countdownTick);
      setState(() => _countdown = i);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    SoundManager.instance.play(SoundEvent.countdownGo);
    _startTraining();
  }

  void _startTraining() {
    SoundManager.instance.play(SoundEvent.workoutStart);
    setState(() {
      _screenState = ExerciseScreenState.training;
      _remaining = _duration;
    });
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _completeTraining();
      } else if (mounted) {
        setState(() => _remaining--);
      }
    });
  }

  Future<void> _completeTraining() async {
    _clock?.cancel();
    SoundManager.instance.play(SoundEvent.workoutComplete);
    HapticFeedback.mediumImpact();
    await _camera.stopImageStream();
    if (!mounted) return;
    setState(() => _screenState = ExerciseScreenState.completed);

    if (widget.planId != null && drill.id.isNotEmpty) {
      final result = (_isHandReaction && _handEngine != null) ? _handEngine!.result() : _engine.result();
      final double speedMetric = result.averageReactionTime != null
          ? (1000 / result.averageReactionTime!.inMilliseconds.clamp(1, 10000)) * 100
          : 50.0;

      try {
        final sessionData = await FirebaseService().submitSessionResult(
          planId: widget.planId!,
          drillId: drill.id,
          accuracy: result.accuracy,
          speed: speedMetric.clamp(0, 100),
          agility: result.accuracy * 0.9,
          balance: result.accuracy * 0.85,
          calories: (result.totalReps * 0.4).ceil(),
          reps: result.totalReps,
          durationMinutes: (_duration / 60).ceil().clamp(1, 60),
        );
        if (sessionData != null) {
          _earnedXp = sessionData['earnedXp'] as int?;
          _leveledUp = sessionData['leveledUp'] == true;
        }
      } catch (e) {
        debugPrint('Session result save error: $e');
      }
    }

    _showResult();
  }

  void _showResult() {
    final result = (_isHandReaction && _handEngine != null) ? _handEngine!.result() : _engine.result();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ResultDialog(
        result: result,
        duration: _duration,
        earnedXp: _earnedXp,
        leveledUp: _leveledUp,
        onReplay: () {
          Navigator.of(context).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => LiveExercisePage(drillId: drill.id, planId: widget.planId)),
          );
        },
        onExit: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionGranted && _screenState != ExerciseScreenState.error) {
      return _permissionScreen();
    }
    if (!_safetyAccepted && _permissionGranted) return _safetyScreen();

    final info = _machine.info(_screenState);
    final frame = _frameState ??
        ExerciseFrameState(
          ready: false,
          guidance: '',
          targetRect: (_isHandReaction && _handEngine != null)
              ? _handEngine!.targetRect
              : _engine.targetRect,
          targetCircle: (_isHandReaction && _handEngine != null)
              ? _handEngine!.targetCircle
              : null,
          reps: 0,
          misses: 0,
          score: 0,
          accuracy: 0,
          averageReactionTime: null,
          totalTargets: (_isHandReaction && _handEngine != null)
              ? HandReactionEngine.totalTargets
              : _engine.totalTargets,
        );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _camera.buildPreview()),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.95),
                  ],
                  stops: const [0.0, 0.25, 0.65, 1.0],
                ),
              ),
            ),
          ),
          if (_screenState != ExerciseScreenState.training)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 1.4, sigmaY: 1.4),
                child: ColoredBox(color: Colors.black.withOpacity(0.18)),
              ),
            ),
          if (_screenState != ExerciseScreenState.training)
            Positioned.fill(
              child: CustomPaint(
                painter: PoseGuidePainter(
                  state: _screenState,
                  pose: _lastPose,
                  ready: _screenState == ExerciseScreenState.readyToStart,
                ),
              ),
            ),
          if (_screenState == ExerciseScreenState.training)
            Positioned.fill(
              child: CustomPaint(
                painter: TargetPainter(
                  frameState: frame,
                  type: _engine.type,
                  isHitFlash: _isHitFlash,
                  showDebug: showPoseDebug,
                  handPoint: _isHandReaction && _handEngine != null
                      ? _handEngine!.lastHands.allPoints.firstOrNull
                      : (_lastPose != null
                          ? (_lastPose!.landmarks['rightIndex'] ??
                              _lastPose!.landmarks['leftIndex'] ??
                              _lastPose!.rightWrist ??
                              _lastPose!.leftWrist)
                          : null),
                ),
              ),
            ),
          if (_screenState != ExerciseScreenState.training &&
              _screenState != ExerciseScreenState.countdown)
            _PositioningOverlay(
              info: info,
              duration: _duration,
              onDurationChanged: (value) => setState(() => _duration = value),
              onStart: _screenState == ExerciseScreenState.readyToStart ? _startCountdown : null,
              onCancel: () => Navigator.of(context).maybePop(),
              canSkip: kDebugMode || _camera.isDemoMode,
              onSkip: () => setState(() {
                _manualBypass = true;
                _stableSince = DateTime.now().subtract(const Duration(seconds: 3));
                _screenState = ExerciseScreenState.readyToStart;
              }),
            ),
          // Hands-not-visible warning banner shown during training for hand-reaction.
          if (_screenState == ExerciseScreenState.training &&
              _isHandReaction &&
              (_handEngine?.lastHands.anyHandVisible == false))
            Positioned(
              top: 80,
              left: 24,
              right: 24,
              child: _GlassBanner(text: 'أظهر يديك بوضوح', color: AppColors.warning),
            ),
          if (_screenState == ExerciseScreenState.training)
            _TrainingHud(frame: frame, remaining: _remaining, onExit: _completeTraining),
          if (_screenState == ExerciseScreenState.countdown) _CountdownOverlay(count: _countdown),
          if (showPoseDebug)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: PoseDebugPainter(
                    pose: _lastPose,
                    state: _screenState,
                    screenSize: MediaQuery.of(context).size,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _permissionScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_camera_rounded, color: AppColors.primary, size: 54),
              const SizedBox(height: 18),
              const Text(
                'Camera Permission',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'الكاميرا مطلوبة لاكتشاف الحركة محليًا. لا يتم حفظ الفيديو.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.70), height: 1.4),
              ),
              const SizedBox(height: 22),
              PrimaryButton(label: 'Allow Camera', onTap: _initializeCamera),
            ],
          ),
        ),
      ),
    );
  }

  Widget _safetyScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.health_and_safety_rounded, color: AppColors.warning, size: 50),
              const SizedBox(height: 18),
              const Text(
                'Safety Warning',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                'فضّي المساحة حولك، ثبت الموبايل بالعرض، وأوقف التمرين إذا شعرت بأي ألم أو دوخة.',
                style: TextStyle(color: Colors.white.withOpacity(0.70), height: 1.45),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'I Understand',
                onTap: () => setState(() => _safetyAccepted = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PositioningOverlay extends StatelessWidget {
  const _PositioningOverlay({
    required this.info,
    required this.duration,
    required this.onDurationChanged,
    required this.onStart,
    required this.onCancel,
    required this.canSkip,
    required this.onSkip,
  });

  final ExerciseStateInfo info;
  final int duration;
  final ValueChanged<int> onDurationChanged;
  final VoidCallback? onStart;
  final VoidCallback onCancel;
  final bool canSkip;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    const neonGreen = Color(0xff39ff14);
    return SafeArea(
      child: Stack(
        children: [
          // Top Bar
          Positioned(
            top: 12,
            left: 18,
            right: 18,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GlassIconButton(icon: Icons.close_rounded, onTap: onCancel),
                const Spacer(),
                _TroubleCard(),
              ],
            ),
          ),
          // Center Card
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          info.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${info.subtitle}\n${info.instruction}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (onStart == null)
                          Text(
                            'جاري التتبع...',
                            style: TextStyle(
                              color: neonGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        else
                          Text(
                            'اضغط للبدء',
                            style: TextStyle(
                              color: neonGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Bottom Action
          Positioned(
            bottom: 16,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onStart != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [30, 45, 60].map((seconds) {
                      final active = seconds == duration;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          selected: active,
                          label: Text('${seconds}s'),
                          onSelected: (_) => onDurationChanged(seconds),
                          selectedColor: neonGreen,
                          backgroundColor: Colors.black.withOpacity(0.4),
                          labelStyle: TextStyle(
                            color: active ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: active ? neonGreen : Colors.white.withOpacity(0.1),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 16),
                if (onStart != null)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: onStart,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: neonGreen,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'ابدأ التمرين',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                if (canSkip && onStart == null)
                    TextButton(
                      onPressed: onSkip,
                    child: const Text(
                      'تخطي الكشف وابدأ',
                      style: TextStyle(color: Colors.white54),
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

class _TroubleCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(Icons.arrow_back_rounded, 'ارجع للخلف'),
          const SizedBox(height: 6),
          _buildRow(Icons.light_mode_rounded, 'إضاءة جيدة'),
          const SizedBox(height: 6),
          _buildRow(Icons.center_focus_strong_rounded, 'في المنتصف'),
        ],
      ),
    );
  }

  Widget _buildRow(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xff39ff14), size: 14),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11),
        ),
      ],
    );
  }
}

class _TrainingHud extends StatelessWidget {
  const _TrainingHud({required this.frame, required this.remaining, required this.onExit});

  final ExerciseFrameState frame;
  final int remaining;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final progress = frame.totalTargets > 0
        ? (frame.reps / frame.totalTargets).clamp(0.0, 1.0)
        : 0.0;
    const neon = Color(0xff39ff14);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── Top row: score pill + timer pill ──────────────────
            Row(
              children: [
                _MetricPill(
                  label: 'Score',
                  value: '${frame.reps} / ${frame.totalTargets}',
                  icon: Icons.star_rounded,
                ),
                const Spacer(),
                _MetricPill(
                  label: 'Timer',
                  value: '${remaining}s',
                  icon: Icons.timer_rounded,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ── Progress bar ──────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white.withOpacity(0.12),
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? neon : AppColors.primary,
                ),
              ),
            ),
            if (frame.guidance.isNotEmpty) ...[
              const SizedBox(height: 10),
              _GlassBanner(text: frame.guidance, color: AppColors.warning),
            ],
            if (frame.exerciseHint != null) ...[
              const SizedBox(height: 8),
              _GlassBanner(text: frame.exerciseHint!, color: AppColors.primary),
            ],
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onExit,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Exit Training'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black.withOpacity(0.45),
                side: BorderSide(color: Colors.white.withOpacity(0.25)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownOverlay extends StatelessWidget {
  const _CountdownOverlay({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 128,
        height: 128,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.62),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary, width: 2),
        ),
        child: Text(
          '$count',
          style: const TextStyle(color: Colors.white, fontSize: 58, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _GlassBanner extends StatelessWidget {
  const _GlassBanner({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.56),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.56),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 7),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.48),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.16)),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({
    required this.result,
    required this.duration,
    this.earnedXp,
    this.leveledUp = false,
    required this.onReplay,
    required this.onExit,
  });

  final DrillResultModel result;
  final int duration;
  final int? earnedXp;
  final bool leveledUp;
  final VoidCallback onReplay;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final avg = result.averageReactionTime == null
        ? '-'
        : '${(result.averageReactionTime!.inMilliseconds / 1000).toStringAsFixed(2)}s';
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leveledUp)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.5 * value),
                            blurRadius: 20 * value,
                            spreadRadius: 2 * value,
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.stars_rounded, color: AppColors.primary, size: 28),
                          SizedBox(width: 8),
                          Text(
                            'LEVEL UP!',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.stars_rounded, color: AppColors.primary, size: 28),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const Text(
              'Training Complete',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            if (earnedXp != null)
              _ResultRow(label: 'XP Earned', value: '+$earnedXp XP'),
            _ResultRow(label: 'Score', value: '${result.score}'),
            _ResultRow(label: 'Time', value: '${duration}s'),
            _ResultRow(label: 'Hits', value: '${result.totalReps}'),
            _ResultRow(label: 'Accuracy', value: '${result.accuracy.round()}%'),
            _ResultRow(label: 'Average Reaction Time', value: avg),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: PrimaryButton(label: 'Replay', onTap: onReplay)),
                const SizedBox(width: 10),
                Expanded(child: PrimaryButton(label: 'Exit', onTap: onExit)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: Colors.white.withOpacity(0.64)))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class PoseGuidePainter extends CustomPainter {
  PoseGuidePainter({required this.state, required this.pose, required this.ready});

  final ExerciseScreenState state;
  final PoseSnapshot? pose;
  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    final guide = _guideRect(size);
    final rrect = RRect.fromRectAndRadius(guide, const Radius.circular(20));
    const neonGreen = Color(0xff39ff14);

    final outside = Path()..addRect(Offset.zero & size);
    final inside = Path()..addRRect(rrect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, outside, inside),
      Paint()..color = Colors.black.withOpacity(0.35),
    );

    // Soft glow effect
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = ready ? neonGreen.withOpacity(0.25) : Colors.white.withOpacity(0.1)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Thin neon green rounded rectangle
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ready ? neonGreen : Colors.white.withOpacity(0.6),
    );
  }

  @override
  bool shouldRepaint(covariant PoseGuidePainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.pose != pose || oldDelegate.ready != ready;
}

class PoseDebugPainter extends CustomPainter {
  PoseDebugPainter({required this.pose, required this.state, required this.screenSize});

  final PoseSnapshot? pose;
  final ExerciseScreenState state;
  final Size screenSize;

  @override
  void paint(Canvas canvas, Size size) {
    final pose = this.pose;
    if (pose == null) return;

    // Landmarks are already screen-normalised (rotation + mirror baked in
    // by PoseDetectionService). Apply BoxFit.cover offset only so the skeleton
    // lines up with what CameraPreview shows on screen.
    final points = pose.landmarks.map((name, point) {
      return MapEntry(
        name,
        mapLandmarkToScreen(
          x: point.dx * pose.imageSize.width,
          y: point.dy * pose.imageSize.height,
          imageSize: pose.imageSize,
          screenSize: size,
          isFrontCamera: false, // already mirrored
          rotation: 0,          // already rotated
          fit: BoxFit.cover,
        ),
      );
    });

    final skeletonPaint = Paint()
      ..color = const Color(0xff39ff14)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    void line(String a, String b) {
      final pa = points[a];
      final pb = points[b];
      if (pa != null && pb != null) canvas.drawLine(pa, pb, skeletonPaint);
    }

    line('leftShoulder', 'rightShoulder');
    line('leftShoulder', 'leftHip');
    line('rightShoulder', 'rightHip');
    line('leftHip', 'rightHip');
    line('leftHip', 'leftKnee');
    line('rightHip', 'rightKnee');
    line('leftKnee', 'leftAnkle');
    line('rightKnee', 'rightAnkle');
    line('leftShoulder', 'leftWrist');
    line('rightShoulder', 'rightWrist');

    // Small dots
    final dotPaint = Paint()..color = const Color(0xff39ff14);
    final relevantPoints = [
      'leftShoulder', 'rightShoulder', 'leftHip', 'rightHip',
      'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle',
      'leftElbow', 'rightElbow', 'leftWrist', 'rightWrist'
    ];

    for (final key in relevantPoints) {
      final point = points[key];
      if (point != null) {
        canvas.drawCircle(point, 3, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PoseDebugPainter oldDelegate) =>
      oldDelegate.pose != pose || oldDelegate.state != state;
}

class TargetPainter extends CustomPainter {
  TargetPainter({
    required this.frameState,
    required this.type,
    this.isHitFlash = false,
    this.showDebug = false,
    this.handPoint,
  });

  final ExerciseFrameState frameState;
  final ExerciseType type;
  final bool isHitFlash;
  final bool showDebug;
  final Offset? handPoint; // normalized 0-1, for debug only

  // Keep in sync with ExerciseEngine._hitTolerance for handReaction.
  static const _debugHitTolerance = 0.05;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = AppColors.primary.withOpacity(0.22);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.primary;

    if (type == ExerciseType.getInTheBox || type == ExerciseType.sprintCube) {
      final r = frameState.targetRect;
      final rect = Rect.fromLTWH(r.left * size.width, r.top * size.height, r.width * size.width,
          r.height * size.height);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(18));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
      return;
    }

    final target = frameState.targetCircle;
    if (target == null) return;
    final center = Offset(target.center.dx * size.width, target.center.dy * size.height);
    final radius = target.radius * size.shortestSide;
    final hitRadius = (target.radius + _debugHitTolerance) * size.shortestSide;

    if (isHitFlash) {
      // Outer glow burst
      canvas.drawCircle(
        center, radius * 1.45,
        Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xff39ff14).withOpacity(0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      // Bright fill
      canvas.drawCircle(center, radius,
          Paint()..style = PaintingStyle.fill..color = const Color(0xff39ff14).withOpacity(0.55));
      // Bright stroke
      canvas.drawCircle(center, radius,
          Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = const Color(0xff39ff14));
      // "+1" text floating above circle
      final tp = TextPainter(
        text: const TextSpan(
          text: '+1',
          style: TextStyle(
            color: Color(0xff39ff14),
            fontSize: 30,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: Color(0xff39ff14), blurRadius: 8)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, radius + tp.height + 6));
    } else {
      // Normal target
      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, stroke);
    }

    // ── Debug overlay ──────────────────────────────────────────────
    if (showDebug) {
      // Dashed outer hitbox circle
      final dashPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.yellow.withOpacity(0.75);
      _drawDashedCircle(canvas, center, hitRadius, dashPaint, dashCount: 20);

      // Hand position dot
      if (handPoint != null) {
        final hp = Offset(handPoint!.dx * size.width, handPoint!.dy * size.height);
        canvas.drawCircle(hp, 7,
            Paint()..color = Colors.orangeAccent.withOpacity(0.85));
        // Distance line
        canvas.drawLine(hp, center,
            Paint()..color = Colors.orangeAccent.withOpacity(0.5)..strokeWidth = 1.5);
        // Distance text
        final dist = (hp - center).distance;
        final isHit = dist <= hitRadius;
        final dbgText = 'dist:${dist.toStringAsFixed(0)}px  hit:${hitRadius.toStringAsFixed(0)}px  ${isHit ? "HIT" : "MISS"}';
        final dbgTp = TextPainter(
          text: TextSpan(
            text: dbgText,
            style: TextStyle(
              color: isHit ? const Color(0xff39ff14) : Colors.yellow,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        dbgTp.paint(canvas, center + Offset(-dbgTp.width / 2, radius + 6));
      }
    }
  }

  void _drawDashedCircle(Canvas canvas, Offset center, double radius, Paint paint, {int dashCount = 16}) {
    const twoPi = math.pi * 2;
    final dashAngle = twoPi / dashCount;
    final gapAngle = dashAngle * 0.4;
    final arcAngle = dashAngle - gapAngle;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * dashAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, arcAngle, false, paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TargetPainter oldDelegate) =>
      oldDelegate.frameState != frameState ||
      oldDelegate.isHitFlash != isHitFlash ||
      oldDelegate.showDebug != showDebug ||
      oldDelegate.handPoint != handPoint;
}

Rect _guideRect(Size size) {
  final g = ExerciseEngine.guideFrame;
  return Rect.fromLTWH(g.left * size.width, g.top * size.height, g.width * size.width,
      g.height * size.height);
}


// Coordinate mapping: converts raw ML Kit image-space points to the fullscreen
// camera preview using the same BoxFit.cover crop math used by the preview.
Offset mapLandmarkToScreen({
  required double x,
  required double y,
  required Size imageSize,
  required Size screenSize,
  required bool isFrontCamera,
  required Object rotation,
  required BoxFit fit,
}) {
  if (imageSize.width <= 0 || imageSize.height <= 0) return Offset.zero;
  var nx = x / imageSize.width;
  var ny = y / imageSize.height;
  // rotation is expected to be degrees (0, 90, 180, 270)
  int rotDeg = 0;
  if (rotation is int) rotDeg = rotation;
  // Normalize rotation to one of the standard values
  rotDeg = ((rotDeg % 360) + 360) % 360;

  double rx = nx;
  double ry = ny;
  // Rotate normalized coordinates to match the preview orientation
  switch (rotDeg) {
    case 90:
      rx = ny;
      ry = 1 - nx;
      break;
    case 180:
      rx = 1 - nx;
      ry = 1 - ny;
      break;
    case 270:
      rx = 1 - ny;
      ry = nx;
      break;
    case 0:
    default:
      rx = nx;
      ry = ny;
  }

  if (isFrontCamera) rx = 1 - rx;

  final scale = fit == BoxFit.cover
      ? math.max(screenSize.width / imageSize.width, screenSize.height / imageSize.height)
      : math.min(screenSize.width / imageSize.width, screenSize.height / imageSize.height);
  final fittedW = imageSize.width * scale;
  final fittedH = imageSize.height * scale;
  final dx = (screenSize.width - fittedW) / 2;
  final dy = (screenSize.height - fittedH) / 2;
  return Offset(dx + rx * fittedW, dy + ry * fittedH);
}

ExerciseType _typeFor(String id) {
  return switch (id) {
    'get-in-box'    => ExerciseType.getInTheBox,
    'foot-reaction' => ExerciseType.footReaction,
    'rain-body'     => ExerciseType.rainBody,
    'rain-feet'     => ExerciseType.rainFeet,
    'ball-control'  => ExerciseType.ballControl,
    'first-touch'   => ExerciseType.firstTouch,
    'sprint-cube'   => ExerciseType.sprintCube,
    'agility-grid'  => ExerciseType.agilityGrid,
    'power-shot'    => ExerciseType.powerShot,
    'finisher'      => ExerciseType.finisher,
    _               => ExerciseType.handReaction,
  };
}

