import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/lifeline_training_levels.dart';

/// Snapshot for Lifeline arena UI (one Firestore read path).
class LifelineArenaSnapshot {
  final int levelsCleared;
  final int volunteerXp;
  final int volunteerLivesSaved;

  const LifelineArenaSnapshot({
    required this.levelsCleared,
    required this.volunteerXp,
    required this.volunteerLivesSaved,
  });

  /// Elite emergency voice bridge: training tier 10+ OR (5+ lives & 1000+ XP).
  bool get eliteVoiceUnlocked =>
      levelsCleared >= 10 || (volunteerLivesSaved >= 5 && volunteerXp >= 1000);
}

/// Firestore-backed Lifeline arena progress + volunteer XP used for elite bridge unlock.
class LifelineProgressRepository {
  LifelineProgressRepository._();
  static final instance = LifelineProgressRepository._();

  final _db = FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Stream<LifelineArenaSnapshot> watchArenaSnapshot() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      return Stream.value(const LifelineArenaSnapshot(levelsCleared: 0, volunteerXp: 0, volunteerLivesSaved: 0));
    }
    return _db.collection('users').doc(uid).snapshots().map((s) {
      final d = s.data() ?? {};
      int cleared = 0;
      final lc = d['lifelineLevelsCleared'];
      if (lc is int) cleared = lc;
      if (lc is num) cleared = lc.toInt();
      cleared = cleared.clamp(0, kLifelineTrainingLevels.length);

      int xp = 0;
      final xv = d['volunteerXp'];
      if (xv is int) xp = xv < 0 ? 0 : xv;
      if (xv is num) xp = xv.toInt() < 0 ? 0 : xv.toInt();

      int lives = 0;
      final lv = d['volunteerLivesSaved'];
      if (lv is int) lives = lv < 0 ? 0 : lv;
      if (lv is num) lives = lv.toInt() < 0 ? 0 : lv.toInt();

      return LifelineArenaSnapshot(levelsCleared: cleared, volunteerXp: xp, volunteerLivesSaved: lives);
    });
  }

  /// Number of training levels fully cleared (0..kLifelineTrainingLevels.length).
  Stream<int> watchLevelsCleared() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return Stream.value(0);
    return _db.collection('users').doc(uid).snapshots().map((s) {
      final v = s.data()?['lifelineLevelsCleared'];
      if (v is int) return v.clamp(0, kLifelineTrainingLevels.length);
      if (v is num) return v.toInt().clamp(0, kLifelineTrainingLevels.length);
      return 0;
    });
  }

  Stream<int> watchVolunteerXp() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return Stream.value(0);
    return _db.collection('users').doc(uid).snapshots().map((s) {
      final v = s.data()?['volunteerXp'];
      if (v is int) return v < 0 ? 0 : v;
      if (v is num) return v.toInt() < 0 ? 0 : v.toInt();
      return 0;
    });
  }

  Stream<int> watchVolunteerLivesSaved() {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return Stream.value(0);
    return _db.collection('users').doc(uid).snapshots().map((s) {
      final v = s.data()?['volunteerLivesSaved'];
      if (v is int) return v < 0 ? 0 : v;
      if (v is num) return v.toInt() < 0 ? 0 : v.toInt();
      return 0;
    });
  }

  /// Clears [stageIndex] if it is the next stage along [kLifelineTrainingLevels]
  /// (`1` = first item … `length` = last). This is the list position, not the
  /// curriculum [LifelineTrainingLevel.id] (which may have gaps).
  Future<void> recordLevelPassed(int stageIndex, int xpReward) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return;
    if (stageIndex < 1 || stageIndex > kLifelineTrainingLevels.length) return;

    final ref = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final cur = snap.data()?['lifelineLevelsCleared'];
      int cleared = 0;
      if (cur is int) cleared = cur;
      if (cur is num) cleared = cur.toInt();
      cleared = cleared.clamp(0, kLifelineTrainingLevels.length);
      if (stageIndex != cleared + 1) return;
      tx.set(
        ref,
        {
          'lifelineLevelsCleared': stageIndex,
          'volunteerXp': FieldValue.increment(xpReward),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}
