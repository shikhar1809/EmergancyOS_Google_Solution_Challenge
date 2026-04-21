import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/maps/eos_hybrid_map.dart';
import '../../../core/maps/ops_map_controller.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/google_maps_illustrative_light_style.dart';
import '../../../core/constants/india_ops_zones.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/fleet_map_icons.dart';
import '../../../core/utils/fleet_unit_availability.dart';
import '../../../core/utils/ops_fleet_docs_dedupe.dart';
import '../../../core/utils/osrm_route_util.dart';
import '../../../services/demo_fleet_simulation.dart';
import '../../../services/fleet_assignment_service.dart';
import '../../../services/fleet_gate_credentials_service.dart';
import '../../../services/fleet_unit_service.dart';
import '../../../services/incident_service.dart';
import '../../../services/ops_hospital_service.dart';
import '../domain/admin_panel_access.dart';
import '../domain/command_center_accent.dart';
import 'widgets/fleet_credentials_dialog.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

class AdminFleetManagementScreen extends StatefulWidget {
  const AdminFleetManagementScreen({
    super.key,
    required this.access,
  });

  final AdminPanelAccess access;

  @override
  State<AdminFleetManagementScreen> createState() => _AdminFleetManagementScreenState();
}

class _AdminFleetManagementScreenState extends State<AdminFleetManagementScreen> {
  @override
  void initState() {
    super.initState();
    // Ensure fleet map icons are loaded for the track sheet.
    FleetMapIcons.preload();
  }

  Color get _accent => CommandCenterAccent.forRole(widget.access.role).primary;

  // ── Track sheet ─────────────────────────────────────────────────────────────

