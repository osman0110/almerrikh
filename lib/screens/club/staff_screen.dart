import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api_service.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../widgets/common_widgets.dart';
import 'club_dashboard.dart';

// Access codes remain reusable until they are deactivated or deleted.
//
// 'massage_specialist' is intentionally NOT offered here anymore — at this
// club physiotherapy and massage are the same job, so 'physiotherapist' is
// the single combined role for new invites (see role_physiotherapist /
// role_massage_specialist, which now share one label: "Physiotherapy &
// Massage"). Existing 'massage_specialist' accounts still work — they keep
// full access via isMassageRole/canManagePhysioSessions and land on the same
// shared dashboard (see _orgHomePage() in main.dart) — this list only
// controls what NEW codes can be created.
const List<String> _invitableAccountTypes = [
  'player',
  'admin',
  'coach',
  'tactical_coach',
  'performance_manager',
  'doctor',
  'physiotherapist',
  'nutritionist',
  'analyst',
];

String _roleLabel(String role) =>
    AppLocalizations.get('role_$role') != 'role_$role'
        ? AppLocalizations.get('role_$role')
        : role;

Color _roleColor(String role) {
  switch (role) {
    case 'owner':
    case 'admin':
      return AppColors.maroon;
    case 'coach':
    case 'tactical_coach':
    case 'performance_manager':
      return AppColors.coachAccent;
    case 'doctor':
    case 'physiotherapist':
    case 'massage_specialist':
      return AppColors.success;
    case 'nutritionist':
      return AppColors.warning;
    case 'player':
      return AppColors.primary;
    default:
      return AppColors.risk; // analyst
  }
}

class ClubStaffScreen extends StatefulWidget {
  const ClubStaffScreen({super.key});

  @override
  State<ClubStaffScreen> createState() => _ClubStaffScreenState();
}

