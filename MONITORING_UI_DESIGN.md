# وحدة المراقبة الصحية - دليل الواجهات والتصميم
## Player Monitoring Module - UI Design Guide

---

## 📋 نظرة عامة
وحدة متكاملة لتتبع صحة اللاعب والأداء البدني تتضمن تسجيل مقاييس جسدية وحالة الاستعداد والإرهاق.

**الهدف**: تتبع شامل لصحة اللاعب قبل وأثناء وبعد التدريب

---

## 🎨 نظام التصميم

### الألوان الأساسية
```
Primary (أحمر الميريخ):    #CC2E2E / #2E7D32 (أخضر ديناميكي)
Success (أخضر):           #2E7D32 / #4CAF50
Warning (أصفر):           #FFA500 / #FF9800
Destructive (أحمر):       #DC2626 / #F44336
Background (خلفية):       #0A0A12
Card (بطاقة):            #1A1A24
Text Primary:             White (100%)
Text Secondary:           White (50%)
Text Tertiary:            White (30%)
```

### الخطوط
- **العربية**: Tajawal Bold/Normal/Light
- **English**: Inter Bold/Normal/Light
- **Headings**: Bold, 20-28px
- **Body**: Normal, 14-16px
- **Labels**: Bold, 12-14px

### الحدود والزوايا
- Border Radius: 12-18px
- Border Width: 1px (opacity 0.1)
- Padding: 16px (standard)
- Gap: 12px (items)

---

## 🗺️ خريطة الملاحة

```
Player Dashboard (الصفحة الرئيسية)
├── Quick Actions (إجراءات سريعة)
│   ├── "بدء تقييم" → /physical-assessment
│   ├── "الجاهزية" → /player/monitoring ⭐
│   └── "ملفي" → /player/profile
│
└── /player/monitoring (لوحة المراقبة الرئيسية)
    ├── Readiness Card (بطاقة الجاهزية)
    ├── Metrics Summary (ملخص المقاييس)
    ├── Load Analysis (تحليل الحمل)
    ├── Alerts (التنبيهات)
    ├── Insights (الرؤى الذكية)
    │
    ├── /player/monitoring/body-metrics (قياسات جسدية)
    ├── /player/monitoring/hooper (استعداد ما قبل التدريب)
    └── /player/monitoring/rpe (تقييم ما بعد التدريب)
```

---

## 📱 الواجهات التفصيلية

### 1️⃣ Monitoring Dashboard (لوحة المراقبة الرئيسية)
**المسار**: `/player/monitoring`

#### الهدف
عرض شامل لحالة صحة اللاعب والأداء والمخاطر

#### المكونات (من الأعلى للأسفل):

**A. App Bar**
```
┌─────────────────────────────────┐
│  ← Wellness Monitoring    🔄    │
└─────────────────────────────────┘
```
- العنوان: "Wellness Monitoring"
- زر رجوع (تلقائي)
- زر تحديث (refresh)

---

**B. Readiness Card (بطاقة الجاهزية الرئيسية)**
```
┌──────────────────────────────────┐
│  READINESS TO TRAIN              │
│                                  │
│        ████ 75%                  │
│                                  │
│   🟢 Ready to Compete            │
│   Last updated: Today 10:30 AM   │
└──────────────────────────────────┘
```

**المواصفات:**
- عرض النسبة المئوية (0-100)
- شريط تقدم ملون:
  - 🟢 Green (70-100): Ready
  - 🟡 Amber (40-69): Caution
  - 🔴 Red (0-39): At Risk
- نص الحالة أسفل
- آخر تحديث
- Gradient: Green to Dark

---

**C. Metrics Section (قسم المقاييس)**

**Body Metrics Card**
```
┌──────────────────────────────────┐
│  ❤️ Body Fat                     │
│  ────────────────────────────    │
│  18.5% | BMI: 23.1               │
│                                  │
│  Last: 2025-05-15 2:30 PM        │
│  [+ Add New Metrics]             │
└──────────────────────────────────┘
```