  void _showTrackSheet(BuildContext context, Map<String, dynamic> data, String docId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.slate900,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _FleetTrackingSheet(data: data, docId: docId),
    );
  }

  Future<void> _showCreateFleetSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.slate900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _CreateFleetSheet(),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      primary: false,
      backgroundColor: AppColors.slate900,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateFleetSheet(context),
        backgroundColor: _accent,
        icon: const Icon(Icons.add),
        label: Text(context.opsTr('New fleet')),
      ),
      appBar: AppBar(
        backgroundColor: AppColors.slate800,
        title: Row(
          children: [
            Icon(Icons.directions_car_filled, color: _accent),
            const SizedBox(width: 12),
            Text(context.opsTr('Fleet Management'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.white12, height: 1),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FleetUnitService.watchFleetUnits(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: _accent));
          }

          final docs = snapshot.data!.docs;
          final visibleDocs = dedupeFleetDocsByCallSign(
            docs
                .where(
                  (doc) => widget.access.isFleetDocVisible(doc.data(), doc.id),
                )
                .toList(),
          );

          if (visibleDocs.isEmpty) {
            return Center(
              child: Text(context.opsTr('No fleet units available for your role.'), style: TextStyle(color: Colors.white54, fontSize: 16)),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.slate800.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.white54, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${visibleDocs.length} units (one card per call sign). '
                          'Track opens the live map. Show credentials opens the gate password; Get/Reset creates or rotates ops_fleet_accounts.',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: visibleDocs
                      .map((doc) => _buildFleetCard(context, doc.data(), doc.id))
                      .toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFleetCard(BuildContext context, Map<String, dynamic> data, String docId) {
    final callSign = (data['fleetCallSign'] as String?)?.trim() ?? 'Unknown';
    final type = (data['vehicleType'] as String?)?.trim().toLowerCase() ?? 'unknown';
    final staffed = fleetUnitIsStaffedAvailable(data, docId);
    final placeholder = isFleetUnitPlaceholderDoc(docId);
    final assignedIncident = (data['assignedIncidentId'] as String?)?.trim();
    final onRun = assignedIncident != null && assignedIncident.isNotEmpty;

    final Color typeColor = switch (type) {
      'medical' || 'ambulance' => Colors.redAccent,
      _ => Colors.grey,
    };
    final IconData typeIcon = switch (type) {
      'medical' || 'ambulance' => Icons.medical_services,
      _ => Icons.directions_car,
    };

    final String badgeLabel;
    final Color badgeBorder;
    final Color badgeBg;
    final Color badgeFg;
    if (onRun) {
      badgeLabel = 'ASSIGNED';
      badgeBorder = Colors.orange;
      badgeBg = Colors.orange.withValues(alpha: 0.2);
      badgeFg = Colors.orangeAccent;
    } else if (staffed) {
      badgeLabel = 'AVAILABLE';
      badgeBorder = Colors.green;
      badgeBg = Colors.green.withValues(alpha: 0.2);
      badgeFg = Colors.greenAccent;
    } else if (placeholder) {
      badgeLabel = 'NO OPERATOR';
      badgeBorder = Colors.white38;
      badgeBg = Colors.white10;
      badgeFg = Colors.white54;
    } else {
      badgeLabel = 'OFF DUTY';
      badgeBorder = Colors.orange;
      badgeBg = Colors.orange.withValues(alpha: 0.2);
      badgeFg = Colors.orangeAccent;
    }

    final highlightStandby = staffed && !onRun;

    return Container(
      width: 380,
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlightStandby ? Colors.white12 : typeColor.withValues(alpha: 0.3)),
        boxShadow: !highlightStandby
            ? [BoxShadow(color: typeColor.withValues(alpha: 0.1), blurRadius: 10, spreadRadius: 2)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: const Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Icon(typeIcon, color: typeColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(callSign,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      color: badgeFg,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.account_tree_outlined, 'Type', type.toUpperCase()),
                const SizedBox(height: 6),
                _infoRow(Icons.badge_outlined, 'Fleet ID', callSign),
                if (assignedIncident != null && assignedIncident.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _infoRow(Icons.crisis_alert, 'Incident', assignedIncident, highlight: true),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.my_location_outlined,
                    label: 'Track',
                    color: Colors.green,
                    onTap: () => _showTrackSheet(context, data, docId),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => FleetCredentialsDialog(
                          fleetCallSign: callSign,
                          vehicleType: type,
                        ),
                      );
                    },
                    icon: Icon(Icons.visibility_outlined, color: _accent, size: 16),
                    label: Text(
                      'Show credentials',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        color: _accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FutureBuilder<bool>(
                    key: ValueKey<String>('fleet-mgmt-gate-$callSign'),
                    future: FleetGateCredentialsService.gateAccountExists(callSign),
                    builder: (context, snap) {
                      final hasGate = snap.data ?? false;
                      final label =
                          hasGate ? 'Reset credentials' : 'Get credentials';
                      return Material(
                        color: _accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: snap.connectionState == ConnectionState.waiting
                              ? null
                              : () {
                                  showDialog<void>(
                                    context: context,
                                    builder: (ctx) => FleetCredentialsDialog(
                                      fleetCallSign: callSign,
                                      vehicleType: type,
                                    ),
                                  );
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_note_rounded,
                                    color: _accent, size: 18),
                                const SizedBox(height: 4),
                                Text(
                                  snap.connectionState ==
                                          ConnectionState.waiting
                                      ? '…'
                                      : label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: TextStyle(
                                    color: _accent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
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
            ),
          ),
          if (!placeholder && staffed && !onRun && (type == 'medical' || type == 'ambulance')) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    side: const BorderSide(color: Colors.cyanAccent),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => _showAssignToIncidentDialog(
                    context,
                    operatorUid: docId,
                  ),
                  icon: const Icon(Icons.crisis_alert, size: 18),
                  label: Text(context.opsTr('Assign to accepted incident'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showAssignToIncidentDialog(
    BuildContext context, {
    required String operatorUid,
  }) async {
    final hid = widget.access.boundHospitalDocId?.trim();
    try {
      late final QuerySnapshot<Map<String, dynamic>> snap;
      if (hid != null && hid.isNotEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('ops_incident_hospital_assignments')
            .where('acceptedHospitalId', isEqualTo: hid)
            .where('dispatchStatus', isEqualTo: 'accepted')
            .limit(40)
            .get();
      } else {
        snap = await FirebaseFirestore.instance
            .collection('ops_incident_hospital_assignments')
            .where('dispatchStatus', isEqualTo: 'accepted')
            .limit(40)
            .get();
      }
      if (!context.mounted) return;
      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.opsTr('No accepted hospital consignments to assign.')),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.slate800,
          title: Text(context.opsTr('Assign unit to incident'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 420,
            height: 360,
            child: ListView(
              children: snap.docs.map((d) {
                final incId = d.id;
                final hosp =
                    (d.data()['acceptedHospitalName'] as String?)?.trim() ?? '';
                return ListTile(
                  textColor: Colors.white,
                  iconColor: _accent,
                  leading: const Icon(Icons.local_hospital_outlined),
                  title: Text(
                    incId.length > 28 ? '${incId.substring(0, 26)}…' : incId,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  subtitle: hosp.isNotEmpty
                      ? Text(hosp, style: const TextStyle(color: Colors.white54))
                      : null,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      final incSnap = await FirebaseFirestore.instance
                          .collection('sos_incidents')
                          .doc(incId)
                          .get();
                      final st =
                          incSnap.data()?['status'] as String? ?? '';
                      if (!['pending', 'dispatched', 'blocked'].contains(st)) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Incident is no longer open (status: $st).'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                        return;
                      }
                      await IncidentService.adminAssignAmbulanceDriver(
                        incidentId: incId,
                        driverUid: operatorUid,
                      );
                      await FleetUnitService.markAssignedToIncident(
                        operatorUid: operatorUid,
                        incidentId: incId,
                      );
                      try {
                        final unitSnap = await FirebaseFirestore.instance
                            .collection('ops_fleet_units')
                            .doc(operatorUid)
                            .get();
                        final ud = unitSnap.data();
                        final cs = (ud?['fleetCallSign'] as String?)?.trim() ?? '';
                        var vt = (ud?['vehicleType'] as String?)?.trim().toLowerCase() ?? 'medical';
                        if (vt == 'ambulance') vt = 'medical';
                        if (cs.isNotEmpty) {
                          await FleetAssignmentService.sendAssignment(
                            fleetId: cs,
                            incidentId: incId,
                            vehicleType: vt,
                            callSign: cs,
                          );
                        }
                      } catch (e) {
                        debugPrint('[FleetManagement] sendAssignment after panel assign: $e');
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Unit assigned to $incId'),
                            backgroundColor: Colors.green.shade800,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Assign failed: $e'),
                            backgroundColor: Colors.red.shade800,
                          ),
                        );
                      }
                    }
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.opsTr('Close')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load consignments: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Widget _infoRow(IconData icon, String label, String value, {bool highlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        SizedBox(
          width: 70,
          child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: highlight ? Colors.orangeAccent : Colors.white70,
              fontSize: 13,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Small action button used inside each fleet card ───────────────────────────

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Fleet live tracking sheet ─────────────────────────────────────────────────

class _FleetTrackingSheet extends StatefulWidget {
  const _FleetTrackingSheet({required this.data, required this.docId});

  final Map<String, dynamic> data;
  final String docId;

  @override
  State<_FleetTrackingSheet> createState() => _FleetTrackingSheetState();
}

class _FleetTrackingSheetState extends State<_FleetTrackingSheet> {
  Timer? _ticker;
  DemoFleetPose? _pose;
  DemoFleetPose? _prevPoseForSpeed;
  OpsMapController? _mapCtl;
  bool _iconsReady = false;
  Map<String, dynamic>? _liveRow;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _unitSub;
  double? _speedKmh;
  int? _etaMins;
  String _lastPingLabel = '—';
  // ignore: unused_field
  LatLng? _etaVictimPin;
  String? _etaForIncidentId;
  int _tickCount = 0;

  static final _zone = IndiaOpsZones.lucknow;

  Map<String, dynamic> get _d => _liveRow ?? widget.data;

  @override
  void initState() {
    super.initState();
    _liveRow = Map<String, dynamic>.from(widget.data);
    _unitSub = FirebaseFirestore.instance.collection('ops_fleet_units').doc(widget.docId).snapshots().listen((s) {
      if (!s.exists || !mounted) return;
      setState(() => _liveRow = s.data());
    });
    FleetMapIcons.preload().then((_) {
      if (context.mounted) setState(() => _iconsReady = true);
    });
    _tick();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_refreshEta());
  }

  Future<void> _refreshEta() async {
    final aid = (_d['assignedIncidentId'] as String?)?.trim();
    if (aid == null || aid.isEmpty) {
      if (mounted) setState(() => _etaMins = null);
      return;
    }
    if (_etaForIncidentId == aid && _etaMins != null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('sos_incidents').doc(aid).get();
      if (!doc.exists || !mounted) return;
      final m = doc.data() ?? {};
      final la = (m['lastKnownLat'] as num?)?.toDouble();
      final lo = (m['lastKnownLng'] as num?)?.toDouble();
      final lat = la ?? (m['lat'] as num?)?.toDouble();
      final lng = lo ?? (m['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      final victim = LatLng(lat, lng);
      final unitLat = (_d['lat'] as num?)?.toDouble();
      final unitLng = (_d['lng'] as num?)?.toDouble();
      if (unitLat == null || unitLng == null) return;
      final route = await OsrmRouteUtil.drivingRoute(LatLng(unitLat, unitLng), victim);
      final eta = OsrmRouteUtil.etaMinutesFromRoute(route);
      if (!mounted) return;
      setState(() {
        _etaVictimPin = victim;
        _etaForIncidentId = aid;
        _etaMins = eta;
      });
    } catch (_) {}
  }

  void _tick() {
    if (!context.mounted) return;
    _tickCount++;
    final row = _d;
    DemoFleetPose p;
    if (DemoFleetSimulation.isDemoDoc(widget.docId)) {
      p = DemoFleetSimulation.poseFor(
        widget.docId,
        DateTime.now(),
        _zone,
        assignedIncidentId: row['assignedIncidentId'] as String?,
      );
    } else {
      final lat = (row['lat'] as num?)?.toDouble();
      final lng = (row['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      p = DemoFleetPose(LatLng(lat, lng), (row['headingDeg'] as num?)?.toDouble() ?? 0);
    }
    final prev = _prevPoseForSpeed;
    if (prev != null) {
      final dM = Geolocator.distanceBetween(
        prev.latLng.latitude,
        prev.latLng.longitude,
        p.latLng.latitude,
        p.latLng.longitude,
      );
      _speedKmh = (dM * 3.6).clamp(0, 180);
    }
    _prevPoseForSpeed = p;

    final upd = row['updatedAt'];
    if (upd is Timestamp) {
      final ago = DateTime.now().difference(upd.toDate());
      if (ago.inSeconds < 90) {
        _lastPingLabel = '${ago.inSeconds}s ago';
      } else if (ago.inMinutes < 120) {
        _lastPingLabel = '${ago.inMinutes}m ago';
      } else {
        _lastPingLabel = '${ago.inHours}h ago';
      }
    }

    setState(() => _pose = p);
    _mapCtl?.animateCamera(CameraUpdate.newLatLng(p.latLng));
    if (_tickCount % 15 == 0) unawaited(_refreshEta());
  }

  BitmapDescriptor _iconFor(String type) {
    final fallback = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    return switch (type) {
      'medical' || 'ambulance' => FleetMapIcons.ambulanceOr(fallback),
      _ => fallback,
    };
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _unitSub?.cancel();
    _mapCtl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callSign = (widget.data['fleetCallSign'] as String?)?.trim() ?? widget.docId;
    final type = (widget.data['vehicleType'] as String?)?.trim().toLowerCase() ?? 'unknown';
    final isDemo = DemoFleetSimulation.isDemoDoc(widget.docId);
    final pose = _pose;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, __) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.my_location, color: Colors.greenAccent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tracking: $callSign',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        isDemo
                            ? 'Simulated track · 1 s updates · ~${_speedKmh?.toStringAsFixed(0) ?? "—"} km/h'
                            : 'Live row · Last ping: $_lastPingLabel · ~${_speedKmh?.toStringAsFixed(0) ?? "—"} km/h',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      if (_etaMins != null)
                        Text(
                          'ETA to assigned victim (OSRM est.): ~$_etaMins min',
                          style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (pose != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _Chip('Lat', pose.latLng.latitude.toStringAsFixed(5)),
                  const SizedBox(width: 6),
                  _Chip('Lng', pose.latLng.longitude.toStringAsFixed(5)),
                  const SizedBox(width: 6),
                  _Chip('Hdg', '${pose.headingDeg.round()}°'),
                  if (_speedKmh != null) ...[
                    const SizedBox(width: 6),
                    _Chip('Spd', '${_speedKmh!.round()} km/h'),
                  ],
                  if (_etaMins != null) ...[
                    const SizedBox(width: 6),
                    _Chip('ETA', '~$_etaMins m'),
                  ],
                  const SizedBox(width: 6),
                  _Chip('Ping', _lastPingLabel),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: pose == null
                ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                : EosHybridMap(
                    initialCameraPosition: CameraPosition(target: pose.latLng, zoom: 15),
                    onMapCreated: (c) => _mapCtl = c,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                    mapType: MapType.normal,
                    mapId: AppConstants.googleMapsDarkMapId.isNotEmpty ? AppConstants.googleMapsDarkMapId : null,
                    style: effectiveGoogleMapsEmbeddedStyleJson(),
                    markers: {
                      Marker(
                        markerId: const MarkerId('fleet_unit'),
                        position: pose.latLng,
                        rotation: pose.headingDeg,
                        anchor: const Offset(0.5, 0.5),
                        flat: true,
                        icon: _iconsReady
                            ? _iconFor(type)
                            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        infoWindow: InfoWindow(title: callSign, snippet: type.toUpperCase()),
                      ),
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace'),
      ),
    );
  }
}

// ── Create fleet (admin) ─────────────────────────────────────────────────────

class _CreateFleetSheet extends StatefulWidget {
  @override
  State<_CreateFleetSheet> createState() => _CreateFleetSheetState();
}

class _CreateFleetSheetState extends State<_CreateFleetSheet> {
  final _callSignCtl = TextEditingController();
  final _driverCtl = TextEditingController();
  final _coCtl = TextEditingController();
  String _vehicleType = 'medical';
  String? _hospitalId;
  bool _saving = false;

  @override
  void dispose() {
    _callSignCtl.dispose();
    _driverCtl.dispose();
    _coCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cs = _callSignCtl.text.trim();
    if (cs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.opsTr('Enter a fleet call sign / ID')), backgroundColor: Colors.redAccent),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await FleetUnitService.createUnit(
        fleetCallSign: cs,
        vehicleType: _vehicleType,
        driverName: _driverCtl.text.trim().isEmpty ? '—' : _driverCtl.text.trim(),
        coPassenger: _coCtl.text.trim().isEmpty ? '—' : _coCtl.text.trim(),
        assignedHospitalId: _hospitalId,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Created $cs. Operator gate is in ops_fleet_accounts — open Credentials on the unit card to view or reset the password.',
          ),
          backgroundColor: Colors.green.shade800,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtl) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, color: AppColors.accentBlue, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Create new fleet',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: ListView(
              controller: scrollCtl,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                TextField(
                  controller: _callSignCtl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: context.opsTr('Fleet ID / call sign'),
                    hintText: context.opsTr('e.g. EMS-LKO-57'),
                    labelStyle: const TextStyle(color: Colors.white54),
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.accentBlue)),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _vehicleType, // ignore: deprecated_member_use
                  dropdownColor: AppColors.slate800,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: context.opsTr('Vehicle type'),
                    labelStyle: TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  ),
                  items: [
                    DropdownMenuItem(value: 'medical', child: Text(context.opsTr('Medical / ambulance'))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _vehicleType = v);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _driverCtl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: context.opsTr('Driver name'),
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.accentBlue)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _coCtl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: context.opsTr('Co-passenger / EMT'),
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.accentBlue)),
                  ),
                ),
                const SizedBox(height: 16),
                StreamBuilder(
                  stream: OpsHospitalService.watchHospitals(),
                  builder: (context, snap) {
                    final rows = snap.data ?? <OpsHospitalRow>[];
                    return DropdownButtonFormField<String?>(
                      value: _hospitalId, // ignore: deprecated_member_use
                      dropdownColor: AppColors.slate800,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: context.opsTr('Home hospital (optional)'),
                        labelStyle: TextStyle(color: Colors.white54),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(context.opsTr('None'), style: TextStyle(color: Colors.white70)),
                        ),
                        ...rows.map(
                          (h) => DropdownMenuItem<String?>(
                            value: h.id,
                            child: Text('${h.id} — ${h.name}', style: const TextStyle(color: Colors.white70)),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _hospitalId = v),
                    );
                  },
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Creating…' : 'Create fleet unit'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
