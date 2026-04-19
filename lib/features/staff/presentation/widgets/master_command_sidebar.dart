import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/india_ops_zones.dart';
import '../../../../core/l10n/dashboard_l10n.dart';
import '../../../../core/utils/fleet_unit_availability.dart';
import '../../../../services/ops_hospital_service.dart';
import '../../../../services/ops_zone_resource_catalog.dart';
import '../../../../services/incident_service.dart';
import '../../../../services/volunteer_presence_service.dart'
    show ActiveVolunteerNearby;
import '../../domain/admin_panel_access.dart';
import 'command_center_incident_lists.dart';

enum _LiveOpsCategory { consignments, fleet, volunteers, hospitals }

/// Master console — **Live Ops** tab map column: SOS lists, live fleet, duty volunteers, hospital capacity.
class MasterLiveOpsSidebar extends StatefulWidget {
  const MasterLiveOpsSidebar({
    super.key,
    required this.access,
    required this.accent,
    required this.zone,
    required this.dutyVols,
    required this.fleetDocs,
    required this.onPlaceTap,
    required this.filteredIncidents,
    required this.selectedId,
    required this.onIncidentTap,
    required this.onArchiveIncidentTap,
    this.priorityLabelFor,
    this.onFleetRowSelected,
    this.onHospitalRowSelected,
    this.onVolunteerRowSelected,
  });

  final AdminPanelAccess access;
  final Color accent;
  final IndiaOpsZone? zone;
  final List<ActiveVolunteerNearby> dutyVols;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> fleetDocs;
  final void Function(LatLng) onPlaceTap;
  final List<SosIncident> filteredIncidents;
  final String? selectedId;
  final void Function(SosIncident) onIncidentTap;
  final void Function(SosIncident incident, String closureStatus)
  onArchiveIncidentTap;
  final String Function(SosIncident)? priorityLabelFor;

  /// Optional: map focus + detail panel (e.g. master Live Ops).
  final void Function(String fleetDocId, LatLng pos)? onFleetRowSelected;
  final void Function(OpsHospitalRow row)? onHospitalRowSelected;
  final void Function(ActiveVolunteerNearby v)? onVolunteerRowSelected;

  @override
  State<MasterLiveOpsSidebar> createState() => _MasterLiveOpsSidebarState();
}

class _MasterLiveOpsSidebarState extends State<MasterLiveOpsSidebar> {
  _LiveOpsCategory _category = _LiveOpsCategory.consignments;

