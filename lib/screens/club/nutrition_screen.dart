import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import 'club_widgets.dart' show ClubErrorState;
import 'physio_session_screen.dart' show PhysioSessionScreen;

const List<String> _planTypes = ['training_day', 'match_day', 'travel_day', 'rest_day'];
const List<String> _complianceStatuses = ['compliant', 'partial', 'non_compliant'];

String _lbl(String key) {
  final v = AppLocalizations.get(key);
  return v != key ? v : key;
}

Color _complianceColor(String s) {
  switch (s) {
    case 'compliant': return AppColors.success;
    case 'partial': return AppColors.warning;
    case 'non_compliant': return AppColors.destructive;
    default: return AppColors.muted;
  }
}

class NutritionScreen extends StatefulWidget {
  const NutritionScreen({super.key, required this.playerId, required this.playerName});
  final String playerId;
  final String playerName;

  @override
  State<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends State<NutritionScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: getAppLanguage() == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.foreground, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(widget.playerName,
              style: const TextStyle(
                  color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 15)),
          actions: [
            // Cross-link to physio/massage sessions — only for roles that
            // manage both (doctor/admin), so their view of a player links
            // straight across specialties instead of two separate silos.
            if (canManagePhysioSessions)
              IconButton(
                icon: const Icon(Icons.spa_rounded, color: AppColors.foreground, size: 20),
                tooltip: _lbl('physio_sessions_title'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PhysioSessionScreen(
                    playerId: widget.playerId,
                    playerName: widget.playerName,
                  ),
                )),
              ),
          ],
          bottom: TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.muted,
            indicatorColor: AppColors.primary,
            labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            tabs: [
              Tab(text: _lbl('nutrition_tab_profile')),
              Tab(text: _lbl('nutrition_tab_plans')),
              Tab(text: _lbl('nutrition_tab_supplements')),
              Tab(text: _lbl('nutrition_tab_compliance')),
              Tab(text: _lbl('nutrition_tab_hydration')),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            _ProfileTab(playerId: widget.playerId),
            _PlansTab(playerId: widget.playerId),
            _SupplementsTab(playerId: widget.playerId),
            _ComplianceTab(playerId: widget.playerId),
            _HydrationHistoryTab(playerId: widget.playerId),
          ],
        ),
      ),
    );
  }
}