**Hooper Index Card**
```
┌──────────────────────────────────┐
│  🧠 Hooper Index (Today)         │
│  ────────────────────────────    │
│  12 | 🟡 Moderate                │
│                                  │
│  Sleep: 6/7 | Fatigue: 4/7       │
│  Stress: 2/7 | Soreness: 3/7     │
│  [+ Update Today]                │
└──────────────────────────────────┘
```

**Last RPE Card**
```
┌──────────────────────────────────┐
│  💪 Last Training Load           │
│  ────────────────────────────    │
│  140 (RPE 7 × 20 min)            │
│                                  │
│  Submitted: 2:45 PM              │
└──────────────────────────────────┘
```

---

**D. Load Analysis Section (تحليل الحمل)**

**ACWR Card (Acute-to-Chronic Load Ratio)**
```
┌──────────────────────────────────┐
│  Load Ratio (ACWR)               │
│  Acute / Chronic                 │
│                                  │
│           1.20                   │
│  🟢 Safe (< 1.5)                 │
└──────────────────────────────────┘
```

**Load Cards Row**
```
┌─────────────┬──────────────────┐
│ Acute Load  │ Chronic Load     │
│ 7 days avg  │ 28 days avg      │
│             │                  │
│    142      │      118         │
└─────────────┴──────────────────┘
```

---

**E. Weekly Load Chart**
```
┌──────────────────────────────────┐
│  Weekly Training Load            │
│                                  │
│  250 │                           │
│  200 │      ██                   │
│  150 │   ██ ██ ██                │
│  100 │████ ██ ██ ██           ██ │
│   50 │                           │
│    0 │─────────────────────────  │
│      Sun Mon Tue Wed Thu Fri Sat │
└──────────────────────────────────┘
```

---

**F. Alerts Section (التنبيهات)**
```
┌──────────────────────────────────┐
│  ⚠️ ALERTS                        │
│                                  │
│  🔴 Elevated Hooper over 3 days  │
│                                  │
│  🟡 High fatigue with high load  │
│                                  │
│  🟡 Sleep quality below 6 hours  │
└──────────────────────────────────┘
```

---

**G. AI Insights Section (الرؤى الذكية)**
```
┌──────────────────────────────────┐
│  💡 AI INSIGHTS                  │
│                                  │
│  Your recovery is below average  │
│  for this training phase.        │
│                                  │
│  Consider increasing sleep to    │
│  8+ hours for optimal performance│
└──────────────────────────────────┘
```

---

**H. Recommendations Section (التوصيات)**
```
┌──────────────────────────────────┐
│  📋 RECOMMENDATIONS              │
│                                  │
│  ┌──────────────┐ ┌────────────┐ │
│  │ Increase     │ │ Reduce     │ │
│  │ Sleep        │ │ Training   │ │
│  │ Duration     │ │ Intensity  │ │
│  └──────────────┘ └────────────┘ │
│  ┌──────────────┐ ┌────────────┐ │
│  │ Foam Roll    │ │ Hydrate    │ │
│  │ & Stretch    │ │ More       │ │
│  └──────────────┘ └────────────┘ │
└──────────────────────────────────┘
```

---

### 2️⃣ Body Metrics Screen (قياسات جسدية)
**المسار**: `/player/monitoring/body-metrics`

#### الهدف
تسجيل قياسات جسم اللاعب (الوزن، الطول، نسبة الدهون) مع حساب BMI تلقائي

#### المكونات:

**A. App Bar**
```
┌─────────────────────────────────┐
│  ← Body Metrics                 │
└─────────────────────────────────┘
```

---

**B. Latest Record Card**
```
┌──────────────────────────────────┐
│  Latest Record                   │
│  ──────────────────────────────  │
│                                  │
│  Weight      Height    Body Fat  │
│   75 kg      180 cm      18.5%   │
│                                  │
│  BMI: 23.1 (Normal)              │
│  Updated: May 15, 2:30 PM        │
└──────────────────────────────────┘
```

---