  @override
  Widget build(BuildContext context) {
    final z = widget.zone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _catChip(
                      _LiveOpsCategory.consignments,
                      context.opsTr('SOS'),
                      Icons.emergency_outlined,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _catChip(
                      _LiveOpsCategory.fleet,
                      context.opsTr('Fleet'),
                      Icons.local_shipping_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _catChip(
                      _LiveOpsCategory.volunteers,
                      context.opsTr('Volunteers'),
                      Icons.groups_outlined,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _catChip(
                      _LiveOpsCategory.hospitals,
                      context.opsTr('Hospitals'),
                      Icons.local_hospital_outlined,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _bodyFor(z)),
      ],
    );
  }

  Widget _catChip(_LiveOpsCategory c, String label, IconData icon) {
    final on = _category == c;
    return Material(
      color: on
          ? widget.accent.withValues(alpha: 0.2)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => setState(() => _category = c),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: on ? widget.accent : Colors.white54),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: on ? widget.accent : Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bodyFor(IndiaOpsZone? zone) {
    return switch (_category) {
      _LiveOpsCategory.consignments => DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.white.withValues(alpha: 0.04),
              child: TabBar(
                labelColor: widget.accent,
                unselectedLabelColor: Colors.white38,
                indicatorColor: widget.accent,
                indicatorWeight: 2,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
                tabs: const [
                  Tab(text: 'Active'),
                  Tab(text: 'Archive'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  CommandCenterActiveIncidentList(
                    filtered: widget.filteredIncidents,
                    selectedId: widget.selectedId,
                    onIncidentTap: widget.onIncidentTap,
                    accent: widget.accent,
                    priorityLabelFor: widget.priorityLabelFor,
                    zone: zone,
                  ),
                  CommandCenterArchiveIncidentList(
                    selectedId: widget.selectedId,
                    onArchiveTap: widget.onArchiveIncidentTap,
                    accent: widget.accent,
                    zone: zone,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _LiveOpsCategory.fleet => _liveOpsFleet(zone),
      _LiveOpsCategory.volunteers => _liveOpsVolunteers(),
      _LiveOpsCategory.hospitals => _liveOpsHospitals(),
    };
  }

  Widget _liveOpsFleet(IndiaOpsZone? zone) {
    final docs = widget.fleetDocs;
    final inZone = zone == null
        ? docs
        : docs.where((d) {
            final lat = (d.data()['lat'] as num?)?.toDouble();
            final lng = (d.data()['lng'] as num?)?.toDouble();
            if (lat == null || lng == null) return true;
            return zone.containsLatLng(LatLng(lat, lng));
          }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Text(
            '${inZone.length} units${zone != null ? ' · ${zone.label}' : ''}',
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: inZone.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No fleet documents in Firestore for this view.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: inZone.length,
                  itemBuilder: (_, i) {
                    final d = inZone[i];
                    final data = d.data();
                    final cs =
                        (data['fleetCallSign'] as String?)?.trim() ?? d.id;
                    final avail = fleetUnitIsStaffedAvailable(data, d.id);
                    final aid =
                        (data['assignedIncidentId'] as String?)?.trim() ?? '';
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          final lat = (data['lat'] as num?)?.toDouble();
                          final lng = (data['lng'] as num?)?.toDouble();
                          if (lat == null || lng == null) return;
                          final pos = LatLng(lat, lng);
                          final sel = widget.onFleetRowSelected;
                          if (sel != null) {
                            sel(d.id, pos);
                          } else {
                            widget.onPlaceTap(pos);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cs,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                avail
                                    ? (aid.isNotEmpty
                                          ? 'Responding · $aid'
                                          : 'Standby / available')
                                    : (isFleetUnitPlaceholderDoc(d.id)
                                          ? 'Registered · no operator signed in'
                                          : 'Off duty / unavailable'),
                                style: TextStyle(
                                  color: avail
                                      ? Colors.lightGreenAccent
                                      : Colors.white38,
                                  fontSize: 10,
                                ),
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

  Widget _liveOpsVolunteers() {
    final vols = widget.dutyVols;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Text(
            '${vols.length} on duty · fresh GPS in zone',
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: vols.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No volunteers with a recent duty ping in this zone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: vols.length,
                  itemBuilder: (_, i) {
                    final v = vols[i];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          final sel = widget.onVolunteerRowSelected;
                          if (sel != null) {
                            sel(v);
                          } else {
                            widget.onPlaceTap(LatLng(v.lat, v.lng));
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                OpsZoneResourceCatalog.dutyNarrative(v),
                                style: const TextStyle(
                                  color: Colors.tealAccent,
                                  fontSize: 10,
                                ),
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

  Widget _liveOpsHospitals() {
    final df = DateFormat('MMM d HH:mm');
    return StreamBuilder<List<OpsHospitalRow>>(
      stream: OpsHospitalService.watchHospitals(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              '${snap.error}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          );
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: widget.accent));
        }
        final rows = snap.data!;
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No hospitals in ops_hospitals yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          );
        }
        final avail = rows.fold<int>(0, (a, r) => a + r.bedsAvailable);
        final cap = rows.fold<int>(0, (a, r) => a + r.bedsTotal);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: Text(
                'Live grid · $avail avail / $cap capacity',
                style: const TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final note = (r.traumaBedsNote ?? '').trim();
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final h = widget.onHospitalRowSelected;
                        if (h != null) {
                          h(r);
                        } else {
                          final lat = r.lat;
                          final lng = r.lng;
                          if (lat != null && lng != null) {
                            widget.onPlaceTap(LatLng(lat, lng));
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '${r.region} · ${r.bedsAvailable} / ${r.bedsTotal} beds · ${df.format(r.updatedAt.toLocal())}',
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 10,
                              ),
                            ),
                            if (note.isNotEmpty)
                              Text(
                                note,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                  height: 1.25,
                                ),
                              ),
                            const Divider(height: 16, color: Colors.white12),
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