Widget _field(TextEditingController ctrl, String hint, {int maxLines = 1, TextInputType? keyboardType}) {
  return TextField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    style: const TextStyle(color: AppColors.foreground, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.muted),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

void _snack(BuildContext context, String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

Widget _emptyState(String msg) => Center(
      child: Text(msg, style: TextStyle(color: AppColors.muted, fontSize: 14)),
    );

// ── Profile tab ────────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({required this.playerId});
  final String playerId;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      _profile = await ApiService.getNutritionProfile(widget.playerId);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showEditSheet() {
    final allergiesCtrl = TextEditingController(text: (_profile?['allergies'] as String?) ?? '');
    final restrictionsCtrl = TextEditingController(text: (_profile?['dietary_restrictions'] as String?) ?? '');
    final calorieCtrl = TextEditingController(text: _profile?['calorie_target']?.toString() ?? '');
    final proteinCtrl = TextEditingController(text: _profile?['protein_target_g']?.toString() ?? '');
    final carbCtrl = TextEditingController(text: _profile?['carb_target_g']?.toString() ?? '');
    final fluidCtrl = TextEditingController(text: _profile?['fluid_target_ml']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: (_profile?['notes'] as String?) ?? '');

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 20, left: 20, right: 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_lbl('nutrition_profile_title'),
                  style: const TextStyle(
                      color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 16),
              _field(allergiesCtrl, _lbl('allergies'), maxLines: 2),
              const SizedBox(height: 10),
              _field(restrictionsCtrl, _lbl('dietary_restrictions'), maxLines: 2),
              const SizedBox(height: 10),
              _field(calorieCtrl, _lbl('calorie_target'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              _field(proteinCtrl, _lbl('protein_target_g'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              _field(carbCtrl, _lbl('carb_target_g'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              _field(fluidCtrl, _lbl('fluid_target_ml'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              _field(notesCtrl, _lbl('notes'), maxLines: 2),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final res = await ApiService.saveNutritionProfile(
                      playerId: widget.playerId,
                      allergies: allergiesCtrl.text.trim(),
                      dietaryRestrictions: restrictionsCtrl.text.trim(),
                      calorieTarget: int.tryParse(calorieCtrl.text.trim()),
                      proteinTargetG: int.tryParse(proteinCtrl.text.trim()),
                      carbTargetG: int.tryParse(carbCtrl.text.trim()),
                      fluidTargetMl: int.tryParse(fluidCtrl.text.trim()),
                      notes: notesCtrl.text.trim(),
                    );
                    if (!mounted) return;
                    if (res['success'] == true) {
                      Navigator.of(context).pop();
                      _load();
                    } else {
                      _snack(context, res['message']?.toString() ?? AppLocalizations.get('error_generic'));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.foreground,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(_lbl('save_btn'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, child: Text(label, style: TextStyle(color: AppColors.muted, fontSize: 11.5))),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: AppColors.foreground, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_loadError) {
      return ClubErrorState(
        title: AppLocalizations.get('error_load_failed'),
        description: AppLocalizations.get('error_check_internet'),
        retryLabel: AppLocalizations.get('retry_btn'),
        onRetry: _load,
      );
    }
    final p = _profile;
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(_lbl('allergies'), (p?['allergies'] as String?) ?? '-'),
                _row(_lbl('dietary_restrictions'), (p?['dietary_restrictions'] as String?) ?? '-'),
                _row(_lbl('calorie_target'), p?['calorie_target']?.toString() ?? '-'),
                _row(_lbl('protein_target_g'), p?['protein_target_g']?.toString() ?? '-'),
                _row(_lbl('carb_target_g'), p?['carb_target_g']?.toString() ?? '-'),
                _row(_lbl('fluid_target_ml'), p?['fluid_target_ml']?.toString() ?? '-'),
                if ((p?['notes'] as String?)?.isNotEmpty == true) ...[
                  const Divider(color: AppColors.border, height: 20),
                  Text(p!['notes'], style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (canManageNutrition)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: _showEditSheet,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(_lbl('nutrition_edit_profile'),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Day plans tab ────────────────────────────────────────────────────────────

class _PlansTab extends StatefulWidget {
  const _PlansTab({required this.playerId});
  final String playerId;

  @override
  State<_PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<_PlansTab> {
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      _plans = await ApiService.getNutritionPlans(widget.playerId);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic>? _planFor(String type) {
    for (final p in _plans) {
      if (p['plan_type'] == type) return p;
    }
    return null;
  }

  void _showEditSheet(String planType) {
    final existing = _planFor(planType);
    final calorieCtrl = TextEditingController(text: existing?['calorie_target']?.toString() ?? '');
    final proteinCtrl = TextEditingController(text: existing?['protein_target_g']?.toString() ?? '');
    final carbCtrl = TextEditingController(text: existing?['carb_target_g']?.toString() ?? '');
    final fluidCtrl = TextEditingController(text: existing?['fluid_target_ml']?.toString() ?? '');
    final beforeCtrl = TextEditingController(text: (existing?['hydration_before'] as String?) ?? '');
    final duringCtrl = TextEditingController(text: (existing?['hydration_during'] as String?) ?? '');
    final afterCtrl = TextEditingController(text: (existing?['hydration_after'] as String?) ?? '');
    final notesCtrl = TextEditingController(text: (existing?['notes'] as String?) ?? '');

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 20, left: 20, right: 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_lbl('plan_type_$planType'),
                  style: const TextStyle(
                      color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 16),
              _field(calorieCtrl, _lbl('calorie_target'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              _field(proteinCtrl, _lbl('protein_target_g'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              _field(carbCtrl, _lbl('carb_target_g'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              _field(fluidCtrl, _lbl('fluid_target_ml'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              _field(beforeCtrl, _lbl('hydration_before')),
              const SizedBox(height: 10),
              _field(duringCtrl, _lbl('hydration_during')),
              const SizedBox(height: 10),
              _field(afterCtrl, _lbl('hydration_after')),
              const SizedBox(height: 10),
              _field(notesCtrl, _lbl('notes'), maxLines: 2),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final res = await ApiService.saveNutritionDayPlan(
                      playerId: widget.playerId,
                      planType: planType,
                      calorieTarget: int.tryParse(calorieCtrl.text.trim()),
                      proteinTargetG: int.tryParse(proteinCtrl.text.trim()),
                      carbTargetG: int.tryParse(carbCtrl.text.trim()),
                      fluidTargetMl: int.tryParse(fluidCtrl.text.trim()),
                      hydrationBefore: beforeCtrl.text.trim(),
                      hydrationDuring: duringCtrl.text.trim(),
                      hydrationAfter: afterCtrl.text.trim(),
                      notes: notesCtrl.text.trim(),
                    );
                    if (!mounted) return;
                    if (res['success'] == true) {
                      Navigator.of(context).pop();
                      _load();
                    } else {
                      _snack(context, res['message']?.toString() ?? AppLocalizations.get('error_generic'));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.foreground,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(_lbl('save_btn'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_loadError) {
      return ClubErrorState(
        title: AppLocalizations.get('error_load_failed'),
        description: AppLocalizations.get('error_check_internet'),
        retryLabel: AppLocalizations.get('retry_btn'),
        onRetry: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _planTypes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final type = _planTypes[i];
          final plan = _planFor(type);
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: canManageNutrition ? () => _showEditSheet(type) : null,
            child: Container(
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
                    children: [
                      Expanded(
                        child: Text(_lbl('plan_type_$type'),
                            style: const TextStyle(
                                color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      if (canManageNutrition)
                        const Icon(Icons.edit_rounded, color: AppColors.muted, size: 16),
                    ],
                  ),
                  if (plan == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_lbl('no_plan_set'), style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    )
                  else ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      children: [
                        if (plan['calorie_target'] != null)
                          Text('${plan['calorie_target']} ${_lbl('kcal_unit')}',
                              style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                        if (plan['protein_target_g'] != null)
                          Text('${plan['protein_target_g']}g ${_lbl('protein_short')}',
                              style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                        if (plan['carb_target_g'] != null)
                          Text('${plan['carb_target_g']}g ${_lbl('carb_short')}',
                              style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                        if (plan['fluid_target_ml'] != null)
                          Text('${plan['fluid_target_ml']}ml ${_lbl('fluid_short')}',
                              style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Supplements tab ──────────────────────────────────────────────────────────

class _SupplementsTab extends StatefulWidget {
  const _SupplementsTab({required this.playerId});
  final String playerId;

  @override
  State<_SupplementsTab> createState() => _SupplementsTabState();
}

class _SupplementsTabState extends State<_SupplementsTab> {
  List<Map<String, dynamic>> _supplements = [];
  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      _supplements = await ApiService.getSupplements(widget.playerId);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showAddSheet() {
    final nameCtrl = TextEditingController();
    final dosageCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 20, left: 20, right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_lbl('new_supplement'),
                style: const TextStyle(
                    color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 16),
            _field(nameCtrl, _lbl('supplement_name')),
            const SizedBox(height: 10),
            _field(dosageCtrl, _lbl('dosage')),
            const SizedBox(height: 10),
            _field(reasonCtrl, _lbl('reason'), maxLines: 2),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final res = await ApiService.addSupplement(
                    playerId: widget.playerId,
                    supplementName: nameCtrl.text.trim(),
                    dosage: dosageCtrl.text.trim(),
                    reason: reasonCtrl.text.trim(),
                  );
                  if (!mounted) return;
                  if (res['success'] == true) {
                    Navigator.of(context).pop();
                    _load();
                  } else {
                    _snack(context, res['message']?.toString() ?? AppLocalizations.get('error_generic'));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.foreground,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(_lbl('new_supplement'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signoff(Map<String, dynamic> s) async {
    String? asRole;
    if (isOrgAdmin) {
      asRole = await showDialog<String>(
        context: context,
        builder: (_) => SimpleDialog(
          backgroundColor: AppColors.card,
          title: Text(_lbl('signoff_as'), style: const TextStyle(color: AppColors.foreground, fontSize: 15)),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'doctor'),
              child: Text(_lbl('role_doctor'), style: const TextStyle(color: AppColors.foreground)),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'nutritionist'),
              child: Text(_lbl('role_nutritionist'), style: const TextStyle(color: AppColors.foreground)),
            ),
          ],
        ),
      );
      if (asRole == null) return;
    }
    final res = await ApiService.signoffSupplement(id: s['id'].toString(), asRole: asRole);
    if (!mounted) return;
    if (res['success'] == true) {
      _load();
    } else {
      _snack(context, res['message']?.toString() ?? AppLocalizations.get('error_generic'));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_loadError) {
      return ClubErrorState(
        title: AppLocalizations.get('error_load_failed'),
        description: AppLocalizations.get('error_check_internet'),
        retryLabel: AppLocalizations.get('retry_btn'),
        onRetry: _load,
      );
    }
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          backgroundColor: AppColors.card,
          child: _supplements.isEmpty
              ? ListView(children: [SizedBox(height: 200, child: _emptyState(_lbl('no_supplements')))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _supplements.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = _supplements[i];
                    final doctorOk = s['doctor_signoff'] == true;
                    final nutritionistOk = s['nutritionist_signoff'] == true;
                    final approved = s['status'] == 'approved';
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: (approved ? AppColors.success : AppColors.warning).withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(s['supplement_name'] ?? '',
                                    style: const TextStyle(
                                        color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: (approved ? AppColors.success : AppColors.warning).withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(_lbl('supplement_status_${s['status']}'),
                                    style: TextStyle(
                                        color: approved ? AppColors.success : AppColors.warning,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                          if ((s['dosage'] as String?)?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(s['dosage'], style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                            ),
                          if ((s['reason'] as String?)?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(s['reason'],
                                  style: const TextStyle(color: AppColors.foreground, fontSize: 12)),
                            ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(doctorOk ? Icons.check_circle_rounded : Icons.circle_outlined,
                                  color: doctorOk ? AppColors.success : AppColors.muted, size: 14),
                              const SizedBox(width: 4),
                              Text(_lbl('role_doctor'), style: TextStyle(color: AppColors.muted, fontSize: 11)),
                              const SizedBox(width: 14),
                              Icon(nutritionistOk ? Icons.check_circle_rounded : Icons.circle_outlined,
                                  color: nutritionistOk ? AppColors.success : AppColors.muted, size: 14),
                              const SizedBox(width: 4),
                              Text(_lbl('role_nutritionist'), style: TextStyle(color: AppColors.muted, fontSize: 11)),
                              const Spacer(),
                              if (!approved && canManageNutrition)
                                TextButton(
                                  onPressed: () => _signoff(s),
                                  child: Text(_lbl('sign_off'),
                                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (canManageNutrition)
          Positioned(
            right: 16, bottom: 16,
            child: FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: _showAddSheet,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

// ── Compliance tab ───────────────────────────────────────────────────────────

class _ComplianceTab extends StatefulWidget {
  const _ComplianceTab({required this.playerId});
  final String playerId;

  @override
  State<_ComplianceTab> createState() => _ComplianceTabState();
}

class _ComplianceTabState extends State<_ComplianceTab> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      _logs = await ApiService.getNutritionCompliance(widget.playerId);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showLogSheet() {
    String status = 'compliant';
    final notesCtrl = TextEditingController();
    final today = DateTime.now().toIso8601String().split('T').first;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 20, left: 20, right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_lbl('log_compliance')} — $today',
                  style: const TextStyle(
                      color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: status,
                    isExpanded: true,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                    items: _complianceStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(_lbl('compliance_status_$s'))))
                        .toList(),
                    onChanged: (v) { if (v != null) setSheetState(() => status = v); },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _field(notesCtrl, _lbl('notes'), maxLines: 2),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final res = await ApiService.logNutritionCompliance(
                      playerId: widget.playerId,
                      logDate: today,
                      status: status,
                      notes: notesCtrl.text.trim(),
                    );
                    if (!mounted) return;
                    if (res['success'] == true) {
                      Navigator.of(context).pop();
                      _load();
                    } else {
                      _snack(context, res['message']?.toString() ?? AppLocalizations.get('error_generic'));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.foreground,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(_lbl('save_btn'),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_loadError) {
      return ClubErrorState(
        title: AppLocalizations.get('error_load_failed'),
        description: AppLocalizations.get('error_check_internet'),
        retryLabel: AppLocalizations.get('retry_btn'),
        onRetry: _load,
      );
    }
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          backgroundColor: AppColors.card,
          child: _logs.isEmpty
              ? ListView(children: [SizedBox(height: 200, child: _emptyState(_lbl('no_compliance_logs')))])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _logs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final l = _logs[i];
                    final status = (l['status'] ?? '').toString();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _complianceColor(status).withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          Text((l['log_date'] as String?) ?? '',
                              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 12)),
                          const SizedBox(width: 10),
                          if ((l['notes'] as String?)?.isNotEmpty == true)
                            Expanded(
                              child: Text(l['notes'], style: TextStyle(color: AppColors.muted, fontSize: 11)),
                            )
                          else
                            const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _complianceColor(status).withOpacity(0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(_lbl('compliance_status_$status'),
                                style: TextStyle(color: _complianceColor(status), fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (canManageNutrition)
          Positioned(
            right: 16, bottom: 16,
            child: FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: _showLogSheet,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

// Read-only — hydration is logged by the player themselves
// (lib/screens/player/my_nutrition_screen.dart's hydration tab); staff just
// monitor it here alongside fluid_target_ml on the profile tab.
class _HydrationHistoryTab extends StatefulWidget {
  const _HydrationHistoryTab({required this.playerId});
  final String playerId;

  @override
  State<_HydrationHistoryTab> createState() => _HydrationHistoryTabState();
}

class _HydrationHistoryTabState extends State<_HydrationHistoryTab> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      _logs = await ApiService.getPlayerHydrationLogs(widget.playerId);
    } catch (_) {
      if (mounted) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_loadError) {
      return ClubErrorState(
        title: AppLocalizations.get('error_load_failed'),
        description: AppLocalizations.get('error_check_internet'),
        retryLabel: AppLocalizations.get('retry_btn'),
        onRetry: _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      child: _logs.isEmpty
          ? ListView(children: [SizedBox(height: 200, child: _emptyState(_lbl('no_hydration_logs')))])
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _logs.length,
              itemBuilder: (_, i) {
                final l = _logs[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${l['log_date']}', style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                      Text('${l['amount_ml']} ml',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
