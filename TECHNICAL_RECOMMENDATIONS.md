# توصيات فنية مفصلة - تحسين جودة التمارين
## Technical Implementation Guide

---

## 🔧 التعديلات الفنية المقترحة

### 1️⃣ تحسين Pre-Assessment Screening

**الملف:** `lib/screens/physical_assessment/assessment_camera_page.dart`

**التعديل المقترح:**

```dart
// أضف enum جديد
enum ScreeningQuestion {
  recentInjury,      // إصابة حديثة
  chronicPain,       // ألم مزمن
  dizzinessHistory,  // تاريخ دوار
  medication,        // أدوية تؤثر
}

// أنشئ screening questionnaire قبل الاختبار
class PreAssessmentScreen extends StatefulWidget {
  final AssessmentTestType testType;
  final VoidCallback onPass;
  final VoidCallback onFail;
  
  // الأسئلة المهمة لكل اختبار:
  static Map<AssessmentTestType, List<String>> warningQuestions = {
    AssessmentTestType.singleLegDropJump: [
      'هل كان لديك إصابة في الركبة خلال آخر 3 أشهر؟',
      'هل تشعر بألم في الكاحل أو الركبة الآن؟',
      'هل أنت مصاب بدوار أو مشاكل توازن؟',
    ],
    AssessmentTestType.dropJump: [
      'هل كان لديك إصابة في الركبة خلال آخر 3 أشهر؟',
      'هل تشعر بألم في الركبة أو الكاحل الآن؟',
    ],
    AssessmentTestType.countermovementJump: [
      'هل أنت متعب جداً اليوم؟',
      'هل أكملت الإحماء؟',
    ],
  };
}
```

---

### 2️⃣ تحسين Calibration Wizard

**الملف:** `lib/screens/physical_assessment/assessment_camera_page.dart`

**التعديل المقترح:**

```dart
// أضف calibration state جديد
enum CalibrationStep {
  introduction,      // شرح الاختبار
  positioning,       // موضع الجسم
  poseDetection,     // فحص الكشف
  ready,            // جاهز للبداية
}

class CalibrationWizard {
  static Widget buildStep(
    CalibrationStep step,
    AssessmentTestType testType,
    PoseSnapshot? latestPose,
  ) {
    return switch (step) {
      CalibrationStep.introduction =>
        _buildIntroductionCard(testType),
      CalibrationStep.positioning =>
        _buildPositioningGuide(testType),
      CalibrationStep.poseDetection =>
        _buildPoseDetectionCheck(latestPose),
      CalibrationStep.ready =>
        _buildReadyCard(),
    };
  }

  static Widget _buildIntroductionCard(AssessmentTestType type) {
    final descriptions = {
      AssessmentTestType.countermovementJump:
        'اختبار القفز مع الاستعداد الحر\n'
        '• الهدف: قياس قوتك الانفجارية\n'
        '• المدة: 5 قفزات\n'
        '• الأمان: تأكد من الإحماء الجيد',
      AssessmentTestType.squatJump:
        'اختبار القفز من وضع ثابت\n'
        '• الهدف: قياس القوة المقبضة\n'
        '• المدة: 5 قفزات\n'
        '• ملاحظة: لا تستخدم الاستعداد الحر',
      // ... إضافة الباقي
    };

    return Card(
      child: Column(
        children: [
          Text(descriptions[type] ?? '',
            style: Theme.of(context).textTheme.bodyLarge),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => nextStep(),
            child: const Text('فهمت، دعني أبدأ'),
          ),
        ],
      ),
    );
  }

  static Widget _buildPositioningGuide(AssessmentTestType type) {
    final guides = {
      AssessmentTestType.countermovementJump: '''
قف في منتصف الشاشة:
1. قدميك بعرض الأكتاف
2. يداك خلف رأسك (أو معك)
3. اجعل جسمك مستقيماً
4. النظر للأمام''',
      // ... إضافة الباقي
    };

    return Column(
      children: [
        // صورة توضيحية
        Image.asset('assets/positioning/${type.name}.png'),
        SizedBox(height: 20),
        Text(guides[type] ?? ''),
        SizedBox(height: 20),
        LinearProgressIndicator(
          value: 0.66,
          minHeight: 8,
        ),
      ],
    );
  }
}
```

---

### 3️⃣ إضافة Countdown Widget مرئي

**الملف جديد:** `lib/widgets/countdown_widget.dart`

```dart
class CountdownWidget extends StatefulWidget {
  final Duration duration;
  final VoidCallback onComplete;
  final bool showBigNumber; // عرض رقم كبير

  const CountdownWidget({
    required this.duration,
    required this.onComplete,
    this.showBigNumber = true,
  });

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _remaining = widget.duration.inSeconds;
    _startCountdown();
  }

  void _startCountdown() {
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _remaining--);
        if (_remaining <= 0) {
          widget.onComplete();
        } else {
          _controller.forward(from: 0.0);
        }
      }
    });

    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.5, end: 1.0).animate(_controller),
      child: Center(
        child: Text(
          _remaining.toString(),
          style: TextStyle(
            fontSize: widget.showBigNumber ? 120 : 48,
            fontWeight: FontWeight.bold,
            color: _remaining <= 1 
              ? AppColors.destructive 
              : AppColors.success,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

---

### 4️⃣ تحسين ResultDisplay Widget

**الملف:** `lib/widgets/assessment_result_display.dart` (جديد)

```dart
class AssessmentResultDisplay extends StatelessWidget {
  final AssessmentResult result;
  final PlayerProfile player;

