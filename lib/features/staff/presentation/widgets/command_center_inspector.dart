// Command-center inspector keeps a few private helpers reserved for the
// forthcoming video-assessment and fleet detail rows.
// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/constants/india_ops_zones.dart';
import '../../../../core/utils/fleet_unit_availability.dart';
import '../../../../firebase_options.dart';
import '../../../../core/widgets/shared_situation_brief_card.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/dispatch_incident_priority.dart';
import '../../../../features/map/domain/emergency_zone_classification.dart';
import '../../../../services/fleet_unit_service.dart';
import '../../../../services/incident_service.dart';
import '../../../../services/incident_report_service.dart';
import '../../../../services/ops_incident_hospital_assignment_service.dart';
import '../../../../services/gemini_dispatch_advisory_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

import 'command_center_shared_widgets.dart';

/// Full incident control surface: mirrors victim SOS + volunteer consignment fields with one-tap actions.
class CommandCenterInspector extends StatefulWidget {
  const CommandCenterInspector({
    super.key,
    required this.incident,
    required this.opsZone,
    required this.sceneIncidentTier,
    required this.fleetDocs,
    this.boundHospitalDocId,
    this.showMasterHospitalControls = false,
    required this.noteController,
    required this.etaAmbController,
    required this.medLineController,
    required this.incidentTypeController,
    required this.onSaveNote,
    required this.onSaveDispatchFields,
    required this.onAfterMutation,
  });

  final SosIncident incident;
  /// Medical ops: `ops_hospitals` doc id — used to show accept/decline when this hospital is notified.
  final String? boundHospitalDocId;
  /// Master console: accept/skip hospital chain and restart dispatch without a bound hospital doc.
  final bool showMasterHospitalControls;
  final IndiaOpsZone opsZone;
  /// Hex coverage tier at the victim pin (for dispatch priority badge).
  final TierHealth sceneIncidentTier;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> fleetDocs;
  final TextEditingController noteController;
  final TextEditingController etaAmbController;
  final TextEditingController medLineController;
  final TextEditingController incidentTypeController;
  final VoidCallback onSaveNote;
  final Future<void> Function() onSaveDispatchFields;
  final VoidCallback onAfterMutation;

  @override
  State<CommandCenterInspector> createState() => _CommandCenterInspectorState();
}

class _CommandCenterInspectorState extends State<CommandCenterInspector> {
  /// Hospital accept/decline run in us-east1 (Cloud Run CPU quota in us-central1).
  static final _functionsUsEast1 = FirebaseFunctions.instanceFor(region: 'us-east1');

  final _broadcastCtrl = TextEditingController();
  final _ambDriverUidCtrl = TextEditingController();
  bool _hospitalDispatchBusy = false;
  bool _restartHospitalDispatchBusy = false;
  bool _timelineExpanded = false;
  final _familyNameCtrl = TextEditingController();
  final _familyPhoneCtrl = TextEditingController();

  // Gemini advisory state (non-critical, informational only)
  bool _geminiHospitalExplainLoading = false;
  String? _geminiHospitalExplainText;

