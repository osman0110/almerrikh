import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../services/pose_detection_service_web.dart';
import 'assessment_camera_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WebPoseSetupScreen
//
// Shown on Flutter Web before any pose-based assessment.
// Runs in order:
//   1. Browser compatibility check
//   2. Local MediaPipe asset verification
//   3. AI model preload (MediaPipe PoseLandmarker)
//   4. Camera permission
//   5. Ready → user taps Start
//
// Fast-path: if model already loaded from a previous assessment in the same
// session, steps 1-3 show ✅ immediately and the screen skips to camera check.
// ─────────────────────────────────────────────────────────────────────────────

enum _StepStatus { pending, loading, success, warning, error }

class _Step {
  _Step({required this.ar, required this.en});
  final String ar;
  final String en;
  _StepStatus status = _StepStatus.pending;
}

class WebPoseSetupScreen extends StatefulWidget {
  const WebPoseSetupScreen({super.key, required this.cameraArgs});
  final AssessmentCameraArguments cameraArgs;

  @override
  State<WebPoseSetupScreen> createState() => _WebPoseSetupScreenState();
}

class _WebPoseSetupScreenState extends State<WebPoseSetupScreen>
    with SingleTickerProviderStateMixin {
  late final List<_Step> _steps;
  int _currentIdx = 0;
  double _progress = 0.0;
  String? _errorMsg;
  bool _cameraPromptVisible = false; // show "Allow Camera" button
  bool _canStart = false;
  bool _autoStarting = false;
  int _autoCountdown = 0;
  Timer? _autoTimer;

  // Cycling tips while loading
  static const _tipsAr = [
    'سيتم حفظ الملفات في المتصفح وستعمل أسرع في المرات القادمة',
    'اجعل الجسم كاملاً ظاهراً داخل الإطار',
    'ضع الكاميرا على بعد 2-3 متر',
    'اسمح بالكاميرا عند الطلب للاستمرار',
  ];
  static const _tipsEn = [
    'Files are cached in your browser — next sessions will be much faster',
    'Keep your full body visible inside the frame',
    'Place the camera 2–3 metres away',
    'Allow camera access when prompted to continue',
  ];
  int _tipIdx = 0;
  Timer? _tipTimer;

  // Debug info (shown only in debug builds)
  String _debugLines = '';

  bool get _isAr => getAppLanguage() == 'ar';
  String _t(String ar, String en) => _isAr ? ar : en;

  @override
  void initState() {
    super.initState();
    _steps = [
      _Step(ar: 'فحص المتصفح',            en: 'Checking browser'),
      _Step(ar: 'تحميل ملفات الذكاء',      en: 'Loading AI files'),
      _Step(ar: 'تجهيز نموذج الحركة',      en: 'Preparing pose model'),
      _Step(ar: 'التحقق من الكاميرا',      en: 'Camera access'),
      _Step(ar: 'جاهز للبدء',              en: 'Ready to start'),
    ];

    _tipTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _tipIdx = (_tipIdx + 1) % _tipsAr.length);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _autoTimer?.cancel();
    super.dispose();
  }

  // ── Setup flow ─────────────────────────────────────────────────────────────

  Future<void> _init() async {
    if (PoseDetectionService.isModelReady) {
      // Fast path: model was already loaded this session
      _setRange(0, 3, _StepStatus.success);
      setState(() { _progress = 0.75; _currentIdx = 3; });
      await _doCameraStep(fastPath: true);
    } else {
      await _runFullSetup();
    }
  }

  Future<void> _runFullSetup() async {
    await _stepBrowserCheck();
    if (!mounted || _errorMsg != null) return;
    await _stepAssetVerify();
    if (!mounted || _errorMsg != null) return;
    await _stepModelLoad();
    if (!mounted || _errorMsg != null) return;
    await _doCameraStep(fastPath: false);
  }

  // Step 1 — Browser compatibility
  Future<void> _stepBrowserCheck() async {
    _setStep(0, _StepStatus.loading);
    await Future.delayed(const Duration(milliseconds: 250));

    final r = PoseDetectionService.checkBrowserSupport();
    _appendDebug('browser: secure=${r.isSecureContext} media=${r.hasMediaDevices} wasm=${r.hasWebAssembly}');

    if (!r.supported) {
      String msg;
      if (!r.isSecureContext) {
        msg = _t(
          'يتطلب الموقع HTTPS لاستخدام الكاميرا والذكاء الاصطناعي.',
          'This site requires HTTPS for camera and AI. Open via https://');
      } else if (!r.hasWebAssembly) {
        msg = _t(
          'متصفحك لا يدعم الذكاء الاصطناعي. استخدم Chrome أو Safari الحديث.',
          'Your browser does not support AI detection. Use modern Chrome or Safari.');
      } else {
        msg = _t(
          'المتصفح لا يدعم الكاميرا. تحقق من إعدادات الأذونات.',
          'Browser does not support camera. Check permissions.');
      }
      _setError(0, msg);
      return;
    }
    _setStep(0, _StepStatus.success);
    setState(() => _progress = 0.20);
  }

  // Step 2 — Asset files
  Future<void> _stepAssetVerify() async {
    _setStep(1, _StepStatus.loading);
    setState(() => _currentIdx = 1);

    final r = await PoseDetectionService.verifyAssets();
    _appendDebug('assets: ok=${r.ok} missing=${r.missing}');

    if (!r.ok) {
      _setError(1, _t(
        'ملفات الذكاء الاصطناعي مفقودة. تواصل مع الدعم الفني.',
        'AI model files are missing. Please contact support.'));
      return;
    }
    _setStep(1, _StepStatus.success);
    setState(() => _progress = 0.40);
  }

  // Step 3 — Model preload
  Future<void> _stepModelLoad() async {
    _setStep(2, _StepStatus.loading);
    setState(() => _currentIdx = 2);

    // Start preload + poll progress concurrently
    final preloadFuture = PoseDetectionService.preloadModel();

    while (mounted) {
      final status = PoseDetectionService.engineStatus;
      if (status != 'loading') break;
      final jsProgress = PoseDetectionService.modelLoadProgress;
      setState(() => _progress = 0.40 + (jsProgress / 100.0) * 0.35);
      await Future.delayed(const Duration(milliseconds: 180));
    }

    final result = await preloadFuture;
    _appendDebug('model: success=${result.success} error=${result.error}');

    if (!result.success) {
      final errMsg = result.error ?? '';
      String msg;
      if (errMsg.contains('HTTPS_REQUIRED')) {
        msg = _t(
          'يتطلب تحميل النموذج HTTPS. افتح الموقع عبر https://',
          'Model loading requires HTTPS. Open the site over https://');
      } else if (errMsg.contains('timeout')) {
        msg = _t(
          'انتهت مهلة التحميل. تحقق من الاتصال وأعد المحاولة.',
          'Load timed out. Check your connection and retry.');
      } else if (errMsg.contains('assets not found') || errMsg.contains('missing')) {
        msg = _t(
          'ملفات الذكاء غير موجودة. تواصل مع الدعم الفني.',
          'AI files not found. Please contact support.');
      } else {
        msg = _t(
          'فشل تحميل نموذج الذكاء الاصطناعي. أعد المحاولة.',
          'Failed to load AI model. Please retry.');
      }
      _setError(2, msg);
      return;
    }

    _setStep(2, _StepStatus.success);
    setState(() => _progress = 0.75);
  }

  // Step 4 — Camera
  Future<void> _doCameraStep({required bool fastPath}) async {
    _setStep(3, _StepStatus.loading);
    setState(() { _currentIdx = 3; });

    // Check existing permission silently
    final permState = await PoseDetectionService.getCameraPermissionState();
    _appendDebug('camera perm: $permState');

    if (!mounted) return;

    if (permState == 'denied') {
      _setError(3, _t(
        'تم رفض إذن الكاميرا. فعّل الكاميرا في إعدادات المتصفح.',
        'Camera permission denied. Enable camera in browser settings.'));
      return;
    }

    if (permState == 'granted') {
      // Already granted — test silently
      final camResult = await PoseDetectionService.testCameraAccess();
      _appendDebug('camera test: ok=${camResult.ok}');
      if (!mounted) return;
      if (camResult.ok) {
        _finishSetup(fastPath: fastPath);
        return;
      } else {
        _setError(3, _t(
          'تعذر فتح الكاميرا. تأكد أن الكاميرا غير مستخدمة من تطبيق آخر.',
          'Could not open camera. Make sure no other app is using it.'));
        return;
      }
    }

    // 'prompt' or 'unknown' — show button for user gesture
    setState(() => _cameraPromptVisible = true);
  }

  // Called when user taps "Allow Camera" button
  Future<void> _onAllowCamera() async {
    setState(() => _cameraPromptVisible = false);
    _setStep(3, _StepStatus.loading);

    final camResult = await PoseDetectionService.testCameraAccess();
    _appendDebug('camera tap: ok=${camResult.ok} err=${camResult.error}');
    if (!mounted) return;

    if (!camResult.ok) {
      String msg;
      if (camResult.error == 'NotAllowedError') {
        msg = _t(
          'تم رفض إذن الكاميرا. فعّل الكاميرا في إعدادات المتصفح.',
          'Camera access denied. Enable camera access in browser settings.');
      } else {
        msg = _t(
          'تعذر فتح الكاميرا. أغلق التطبيقات الأخرى وأعد المحاولة.',
          'Could not open camera. Close other apps and retry.');
      }
      _setError(3, msg);
      return;
    }

    _finishSetup(fastPath: false);
  }

  void _finishSetup({required bool fastPath}) {
    if (!mounted) return;
    _setStep(3, _StepStatus.success);
    _setStep(4, _StepStatus.success);
    setState(() {
      _progress = 1.0;
      _currentIdx = 4;
      _canStart = true;
    });

    if (fastPath) {
      // Auto-start after brief delay for returning users
      _autoStarting = true;
      _autoCountdown = 2;
      _autoTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() => _autoCountdown--);
        if (_autoCountdown <= 0) {
          t.cancel();
          if (mounted) _startExercise();
        }
      });
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _startExercise() {
    _autoTimer?.cancel();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => AssessmentCameraPage(
        player:    widget.cameraArgs.player,
        testType:  widget.cameraArgs.testType,
        sessionId: widget.cameraArgs.sessionId,
      ),
    ));
  }

  Future<void> _retry() async {
    setState(() {
      _errorMsg = null;
      _cameraPromptVisible = false;
      _canStart = false;
      _autoStarting = false;
      for (final s in _steps) s.status = _StepStatus.pending;
      _progress = 0;
      _currentIdx = 0;
    });
    _autoTimer?.cancel();
    await _runFullSetup();
  }

  // ── State helpers ──────────────────────────────────────────────────────────

  void _setStep(int idx, _StepStatus s) {
    if (!mounted) return;
    setState(() => _steps[idx].status = s);
  }

  void _setRange(int from, int to, _StepStatus s) {
    for (int i = from; i < to && i < _steps.length; i++) {
      _steps[i].status = s;
    }
  }

  void _setError(int idx, String msg) {
    if (!mounted) return;
    setState(() {
      _steps[idx].status = _StepStatus.error;
      _errorMsg = msg;
    });
  }

  void _appendDebug(String line) {
    if (!kDebugMode) return;
    _debugLines += '$line\n';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: GoogleFonts.cairoTextTheme(Theme.of(context).textTheme),
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildProgressBar(),
                    const SizedBox(height: 20),
                    _buildStepsCard(),
                    const SizedBox(height: 16),
                    _buildTipsCard(),
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 16),
                      _buildErrorCard(),
                    ],
                    const SizedBox(height: 24),
                    _buildBottomArea(),
                    if (kDebugMode && _debugLines.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildDebugCard(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 68, height: 68,
          decoration: BoxDecoration(
            color: AppColors.maroon.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.self_improvement_rounded,
              color: AppColors.maroon, size: 34),
        ),
        const SizedBox(height: 14),
        Text(
          _t('تجهيز مدرب الذكاء الاصطناعي', 'Preparing AI Coach'),
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.foreground,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          _t(
            'يتم تحميل نموذج اكتشاف الحركة لأول مرة',
            'Loading motion detection model for the first time',
          ),
          style: GoogleFonts.cairo(
            fontSize: 13,
            color: AppColors.muted,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final pct = (_progress * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_t('التقدم', 'Progress'),
                style: GoogleFonts.cairo(fontSize: 12, color: AppColors.muted)),
            Text('$pct%',
                style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.maroon)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: _progress),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            builder: (_, value, __) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: AppColors.surface2,
              valueColor: AlwaysStoppedAnimation<Color>(
                _errorMsg != null ? AppColors.destructive : AppColors.maroon,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        children: List.generate(_steps.length, (i) {
          final step = _steps[i];
          final isActive = i == _currentIdx;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _stepIcon(step.status, isActive),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isAr ? step.ar : step.en,
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          color: step.status == _StepStatus.pending
                              ? AppColors.muted
                              : AppColors.foreground,
                        ),
                      ),
                      // Camera prompt inline
                      if (i == 3 && _cameraPromptVisible)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: GestureDetector(
                            onTap: _onAllowCamera,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 9),
                              decoration: BoxDecoration(
                                color: AppColors.maroon,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.videocam_rounded,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 7),
                                  Text(
                                    _t('السماح بالكاميرا', 'Allow Camera'),
                                    style: GoogleFonts.cairo(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _stepIcon(_StepStatus status, bool isActive) {
    switch (status) {
      case _StepStatus.pending:
        return Icon(Icons.radio_button_unchecked_rounded,
            color: AppColors.muted, size: 22);
      case _StepStatus.loading:
        return SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: isActive ? AppColors.maroon : AppColors.muted,
          ),
        );
      case _StepStatus.success:
        return const Icon(Icons.check_circle_rounded,
            color: AppColors.success, size: 22);
      case _StepStatus.warning:
        return const Icon(Icons.warning_amber_rounded,
            color: AppColors.warning, size: 22);
      case _StepStatus.error:
        return const Icon(Icons.cancel_rounded,
            color: AppColors.destructive, size: 22);
    }
  }

  Widget _buildTipsCard() {
    final tips = _isAr ? _tipsAr : _tipsEn;
    final tip  = tips[_tipIdx % tips.length];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: Container(
        key: ValueKey(_tipIdx),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.primary.withOpacity(0.30), width: 0.8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.tips_and_updates_rounded,
                color: AppColors.gold, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tip,
                style: GoogleFonts.cairo(
                  fontSize: 12.5,
                  color: AppColors.foreground,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.destructive.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.destructive.withOpacity(0.25), width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.destructive, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMsg!,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppColors.destructive,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomArea() {
    if (_errorMsg != null) {
      return GestureDetector(
        onTap: _retry,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.maroon,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                _t('إعادة المحاولة', 'Retry'),
                style: GoogleFonts.cairo(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    if (_canStart) {
      final label = _autoStarting
          ? _t('البدء تلقائياً... $_autoCountdown', 'Starting... $_autoCountdown')
          : _t('بدء التمرين', 'Start Exercise');
      return Column(
        children: [
          GestureDetector(
            onTap: _startExercise,
            child: Container(
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.maroon,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.maroon.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          if (_autoStarting)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextButton(
                onPressed: () {
                  _autoTimer?.cancel();
                  setState(() => _autoStarting = false);
                },
                child: Text(
                  _t('إلغاء التشغيل التلقائي', 'Cancel auto-start'),
                  style: GoogleFonts.cairo(
                      fontSize: 12, color: AppColors.muted),
                ),
              ),
            ),
        ],
      );
    }

    // Loading — show placeholder
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          _t('جارٍ التجهيز...', 'Preparing...'),
          style: GoogleFonts.cairo(
              fontSize: 14, color: AppColors.muted),
        ),
      ),
    );
  }

  Widget _buildDebugCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('DEBUG',
              style: TextStyle(
                  color: Color(0xFF00FF88),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Text(
            'status: ${PoseDetectionService.engineStatus}\n'
            'progress: ${PoseDetectionService.modelLoadProgress.toStringAsFixed(0)}%\n'
            'ready: ${PoseDetectionService.isModelReady}\n'
            '$_debugLines',
            style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 10,
                fontFamily: 'monospace',
                height: 1.6),
          ),
        ],
      ),
    );
  }
}
