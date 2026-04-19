import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/constants/india_ops_zones.dart';
import 'incident_service.dart';
import 'ops_analytics_derived.dart';
import 'ops_incident_analytics_digest.dart';

/// Shared Firestore digest + `lifelineChat` callable for Analytics and Insights consoles.
abstract final class OpsLifelineAnalyticsChat {
  static bool excludeTrainingIncident(SosIncident e) {
    final id = e.id;
    return id.startsWith('demo_') || id.startsWith('demo_ops_');
  }

  /// [history] = prior turns only (do not include the current user message).
  static Future<String> send({
    required String message,
    required IndiaOpsZone zone,
    required List<Map<String, String>> history,
    required String scenario,
    bool analyticsMode = true,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('sos_incidents')
        .limit(500)
        .get();
    final all = snap.docs
        .map(SosIncident.fromFirestore)
        .where((e) => !excludeTrainingIncident(e))
        .toList();
    final nowAi = DateTime.now();
    final inZ = all.where((e) => zone.containsLatLng(e.liveVictimPin)).toList();
    final inc48 = inZ
        .where(
          (e) => nowAi.difference(e.timestamp) <= const Duration(hours: 48),
        )
        .toList();
    final inc7d = inZ
        .where(
          (e) => nowAi.difference(e.timestamp) <= const Duration(days: 7),
        )
        .toList();
    final trend7 = OpsAnalyticsDerived.sevenDayCountsInZone(inZ, nowAi);
    final b48 = OpsAnalyticsDerived.hexBinsForIncidents(inc48, zone);
    final b7d = OpsAnalyticsDerived.hexBinsForIncidents(inc7d, zone);
    final digest = OpsIncidentAnalyticsDigest.build(all, zone: zone);
    final augment = OpsAnalyticsDerived.augmentForGemini(
      trend7: trend7,
      hotspot48h: OpsAnalyticsDerived.hotspotSummary(b48, zone),
      hotspot7d: OpsAnalyticsDerived.hotspotSummary(b7d, zone),
    );
    final fullDigest = '$digest\n$augment';

    final callable = FirebaseFunctions.instance.httpsCallable('lifelineChat');
    final res = await callable.call({
      'message': message,
      'scenario': scenario,
      'contextDigest': fullDigest,
      'history': history,
      'analyticsMode': analyticsMode,
    });
    final raw = res.data;
    final Map<String, dynamic> data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final status = (data['status'] as String?)?.trim() ?? 'ok';
    var reply = (data['text'] as String?)?.trim() ?? 'No response.';
    if (status == 'rate_limited') {
      reply = '[Rate limited] $reply';
    } else if (status == 'offline') {
      reply = '[Analytics AI offline] $reply';
    }
    return reply;
  }
}