**C. Input Form**
```
┌──────────────────────────────────┐
│  ENTER NEW METRICS               │
│  ──────────────────────────────  │
│                                  │
│  Weight (kg)                     │
│  ┌──────────────────────────┐    │
│  │ 75                       │    │
│  └──────────────────────────┘    │
│                                  │
│  Height (cm)                     │
│  ┌──────────────────────────┐    │
│  │ 180                      │    │
│  └──────────────────────────┘    │
│                                  │
│  Body Fat (%)                    │
│  ┌──────────────────────────┐    │
│  │ 18.5                     │    │
│  └──────────────────────────┘    │
│                                  │
│  📊 BMI Preview: 23.1 (Normal)   │
│                                  │
│  ┌──────────────────────────┐    │
│  │      SAVE METRICS        │    │
│  └──────────────────────────┘    │
└──────────────────────────────────┘
```

**Validation Rules:**
- Weight: 20–300 kg
- Height: 100–250 cm
- Body Fat: 1–60%
- Live BMI calculation

**BMI Color Coding:**
- 🔵 Underweight: < 18.5
- 🟢 Normal: 18.5–24.9
- 🟡 Overweight: 25–29.9
- 🔴 Obese: ≥ 30

---

### 3️⃣ Hooper Index Screen (استعداد ما قبل التدريب)
**المسار**: `/player/monitoring/hooper`

#### الهدف
تسجيل مستويات الاستعداد قبل التدريب (نوم، إرهاق، إجهاد، آلام العضلات)

#### المكونات:

**A. App Bar**
```
┌─────────────────────────────────┐
│  ← Pre-Training Wellness        │
└─────────────────────────────────┘
```

---

**B. Hooper Score Display**
```
┌──────────────────────────────────┐
│  HOOPER INDEX SCORE              │
│                                  │
│         14                       │
│  🟡 MODERATE (11-16)             │
│                                  │
│  Status: Proceed with caution    │
└──────────────────────────────────┘
```

**Status Colors:**
- 🟢 Normal: 4–10
- 🟡 Moderate: 11–16
- 🔴 High Risk: 17–28

---

**C. Metric Sliders (1-7 Scale)**

```
┌──────────────────────────────────┐
│  SLEEP QUALITY                   │
│  ──────────────────────────────  │
│  😴 Poor ←────[●]───→ 😴 Excellent│
│  1    2   3   4   5   6   7      │
│  Your Selection: 4               │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│  FATIGUE LEVEL                   │
│  ──────────────────────────────  │
│  😩 Low ←─────────[●]→ 😩 High    │
│  1    2   3   4   5   6   7      │
│  Your Selection: 5               │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│  STRESS LEVEL                    │
│  ──────────────────────────────  │
│  😌 Low ←───[●]─────→ 😌 High    │
│  1    2   3   4   5   6   7      │
│  Your Selection: 3               │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│  MUSCLE SORENESS                 │
│  ──────────────────────────────  │
│  💪 None ←────[●]────→ 💪 Severe │
│  1    2   3   4   5   6   7      │
│  Your Selection: 4               │
└──────────────────────────────────┘
```

---

**D. Optional Fields**

```
┌──────────────────────────────────┐
│  SLEEP HOURS (Optional)          │
│  ──────────────────────────────  │
│  ┌──────────────────────────┐    │
│  │ 7.5                      │    │
│  └──────────────────────────┘    │
│                                  │
│  NOTES (Optional)                │
│  ──────────────────────────────  │
│  ┌──────────────────────────┐    │
│  │ Feeling stiff from...    │    │
│  │                          │    │
│  └──────────────────────────┘    │
└──────────────────────────────────┘
```

---

**E. Submit Button**
```
┌──────────────────────────────────┐
│      SUBMIT WELLNESS CHECK       │
└──────────────────────────────────┘
```

---

### 4️⃣ RPE Screen (تقييم ما بعد التدريب)
**المسار**: `/player/monitoring/rpe`

#### الهدف
تقييم الإرهاق بعد التدريب (RPE من 1–10) مع حساب حمل التدريب

