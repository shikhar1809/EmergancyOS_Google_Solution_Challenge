import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'emergency_services_data.dart';

/// Server-side hybrid health alerts (ReliefWeb + Gemini search fallback).
abstract final class RegionalHealthAlertsService {
  static Future<List<DiseaseOutbreak>> fetchForLocation({
    required double lat,
    required double lng,
    String? countryCodeIso2,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('getRegionalHealthAlerts');
      final iso = (countryCodeIso2 ?? 'IN').trim();
      final result = await callable.call(<String, dynamic>{
        'lat': lat,
        'lng': lng,
        if (iso.length == 2) 'countryCode': iso.toUpperCase(),
      });
      final raw = result.data;
      if (raw is! Map) return [];
      final list = raw['outbreaks'];
      if (list is! List) return [];
      final out = <DiseaseOutbreak>[];
      for (final item in list) {
        if (item is Map) {
          try {
            out.add(DiseaseOutbreak.fromJson(Map<String, dynamic>.from(item)));
          } catch (e) {
            debugPrint('[RegionalHealthAlerts] skip item: $e');
          }
        }
      }
      return out;
    } catch (e) {
      debugPrint('[RegionalHealthAlerts] callable failed: $e');
      return [];
    }
  }
}
