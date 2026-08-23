import 'package:flutter/material.dart';
import '../../app_colors.dart';
import '../../app_state.dart';
import '../../models/fms_model.dart';
import '../../services/fms_service.dart';
import '../../widgets/common_widgets.dart';

/// Manual FMS (Functional Movement Screen) entry — a coach grades each of
/// the 7 movements 0-3 (bilateral ones per side), flags pain where present,
/// and the total (/21) is computed live using the official FMS rules:
/// bilateral final score = weaker side; a pain flag forces that movement to 0.
class FmsAssessmentScreen extends StatefulWidget {
  const FmsAssessmentScreen({super.key, required this.playerId, required this.playerName});

  final String playerId;
  final String playerName;

  @override
  State<FmsAssessmentScreen> createState() => _FmsAssessmentScreenState();
}

class _FmsAssessmentScreenState extends State<FmsAssessmentScreen> {
  final Map<FmsMovement, int?> _singleScores = {};
  final Map<FmsMovement, int?> _leftScores = {};
  final Map<FmsMovement, int?> _rightScores = {};
  final Map<FmsMovement, bool> _pain = {};
  final Map<FmsMovement, TextEditingController> _movementNotesCtrl = {
    for (final m in FmsMovement.values) m: TextEditingController(),
  };
  final _notesCtrl = TextEditingController();

  List<FmsAssessment> _history = [];
  bool _loadingHistory = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    for (final c in _movementNotesCtrl.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final h = await FmsService.getFmsHistory(widget.playerId, limit: 5);
    if (!mounted) return;
    setState(() {
      _history = h;
      _loadingHistory = false;
    });
  }

  int _finalScoreFor(FmsMovement m) {
    final pain = _pain[m] ?? false;
    if (pain) return 0;
    if (m.isBilateral) {
      final l = _leftScores[m];
      final r = _rightScores[m];
      if (l == null || r == null) return 0;
      return l < r ? l : r;
    }
    return _singleScores[m] ?? 0;
  }

  int get _totalScore =>
      FmsMovement.values.map(_finalScoreFor).fold(0, (a, b) => a + b);

  bool get _isComplete => FmsMovement.values.every((m) {
        if (m.isBilateral) return _leftScores[m] != null && _rightScores[m] != null;
        return _singleScores[m] != null;
      });

  Future<void> _submit() async {
    if (!_isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تسجيل درجة لكل الحركات السبع')),
      );
      return;
    }
    setState(() => _submitting = true);

    final movements = <FmsMovement, FmsMovementInput>{
      for (final m in FmsMovement.values)
        m: m.isBilateral
            ? FmsMovementInput(
                left: _leftScores[m], right: _rightScores[m], pain: _pain[m] ?? false,
                notes: _movementNotesCtrl[m]!.text.trim().isEmpty ? null : _movementNotesCtrl[m]!.text.trim(),
              )
            : FmsMovementInput(
                score: _singleScores[m], pain: _pain[m] ?? false,
                notes: _movementNotesCtrl[m]!.text.trim().isEmpty ? null : _movementNotesCtrl[m]!.text.trim(),
              ),
    };

    final res = await FmsService.saveFmsAssessment(
      playerId: widget.playerId,
      movements: movements,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ تقييم FMS — المجموع: ${res['total_score']} / 21')),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['error']?.toString() ?? 'حدث خطأ أثناء الحفظ')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canManageFms) return const RoleAccessDeniedPage();
    final previous = _history.isNotEmpty ? _history.first : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('FMS — ${widget.playerName}',
            style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Sticky total score header ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.card,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('المجموع الحالي', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      Text('$_totalScore / 21',
                          style: const TextStyle(
                              color: AppColors.foreground, fontWeight: FontWeight.w900, fontSize: 26)),
                    ],
                  ),
                  if (!_loadingHistory && previous != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('آخر تقييم', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        Text('${previous.totalScore} / 21',
                            style: const TextStyle(color: AppColors.textSoft, fontWeight: FontWeight.w700, fontSize: 16)),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ...FmsMovement.values.map(_buildMovementCard),
                  const SizedBox(height: 8),
                  const Text('ملاحظات عامة (اختياري)',
                      style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: AppColors.foreground),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.card,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('حفظ تقييم FMS',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementCard(FmsMovement m) {
    final pain = _pain[m] ?? false;
    final finalScore = _finalScoreFor(m);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(m.placeholderIcon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${m.nameAr} (${m.nameEn})',
                        style: const TextStyle(
                            color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(m.description,
                        style: const TextStyle(color: AppColors.muted, fontSize: 10.5, height: 1.3)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (pain ? AppColors.destructive : AppColors.primary).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$finalScore',
                    style: TextStyle(
                        color: pain ? AppColors.destructive : AppColors.primary,
                        fontWeight: FontWeight.w900, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (m.isBilateral)
            Row(
              children: [
                Expanded(child: _sideSelector('يسار', _leftScores[m], (v) => setState(() => _leftScores[m] = v))),
                const SizedBox(width: 10),
                Expanded(child: _sideSelector('يمين', _rightScores[m], (v) => setState(() => _rightScores[m] = v))),
              ],
            )
          else
            _sideSelector(null, _singleScores[m], (v) => setState(() => _singleScores[m] = v)),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: pain,
                activeColor: AppColors.destructive,
                onChanged: (v) => setState(() => _pain[m] = v),
              ),
              const Text('ألم أثناء الحركة (يفرض درجة 0)',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _movementNotesCtrl[m],
            maxLines: 2,
            style: const TextStyle(color: AppColors.foreground, fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: pain ? 'ملاحظات الألم / موضعه' : 'ملاحظات (اختياري)',
              hintStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideSelector(String? label, int? value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          const SizedBox(height: 4),
        ],
        Row(
          children: List.generate(4, (i) {
            final selected = value == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary.withOpacity(0.18) : AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                  ),
                  alignment: Alignment.center,
                  child: Text('$i',
                      style: TextStyle(
                          color: selected ? AppColors.primary : AppColors.muted,
                          fontWeight: FontWeight.w800, fontSize: 14)),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