#### المكونات:

**A. App Bar**
```
┌─────────────────────────────────┐
│  ← Post-Training Effort         │
└─────────────────────────────────┘
```

---

**B. RPE Scale (1-10 with Emojis)**

```
┌──────────────────────────────────┐
│  RATE YOUR EFFORT                │
│  ──────────────────────────────  │
│  How hard was the session?       │
│                                  │
│  1️⃣   2️⃣   3️⃣   4️⃣   5️⃣        │
│ 😴   😑   😐   😕   😤        │
│ Rest  Easy  Med Tough Hard       │
│                                  │
│  6️⃣   7️⃣   8️⃣   9️⃣  1️⃣0️⃣      │
│ 😤   😫   😱   😩   🔥        │
│ Hard Hard Max  Max  ALL OUT     │
│                                  │
│  ► Your selection: 7             │
└──────────────────────────────────┘
```

---

**C. Duration Input**

```
┌──────────────────────────────────┐
│  SESSION DURATION                │
│  ──────────────────────────────  │
│  How long was the session?       │
│                                  │
│  ┌──────────────────────────┐    │
│  │ 45          minutes       │    │
│  └──────────────────────────┘    │
└──────────────────────────────────┘
```

---

**D. Training Load Calculation (Live)**

```
┌──────────────────────────────────┐
│  TRAINING LOAD                   │
│  ──────────────────────────────  │
│  RPE × Duration = Load           │
│                                  │
│  7 × 45 min = 315               │
│                                  │
│  Classification:                 │
│  🟡 Moderate Load (200-400)      │
│                                  │
│  Recommendation:                 │
│  ✓ Within safe limits            │
│  Recovery: 24-36 hours optimal   │
└──────────────────────────────────┘
```

**Load Guidelines:**
- 🟢 Light: 0–150
- 🟡 Moderate: 151–300
- 🔴 High: 301–450
- 🔴🔴 Very High: > 450

---

**E. Optional Fields**

```
┌──────────────────────────────────┐
│  SESSION TYPE (Optional)         │
│  ┌──────────────────────────┐    │
│  │ - Select -           ▼   │    │
│  │ Strength               │    │
│  │ Agility                │    │
│  │ Endurance              │    │
│  │ Technique              │    │
│  └──────────────────────────┘    │
│                                  │
│  NOTES (Optional)                │
│  ──────────────────────────────  │
│  ┌──────────────────────────┐    │
│  │ Hamstring was tight...   │    │
│  │                          │    │
│  └──────────────────────────┘    │
└──────────────────────────────────┘
```

---

**F. Submit Button**
```
┌──────────────────────────────────┐
│      SAVE SESSION RATING         │
└──────────────────────────────────┘
```

---

### 5️⃣ Team Wellness Screen (كوتش - صحة الفريق)
**المسار**: `/club/wellness`

#### الهدف
لوحة تحكم المدرب لمراقبة صحة الفريق بأكمله

#### المكونات:

**A. Team Stats Row**
```
┌────────┬────────┬────────┬────────┐
│ 85     │ 12     │ 7.2    │ 4,200  │
│ Team   │ Injury │ Avg    │ Weekly │
│Readiness│ Risk  │ RPE    │ Load   │
└────────┴────────┴────────┴────────┘
```

---

**B. Player Status List**
```
┌──────────────────────────────────┐
│ PLAYERS SUMMARY                  │
│ ──────────────────────────────── │
│                                  │
│ 🟢 15 Ready                      │
│ 🟡 3 Caution                     │
│ 🔴 2 At Risk                     │
│                                  │
│ [PLAYER LIST]                    │
│ ┌────────────────────────────┐   │
│ │ Ahmed Hassan        85% 🟢  │   │
│ │ Mohamed Ali         72% 🟡  │   │
│ │ Omar Khaled         45% 🔴  │   │
│ │ Jamal Saeed         91% 🟢  │   │
│ └────────────────────────────┘   │
└──────────────────────────────────┘
```

