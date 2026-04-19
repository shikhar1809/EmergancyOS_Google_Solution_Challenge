import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/maps/ops_map_controller.dart';
import '../../../core/config/build_config.dart';
import '../../../core/constants/india_ops_zones.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/map/domain/emergency_zone_classification.dart';
import '../../../core/utils/dispatch_incident_priority.dart';
import '../../../core/utils/fleet_unit_availability.dart';
import '../../../core/utils/fleet_map_icons.dart';
import '../../../core/utils/ops_fleet_docs_dedupe.dart';
import '../../../core/utils/osrm_route_util.dart';
import '../../../core/utils/ops_map_markers.dart';
import '../../../services/demo_fleet_route_cache.dart';
import '../../../services/demo_fleet_routing.dart';
import '../../../services/demo_fleet_simulation.dart';
import '../../../services/fleet_gate_credentials_service.dart';
import '../../../services/fleet_unit_service.dart';
import '../../../services/incident_service.dart';
import '../../../services/ops_hospital_service.dart';
import '../../../services/ops_zone_resource_catalog.dart';
import '../../../services/places_service.dart';
import '../../../services/ops_coverage_zone_service.dart';
import '../../../services/volunteer_presence_service.dart'
    show ActiveVolunteerNearby, VolunteerPresenceService;
import '../domain/admin_panel_access.dart';
import '../domain/command_center_accent.dart';
import 'widgets/command_center_inspector.dart';
import 'widgets/command_center_shared_widgets.dart';
import 'widgets/command_center_sidebar.dart';
import 'widgets/command_center_map.dart';
import 'widgets/fleet_credentials_dialog.dart';
import 'widgets/hospital_onboarding_dialog.dart';
import 'widgets/master_command_sidebar.dart';
import 'hospital_live_ops_screen.dart' show HospitalOverviewCapacitySection;
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

enum _LiveOpsDetailKind {
  none,
  incident,
  fleetDoc,
  hospital,
  volunteer,
  liveResponder,
}

/// Full-width ops dashboard: filters, incident list, live map. (Gemini Q&A lives under Analytics.)
class AdminCommandCenterScreen extends StatefulWidget {
  const AdminCommandCenterScreen({
    super.key,
    required this.access,
    this.focusIncidentId,
    this.masterSidebarMode = MasterCommandSidebarMode.none,
  });

  final AdminPanelAccess access;
  final String? focusIncidentId;

  /// Master-only: [none] = Overview with incident sidebar; [liveOps] = fleet / vols / hospitals sidebar.
  final MasterCommandSidebarMode masterSidebarMode;

  @override
  State<AdminCommandCenterScreen> createState() =>
      _AdminCommandCenterScreenState();
}

