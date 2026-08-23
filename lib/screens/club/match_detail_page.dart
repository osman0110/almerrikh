import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:printing/printing.dart';
import '../../app_colors.dart';
import '../../app_localizations.dart';
import '../../app_config.dart' show kWebBase;
import '../../app_state.dart';
import '../../models/club_models.dart';
import '../../services/club_service.dart';
import '../../services/report_service.dart';
import '../../utils/app_logger.dart';
import 'match_form_page.dart';
import 'coach_evaluation_sheet.dart';
import 'injury_case_screen.dart';

class MatchDetailPage extends StatefulWidget {
  const MatchDetailPage({super.key, required this.matchId});
  final String matchId;

  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  MatchModel? _match;
  List<ClubPlayer> _players = [];
  List<CoachEvaluation> _evaluations = [];
  List<MatchCard> _cards = [];
  List<MatchParticipation> _participations = [];
  bool _loading = true;
  bool _loadError = false;
  bool _clockBusy = false;
  DateTime _clockSnapshotAt = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_match?.clockRunning == true ||
          _participations.any((p) => p.clockRunning))) {
        setState(() {});
      }
    });
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  int _liveSeconds(int storedSeconds, bool running) => storedSeconds +
      (running ? DateTime.now().difference(_clockSnapshotAt).inSeconds : 0);

  String _formatClock(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final secs = safe % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      final match = await ClubService().getMatch(widget.matchId);
      if (!mounted || match == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      setState(() => _match = match);

      final futures = <Future>[
        ...match.playerIds.map((pid) => ClubService().getPlayer(pid)),
        ClubService().getEvaluations(matchId: widget.matchId),
      ];
      final results = await Future.wait(futures);

      if (!mounted) return;
      _players = results
          .sublist(0, match.playerIds.length)
          .whereType<ClubPlayer>()
          .toList();
      _evaluations = results.last as List<CoachEvaluation>;
      _cards = await ClubService().getMatchCards(widget.matchId);
      _participations = match.participations;
      _clockSnapshotAt = DateTime.now();
    } catch (e) {
      AppLogger.e('MatchDetail', 'Failed to load match ${widget.matchId}', e);
      if (mounted && _match == null) setState(() => _loadError = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _editScore() async {
    final m = _match;
    if (m == null) return;
    final ourCtrl = TextEditingController(text: m.ourScore?.toString() ?? '');
    final opponentCtrl = TextEditingController(text: m.opponentScore?.toString() ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.border)),
        title: Text(AppLocalizations.get('match_score_label'),
            style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w900)),
        content: Row(mainAxisSize: MainAxisSize.min, children: [
          Expanded(
            child: TextField(
              controller: ourCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.foreground),
              decoration: InputDecoration(
                labelText: AppLocalizations.get('match_our_score_label'),
                labelStyle: const TextStyle(color: AppColors.muted),
                enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Text(':', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: opponentCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.foreground),
              decoration: InputDecoration(
                labelText: AppLocalizations.get('match_opponent_score_label'),
                labelStyle: const TextStyle(color: AppColors.muted),
                enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border)),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.get('cancel'),
                style: const TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.get('save_btn'),
                style: const TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    m.ourScore = int.tryParse(ourCtrl.text.trim());
    m.opponentScore = int.tryParse(opponentCtrl.text.trim());
    final id = await ClubService().saveMatch(m);
    if (!mounted) return;
    if (id != null) {
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.get('match_save_failed'))));
    }
  }

  Future<void> _addCard(String playerId, String cardType) async {
    final liveMinute = _match == null
        ? 0
        : _liveSeconds(_match!.elapsedSeconds, _match!.clockRunning) ~/ 60;
    final minuteCtrl = TextEditingController(
        text: _match?.clockRunning == true ? '$liveMinute' : '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.border)),
        title: Text(
            cardType == 'yellow'
                ? AppLocalizations.get('yellow_card_label')
                : AppLocalizations.get('red_card_label'),
            style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w900)),
        content: TextField(
          controller: minuteCtrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.foreground),
          decoration: InputDecoration(
            labelText: AppLocalizations.get('card_minute_label'),
            labelStyle: const TextStyle(color: AppColors.muted),
            enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.border)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.get('cancel'),
                style: const TextStyle(color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(AppLocalizations.get('save_btn'),
                style: const TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final updated = [
      ..._cards,
      MatchCard(
        id: 0,
        matchId: widget.matchId,
        playerId: playerId,
        cardType: cardType,
        minute: int.tryParse(minuteCtrl.text.trim()),
      ),
    ];
    final ok = await ClubService().saveMatchCards(widget.matchId, updated);
    if (!mounted) return;
    if (ok) {
      setState(() => _cards = updated);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.get('match_save_failed'))));
    }
  }

  Future<void> _editParticipation(ClubPlayer player) async {
    final existing = _participations.where((p) => p.playerId == player.id).firstOrNull;
    final starter = ValueNotifier<bool>(existing?.starter ?? false);
    final played = ValueNotifier<bool>(existing?.played ?? true);
    final goalsCtrl = TextEditingController(text: '${existing?.goals ?? 0}');
    final assistsCtrl = TextEditingController(text: '${existing?.assists ?? 0}');
    final minutesCtrl = TextEditingController(
        text: '${existing?.minutesPlayed ?? _match!.playerMinutes[player.id] ?? 0}');
    final ratingCtrl = TextEditingController(text: existing?.rating?.toString() ?? '');
    final injured = ValueNotifier<bool>(existing?.injured ?? false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.border)),
          title: Text(player.fullName,
              style: const TextStyle(color: AppColors.foreground, fontWeight: FontWeight.w900)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AppLocalizations.get('match_starter_label'),
                    style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                value: starter.value,
                activeColor: AppColors.primary,
                onChanged: (v) => setDialogState(() => starter.value = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AppLocalizations.get('match_played_label'),
                    style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                value: played.value,
                activeColor: AppColors.primary,
                onChanged: (v) => setDialogState(() => played.value = v),
              ),
              TextField(
                controller: minutesCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.foreground),
                decoration: InputDecoration(
                    labelText: AppLocalizations.get('match_minutes_label'),
                    labelStyle: const TextStyle(color: AppColors.muted)),
              ),
              TextField(
                controller: goalsCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.foreground),
                decoration: InputDecoration(
                    labelText: AppLocalizations.get('match_goals_label'),
                    labelStyle: const TextStyle(color: AppColors.muted)),
              ),
              TextField(
                controller: assistsCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.foreground),
                decoration: InputDecoration(
                    labelText: AppLocalizations.get('match_assists_label'),
                    labelStyle: const TextStyle(color: AppColors.muted)),
              ),
              TextField(
                controller: ratingCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.foreground),
                decoration: InputDecoration(
                    labelText: AppLocalizations.get('match_rating_label'),
                    labelStyle: const TextStyle(color: AppColors.muted)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AppLocalizations.get('match_injured_label'),
                    style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
                value: injured.value,
                activeColor: AppColors.destructive,
                onChanged: (v) => setDialogState(() => injured.value = v),
              ),
            ],
            ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(AppLocalizations.get('cancel'),
                  style: const TextStyle(color: AppColors.muted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(AppLocalizations.get('save_btn'),
                  style: const TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final updated = MatchParticipation(
      playerId: player.id,
      starter: starter.value,
      played: played.value,
      minutesPlayed: int.tryParse(minutesCtrl.text.trim()) ?? 0,
      goals: int.tryParse(goalsCtrl.text.trim()) ?? 0,
      assists: int.tryParse(assistsCtrl.text.trim()) ?? 0,
      rating: double.tryParse(ratingCtrl.text.trim()),
      injured: injured.value,
    );
    final list = [
      ..._participations.where((p) => p.playerId != player.id),
      updated,
    ];
    final ok = await ClubService().saveMatchParticipations(widget.matchId, list);
    if (!mounted) return;
    if (ok) {
      setState(() => _participations = list);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.get('match_save_failed'))));
    }
  }

  Future<void> _runClock(String operation, {String? playerId}) async {
    if (_clockBusy) return;
    if (operation == 'start_match' &&
        !_participations.any((participation) => participation.starter)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.get('activity_select_starters_hint'))));
      return;
    }
    setState(() => _clockBusy = true);
    final error = await ClubService().controlMatchClock(
        widget.matchId, operation, playerId: playerId);
    if (error == null && mounted) {
      // Apply the clock change locally instead of re-fetching the whole
      // match (which flashed the entire page to a spinner on every
      // start/stop tap). All clocks share `_clockSnapshotAt` as their
      // timing baseline, so moving that baseline requires freezing every
      // running clock's elapsed time to its live value first, not just
      // the one being toggled.
      setState(() {
        final now = DateTime.now();
        final m = _match!;
        m.elapsedSeconds = _liveSeconds(m.elapsedSeconds, m.clockRunning);
        _participations = _participations
            .map((p) => MatchParticipation(
                  playerId: p.playerId,
                  starter: p.starter,
                  played: p.played,
                  minuteIn: p.minuteIn,
                  minuteOut: p.minuteOut,
                  minutesPlayed: p.minutesPlayed,
                  position: p.position,
                  goals: p.goals,
                  assists: p.assists,
                  notPlayedReason: p.notPlayedReason,
                  clockRunning: p.clockRunning,
                  elapsedSeconds: _liveSeconds(p.elapsedSeconds, p.clockRunning),
                ))
            .toList();
        _clockSnapshotAt = now;

        if (playerId == null) {
          m.clockRunning = operation == 'start_match';
          if (operation == 'finish_match') m.status = 'completed';
        } else {
          final index = _participations.indexWhere((p) => p.playerId == playerId);
          if (index != -1) {
            _participations[index].clockRunning = operation == 'start_player';
          }
        }
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error!)));
    }
    if (mounted) setState(() => _clockBusy = false);
  }

  Future<void> _setStarter(String playerId, bool selected) async {
    if (_clockBusy) return;
    setState(() => _clockBusy = true);
    final ok = await ClubService().setMatchStarter(
        widget.matchId, playerId, selected);
    if (ok && mounted) {
      setState(() {
        final index = _participations.indexWhere((p) => p.playerId == playerId);
        if (index != -1) {
          _participations[index].starter = selected;
        } else {
          _participations = [
            ..._participations,
            MatchParticipation(playerId: playerId, starter: selected),
          ];
        }
      });
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.get('activity_clock_save_failed'))));
    }
    if (mounted) setState(() => _clockBusy = false);
  }

  Future<void> _addStat(String playerId, String stat) async {
    if (_clockBusy) return;
    setState(() => _clockBusy = true);
    final ok = await ClubService().incrementMatchStat(
        widget.matchId, playerId, stat);
    if (ok && mounted) {
      setState(() {
        final index = _participations.indexWhere((p) => p.playerId == playerId);
        if (index == -1) {
          _participations = [
            ..._participations,
            MatchParticipation(
              playerId: playerId,
              goals: stat == 'goals' ? 1 : 0,
              assists: stat == 'assists' ? 1 : 0,
            ),
          ];
        } else {
          final participation = _participations[index];
          if (stat == 'goals') {
            participation.goals++;
          } else if (stat == 'assists') {
            participation.assists++;
          }
        }
        _clockBusy = false;
      });
      return;
    }
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.get('match_save_failed'))));
    }
    if (mounted) setState(() => _clockBusy = false);
  }

  String get _surveyUrl => '$kWebBase/survey/?match_id=${widget.matchId}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2)))
            else if (_loadError && _match == null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.muted, size: 40),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.get('error_generic'),
                          style: const TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(AppLocalizations.get('retry')),
                      ),
                    ],
                  ),
                ),
              )
            else if (_match == null)
              Expanded(
                child: Center(child: Text(AppLocalizations.get('match_not_found'),
                    style: const TextStyle(color: AppColors.muted))))
            else
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.card,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      _buildMatchCard(),
                      if (canControlActivityClock) ...[
                        const SizedBox(height: 16),
                        _buildClockCard(),
                      ],
                      const SizedBox(height: 16),
                      if (_match!.wellnessRequired || _match!.rpeRequired)
                        _buildSurveyCard(),
                      const SizedBox(height: 16),
                      _buildPlayersSection(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.8))),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: AppColors.card, shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3)),
                ]),
            child: const Icon(Icons.arrow_back_rounded,
                color: AppColors.foreground, size: 18),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            _match != null
                ? AppLocalizations.format('match_vs', {'opponent': _match!.opponent})
                : AppLocalizations.get('match_detail_title'),
            style: const TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w900, fontSize: 18)),
        ),
        if (_match != null && _players.isNotEmpty)
          GestureDetector(
            onTap: _printParticipantsReport,
            child: Container(
              width: 38, height: 38,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                  color: AppColors.surface2, shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2)),
                  ]),
              child: const Icon(Icons.print_outlined,
                  color: AppColors.foreground, size: 17),
            ),
          ),
        if (_match != null && canManageMatches)
          GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MatchFormPage(matchId: widget.matchId)),
              );
              _load();
            },
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.edit_rounded,
                  color: AppColors.primary, size: 18),
            ),
          ),
      ]),
    );
  }

  void _printParticipantsReport() {
    Printing.layoutPdf(
      onLayout: (format) =>
          ReportService.instance.generateMatchParticipantsReportPdf(
        match: _match!,
        players: _players,
        participations: _participations,
        cards: _cards,
      ),
    );
  }

  Widget _buildMatchCard() {
    final m = _match!;
    final statusColor = m.status == 'completed'
        ? AppColors.success
        : m.status == 'cancelled'
            ? AppColors.destructive
            : AppColors.warning;
    final opponentInitial =
        m.opponent.trim().isNotEmpty ? m.opponent.trim()[0] : '؟';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (m.competitionName != null) ...[
                _pillBadge(
                  icon: Icons.emoji_events_rounded,
                  label: m.competitionName!,
                  color: AppColors.muted,
                  bg: AppColors.background,
                ),
                const Spacer(),
              ] else
                const Spacer(),
              Container(
                height: 19,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 5, height: 5,
                    decoration: BoxDecoration(
                        color: statusColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text(m.statusLabel, style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700, fontSize: 9.5)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Expanded(
                child: Column(children: [
                  Image.asset('assets/images/logo.png',
                      width: 44, height: 44, fit: BoxFit.contain),
                  const SizedBox(height: 8),
                  const Text('المريخ', style: TextStyle(
                      color: AppColors.foreground,
                      fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
              GestureDetector(
                onTap: canManageMatches ? _editScore : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (m.hasResult)
                      Text('${m.ourScore} : ${m.opponentScore}',
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(color: AppColors.foreground,
                              fontWeight: FontWeight.w900, fontSize: 20))
                    else ...[
                      const Text('VS', style: TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700, fontSize: 10.5)),
                      const SizedBox(height: 3),
                      Text(m.matchTime, textDirection: TextDirection.ltr,
                          style: const TextStyle(color: AppColors.foreground,
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ],
                    if (canManageMatches) ...[
                      const SizedBox(height: 3),
                      Icon(m.hasResult ? Icons.edit_rounded : Icons.add_circle_outline_rounded,
                          color: AppColors.muted, size: 12),
                    ],
                  ]),
                ),
              ),
              Expanded(
                child: Column(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: const BoxDecoration(
                        color: AppColors.surface2, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(opponentInitial, style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  const SizedBox(height: 8),
                  Text(m.opponent, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.foreground,
                          fontWeight: FontWeight.w700, fontSize: 12)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _infoRow(Icons.calendar_today_rounded,
                    AppLocalizations.formatFullDate(m.matchDate)),
                if (m.location != null) ...[
                  const SizedBox(height: 11),
                  _infoRow(Icons.location_on_rounded, m.location!),
                ],
                const SizedBox(height: 11),
                _infoRow(Icons.people_rounded,
                    AppLocalizations.format('match_players_count', {'count': m.playerIds.length})),
              ]),
            ),
          ]),
        ),
        if (m.notes != null && m.notes!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLocalizations.get('match_notes_label'), style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700, fontSize: 11.5)),
              const SizedBox(height: 6),
              Text(m.notes!, style: const TextStyle(
                  color: AppColors.foreground, fontSize: 12.5, height: 1.6)),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _pillBadge({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(
            color: color, fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8)),
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.muted, size: 13),
      ),
      const SizedBox(width: 9),
      Expanded(child: Text(text, style: const TextStyle(
          color: AppColors.foreground, fontWeight: FontWeight.w600, fontSize: 12.5))),
    ]);
  }

  Widget _buildClockCard() {
    final match = _match!;
    final running = match.clockRunning;
    final elapsed = _liveSeconds(match.elapsedSeconds, running);
    final hasStarted = match.elapsedSeconds > 0 || running;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: running
            ? Border.all(color: AppColors.success.withOpacity(0.45))
            : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 14,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(children: [
        Row(children: [
          Icon(Icons.timer_rounded,
              color: running ? AppColors.success : AppColors.primary, size: 24),
          const SizedBox(width: 10),
          Expanded(child: Text(AppLocalizations.get('activity_clock_title'),
              style: const TextStyle(color: AppColors.foreground,
                  fontWeight: FontWeight.w800, fontSize: 14))),
          Text(_formatClock(elapsed),
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: AppColors.foreground,
                  fontWeight: FontWeight.w900, fontSize: 22,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _clockBusy || (!running && hasStarted)
                ? null
                : () => _runClock(running ? 'finish_match' : 'start_match'),
            icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(AppLocalizations.get(running
                ? 'activity_finish_match'
                : 'activity_start_match')),
            style: ElevatedButton.styleFrom(
              backgroundColor: running ? AppColors.destructive : AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        if (!hasStarted) ...[
          const SizedBox(height: 9),
          Text(AppLocalizations.get('activity_select_starters_hint'),
              style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ],
      ]),
    );
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: _surveyUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.get('link_copied'),
            style: const TextStyle()),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _showQrDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: Text(AppLocalizations.get('match_survey_title'),
                      style: const TextStyle(
                          color: AppColors.foreground,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: AppColors.muted, size: 16),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: _surveyUrl,
                  version: QrVersions.auto,
                  size: 240,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_surveyUrl,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  _copyLink();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.copy_rounded, color: Colors.white, size: 15),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.get('copy_link_label'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSurveyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.qr_code_2_rounded,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(AppLocalizations.get('match_survey_title'),
                style: TextStyle(color: AppColors.foreground,
                    fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(_surveyUrl,
            style: const TextStyle(color: AppColors.primary,
                fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Row(children: [
          if (_match!.wellnessRequired)
            _surveyBadge(AppLocalizations.get('match_wellness_badge')),
          if (_match!.wellnessRequired && _match!.rpeRequired)
            const SizedBox(width: 6),
          if (_match!.rpeRequired)
            _surveyBadge(AppLocalizations.get('match_rpe_badge')),
        ]),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _showQrDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.share_rounded, color: AppColors.foreground, size: 16),
              const SizedBox(width: 6),
              Text(AppLocalizations.get('match_share_survey'),
                  style: TextStyle(color: AppColors.foreground,
                      fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _surveyBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary.withOpacity(0.4))),
      child: Text(label, style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }

  Widget _buildPlayersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(AppLocalizations.get(canControlActivityClock &&
                  !_match!.clockRunning && _match!.elapsedSeconds == 0
              ? 'activity_starting_lineup'
              : 'match_players_title'),
              style: const TextStyle(color: AppColors.foreground,
                  fontWeight: FontWeight.w800, fontSize: 15)),
          const Spacer(),
          Text(AppLocalizations.format('match_players_count', {'count': _players.length}),
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 10),
        if (_players.isEmpty)
          Text(AppLocalizations.get('match_no_players'),
              style: const TextStyle(color: AppColors.muted, fontSize: 13))
        else
          ..._players.map((p) {
            final eval = _evaluations
                .where((e) => e.playerId == p.id)
                .firstOrNull;
            final minutes = _match!.playerMinutes[p.id];
            final cards = _cards.where((c) => c.playerId == p.id).toList();
            final participation = _participations.where((mp) => mp.playerId == p.id).firstOrNull;
            return _PlayerMatchCard(
              player: p,
              minutes: minutes,
              evaluation: eval,
              cards: cards,
              participation: participation,
              matchId: widget.matchId,
              onEvaluationSaved: _load,
              onAddCard: (type) => _addCard(p.id, type),
              onEditParticipation: () => _editParticipation(p),
              canManageLive: canControlActivityClock,
              matchRunning: _match!.clockRunning,
              lineupLocked: _match!.clockRunning || _match!.elapsedSeconds > 0,
              clockBusy: _clockBusy,
              liveSeconds: _liveSeconds(
                  participation?.elapsedSeconds ?? 0,
                  participation?.clockRunning ?? false),
              onStarterChanged: (selected) => _setStarter(p.id, selected),
              onClockToggle: () => _runClock(
                  participation?.clockRunning == true
                      ? 'stop_player'
                      : 'start_player',
                  playerId: p.id),
              onAddGoal: () => _addStat(p.id, 'goals'),
              onAddAssist: () => _addStat(p.id, 'assists'),
            );
          }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Player Match Card
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerMatchCard extends StatelessWidget {
  const _PlayerMatchCard({
    required this.player,
    required this.minutes,
    required this.evaluation,
    required this.cards,
    required this.participation,
    required this.matchId,
    required this.onEvaluationSaved,
    required this.onAddCard,
    required this.onEditParticipation,
    required this.canManageLive,
    required this.matchRunning,
    required this.lineupLocked,
    required this.clockBusy,
    required this.liveSeconds,
    required this.onStarterChanged,
    required this.onClockToggle,
    required this.onAddGoal,
    required this.onAddAssist,
  });

  final ClubPlayer player;
  final int? minutes;
  final CoachEvaluation? evaluation;
  final List<MatchCard> cards;
  final MatchParticipation? participation;
  final String matchId;
  final VoidCallback onEvaluationSaved;
  final ValueChanged<String> onAddCard;
  final VoidCallback onEditParticipation;
  final bool canManageLive;
  final bool matchRunning;
  final bool lineupLocked;
  final bool clockBusy;
  final int liveSeconds;
  final ValueChanged<bool> onStarterChanged;
  final VoidCallback onClockToggle;
  final VoidCallback onAddGoal;
  final VoidCallback onAddAssist;

  String _formatClock(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  Widget _eventButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    int? count,
  }) {
    return Expanded(
      child: SizedBox(
        height: 46,
        child: OutlinedButton.icon(
          onPressed: clockBusy ? null : onTap,
          icon: Icon(icon, size: 20),
          label: Text(count == null ? label : '$label  $count',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withOpacity(0.45)),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avg = evaluation?.average;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
        border: evaluation != null
            ? Border.all(color: AppColors.primary.withOpacity(0.25))
            : null,
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () async {
            if (isDoctorRole) {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => InjuryCaseScreen(
                  playerId: player.id,
                  playerName: player.fullName,
                ),
              ));
              return;
            }
            final result = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              backgroundColor: AppColors.card,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              builder: (_) => CoachEvaluationSheet(
                player: player,
                matchId: matchId,
                existing: evaluation,
              ),
            );
            if (result == true) onEvaluationSaved();
          },
          child: Row(children: [
          // Avatar
          Container(
            width: 38, height: 38,
            decoration: const BoxDecoration(
                color: AppColors.primarySoft, shape: BoxShape.circle),
            child: Center(child: Text(player.initials,
                style: const TextStyle(color: AppColors.maroon,
                    fontWeight: FontWeight.w900, fontSize: 14))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player.fullName, style: const TextStyle(
                    color: AppColors.foreground,
                    fontWeight: FontWeight.w700, fontSize: 13)),
                Text('#${player.number}  ·  ${player.position}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          if (minutes != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8)),
              child: Text('$minutes${AppLocalizations.get('match_minutes_suffix')}',
                  style: const TextStyle(color: AppColors.muted,
                      fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          const SizedBox(width: 8),
          if (avg != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.3))),
              child: Text(avg.toStringAsFixed(1),
                  style: const TextStyle(color: AppColors.primary,
                      fontWeight: FontWeight.w900, fontSize: 13)),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, color: AppColors.muted, size: 13),
                const SizedBox(width: 3),
                Text(AppLocalizations.get('match_evaluate_btn'), style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600, fontSize: 11)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        const Divider(color: AppColors.border, height: 1),
        const SizedBox(height: 8),
        if (canManageLive)
          Row(children: [
            SizedBox(
              width: 38,
              height: 38,
              child: Checkbox(
                value: participation?.starter ?? false,
                onChanged: lineupLocked || clockBusy
                    ? null
                    : (value) => onStarterChanged(value ?? false),
                activeColor: AppColors.primary,
                side: const BorderSide(color: AppColors.muted),
              ),
            ),
            Text(AppLocalizations.get((participation?.starter ?? false)
                    ? 'match_starter_label'
                    : 'match_substitute_label'),
                style: TextStyle(color: (participation?.starter ?? false)
                        ? AppColors.foreground : AppColors.muted,
                    fontWeight: FontWeight.w700, fontSize: 12)),
            const Spacer(),
            Text(_formatClock(liveSeconds),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    color: participation?.clockRunning == true
                        ? AppColors.success : AppColors.muted,
                    fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(width: 8),
            SizedBox(
              width: 42,
              height: 42,
              child: IconButton(
                onPressed: !matchRunning || clockBusy ? null : onClockToggle,
                style: IconButton.styleFrom(
                  backgroundColor: participation?.clockRunning == true
                      ? AppColors.destructive.withOpacity(0.14)
                      : AppColors.success.withOpacity(0.14),
                ),
                icon: Icon(participation?.clockRunning == true
                    ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    color: participation?.clockRunning == true
                        ? AppColors.destructive : AppColors.success),
              ),
            ),
          ])
        else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(AppLocalizations.get(participation?.starter == true
                    ? 'match_starter_label'
                    : 'match_substitute_label'),
                style: TextStyle(color: participation?.starter == true
                        ? AppColors.primary : AppColors.muted,
                    fontWeight: FontWeight.w700, fontSize: 11)),
          ),
        if (cards.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: cards.map((c) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: (c.cardType == 'yellow'
                        ? const Color(0xFFE5A315)
                        : AppColors.destructive)
                    .withOpacity(0.15),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.square_rounded, size: 11,
                    color: c.cardType == 'yellow'
                        ? const Color(0xFFE5A315) : AppColors.destructive),
                if (c.minute != null) ...[
                  const SizedBox(width: 3),
                  Text("${c.minute}'", style: const TextStyle(
                      color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 10)),
                ],
              ]),
            )).toList(),
          ),
        ],
        if (canManageLive) ...[
          const SizedBox(height: 10),
          Row(children: [
            _eventButton(
              icon: Icons.sports_soccer_rounded,
              label: AppLocalizations.get('match_add_goal'),
              color: AppColors.success,
              count: participation?.goals ?? 0,
              onTap: onAddGoal,
            ),
            const SizedBox(width: 7),
            _eventButton(
              icon: Icons.assistant_direction_rounded,
              label: AppLocalizations.get('match_add_assist'),
              color: AppColors.primary,
              count: participation?.assists ?? 0,
              onTap: onAddAssist,
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _eventButton(
              icon: Icons.square_rounded,
              label: AppLocalizations.get('yellow_card_label'),
              color: const Color(0xFFE5A315),
              onTap: () => onAddCard('yellow'),
            ),
            const SizedBox(width: 7),
            _eventButton(
              icon: Icons.square_rounded,
              label: AppLocalizations.get('red_card_label'),
              color: AppColors.destructive,
              onTap: () => onAddCard('red'),
            ),
          ]),
        ],
        if (canManageMatches) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton(
              onPressed: onEditParticipation,
              icon: const Icon(Icons.edit_rounded, color: AppColors.muted),
            ),
          ),
        ],
      ]),
    );
  }
}