---

**C. Team Load Chart**
```
┌──────────────────────────────────┐
│ Team Training Load (Last 7 days) │
│                                  │
│   5000 │                         │
│   4000 │      ██                 │
│   3000 │   ██ ██ ██              │
│   2000 │███ ██ ██ ██          ██ │
│   1000 │                         │
│      0 │──────────────────────── │
│        │Sun Mon Tue Wed Thu Fri S│
└──────────────────────────────────┘
```

---

**D. Recovery Recommendations**
```
┌──────────────────────────────────┐
│ 💡 TEAM INSIGHTS                 │
│                                  │
│ • 5 players need extra recovery  │
│ • Avg load trending up (↑ 15%)   │
│ • Sleep quality dropping         │
│                                  │
│ ACTIONS:                         │
│ [Reduce Intensity] [Add Rest Day]│
└──────────────────────────────────┘
```

---

## 🔄 User Flows

### Flow 1: Player Day Workflow
```
1. Log in → Player Dashboard
2. See "الجاهزية" (Wellness) quick action
3. Click → Monitoring Dashboard
4. Review readiness score (75%) 🟢
5. If readiness < 70%:
   - Check alerts
   - Follow recommendations
6. Before training: Update Hooper Index
7. After training: Log RPE
8. Dashboard updates automatically
```

---

### Flow 2: Coach Weekly Review
```
1. Go to /club/wellness
2. See team readiness overview
3. Identify at-risk players (🔴)
4. Click player → View history & trends
5. Download report / share recommendations
6. Plan recovery activities
```

---

### Flow 3: Data Submission (Player)
```
Body Metrics Path:
  ➜ Body Metrics Screen
  ➜ Enter weight, height, body fat
  ➜ See live BMI calculation
  ➜ Tap "SAVE METRICS"
  ➜ API validates (20-300 kg, etc)
  ➜ Dashboard updates
  ➜ Show success message

Hooper Path:
  ➜ Hooper Screen
  ➜ Adjust 4 sliders (1-7)
  ➜ See live Hooper score update
  ➜ Optionally enter sleep hours & notes
  ➜ Tap "SUBMIT WELLNESS CHECK"
  ➜ Score saved + color status shown
  ➜ Dashboard alerts if high risk

RPE Path:
  ➜ RPE Screen
  ➜ Select effort (1-10 emojis)
  ➜ Enter duration (minutes)
  ➜ See live training load calculation
  ➜ Optional: add session type & notes
  ➜ Tap "SAVE SESSION RATING"
  ➜ Load saved + dashboard metrics update
```

---

## 📊 Data Hierarchy

```
READINESS SCORE (Calculated)
├── Hooper Index (Today)
│   ├── Sleep Quality (1-7)
│   ├── Fatigue (1-7)
│   ├── Stress (1-7)
│   └── Muscle Soreness (1-7)
├── RPE Load History
│   ├── Last 7 days
│   └── Last 28 days (chronic)
├── ACWR (Acute/Chronic Ratio)
└── Body Metrics (Latest)
    ├── Weight, Height
    └── Body Fat %

ALERTS & INSIGHTS
├── Injury Risk Indicators
│   ├── Elevated Hooper (3+ days)
│   ├── High fatigue + High load
│   ├── ACWR > 1.5
│   └── Poor sleep pattern
└── AI Recommendations
    ├── Recovery tips
    ├── Training adjustments
    └── Hydration & nutrition
```

---

## 🎯 Color Status Legend

```
🟢 GREEN (Normal/Good)
   - Readiness: 70-100%
   - Hooper: 4-10
   - ACWR: < 1.3
   → Status: "Ready to Compete"

🟡 AMBER (Moderate/Caution)
   - Readiness: 40-69%
   - Hooper: 11-16
   - ACWR: 1.3-1.5
   → Status: "Proceed with Caution"

🔴 RED (At Risk/High)
   - Readiness: < 40%
   - Hooper: 17-28
   - ACWR: > 1.5
   → Status: "At Risk - Reduce Load"
```