class _AdminCommandCenterScreenState extends State<AdminCommandCenterScreen>
    with TickerProviderStateMixin {
  Color get _accent => CommandCenterAccent.forRole(widget.access.role).primary;

  final _searchCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _etaAmbCtrl = TextEditingController();
  final _medLineCtrl = TextEditingController();
  final _incidentTypeCtrl = TextEditingController();
  OpsMapController? _mapCtl;

  String? _selectedId;

  /// Sidebar **Archive** tab selection (not in active [filtered] list).
  SosIncident? _archiveSidebarSelection;

  /// Firestore archive doc `status` (or similar) when [_archiveSidebarSelection] is shown.
  String _archiveClosureLabel = '';
  String? _selectedFleetKey;
  bool _liveOpsDetailOpen = true;
  _LiveOpsDetailKind _liveOpsDetailKind = _LiveOpsDetailKind.none;
  String? _liveOpsFleetDocId;
  OpsHospitalRow? _liveOpsHospitalRow;
  String? _liveOpsVolunteerUserId;
  String? _liveOpsLiveResponderKey;
  String? _controllerIncidentId;
  IncidentStatus? _statusFilter;
  String _typeFilter = '';
  TimeWin _timeWin = TimeWin.h24;
  final bool _nearSelectionOnly = false;
  final bool _onlyWithVolunteers = false;
  bool _onlyEmsActive = false;
  bool _onlySmsLinked = false;

  IndiaOpsZone? _zone;

  /// True when [boundHospitalDocId] resolved to a hospital-centred ops zone (30 km mesh).
  bool _hospitalScopedZone = false;
  LatLng? _boundHospitalMarkerPos;
  String? _boundHospitalMarkerName;
  int? _boundHospitalBedsAvail;
  int? _boundHospitalBedsTotal;
  String? _boundHospitalRegion;
  List<String> _boundHospitalServices = const [];
  TabController? _legacySidebarTabs;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _volunteerDutySub;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _volunteerDutyDocs =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _fleetSub;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _fleetDocs =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _allIncidentSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allIncidentDocs = [];
  List<SosIncident> _cachedFiltered = [];
  EmergencyHexZoneModel? _cachedHexModel;
  final Map<String, LatLng> _fleetTargetPos = {};
  final Map<String, LatLng> _fleetSmoothPos = {};
  Timer? _fleetSmoothTimer;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _coverageZonesSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _coverageZoneDocs = [];
  bool _zoneEditMode = false;
  HexAxial? _editHexAxial;
  List<LatLng> _editCornerTaps = [];
  StreamSubscription<OpsHospitalRow?>? _hospitalRowSub;
  StreamSubscription<List<OpsHospitalRow>>? _allOpsHospitalsSub;
  List<OpsHospitalRow> _allOpsHospitals = [];
  double _commandMapZoom = 11.0;

  /// Driving route from representative hospital → selected incident (OSRM).
  List<LatLng> _selectedHospitalRoute = const [];
  int? _selectedHospitalRouteEtaMin;
  bool _selectedHospitalRouteLoading = false;
  int _hospitalRouteReqSeq = 0;
  final Map<String, double> _simHeadingByMarkerKey = {};
  Set<String> _simulatedFleetKeys = {};
  final Map<String, double> _fleetSmoothHeading = {};
  int _evictCountdown = 2700; // ~90s @ 33ms tick

  static const int _maxFacilityMarkers = 40;

  /// Map layer toggles (all roles). Hex uses full zone directory for green/yellow/red — not role-filtered.
  bool _ccShowHexGrid = true;
  bool _ccShowActiveFleet = true;
  bool _ccShowStandbyFleet = true;
  bool _ccShowStations = true;

  @override
  void initState() {
    super.initState();
    // Medical + master Overview: incident list sidebar (Active consignments, archive, …).
    // Master Live Ops tab uses [MasterLiveOpsSidebar] instead — no tab controller here.
    final useIncidentSidebar =
        widget.access.role != AdminConsoleRole.master ||
        widget.masterSidebarMode == MasterCommandSidebarMode.none;
    if (useIncidentSidebar) {
      _legacySidebarTabs = TabController(
        length: widget.access.commandTabs.length,
        vsync: this,
      );
    }
    final f = widget.focusIncidentId?.trim();
    if (f != null && f.isNotEmpty) _selectedId = f;
    if (widget.access.role == AdminConsoleRole.master) {
      _timeWin = TimeWin.h1;
    }
    _volunteerDutySub = VolunteerPresenceService.watchOnDutyUsers().listen((
      snap,
    ) {
      if (!context.mounted) return;
      setState(() {
        _volunteerDutyDocs
          ..clear()
          ..addAll(snap.docs);
        _rebuildHexGrid();
      });
    });
    _fleetSub = FleetUnitService.watchFleetUnits().listen((snap) {
      if (!context.mounted) return;
      setState(() {
        _fleetDocs
          ..clear()
          ..addAll(snap.docs.where((d) => !d.id.startsWith('demo_')));
      });
      _scheduleDemoRoutePrefetch();
      _applyFleetTargets();
    });
    _allIncidentSub = FirebaseFirestore.instance
        .collection('sos_incidents')
        .limit(400)
        .snapshots()
        .listen((snap) {
          if (!context.mounted) return;
          setState(() {
            _allIncidentDocs = snap.docs;
            _cachedFiltered = _applyFilters(
              snap.docs.map(SosIncident.fromFirestore).toList(),
            );
            // Refresh hex grid on data changes
            _rebuildHexGrid();
          });
          _scheduleDemoRoutePrefetch();
          _applyFleetTargets();
        });

    _fleetSmoothTimer = Timer.periodic(
      const Duration(milliseconds: 33),
      (_) => _tickFleetSmooth(),
    );
    _allOpsHospitalsSub = OpsHospitalService.watchHospitals().listen((rows) {
      if (!mounted) return;
      setState(() => _allOpsHospitals = rows);
    });
    _bootstrapOps();
  }

  Future<void> _bootstrapOps() async {
    await OpsMapMarkers.preload();
    await FleetMapIcons.preload();
    if (!context.mounted) return;

    var z = IndiaOpsZones.byId(IndiaOpsZones.lucknowZoneId);
    var hospitalScoped = false;
    LatLng? hospPos;
    String? hospName;
    int? bedsAvail;
    int? bedsTotal;
    String? hospRegion;
    List<String> hospServices = const [];

    final hid = widget.access.boundHospitalDocId?.trim();
    if (widget.access.role == AdminConsoleRole.medical &&
        hid != null &&
        hid.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('ops_hospitals')
            .doc(hid)
            .get();
        final d = doc.data();
        final lat = (d?['lat'] as num?)?.toDouble();
        final lng = (d?['lng'] as num?)?.toDouble();
        final name = (d?['name'] as String?)?.trim();
        if (d != null) {
          bedsAvail = (d['bedsAvailable'] as num?)?.toInt();
          bedsTotal = (d['bedsTotal'] as num?)?.toInt();
          hospRegion = (d['region'] as String?)?.trim();
          final raw = d['offeredServices'];
          if (raw is List) {
            hospServices = raw
                .map((e) => e.toString())
                .where((s) => s.isNotEmpty)
                .take(8)
                .toList();
          }
        }
        if (lat != null && lng != null) {
          final labelWithCode = (name != null && name.isNotEmpty)
              ? '$hid · $name'
              : hid;
          z = IndiaOpsZone(
            id: 'hospital_scope',
            label: labelWithCode,
            center: LatLng(lat, lng),
            radiusKm: 30,
            defaultZoom: 12.4,
          );
          hospitalScoped = true;
          hospPos = LatLng(lat, lng);
          hospName = name ?? hid;
        }
      } catch (e) {
        debugPrint('[CommandCenter] hospital zone bootstrap: $e');
      }
    }

    // Trigger multi-point Places fetch for extended coverage (e.g. Lucknow → Barabanki).
    unawaited(
      OpsZoneResourceCatalog.fetchAndMergeHospitalsForZone(
        z,
        extraAnchors: const [LatLng(26.93, 81.18)],
      ).then((_) {
        if (mounted) setState(() => _rebuildHexGrid());
      }),
    );

    if (!context.mounted) return;
    setState(() {
      _zone = z;
      _hospitalScopedZone = hospitalScoped;
      _boundHospitalMarkerPos = hospPos;
      _boundHospitalMarkerName = hospName;
      _boundHospitalBedsAvail = bedsAvail;
      _boundHospitalBedsTotal = bedsTotal;
      _boundHospitalRegion = hospRegion;
      _boundHospitalServices = hospServices;
      _rebuildHexGrid();
    });

    if (widget.access.role == AdminConsoleRole.master) {
      _coverageZonesSub?.cancel();
      _coverageZonesSub = OpsCoverageZoneService.watchForZone(z.id).listen((
        snap,
      ) {
        if (!mounted) return;
        setState(() => _coverageZoneDocs = snap.docs);
      });
    }

    // Keep hospital summary (beds, services, name) in sync with LiveOps — single-doc stream.
    if (widget.access.role == AdminConsoleRole.medical &&
        hid != null &&
        hid.isNotEmpty) {
      _hospitalRowSub ??= OpsHospitalService.watchHospital(hid).listen((row) {
        if (!mounted || row == null) return;
        setState(() {
          _boundHospitalMarkerName = row.name;
          _boundHospitalBedsAvail = row.bedsAvailable;
          _boundHospitalBedsTotal = row.bedsTotal;
          _boundHospitalRegion = row.region;
          _boundHospitalServices = row.offeredServices;
        });
      });
    }
    _scheduleDemoRoutePrefetch();
  }

  @override
  void dispose() {
    _legacySidebarTabs?.dispose();
    _volunteerDutySub?.cancel();
    _fleetSub?.cancel();
    _hospitalRowSub?.cancel();
    _allOpsHospitalsSub?.cancel();
    _allIncidentSub?.cancel();
    _fleetSmoothTimer?.cancel();
    _coverageZonesSub?.cancel();
    _searchCtrl.dispose();
    _typeCtrl.dispose();
    _noteCtrl.dispose();
    _etaAmbCtrl.dispose();
    _medLineCtrl.dispose();
    _incidentTypeCtrl.dispose();
    _mapCtl?.dispose();
    super.dispose();
  }

  /// Unique hospital code (Firestore `ops_hospitals` doc id) before the facility name.
  String _hospitalTitleWithCode(String? docId, String? displayName) {
    final code = (docId ?? '').trim();
    final n = (displayName ?? '').trim();
    final friendly = n.isEmpty ? 'Hospital' : n;
    if (code.isEmpty) return friendly;
    return '$code · $friendly';
  }

  void _syncDetailControllers(SosIncident e) {
    _controllerIncidentId = e.id;
    _noteCtrl.text = e.adminDispatchNote ?? '';
    _etaAmbCtrl.text = e.ambulanceEta ?? '';
    _medLineCtrl.text = e.medicalStatus ?? '';
    _incidentTypeCtrl.text = e.type;
  }

  /// Same ops anchor as the public map / master overview ([BuildConfig.opsZoneId]).
  IndiaOpsZone get _canonicalOpsZoneForHex =>
      IndiaOpsZones.byId(BuildConfig.opsZoneId);

  /// Hex disk radius (15 km cap) — matches master overview, independent of hospital-local zone radius.
  double get _hexMeshCoverM =>
      math.min(kMaxCoverageRadiusM, kCommandCenterHexCoverRadiusM);

  void _rebuildHexGrid() {
    if (_zone == null) return;
    final anchor = _canonicalOpsZoneForHex;
    final coverM = _hexMeshCoverM;
    _cachedHexModel = buildEmergencyHexZones(
      center: anchor.center,
      coverRadiusM: coverM,
      hospitals: OpsZoneResourceCatalog.hospitalsInZoneMerged(anchor, _allOpsHospitals),
      volunteerPositions: OpsZoneResourceCatalog.volunteersInZone(
        _volunteerDutyDocs,
        anchor,
      ).map((v) => LatLng(v.lat, v.lng)).toList(),
      useMainAppHospitalDensityColors: true,
    );
  }

  Future<void> _saveDispatchFields() async {
    final id = _selectedId?.trim();
    if (id == null || id.isEmpty) return;
    if (_archiveSidebarSelection != null && _archiveSidebarSelection!.id == id)
      return;
    final amb = _etaAmbCtrl.text.trim();
    final med = _medLineCtrl.text.trim();
    final typ = _incidentTypeCtrl.text.trim();
    await IncidentService.patchIncidentOpsFields(id, {
      'ambulanceEta': amb.isEmpty ? FieldValue.delete() : amb,
      'medicalStatus': med.isEmpty ? FieldValue.delete() : med,
      if (typ.isNotEmpty) 'type': typ,
      'etaUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  bool _isDemoIncidentId(String id) =>
      id.startsWith('demo_') || id.startsWith('demo_ops_');

  List<SosIncident> _applyFilters(List<SosIncident> raw) {
    var list = List<SosIncident>.from(raw);
    list = list.where((e) => !_isDemoIncidentId(e.id)).toList();
    final now = DateTime.now();
    switch (_timeWin) {
      case TimeWin.h1:
        list = list
            .where((e) => now.difference(e.timestamp) < const Duration(hours: 1))
            .toList();
      case TimeWin.h24:
        list = list
            .where((e) => now.difference(e.timestamp).inHours < 24)
            .toList();
      case TimeWin.d7:
        list = list
            .where((e) => now.difference(e.timestamp).inDays < 7)
            .toList();
      case TimeWin.all:
        break;
    }
    if (_statusFilter != null) {
      list = list.where((e) => e.status == _statusFilter).toList();
    }
    if (_typeFilter.trim().isNotEmpty) {
      final t = _typeFilter.trim().toLowerCase();
      list = list.where((e) => e.type.toLowerCase().contains(t)).toList();
    }
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) {
        return e.id.toLowerCase().contains(q) ||
            e.userDisplayName.toLowerCase().contains(q) ||
            e.type.toLowerCase().contains(q);
      }).toList();
    }
    if (_nearSelectionOnly && _selectedId != null) {
      SosIncident? sel;
      for (final e in raw) {
        if (e.id == _selectedId) {
          sel = e;
          break;
        }
      }
      if (sel != null) {
        list = list.where((e) {
          if (e.id == sel!.id) return true;
          final d = _haversineKm(
            sel.liveVictimPin.latitude,
            sel.liveVictimPin.longitude,
            e.liveVictimPin.latitude,
            e.liveVictimPin.longitude,
          );
          return d <= 25;
        }).toList();
      }
    }
    if (_onlyWithVolunteers) {
      list = list.where((e) => e.acceptedVolunteerIds.isNotEmpty).toList();
    }
    if (_onlyEmsActive) {
      list = list
          .where((e) => (e.emsWorkflowPhase ?? '').trim().isNotEmpty)
          .toList();
    }
    if (_onlySmsLinked) {
      list = list.where((e) => e.smsRelayOrOrigin).toList();
    }
    final z = _zone;
    if (z != null) {
      list = list.where((e) => z.containsLatLng(e.liveVictimPin)).toList();
    }
    if (z != null) {
      final hexZ = _canonicalOpsZoneForHex;
      final hospitals = OpsZoneResourceCatalog.hospitalsInZoneMerged(hexZ, _allOpsHospitals);
      final volPos = OpsZoneResourceCatalog.volunteersInZone(
        _volunteerDutyDocs,
        hexZ,
      ).map((v) => LatLng(v.lat, v.lng)).toList();
      final coverM = _hexMeshCoverM;
      list.sort((a, b) {
        final ta = tierHealthAtVictimPin(
          gridCenter: hexZ.center,
          victimPin: a.liveVictimPin,
          coverRadiusM: coverM,
          hospitals: hospitals,
          volunteerPositions: volPos,
        );
        final tb = tierHealthAtVictimPin(
          gridCenter: hexZ.center,
          victimPin: b.liveVictimPin,
          coverRadiusM: coverM,
          hospitals: hospitals,
          volunteerPositions: volPos,
        );
        return DispatchIncidentPriority.compare(a, b, ta, tb);
      });
    } else {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    return list;
  }

  String _priorityLabelFor(SosIncident e) {
    final z = _zone;
    if (z == null)
      return DispatchIncidentPriority.forIncident(e, TierHealth.green).label;
    final hexZ = _canonicalOpsZoneForHex;
    final coverM = _hexMeshCoverM;
    final tier = tierHealthAtVictimPin(
      gridCenter: hexZ.center,
      victimPin: e.liveVictimPin,
      coverRadiusM: coverM,
      hospitals: OpsZoneResourceCatalog.hospitalsInZoneMerged(hexZ, _allOpsHospitals),
      volunteerPositions: OpsZoneResourceCatalog.volunteersInZone(
        _volunteerDutyDocs,
        hexZ,
      ).map((v) => LatLng(v.lat, v.lng)).toList(),
    );
    return DispatchIncidentPriority.forIncident(e, tier).label;
  }

  double _haversineKm(double la, double lo, double lb, double lob) {
    const earth = 6371.0;
    final dLat = math.pi / 180 * (lb - la);
    final dLon = math.pi / 180 * (lob - lo);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(math.pi / 180 * la) *
            math.cos(math.pi / 180 * lb) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earth * c;
  }

  SosIncident? _pick(List<SosIncident> list, String? id) {
    if (id == null) return null;
    for (final e in list) {
      if (e.id == id) return e;
    }
    return null;
  }

  // ignore: unused_element
  SosIncident? _incidentById(String id) {
    for (final d in _allIncidentDocs) {
      if (d.id == id) return SosIncident.fromFirestore(d);
    }
    return null;
  }

  Future<void> _saveNote(SosIncident? sel) async {
    if (sel == null) return;
    final sm = ScaffoldMessenger.of(context);
    try {
      await IncidentService.setAdminDispatchNote(sel.id, _noteCtrl.text.trim());
      if (!mounted) return;
      sm.showSnackBar(SnackBar(content: Text(context.opsTr('Dispatch note saved'))));
    } catch (e) {
      if (!mounted) return;
      sm.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  void _focusOnMap(LatLng p, {double zoom = 14}) {
    _mapCtl?.animateCamera(CameraUpdate.newLatLngZoom(p, zoom));
  }

  void _liveOpsClearDetail() {
    _liveOpsDetailKind = _LiveOpsDetailKind.none;
    _liveOpsFleetDocId = null;
    _liveOpsHospitalRow = null;
    _liveOpsVolunteerUserId = null;
    _liveOpsLiveResponderKey = null;
  }

  LatLng _hospitalOriginForScene(LatLng scene, IndiaOpsZone z) {
    if (widget.access.role == AdminConsoleRole.medical &&
        _boundHospitalMarkerPos != null) {
      return _boundHospitalMarkerPos!;
    }
    final hospitals = OpsZoneResourceCatalog.hospitalsInZoneMerged(z, _allOpsHospitals);
    if (hospitals.isEmpty) return z.center;
    LatLng? best;
    double? bestM;
    for (final p in hospitals) {
      final m = Geolocator.distanceBetween(
        scene.latitude,
        scene.longitude,
        p.lat,
        p.lng,
      );
      if (bestM == null || m < bestM) {
        bestM = m;
        best = LatLng(p.lat, p.lng);
      }
    }
    return best ?? z.center;
  }

  void _frameHospitalAndScene(LatLng hospital, LatLng scene) {
    if (_mapCtl == null) return;
    final minLat = math.min(hospital.latitude, scene.latitude);
    final maxLat = math.max(hospital.latitude, scene.latitude);
    final minLng = math.min(hospital.longitude, scene.longitude);
    final maxLng = math.max(hospital.longitude, scene.longitude);
    var pad = 0.006;
    if ((maxLat - minLat).abs() < 1e-4 && (maxLng - minLng).abs() < 1e-4) {
      pad = 0.02;
    }
    _mapCtl!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - pad, minLng - pad),
          northeast: LatLng(maxLat + pad, maxLng + pad),
        ),
        64,
      ),
    );
  }

  void _frameRouteBounds(Iterable<LatLng> route) {
    if (_mapCtl == null) return;
    final pts = route.toList();
    if (pts.isEmpty) return;
    double minLat = pts.first.latitude;
    double maxLat = minLat;
    double minLng = pts.first.longitude;
    double maxLng = minLng;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    const pad = 0.004;
    _mapCtl!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - pad, minLng - pad),
          northeast: LatLng(maxLat + pad, maxLng + pad),
        ),
        56,
      ),
    );
  }

  void _frameMap(SosIncident? sel, List<SosIncident> markers) {
    if (_mapCtl == null) return;
    final z = _zone;
    if (_hospitalScopedZone &&
        widget.access.role == AdminConsoleRole.medical &&
        z != null) {
      _mapCtl!.animateCamera(
        CameraUpdate.newLatLngZoom(z.center, z.defaultZoom),
      );
    } else if (markers.isNotEmpty) {
      double minLat = markers.first.liveVictimPin.latitude;
      double maxLat = minLat;
      double minLng = markers.first.liveVictimPin.longitude;
      double maxLng = minLng;
      for (final e in markers.take(40)) {
        final p = e.liveVictimPin;
        minLat = minLat < p.latitude ? minLat : p.latitude;
        maxLat = maxLat > p.latitude ? maxLat : p.latitude;
        minLng = minLng < p.longitude ? minLng : p.longitude;
        maxLng = maxLng > p.longitude ? maxLng : p.longitude;
      }
      _mapCtl!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.02, minLng - 0.02),
            northeast: LatLng(maxLat + 0.02, maxLng + 0.02),
          ),
          48,
        ),
      );
    }
  }

  Future<void> _prefetchHospitalRoute(
    SosIncident incident,
    IndiaOpsZone z,
    LatLng origin,
  ) async {
    if (_archiveSidebarSelection != null &&
        _archiveSidebarSelection!.id == incident.id)
      return;
    final seq = ++_hospitalRouteReqSeq;
    if (mounted && _selectedId == incident.id) {
      setState(() => _selectedHospitalRouteLoading = true);
    }
    final scene = incident.liveVictimPin;
    final route = await OsrmRouteUtil.drivingRoute(origin, scene);
    if (!mounted) return;
    if (seq != _hospitalRouteReqSeq) return;
    if (_selectedId != incident.id) return;
    final eta = OsrmRouteUtil.etaMinutesFromRoute(route);
    setState(() {
      _selectedHospitalRoute = route;
      _selectedHospitalRouteEtaMin = eta;
      _selectedHospitalRouteLoading = false;
    });
    _frameRouteBounds(route);
  }

  void _applyIncidentSelection(
    SosIncident? incident,
    List<SosIncident> filtered,
  ) {
    final z = _zone;
    if (incident == null) {
      setState(() {
        _selectedId = null;
        _archiveSidebarSelection = null;
        _archiveClosureLabel = '';
        _selectedHospitalRoute = const [];
        _selectedHospitalRouteEtaMin = null;
        _selectedHospitalRouteLoading = false;
        _hospitalRouteReqSeq++;
        if (widget.masterSidebarMode == MasterCommandSidebarMode.liveOps) {
          _liveOpsClearDetail();
        }
      });
      _frameMap(null, filtered);
      return;
    }
    setState(() {
      _selectedId = incident.id;
      _archiveSidebarSelection = null;
      _selectedHospitalRoute = const [];
      _selectedHospitalRouteEtaMin = null;
      _selectedHospitalRouteLoading = true;
      if (widget.masterSidebarMode == MasterCommandSidebarMode.liveOps) {
        _liveOpsDetailKind = _LiveOpsDetailKind.incident;
        _liveOpsFleetDocId = null;
        _liveOpsHospitalRow = null;
        _liveOpsVolunteerUserId = null;
        _liveOpsLiveResponderKey = null;
        _liveOpsDetailOpen = true;
      }
      _selectedFleetKey = null;
    });
    _syncDetailControllers(incident);
    if (z != null) {
      final origin = _hospitalOriginForScene(incident.liveVictimPin, z);
      _frameHospitalAndScene(origin, incident.liveVictimPin);
      _prefetchHospitalRoute(incident, z, origin);
    } else {
      _mapCtl?.animateCamera(
        CameraUpdate.newLatLngZoom(incident.liveVictimPin, 13),
      );
      setState(() => _selectedHospitalRouteLoading = false);
    }
  }

  void _onArchiveIncidentTap(SosIncident incident, String closureStatus) {
    setState(() {
      _archiveSidebarSelection = incident;
      _archiveClosureLabel = closureStatus.trim().isEmpty
          ? 'archived'
          : closureStatus.trim();
      _selectedId = incident.id;
      _selectedFleetKey = null;
      _selectedHospitalRoute = const [];
      _selectedHospitalRouteEtaMin = null;
      _selectedHospitalRouteLoading = false;
      _hospitalRouteReqSeq++;
      if (widget.masterSidebarMode == MasterCommandSidebarMode.liveOps) {
        _liveOpsDetailKind = _LiveOpsDetailKind.incident;
        _liveOpsFleetDocId = null;
        _liveOpsHospitalRow = null;
        _liveOpsVolunteerUserId = null;
        _liveOpsLiveResponderKey = null;
        _liveOpsDetailOpen = true;
      }
    });
    final z = _zone;
    if (z != null) {
      final origin = _hospitalOriginForScene(incident.liveVictimPin, z);
      _frameHospitalAndScene(origin, incident.liveVictimPin);
    } else {
      _focusOnMap(incident.liveVictimPin);
    }
  }

  bool _nonSimTargetsDiffer(Map<String, LatLng> a, Map<String, LatLng> b) {
    if (a.length != b.length) return true;
    for (final e in a.entries) {
      final o = b[e.key];
      if (o == null) return true;
      if ((o.latitude - e.value.latitude).abs() > 1e-7) return true;
      if ((o.longitude - e.value.longitude).abs() > 1e-7) return true;
    }
    return false;
  }

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  Map<String, LatLng> _demoOpsVictimPins() {
    final m = <String, LatLng>{};
    for (final e in _cachedFiltered) {
      if (e.id.startsWith('demo_ops_')) m[e.id] = e.liveVictimPin;
    }
    return m;
  }

  void _scheduleDemoRoutePrefetch() {
    final z = _zone;
    if (z == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted || _zone != z) return;
      final scenes = _demoOpsVictimPins();
      for (final d in _fleetDocs) {
        if (!DemoFleetSimulation.isDemoDoc(d.id)) continue;
        final data = d.data();
        final aid = (data['assignedIncidentId'] as String?)?.trim();
        final pin = aid != null ? scenes[aid] : null;
        final (a, b) = DemoFleetRouting.fleetEndpoints(
          d.id,
          z,
          aid,
          pin,
          scenes,
        );
        final key = DemoFleetRouting.fleetCacheKey(d.id, z, a, b);
        DemoFleetRouteCache.prefetchFleetLoop(key, a, b);
        await Future<void>.delayed(const Duration(milliseconds: 75));
        if (!context.mounted || _zone != z) return;
      }
      final access = widget.access;
      for (final e in _cachedFiltered) {
        if (!DemoResponderSimulation.isDemoIncident(e.id)) continue;
        final scene = e.liveVictimPin;
        if (e.ambulanceLiveLocation != null &&
            access.isIncidentLiveFleetKeyAllowed('live_${e.id}_amb')) {
          DemoFleetRouteCache.prefetchResponderRoute(e.id, 'amb', scene, z);
          await Future<void>.delayed(const Duration(milliseconds: 75));
          if (!context.mounted || _zone != z) return;
        }
      }
      if (context.mounted) setState(() {});
    });
  }

  static double _lerpHeadingDeg(double from, double to, double t) {
    var delta = (to - from) % 360.0;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    var r = from + delta * t;
    r %= 360;
    if (r < 0) r += 360;
    return r;
  }

  (String incidentId, String role)? _parseLiveSimKey(String k) {
    if (!k.startsWith('live_')) return null;
    const suf = <String, String>{'_amb': 'amb'};
    for (final e in suf.entries) {
      if (k.endsWith(e.key)) {
        final id = k.substring(5, k.length - e.key.length);
        return (id, e.value);
      }
    }
    return null;
  }

  DemoFleetPose? _poseForSimulatedMarkerKey(
    String key,
    DateTime now,
    IndiaOpsZone z,
  ) {
    final scenes = _demoOpsVictimPins();
    if (key.startsWith('fleet_')) {
      final id = key.substring(6);
      if (!DemoFleetSimulation.isDemoDoc(id)) return null;
      String? aid;
      for (final d in _fleetDocs) {
        if (d.id != id) continue;
        aid = (d.data()['assignedIncidentId'] as String?)?.trim();
        break;
      }
      final pin = aid != null ? scenes[aid] : null;
      var pose = DemoFleetSimulation.poseFor(
        id,
        now,
        z,
        assignedIncidentId: aid,
        assignedIncidentScene: pin,
        demoIncidentScenes: scenes,
      );
      if (_hospitalScopedZone) {
        pose = DemoFleetSimulation.clampPoseToZone(pose, z);
      }
      return pose;
    }
    final parsed = _parseLiveSimKey(key);
    if (parsed == null) return null;
    for (final e in _cachedFiltered) {
      if (e.id != parsed.$1) continue;
      if (!DemoResponderSimulation.isDemoIncident(e.id)) return null;
      return DemoResponderSimulation.respondingUnitNearScene(
        e.id,
        parsed.$2,
        e.liveVictimPin,
        now,
      );
    }
    return null;
  }

  void _applyFleetTargets() {
    final z = _zone;
    if (z == null) return;
    final access = widget.access;
    final scenes = _demoOpsVictimPins();
    final next = <String, LatLng>{};
    final nextSim = <String>{};
    final now = DateTime.now();
    final prevSim = _simulatedFleetKeys;

    for (final d in dedupeFleetDocsByCallSign(_fleetDocs)) {
      final data = d.data();
      if (!access.isFleetDocVisible(data, d.id)) continue;
      if (!fleetUnitIsStaffedAvailable(data, d.id)) continue;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final key = 'fleet_${d.id}';
      if (DemoFleetSimulation.isDemoDoc(d.id)) {
        final aid = (data['assignedIncidentId'] as String?)?.trim();
        final pin = aid != null ? scenes[aid] : null;
        final pose = DemoFleetSimulation.poseFor(
          d.id,
          now,
          z,
          assignedIncidentId: aid,
          assignedIncidentScene: pin,
          demoIncidentScenes: scenes,
        );
        if (z.containsLatLng(pose.latLng)) {
          nextSim.add(key);
          _simHeadingByMarkerKey.remove(key);
        }
        continue;
      }
      final p = LatLng(lat, lng);
      if (!z.containsLatLng(p)) continue;
      next[key] = p;
      _simHeadingByMarkerKey.remove(key);
    }
    for (final e in _cachedFiltered) {
      final scene = e.liveVictimPin;
      final amb = e.ambulanceLiveLocation;
      if (amb != null) {
        final k = 'live_${e.id}_amb';
        if (access.isIncidentLiveFleetKeyAllowed(k)) {
          if (DemoResponderSimulation.isDemoIncident(e.id)) {
            final pose = DemoResponderSimulation.respondingUnitNearScene(
              e.id,
              'amb',
              scene,
              now,
            );
            if (z.containsLatLng(pose.latLng)) {
              nextSim.add(k);
              _simHeadingByMarkerKey.remove(k);
            }
          } else {
            next[k] = amb;
            _simHeadingByMarkerKey.remove(k);
          }
        }
      }
    }

    _simulatedFleetKeys = nextSim;
    final targetsChanged = _nonSimTargetsDiffer(_fleetTargetPos, next);
    final simMembershipChanged = !_setEquals(prevSim, nextSim);
    if (!targetsChanged && !simMembershipChanged) return;
    setState(() {
      _fleetTargetPos
        ..clear()
        ..addAll(next);

      // Prime _fleetSmoothPos immediately on first tick to fix hex-grid / fleet visibility delay
      for (final e in next.entries) {
        if (!_fleetSmoothPos.containsKey(e.key)) {
          _fleetSmoothPos[e.key] = e.value;
        }
      }
      for (final simKey in nextSim) {
        if (!_fleetSmoothPos.containsKey(simKey)) {
          final pose = _poseForSimulatedMarkerKey(simKey, now, z);
          if (pose != null) {
            _fleetSmoothPos[simKey] = pose.latLng;
            _fleetSmoothHeading[simKey] = pose.headingDeg;
          }
        }
      }
    });
  }

  void _tickFleetSmooth() {
    if (!context.mounted) return;
    if (_fleetTargetPos.isEmpty &&
        _simulatedFleetKeys.isEmpty &&
        _fleetSmoothPos.isEmpty)
      return;
    final z = _zone;
    if (z == null) return;
    final now = DateTime.now();
    const double alpha =
        0.12; // Slightly "heavier" catch-up for smoother movement
    const double hAlpha = 0.18; // Smoother heading transitions
    var changed = false;

    final keepKeys = {..._fleetTargetPos.keys, ..._simulatedFleetKeys};

    for (final key in _simulatedFleetKeys) {
      var pose = _poseForSimulatedMarkerKey(key, now, z);
      if (pose == null) continue;
      if (_hospitalScopedZone && key.startsWith('fleet_')) {
        pose = DemoFleetSimulation.clampPoseToZone(pose, z);
      } else if (!z.containsLatLng(pose.latLng)) {
        continue;
      }

      final cur = _fleetSmoothPos[key];
      if (cur == null) {
        _fleetSmoothPos[key] = pose.latLng;
      } else {
        // Interpolate simulated position too for maximum smoothness across tick rate variations
        final nLat =
            cur.latitude + (pose.latLng.latitude - cur.latitude) * alpha;
        final nLng =
            cur.longitude + (pose.latLng.longitude - cur.longitude) * alpha;
        _fleetSmoothPos[key] = LatLng(nLat, nLng);
      }

      final prevH = _fleetSmoothHeading[key] ?? pose.headingDeg;

      var dH = (pose.headingDeg - prevH) % 360.0;
      if (dH > 180) dH -= 360;
      if (dH < -180) dH += 360;

      // If the jump is massive (e.g. teleport/reset), snap it.
      if (dH.abs() > 140) {
        _fleetSmoothHeading[key] = pose.headingDeg;
      } else {
        _fleetSmoothHeading[key] = _lerpHeadingDeg(
          prevH,
          pose.headingDeg,
          hAlpha,
        );
      }
      changed = true;
    }

    for (final k in _fleetSmoothPos.keys.toList()) {
      if (!keepKeys.contains(k)) {
        _fleetSmoothPos.remove(k);
        _fleetSmoothHeading.remove(k);
        changed = true;
      }
    }

    for (final e in _fleetTargetPos.entries) {
      if (_simulatedFleetKeys.contains(e.key)) continue;
      final t = e.value;
      final cur = _fleetSmoothPos[e.key];
      if (cur == null) {
        _fleetSmoothPos[e.key] = t;
        changed = true;
      } else {
        final dLat = (t.latitude - cur.latitude).abs();
        final dLng = (t.longitude - cur.longitude).abs();
        if (dLat < 2e-6 && dLng < 2e-6) {
          if (cur.latitude != t.latitude || cur.longitude != t.longitude) {
            _fleetSmoothPos[e.key] = t;
            changed = true;
          }
        } else {
          final nLat = cur.latitude + (t.latitude - cur.latitude) * alpha;
          final nLng = cur.longitude + (t.longitude - cur.longitude) * alpha;
          _fleetSmoothPos[e.key] = LatLng(nLat, nLng);

          final targetH = Geolocator.bearingBetween(
            cur.latitude,
            cur.longitude,
            t.latitude,
            t.longitude,
          );
          if (!targetH.isNaN) {
            final prevH = _fleetSmoothHeading[e.key] ?? targetH;
            var dH = (targetH - prevH) % 360.0;
            if (dH > 180) dH -= 360;
            if (dH < -180) dH += 360;
            if (dH.abs() > 120) {
              _fleetSmoothHeading[e.key] = targetH;
            } else {
              _fleetSmoothHeading[e.key] = _lerpHeadingDeg(
                prevH,
                targetH,
                hAlpha,
              );
            }
          }

          changed = true;
        }
      }
    }
    if (_evictCountdown > 0) {
      _evictCountdown--;
    } else {
      _evictCountdown = 2700; // Reset
      DemoFleetRouteCache.evictFallbacks();
    }

    if (changed) setState(() {});
  }

  BitmapDescriptor _fleetMarkerIcon(
    String key,
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> fleetByUid,
  ) {
    final z = _commandMapZoom;
    final fallback = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueAzure,
    );
    if (key.startsWith('fleet_')) {
      return FleetMapIcons.ambulanceForZoom(z, fallback);
    }
    if (key.endsWith('_amb'))
      return FleetMapIcons.ambulanceForZoom(z, fallback);
    return FleetMapIcons.ambulanceForZoom(z, fallback);
  }

  double _fleetMarkerRotation(
    String key,
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> fleetByUid,
  ) {
    final smoothH = _fleetSmoothHeading[key];
    if (smoothH != null) return smoothH;
    final sim = _simHeadingByMarkerKey[key];
    if (sim != null) return sim;
    if (!key.startsWith('fleet_')) {
      final h = _liveHeadingFromIncident(key);
      return h ?? 0;
    }
    final doc = fleetByUid[key.substring(6)];
    final h = doc?.data()['headingDeg'];
    if (h is num) return h.toDouble();
    return 0;
  }

  static String _hospitalDistanceLine(LatLng hospital, LatLng scenePin) {
    final m = Geolocator.distanceBetween(
      hospital.latitude,
      hospital.longitude,
      scenePin.latitude,
      scenePin.longitude,
    );
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km from hospital';
    return '${m.round()} m from hospital';
  }

  double? _liveHeadingFromIncident(String markerKey) {
    if (!markerKey.endsWith('_amb') || !markerKey.startsWith('live_'))
      return null;
    const suf = 'amb';
    final id = markerKey.substring(5, markerKey.length - suf.length - 1);
    for (final e in _cachedFiltered) {
      if (e.id != id) continue;
      return e.ambulanceLiveHeadingDeg;
    }
    return null;
  }

  /// Shared full-height incident command surface (medical consignment or master active alert).
  Widget _dockedIncidentCommandPanel({
    required SosIncident sel,
    required IndiaOpsZone zone,
    required TierHealth sceneIncidentTier,
    required EmergencyHexZoneModel hexModel,
    required String headerTitle,
    required String clearSelectionTooltip,
    required String? boundHospitalDocId,
    required bool showMasterHospitalControls,
  }) {
    return Material(
      color: AppColors.slate800,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            headerTitle,
                            style: TextStyle(
                              color: _accent.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sel.type,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            '${sel.userDisplayName} · ${sel.id}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                          if (_boundHospitalMarkerPos != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _hospitalDistanceLine(
                                _boundHospitalMarkerPos!,
                                sel.liveVictimPin,
                              ),
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: clearSelectionTooltip,
                      onPressed: () =>
                          _applyIncidentSelection(null, _cachedFiltered),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white54,
                        size: 22,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    InfoChip('St', sel.status.name),
                    InfoChip('V', '${sel.acceptedVolunteerIds.length}'),
                    InfoChip('O', '${sel.onSceneVolunteerIds.length}'),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              children: const [
                LegendDot(color: Colors.tealAccent, label: 'Hex coverage grid'),
                LegendDot(color: Colors.redAccent, label: 'Incident / scene'),
                LegendDot(color: Colors.greenAccent, label: 'Responder'),
                LegendDot(
                  color: Colors.lightBlueAccent,
                  label: 'Fleet (ambulances)',
                ),
                LegendDot(color: Color(0xFF26C6DA), label: 'Hospital dir.'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Text(
              _ccShowHexGrid
                  ? 'Grid · ${hexModel.totalCells} cells · ${hexModel.coveragePercent.toStringAsFixed(0)}% green · 30 km mesh'
                  : 'Coverage grid off — toggle on map to show tier cells',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                child: CommandCenterInspector(
                  incident: sel,
                  opsZone: zone,
                  sceneIncidentTier: sceneIncidentTier,
                  fleetDocs:
                      dedupeFleetDocsByCallSign(_fleetDocs),
                  boundHospitalDocId: boundHospitalDocId,
                  showMasterHospitalControls: showMasterHospitalControls,
                  noteController: _noteCtrl,
                  etaAmbController: _etaAmbCtrl,
                  medLineController: _medLineCtrl,
                  incidentTypeController: _incidentTypeCtrl,
                  onSaveNote: () => _saveNote(sel),
                  onSaveDispatchFields: _saveDispatchFields,
                  onAfterMutation: () => setState(() {}),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Medical ops: full-height active consignment control surface in the right column.
  Widget _medicalDockedConsignmentPanel({
    required SosIncident sel,
    required IndiaOpsZone zone,
    required TierHealth sceneIncidentTier,
    required EmergencyHexZoneModel hexModel,
  }) {
    return _dockedIncidentCommandPanel(
      sel: sel,
      zone: zone,
      sceneIncidentTier: sceneIncidentTier,
      hexModel: hexModel,
      headerTitle: 'Incident command',
      clearSelectionTooltip: 'Clear consignment selection',
      boundHospitalDocId: widget.access.boundHospitalDocId,
      showMasterHospitalControls: false,
    );
  }

  /// Medical ops: read-only summary when the hospital user selects an **archived** consignment.
  Widget _medicalArchivedRecordPanel({
    required SosIncident sel,
    required String closureLabel,
    required EmergencyHexZoneModel hexModel,
  }) {
    final fmt = DateFormat.MMMd().add_Hm();
    final label = closureLabel.trim().isEmpty
        ? 'archived'
        : closureLabel.trim();
    return Material(
      color: AppColors.slate800,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Archived consignment',
                        style: TextStyle(
                          color: _accent.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sel.type,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${sel.userDisplayName} · ${sel.id}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          InfoChip('Closure', label),
                          InfoChip(
                            'Recorded',
                            fmt.format(sel.timestamp.toLocal()),
                          ),
                          InfoChip('St', sel.status.name),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.opsTr('Clear selection'),
                  onPressed: () =>
                      _applyIncidentSelection(null, _cachedFiltered),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white54,
                    size: 22,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 6,
              children: const [
                LegendDot(
                  color: Colors.deepPurpleAccent,
                  label: 'Archived scene pin',
                ),
                LegendDot(color: Colors.tealAccent, label: 'Hex coverage grid'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Text(
              _ccShowHexGrid
                  ? 'Grid · ${hexModel.totalCells} cells · ${hexModel.coveragePercent.toStringAsFixed(0)}% green · 30 km mesh'
                  : 'Coverage grid off — toggle on map to show tier cells',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
              child: Text(
                'This incident is closed in the live queue. The map shows the last known scene location. '
                'Dispatch edits and live controls stay disabled for archived records.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _syncFilteredFromDocs() {
    _cachedFiltered = _applyFilters(
      _allIncidentDocs.map(SosIncident.fromFirestore).toList(),
    );
  }

  /// Master ops only: zone summary + search/status/type/time + EMS/SMS toggles.
  /// Medical (hospital) role: no filter strip — list stays fully zone-scoped from bootstrap.
  Widget _commandCenterFilterBar(
    IndiaOpsZone zone,
    int incidentsInZoneVisible,
  ) {
    if (widget.access.role == AdminConsoleRole.medical) {
      return const SizedBox.shrink();
    }

    final typeLabels = <String>{};
    for (final d in _allIncidentDocs) {
      final t = SosIncident.fromFirestore(d).type.trim();
      if (t.isNotEmpty) typeLabels.add(t);
    }
    final sortedTypes = typeLabels.toList()..sort();

    final zoneLine = '${zone.label} · ${zone.radiusKm.round()} km';
    final countLine =
        '$incidentsInZoneVisible incident${incidentsInZoneVisible == 1 ? '' : 's'} in zone';

    Widget chipRow() {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
        child: Row(
          children: [
            FilterChipWidget(
              label: 'Command zone',
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  zoneLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChipWidget(
              label: 'Response area',
              child: Text(
                countLine,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 168,
              height: 30,
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 11),
                cursorColor: Colors.white70,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  filled: true,
                  fillColor: Colors.black26,
                  hintText: context.opsTr('Search id / name / type'),
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: _accent.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                onChanged: (_) => setState(_syncFilteredFromDocs),
              ),
            ),
            const SizedBox(width: 8),
            FilterChipWidget(
              label: 'Status',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<IncidentStatus?>(
                  value: _statusFilter,
                  isDense: true,
                  dropdownColor: AppColors.slate800,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  items: [
                    DropdownMenuItem<IncidentStatus?>(
                      value: null,
                      child: Text(context.opsTr('All statuses')),
                    ),
                    for (final s in IncidentStatus.values)
                      DropdownMenuItem<IncidentStatus?>(
                        value: s,
                        child: Text(s.name),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _statusFilter = v;
                    _syncFilteredFromDocs();
                  }),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChipWidget(
              label: 'Incident type',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _typeFilter.trim().isEmpty ? null : _typeFilter,
                  hint: Text(context.opsTr('All types'), style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  isDense: true,
                  dropdownColor: AppColors.slate800,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(context.opsTr('All types')),
                    ),
                    for (final t in sortedTypes)
                      DropdownMenuItem<String?>(
                        value: t,
                        child: Text(t, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _typeFilter = (v ?? '').trim();
                    _syncFilteredFromDocs();
                  }),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChipWidget(
              label: 'Time',
              child: DropdownButtonHideUnderline(
                child: DropdownButton<TimeWin>(
                  value: _timeWin,
                  isDense: true,
                  dropdownColor: AppColors.slate800,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                  items: [
                    DropdownMenuItem(value: TimeWin.h1, child: Text(context.opsTr('1h (active)'))),
                    DropdownMenuItem(value: TimeWin.h24, child: Text(context.opsTr('24h'))),
                    DropdownMenuItem(value: TimeWin.d7, child: Text(context.opsTr('7d'))),
                    DropdownMenuItem(
                      value: TimeWin.all,
                      child: Text(context.opsTr('All time')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _timeWin = v;
                      _syncFilteredFromDocs();
                    });
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text(context.opsTr('EMS phase')),
              selected: _onlyEmsActive,
              onSelected: (v) => setState(() {
                _onlyEmsActive = v;
                _syncFilteredFromDocs();
              }),
              showCheckmark: false,
              selectedColor: Colors.white12,
              checkmarkColor: Colors.white,
              labelStyle: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: _onlyEmsActive ? Colors.white70 : Colors.white24,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: Text(context.opsTr('SMS-linked')),
              selected: _onlySmsLinked,
              onSelected: (v) => setState(() {
                _onlySmsLinked = v;
                _syncFilteredFromDocs();
              }),
              showCheckmark: false,
              selectedColor: Colors.white12,
              checkmarkColor: Colors.white,
              labelStyle: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: _onlySmsLinked ? Colors.white70 : Colors.white24,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
    }

    return chipRow();
  }

  InfoWindow? _fleetInfoWindow(
    String key,
    Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> fleetByUid,
  ) {
    if (key.startsWith('fleet_')) {
      final id = key.substring(6);
      final doc = fleetByUid[id];
      if (doc != null) {
        final data = doc.data();
        final driver = data['driverName'] as String? ?? 'Pending / Unknown';
        final aid = data['assignedIncidentId'] as String?;
        final staffed = fleetUnitIsStaffedAvailable(data, id);
        final status = (data['status'] as String?)?.trim().isNotEmpty == true
            ? (data['status'] as String).trim()
            : (aid != null && aid.isNotEmpty
                ? 'responding'
                : (staffed
                    ? 'standby'
                    : (isFleetUnitPlaceholderDoc(id) ? 'no_operator' : 'off_duty')));
        final patientOnboard = data['patientOnboard'] == true;
        return InfoWindow(
          title: data['fleetCallSign'] as String? ?? id,
          snippet:
              'Driver: $driver | Status: $status | Patient: ${patientOnboard ? "Yes" : "No"}',
        );
      }
    }
    final parsed = _parseLiveSimKey(key);
    if (parsed != null) {
      return InfoWindow(
        title: 'Ambulance responder',
        snippet: 'En route to incident: ${parsed.$1}',
      );
    }
    return null;
  }

  Set<Polygon> _coverageZonePolygons() {
    final out = <Polygon>{};
    for (var i = 0; i < _coverageZoneDocs.length; i++) {
      final d = _coverageZoneDocs[i];
      final data = d.data();
      final raw = data['corners'];
      if (raw is! List) continue;
      final pts = <LatLng>[];
      for (final e in raw) {
        if (e is Map) {
          final la = (e['lat'] as num?)?.toDouble();
          final ln = (e['lng'] as num?)?.toDouble();
          if (la != null && ln != null) pts.add(LatLng(la, ln));
        }
      }
      if (pts.length < 3) continue;
      final kind = (data['kind'] as String?) ?? '';
      final fill = switch (kind) {
        'trauma_hub' => Colors.deepPurple.withValues(alpha: 0.38),
        'ambulance_standby' => Colors.lightBlueAccent.withValues(alpha: 0.32),
        _ => Colors.greenAccent.withValues(alpha: 0.28),
      };
      out.add(
        Polygon(
          polygonId: PolygonId('cv_${d.id}'),
          points: pts,
          strokeColor: Colors.white.withValues(alpha: 0.85),
          strokeWidth: 2,
          fillColor: fill,
          zIndex: 4,
        ),
      );
    }
    if (_zoneEditMode && _editCornerTaps.length >= 3) {
      out.add(
        Polygon(
          polygonId: const PolygonId('cv_edit_preview'),
          points: _editCornerTaps,
          strokeColor: Colors.amberAccent,
          strokeWidth: 2,
          fillColor: Colors.amber.withValues(alpha: 0.2),
          zIndex: 6,
        ),
      );
    }
    return out;
  }

  LatLng _hexCenterLatLng(IndiaOpsZone zone, HexAxial axial) {
    final verts = hexVerticesLatLng(zone.center, kZoneHexCircumRadiusM, axial);
    var la = 0.0;
    var ln = 0.0;
    for (final p in verts) {
      la += p.latitude;
      ln += p.longitude;
    }
    return LatLng(la / verts.length, ln / verts.length);
  }

  Future<void> _promptSaveCoverageKind() async {
    final corners = List<LatLng>.from(_editCornerTaps);
    final hex = _editHexAxial;
    final z = _zone;
    if (corners.length != 4 || hex == null || z == null) return;
    final kind = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate800,
        title: Text(context.opsTr('Mark zone type'), style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(context.opsTr('Hospital'), style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'hospital'),
            ),
            ListTile(
              title: Text(context.opsTr('Trauma hub'), style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'trauma_hub'),
            ),
            ListTile(
              title: Text(context.opsTr('Ambulance standby'), style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, 'ambulance_standby'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.opsTr('Cancel')),
          ),
        ],
      ),
    );
    if (!mounted || kind == null || kind.isEmpty) return;
    try {
      await OpsCoverageZoneService.saveQuad(
        zoneId: z.id,
        hexKey: hex.storageKey,
        corners: corners,
        kind: kind,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.opsTr('Coverage zone saved'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
    setState(() {
      _editCornerTaps = [];
      _editHexAxial = null;
    });
  }

  void _onCommandMapTap(LatLng p) {
    if (widget.access.role == AdminConsoleRole.master &&
        _zoneEditMode &&
        _zone != null) {
      final z = _zone!;
      final hexCoverM = _hexMeshCoverM;
      final axial = volunteerToHex(
        kZoneHexCircumRadiusM,
        z.center.latitude,
        z.center.longitude,
        p.latitude,
        p.longitude,
      );
      final dist = Geolocator.distanceBetween(
        z.center.latitude,
        z.center.longitude,
        p.latitude,
        p.longitude,
      );
      if (dist > hexCoverM + kZoneHexCircumRadiusM * 2) return;

      if (_editHexAxial == null || _editHexAxial != axial) {
        setState(() {
          _editHexAxial = axial;
          _editCornerTaps = [];
        });
        final c = _hexCenterLatLng(z, axial);
        _mapCtl?.animateCamera(CameraUpdate.newLatLngZoom(c, 15.2));
        return;
      }

      if (_editCornerTaps.length < 4) {
        setState(() => _editCornerTaps = [..._editCornerTaps, p]);
        if (_editCornerTaps.length == 4) {
          unawaited(_promptSaveCoverageKind());
        }
      }
      return;
    }
    if (_selectedFleetKey != null) {
      setState(() {
        _selectedFleetKey = null;
        if (widget.masterSidebarMode == MasterCommandSidebarMode.liveOps) {
          _liveOpsClearDetail();
        }
      });
    }
  }

  Widget _buildLiveOpsDetailBody(SosIncident? incidentSel) {
    switch (_liveOpsDetailKind) {
      case _LiveOpsDetailKind.none:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Select SOS, fleet, volunteer, or hospital from the sidebar or map.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.38),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        );
      case _LiveOpsDetailKind.incident:
        final e = incidentSel;
        if (e == null) {
          return Center(
            child: Text(context.opsTr('No incident'), style: TextStyle(color: Colors.white38)),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              e.type,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            StatusPill(status: e.status, dispatchedAccent: _accent),
            const SizedBox(height: 10),
            _liveOpsKv('ID', e.id),
            _liveOpsKv('Reporter', e.userDisplayName),
            _liveOpsKv('Status line', e.status.name),
            if ((e.adminDispatchNote ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  e.adminDispatchNote!.trim(),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        );
      case _LiveOpsDetailKind.fleetDoc:
        final id = _liveOpsFleetDocId;
        if (id == null) return const SizedBox.shrink();
        QueryDocumentSnapshot<Map<String, dynamic>>? doc;
        for (final d in _fleetDocs) {
          if (d.id == id) {
            doc = d;
            break;
          }
        }
        if (doc == null)
          return const Center(
            child: Text(
              'Unit not found',
              style: TextStyle(color: Colors.white38),
            ),
          );
        final data = doc.data();
        final callSign = (data['fleetCallSign'] as String?)?.trim() ?? doc.id;
        final type = (data['vehicleType'] as String?)?.trim() ?? '—';
        final avail = fleetUnitIsStaffedAvailable(data, doc.id);
        final inc = (data['assignedIncidentId'] as String?)?.trim() ?? '';
        final station = (data['stationedHospitalId'] as String?)?.trim() ?? '';
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        final df = DateFormat.MMMd().add_Hm();
        final updated = data['updatedAt'];
        var updatedStr = '—';
        if (updated is Timestamp) {
          updatedStr = df.format(updated.toDate().toLocal());
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              callSign,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _liveOpsKv('Type', type),
            _liveOpsKv(
              'Status',
              avail
                  ? 'Available'
                  : (isFleetUnitPlaceholderDoc(doc.id)
                      ? 'No operator signed in'
                      : 'Busy / dispatched'),
            ),
            if (inc.isNotEmpty) _liveOpsKv('Incident', inc),
            if (station.isNotEmpty) _liveOpsKv('Stationed at', station),
            if (lat != null && lng != null)
              _liveOpsKv(
                'Position',
                '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
              ),
            _liveOpsKv('Updated', updatedStr),
            const SizedBox(height: 14),
            FutureBuilder<bool>(
              key: ValueKey<String>('liveops-fleet-gate-$callSign'),
              future: FleetGateCredentialsService.gateAccountExists(callSign),
              builder: (context, snap) {
                final hasGate = snap.data ?? false;
                final label = hasGate ? 'Reset credentials' : 'Get credentials';
                return FilledButton.icon(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => FleetCredentialsDialog(
                        fleetCallSign: callSign,
                        vehicleType: type,
                      ),
                    );
                  },
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: Text(
                    snap.connectionState == ConnectionState.waiting
                        ? 'Credentials…'
                        : label,
                  ),
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                );
              },
            ),
          ],
        );
      case _LiveOpsDetailKind.hospital:
        final r = _liveOpsHospitalRow;
        if (r == null) return const SizedBox.shrink();
        final df = DateFormat.MMMd().add_Hm();
        final note = (r.traumaBedsNote ?? '').trim();
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              r.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _liveOpsKv('ID', r.id),
            _liveOpsKv('Region', r.region),
            _liveOpsKv('Beds', '${r.bedsAvailable} / ${r.bedsTotal}'),
            _liveOpsKv('Updated', df.format(r.updatedAt.toLocal())),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  note,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                final email = FirebaseAuth.instance.currentUser?.email ?? '';
                showDialog<void>(
                  context: context,
                  builder: (ctx) => HospitalOnboardingDialog(
                    hospitalDocId: r.id,
                    hospitalName: r.name,
                    hospitalVicinity: r.region,
                    adminEmail: email,
                    alreadyOnboarded: r.hasStaffCredentials,
                    onboardingLatitude: r.lat,
                    onboardingLongitude: r.lng,
                  ),
                );
              },
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: Text(
                r.hasStaffCredentials
                    ? 'Reset credentials'
                    : 'Get credentials',
              ),
              style: FilledButton.styleFrom(backgroundColor: _accent),
            ),
          ],
        );
      case _LiveOpsDetailKind.volunteer:
        final uid = _liveOpsVolunteerUserId;
        if (uid == null) return const SizedBox.shrink();
        ActiveVolunteerNearby? v;
        for (final x in OpsZoneResourceCatalog.volunteersInZone(
          _volunteerDutyDocs,
          _zone!,
        )) {
          if (x.userId == uid) {
            v = x;
            break;
          }
        }
        if (v == null) {
          return const Center(
            child: Text(
              'Volunteer not in zone list',
              style: TextStyle(color: Colors.white38),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              v.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            _liveOpsKv('User ID', v.userId),
            _liveOpsKv('Duty', OpsZoneResourceCatalog.dutyNarrative(v)),
            _liveOpsKv(
              'Position',
              '${v.lat.toStringAsFixed(5)}, ${v.lng.toStringAsFixed(5)}',
            ),
          ],
        );
      case _LiveOpsDetailKind.liveResponder:
        final key = _liveOpsLiveResponderKey;
        if (key == null) return const SizedBox.shrink();
        final parsed = _parseLiveSimKey(key);
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(context.opsTr('Simulated responder'), style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (parsed != null) ...[
              _liveOpsKv('Incident', parsed.$1),
              _liveOpsKv('Role', parsed.$2),
            ],
            const SizedBox(height: 10),
            Text(
              'Demo unit on map — tied to practice / demo incidents.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        );
    }
  }

  Widget _liveOpsKv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              k,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_zone == null) {
      // Avoid nested [Scaffold] inside parent [Expanded] — use explicit expand so layout
      // always receives bounded constraints (web / multi-site hosting).
      return ColoredBox(
        color: AppColors.slate900,
        child: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }
    final zone = _zone!;
    final user = FirebaseAuth.instance.currentUser;

    final filtered = _cachedFiltered;
    final activeSel = _pick(filtered, _selectedId);
    final sel =
        activeSel ??
        (_archiveSidebarSelection?.id == _selectedId
            ? _archiveSidebarSelection
            : null);
    final hospDir = OpsZoneResourceCatalog.hospitalsInZoneMerged(zone, _allOpsHospitals);
    final hospDirHex =
        OpsZoneResourceCatalog.hospitalsInZoneMerged(_canonicalOpsZoneForHex, _allOpsHospitals);
    final dutyVols = OpsZoneResourceCatalog.volunteersInZone(
      _volunteerDutyDocs,
      zone,
    );
    final volDutyLatLngHex = OpsZoneResourceCatalog.volunteersInZone(
      _volunteerDutyDocs,
      _canonicalOpsZoneForHex,
    ).map((v) => LatLng(v.lat, v.lng)).toList();

    if (activeSel != null && _controllerIncidentId != activeSel.id) {
      final copy = activeSel;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || _selectedId != copy.id) return;
        _syncDetailControllers(copy);
      });
    }

    final fbOrange = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueOrange,
    );
    final fbRed = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueRed,
    );
    final fbGreen = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueGreen,
    );
    final fbBlue = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueBlue,
    );
    final fleetByUid = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final d in dedupeFleetDocsByCallSign(_fleetDocs)) d.id: d,
    };

    final acc = widget.access;
    final hexCoverM = _hexMeshCoverM;
    final sceneTierForSelected = sel == null
        ? TierHealth.green
        : tierHealthAtVictimPin(
            gridCenter: _canonicalOpsZoneForHex.center,
            victimPin: sel.liveVictimPin,
            coverRadiusM: hexCoverM,
            hospitals: hospDirHex,
            volunteerPositions: volDutyLatLngHex,
          );
    const hospitalInfluenceCircles = <Circle>{};
    var hospitalDemoResponding = 0;
    var hospitalDemoStandby = 0;
    if (_hospitalScopedZone) {
      for (final d in _fleetDocs) {
        final data = d.data();
        if (!acc.isFleetDocVisible(data, d.id)) continue;
        if (data['available'] != true) continue;
        if (!DemoFleetSimulation.isDemoDoc(d.id)) continue;
        final aid = (data['assignedIncidentId'] as String?)?.trim() ?? '';
        if (aid.isNotEmpty) {
          hospitalDemoResponding++;
        } else {
          hospitalDemoStandby++;
        }
      }
    }

    final markers = <Marker>{};
    for (final e in filtered.take(80)) {
      final isSel = activeSel != null && e.id == activeSel.id;
      final pin = e.liveVictimPin;
      markers.add(
        Marker(
          markerId: MarkerId(e.id),
          position: pin,
          zIndexInt: isSel ? 4 : 2,
          icon: isSel
              ? OpsMapMarkers.sceneOr(fbRed)
              : OpsMapMarkers.incidentOr(fbOrange),
          onTap: () => _applyIncidentSelection(e, filtered),
        ),
      );
      if (acc.showMapVolunteers) {
        final vol = e.volunteerLiveLocation;
        if (vol != null) {
          markers.add(
            Marker(
              markerId: MarkerId('${e.id}_vol'),
              position: vol,
              zIndexInt: isSel ? 3 : 1,
              icon: OpsMapMarkers.volunteerDutyOr(fbGreen),
            ),
          );
        }
      }
    }

    final archOnly = _archiveSidebarSelection;
    if (archOnly != null &&
        archOnly.id == _selectedId &&
        !filtered.any((e) => e.id == archOnly.id)) {
      final pin = archOnly.liveVictimPin;
      markers.add(
        Marker(
          markerId: MarkerId('archive_pin_${archOnly.id}'),
          position: pin,
          zIndexInt: 4,
          icon: OpsMapMarkers.incidentOr(
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          ),
          infoWindow: InfoWindow(
            title: archOnly.type,
            snippet:
                'Archived · ${_archiveClosureLabel.isEmpty ? 'closed' : _archiveClosureLabel}',
          ),
          onTap: () => _onArchiveIncidentTap(archOnly, _archiveClosureLabel),
        ),
      );
    }

    void addPlaces(
      Iterable<EmergencyPlace> places,
      String layer,
      BitmapDescriptor Function(BitmapDescriptor) pick,
    ) {
      var i = 0;
      for (final p in places.take(_maxFacilityMarkers)) {
        final uid = layer == 'hospital'
            ? OpsZoneResourceCatalog.hospitalDisplayIdForMap(p, _allOpsHospitals)
            : null;
        markers.add(
          Marker(
            markerId: MarkerId('${layer}_$i'),
            position: LatLng(p.lat, p.lng),
            zIndexInt: 0,
            icon: pick(fbBlue),
            infoWindow: InfoWindow(
              title: uid != null ? '$uid · ${p.name}' : p.name,
              snippet: OpsZoneResourceCatalog.facilityNarrative(p, layer),
            ),
          ),
        );
        i++;
      }
    }

    if (_ccShowStations) {
      if (acc.showMapHospitals) {
        if (_hospitalScopedZone &&
            acc.role == AdminConsoleRole.medical &&
            _boundHospitalMarkerPos != null) {
          markers.add(
            Marker(
              markerId: const MarkerId('bound_hospital'),
              position: _boundHospitalMarkerPos!,
              zIndexInt: 2,
              icon: OpsMapMarkers.hospitalOr(fbBlue),
              infoWindow: InfoWindow(
                title: _hospitalTitleWithCode(
                  acc.boundHospitalDocId,
                  _boundHospitalMarkerName,
                ),
                snippet: 'Your facility · command zone',
              ),
            ),
          );
        } else {
          addPlaces(hospDir, 'hospital', OpsMapMarkers.hospitalOr);
        }
      }
    }

    var vi = 0;
    if (acc.showMapVolunteers) {
      for (final v in dutyVols.take(_maxFacilityMarkers)) {
        markers.add(
          Marker(
            markerId: MarkerId('duty_$vi'),
            position: LatLng(v.lat, v.lng),
            zIndexInt: 1,
            icon: OpsMapMarkers.volunteerForGender(v.gender, fbGreen),
            infoWindow: InfoWindow(
              title: v.displayName,
              snippet: OpsZoneResourceCatalog.dutyNarrative(v),
            ),
            onTap:
                acc.role == AdminConsoleRole.master &&
                    widget.masterSidebarMode == MasterCommandSidebarMode.liveOps
                ? () {
                    setState(() {
                      _selectedFleetKey = null;
                      _liveOpsDetailKind = _LiveOpsDetailKind.volunteer;
                      _liveOpsVolunteerUserId = v.userId;
                      _liveOpsFleetDocId = null;
                      _liveOpsHospitalRow = null;
                      _liveOpsLiveResponderKey = null;
                      _liveOpsDetailOpen = true;
                    });
                    unawaited(
                      _mapCtl?.animateCamera(
                        CameraUpdate.newLatLngZoom(LatLng(v.lat, v.lng), 16.85),
                      ),
                    );
                  }
                : null,
          ),
        );
        vi++;
      }
    }

    for (final e in _fleetSmoothPos.entries) {
      final k = e.key;
      if (k.startsWith('live_')) {
        if (!_ccShowActiveFleet) continue;
      } else if (k.startsWith('fleet_')) {
        final docId = k.substring(6);
        final doc = fleetByUid[docId];
        final assigned = ((doc?.data()['assignedIncidentId'] as String?) ?? '')
            .trim()
            .isNotEmpty;
        if (assigned) {
          if (!_ccShowActiveFleet) continue;
        } else {
          if (!_ccShowStandbyFleet) continue;
        }
      }
      markers.add(
        Marker(
          markerId: MarkerId('smooth_${e.key}'),
          position: e.value,
          zIndexInt: (_selectedFleetKey == e.key) ? 8 : 6,
          icon: _fleetMarkerIcon(e.key, fleetByUid),
          anchor: const Offset(0.5, 0.5),
          flat: true,
          rotation: _fleetMarkerRotation(e.key, fleetByUid),
          infoWindow: _fleetInfoWindow(e.key, fleetByUid) ?? InfoWindow.noText,
          onTap: () {
            final k = e.key;
            setState(() {
              if (_selectedFleetKey == k) {
                _selectedFleetKey = null;
                if (widget.masterSidebarMode ==
                    MasterCommandSidebarMode.liveOps) {
                  _liveOpsClearDetail();
                }
              } else {
                _selectedFleetKey = k;
                if (widget.masterSidebarMode ==
                    MasterCommandSidebarMode.liveOps) {
                  _liveOpsDetailOpen = true;
                  if (k.startsWith('fleet_')) {
                    _liveOpsDetailKind = _LiveOpsDetailKind.fleetDoc;
                    _liveOpsFleetDocId = k.substring(6);
                    _liveOpsHospitalRow = null;
                    _liveOpsVolunteerUserId = null;
                    _liveOpsLiveResponderKey = null;
                  } else if (k.startsWith('live_')) {
                    _liveOpsDetailKind = _LiveOpsDetailKind.liveResponder;
                    _liveOpsLiveResponderKey = k;
                    _liveOpsFleetDocId = null;
                    _liveOpsHospitalRow = null;
                    _liveOpsVolunteerUserId = null;
                  }
                }
              }
            });
            if (_selectedFleetKey != null &&
                widget.masterSidebarMode == MasterCommandSidebarMode.liveOps) {
              unawaited(
                _mapCtl?.animateCamera(
                  CameraUpdate.newLatLngZoom(e.value, 16.85),
                ),
              );
            }
          },
        ),
      );
    }

    final mapPolylines = <Polyline>{};
    var pathIdx = 0;
    if (acc.showMapVolunteers) {
      for (final e in filtered.take(28)) {
        final vol = e.volunteerLiveLocation;
        if (vol == null) continue;
        final pin = e.liveVictimPin;
        mapPolylines.add(
          Polyline(
            polylineId: PolylineId('vol_to_scene_${e.id}_$pathIdx'),
            points: OsrmRouteUtil.fallbackPolyline(vol, pin),
            color: AppColors.primarySafe,
            width: 5,
            zIndex: 2,
            patterns: [PatternItem.dash(12), PatternItem.gap(8)],
          ),
        );
        pathIdx++;
      }
    }

    final scenes = _demoOpsVictimPins();
    for (final e in _fleetSmoothPos.entries) {
      final k = e.key;
      List<LatLng>? route;
      Color routeColor = Colors.lightBlueAccent;

      if (k.startsWith('live_')) {
        if (!_ccShowActiveFleet) continue;
        final parsed = _parseLiveSimKey(k);
        if (parsed != null) {
          final inc = filtered.where((f) => f.id == parsed.$1).firstOrNull;
          if (inc != null) {
            route = DemoFleetRouteCache.loopResponder(
              inc.id,
              parsed.$2,
              inc.liveVictimPin,
              zone,
            );
          }
        }
      } else if (k.startsWith('fleet_')) {
        final docId = k.substring(6);
        final doc = fleetByUid[docId];
        final data = doc?.data();
        final aid = (data?['assignedIncidentId'] as String?)?.trim() ?? '';
        if (aid.isNotEmpty) {
          if (!_ccShowActiveFleet) continue;
          final pin = scenes[aid];
          final endPoints = DemoFleetRouting.fleetEndpoints(
            docId,
            zone,
            aid,
            pin,
            scenes,
          );
          final cacheKey = DemoFleetRouting.fleetCacheKey(
            docId,
            zone,
            endPoints.$1,
            endPoints.$2,
          );
          route = DemoFleetRouteCache.loopForKey(cacheKey);
        }
      }

      if (route != null &&
          route.isNotEmpty &&
          !DemoFleetRouteCache.isFallbackLine(route)) {
        final isSelected = _selectedFleetKey == k;
        final isDimmed = _selectedFleetKey != null && !isSelected;

        mapPolylines.add(
          Polyline(
            polylineId: PolylineId('route_${k}_$pathIdx'),
            points: route,
            color: isDimmed
                ? routeColor.withValues(alpha: 0.15)
                : routeColor.withValues(alpha: 0.85),
            width: isSelected ? 8 : (isDimmed ? 3 : 5),
            zIndex: isSelected ? 4 : 1,
            patterns: isSelected
                ? []
                : [PatternItem.dash(16), PatternItem.gap(10)],
          ),
        );
        pathIdx++;
      }
    }

    if (activeSel != null &&
        sel != null &&
        activeSel.id == sel.id &&
        _selectedHospitalRoute.length >= 2 &&
        _selectedId == sel.id) {
      mapPolylines.add(
        Polyline(
          polylineId: const PolylineId('hospital_to_scene_selected'),
          points: _selectedHospitalRoute,
          color: Colors.redAccent,
          width: 6,
          zIndex: 7,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }

    final hexModel =
        _cachedHexModel ??
        buildEmergencyHexZones(
          center: _canonicalOpsZoneForHex.center,
          coverRadiusM: hexCoverM,
          hospitals: hospDirHex,
          volunteerPositions: volDutyLatLngHex,
          useMainAppHospitalDensityColors: true,
        );

    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        if (_hospitalScopedZone && acc.role == AdminConsoleRole.medical)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Material(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.local_hospital_rounded,
                      color: _accent,
                      size: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hospitalTitleWithCode(
                              acc.boundHospitalDocId,
                              _boundHospitalMarkerName,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          if ((_boundHospitalRegion ?? '').isNotEmpty)
                            Text(
                              _boundHospitalRegion!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 12,
                              ),
                            ),
                          if (_boundHospitalBedsAvail != null &&
                              _boundHospitalBedsTotal != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Beds: ${_boundHospitalBedsAvail!} available · ${_boundHospitalBedsTotal!} total capacity',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (_boundHospitalServices.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: _boundHospitalServices
                                  .map(
                                    (s) => Chip(
                                      label: Text(
                                        s.length > 14
                                            ? '${s.substring(0, 12)}…'
                                            : s,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                      backgroundColor: _accent.withValues(
                                        alpha: 0.22,
                                      ),
                                      padding: EdgeInsets.zero,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Fleet in view',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$hospitalDemoResponding responding',
                          style: const TextStyle(
                            color: Color(0xFF7EE787),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '$hospitalDemoStandby standby',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.65),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (acc.role == AdminConsoleRole.medical &&
            (acc.boundHospitalDocId ?? '').trim().isNotEmpty)
          HospitalOverviewCapacitySection(
            hospitalDocId: acc.boundHospitalDocId!.trim(),
          ),
        OpsTopBar(
          accent: _accent,
          userEmail: user?.email ?? 'Signed out',
          child: _commandCenterFilterBar(zone, filtered.length),
        ),
        Expanded(
          child: Row(
            children: [
              if (acc.role != AdminConsoleRole.master ||
                  widget.masterSidebarMode ==
                      MasterCommandSidebarMode.none) ...[
                SizedBox(
                  width: 340,
                  child: CommandCenterSidebar(
                    access: acc,
                    tabController: _legacySidebarTabs!,
                    filteredIncidents: filtered,
                    accent: _accent,
                    selectedId: _selectedId,
                    zone: _zone,
                    priorityLabelFor: _priorityLabelFor,
                    hospitalLocation: acc.role == AdminConsoleRole.medical
                        ? _boundHospitalMarkerPos
                        : null,
                    onIncidentTap: (e) => _applyIncidentSelection(e, filtered),
                    onArchiveIncidentTap: _onArchiveIncidentTap,
                  ),
                ),
                const VerticalDivider(width: 1, color: Colors.white12),
              ] else if (widget.masterSidebarMode ==
                  MasterCommandSidebarMode.liveOps) ...[
                SizedBox(
                  width: 340,
                  child: MasterLiveOpsSidebar(
                    access: acc,
                    accent: _accent,
                    zone: _zone,
                    dutyVols: dutyVols,
                    fleetDocs: dedupeFleetDocsByCallSign(_fleetDocs),
                    onPlaceTap: _focusOnMap,
                    filteredIncidents: filtered,
                    selectedId: _selectedId,
                    onIncidentTap: (e) => _applyIncidentSelection(e, filtered),
                    onArchiveIncidentTap: _onArchiveIncidentTap,
                    priorityLabelFor: _priorityLabelFor,
                    onFleetRowSelected: (docId, pos) {
                      setState(() {
                        _liveOpsDetailKind = _LiveOpsDetailKind.fleetDoc;
                        _liveOpsFleetDocId = docId;
                        _liveOpsHospitalRow = null;
                        _liveOpsVolunteerUserId = null;
                        _liveOpsLiveResponderKey = null;
                        _selectedFleetKey = 'fleet_$docId';
                        _liveOpsDetailOpen = true;
                      });
                      _focusOnMap(pos, zoom: 16.85);
                    },
                    onVolunteerRowSelected: (v) {
                      setState(() {
                        _liveOpsDetailKind = _LiveOpsDetailKind.volunteer;
                        _liveOpsVolunteerUserId = v.userId;
                        _liveOpsFleetDocId = null;
                        _liveOpsHospitalRow = null;
                        _liveOpsLiveResponderKey = null;
                        _selectedFleetKey = null;
                        _liveOpsDetailOpen = true;
                      });
                      _focusOnMap(LatLng(v.lat, v.lng), zoom: 16.85);
                    },
                    onHospitalRowSelected: (r) {
                      setState(() {
                        _liveOpsDetailKind = _LiveOpsDetailKind.hospital;
                        _liveOpsHospitalRow = r;
                        _liveOpsFleetDocId = null;
                        _liveOpsVolunteerUserId = null;
                        _liveOpsLiveResponderKey = null;
                        _selectedFleetKey = null;
                        _liveOpsDetailOpen = true;
                      });
                      final lat = r.lat;
                      final lng = r.lng;
                      if (lat != null && lng != null) {
                        _focusOnMap(LatLng(lat, lng), zoom: 16.85);
                      }
                    },
                  ),
                ),
                const VerticalDivider(width: 1, color: Colors.white12),
              ],
              Expanded(
                flex: 3,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CommandCenterMap(
                              zone: zone,
                              markers: markers,
                              polylines: mapPolylines,
                              polygons: {
                                if (_ccShowHexGrid) ...hexModel.polygons,
                                ..._coverageZonePolygons(),
                              },
                              showHexGrid: _ccShowHexGrid,
                              hexCoverRadiusM: hexCoverM,
                              hexCoverageCenter: _hospitalScopedZone
                                  ? _canonicalOpsZoneForHex.center
                                  : null,
                              overlayCircles: {...hospitalInfluenceCircles},
                              initialPosition:
                                  sel?.liveVictimPin ?? zone.center,
                              initialZoom: sel != null ? 13 : zone.defaultZoom,
                              // Detail panel is beside the map in a [Row], not overlaid.
                              padding: EdgeInsets.zero,
                              onCameraMove: (p) {
                                if (!context.mounted) return;
                                if (FleetMapIcons.zoomTierChanged(
                                  _commandMapZoom,
                                  p.zoom,
                                )) {
                                  setState(() => _commandMapZoom = p.zoom);
                                }
                              },
                              onMapCreated: (c) {
                                _mapCtl = c;
                                if (sel == null) {
                                  _frameMap(null, filtered);
                                  return;
                                }
                                if (activeSel == null) {
                                  _mapCtl?.animateCamera(
                                    CameraUpdate.newLatLngZoom(
                                      sel.liveVictimPin,
                                      13,
                                    ),
                                  );
                                  return;
                                }
                                final origin = _hospitalOriginForScene(
                                  sel.liveVictimPin,
                                  zone,
                                );
                                _frameHospitalAndScene(
                                  origin,
                                  sel.liveVictimPin,
                                );
                                _prefetchHospitalRoute(sel, zone, origin);
                              },
                              onTap: _onCommandMapTap,
                            ),
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            width: 212,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.58),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Map layers',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    CheckboxTheme(
                                      data: CheckboxThemeData(
                                        visualDensity: VisualDensity.compact,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        side: const BorderSide(
                                          color: Colors.white38,
                                        ),
                                        fillColor:
                                            WidgetStateProperty.resolveWith((
                                              s,
                                            ) {
                                              if (s.contains(
                                                WidgetState.selected,
                                              )) {
                                                return _accent.withValues(
                                                  alpha: 0.85,
                                                );
                                              }
                                              return Colors.transparent;
                                            }),
                                      ),
                                      child: Column(
                                        children: [
                                          CheckboxListTile(
                                            value: _ccShowHexGrid,
                                            onChanged: (v) => setState(
                                              () => _ccShowHexGrid = v ?? true,
                                            ),
                                            title: Text(context.opsTr('Coverage grid'), style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                              ),
                                            ),
                                            subtitle: Text(context.opsTr('Green / yellow / red by facilities'), style: TextStyle(
                                                color: Colors.white38,
                                                fontSize: 9,
                                              ),
                                            ),
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            contentPadding: EdgeInsets.zero,
                                            dense: true,
                                          ),
                                          CheckboxListTile(
                                            value: _ccShowActiveFleet,
                                            onChanged: (v) => setState(
                                              () => _ccShowActiveFleet =
                                                  v ?? true,
                                            ),
                                            title: Text(context.opsTr('Active fleet'), style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                              ),
                                            ),
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            contentPadding: EdgeInsets.zero,
                                            dense: true,
                                          ),
                                          CheckboxListTile(
                                            value: _ccShowStandbyFleet,
                                            onChanged: (v) => setState(
                                              () => _ccShowStandbyFleet =
                                                  v ?? true,
                                            ),
                                            title: Text(context.opsTr('Standby fleet'), style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                              ),
                                            ),
                                            subtitle: Text(context.opsTr('Available, unassigned'), style: TextStyle(
                                                color: Colors.white38,
                                                fontSize: 9,
                                              ),
                                            ),
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            contentPadding: EdgeInsets.zero,
                                            dense: true,
                                          ),
                                          CheckboxListTile(
                                            value: _ccShowStations,
                                            onChanged: (v) => setState(
                                              () => _ccShowStations = v ?? true,
                                            ),
                                            title: Text(context.opsTr('Stations'), style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 11,
                                              ),
                                            ),
                                            subtitle: Text(
                                              acc.showMapHospitals
                                                  ? 'Directory pins for your role'
                                                  : 'No station layers for this role',
                                              style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 9,
                                              ),
                                            ),
                                            controlAffinity:
                                                ListTileControlAffinity.leading,
                                            contentPadding: EdgeInsets.zero,
                                            dense: true,
                                          ),
                                          if (acc.role ==
                                              AdminConsoleRole.master) ...[
                                            const Divider(
                                              height: 14,
                                              color: Colors.white24,
                                            ),
                                            CheckboxListTile(
                                              value: _zoneEditMode,
                                              onChanged: (v) => setState(() {
                                                _zoneEditMode = v ?? false;
                                                if (!_zoneEditMode) {
                                                  _editHexAxial = null;
                                                  _editCornerTaps = [];
                                                }
                                              }),
                                              title: Text(context.opsTr('Zone editor'), style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              subtitle: Text(context.opsTr('Tap a hex to zoom, then 4 map taps for corners'), style: TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 9,
                                                ),
                                              ),
                                              controlAffinity:
                                                  ListTileControlAffinity
                                                      .leading,
                                              contentPadding: EdgeInsets.zero,
                                              dense: true,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (_hospitalScopedZone) ...[
                                      const Divider(
                                        height: 14,
                                        color: Colors.white24,
                                      ),
                                      Text(
                                        'Fleet in view',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.85,
                                          ),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Responding: $hospitalDemoResponding · Standby: $hospitalDemoStandby',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.65,
                                          ),
                                          fontSize: 10,
                                          height: 1.25,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (activeSel != null &&
                                    sel != null &&
                                    activeSel.id == sel.id &&
                                    (_selectedHospitalRouteLoading ||
                                        _selectedHospitalRouteEtaMin != null ||
                                        _selectedHospitalRoute.length >= 2))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Material(
                                      color: Colors.black.withValues(
                                        alpha: 0.65,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        child: Text(
                                          _selectedHospitalRouteLoading
                                              ? 'Computing hospital route…'
                                              : (_selectedHospitalRouteEtaMin !=
                                                        null
                                                    ? 'Est. response ~$_selectedHospitalRouteEtaMin min (avg drive)'
                                                    : 'Hospital route on map (red)'),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Material(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      _ccShowHexGrid
                                          ? 'Hex grid · ${hexModel.totalCells} cells · ${hexModel.coveragePercent.toStringAsFixed(0)}% green · ${(hexCoverM / 1000).round()} km coverage'
                                          : 'Coverage grid off — toggle “Coverage grid” to show green / yellow / red cells',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.masterSidebarMode ==
                        MasterCommandSidebarMode.liveOps)
                      OpsCollapsibleDetailPanel(
                        expanded: _liveOpsDetailOpen,
                        onToggleExpanded: () => setState(
                          () => _liveOpsDetailOpen = !_liveOpsDetailOpen,
                        ),
                        accent: _accent,
                        body: _buildLiveOpsDetailBody(sel),
                      ),
                  ],
                ),
              ),
              if (acc.role == AdminConsoleRole.medical &&
                  activeSel != null) ...[
                const VerticalDivider(width: 1, color: Colors.white12),
                SizedBox(
                  width: 420,
                  child: _medicalDockedConsignmentPanel(
                    sel: activeSel,
                    zone: zone,
                    sceneIncidentTier: sceneTierForSelected,
                    hexModel: hexModel,
                  ),
                ),
              ] else if (acc.role == AdminConsoleRole.master &&
                  widget.masterSidebarMode == MasterCommandSidebarMode.none &&
                  activeSel != null) ...[
                const VerticalDivider(width: 1, color: Colors.white12),
                SizedBox(
                  width: 420,
                  child: _dockedIncidentCommandPanel(
                    sel: activeSel,
                    zone: zone,
                    sceneIncidentTier: sceneTierForSelected,
                    hexModel: hexModel,
                    headerTitle: 'Active alert command',
                    clearSelectionTooltip: 'Clear alert selection',
                    boundHospitalDocId: null,
                    showMasterHospitalControls: true,
                  ),
                ),
              ] else if (acc.role == AdminConsoleRole.medical &&
                  sel != null &&
                  activeSel == null) ...[
                const VerticalDivider(width: 1, color: Colors.white12),
                SizedBox(
                  width: 420,
                  child: _medicalArchivedRecordPanel(
                    sel: sel,
                    closureLabel: _archiveClosureLabel,
                    hexModel: hexModel,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      ),
    );
  }
}

enum TimeWin { h1, h24, d7, all }
