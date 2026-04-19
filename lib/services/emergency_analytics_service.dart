import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
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
class EmergencyAnalyticsService {
  // Replace with the actual API Key or utilize firebase extensions logic if preferred.
  // For the solution challenge demo, injecting via dart-define or env is standard.
  static const String _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  
  static Future<AnalyticsInsight> getAdminInsights(String userPrompt) async {
    if (_geminiApiKey.isEmpty) {
      throw Exception('Gemini API Key is missing. Add --dart-define=GEMINI_API_KEY=your_key to your build command.');
    }

    try {
      // 1. Fetch raw data
      final db = FirebaseFirestore.instance;
      // Fetch up to 100 recent archived incidents (for historical hotspotting)
      final archivedSnap = await db
          .collection('sos_incidents')
          .where('isArchived', isEqualTo: true)
          .orderBy('archivedAt', descending: true)
          .limit(100)
          .get();

      // Fetch active
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

      final dataDump = jsonEncode(allIncidents);

      // 2. Initialize Gemini
      final model = GenerativeModel(
        model: 'gemini-2.5-flash', 
        apiKey: _geminiApiKey,
        systemInstruction: Content.system('''
You are an expert emergency response data analyst. You will be provided with a JSON dump of historic and active SOS incidents.
The user is an Emergency System Admin.
When responding to the user's query, you MUST return a strict JSON object with EXACTLY two keys:
1. "explanation": A detailed, conversational text string explaining your analytical findings and rationale. Format with line breaks if necessary.
2. "markers": A JSON array of objects, containing { "lat": double, "lng": double, "label": "Short String Label" }. Limit to maximum 5 markers.

DO NOT return any markdown formatting outside of the JSON block. Return ONLY the raw JSON object.
'''),
      );

      final prompt = 'User Query: $userPrompt\n\nIncident Data: $dataDump';
      
      final response = await model.generateContent([Content.text(prompt)]);
      final text = response.text?.trim() ?? '';
      
      // Clean up markdown json blocks if gemini included them despite instructions
      String jsonText = text;
      if (jsonText.startsWith('```json')) {
        jsonText = jsonText.substring(7);
        if (jsonText.endsWith('```')) {
          jsonText = jsonText.substring(0, jsonText.length - 3);
        }
      } else if (jsonText.startsWith('```')) {
         jsonText = jsonText.substring(3);
         if (jsonText.endsWith('```')) {
          jsonText = jsonText.substring(0, jsonText.length - 3);
        }
      }

      final decoded = jsonDecode(jsonText.trim());
      
      final explanation = decoded['explanation'] ?? 'No explanation provided.';
      final List<dynamic> markersRaw = decoded['markers'] ?? [];
      
      final markers = markersRaw.map((m) {
        return InsightMarker(
          position: LatLng(m['lat'] as double, m['lng'] as double),
          label: (m['label'] ?? 'Marker').toString(),
        );
      }).toList();

      return AnalyticsInsight(explanation: explanation, markers: markers);
    } catch (e, st) {
      debugPrint('EmergencyAnalyticsService Error: $e \n $st');
      throw Exception('Failed to generate insights: $e');
    }
  }
}
