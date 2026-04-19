import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/foundation.dart';

/// EmergencyOS: AnalyticsInsight in lib/services/emergency_analytics_service.dart.
class AnalyticsInsight {
  final String explanation;
  final List<InsightMarker> markers;

  AnalyticsInsight({required this.explanation, required this.markers});
}

/// EmergencyOS: InsightMarker in lib/services/emergency_analytics_service.dart.
class InsightMarker {
  final LatLng position;
  final String label;

  InsightMarker({required this.position, required this.label});
}

/// EmergencyOS: EmergencyAnalyticsService in lib/services/emergency_analytics_service.dart.
///
/// Admin analytics insights powered by Gemini, routed through the server-side
/// `lifelineChat` Cloud Function (analyticsMode). No client-side API key is
/// required — the Gemini secret lives on Cloud Functions.
class EmergencyAnalyticsService {
  static const _scenario = 'Admin analytics insights (map markers + explanation)';

  static Future<AnalyticsInsight> getAdminInsights(String userPrompt) async {
    try {
      final db = FirebaseFirestore.instance;

      final archivedSnap = await db
          .collection('sos_incidents')
          .where('isArchived', isEqualTo: true)
          .orderBy('archivedAt', descending: true)
          .limit(100)
          .get();

      final activeSnap = await db
          .collection('sos_incidents')
          .where('isArchived', isEqualTo: false)
          .get();

      final allIncidents = [...archivedSnap.docs, ...activeSnap.docs].map((d) {
        final data = d.data();
        final loc = data['location'] as GeoPoint?;
        return {
          'id': d.id,
          'type': data['type'] ?? 'unknown',
          'status': data['status'] ?? 'unknown',
          'lat': loc?.latitude,
          'lng': loc?.longitude,
          'archived': data['isArchived'] ?? false,
        };
      }).toList();

      final digest =
          'Incident snapshot (count=${allIncidents.length}):\n${jsonEncode(allIncidents)}';

      final message = '''
User Query: $userPrompt

You MUST return ONLY a raw JSON object with EXACTLY two keys:
1. "explanation": conversational analytical findings (line breaks allowed).
2. "markers": array of at most 5 objects: { "lat": number, "lng": number, "label": string }.

No markdown fences, no prose outside the JSON.
''';

      final callable = FirebaseFunctions.instance.httpsCallable('lifelineChat');
      final res = await callable
          .call(<String, dynamic>{
            'message': message,
            'scenario': _scenario,
            'contextDigest': digest,
            'history': const <Map<String, String>>[],
            'analyticsMode': true,
          })
          .timeout(const Duration(seconds: 30));

      final data = (res.data as Map?) ?? const {};
      final status = (data['status'] as String?)?.trim() ?? 'ok';
      final text = (data['text'] as String?)?.trim() ?? '';

      if (status == 'offline') {
        throw Exception(
          'Analytics AI is offline on this project. Ask an admin to set GEMINI_API_KEY in Cloud Functions secrets.',
        );
      }
      if (text.isEmpty) {
        throw Exception('Empty response from analytics AI.');
      }

      var jsonText = text;
      if (jsonText.startsWith('```json')) {
        jsonText = jsonText.substring(7);
      } else if (jsonText.startsWith('```')) {
        jsonText = jsonText.substring(3);
      }
      if (jsonText.endsWith('```')) {
        jsonText = jsonText.substring(0, jsonText.length - 3);
      }

      final match = RegExp(r'\{[\s\S]*\}').firstMatch(jsonText.trim());
      final decoded = jsonDecode(match?.group(0) ?? jsonText.trim());

      final explanation =
          (decoded['explanation'] as String?)?.trim() ?? 'No explanation provided.';
      final List<dynamic> markersRaw = (decoded['markers'] as List?) ?? const [];

      final markers = <InsightMarker>[];
      for (final m in markersRaw) {
        if (m is! Map) continue;
        final lat = (m['lat'] as num?)?.toDouble();
        final lng = (m['lng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        markers.add(
          InsightMarker(
            position: LatLng(lat, lng),
            label: (m['label'] ?? 'Marker').toString(),
          ),
        );
      }

      return AnalyticsInsight(explanation: explanation, markers: markers);
    } catch (e, st) {
      debugPrint('EmergencyAnalyticsService Error: $e \n $st');
      throw Exception('Failed to generate insights: $e');
    }
  }
}
