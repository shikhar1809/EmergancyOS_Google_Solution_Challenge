import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/india_ops_zones.dart';
import '../../../../services/incident_service.dart';
import 'command_center_shared_widgets.dart';

DateTime _archiveDocSortTime(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) {
    final p = DateTime.tryParse(v);
    if (p != null) return p;
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

String _archiveClosureLabelText(Map<String, dynamic> data) {
  final label = (data['closureLabel'] as String?)?.trim();
  if (label != null && label.isNotEmpty) {
    if (label.toLowerCase() == 'unattended') return 'Unattended';
    return label;
  }
  return (data['status'] as String?)?.trim() ?? 'archived';
}

Color commandPriorityChipColor(String label) {
  return switch (label) {
    'P1' => Colors.redAccent,
    'P2' => Colors.orangeAccent,
    'P3' => Colors.amberAccent,
    _ => Colors.lightBlueAccent,
  };
}

/// Active SOS rows for command sidebars (master + medical).
class CommandCenterActiveIncidentList extends StatelessWidget {
  const CommandCenterActiveIncidentList({
    super.key,
    required this.filtered,
    required this.selectedId,
    required this.onIncidentTap,
    required this.accent,
    this.priorityLabelFor,
    this.hospitalLocation,
    this.boundHospitalDocId,
    this.zone,
  });

  final List<SosIncident> filtered;
  final String? selectedId;
  final void Function(SosIncident) onIncidentTap;
  final Color accent;
  final String Function(SosIncident)? priorityLabelFor;
  final LatLng? hospitalLocation;
  /// When set, list uses hospital-facing status labels and listens for assignment ambulance status.
  final String? boundHospitalDocId;
  final IndiaOpsZone? zone;

  /// Beyond this straight-line distance, the victim pin is likely wrong — don’t show fake precision.
  static const double _maxTrustDistanceM = 2_000_000;

  static String? distanceFromHospitalLine(SosIncident e, LatLng? hospital) {
    if (hospital == null) return null;
    final pin = e.liveVictimPin;
    final m = Geolocator.distanceBetween(
      hospital.latitude,
      hospital.longitude,
      pin.latitude,
      pin.longitude,
    );
    if (m > _maxTrustDistanceM) {
      return 'Location unreliable (check victim GPS)';
    }
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km from hospital';
    return '${m.round()} m from hospital';
  }

  @override
  Widget build(BuildContext context) {
    final hid = boundHospitalDocId?.trim();
    if (hid != null && hid.isNotEmpty) {
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('ops_incident_hospital_assignments')
            .where('acceptedHospitalId', isEqualTo: hid)
            .where('dispatchStatus', whereIn: ['accepted', 'failed_to_assist'])
            .snapshots(),
        builder: (context, snap) {
          final assignmentAmb = <String, String>{};
          final chainSt = <String, String>{};
          if (snap.hasData) {
            for (final doc in snap.data!.docs) {
              final d = doc.data();
              final st = (d['dispatchStatus'] as String?)?.trim();
              if (st != null && st.isNotEmpty) {
                chainSt[doc.id] = st;
              }
              final s = d['ambulanceDispatchStatus'] as String?;
              if (s != null && s.isNotEmpty) {
                assignmentAmb[doc.id] = s;
              }
            }
          }
          return _buildColumn(
            assignmentAmbulanceByIncident: assignmentAmb,
            assignmentChainDispatchStatusByIncident: chainSt,
            useHospitalStatus: true,
          );
        },
      );
    }
    return _buildColumn(
      assignmentAmbulanceByIncident: const {},
      useHospitalStatus: false,
    );
  }

  Widget _buildColumn({
    required Map<String, String> assignmentAmbulanceByIncident,
    Map<String, String> assignmentChainDispatchStatusByIncident = const {},
    required bool useHospitalStatus,
  }) {
    final fmt = DateFormat.MMMd().add_Hm();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Text(
            '${filtered.length} active consignments${zone != null ? " · ${zone!.label}" : ""}',
            style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 11),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No active SOS in this command zone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final e = filtered[i];
                    final on = e.id == selectedId;
                    final hospDist = distanceFromHospitalLine(e, hospitalLocation);
                    final pl = priorityLabelFor;
                    final ambAssign = assignmentAmbulanceByIncident[e.id];
                    final chainAssign = assignmentChainDispatchStatusByIncident[e.id];
                    return Material(
                      color: on ? accent.withValues(alpha: 0.12) : Colors.transparent,
                      child: InkWell(
                        onTap: () => onIncidentTap(e),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (pl != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(
                                        color: commandPriorityChipColor(pl(e)).withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: commandPriorityChipColor(pl(e)).withValues(alpha: 0.5),
                                        ),
                                      ),
                                      child: Text(
                                        pl(e),
                                        style: TextStyle(
                                          color: commandPriorityChipColor(pl(e)),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ],
                                  Expanded(
                                    child: Text(
                                      e.type,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  if (useHospitalStatus)
                                    HospitalConsignmentStatusPill(
                                      incident: e,
                                      ambulanceDispatchStatus: ambAssign,
                                      hospitalAssignmentDispatchStatus: chainAssign,
                                    )
                                  else
                                    StatusPill(status: e.status, dispatchedAccent: accent),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                e.userDisplayName,
                                style: const TextStyle(color: Colors.white60, fontSize: 12),
                              ),
                              Text(
                                fmt.format(e.timestamp.toLocal()),
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                              if (hospDist != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  hospDist,
                                  style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              Row(
                                children: [
                                  if (e.acceptedVolunteerIds.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Text(
                                        'V${e.acceptedVolunteerIds.length}',
                                        style: const TextStyle(
                                          color: Colors.lightGreenAccent,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  if (e.onSceneVolunteerIds.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Text(
                                        'O${e.onSceneVolunteerIds.length}',
                                        style: const TextStyle(
                                          color: Colors.tealAccent,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  if (e.emsWorkflowPhase != null && e.emsWorkflowPhase!.isNotEmpty)
                                    Text(
                                      'EMS ${emsWorkflowPhaseShortLabel(e.emsWorkflowPhase)}',
                                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 9),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Recent archived SOS rows (read-only selection → map focus).
class CommandCenterArchiveIncidentList extends StatelessWidget {
  const CommandCenterArchiveIncidentList({
    super.key,
    required this.selectedId,
    required this.onArchiveTap,
    required this.accent,
    this.zone,
  });

  final String? selectedId;
  final void Function(SosIncident incident, String closureStatus) onArchiveTap;
  final Color accent;
  final IndiaOpsZone? zone;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.MMMd().add_Hm();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sos_incidents_archive').limit(100).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('${snap.error}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          );
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: accent));
        }
        final docs = snap.data!.docs.toList();
        docs.sort((a, b) {
          final da = _archiveDocSortTime(a.data()['timestamp']);
          final db = _archiveDocSortTime(b.data()['timestamp']);
          return db.compareTo(da);
        });
        var rows = docs.map((d) {
          final inc = SosIncident.fromFirestore(d);
          final closure = _archiveClosureLabelText(d.data());
          return (inc, closure);
        }).toList();
        if (zone != null) {
          rows = rows.where((t) => zone!.containsLatLng(t.$1.liveVictimPin)).toList();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                '${rows.length} archived in zone${zone != null ? " · ${zone!.label}" : ""}',
                style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 11),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No archived incidents in this view yet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (_, i) {
                        final e = rows[i].$1;
                        final closure = rows[i].$2;
                        final on = e.id == selectedId;
                        return Material(
                          color: on ? accent.withValues(alpha: 0.1) : Colors.transparent,
                          child: InkWell(
                            onTap: () => onArchiveTap(e, closure),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.archive_outlined, size: 16, color: accent.withValues(alpha: 0.9)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          e.type,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white12,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          closure,
                                          style: TextStyle(
                                            color: accent.withValues(alpha: 0.95),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    e.userDisplayName,
                                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                                  ),
                                  Text(
                                    '${fmt.format(e.timestamp.toLocal())} · ${e.id}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
