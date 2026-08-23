class PhysicalReportPlayer {
  const PhysicalReportPlayer({
    required this.id,
    required this.name,
    required this.position,
    required this.teamName,
    required this.isReady,
    required this.bodyFatPercentage,
    required this.load7d,
    required this.sessionsCount,
  });

  final String id;
  final String name;
  final String position;
  final String teamName;
  final bool isReady;
  final double? bodyFatPercentage;
  final int load7d;
  int get weeklyLoad => load7d;
  final int sessionsCount;

  PhysicalReportPlayer copyWith({bool? isReady}) => PhysicalReportPlayer(
    id: id,
    name: name,
    position: position,
    teamName: teamName,
    isReady: isReady ?? this.isReady,
    bodyFatPercentage: bodyFatPercentage,
    load7d: load7d,
    sessionsCount: sessionsCount,
  );

  factory PhysicalReportPlayer.fromJson(Map<String, dynamic> json) {
    final bodyFat = json['body_fat_percentage'];
    return PhysicalReportPlayer(
      id: json['player_id']?.toString() ?? '',
      name: json['player_name']?.toString() ?? '',
      position: json['position']?.toString() ?? '',
      teamName: json['team_name']?.toString() ?? '',
      isReady: json['is_ready'] != false,
      bodyFatPercentage: bodyFat is num
          ? bodyFat.toDouble()
          : double.tryParse(bodyFat?.toString() ?? ''),
      load7d: (json['load_7d'] as num?)?.round() ??
          (json['weekly_load'] as num?)?.round() ??
          0,
      sessionsCount: (json['sessions_count'] as num?)?.round() ?? 0,
    );
  }
}

class PhysicalReportSummary {
  const PhysicalReportSummary({
    required this.totalPlayers,
    required this.readyPlayers,
    required this.notReadyPlayers,
    required this.averageBodyFat,
    required this.totalSessions,
  });

  final int totalPlayers;
  final int readyPlayers;
  final int notReadyPlayers;
  final double? averageBodyFat;
  final int totalSessions;

  factory PhysicalReportSummary.fromJson(Map<String, dynamic> json) {
    final average = json['average_body_fat'];
    return PhysicalReportSummary(
      totalPlayers: (json['total_players'] as num?)?.round() ?? 0,
      readyPlayers: (json['ready_players'] as num?)?.round() ?? 0,
      notReadyPlayers: (json['not_ready_players'] as num?)?.round() ?? 0,
      averageBodyFat: average is num
          ? average.toDouble()
          : double.tryParse(average?.toString() ?? ''),
      totalSessions: (json['total_sessions'] as num?)?.round() ?? 0,
    );
  }
}

class PhysicalReportData {
  const PhysicalReportData({required this.summary, required this.players});

  final PhysicalReportSummary summary;
  final List<PhysicalReportPlayer> players;

  factory PhysicalReportData.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final players = json['players'];
    return PhysicalReportData(
      summary: PhysicalReportSummary.fromJson(
        summary is Map<String, dynamic> ? summary : <String, dynamic>{},
      ),
      players: players is List
          ? players
                .whereType<Map>()
                .map(
                  (item) => PhysicalReportPlayer.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }
}