  @override
  void dispose() {
    _broadcastCtrl.dispose();
    _ambDriverUidCtrl.dispose();
    _familyNameCtrl.dispose();
    _familyPhoneCtrl.dispose();
    super.dispose();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _closestFleetByType(String vehicleType, {int limit = 4}) {
    final v = widget.incident.liveVictimPin;
    final z = widget.opsZone;
    final rows = <({double d, QueryDocumentSnapshot<Map<String, dynamic>> doc})>[];
    for (final d in widget.fleetDocs) {
      final data = d.data();
      if (!fleetUnitIsStaffedAvailable(data, d.id)) continue;
      final vt = (data['vehicleType'] as String?)?.trim() ?? '';
      if (vt != vehicleType) continue;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final p = LatLng(lat, lng);
      if (!z.containsLatLng(p)) continue;
      final dist = Geolocator.distanceBetween(v.latitude, v.longitude, lat, lng);
      rows.add((d: dist, doc: d));
    }
    rows.sort((a, b) => a.d.compareTo(b.d));
    return rows.take(limit).map((e) => e.doc).toList();
  }

  String _fleetDistLabel(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final v = widget.incident.liveVictimPin;
    final lat = (doc.data()['lat'] as num?)?.toDouble();
    final lng = (doc.data()['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return '';
    final m = Geolocator.distanceBetween(v.latitude, v.longitude, lat, lng);
    final etaMins = (m / 1000 / 40 * 60).round(); // Assuming 40 km/h average city speed
    final etaLabel = etaMins > 0 ? ' (ETA: ~$etaMins min)' : ' (Arriving)';
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km$etaLabel';
    return '${m.round()} m$etaLabel';
  }

  Widget _closestFleetBlock(String title, String vehicleType, Future<void> Function(String uid) assign) {
    final closest = _closestFleetByType(vehicleType);
    if (closest.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          context.opsTr('No available {title} units in zone with live GPS.').replaceAll('{title}', title),
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          for (final d in closest)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${d.id.length <= 10 ? d.id : '${d.id.substring(0, 8)}…'} · ${_fleetDistLabel(d)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () async {
                      try {
                        await assign(d.id);
                        await FleetUnitService.markAssignedToIncident(operatorUid: d.id, incidentId: widget.incident.id);
                        widget.onAfterMutation();
                        await _snack('$title allotted', ok: true);
                      } catch (e) {
                        await _snack(e);
                      }
                    },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    child: Text(context.opsTr('Allot'), style: TextStyle(fontSize: 10)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Pre-arrival handoff packet produced by Gemini when the ambulance is ~2
  /// minutes out. Shown prominently so the trauma team can prep the bay before
  /// the ambulance rolls in.
  Widget _preArrivalHandoffCard(SosIncident inc) {
    final h = inc.preArrivalHandoff;
    if (h == null) return const SizedBox.shrink();
    final status = (h['status'] ?? '').toString();
    if (status != 'ready') return const SizedBox.shrink();
    final snapshot = (h['patientSnapshot'] ?? '').toString().trim();
    final presentation = (h['likelyPresentation'] ?? '').toString().trim();
    final prepareRoom = (h['prepareRoom'] is List)
        ? (h['prepareRoom'] as List).map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final prepareTeam = (h['prepareTeam'] is List)
        ? (h['prepareTeam'] as List).map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final bloodAndMeds = (h['bloodAndMeds'] is List)
        ? (h['bloodAndMeds'] as List).map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final contraindications = (h['contraindications'] is List)
        ? (h['contraindications'] as List).map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
        : const <String>[];
    final hospitalName = (h['hospitalName'] ?? '').toString().trim();
    final etaSec = (h['etaSeconds'] is num) ? (h['etaSeconds'] as num).round() : 0;

    Widget sectionList(String title, IconData icon, Color color, List<String> items) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
            ]),
            const SizedBox(height: 4),
            ...items.take(6).map((s) => Padding(
                  padding: const EdgeInsets.only(top: 3, left: 18),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('• ', style: TextStyle(color: color, fontSize: 12)),
                    Expanded(child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35))),
                  ]),
                )),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.55), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withValues(alpha: 0.15),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: Colors.redAccent, size: 18),
              const SizedBox(width: 6),
              const Text('PRE-ARRIVAL HANDOFF',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (etaSec > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('ETA ${etaSec}s',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w900)),
                ),
            ],
          ),
          if (hospitalName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Receiving: $hospitalName',
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
          if (snapshot.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(snapshot, style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600)),
          ],
          if (presentation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(presentation, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35, fontStyle: FontStyle.italic)),
          ],
          sectionList('PREPARE ROOM', Icons.meeting_room_rounded, Colors.amberAccent, prepareRoom),
          sectionList('PAGE TEAM', Icons.people_alt_rounded, const Color(0xFF64B5F6), prepareTeam),
          sectionList('BLOOD / MEDS', Icons.bloodtype_rounded, Colors.redAccent, bloodAndMeds),
          sectionList('CONTRAINDICATIONS', Icons.warning_rounded, Colors.orangeAccent, contraindications),
        ],
      ),
    );
  }

  /// Short Gemini-written explanation for why the current hospital was chosen
  /// by the dispatch engine (`aiHospitalRationale` on the incident doc).
  Widget _aiHospitalRationaleCard(SosIncident inc) {
    final r = inc.aiHospitalRationale;
    if (r == null) return const SizedBox.shrink();
    final text = (r['text'] ?? '').toString().trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final hospital = (r['hospitalName'] ?? '').toString().trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFBA68C8).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBA68C8).withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_hospital_rounded, color: Color(0xFFBA68C8), size: 16),
              const SizedBox(width: 6),
              const Text('GEMINI HOSPITAL RATIONALE',
                  style: TextStyle(color: Color(0xFFBA68C8), fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w900)),
              const Spacer(),
              if (hospital.isNotEmpty)
                Flexible(
                  child: Text(
                    hospital,
                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }

  /// Surfaces the Gemini vision triage (written by `applyAiTriageToIncident`)
  /// as a visible dispatch decision in the command center. If no AI triage is
  /// present, the widget collapses to nothing.
  Widget _aiTriageCard(SosIncident inc) {
    final triage = inc.triage;
    if (triage == null) return const SizedBox.shrink();
    final aiVision = triage['aiVision'];
    if (aiVision is! Map) return const SizedBox.shrink();
    final severity = (aiVision['severity'] ?? '').toString().toLowerCase();
    final category = (aiVision['category'] ?? '').toString();
    final specialty = (aiVision['aiRecommendedSpecialty'] ?? '').toString();
    final confidence = (aiVision['confidence'] ?? 'medium').toString();
    final analysis = (aiVision['analysis'] ?? '').toString();
    final steps = (aiVision['steps'] is List)
        ? (aiVision['steps'] as List).map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
        : const <String>[];

    final severityColor = switch (severity) {
      'red' => Colors.redAccent,
      'yellow' => Colors.amberAccent,
      'black' => Colors.white70,
      _ => Colors.greenAccent,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Colors.cyanAccent, size: 16),
              const SizedBox(width: 6),
              const Text('GEMINI TRIAGE VISION',
                  style: TextStyle(color: Colors.cyanAccent, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w900)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: severityColor.withValues(alpha: 0.6)),
                ),
                child: Text(severity.toUpperCase(),
                    style: TextStyle(color: severityColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (category.isNotEmpty)
                _chip(label: 'category: $category', color: Colors.white70),
              if (specialty.isNotEmpty)
                _chip(label: 'AI routed → $specialty', color: Colors.cyanAccent),
              _chip(label: 'confidence: $confidence', color: Colors.white54),
            ],
          ),
          if (analysis.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(analysis, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...steps.take(5).map((s) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('• ', style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                    Expanded(child: Text(s, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35))),
                  ]),
                )),
          ],
          const SizedBox(height: 6),
          const Text(
            'Hospital dispatch chain has been re-ranked using this specialty recommendation.',
            style: TextStyle(color: Colors.white38, fontSize: 10, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _chip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _dispatchPriorityBanner(SosIncident inc) {
    final pri = DispatchIncidentPriority.forIncident(inc, widget.sceneIncidentTier);
    final c = switch (pri.label) {
      'P1' => Colors.redAccent,
      'P2' => Colors.orangeAccent,
      'P3' => Colors.amberAccent,
      _ => Colors.lightBlueAccent,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.withValues(alpha: 0.55)),
            ),
            child: Text(
              pri.label,
              style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Dispatch priority · score ${pri.score} · coverage cell: ${widget.sceneIncidentTier.name}',
              style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _incidentTimelineTiles(SosIncident inc) {
    final fmt = DateFormat.MMMd().add_Hm();
    final entries = <({DateTime t, String line})>[];
    entries.add((t: inc.timestamp, line: 'SOS reported'));
    if (inc.firstAcknowledgedAt != null) {
      entries.add((t: inc.firstAcknowledgedAt!, line: 'First acknowledgement'));
    }
    if (inc.emsAcceptedAt != null) {
      entries.add((t: inc.emsAcceptedAt!, line: 'Ambulance / EMS accepted'));
    }
    if (inc.emsOnSceneAt != null) {
      entries.add((t: inc.emsOnSceneAt!, line: 'EMS on scene'));
    }
    if (inc.emsRescueCompleteAt != null) {
      entries.add((t: inc.emsRescueCompleteAt!, line: 'Rescue complete (scene)'));
    }
    if (inc.emsReturningStartedAt != null) {
      entries.add((t: inc.emsReturningStartedAt!, line: 'Returning to hospital'));
    }
    if (inc.emsHospitalArrivalAt != null) {
      entries.add((t: inc.emsHospitalArrivalAt!, line: 'Arrived at hospital'));
    }
    if (inc.emsResponseCompleteAt != null) {
      final total = inc.emsResponseCompleteAt!.difference(inc.timestamp);
      final m = total.inMinutes;
      final s = total.inSeconds % 60;
      entries.add((t: inc.emsResponseCompleteAt!, line: 'Response complete · total cycle ${m}m ${s}s'));
    }
    if (inc.acceptedVolunteerIds.isNotEmpty) {
      entries.add((t: inc.volunteerUpdatedAt ?? inc.timestamp, line: 'Volunteers accepted: ${inc.acceptedVolunteerIds.length}'));
    }
    if (inc.onSceneVolunteerIds.isNotEmpty) {
      entries.add((t: inc.volunteerUpdatedAt ?? inc.timestamp, line: 'On-scene volunteers: ${inc.onSceneVolunteerIds.length}'));
    }
    entries.sort((a, b) => a.t.compareTo(b.t));
    return entries
        .map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 108,
                  child: Text(
                    fmt.format(e.t.toLocal()),
                    style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
                Expanded(
                  child: Text(e.line, style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.25)),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  Future<void> _snack(Object e, {bool ok = false}) async {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? e.toString() : 'Error: $e'),
        backgroundColor: ok ? AppColors.primarySafe : AppColors.primaryDanger,
      ),
    );
  }

  Future<void> _acceptHospitalDispatch(String hospitalId) async {
    if (_hospitalDispatchBusy || hospitalId.isEmpty) return;
    setState(() => _hospitalDispatchBusy = true);
    try {
      final callable = _functionsUsEast1.httpsCallable('acceptHospitalDispatch');
      await callable.call(<String, dynamic>{'incidentId': widget.incident.id, 'hospitalId': hospitalId});
      widget.onAfterMutation();
      await _snack('Hospital accepted dispatch', ok: true);
    } catch (e) {
      await _snack(e);
    } finally {
      if (mounted) setState(() => _hospitalDispatchBusy = false);
    }
  }

  Future<void> _declineHospitalDispatch(String hospitalId) async {
    if (_hospitalDispatchBusy || hospitalId.isEmpty) return;
    setState(() => _hospitalDispatchBusy = true);
    try {
      final callable = _functionsUsEast1.httpsCallable('declineHospitalDispatch');
      await callable.call(<String, dynamic>{'incidentId': widget.incident.id, 'hospitalId': hospitalId});
      widget.onAfterMutation();
      await _snack('Declined — dispatch escalated to next hospital', ok: true);
    } catch (e) {
      await _snack(e);
    } finally {
      if (mounted) setState(() => _hospitalDispatchBusy = false);
    }
  }

  Future<void> _adminRestartHospitalDispatch() async {
    if (_restartHospitalDispatchBusy) return;
    setState(() => _restartHospitalDispatchBusy = true);
    try {
      final callable = _functionsUsEast1.httpsCallable('adminRestartHospitalDispatch');
      await callable.call(<String, dynamic>{'incidentId': widget.incident.id});
      widget.onAfterMutation();
      await _snack('Hospital dispatch restarted', ok: true);
    } catch (e) {
      await _snack(e);
    } finally {
      if (mounted) setState(() => _restartHospitalDispatchBusy = false);
    }
  }

  String _videoAssessmentLine(String k, Object? v) {
    if (v == null) return '';
    if (v is Timestamp) {
      return DateFormat.MMMd().add_Hm().format(v.toDate().toLocal());
    }
    final s = v.toString().trim();
    return s.isEmpty ? '' : s;
  }

  String _triageOneLiner(Map<String, dynamic>? t) {
    if (t == null || t.isEmpty) return 'No triage snapshot yet.';
    final cat = t['category']?.toString() ?? '—';
    final notes = t['notes']?.toString().trim() ?? '';
    final score = t['severityScore'];
    final flags = (t['severityFlags'] as List?)?.cast<dynamic>().join(', ') ?? '';
    final buf = StringBuffer('Category: $cat');
    if (score != null) buf.write(' · score $score');
    if (flags.isNotEmpty) buf.write(' · $flags');
    if (notes.isNotEmpty) buf.write('\n$notes');
    return buf.toString();
  }

  Widget _assignedFleetRow(String label, String driverId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$label: ${driverId.length > 12 ? '${driverId.substring(0, 10)}...' : driverId}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          FilledButton.icon(
            onPressed: () => context.push('/ptt-channel/${Uri.encodeComponent('ops_$driverId')}?type=fleet_operations'),
            icon: const Icon(Icons.headset_mic, size: 14),
            label: Text(context.opsTr('Connect to Driver'), style: TextStyle(fontSize: 10)),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ],
      ),
    );
  }

  String _sceneReportPreview(Map<String, dynamic>? r) {
    if (r == null || r.isEmpty) return 'No volunteer scene report filed.';
    try {
      const encoder = JsonEncoder.withIndent('  ');
      final s = encoder.convert(r);
      return s.length > 1200 ? '${s.substring(0, 1200)}…' : s;
    } catch (_) {
      return r.toString();
    }
  }

  Future<void> _postBroadcast() async {
    final t = _broadcastCtrl.text.trim();
    if (t.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(widget.incident.id)
          .collection('victim_activity')
          .add({
        'text': 'Dispatch: $t',
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'command_center',
      });
      _broadcastCtrl.clear();
      widget.onAfterMutation();
      await _snack('Posted to victim / volunteer live feed', ok: true);
    } catch (e) {
      await _snack(e);
    }
  }

  Future<void> _loadGeminiHospitalExplain(OpsIncidentHospitalAssignment assignment) async {
    if (_geminiHospitalExplainLoading) return;
    setState(() {
      _geminiHospitalExplainLoading = true;
      _geminiHospitalExplainText = null;
    });
    try {
      final assignmentInfo = StringBuffer()
        ..writeln('Primary hospital: ${assignment.primaryHospitalName ?? assignment.primaryHospitalId ?? "—"}')
        ..writeln('Status: ${assignment.dispatchStatus ?? "—"}')
        ..writeln('Ambulance ops: ${assignment.ambulanceDispatchStatus ?? "—"}')
        ..writeln('Cascade order: ${assignment.orderedHospitalIds.take(8).join(" → ")}');
      if (assignment.acceptedHospitalName != null) {
        assignmentInfo.writeln('Accepted by: ${assignment.acceptedHospitalName}');
      }
      final text = await GeminiDispatchAdvisoryService.generateIncidentSituationSummary(
        incident: widget.incident,
        hospitalAssignmentInfo: assignmentInfo.toString(),
      );
      if (!mounted) return;
      setState(() => _geminiHospitalExplainText = text ?? 'Could not generate explanation.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _geminiHospitalExplainText = 'Advisory unavailable: $e');
    } finally {
      if (mounted) setState(() => _geminiHospitalExplainLoading = false);
    }
  }

  Future<void> _confirmArchive() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'ops';
    final master = widget.showMasterHospitalControls;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate800,
        title: Text(
          master ? 'Stop operation (resolved)?' : 'Archive incident?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          master
              ? 'Archives this incident as resolved, removes it from the active list, and ends dispatch for responders.'
              : 'Copies the document to archive and removes it from the active list. Responder closure XP may apply.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.opsTr('Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryDanger),
            child: Text(master ? 'Stop & archive' : 'Archive'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    try {
      await IncidentService.archiveAndCloseIncident(
        incidentId: widget.incident.id,
        status: 'resolved',
        closedByUid: uid,
      );
      widget.onAfterMutation();
      await _snack(master ? 'Operation stopped' : 'Archived', ok: true);
    } catch (e) {
      await _snack(e);
    }
  }

  Future<void> _confirmCancelFalseAlarm() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'ops';
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate800,
        title: Text(context.opsTr('Stop operation (false alarm)?'), style: TextStyle(color: Colors.white)),
        content: Text(context.opsTr('Archives as cancelled (false alarm). Removes the incident from the active list; responder closure XP may differ from a resolved stop.'), style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.opsTr('Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryDanger),
            child: Text(context.opsTr('Confirm false alarm')),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
    try {
      await IncidentService.archiveAndCloseIncident(
        incidentId: widget.incident.id,
        status: 'cancelled',
        closedByUid: uid,
      );
      widget.onAfterMutation();
      await _snack('Operation stopped (false alarm)', ok: true);
    } catch (e) {
      await _snack(e);
    }
  }

  Future<void> _showVictimCardDialog(SosIncident inc) async {
    final url =
        'https://${DefaultFirebaseOptions.webMain.projectId}.web.app/victim-card/${Uri.encodeComponent(inc.id)}';
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppColors.slate900,
          title: Text(context.opsTr('Victim medical card'), style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Incident ${inc.id}',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Type: ${inc.type}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  'Blood: ${inc.bloodType ?? "-"} · Allergies: ${inc.allergies ?? "-"}',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
                ),
                const SizedBox(height: 4),
                if ((inc.emergencyContactPhone ?? '').isNotEmpty ||
                    (inc.emergencyContactEmail ?? '').isNotEmpty) ...[
                  if ((inc.emergencyContactPhone ?? '').isNotEmpty)
                    Text(
                      'Emergency contact phone: ${inc.emergencyContactPhone}',
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                    ),
                  if ((inc.emergencyContactEmail ?? '').isNotEmpty)
                    Text(
                      'Emergency contact email: ${inc.emergencyContactEmail}',
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                    ),
                ],
                const SizedBox(height: 12),
                Center(
                  child: QrImageView(
                    data: url,
                    version: QrVersions.auto,
                    size: 160,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  url,
                  style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 10),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.opsTr('Close')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final inc = widget.incident;
    final fmt = DateFormat.MMMd().add_Hm();
    final volAt = inc.volunteerUpdatedAt;
    final locAt = inc.lastLocationAt;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                      _dispatchPriorityBanner(inc),
                      _preArrivalHandoffCard(inc),
                      _aiTriageCard(inc),
                      _aiHospitalRationaleCard(inc),
          SharedSituationBriefCard(
            incidentId: inc.id,
            accentColor: const Color(0xFF7C4DFF),
            compact: false,
            showRefreshButton: true,
          ),
          _sectionTitle('Voice channels (LiveKit)'),
          Text(
            'Opens Comms with this incident and joins the room — same as the Comms tab, not legacy PTT.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () {
                  GoRouter.of(context).go(
                    '/master-dashboard?focus=${Uri.encodeComponent(inc.id)}&comms=${Uri.encodeComponent('operation')}',
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.headset_mic_rounded, size: 18),
                    SizedBox(width: 6),
                    Text(context.opsTr('Operation channel')),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () {
                  GoRouter.of(context).go(
                    '/master-dashboard?focus=${Uri.encodeComponent(inc.id)}&comms=${Uri.encodeComponent('emergency')}',
                  );
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.campaign_rounded, size: 18),
                    SizedBox(width: 6),
                    Text(context.opsTr('Emergency channel')),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // High-level status snapshot at the top of the incident details column.
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.slate800,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.opsTr('Status overview'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 6),
                _statusLine('EMS', emsWorkflowPhaseShortLabel(inc.emsWorkflowPhase)),
                StreamBuilder<OpsIncidentHospitalAssignment?>(
                  stream: OpsIncidentHospitalAssignmentService.watchForIncident(inc.id),
                  builder: (context, asSnap) {
                    return _statusLine(
                      'Assigned hospital',
                      _assignedHospitalLabelFromAssignment(asSnap.data),
                    );
                  },
                ),
                _statusLine('Type of emergency', inc.type),
                _statusLine('Report Accepted', inc.emsAcceptedAt != null
                    ? DateFormat('MMM d, HH:mm').format(inc.emsAcceptedAt!.toLocal())
                    : 'Pending'),
                _statusLine('Victim conscious', _victimConsciousLabel(inc)),
                _statusLine('Location', inc.location.latitude.toStringAsFixed(5) + ', ' + inc.location.longitude.toStringAsFixed(5)),
                if (inc.bloodType != null && inc.bloodType!.isNotEmpty)
                  _statusLine('Blood Type', inc.bloodType!, isHighlighted: true),
                if (inc.allergies != null && inc.allergies!.isNotEmpty)
                  _statusLine('Allergies', inc.allergies!),
                if (inc.medicalConditions != null && inc.medicalConditions!.isNotEmpty)
                  _statusLine('Medical Conditions', inc.medicalConditions!),
                if ((inc.emsWorkflowPhase ?? '').trim() == 'on_scene' &&
                    inc.emsOnSceneAt != null)
                  _OnSceneHoldCountdownLine(onSceneAt: inc.emsOnSceneAt!),
                if ((inc.emsWorkflowPhase ?? '').trim() == 'returning')
                  _statusLine(
                    'Return distance',
                    _returnDistanceLabel(inc),
                  ),
                if (inc.emsHospitalArrivalAt != null)
                  _statusLine('Hospital Arrival', DateFormat('MMM d, HH:mm').format(inc.emsHospitalArrivalAt!.toLocal())),
              ],
            ),
          ),
          if (inc.isFleetEmergencyActive ||
              (inc.fleetEmergencyState ?? '').trim() == 'reassigned')
            _FleetEmergencyInspectorBlock(incident: inc),
          StreamBuilder<OpsIncidentHospitalAssignment?>(
            stream: OpsIncidentHospitalAssignmentService.watchForIncident(inc.id),
            builder: (context, asSnap) {
              final a = asSnap.data;
              final master = widget.showMasterHospitalControls;
              if (a == null) {
                if (!master) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.slate800,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.opsTr('Hospital & ambulance dispatch'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Text(context.opsTr('No hospital assignment document yet. Start or refresh the notify chain from the incident location.'), style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.35),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: _restartHospitalDispatchBusy ? null : _adminRestartHospitalDispatch,
                          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: _restartHospitalDispatchBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(context.opsTr('Restart hospital dispatch'), style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final bound = widget.boundHospitalDocId?.trim();
              final notified = (a.notifiedHospitalId ?? '').trim();
              final st = (a.dispatchStatus ?? '').trim();
              final canAct = bound != null &&
                  bound.isNotEmpty &&
                  notified == bound &&
                  st == 'pending_acceptance';
              final canMasterPending =
                  master && notified.isNotEmpty && st == 'pending_acceptance';
              final showMasterRestart = master &&
                  (st == 'exhausted' ||
                      st == 'no_candidates' ||
                      st == 'failed_to_assist' ||
                      st == 'pending_notify');
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.slate800,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.opsTr('Hospital & ambulance dispatch'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hospital workflow: ${a.dispatchStatus ?? "—"}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      Text(
                        'Notified: ${a.notifiedHospitalName ?? (notified.isNotEmpty ? notified : "—")} · index ${a.notifyIndex ?? 0}',
                        style: const TextStyle(color: Colors.white54, fontSize: 10, height: 1.3),
                      ),
                      if ((a.acceptedHospitalName ?? '').trim().isNotEmpty)
                        Text(
                          'Accepted hospital: ${a.acceptedHospitalName}',
                          style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 10),
                        ),
                      Text(
                        'Ambulance: ${a.ambulanceDispatchStatus ?? "—"}'
                        '${(a.assignedFleetCallSign ?? '').trim().isNotEmpty ? " · ${a.assignedFleetCallSign}" : ""}',
                        style: const TextStyle(color: Colors.white60, fontSize: 10),
                      ),
                      if (a.notifiedHospitalIds.isNotEmpty)
                        Text(
                          'Hospitals pinged: ${a.notifiedHospitalIds.join(", ")}',
                          style: const TextStyle(color: Colors.white38, fontSize: 9, height: 1.25),
                        ),
                      if (canAct) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: _hospitalDispatchBusy ? null : () => _acceptHospitalDispatch(bound),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(context.opsTr('Accept dispatch'), style: TextStyle(fontSize: 11)),
                            ),
                            OutlinedButton(
                              onPressed: _hospitalDispatchBusy ? null : () => _declineHospitalDispatch(bound),
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                              child: Text(context.opsTr('Decline'), style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                      if (canMasterPending) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: _hospitalDispatchBusy ? null : () => _acceptHospitalDispatch(notified),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(context.opsTr('Accept dispatch'), style: TextStyle(fontSize: 11)),
                            ),
                            OutlinedButton(
                              onPressed: _hospitalDispatchBusy ? null : () => _declineHospitalDispatch(notified),
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                              child: Text(context.opsTr('Notify next hospital'), style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                      if (showMasterRestart) ...[
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: (_restartHospitalDispatchBusy || _hospitalDispatchBusy)
                              ? null
                              : _adminRestartHospitalDispatch,
                          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: _restartHospitalDispatchBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(context.opsTr('Restart hospital dispatch'), style: TextStyle(fontSize: 11)),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // ── Gemini routing brief card ──────────────────────────
                      // Promoted from a 10px text blob to a proper titled card
                      // so the AI output actually reads as an AI product, not
                      // a debug log. Still compact, but legible on 1080p demos.
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF536DFE).withValues(alpha: 0.10),
                              const Color(0xFF536DFE).withValues(alpha: 0.02),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF536DFE).withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.auto_awesome,
                                    size: 14, color: Color(0xFF8FA1FF)),
                                const SizedBox(width: 6),
                                const Text(
                                  'Gemini routing brief',
                                  style: TextStyle(
                                    color: Color(0xFF8FA1FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: _geminiHospitalExplainLoading
                                      ? null
                                      : () => _loadGeminiHospitalExplain(a),
                                  icon: Icon(
                                    _geminiHospitalExplainText != null
                                        ? Icons.refresh_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 14,
                                    color: const Color(0xFF8FA1FF),
                                  ),
                                  label: Text(
                                    _geminiHospitalExplainText != null
                                        ? 'Refresh'
                                        : 'Generate',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF8FA1FF),
                                        fontWeight: FontWeight.w700),
                                  ),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    minimumSize: const Size(0, 26),
                                  ),
                                ),
                              ],
                            ),
                            if (_geminiHospitalExplainLoading)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF8FA1FF)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Thinking through the dispatch…',
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.55),
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (_geminiHospitalExplainText != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: SelectableText(
                                  _geminiHospitalExplainText!.trim(),
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.88),
                                    fontSize: 12.5,
                                    height: 1.42,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Tap generate for an AI explanation of why this '
                                  'hospital was routed and what ops should watch for.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.45),
                                    fontSize: 10.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (widget.boundHospitalDocId == null || widget.boundHospitalDocId!.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _closestFleetBlock('Ambulance', 'medical', (uid) async {
                await IncidentService.adminAssignAmbulanceDriver(incidentId: inc.id, driverUid: uid);
              }),
            ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _timelineExpanded = !_timelineExpanded),
            child: Row(
              children: [
                Icon(
                  _timelineExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white54,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  _timelineExpanded ? 'Hide incident timeline' : 'Show incident timeline',
                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (_timelineExpanded) ...[
            const SizedBox(height: 8),
            ..._incidentTimelineTiles(inc),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Text(
              'Lifecycle: ${inc.lifecyclePhaseLabel}'
              '${inc.firstAcknowledgedAt != null ? ' · First ack ${fmt.format(inc.firstAcknowledgedAt!.toLocal())}' : ''}',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
          const SizedBox(height: 8),
          _sectionTitle('Victim medical card'),
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.slate800,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GPS: ${inc.liveVictimPin.latitude.toStringAsFixed(5)}, ${inc.liveVictimPin.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                if (locAt != null)
                  Text(
                    'Last update: ${fmt.format(locAt.toLocal())}',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Blood: ${inc.bloodType ?? "—"} · Allergies: ${inc.allergies ?? "—"} · Conditions: ${inc.medicalConditions ?? "—"}',
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, height: 1.3),
                ),
                if ((inc.emergencyContactPhone ?? '').isNotEmpty ||
                    (inc.emergencyContactEmail ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((inc.emergencyContactPhone ?? '').isNotEmpty)
                          Text(
                            'Emergency contact phone: ${inc.emergencyContactPhone} (${inc.useEmergencyContactForSms ? "SMS on" : "SMS off"})',
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                          ),
                        if ((inc.emergencyContactEmail ?? '').isNotEmpty)
                          Text(
                            'Emergency contact email: ${inc.emergencyContactEmail}',
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                if (inc.smsRelayOrOrigin)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'SMS origin phone: ${inc.senderPhone ?? "—"}',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 10),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  _triageOneLiner(inc.triage),
                  style: const TextStyle(color: Colors.white60, fontSize: 11, height: 1.35),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showVictimCardDialog(inc),
                        icon: const Icon(Icons.qr_code, size: 16),
                        label: Text(context.opsTr('QR / share card'), style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          try {
                            await IncidentReportService.generateAndStoreReport(inc);
                            await _snack('Incident report generated', ok: true);
                          } catch (e) {
                            await _snack(e);
                          }
                        },
                        icon: const Icon(Icons.description, size: 16),
                        label: Text(context.opsTr('Generate report'), style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Volunteer roster'),
          Text(
            'Accepted ${inc.acceptedVolunteerIds.length} · On-scene ${inc.onSceneVolunteerIds.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (volAt != null)
            Text('Last volunteer GPS: ${fmt.format(volAt.toLocal())}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ...inc.acceptedVolunteerIds.take(5).map((vid) {
            final name = inc.responderNames[vid];
            final label = name != null && name.isNotEmpty ? name : 'Responder';
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.volunteer_activism, size: 16, color: Colors.tealAccent.withValues(alpha: 0.85)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (inc.acceptedVolunteerIds.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '+ ${inc.acceptedVolunteerIds.length - 5} more responder${inc.acceptedVolunteerIds.length - 5 == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
          const SizedBox(height: 14),
          _sectionTitle('Live feed → victim & volunteer apps'),
          SizedBox(
            height: 140,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('sos_incidents')
                  .doc(inc.id)
                  .collection('victim_activity')
                  .orderBy('createdAt', descending: true)
                  .limit(40)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Text('Feed error: ${snap.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 11));
                }
                if (!snap.hasData) {
                  return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Center(
                    child: Text(context.opsTr('No activity yet.'), style: TextStyle(color: Colors.white38, fontSize: 11)),
                  );
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (_, i) {
                    final d = docs[i].data();
                    final text = (d['text'] as String?) ?? '';
                    DateTime? t;
                    final c = d['createdAt'];
                    if (c is Timestamp) t = c.toDate();
                    final ts = t == null ? '' : fmt.format(t.toLocal());
                    return Text('$ts · $text', style: const TextStyle(color: Colors.white70, fontSize: 10, height: 1.3));
                  },
                );
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _broadcastCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: _denseDeco('Broadcast line to feed'),
                  onSubmitted: (_) => _postBroadcast(),
                ),
              ),
              const SizedBox(width: 6),
              FilledButton(onPressed: _postBroadcast, child: Text(context.opsTr('Send'))),
            ],
          ),
          const SizedBox(height: 14),
          _sectionTitle('Volunteer scene report (read-only)'),
          SelectableText(
            _sceneReportPreview(inc.volunteerSceneReport),
            style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace', height: 1.25),
          ),
          const SizedBox(height: 14),
          _sectionTitle('Internal note'),
          TextField(
            controller: widget.noteController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: _denseDeco('Dispatch note'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: widget.onSaveNote, child: Text(context.opsTr('Save note'))),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _confirmArchive,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryDanger),
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: Text(
              widget.showMasterHospitalControls
                  ? 'Stop operation — resolved'
                  : 'Archive & close (resolved)',
            ),
          ),
          if (widget.showMasterHospitalControls) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _confirmCancelFalseAlarm,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orangeAccent),
              icon: const Icon(Icons.warning_amber_rounded, size: 18),
              label: Text(context.opsTr('Stop operation — false alarm')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusLine(String label, String value, {bool isHighlighted = false}) {
    final textColor = isHighlighted ? Colors.amber : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(color: isHighlighted ? Colors.amber : Colors.white54, fontSize: 11, fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(color: textColor, fontSize: 11, fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _assignedHospitalLabelFromAssignment(OpsIncidentHospitalAssignment? a) {
    if (a == null) return 'Not assigned';
    final st = (a.dispatchStatus ?? '').trim();
    if (st == 'accepted') {
      final id = (a.acceptedHospitalId ?? '').trim();
      final name = (a.acceptedHospitalName ?? '').trim();
      final code = id.isNotEmpty ? id : '—';
      if (name.isNotEmpty) return '$name · code $code';
      return 'code $code';
    }
    if (st == 'pending_acceptance') {
      final n = (a.notifiedHospitalName ?? '').trim();
      if (n.isNotEmpty) return 'Awaiting acceptance: $n';
      final id = (a.notifiedHospitalId ?? '').trim();
      if (id.isNotEmpty) return 'Awaiting acceptance: $id';
      return 'Hospital notifying…';
    }
    if (st.isNotEmpty) {
      return st.replaceAll('_', ' ');
    }
    return 'See Hospital dispatch section';
  }

  String _victimConsciousLabel(SosIncident inc) {
    final triageMap = inc.triage ?? const <String, dynamic>{};
    final triage = triageMap.values.join(' ').toLowerCase();
    if (triage.contains('unconscious') || triage.contains('unresponsive')) {
      return 'No';
    }
    if (triage.contains('conscious')) return 'Yes';
    return 'Unknown';
  }

  String _returnDistanceLabel(SosIncident inc) {
    final driver = inc.craneLiveLocation;
    final hospital = inc.plannedOriginLatLng;
    if (driver == null || hospital == null) return '—';
    final meters = Geolocator.distanceBetween(
      driver.latitude,
      driver.longitude,
      hospital.latitude,
      hospital.longitude,
    );
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '${meters.round()} m';
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: const TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.4),
        ),
      );

  InputDecoration _denseDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
        filled: true,
        fillColor: Colors.black26,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      );

  Widget _miniField(String label, TextEditingController c, {int maxLines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: _denseDeco(label),
        ),
      );
}

/// Ticking countdown for the driver's 1-minute "on-scene hold" before the
/// rescue-complete slider unlocks. Displayed inside the Status overview card.
class _OnSceneHoldCountdownLine extends StatefulWidget {
  const _OnSceneHoldCountdownLine({required this.onSceneAt});
  final DateTime onSceneAt;

  @override
  State<_OnSceneHoldCountdownLine> createState() =>
      _OnSceneHoldCountdownLineState();
}

class _OnSceneHoldCountdownLineState extends State<_OnSceneHoldCountdownLine> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed =
        DateTime.now().difference(widget.onSceneAt).inSeconds.clamp(0, 60);
    final remaining = 60 - elapsed;
    final value =
        remaining <= 0 ? 'Ready to return' : '${remaining}s until return unlock';
    final color = remaining <= 0 ? Colors.greenAccent : const Color(0xFFFFB74D);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Expanded(
            flex: 2,
            child: Text(
              'On-scene hold',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dedicated ops panel that surfaces an in-run driver SOS on the master
/// command centre inspector. Offers the two supported ops actions:
/// opening the operator channel (ack's the emergency) and allotting a
/// fresh ambulance (releases the current unit + re-dispatches).
class _FleetEmergencyInspectorBlock extends StatefulWidget {
  const _FleetEmergencyInspectorBlock({required this.incident});

  final SosIncident incident;

  @override
  State<_FleetEmergencyInspectorBlock> createState() =>
      _FleetEmergencyInspectorBlockState();
}

class _FleetEmergencyInspectorBlockState
    extends State<_FleetEmergencyInspectorBlock> {
  bool _busy = false;

  Future<void> _openOperatorChannel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await IncidentService.acknowledgeFleetEmergency(
        incidentId: widget.incident.id,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    GoRouter.of(context).go(
      '/master-dashboard?focus=${Uri.encodeComponent(widget.incident.id)}'
      '&comms=${Uri.encodeComponent('operation')}',
    );
  }

  Future<void> _allotNewFleet() async {
    if (_busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF11181F),
        title: const Text(
          'Allot new fleet?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'The current ambulance will be released and a fresh unit will be '
          'dispatched to this incident.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Allot new fleet'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    String? newFleet;
    try {
      newFleet = await IncidentService.reassignFleetForEmergency(
        incidentId: widget.incident.id,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newFleet == null
              ? 'No available ambulance found — manual dispatch required.'
              : 'Dispatched new ambulance to the incident.',
        ),
      ),
    );
  }

  Future<void> _resolve() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await IncidentService.resolveFleetEmergency(
        incidentId: widget.incident.id,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final inc = widget.incident;
    final state = (inc.fleetEmergencyState ?? '').trim();
    final active = inc.isFleetEmergencyActive;
    final reassigned = state == 'reassigned';
    final cs = (inc.fleetEmergencyRaisedByCallSign ?? '').trim();
    final note = (inc.fleetEmergencyNote ?? '').trim();
    final raisedAt = inc.fleetEmergencyRaisedAt;

    final headline = reassigned
        ? 'Fleet reassigned after SOS'
        : (state == 'acknowledged'
            ? 'Driver SOS · ops on the channel'
            : 'Driver SOS · needs support');

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: reassigned
            ? const Color(0xFF10212A)
            : Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: reassigned
              ? Colors.cyanAccent.withValues(alpha: 0.4)
              : Colors.redAccent.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                reassigned
                    ? Icons.check_circle_rounded
                    : Icons.priority_high_rounded,
                color: reassigned ? Colors.cyanAccent : Colors.redAccent,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    color: reassigned ? Colors.cyanAccent : Colors.redAccent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (raisedAt != null)
                Text(
                  DateFormat.Hm().format(raisedAt),
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 10),
                ),
            ],
          ),
          if (cs.isNotEmpty || note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (cs.isNotEmpty) 'Unit: $cs',
                if (note.isNotEmpty) note,
              ].join(' · '),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
          if (active) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _openOperatorChannel,
                  icon: const Icon(Icons.headset_mic_rounded, size: 16),
                  label: const Text('Open operator channel'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _allotNewFleet,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text('Allot new fleet'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _resolve,
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.white60),
                  label: const Text(
                    'Clear banner',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