---

## 📱 Responsive Design

**Phone (Vertical - Primary)**
- Width: 360-480px
- Padding: 16px standard
- Cards stack vertically
- Full-width inputs
- Touch targets: 44px minimum

**Tablet (Optional Future)**
- Width: 600px+
- Two-column layouts possible
- Side navigation option

---

## ♿ Accessibility

```
✓ Color contrast: WCAG AA compliant
✓ Touch targets: 44px × 44px minimum
✓ RTL support: Full Arabic support
✓ Screen reader: Semantic HTML
✓ Font sizes: 12px minimum body text
✓ Labels: All inputs labeled
```

---

## 🔐 Security Indicators

```
🔒 Auth Protected:
   - All endpoints require Bearer token
   - User data isolated by token
   - No cross-player access possible

✓ Validation:
   - Server-side input validation
   - Range checks (weight, height, scores)
   - Sanitized database queries
```

---

## 📝 Labels & Copy (EN/AR)

```
English                          | العربية
─────────────────────────────────┼──────────────────────────
Wellness Monitoring              | مراقبة الصحة
Readiness to Train               | الجاهزية للتدريب
Body Metrics                     | القياسات الجسدية
Body Fat                         | نسبة الدهون
Hooper Index                     | مؤشر هوبر
RPE Score                        | درجة الإرهاق
Training Load                    | حمل التدريب
Sleep Quality                    | جودة النوم
Fatigue Level                    | مستوى الإرهاق
Stress Level                     | مستوى الإجهاد
Muscle Soreness                  | آلام العضلات
Ready to Compete                 | جاهز للمنافسة
Proceed with Caution             | تابع بحذر
At Risk - Reduce Load            | في خطر - قلل الحمل
```

---

## 🎬 Animation & Transitions

```
✓ Screen transitions: Fade (180ms)
✓ Button press: Subtle scale (100ms)
✓ Loading: Circular progress indicator
✓ Sliders: Smooth value transitions (200ms)
✓ Cards: Appear with slight slide (150ms)
✓ Chart updates: Smooth redraw (300ms)
```

---

## 📲 Bottom Navigation (Player)

```
┌─────────────────────────────────┐
│ 🏠      ⚽      📋      👤      │
│Home   Assessments History Profile│
│                                  │
│ Current: (Active icon in green) │
└─────────────────────────────────┘

Active route: /player
Index: 0 (Home)
```

---

## 🚀 Implementation Checklist for Design Team

- [ ] Export all color variables (Figma/Adobe)
- [ ] Create component library:
  - [ ] MetricCard (label, value, icon, color)
  - [ ] AlertBox (icon, text, severity color)
  - [ ] InsightBox (lightbulb icon, text)
  - [ ] SliderInput (1-7 or custom range)
  - [ ] StatusChip (colored tag with text)
- [ ] Define typography scale
- [ ] Create spacing scale (8px grid)
- [ ] Design dark theme variants
- [ ] RTL mirror layouts
- [ ] Create interactive prototypes
- [ ] Accessibility audit (color contrast, touch targets)
- [ ] Design for loading states
- [ ] Design for error states
- [ ] Create hand-off specifications

---

## 📞 Design Handoff Notes

**Figma File Structure Suggested:**
```
Monitoring Module
├── 0. Components
│   ├── Cards
│   ├── Inputs (Sliders, TextFields)
│   ├── Buttons
│   ├── Status Chips
│   └── Charts
├── 1. Screens
│   ├── Dashboard
│   ├── Body Metrics
│   ├── Hooper Index
│   ├── RPE
│   └── Team Wellness
├── 2. Flows
│   ├── Data Entry Flow
│   ├── Player Day Workflow
│   └── Coach Review
└── 3. Specifications
    ├── Colors
    ├── Typography
    └── Spacing
```

---

**Version**: 1.0 (May 15, 2025)
**Module Status**: MVP Ready
**Target Client**: Al Merrikh SC
**Next Phase**: Design hand-off to Cloud Design team
