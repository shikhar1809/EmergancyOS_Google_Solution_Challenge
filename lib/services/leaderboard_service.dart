import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/sos_demo_incident_filter.dart';

// ---------------------------------------------------------------------------
// Leaderboard Service — Volunteer acceptances from active + archived incidents
//
// Counts each uid in `acceptedVolunteerIds` on open incidents + recent archives,
// then merges `leaderboard/{uid}` (written when incidents archive) and the
// current user's `users/{uid}` XP so the list is never empty when XP exists.
// ---------------------------------------------------------------------------

/// A single entry on the leaderboard.
class LeaderboardEntry {
  final String userId;
  final String displayName;
  final int responseCount;
  final int onDutyMinutes; // minutes the volunteer has been on duty (all-time)
  /// Stored on `users/{uid}` — SOS acceptances, closures, Lifeline, etc.
  final int volunteerXp;
  final bool isCurrentUser;

  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.responseCount,
    required this.isCurrentUser,
    this.onDutyMinutes = 0,
    this.volunteerXp = 0,
  });

  /// Primary ladder metric: volunteer XP (tie-break: response count in sort).
  int get score => volunteerXp;
}

/// Dashboard stats for the current user.
class UserDashboardStats {
  final int responsesThisWeek;
  final int totalActiveAlerts;

  const UserDashboardStats({
    required this.responsesThisWeek,
    required this.totalActiveAlerts,
  });
}

/// EmergencyOS: LeaderboardService in lib/services/leaderboard_service.dart.
class LeaderboardService {
  static final _db = FirebaseFirestore.instance;
  static const _archiveCol = 'sos_incidents_archive';
  static const _precomputedLbCol = 'leaderboard';

