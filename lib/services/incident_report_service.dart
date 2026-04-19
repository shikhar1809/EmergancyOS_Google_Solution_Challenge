import 'package:cloud_firestore/cloud_firestore.dart';

import 'incident_service.dart';

/// Builds and stores narrative incident reports for sharing and audit.
class IncidentReportService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String goodSamaritanShieldText =
      'This report documents bystander assistance provided in good faith '
      'during an emergency. Nothing in this document should be interpreted '
      'as a waiver of Good Samaritan protections available under applicable law.';

  /// Compose a simple narrative from the SosIncident snapshot.
  static Map<String, dynamic> buildReportPayload(SosIncident inc) {
    final now = DateTime.now();
    final Map<String, dynamic> triage = inc.triage ?? const {};

    final buffer = StringBuffer()
      ..writeln('Incident ID: ${inc.id}')
      ..writeln('Type: ${inc.type}')
      ..writeln('Reported at: ${inc.timestamp.toIso8601String()}')
      ..writeln('Location: ${inc.location.latitude}, ${inc.location.longitude}')
      ..writeln()
      ..writeln('Status: ${inc.status.name}')
      ..writeln('Lifecycle: ${inc.lifecyclePhaseLabel}')
      ..writeln();

    if (inc.firstAcknowledgedAt != null) {
      buffer.writeln('First acknowledgement at: ${inc.firstAcknowledgedAt!.toIso8601String()}');
    }
    if (inc.emsAcceptedAt != null) {
      buffer.writeln('EMS accepted at: ${inc.emsAcceptedAt!.toIso8601String()}');
    }
    if (inc.emsOnSceneAt != null) {
      buffer.writeln('EMS on scene at: ${inc.emsOnSceneAt!.toIso8601String()}');
    }
    if (inc.emsRescueCompleteAt != null) {
      buffer.writeln('EMS rescue complete (scene) at: ${inc.emsRescueCompleteAt!.toIso8601String()}');
    }
    if (inc.emsReturningStartedAt != null) {
      buffer.writeln('EMS returning started at: ${inc.emsReturningStartedAt!.toIso8601String()}');
    }
    if (inc.emsHospitalArrivalAt != null) {
      buffer.writeln('EMS hospital arrival at: ${inc.emsHospitalArrivalAt!.toIso8601String()}');
    }
    if (inc.emsResponseCompleteAt != null) {
      buffer.writeln('EMS response complete at: ${inc.emsResponseCompleteAt!.toIso8601String()}');
    }

    final rescueDurationSeconds = (inc.emsRescueCompleteAt != null && inc.emsAcceptedAt != null)
        ? inc.emsRescueCompleteAt!.difference(inc.emsAcceptedAt!).inSeconds
        : null;
    final returnDurationSeconds = (inc.emsResponseCompleteAt != null && inc.emsReturningStartedAt != null)
        ? inc.emsResponseCompleteAt!.difference(inc.emsReturningStartedAt!).inSeconds
        : null;
    final totalCycleSeconds = inc.emsResponseCompleteAt != null
        ? inc.emsResponseCompleteAt!.difference(inc.timestamp).inSeconds
        : null;
    if (rescueDurationSeconds != null) {
      buffer.writeln('Rescue duration (accept → rescue complete): ${rescueDurationSeconds}s');
    }
    if (returnDurationSeconds != null) {
      buffer.writeln('Return leg duration (returning start → response complete): ${returnDurationSeconds}s');
    }
    if (totalCycleSeconds != null) {
      buffer.writeln('Total response cycle (SOS → response complete): ${totalCycleSeconds}s');
    }

    buffer.writeln();
    buffer.writeln('Victim medical snapshot:');
    buffer.writeln('  Blood type: ${inc.bloodType ?? "-"}');
    buffer.writeln('  Allergies: ${inc.allergies ?? "-"}');
    buffer.writeln('  Conditions: ${inc.medicalConditions ?? "-"}');

    if (triage.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Triage summary:');
      triage.forEach((k, v) {
        buffer.writeln('  $k: $v');
      });
    }

    buffer.writeln();
    buffer.writeln('Good Samaritan Shield:');
    buffer.writeln(goodSamaritanShieldText);

    return <String, dynamic>{
      'incidentId': inc.id,
      'userId': inc.userId,
      if ((inc.returnHospitalId ?? '').trim().isNotEmpty)
        'acceptedHospitalId': inc.returnHospitalId!.trim(),
      'type': inc.type,
      'status': inc.status.name,
      'createdAt': now.toIso8601String(),
      'narrative': buffer.toString(),
      'triage': triage,
      'goodSamaritanShield': goodSamaritanShieldText,
      if (inc.emsRescueCompleteAt != null) 'emsRescueCompleteAt': inc.emsRescueCompleteAt!.toIso8601String(),
      if (inc.emsReturningStartedAt != null) 'emsReturningStartedAt': inc.emsReturningStartedAt!.toIso8601String(),
      if (inc.emsHospitalArrivalAt != null) 'emsHospitalArrivalAt': inc.emsHospitalArrivalAt!.toIso8601String(),
      if (inc.emsResponseCompleteAt != null) 'emsResponseCompleteAt': inc.emsResponseCompleteAt!.toIso8601String(),
      if (rescueDurationSeconds != null) 'rescueDurationSeconds': rescueDurationSeconds,
      if (returnDurationSeconds != null) 'returnDurationSeconds': returnDurationSeconds,
      if (totalCycleSeconds != null) 'totalCycleSeconds': totalCycleSeconds,
    };
  }

  /// One-tap plaintext for ER handoff / SMS (kept short for radio + clipboard).
  static String buildTriageHandoffCard(SosIncident inc) {
    final triage = inc.triage ?? const <String, dynamic>{};
    final sev = (triage['severity'] ?? triage['triageLevel'] ?? triage['level'])
        ?.toString()
        .trim();
    final buf = StringBuffer()
      ..writeln('EMERGENCYOS PRE-ARRIVAL')
      ..writeln('ID: ${inc.id}')
      ..writeln('Type: ${inc.type}')
      ..writeln('Status: ${inc.status.name}')
      ..writeln('Pin: ${inc.liveVictimPin.latitude.toStringAsFixed(5)},${inc.liveVictimPin.longitude.toStringAsFixed(5)}');
    if (sev != null && sev.isNotEmpty) buf.writeln('Triage: $sev');
    if ((inc.ambulanceEta ?? '').trim().isNotEmpty) {
      buf.writeln('Ambulance ETA: ${inc.ambulanceEta!.trim()}');
    }
    buf.writeln('Blood: ${inc.bloodType ?? "—"}');
    buf.writeln('Allergies: ${inc.allergies ?? "—"}');
    buf.writeln('Conditions: ${inc.medicalConditions ?? "—"}');
    if ((inc.emergencyContactPhone ?? '').trim().isNotEmpty) {
      buf.writeln('ICE phone: ${inc.emergencyContactPhone!.trim()}');
    }
    var s = buf.toString().trim();
    if (s.length > 480) s = '${s.substring(0, 477)}...';
    return s;
  }

  /// Generate and persist a report document under `sos_incidents/{id}/incident_reports`.
  static Future<void> generateAndStoreReport(SosIncident incident) async {
    final payload = buildReportPayload(incident);
    await _db
        .collection('sos_incidents')
        .doc(incident.id)
        .collection('incident_reports')
        .add(<String, dynamic>{
      ...payload,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

