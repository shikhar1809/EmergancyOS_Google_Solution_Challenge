import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Fleet operator–authored handoff notes + photo URLs for an incident.
@immutable
class FleetOperatorHandoffDraft {
  const FleetOperatorHandoffDraft({
    required this.notesText,
    required this.photoUrls,
    this.v2Data = const {},
    this.updatedAt,
  });

  final String notesText;
  final List<String> photoUrls;
  final Map<String, dynamic> v2Data;
  final DateTime? updatedAt;

  factory FleetOperatorHandoffDraft.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    final urls = d['photoUrls'];
    final list = <String>[];
    if (urls is List) {
      for (final e in urls) {
        if (e is String && e.trim().isNotEmpty) list.add(e.trim());
      }
    }
    final t = d['updatedAt'];
    return FleetOperatorHandoffDraft(
      notesText: (d['notesText'] as String?)?.trim() ?? '',
      photoUrls: list,
      v2Data: (d['v2Data'] as Map<String, dynamic>?) ?? {},
      updatedAt: t is Timestamp ? t.toDate() : null,
    );
  }
}

abstract final class FleetOperatorHandoffService {
  static final _db = FirebaseFirestore.instance;
  static final _storage = FirebaseStorage.instance;

  static DocumentReference<Map<String, dynamic>> _ref(String incidentId, String operatorUid) {
    return _db
        .collection('sos_incidents')
        .doc(incidentId.trim())
        .collection('fleet_operator_handoff')
        .doc(operatorUid.trim());
  }

  static Stream<FleetOperatorHandoffDraft?> watchDraft(String incidentId, String operatorUid) {
    final id = incidentId.trim();
    final uid = operatorUid.trim();
    if (id.isEmpty || uid.isEmpty) {
      return const Stream.empty();
    }
    return _ref(id, uid).snapshots().map((s) {
      if (!s.exists || s.data() == null) return null;
      return FleetOperatorHandoffDraft.fromFirestore(s);
    });
  }

  static Future<void> saveDraft(
    String incidentId,
    String operatorUid, {
    required String notesText,
    required List<String> photoUrls,
    Map<String, dynamic>? v2Data,
  }) async {
    final id = incidentId.trim();
    final uid = operatorUid.trim();
    if (id.isEmpty || uid.isEmpty) {
      throw ArgumentError('incidentId and operatorUid are required for handoff save');
    }
    await _ref(id, uid).set(
      {
        'notesText': notesText,
        'photoUrls': photoUrls,
        if (v2Data != null) 'v2Data': v2Data,
        'updatedAt': FieldValue.serverTimestamp(),
        'operatorUid': uid,
      },
    );
  }

  static Future<String> uploadPhoto(
    String incidentId,
    String operatorUid,
    Uint8List bytes,
    String fileName,
  ) async {
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'sos_incidents/${incidentId.trim()}/fleet_handoff/${operatorUid.trim()}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = _storage.ref(path);
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }
}