class _ClubStaffScreenState extends State<ClubStaffScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _codes = [];
  List<ClubTeam> _teams = [];
  bool _loading = true;
  bool _loadError = false;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    final results = await Future.wait([
      ApiService.getClubStaff(),
      ApiService.getClubAccessCodes(),
      ClubService().getTeams(),
    ]);
    if (!mounted) return;
    final staff = results[0] as List<Map<String, dynamic>>?;
    final codes = results[1] as List<Map<String, dynamic>>?;
    final teams = results[2] as List<ClubTeam>;
    setState(() {
      if (staff != null) _staff = staff;
      if (codes != null) _codes = codes;
      _teams = teams;
      _loadError = staff == null || codes == null;
      _loading = false;
    });
  }

  Future<void> _assignTeam(Map<String, dynamic> member) async {
    if (_teams.isEmpty) {
      _snack(AppLocalizations.get('team_not_assigned'));
      return;
    }
    final selected = await showModalBottomSheet<ClubTeam>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.get('assign_team_title'),
                style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              for (final team in _teams)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.groups_rounded,
                    color: AppColors.coachAccent,
                  ),
                  title: Text(
                    team.name,
                    style: const TextStyle(color: AppColors.foreground),
                  ),
                  onTap: () => Navigator.pop(sheetContext, team),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    final response = await ApiService.assignStaffTeam(
      staffId: member['id'].toString(),
      teamId: selected.id,
    );
    if (!mounted) return;
    if (response['success'] == true) {
      await _load();
    } else {
      _snack(response['error']?.toString() ?? AppLocalizations.get('error_generic'));
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Future<void> _createCode(String accountType, String? note) async {
    final res = await ApiService.createAccessCode(accountType: accountType, note: note);
    if (!mounted) return;
    if (res['code'] != null) {
      // Refresh the codes list right away — don't rely on the reveal sheet's
      // "Done" button being tapped (swiping it away skipped the reload).
      await _load();
      if (!mounted) return;
      Navigator.of(context).pop();
      _showCodeSheet(res['code'] as String, accountType);
    } else {
      final err = res['error']?.toString() ?? AppLocalizations.get('error_generic');
      _snack(err);
    }
  }

  Future<void> _toggleCode(Map<String, dynamic> c) async {
    final code = (c['code'] ?? '').toString();
    final nextActive =
        !(c['is_active'] == true || c['is_active'].toString() == '1');
    final res = await ApiService.toggleAccessCode(code: code, isActive: nextActive);
    if (!mounted) return;
    if (res['success'] == true) {
      await _load();
    } else {
      _snack(res['error']?.toString() ?? AppLocalizations.get('error_generic'));
    }
  }

  Future<void> _deleteCode(Map<String, dynamic> c) async {
    final code = (c['code'] ?? '').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(AppLocalizations.get('delete_code_confirm'),
            style: const TextStyle(color: AppColors.foreground, fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.get('delete_label'),
                style: const TextStyle(color: AppColors.destructive)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await ApiService.deleteAccessCode(code);
    if (!mounted) return;
    if (res['success'] == true) {
      _snack(AppLocalizations.get('code_deleted'));
      _load();
    } else {
      _snack(res['error']?.toString() ?? AppLocalizations.get('error_generic'));
    }
  }

  void _showCodeSheet(String code, String accountType) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_roleLabel(accountType),
                style: TextStyle(
                    color: _roleColor(accountType),
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: code));
                _snack(AppLocalizations.format('code_copied', {'code': code}));
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(code,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(AppLocalizations.get('code_reusable_hint'),
                style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _load();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.foreground,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(AppLocalizations.get('done_label'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateSheet() {
    String selectedType = 'player';
    final noteCtrl = TextEditingController();
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
              Text(AppLocalizations.get('create_code_title'),
                  style: const TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
              const SizedBox(height: 4),
              Text(AppLocalizations.get('code_reusable_hint'),
                  style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4)),
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
                    value: selectedType,
                    isExpanded: true,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(
                        color: AppColors.foreground, fontSize: 14),
                    items: _invitableAccountTypes
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(_roleLabel(r)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setSheetState(() => selectedType = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteCtrl,
                style: const TextStyle(color: AppColors.foreground, fontSize: 14),
                decoration: InputDecoration(
                  hintText: AppLocalizations.get('note_optional'),
                  hintStyle: TextStyle(color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => _createCode(
                      selectedType,
                      noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.foreground,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(AppLocalizations.get('create_code_btn'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(Map<String, dynamic> member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(AppLocalizations.get('remove_staff_confirm'),
            style: const TextStyle(color: AppColors.foreground, fontSize: 15)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.get('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.get('remove_label'),
                style: const TextStyle(color: AppColors.destructive)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await ApiService.removeStaffMember(member['id'].toString());
    if (!mounted) return;
    if (res['success'] == true) {
      _snack(AppLocalizations.get('staff_removed'));
      _load();
    } else {
      _snack(res['error']?.toString() ?? AppLocalizations.get('error_generic'));
    }
  }

  Widget _buildStaffTab() {
    if (_staff.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.groups_rounded, color: AppColors.muted, size: 48),
            const SizedBox(height: 12),
            Text(AppLocalizations.get('no_staff_yet'),
                style: TextStyle(color: AppColors.muted, fontSize: 14)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(AppLocalizations.get('staff_hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _staff.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final m = _staff[i];
        final role = (m['staff_role'] ?? '').toString();
        final isOwner = role == 'owner';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _roleColor(role).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_rounded, color: _roleColor(role), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((m['name'] ?? '').toString(),
                        style: const TextStyle(
                            color: AppColors.foreground,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    Text((m['email'] ?? '').toString(),
                        style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    Text(
                      (m['team_name'] ?? '').toString().isNotEmpty
                          ? m['team_name'].toString()
                          : AppLocalizations.get('team_not_assigned'),
                      style: TextStyle(color: AppColors.muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _roleColor(role).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_roleLabel(role),
                    style: TextStyle(
                        color: _roleColor(role),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              if (role == 'coach')
                IconButton(
                  tooltip: AppLocalizations.get('assign_team_title'),
                  icon: const Icon(
                    Icons.group_work_outlined,
                    color: AppColors.coachAccent,
                    size: 18,
                  ),
                  onPressed: () => _assignTeam(m),
                ),
              if (!isOwner)
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.destructive, size: 18),
                  onPressed: () => _confirmRemove(m),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCodesTab() {
    if (_codes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.vpn_key_outlined, color: AppColors.muted, size: 48),
            const SizedBox(height: 12),
            Text(AppLocalizations.get('no_codes_yet'),
                style: TextStyle(color: AppColors.muted, fontSize: 14)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _showCreateSheet,
              child: Text(AppLocalizations.get('create_first_code'),
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _codes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = _codes[i];
        final code = (c['code'] ?? '').toString();
        final type = (c['account_type'] ?? '').toString();
        final note = c['note'] as String?;
        final active =
            c['is_active'] == true || c['is_active'].toString() == '1';
        final invitationStatus = active ? 'active' : 'revoked';
        final useCount = (c['use_count'] as num?)?.toInt() ?? 0;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: active ? _roleColor(type).withOpacity(0.3) : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: code));
                      _snack(AppLocalizations.format('code_copied', {'code': code}));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: active
                            ? _roleColor(type).withOpacity(0.10)
                            : AppColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(code,
                          style: TextStyle(
                              color: active ? _roleColor(type) : AppColors.muted,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_roleLabel(type),
                            style: TextStyle(
                                color: _roleColor(type),
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                        Text(
                          AppLocalizations.get(
                            'invite_status_$invitationStatus',
                          ),
                          style: TextStyle(
                            color: active ? AppColors.success : AppColors.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (note != null && note.isNotEmpty)
                          Text(note,
                              style: TextStyle(color: AppColors.muted, fontSize: 11)),
                        Text(
                          AppLocalizations.format('code_use_count', {'count': '$useCount'}),
                          style: TextStyle(color: AppColors.muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: active,
                    activeColor: AppColors.primary,
                    onChanged: (_) => _toggleCode(c),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.destructive, size: 20),
                    onPressed: () => _deleteCode(c),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isOrgAdmin) return const RoleAccessDeniedPage();
    return ClubShell(
      currentIndex: 6,
      child: Directionality(
        textDirection:
            getAppLanguage() == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppColors.foreground, size: 20),
            onPressed: () => Navigator.canPop(context)
                ? Navigator.pop(context)
                : ClubShell.go(context, '/club'),
          ),
          title: Text(AppLocalizations.get('staff_title'),
              style: const TextStyle(
                  color: AppColors.foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 17)),
          actions: [
            TextButton.icon(
              onPressed: _showCreateSheet,
              icon: const Icon(Icons.add, color: AppColors.primary, size: 18),
              label: Text(AppLocalizations.get('new_btn'),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700)),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.foreground,
            unselectedLabelColor: AppColors.muted,
            tabs: [
              Tab(text: AppLocalizations.get('staff_tab')),
              Tab(text: AppLocalizations.get('codes_tab')),
            ],
          ),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : _loadError
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.cloud_off_rounded,
                              color: AppColors.destructive, size: 34),
                          const SizedBox(height: 10),
                          Text(
                            AppLocalizations.get('staff_load_failed'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppColors.foreground),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(AppLocalizations.get('retry')),
                          ),
                        ],
                      ),
                    ),
                  )
            : TabBarView(
                controller: _tabController,
                children: [
                  RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    backgroundColor: AppColors.card,
                    child: _buildStaffTab(),
                  ),
                  RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    backgroundColor: AppColors.card,
                    child: _buildCodesTab(),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}
