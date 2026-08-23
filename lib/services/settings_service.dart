// MVP settings store — in-memory mock, no external API yet.
class SettingsService {
  static final Map<String, dynamic> _data = {
    'profile': {
      'name': 'الكوتش',
      'role': 'coach',
      'club_name': 'المريخ SC',
      'email': null,
      'phone': null,
      'avatar_url': null,
    },
    'app': {
      'language': 'ar',
      'theme': 'base',
      'club_theme_enabled': false,
      'font_size': 'medium',
      'injury_warning': true,
    },
    'notifications': {
      'sessions': true,
      'injury_alerts': true,
      'ai_results': true,
    },
    'ai': {
      'enabled': true,
      'coach_review_required': true,
      'save_reports': true,
      'confidence_threshold': 0.85,
    },
    'subscription': {
      'plan': 'trial',
      'status': 'active',
      'days_left': 3,
      'expires_at': null,
    },
    // Which sections each report shows — coach-customizable (add/remove),
    // per report screen. Missing key/section = show everything (default).
    'reports': {
      'team_wellness_sections': <String>['readiness_hero', 'kpi_row', 'attention_banner', 'player_list'],
      'team_indicators_sections': <String>['kpi_row', 'at_risk', 'all_players'],
    },
  };

  static Map<String, dynamic> getSettings() => _data;

  static Map<String, dynamic> getProfile() =>
      Map<String, dynamic>.from(_data['profile'] as Map<String, dynamic>? ?? {});

  static void updateSetting(String key, dynamic value) {
    final parts = key.split('.');
    if (parts.length == 2) {
      (_data[parts[0]] as Map<String, dynamic>?)?[parts[1]] = value;
    }
  }

  /// Enabled section keys for a customizable report (e.g.
  /// 'team_wellness_sections') — a coach can add/remove sections via each
  /// report's customize sheet.
  static Set<String> getReportSections(String reportKey) {
    final reports = _data['reports'] as Map<String, dynamic>? ?? {};
    final list = reports[reportKey] as List?;
    return list != null ? list.map((e) => e.toString()).toSet() : <String>{};
  }

  static void setReportSections(String reportKey, Set<String> sections) {
    updateSetting('reports.$reportKey', sections.toList());
  }
}