  const AssessmentResultDisplay({
    required this.result,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. النتيجة الإجمالية مع Gauge
        _buildScoreGauge(result.overallScore),
        SizedBox(height: 24),

        // 2. تقييم الأداء
        _buildPerformanceMetrics(),
        SizedBox(height: 24),

        // 3. المشاكل المكتشفة
        if (result.issues.isNotEmpty)
          _buildIssuesCard(),
        SizedBox(height: 24),

        // 4. نقاط القوة
        if (_getStrengths().isNotEmpty)
          _buildStrengthsCard(),
        SizedBox(height: 24),

        // 5. التوصيات العملية
        _buildRecommendations(),
        SizedBox(height: 24),

        // 6. المقارنة مع الاختبار السابق
        _buildProgressComparison(),
      ],
    );
  }

  Widget _buildScoreGauge(int score) {
    final label = score >= 80 ? 'ممتاز'
        : score >= 60 ? 'جيد'
        : score >= 40 ? 'متوسط'
        : 'يحتاج تحسين';
    
    final color = score >= 80 ? AppColors.success
        : score >= 60 ? AppColors.primary
        : score >= 40 ? AppColors.warning
        : AppColors.destructive;

    return GaugeChart(
      value: score / 100,
      label: label,
      color: color,
      size: 200,
    );
  }

  Widget _buildIssuesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_rounded, color: AppColors.warning),
                SizedBox(width: 8),
                Text('المشاكل المكتشفة', 
                  style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            SizedBox(height: 12),
            for (final (idx, issue) in result.issues.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.warning,
                      child: Text('${idx + 1}'),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(issue,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (idx < result.correctionTips.length)
                            Text(result.correctionTips[idx],
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fitness_center_rounded, 
                  color: AppColors.primary),
                SizedBox(width: 8),
                Text('تمارين موصى بها',
                  style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            SizedBox(height: 12),
            for (final drill in result.recommendedDrills)
              _buildDrillTile(drill),
          ],
        ),
      ),
    );
  }

  Widget _buildDrillTile(String drill) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.play_circle_outline, 
              color: AppColors.primary, size: 20),
            SizedBox(width: 12),
            Expanded(child: Text(drill)),
            Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressComparison() {
    // مقارنة مع آخر اختبار
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('التطور', 
              style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    Text('الاختبار السابق'),
                    SizedBox(height: 8),
                    Text('70', 
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                  ],
                ),
                Icon(Icons.trending_up, color: AppColors.success),
                Column(
                  children: [
                    Text('الاختبار الحالي'),
                    SizedBox(height: 8),
                    Text('75',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success)),
                  ],
                ),
              ],
            ),
            SizedBox(height: 12),
            Text('+5 نقاط 🎉',
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
```

---

### 5️⃣ تحسين Scoring Logic للـ Reaction Exercises

**الملف:** `lib/services/exercise_engine.dart`

**التعديل المقترح:**

```dart
class DrillResult {
  final int totalReps;
  final int misses;
  final int score; // الدرجة النهائية
  final double accuracy;
  final Duration? averageReactionTime;
  final double consistency; // تناسق الأداء الجديد
  final double speedIndex; // مؤشر السرعة الجديد

  int get finalScore {
    // صيغة أفضل من: reps * 100 - misses * 20
    
    // 1. Base score من الـ reps
    final repScore = (totalReps * 10).clamp(0, 100);
    
    // 2. Penalty من الـ misses
    final missePenalty = (misses * 15).clamp(0, 100);
    
    // 3. Reaction time bonus
    final reactionBonus = averageReactionTime != null
        ? ((1500 - averageReactionTime!.inMilliseconds) / 1500 * 20)
          .clamp(0, 20)
        : 0.0;
    
    // 4. Consistency bonus
    final consistencyBonus = consistency * 15;
    
    return ((repScore - missePenalty + reactionBonus + consistencyBonus) / 100)
        .clamp(0, 100)
        .toInt();
  }

  double calculateConsistency() {
    if (_reactionTimes.isEmpty) return 0.5;
    
    final mean = _reactionTimes
        .map((d) => d.inMilliseconds)
        .reduce((a, b) => a + b) / _reactionTimes.length;
    
    final variance = _reactionTimes
        .map((d) => (d.inMilliseconds - mean).abs())
        .reduce((a, b) => a + b) / _reactionTimes.length;
    
    // لو variance منخفضة = أداء متناسقة
    return (1 - (variance / 500)).clamp(0, 1);
  }
}
```

---

### 6️⃣ إضافة Jump Height Calibration

**الملف:** `lib/services/jump_analysis_service.dart`

**التعديل المقترح:**

```dart
class JumpAnalysisService {
  // أزل الافتراض الثابت
  // static const double _assumedHeightCm = 175.0;
  
  // استخدم ارتفاع اللاعب الحقيقي
  static AssessmentResult analyze(
    AssessmentTestType testType,
    String playerId,
    String playerName,
    List<PoseSnapshot> frames, {
    double? playerHeightCm, // ⭐ هذا موجود لكن قد لا يكون مستخدماً دائماً
  }) {
    final heightCm = playerHeightCm ?? _estimateHeightFromFrames(frames);
    
    // الباقي...
  }

  static double _estimateHeightFromFrames(List<PoseSnapshot> frames) {
    // محاولة تقدير الارتفاع من النسب
    final bodyBoxHeights = frames
        .map((f) => f.bodyBox?.height ?? 0)
        .where((h) => h > 0)
        .toList();
    
    if (bodyBoxHeights.isEmpty) return 175.0;
    
    final avgBodyHeight = bodyBoxHeights.reduce((a, b) => a + b) / bodyBoxHeights.length;
    // العلاقة المتوقعة بين ارتفاع الـ body box وارتفاع الجسم
    return avgBodyHeight * 2.2; // تقريبي
  }
}
```

---

### 7️⃣ تحسين Hooper Index Display

**الملف:** `lib/screens/player/hooper_index_screen.dart`

**التعديل المقترح:**

```dart
class HooperTrendChart extends StatelessWidget {
  final List<HooperReading> history; // آخر 30 يوم
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // الخط البياني
        LineChart(
          LineChartData(
            lineBarsData: [
              LineChartBarData(
                spots: history.map((h) => 
                  FlSpot(h.daysAgo.toDouble(), h.hooperIndex.toDouble())
                ).toList(),
                isCurved: true,
                color: Colors.blue,
              ),
            ],
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final days = value.toInt();
                    return Text('$days أيام');
                  },
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 20),
        
        // التحليل التلقائي
        if (_getTrend() == Trend.increasing)
          AlertCard(
            icon: Icons.trending_up,
            title: 'تحذير: الإجهاد يزداد',
            message: 'الـ Hooper Index يرتفع. خفف الحمل التدريبي.',
            color: AppColors.warning,
          ),
        
        if (_getTrend() == Trend.stable)
          InfoCard(
            icon: Icons.trending_flat,
            title: 'مستقر: جاهز للتدريب',
            message: 'حالتك مستقرة. تابع التدريب الطبيعي.',
            color: AppColors.success,
          ),
      ],
    );
  }
}
```

---

### 8️⃣ إضافة Injury Screening System

**ملف جديد:** `lib/services/injury_screening_service.dart`

```dart
enum InjuryRiskLevel {
  green,      // آمن
  yellow,     // احذر
  red,        // ممنوع
}

