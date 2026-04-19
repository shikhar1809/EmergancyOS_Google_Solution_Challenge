import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Global routing for victim-side voice and map tiles (Firestore: `ops_integration_routing/global`).
@immutable
class OpsIntegrationRouting {
  const OpsIntegrationRouting({
    required this.victimVoiceTransport,
    required this.mapsTiles,
    this.updatedAt,
    this.updatedByUid,
    this.updatedByEmail,
  });

  final VictimVoiceTransport victimVoiceTransport;
  final OpsMapsTiles mapsTiles;
  final DateTime? updatedAt;
  final String? updatedByUid;
  final String? updatedByEmail;

  static const globalDocPath = 'ops_integration_routing/global';

  static const defaults = OpsIntegrationRouting(
    victimVoiceTransport: VictimVoiceTransport.livekit,
    mapsTiles: OpsMapsTiles.google,
  );

  bool get useFirebasePttOnly =>
      victimVoiceTransport == VictimVoiceTransport.firebasePtt;

  factory OpsIntegrationRouting.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data();
    if (d == null) return defaults;
    return OpsIntegrationRouting(
      victimVoiceTransport: VictimVoiceTransport.fromFirestore(d['victimVoiceTransport']),
      mapsTiles: OpsMapsTiles.fromFirestore(d['mapsTiles']),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      updatedByUid: d['updatedByUid'] as String?,
      updatedByEmail: d['updatedByEmail'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'victimVoiceTransport': victimVoiceTransport.firestoreValue,
      'mapsTiles': mapsTiles.firestoreValue,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': FirebaseAuth.instance.currentUser?.uid ?? '',
      'updatedByEmail': FirebaseAuth.instance.currentUser?.email ?? '',
    };
  }
}

enum VictimVoiceTransport {
  livekit,
  firebasePtt;

  String get firestoreValue => switch (this) {
        livekit => 'livekit',
        firebasePtt => 'firebase_ptt',
      };

  static VictimVoiceTransport fromFirestore(Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s == 'firebase_ptt') return VictimVoiceTransport.firebasePtt;
    return VictimVoiceTransport.livekit;
  }
}

enum OpsMapsTiles {
  google,
  leaflet;

  String get firestoreValue => switch (this) {
        google => 'google',
        leaflet => 'leaflet',
      };

  static OpsMapsTiles fromFirestore(Object? v) {
    final s = v?.toString().trim() ?? '';
    if (s == 'leaflet') return OpsMapsTiles.leaflet;
    return OpsMapsTiles.google;
  }
}

abstract final class OpsIntegrationRoutingService {
  static final _db = FirebaseFirestore.instance;

  static Stream<OpsIntegrationRouting> watchGlobal() {
    return _db.doc(OpsIntegrationRouting.globalDocPath).snapshots().map(
          OpsIntegrationRouting.fromSnapshot,
        );
  }

  static Future<void> writeGlobal(OpsIntegrationRouting next) async {
    await _db.doc(OpsIntegrationRouting.globalDocPath).set(
          next.toFirestore(),
          SetOptions(merge: true),
        );
  }

  static Future<void> appendAudit({
    required String flag,
    required String oldValue,
    required String newValue,
  }) async {
    final u = FirebaseAuth.instance.currentUser;
    await _db.collection('ops_integration_routing_audit').add({
      'flag': flag,
      'oldValue': oldValue,
      'newValue': newValue,
      'uid': u?.uid ?? '',
      'email': u?.email ?? '',
      'ts': FieldValue.serverTimestamp(),
    });
  }
}