  static String _titleCaseLocalPart(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  /// Best-effort display name from a `users/{uid}` document.
  static String? _nameFromUserMap(Map<String, dynamic>? u) {
    if (u == null) return null;
    const keys = [
      'displayName',
      'name',
      'fullName',
      'username',
      'nickname',
      'userName',
      'legalName',
    ];
    for (final key in keys) {
      final v = u[key];
      if (v is String) {
        final t = v.trim();
        if (t.isNotEmpty) return t;
      }
    }
    final fn = (u['firstName'] as String?)?.trim();
    final ln = (u['lastName'] as String?)?.trim();
    if (fn != null && fn.isNotEmpty) {
      if (ln != null && ln.isNotEmpty) return '$fn $ln'.trim();
      return fn;
    }
    if (ln != null && ln.isNotEmpty) return ln;
    final em = u['email'];
    if (em is String) {
      final trimmed = em.trim();
      final at = trimmed.indexOf('@');
      if (at > 0) {
        final local = trimmed.substring(0, at).trim();
        if (local.isNotEmpty) return _titleCaseLocalPart(local);
      }
    }
    return null;
  }

  /// Best-effort public label from Firebase Auth (for denormalizing onto incidents).
  static String volunteerLabelFromAuth(User user) {
    final dn = user.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    final em = user.email?.trim();
    if (em != null && em.contains('@')) {
      final local = em.split('@').first.trim();
      if (local.isNotEmpty) return _titleCaseLocalPart(local);
    }
    final ph = user.phoneNumber?.trim();
    if (ph != null && ph.isNotEmpty) return ph;
    if (user.uid.length >= 6) return 'Member ${user.uid.substring(0, 6)}';
    return 'Member';
  }

  static bool _isWeakDisplayLabel(String? s) {
    if (s == null) return true;
    final t = s.trim();
    if (t.isEmpty || t == 'Volunteer') return true;
    // UID fallback from volunteerLabelFromAuth — prefer real names when available.
    if (t.startsWith('Member ') && t.length <= 16) return true;
    return false;
  }

  /// Picks the best human-readable label for the leaderboard row.
  static String _coalesceLeaderboardName({
    required String uid,
    String? incidentHint,
    String? userDocName,
    String? leaderboardDocName,
    String? authFallback,
    String? phone,
  }) {
    for (final c in [
      incidentHint,
      userDocName,
      if (!_isWeakDisplayLabel(leaderboardDocName)) leaderboardDocName,
      authFallback,
      phone,
    ]) {
      if (!_isWeakDisplayLabel(c)) return c!.trim();
    }
    if (!_isWeakDisplayLabel(leaderboardDocName)) return leaderboardDocName!.trim();
    if (uid.length >= 6) return 'Member ${uid.substring(0, 6)}';
    return 'Member';
  }

  /// Names stored on incidents when volunteers accept (`responderNames.{uid}`).
  /// Readable for all users who can read incidents — avoids blocked `users/{uid}` reads.
  static Map<String, String> _collectResponderNameHints(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> activeDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> archiveDocs,
  ) {
    final hints = <String, String>{};
    void mergeFromData(Map<String, dynamic> data) {
      final raw = data['responderNames'];
      if (raw is! Map) return;
      raw.forEach((k, v) {
        final uid = k.toString().trim();
        final name = v?.toString().trim();
        if (uid.isEmpty || name == null || name.isEmpty) return;
        hints[uid] = name;
      });
    }

    // Archive query is newest-first; reverse so later merges win with newer archives.
    for (final d in archiveDocs.reversed) {
      mergeFromData(d.data());
    }
    for (final d in activeDocs) {
      mergeFromData(d.data());
    }
    return hints;
  }

  /// Writes `displayName` / `email` / derived `name` so the leaderboard can show real labels.
  static Future<void> syncVolunteerPublicProfile(User user) async {
    if (user.uid.isEmpty) return;
    try {
      final email = user.email?.trim();
      final dn = user.displayName?.trim();
      final payload = <String, Object>{};
      if (email != null && email.isNotEmpty) payload['email'] = email;
      if (dn != null && dn.isNotEmpty) {
        payload['displayName'] = dn;
      } else if (email != null && email.contains('@')) {
        final local = email.split('@').first.trim();
        if (local.isNotEmpty) payload['name'] = _titleCaseLocalPart(local);
      }
      if (payload.isEmpty) return;
      await _db.collection('users').doc(user.uid).set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[LeaderboardService] syncVolunteerPublicProfile: $e');
    }
  }

  static void _tallyAcceptedVolunteers(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, int> counts,
  ) {
    for (final doc in docs) {
      final data = doc.data();
      final accepted = List<dynamic>.from(data['acceptedVolunteerIds'] ?? []);
      for (final raw in accepted) {
        final v = raw.toString().trim();
        if (v.isEmpty || isDemoLeaderboardUserId(v)) continue;
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _withoutDemoIncidents(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((d) => !isDemoSosFirestoreDoc(d.id, d.data())).toList();
  }

  static Future<List<LeaderboardEntry>> _buildEntries({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> activeDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> archiveDocs,
  }) async {
    activeDocs = _withoutDemoIncidents(activeDocs);
    archiveDocs = _withoutDemoIncidents(archiveDocs);
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final counts = <String, int>{};
    _tallyAcceptedVolunteers(activeDocs, counts);
    _tallyAcceptedVolunteers(archiveDocs, counts);

    if (counts.isEmpty) return [];

    final nameHints =
        _collectResponderNameHints(activeDocs, archiveDocs);
    final names = <String, String>{};
    final dutyMinutes = <String, int>{};
    final volunteerXpMap = <String, int>{};

    final uidList = counts.keys.toList();
    for (var i = 0; i < uidList.length; i += 30) {
      final chunk = uidList.sublist(i, (i + 30 > uidList.length) ? uidList.length : i + 30);
      try {
        final results = await Future.wait([
          _db.collection('users').where(FieldPath.documentId, whereIn: chunk).get().timeout(const Duration(seconds: 10)),
          _db.collection(_precomputedLbCol).where(FieldPath.documentId, whereIn: chunk).get().timeout(const Duration(seconds: 10)),
        ]);
        
        final userDocs = {for (var d in results[0].docs) d.id: d.data()};
        final lbDocs = {for (var d in results[1].docs) d.id: d.data()};

        for (final uid in chunk) {
          final u = userDocs[uid];
          final lb = lbDocs[uid];

          dutyMinutes[uid] = u != null ? ((u['dutyMinutes'] ?? 0) as num).toInt() : 0;
          volunteerXpMap[uid] = u != null
              ? ((u['volunteerXp'] ?? 0) as num).toInt()
              : ((lb?['volunteerXp'] ?? 0) as num).toInt();

          String? authFb;
          if (uid == currentUid) {
            final auth = FirebaseAuth.instance.currentUser;
            if (auth != null && auth.uid == uid) {
              authFb = auth.displayName?.trim();
              if (authFb == null || authFb.isEmpty) {
                final em = auth.email;
                if (em != null && em.contains('@')) {
                  authFb = _titleCaseLocalPart(em.split('@').first.trim());
                }
              }
            }
          }

          final lbName = (lb?['displayName'] as String?)?.trim();
          final ph = u?['phoneNumber'];
          final phoneStr = ph is String ? ph.trim() : null;

          names[uid] = _coalesceLeaderboardName(
            uid: uid,
            incidentHint: nameHints[uid],
            userDocName: _nameFromUserMap(u),
            leaderboardDocName: lbName,
            authFallback: authFb,
            phone: phoneStr,
          );
        }
      } catch (e) {
        debugPrint('[LeaderboardService] bulk fetch failed for chunk: $e');
        // Fallback for this chunk
        for (final uid in chunk) {
          dutyMinutes[uid] = dutyMinutes[uid] ?? 0;
          volunteerXpMap[uid] = volunteerXpMap[uid] ?? 0;
          final hint = nameHints[uid];
          if (hint != null && hint.isNotEmpty) {
            names[uid] = hint;
          } else if (uid == currentUid) {
            final auth = FirebaseAuth.instance.currentUser;
            if (auth != null) {
              names[uid] = volunteerLabelFromAuth(auth);
            }
          }
          if (!names.containsKey(uid)) {
            names[uid] = uid.length >= 6 ? 'Member ${uid.substring(0, 6)}' : 'Member';
          }
        }
      }
    }

    final entries = counts.entries
        .map(
          (e) => LeaderboardEntry(
            userId: e.key,
            displayName: names[e.key] ??
                (e.key.length >= 6 ? 'Member ${e.key.substring(0, 6)}' : 'Member'),
            responseCount: e.value,
            onDutyMinutes: dutyMinutes[e.key] ?? 0,
            volunteerXp: volunteerXpMap[e.key] ?? 0,
            isCurrentUser: e.key == currentUid,
          ),
        )
        .toList();

    entries.sort((a, b) {
      final byXp = b.volunteerXp.compareTo(a.volunteerXp);
      if (byXp != 0) return byXp;
      return b.responseCount.compareTo(a.responseCount);
    });
    return entries;
  }

  /// Merges precomputed `leaderboard` docs (from Cloud Functions) and ensures the
  /// signed-in user appears when they have XP but no incident tallies yet.
  static Future<List<LeaderboardEntry>> _mergePrecomputedLeaderboardAndSelf(
    List<LeaderboardEntry> base,
  ) async {
    final byUid = <String, LeaderboardEntry>{for (final e in base) e.userId: e};
    final curUid = FirebaseAuth.instance.currentUser?.uid;

    try {
      final snap = await _db
          .collection(_precomputedLbCol)
          .orderBy('volunteerXp', descending: true)
          .limit(100)
          .get()
          .timeout(const Duration(seconds: 12));
      for (final doc in snap.docs) {
        final uid = doc.id.trim();
        if (uid.isEmpty || isDemoLeaderboardUserId(uid)) continue;
        final d = doc.data();
        final xp = (d['volunteerXp'] as num?)?.toInt() ?? 0;
        final rc = (d['responsesCount'] as num?)?.toInt() ?? 0;
        final dn = (d['displayName'] as String?)?.trim();
        final prev = byUid[uid];
        if (prev != null) {
          final pickName = _coalesceLeaderboardName(
            uid: uid,
            incidentHint: null,
            userDocName: _isWeakDisplayLabel(prev.displayName) ? null : prev.displayName,
            leaderboardDocName: dn,
            authFallback: null,
            phone: null,
          );
          byUid[uid] = LeaderboardEntry(
            userId: uid,
            displayName: pickName,
            responseCount: prev.responseCount > rc ? prev.responseCount : rc,
            volunteerXp: prev.volunteerXp > xp ? prev.volunteerXp : xp,
            onDutyMinutes: prev.onDutyMinutes,
            isCurrentUser: uid == curUid,
          );
        } else {
          // Include ALL users from the leaderboard collection,
          // even those with 0 XP / 0 responses, for proper ranking.
          byUid[uid] = LeaderboardEntry(
            userId: uid,
            displayName: _coalesceLeaderboardName(
              uid: uid,
              incidentHint: null,
              userDocName: null,
              leaderboardDocName: dn,
              authFallback: null,
              phone: null,
            ),
            responseCount: rc,
            volunteerXp: xp,
            isCurrentUser: uid == curUid,
          );
        }
      }
    } catch (e) {
      debugPrint('[LeaderboardService] precomputed leaderboard query: $e');
    }

    // ── Also pull in ALL registered users so the board is never empty ──
    try {
      final usersSnap = await _db
          .collection('users')
          .limit(200)
          .get()
          .timeout(const Duration(seconds: 12));
      for (final doc in usersSnap.docs) {
        final uid = doc.id.trim();
        if (uid.isEmpty || byUid.containsKey(uid) || isDemoLeaderboardUserId(uid)) continue;
        final u = doc.data();
        final xp = (u['volunteerXp'] as num?)?.toInt() ?? 0;
        final ph = u['phoneNumber'];
        final phoneStr = ph is String ? ph.trim() : null;
        byUid[uid] = LeaderboardEntry(
          userId: uid,
          displayName: _coalesceLeaderboardName(
            uid: uid,
            incidentHint: null,
            userDocName: _nameFromUserMap(u),
            leaderboardDocName: null,
            authFallback: null,
            phone: phoneStr,
          ),
          responseCount: 0,
          volunteerXp: xp,
          isCurrentUser: uid == curUid,
        );
      }
    } catch (e) {
      debugPrint('[LeaderboardService] users collection query: $e');
    }

    if (curUid != null && curUid.isNotEmpty) {
      try {
        final udoc = await _db.collection('users').doc(curUid).get().timeout(const Duration(seconds: 5));
        final u = udoc.data();
        final xp = (u?['volunteerXp'] as num?)?.toInt() ?? 0;
        final prev = byUid[curUid];
        final auth = FirebaseAuth.instance.currentUser;
        final fromUserDoc = _nameFromUserMap(u);
        var selfName = _coalesceLeaderboardName(
          uid: curUid,
          incidentHint: null,
          userDocName: fromUserDoc,
          leaderboardDocName: null,
          authFallback: auth != null ? volunteerLabelFromAuth(auth) : null,
          phone: (u?['phoneNumber'] is String) ? (u!['phoneNumber'] as String).trim() : null,
        );

        if (prev == null) {
          // Always show the current user on the leaderboard, even with 0 XP,
          // so they can see their position and be motivated to participate.
          byUid[curUid] = LeaderboardEntry(
            userId: curUid,
            displayName: selfName,
            responseCount: 0,
            volunteerXp: xp,
            isCurrentUser: true,
          );
        } else {
          final nm = _coalesceLeaderboardName(
            uid: curUid,
            incidentHint: null,
            userDocName: _isWeakDisplayLabel(prev.displayName) ? null : prev.displayName,
            leaderboardDocName: null,
            authFallback: selfName,
            phone: null,
          );
          byUid[curUid] = LeaderboardEntry(
            userId: curUid,
            displayName: nm,
            responseCount: prev.responseCount,
            volunteerXp: prev.volunteerXp > xp ? prev.volunteerXp : xp,
            onDutyMinutes: prev.onDutyMinutes,
            isCurrentUser: true,
          );
        }
      } catch (e) {
        debugPrint('[LeaderboardService] merge self XP: $e');
      }
    }

    byUid.removeWhere((k, _) => isDemoLeaderboardUserId(k) && k != curUid);

    final out = byUid.values.toList();
    out.sort((a, b) {
      final byXp = b.volunteerXp.compareTo(a.volunteerXp);
      if (byXp != 0) return byXp;
      return b.responseCount.compareTo(a.responseCount);
    });
    return out;
  }

  /// Live leaderboard: open SOS (by status) + recent archived incidents.
  static Stream<List<LeaderboardEntry>> watchLeaderboard() {
    var activeDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    var archiveDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    var activeReady = false;
    var archiveReady = false;
    var archiveFailed = false;

    late final StreamController<List<LeaderboardEntry>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subActive;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? subArchive;

    Future<void> emit() async {
      if (!activeReady || !archiveReady) return;
      try {
        final arch =
            archiveFailed ? <QueryDocumentSnapshot<Map<String, dynamic>>>[] : archiveDocs;
        var entries = await _buildEntries(activeDocs: activeDocs, archiveDocs: arch);
        entries = await _mergePrecomputedLeaderboardAndSelf(entries);
        if (!controller.isClosed) controller.add(entries);
      } catch (e, st) {
        debugPrint('[LeaderboardService] emit failed: $e\n$st');
        try {
          final fallback = await _mergePrecomputedLeaderboardAndSelf(<LeaderboardEntry>[]);
          if (!controller.isClosed) controller.add(fallback);
        } catch (e2, st2) {
          debugPrint('[LeaderboardService] emit fallback failed: $e2\n$st2');
          if (!controller.isClosed) controller.add(<LeaderboardEntry>[]);
        }
      }
    }

    controller = StreamController<List<LeaderboardEntry>>(
      onListen: () {
        Future<void> bootstrap() async {
          try {
            final q = await _db
                .collection('sos_incidents')
                .where('status', whereIn: ['pending', 'dispatched', 'blocked'])
                .get()
                .timeout(const Duration(seconds: 20));
            activeDocs = q.docs;
          } catch (e) {
            debugPrint('[LeaderboardService] bootstrap active incidents: $e');
            activeDocs = [];
          }
          activeReady = true;

          try {
            final arch = await _db
                .collection(_archiveCol)
                .orderBy('timestamp', descending: true)
                .limit(500)
                .get()
                .timeout(const Duration(seconds: 20));
            archiveDocs = arch.docs;
            archiveFailed = false;
          } catch (e) {
            debugPrint('[LeaderboardService] bootstrap archive orderBy: $e');
            try {
              final arch = await _db
                  .collection(_archiveCol)
                  .limit(500)
                  .get()
                  .timeout(const Duration(seconds: 20));
              archiveDocs = arch.docs;
              archiveFailed = false;
            } catch (e2) {
              debugPrint('[LeaderboardService] bootstrap archive fallback: $e2');
              archiveDocs = [];
              archiveFailed = true;
            }
          }
          archiveReady = true;
          await emit();
        }

        unawaited(bootstrap());

        subActive = _db
            .collection('sos_incidents')
            .where('status', whereIn: ['pending', 'dispatched', 'blocked'])
            .snapshots()
            .listen(
          (s) {
            activeDocs = s.docs;
            activeReady = true;
            unawaited(emit());
          },
          onError: (e, st) {
            debugPrint('[LeaderboardService] active incidents stream: $e');
            activeDocs = [];
            activeReady = true;
            unawaited(emit());
          },
        );

        void onArchiveSnap(QuerySnapshot<Map<String, dynamic>> s) {
          archiveDocs = s.docs;
          archiveReady = true;
          archiveFailed = false;
          unawaited(emit());
        }

        void markArchiveSkipped() {
          archiveFailed = true;
          archiveDocs = [];
          archiveReady = true;
          unawaited(emit());
        }

        subArchive = _db
            .collection(_archiveCol)
            .orderBy('timestamp', descending: true)
            .limit(500)
            .snapshots()
            .listen(
          onArchiveSnap,
          onError: (e, st) {
            debugPrint('[LeaderboardService] archive orderBy failed, try limit-only: $e');
            subArchive?.cancel();
            subArchive = _db.collection(_archiveCol).limit(500).snapshots().listen(
              onArchiveSnap,
              onError: (e2, st2) {
                debugPrint('[LeaderboardService] archive unavailable (active incidents only): $e2');
                markArchiveSkipped();
              },
            );
          },
        );
      },
      onCancel: () async {
        await subActive?.cancel();
        await subArchive?.cancel();
      },
    );

    return controller.stream;
  }

  static DateTime? _incidentCreatedAt(Map<String, dynamic> d) {
    final t = d['timestamp'];
    if (t is Timestamp) return t.toDate();
    return null;
  }

  /// Streams count of pending/dispatched SOS created within the last hour (master active window).
  static Stream<int> watchActiveAlertCount() {
    const window = Duration(hours: 1);
    return _db
        .collection('sos_incidents')
        .where('status', whereIn: ['pending', 'dispatched'])
        .snapshots()
        .map((snap) {
          final now = DateTime.now();
          var n = 0;
          for (final doc in snap.docs) {
            final ts = _incidentCreatedAt(doc.data());
            if (ts != null && now.difference(ts) <= window) n++;
          }
          return n;
        });
  }

  /// Returns the rank of the current user in the leaderboard (1-indexed).
  static Future<int?> getCurrentUserRank() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return null;

    try {
      final active = await _db
          .collection('sos_incidents')
          .where('status', whereIn: ['pending', 'dispatched', 'blocked'])
          .get();

      List<QueryDocumentSnapshot<Map<String, dynamic>>> archiveDocs = [];
      try {
        final arch = await _db
            .collection(_archiveCol)
            .orderBy('timestamp', descending: true)
            .limit(500)
            .get();
        archiveDocs = arch.docs;
      } catch (e) {
        debugPrint('[LeaderboardService] rank archive orderBy failed: $e');
        try {
          final arch = await _db.collection(_archiveCol).limit(500).get();
          archiveDocs = arch.docs;
        } catch (e2) {
          debugPrint('[LeaderboardService] rank archive skipped: $e2');
        }
      }

      var entries = await _buildEntries(activeDocs: active.docs, archiveDocs: archiveDocs);
      entries = await _mergePrecomputedLeaderboardAndSelf(entries);
      final idx = entries.indexWhere((e) => e.userId == currentUid);
      return idx == -1 ? null : idx + 1;
    } catch (_) {
      return null;
    }
  }
}

// ─── Riverpod Providers ───────────────────────────────────────────────────

/// Leaderboard from accepted volunteers on active + archived incidents.
final leaderboardProvider = StreamProvider<List<LeaderboardEntry>>(
  (_) => LeaderboardService.watchLeaderboard(),
);

/// Current user's merged response count (same basis as leaderboard).
final myResponseCountProvider = Provider<AsyncValue<int>>((ref) {
  final lb = ref.watch(leaderboardProvider);
  return lb.when(
    data: (entries) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return const AsyncData(0);
      LeaderboardEntry? row;
      for (final e in entries) {
        if (e.userId == uid) {
          row = e;
          break;
        }
      }
      return AsyncData(row?.responseCount ?? 0);
    },
    loading: () => const AsyncLoading<int>(),
    error: (e, s) => AsyncError<int>(e, s),
  );
});

/// Count of currently active (pending/dispatched) alerts — all users
final activeAlertCountProvider = StreamProvider<int>(
  (_) => LeaderboardService.watchActiveAlertCount(),
);
