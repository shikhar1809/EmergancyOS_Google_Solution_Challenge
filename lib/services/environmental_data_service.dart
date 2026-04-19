import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import 'emergency_services_data.dart';

class HexEnvironmentalData {
  final int aqi;
  final String category;
  final String dominantPollutant;
  final Color categoryColor;
  final String? healthRecommendation;

  /// Simulated heat stroke alert based loosely on random math for demonstration
  final String heatStrokeWarning;
  final bool hasHeatWarning;

  HexEnvironmentalData({
    required this.aqi,
    required this.category,
    required this.dominantPollutant,
    required this.categoryColor,
    this.healthRecommendation,
    required this.heatStrokeWarning,
    required this.hasHeatWarning,
  });
}

class EnvironmentalDataService {
  static const String _baseUrl = 'https://airquality.googleapis.com/v1/currentConditions:lookup';

  /// Maps Google Air Quality API result into app [AQIInfo] for map / health panels.
  static AQIInfo toAqiInfo(HexEnvironmentalData h) {
    final base = AQIInfo.fromAQI(h.aqi.toDouble());
    final heat = h.hasHeatWarning && h.heatStrokeWarning.isNotEmpty
        ? '\n${h.heatStrokeWarning}'
        : '';
    final impact = '${h.healthRecommendation ?? base.healthImpact}$heat';
    return AQIInfo(
      aqi: h.aqi.toDouble(),
      category: h.category,
      healthImpact: impact,
      advice: h.healthRecommendation ?? base.advice,
      maskAdvisory: base.maskAdvisory,
      isIndoorRecommended: h.aqi > 100,
      sensitiveGroups: base.sensitiveGroups,
      timestamp: DateTime.now(),
    );
  }

  static Future<HexEnvironmentalData?> fetchForLocation(LatLng location) async {
    final apiKey = AppConstants.googleMapsApiKey;
    if (apiKey.isEmpty) {
      debugPrint('[EnvironmentalDataService] Missing Google Maps API Key');
      return null;
    }

    try {
      final url = Uri.parse('$_baseUrl?key=$apiKey');
      final body = jsonEncode({
        "location": {
          "latitude": location.latitude,
          "longitude": location.longitude
        },
        "extraComputations": [
          "HEALTH_RECOMMENDATIONS"
        ]
      });

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final indexes = data['indexes'] as List<dynamic>?;
        if (indexes == null || indexes.isEmpty) return null;

        // Find Universal AQI or fallback to the first available index
        final uaqiObj = indexes.firstWhere(
          (idx) => idx['code'] == 'uaqi',
          orElse: () => indexes.first,
        );

        final aqi = uaqiObj['aqi'] as int? ?? 0;
        final categoryDisplay = uaqiObj['category'] as String? ?? 'Unknown';
        final dominantPollutant = uaqiObj['dominantPollutant'] as String? ?? 'N/A';
        
        final colorData = uaqiObj['color'] as Map<dynamic, dynamic>? ?? {};
        final red = ((colorData['red'] as num?)?.toDouble() ?? 0) * 255;
        final green = ((colorData['green'] as num?)?.toDouble() ?? 0) * 255;
        final blue = ((colorData['blue'] as num?)?.toDouble() ?? 0) * 255;
        final cColor = Color.fromARGB(255, red.toInt(), green.toInt(), blue.toInt());

        String? topRec;
        final recs = data['healthRecommendations'] as Map<String, dynamic>?;
        if (recs != null) {
          // Attempt to pull a general population recommendation
          topRec = recs['generalPopulation']?.toString();
        }

        // Simulate Heat Stroke warning based on coordinate hash and AQI for demo
        final hash = location.latitude.toStringAsFixed(2).hashCode ^ location.longitude.toStringAsFixed(2).hashCode;
        final randomSim = Random(hash);
        final tempC = 28 + randomSim.nextInt(15); // simulate temperature between 28 and 42 Celsius
        
        String heatWarning = 'No severe heat advisories.';
        bool hasHeatWarning = false;

        if (tempC >= 40) {
          heatWarning = 'Red Alert: Severe Heatstroke Risk ($tempC°C). Seek cooling shelters immediately.';
          hasHeatWarning = true;
        } else if (tempC >= 36) {
          heatWarning = 'Warning: High Heat Advisory ($tempC°C). Avoid prolonged outdoor exposure.';
          hasHeatWarning = true;
        }

        return HexEnvironmentalData(
          aqi: aqi,
          category: categoryDisplay,
          dominantPollutant: dominantPollutant,
          categoryColor: cColor,
          healthRecommendation: topRec,
          heatStrokeWarning: heatWarning,
          hasHeatWarning: hasHeatWarning,
        );
      } else {
        debugPrint('[EnvironmentalDataService] Failed with ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[EnvironmentalDataService] Error fetching environmental data: $e');
      return null;
    }
  }
}
