import 'package:cloud_firestore/cloud_firestore.dart';

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
    return PlayerProfile(
      id: id,
      name: data['name'] as String? ?? 'Unnamed Player',
      photoUrl: data['photoUrl'] as String?,
      heightCm: data['heightCm'] is int ? data['heightCm'] as int : null,
      weightKg: data['weightKg'] is int ? data['weightKg'] as int : null,
      dominantFoot: data['dominantFoot'] as String?,
      position: data['position'] as String?,
      team: data['team'] as String?,
      category: data['category'] as String?,
      injuryNotes: data['injuryNotes'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (heightCm != null) 'heightCm': heightCm,
      if (weightKg != null) 'weightKg': weightKg,
      if (dominantFoot != null) 'dominantFoot': dominantFoot,
      if (position != null) 'position': position,
      if (team != null) 'team': team,
      if (category != null) 'category': category,
      if (injuryNotes != null) 'injuryNotes': injuryNotes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
