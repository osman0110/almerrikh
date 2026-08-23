import 'package:flutter/material.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import 'player_dashboard.dart' show PlayerShell, PlayerPageHeader;

const List<String> _planTypes = ['training_day', 'match_day', 'travel_day', 'rest_day'];

String _lbl(String key) {
  final v = AppLocalizations.get(key);
  return v != key ? v : key;
}

Widget _emptyState(String msg) => Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Text(msg, style: TextStyle(color: AppColors.muted, fontSize: 14)),
      ),
    );

/// Read-only view of the player's own nutrition profile, day plans, and supplements.
class MyNutritionScreen extends StatefulWidget {
  const MyNutritionScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  State<MyNutritionScreen> createState() => _MyNutritionScreenState();
}

class _MyNutritionScreenState extends State<MyNutritionScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTabIndex,
  );

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIndependent =
        currentPlayerType == PlayerType.independent || currentPlayerType == null;
    return PlayerShell(
      currentIndex: isIndependent ? 1 : 3,
      child: Directionality(
        textDirection: getAppLanguage() == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Column(
          children: [
            PlayerPageHeader(title: _lbl('nutrition_title')),
            Material(
              color: AppColors.background,
              child: TabBar(
                controller: _tab,
                isScrollable: true,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.muted,
                indicatorColor: AppColors.primary,
                labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                tabs: [
                  Tab(icon: const Icon(Icons.person_outline_rounded, size: 18), text: _lbl('nutrition_tab_profile')),
                  Tab(icon: const Icon(Icons.restaurant_menu_rounded, size: 18), text: _lbl('nutrition_tab_plans')),
                  Tab(icon: const Icon(Icons.medication_rounded, size: 18), text: _lbl('nutrition_tab_supplements')),
                  Tab(icon: const Icon(Icons.water_drop_rounded, size: 18), text: _lbl('nutrition_tab_hydration')),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: const [
                  _MyProfileTab(),
                  _MyPlansTab(),
                  _MySupplementsTab(),
                  _MyHydrationTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyProfileTab extends StatefulWidget {
  const _MyProfileTab();

  @override
  State<_MyProfileTab> createState() => _MyProfileTabState();
}

class _MyProfileTabState extends State<_MyProfileTab> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _profile = await ApiService.getMyNutritionProfile();
    if (mounted) setState(() => _loading = false);
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 150, child: Text(label, style: TextStyle(color: AppColors.muted, fontSize: 11.5))),
            Expanded(
              child: Text(value,
                  style: const TextStyle(color: AppColors.foreground, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    final p = _profile;
    if (p == null) return _emptyState(_lbl('no_plan_set'));
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
                _row(_lbl('allergies'), (p['allergies'] as String?) ?? '-'),
                _row(_lbl('dietary_restrictions'), (p['dietary_restrictions'] as String?) ?? '-'),
                _row(_lbl('calorie_target'), p['calorie_target']?.toString() ?? '-'),
                _row(_lbl('protein_target_g'), p['protein_target_g']?.toString() ?? '-'),
                _row(_lbl('carb_target_g'), p['carb_target_g']?.toString() ?? '-'),
                _row(_lbl('fluid_target_ml'), p['fluid_target_ml']?.toString() ?? '-'),
                if ((p['notes'] as String?)?.isNotEmpty == true) ...[
                  const Divider(color: AppColors.border, height: 20),
                  Text(p['notes'], style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyPlansTab extends StatefulWidget {
  const _MyPlansTab();

  @override
  State<_MyPlansTab> createState() => _MyPlansTabState();
}

class _MyPlansTabState extends State<_MyPlansTab> {
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _plans = await ApiService.getMyNutritionPlans();
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic>? _planFor(String type) {
    for (final p in _plans) {
      if (p['plan_type'] == type) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
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
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_lbl('plan_type_$type'),
                    style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
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
                  if ((plan['hydration_before'] as String?)?.isNotEmpty == true ||
                      (plan['hydration_during'] as String?)?.isNotEmpty == true ||
                      (plan['hydration_after'] as String?)?.isNotEmpty == true) ...[
                    const Divider(color: AppColors.border, height: 18),
                    if ((plan['hydration_before'] as String?)?.isNotEmpty == true)
                      Text('${_lbl('hydration_before')}: ${plan['hydration_before']}',
                          style: TextStyle(color: AppColors.foreground, fontSize: 11.5)),
                    if ((plan['hydration_during'] as String?)?.isNotEmpty == true)
                      Text('${_lbl('hydration_during')}: ${plan['hydration_during']}',
                          style: TextStyle(color: AppColors.foreground, fontSize: 11.5)),
                    if ((plan['hydration_after'] as String?)?.isNotEmpty == true)
                      Text('${_lbl('hydration_after')}: ${plan['hydration_after']}',
                          style: TextStyle(color: AppColors.foreground, fontSize: 11.5)),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MySupplementsTab extends StatefulWidget {
  const _MySupplementsTab();

  @override
  State<_MySupplementsTab> createState() => _MySupplementsTabState();
}

class _MySupplementsTabState extends State<_MySupplementsTab> {
  List<Map<String, dynamic>> _supplements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _supplements = await ApiService.getMySupplements();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_supplements.isEmpty) return _emptyState(_lbl('no_supplements'));
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _supplements.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final s = _supplements[i];
          final approved = s['status'] == 'approved';
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: (approved ? AppColors.success : AppColors.warning).withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s['supplement_name'] ?? '',
                          style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
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
                    child: Text(s['reason'], style: const TextStyle(color: AppColors.foreground, fontSize: 12)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MyHydrationTab extends StatefulWidget {
  const _MyHydrationTab();

  @override
  State<_MyHydrationTab> createState() => _MyHydrationTabState();
}

class _MyHydrationTabState extends State<_MyHydrationTab> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _saving = false;
  final _amountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs = await ApiService.getMyHydrationLogs();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) return;
    setState(() => _saving = true);
    final res = await ApiService.logMyHydration(amountMl: amount);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      _amountCtrl.clear();
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res['message']?.toString() ??
            res['error']?.toString() ??
            AppLocalizations.get('error_generic')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    return ListView(
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
              Text(_lbl('hydration_log_today'),
                  style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _lbl('hydration_amount_hint'),
                      hintStyle: const TextStyle(color: AppColors.muted),
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.foreground,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(_lbl('hydration_log_btn')),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(_lbl('hydration_history_label'),
            style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 8),
        if (_logs.isEmpty)
          _emptyState(_lbl('no_hydration_logs'))
        else
          ..._logs.map((l) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${l['log_date']}', style: const TextStyle(color: AppColors.foreground, fontSize: 12)),
                    Text('${l['amount_ml']} ml',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
              )),
      ],
    );
  }
}