class InjuryScreening {
  final String playerId;
  final DateTime date;
  final List<InjuryArea> reportedInjuries;
  final List<String> painLocations;
  
  bool canPerformTest(AssessmentTestType type) {
    if (type == AssessmentTestType.singleLegDropJump) {
      // SLDJ خطر جداً للإصابات
      if (hasRecentKneeInjury) return false;
      if (hasRecentAnkleInjury) return false;
      if (reportsPainInLegs) return false;
    }
    
    if (type == AssessmentTestType.dropJump) {
      if (hasRecentKneeInjury) return false;
      if (reportsPainInLegs) return false;
    }
    
    return true;
  }
  
  InjuryRiskLevel getRiskLevel(AssessmentTestType type) {
    if (!canPerformTest(type)) return InjuryRiskLevel.red;
    
    if (type == AssessmentTestType.countermovementJump) {
      if (hasRecentKneeInjury) return InjuryRiskLevel.yellow;
      if (reportsPainInLegs) return InjuryRiskLevel.yellow;
    }
    
    return InjuryRiskLevel.green;
  }
}
```

---

## 📊 الملفات المطلوب تعديلها

| الملف | التعديل | الأولوية | الوقت |
|-----|--------|---------|------|
| `assessment_camera_page.dart` | +Pre-screening, +Calibration | عالية | 6h |
| `exercise_engine.dart` | +Scoring logic, +Consistency | متوسطة | 4h |
| `assessment_result_page.dart` | +Better display | متوسطة | 3h |
| `hooper_index_screen.dart` | +Charts | متوسطة | 3h |
| `jump_analysis_service.dart` | +Height calibration | منخفضة | 1h |
| (جديد) `countdown_widget.dart` | +Countdown | متوسطة | 2h |
| (جديد) `injury_screening_service.dart` | +Safety | عالية | 2h |

**المجموع:** ~21 ساعة

---

## 🎯 الأولويات النهائية

### للديمو (أسبوع واحد):

1. ✅ Pre-Assessment Screening
2. ✅ Calibration Wizard
3. ✅ Remove ineffective drills
4. ✅ Countdown Widget

### للإصدار 2 (شهر واحد):

1. ✅ Improved Result Display
2. ✅ Hooper Charts
3. ✅ Injury Screening
4. ✅ Height Calibration

---

**آخر تحديث:** 2 يونيو 2026  
**الإصدار:** 1.0
