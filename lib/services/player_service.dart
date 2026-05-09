import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/player_profile_model.dart';
import 'firebase_service.dart';

class PlayerService {
  PlayerService._internal();
  static final PlayerService instance = PlayerService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String? _currentUserPath() {
    if (!Firebase.apps.isNotEmpty) {
      return null;
    }
    final uid = FirebaseService().uid;
    if (uid == null) return null;
    return 'users/$uid';
  }

  Stream<List<PlayerProfile>> streamPlayers() {
    final base = _currentUserPath();
    if (base == null) {
      return Stream.value([]);
    }
    return _firestore
        .collection('$base/players')
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => PlayerProfile.fromMap(doc.id, doc.data()))
              .toList();
        });
  }

  Future<PlayerProfile> savePlayer(PlayerProfile profile) async {
    final base = _currentUserPath();
    if (base == null) {
      throw Exception('User not authenticated');
    }
    final ref = _firestore.collection('$base/players').doc(profile.id.isEmpty
        ? null
        : profile.id);
    final data = profile.toMap();
    if (profile.id.isEmpty) {
      final created = await _firestore.collection('$base/players').add(data);
      return PlayerProfile.fromMap(created.id, {
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await ref.set(data, SetOptions(merge: true));
    final snapshot = await ref.get();
    return PlayerProfile.fromMap(snapshot.id, snapshot.data() ?? {});
  }

  Future<void> deletePlayer(String playerId) async {
    final base = _currentUserPath();
    if (base == null) {
      throw Exception('User not authenticated');
    }
    await _firestore.doc('$base/players/$playerId').delete();
  }

  Future<PlayerProfile?> getPlayerById(String playerId) async {
    final base = _currentUserPath();
    if (base == null) {
      throw Exception('User not authenticated');
    }
    final snapshot = await _firestore.doc('$base/players/$playerId').get();
    if (!snapshot.exists) return null;
    return PlayerProfile.fromMap(snapshot.id, snapshot.data()!);
  }
}
