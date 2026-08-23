class PlayerProfile {
  PlayerProfile({
    required this.id,
    required this.name,
    this.photoUrl,
    this.heightCm,
    this.weightKg,
    this.dominantFoot,
    this.position,
    this.team,
    this.category,
    this.injuryNotes,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? photoUrl;
  final int? heightCm;
  final int? weightKg;
  final String? dominantFoot;
  final String? position;
  final String? team;
  final String? category;
  final String? injuryNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory PlayerProfile.fromMap(String id, Map<String, dynamic> data) {
    DateTime? _parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
      return null;
    }

    return PlayerProfile(
      id: id,
      name: data['name'] as String? ?? 'Unnamed Player',
      photoUrl: data['photoUrl'] as String? ?? data['photo_url'] as String?,
      heightCm: data['heightCm'] is int
          ? data['heightCm'] as int
          : data['height_cm'] != null
              ? int.tryParse(data['height_cm'].toString())
              : null,
      weightKg: data['weightKg'] is int
          ? data['weightKg'] as int
          : data['weight_kg'] != null
              ? int.tryParse(data['weight_kg'].toString())
              : null,
      dominantFoot: data['dominantFoot'] as String? ?? data['dominant_foot'] as String?,
      position: data['position'] as String?,
      team: data['team'] as String? ?? data['team_name'] as String?,
      category: data['category'] as String?,
      injuryNotes: data['injuryNotes'] as String? ?? data['injury_notes'] as String?,
      createdAt: _parseDate(data['createdAt'] ?? data['created_at']),
      updatedAt: _parseDate(data['updatedAt'] ?? data['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (heightCm != null) 'heightCm': heightCm,
      if (weightKg != null) 'weightKg': weightKg,
      if (dominantFoot != null) 'dominantFoot': dominantFoot,
      if (position != null) 'position': position,
      if (team != null) 'team': team,
      if (category != null) 'category': category,
      if (injuryNotes != null) 'injuryNotes': injuryNotes,
    };
  }

  PlayerProfile copyWith({
    String? id,
    String? name,
    String? photoUrl,
    int? heightCm,
    int? weightKg,
    String? dominantFoot,
    String? position,
    String? team,
    String? category,
    String? injuryNotes,
  }) {
    return PlayerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      photoUrl: photoUrl ?? this.photoUrl,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      dominantFoot: dominantFoot ?? this.dominantFoot,
      position: position ?? this.position,
      team: team ?? this.team,
      category: category ?? this.category,
      injuryNotes: injuryNotes ?? this.injuryNotes,
      createdAt: this.createdAt,
      updatedAt: this.updatedAt,
    );
  }
}
