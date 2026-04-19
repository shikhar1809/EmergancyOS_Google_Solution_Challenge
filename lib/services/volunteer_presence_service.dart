import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Snapshot of another volunteer for map / dashboard.
class ActiveVolunteerNearby {
  final String userId;
  final String displayName;
  final double lat;
  final double lng;
  final DateTime? dutyUpdatedAt;
  /// 'male', 'female', or '' when unknown.
  final String gender;

  const ActiveVolunteerNearby({
    required this.userId,
    required this.displayName,
    required this.lat,
    required this.lng,
    this.dutyUpdatedAt,
    this.gender = '',
  });
}

/// Publishes on-duty state + last known location to `users/{uid}` for the
/// “active volunteers in the area” map and dashboard hint.
///
/// Fields: `volunteerOnDuty`, `dutyLat`, `dutyLng`, `dutyUpdatedAt`.
class VolunteerPresenceService {
  VolunteerPresenceService._();

  static final _db = FirebaseFirestore.instance;
  // FIX 6: Track volunteer duty state and lifecycle registration for immediate offline marking.
  static bool _lifecycleRegistered = false;
  static bool _currentlyOnDuty = false;

  /// Register the app lifecycle observer once at startup (call from app_bootstrap.dart).
  /// When the app backgrounds or is closed, volunteer availability is immediately
  /// written to Firestore rather than waiting for the heartbeat TTL to expire.
  static void initLifecycleObserver() {
    if (_lifecycleRegistered) return;
    _lifecycleRegistered = true;
    WidgetsBinding.instance.addObserver(_LifecycleObserver());
  }

  /// Default radius for “nearby” (meters); align with map grid scan when possible.
  static const double defaultNearbyRadiusM = 25000;

  static const Duration staleLocationTtl = Duration(minutes: 45);

  static double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;

  /// Display name from a `users/{uid}` document (leaderboard / roster).
  static String displayNameFromUserDoc(Map<String, dynamic>? d) =>
      _labelFromUserData(d);

  static String _labelFromUserData(Map<String, dynamic>? d) {
    if (d == null) return 'Volunteer';
    for (final key in ['displayName', 'name', 'fullName']) {
      final v = d[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    final em = d['email'];
    if (em is String && em.contains('@')) {
      final local = em.split('@').first.trim();
      if (local.isNotEmpty) {
        return local[0].toUpperCase() + (local.length > 1 ? local.substring(1).toLowerCase() : '');
      }
    }
    return 'Volunteer';
  }

  static bool _isFresh(Timestamp? ts) {
    if (ts == null) return false;
    final age = DateTime.now().difference(ts.toDate());
    return age <= staleLocationTtl;
  }

  /// Call when toggling duty or periodically while on duty.
  static Future<void> publishDutyPresence({required bool onDuty}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    // FIX 6: Track duty state so lifecycle observer can restore it on resume.
    _currentlyOnDuty = onDuty;

    if (!onDuty) {
      try {
        await _db.collection('users').doc(uid).set(
          {
            'volunteerOnDuty': false,
            'dutyUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('[VolunteerPresence] clear: $e');
      }
      return;
    }

    double? lat;
    double? lng;
    try {
      final pos = await Geolocator.getCurrentPosition();
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        lat = last?.latitude;
        lng = last?.longitude;
      } catch (_) {}
    }

    try {
      final patch = <String, Object?>{
        'volunteerOnDuty': true,
        'dutyUpdatedAt': FieldValue.serverTimestamp(),
      };
      if (lat != null && lng != null) {
        patch['dutyLat'] = lat;
        patch['dutyLng'] = lng;
      }
      await _db.collection('users').doc(uid).set(patch, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[VolunteerPresence] publish: $e');
    }
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchOnDutyUsers() {
    return _db
        .collection('users')
        .where('volunteerOnDuty', isEqualTo: true)
        .limit(200)
        .snapshots();
  }

  /// Filters [docs] to fresh locations within [radiusM] of [center], excludes [excludeUid].
  static List<ActiveVolunteerNearby> filterNearby(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    LatLng center,
    double radiusM, {
    String? excludeUid,
  }) {
    final out = <ActiveVolunteerNearby>[];
    for (final doc in docs) {
      final uid = doc.id;
      if (excludeUid != null && uid == excludeUid) continue;
      final d = doc.data();
      final lat = (d['dutyLat'] as num?)?.toDouble();
      final lng = (d['dutyLng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final ts = d['dutyUpdatedAt'];
      if (!_isFresh(ts is Timestamp ? ts : null)) continue;
      final dist = haversineMeters(center.latitude, center.longitude, lat, lng);
      if (dist > radiusM) continue;
      out.add(ActiveVolunteerNearby(
        userId: uid,
        displayName: _labelFromUserData(d),
        lat: lat,
        lng: lng,
        dutyUpdatedAt: ts is Timestamp ? ts.toDate() : null,
        gender: _genderFromUserData(d),
      ));
    }
    out.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return out;
  }

  /// Determines gender from explicit 'gender' field or falls back to email heuristic.
  /// Returns 'male', 'female', or '' when unknown.
  static String _genderFromUserData(Map<String, dynamic>? d) {
    if (d == null) return '';
    final g = d['gender'];
    if (g is String) {
      final lower = g.trim().toLowerCase();
      if (lower == 'female' || lower == 'f') return 'female';
      if (lower == 'male' || lower == 'm') return 'male';
    }
    // email-based heuristic: ends with common female first-name patterns
    final email = (d['email'] as String? ?? '').split('@').first.toLowerCase();
    const femaleHints = ['she', 'her', 'girl', 'lady'];
    for (final hint in femaleHints) {
      if (email.contains(hint)) return 'female';
    }
    return '';
  }
}

/// FIX 6: Lifecycle observer that immediately clears volunteer availability
/// when the app goes to background, is paused, or is detached/closed.
/// Re-broadcasts presence when the app resumes if the volunteer was on duty.
class _LifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _markOfflineImmediate();
    } else if (state == AppLifecycleState.resumed) {
      if (VolunteerPresenceService._currentlyOnDuty) {
        VolunteerPresenceService.publishDutyPresence(onDuty: true);
      }
    }
  }

  Future<void> _markOfflineImmediate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      await VolunteerPresenceService._db.collection('users').doc(uid).set(
        {
          'volunteerOnDuty': false,
          'dutyUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint('[VolunteerPresence] Lifecycle: marked offline immediately.');
    } catch (e) {
      debugPrint('[VolunteerPresence] Lifecycle offline mark failed: $e');
    }
  }
}
