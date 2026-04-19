// Many fields and helpers below are reserved for upcoming map layers
// (AQI / outbreak / mock hotspot drills). Suppressed until wired into the UI.
// ignore_for_file: unused_field, unused_element, unused_element_parameter

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:emergency_os/core/maps/eos_hybrid_map.dart';
import 'package:emergency_os/core/maps/ops_map_controller.dart';
import 'package:http/http.dart' as http;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emergency_os/services/demo_fleet_route_cache.dart';
import 'package:emergency_os/services/demo_fleet_routing.dart';
import 'package:emergency_os/services/demo_fleet_simulation.dart';
import 'package:emergency_os/services/fleet_unit_service.dart';
import 'package:emergency_os/services/volunteer_presence_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:emergency_os/services/ops_hospital_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:emergency_os/core/l10n/app_localizations.dart';
import 'package:emergency_os/core/theme/app_colors.dart';
import 'package:emergency_os/core/utils/map_marker_generator.dart';
import 'package:emergency_os/core/utils/ops_map_markers.dart';
import 'package:emergency_os/features/hazards/data/hazard_repository.dart';
import 'package:emergency_os/features/hazards/domain/hazard_model.dart';
import 'package:emergency_os/core/constants/app_constants.dart';
import 'package:emergency_os/core/constants/google_maps_illustrative_light_style.dart';
import 'package:emergency_os/core/config/build_config.dart';
import 'package:emergency_os/core/constants/india_ops_zones.dart';
import 'package:emergency_os/services/ops_zone_resource_catalog.dart';
import 'package:emergency_os/services/places_service.dart';
import 'package:emergency_os/services/bed_availability_service.dart';
import 'package:emergency_os/services/connectivity_service.dart';
import 'package:emergency_os/services/offline_cache_service.dart';
import 'package:emergency_os/services/drill_map_demo_incidents.dart';
import 'package:emergency_os/services/incident_service.dart';
import 'package:emergency_os/services/offline_map_pack_service.dart';
import 'package:emergency_os/core/utils/map_platform.dart';
import 'package:emergency_os/features/map/domain/emergency_zone_classification.dart';
import 'widgets/offline_emergency_directory.dart';
import 'package:emergency_os/services/emergency_services_data.dart';
import 'package:emergency_os/services/environmental_data_service.dart';
import 'package:emergency_os/services/regional_health_alerts_service.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, this.isDrillShell = false});

  /// Practice Grid under `/drill/map` — demo SOS pins, no live Firestore incidents.
  final bool isDrillShell;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with TickerProviderStateMixin {
  static const TextStyle _mapFilterCheckboxTitleStyle = TextStyle(
    color: Color(0xFFFFF176),
    fontSize: 11,
    fontWeight: FontWeight.w700,
  );

  final Completer<OpsMapController> _controller = Completer<OpsMapController>();
  Position? _currentPosition;
  LatLng? _prevUserForCourse;
  double _userCourseDeg = 0;
  double _emergencyRadius = 15000;

  static bool _scanCompleted = false;
  bool _isScanning = true;

  BitmapDescriptor? _hospitalIcon;
  BitmapDescriptor? _userIcon;
  List<EmergencyPlace> _hospitals = [];

  /// Layer toggles for the map. Emergency services = hospital directory.
  bool _mapShowEmergencyServices = true;
  /// Only the nearest facility per type (within grid radius).
  final bool _mapNearestOnly = false;
  /// Live SOS pins + past incidents in the area (chip: "Live SOS").
  bool _mapShowPastIncidents = true;
  /// Hex response zones (annulus tiers to 30 km) from grid radius + service counts.
  bool _mapShowZoneClassification = false;
  /// Other on-duty volunteers with fresh locations inside the grid radius.
  bool _mapShowVolunteers = true;
  bool _zonePanelExpanded = true;
  /// Main map: past incident pins for the current hex only (toggled via Zone Info).
  bool _showPastIncidentsForZone = false;

  /// New emergency service layers
  bool _mapShowPharmacies = false;
  bool _mapShowCoolingCenters = false;
  bool _mapShowBloodBanks = false;
  final bool _mapShowOutbreaks = false;
  final bool _mapShowAQI = false;

  /// New service data
  List<PharmacyPlace> _pharmacies = [];
  List<CoolingCenter> _coolingCenters = [];
  List<BloodBankInfo> _bloodBanks = [];
  List<DiseaseOutbreak> _outbreaks = [];
  AQIInfo? _aqiInfo;
  String _pharmacyMedicineFilter = '';

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _volunteerDutySub;
  StreamSubscription<List<OpsHospitalRow>>? _opsHospitalsSub;
  List<OpsHospitalRow> _opsHospitalRows = [];
  int? _cachedPackRadiusM;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _fleetDemoSub;
  StreamSubscription<NetworkQuality>? _networkQualitySub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _volunteerDutyDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _fleetDemoDocs = [];
  Timer? _demoFleetMotionTimer;
  List<LatLng> _hospitalRoute = [];

  /// Responder → victim road paths (green on map), keyed by incident id.
  final Map<String, List<LatLng>> _volunteerResponderPolylines = {};
  String _lastVolunteerRouteRequestSig = '';
  String _lastDemoFleetResponderSig = '';
  String _lastFleetDemoRouteSig = '';

  BitmapDescriptor? _cardiacIcon;
  BitmapDescriptor? _accidentIcon;
  BitmapDescriptor? _fireHazardIcon;
  BitmapDescriptor? _chokingIcon;
  BitmapDescriptor? _bleedingIcon;

  BitmapDescriptor? _collisionEmoji;
  BitmapDescriptor? _pedestrianEmoji;
  BitmapDescriptor? _rolloverEmoji;

  BitmapDescriptor? _incidentCardiacMarker;
  BitmapDescriptor? _incidentCollisionMarker;
  BitmapDescriptor? _incidentBleedingMarker;
  BitmapDescriptor? _incidentFireMarker;
  BitmapDescriptor? _incidentDrowningMarker;
  BitmapDescriptor? _incidentStrokeMarker;
  BitmapDescriptor? _incidentChokingMarker;
  BitmapDescriptor? _incidentDefaultMarker;
  BitmapDescriptor? _volunteerDutyIcon;
  BitmapDescriptor? _volunteerMaleIcon;
  BitmapDescriptor? _volunteerFemaleIcon;
  BitmapDescriptor? _pharmacyIcon;
  BitmapDescriptor? _coolingCenterIcon;
  BitmapDescriptor? _bloodBankIcon;
  BitmapDescriptor? _outbreakIcon;

  late AnimationController _rotationController;
  late AnimationController _pulseController;

  CameraPosition _initialPosition = IndiaOpsZones.lucknowCameraPosition(zoom: 14.0);

  /// Bottom inset reserved above system nav (filters moved to the right).
  static const double _mapChipBarBottomInset = 24;
  /// No full-width bottom bar; used only for Nearest FAB offset math.
  static const double _mapChipBarHeightEstimate = 0;
  /// Gap between chip bar top and nearest-service legend.
  static const double _mapLegendGapAboveChipBar = 10;

  DateTime _lastMapUiPaint = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _mapUiMinInterval = const Duration(milliseconds: 180);
  bool? _lastSuppressMarkerMotion;

  List<SosIncident> _pastIncidents = [];
  AreaIntelligence _areaIntel = AreaIntelligence.empty();
  bool _loadingPastIncidents = false;
  final bool _showHeatmaps = true;
  /// Demo: random heat blobs near you (Hotspot button).
  bool _mockHotspotsOn = false;
  final List<LatLng> _mockHotspotCenters = [];
  final List<double> _mockHotspotRadii = [];
  final math.Random _mockHotspotRng = math.Random();

  /// Offline map pack prefetch (places + incidents + OSRM routes).
  double _offlinePackProgress = 0;
  bool _offlinePackJobRunning = false;
  bool _offlinePackComplete = false;

  bool _offlineHydrateRequested = false;


  /// Countdown tick for periodic eviction of fallback straight-line routes.
  int _evictCountdown = 0;

  /// Nearest-service legend (bottom-right); chip bar leaves horizontal space when visible.
  bool _routeLegendVisible() {
    if (_isScanning) return false;
    if (_mapShowZoneClassification) return true;
    if (_currentPosition == null) return false;
    final pastLegend = widget.isDrillShell
        ? (_mapShowPastIncidents && _pastIncidents.isNotEmpty)
        : (_showPastIncidentsForZone && _pastIncidentsInUserHex().isNotEmpty);
    return (_mapShowEmergencyServices &&
            (_hospitals.isNotEmpty ||
                _opsHospitalRows.any((r) => r.lat != null && r.lng != null))) ||
        pastLegend ||
        (widget.isDrillShell && _mapShowVolunteers && _nearbyOnDutyVolunteers().isNotEmpty);
  }

  bool _placeWithinGrid(EmergencyPlace p) {
    final pos = _currentPosition;
    if (pos == null) return false;
    return Geolocator.distanceBetween(pos.latitude, pos.longitude, p.lat, p.lng) <= _emergencyRadius;
  }

  /// Hospitals within the grid ring, or only the nearest when [_mapNearestOnly].
  /// If no hospital falls inside the ring, shows the globally nearest pin so the
  /// layer is not empty when directory data exists.
  List<EmergencyPlace> _hospitalsForMapMarkers() {
    if (_hospitals.isEmpty || _currentPosition == null) return [];
    final inGrid = _hospitals.where(_placeWithinGrid).toList();
    if (inGrid.isNotEmpty) {
      if (!_mapNearestOnly) return inGrid;
      return [_nearestPlace(inGrid)];
    }
    if (!_mapNearestOnly) return [];
    return [_nearestPlace(_hospitals)];
  }

  /// Same fixed ops anchor as [AdminCommandCenterScreen._rebuildHexGrid].
  IndiaOpsZone get _activeOpsZone => IndiaOpsZones.byId(BuildConfig.opsZoneId);

  double _hexGridCoverRadiusM(IndiaOpsZone z) =>
      math.min(z.radiusM, kCommandCenterHexCoverRadiusM);

  List<EmergencyPlace> _hospitalsForHexModel(IndiaOpsZone zone) {
    final fromCatalog = OpsZoneResourceCatalog.hospitalsInZoneMerged(
      zone,
      widget.isDrillShell ? const [] : _opsHospitalRows,
    );
    if (fromCatalog.isNotEmpty) return fromCatalog;
    final c = zone.center;
    final maxR = zone.radiusM + kMaxCoverageRadiusM;
    return _hospitals.where((p) {
      final m = Geolocator.distanceBetween(c.latitude, c.longitude, p.lat, p.lng);
      return m <= maxR;
    }).toList();
  }

  EmergencyHexZoneModel? _computeHexZoneModel() {
    final zone = _activeOpsZone;
    final coverM = _hexGridCoverRadiusM(zone);
    final volPts = OpsZoneResourceCatalog.volunteersInZone(_volunteerDutyDocs, zone)
        .map((v) => LatLng(v.lat, v.lng))
        .toList();
    return buildEmergencyHexZones(
      center: zone.center,
      coverRadiusM: coverM,
      hospitals: _hospitalsForHexModel(zone),
      volunteerPositions: volPts,
      useMainAppHospitalDensityColors: true,
    );
  }

  List<ActiveVolunteerNearby> _nearbyOnDutyVolunteers() {
    if (_currentPosition == null) return [];
    final c = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    return VolunteerPresenceService.filterNearby(
      _volunteerDutyDocs,
      c,
      _emergencyRadius,
      excludeUid: FirebaseAuth.instance.currentUser?.uid,
    );
  }

  @override
  void initState() {
    super.initState();
    ConnectivityService().start();
    _rotationController = AnimationController(vsync: this, duration: const Duration(seconds: 10));
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseController.addListener(_scheduleMapUiRepaint);

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMapAnimationMode());

    _volunteerDutySub = VolunteerPresenceService.watchOnDutyUsers().listen((snap) {
      if (!context.mounted) return;
      setState(() => _volunteerDutyDocs = snap.docs);
    });

    _networkQualitySub = ConnectivityService().qualityStream.listen((_) {
      if (!context.mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncMapAnimationMode());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Restore last known location for the initial camera position
      final lastLoc = await OfflineMapPackService.loadLastLocation();
      if (lastLoc != null && context.mounted) {
        setState(() {
          _initialPosition = IndiaOpsZones.lucknowSafeCamera(lastLoc, preferZoom: 11.5);
        });
      }
      final ready = await OfflineMapPackService.isReady();
      final r = await OfflineMapPackService.loadRoutePolylines();
      if (!context.mounted) return;
      setState(() {
        _offlinePackComplete = ready;
        if (r.hospital.length > 1) _hospitalRoute = r.hospital;
      });
    });

    _loadCustomMarkers();
    if (_scanCompleted) {
      _isScanning = false;
      _determinePosition();
    } else {
      _startScanSequence();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEmergencyServicesData());
    if (!widget.isDrillShell) {
      _mapShowPastIncidents = false;
      _mapShowVolunteers = false;
      _opsHospitalsSub = OpsHospitalService.watchHospitals().listen((rows) {
        if (!context.mounted) return;
        setState(() => _opsHospitalRows = rows);
      });
      unawaited(OfflineMapPackService.loadLastPackRadiusMeters().then((r) {
        if (!context.mounted || r == null) return;
        setState(() => _cachedPackRadiusM = r);
      }));
    }
    // Demo fleet / seeded `demo_ops_*` playback: practice map only — main map is real incidents only.
    if (widget.isDrillShell) {
      _fleetDemoSub = FleetUnitService.watchFleetUnits().listen((snap) {
        if (!context.mounted) return;
        final demo = snap.docs.where((d) => DemoFleetSimulation.isDemoDoc(d.id)).toList();
        setState(() => _fleetDemoDocs = demo);
      });
      // Synchronized with Admin Command Center for 30 FPS fleet simulation (~33ms)
      _demoFleetMotionTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (!context.mounted || _fleetDemoDocs.isEmpty) return;
        // Every ~90 seconds evict cached fallback straight lines so OSRM routes
        // are retried once the rate limit window has passed.
        _evictCountdown++;
        if (_evictCountdown >= 2727) { // 2727 * 33ms ≈ 90s
          _evictCountdown = 0;
          DemoFleetRouteCache.evictFallbacks();
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _opsHospitalsSub?.cancel();
    _fleetDemoSub?.cancel();
    _demoFleetMotionTimer?.cancel();
    _networkQualitySub?.cancel();
    _volunteerDutySub?.cancel();
    _rotationController.dispose();
    _pulseController.removeListener(_scheduleMapUiRepaint);
    _pulseController.dispose();
    super.dispose();
  }

  void _bumpUserCourseFrom(Position p) {
    final prev = _prevUserForCourse;
    final h = p.heading;
    if (h >= 0 &&
        h <= 360 &&
        (p.speed > 0.4 || (p.headingAccuracy >= 0 && p.headingAccuracy < 55))) {
      _userCourseDeg = h;
    } else if (prev != null) {
      final d = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        p.latitude,
        p.longitude,
      );
      if (d >= 6) {
        _userCourseDeg = Geolocator.bearingBetween(
          prev.latitude,
          prev.longitude,
          p.latitude,
          p.longitude,
        );
      }
    }
    _prevUserForCourse = LatLng(p.latitude, p.longitude);
  }

  Future<void> _loadCustomMarkers() async {
    await OpsMapMarkers.preload();
    const subtleHospital = Color(0xFF26C6DA);
    _hospitalIcon = await MapMarkerGenerator.getMinimalPin(Icons.local_hospital_rounded, subtleHospital);
    _userIcon = await MapMarkerGenerator.getMinimalPin(Icons.navigation_rounded, AppColors.primaryInfo);
    _volunteerMaleIcon = await MapMarkerGenerator.getMinimalPin(Icons.man_rounded, AppColors.primarySafe);
    _volunteerFemaleIcon = await MapMarkerGenerator.getMinimalPin(Icons.woman_rounded, const Color(0xFFE91E63));
    _volunteerDutyIcon = await MapMarkerGenerator.getMinimalPin(Icons.groups_rounded, AppColors.primarySafe);
    _cardiacIcon = await MapMarkerGenerator.getMinimalPin(HazardType.cardiacArrest.icon, HazardType.cardiacArrest.color);
    _accidentIcon = await MapMarkerGenerator.getMinimalPin(HazardType.accident.icon, HazardType.accident.color);
    _fireHazardIcon = await MapMarkerGenerator.getMinimalPin(HazardType.fire.icon, HazardType.fire.color);
    _chokingIcon = await MapMarkerGenerator.getMinimalPin(HazardType.choking.icon, HazardType.choking.color);
    _bleedingIcon = await MapMarkerGenerator.getMinimalPin(HazardType.bleeding.icon, HazardType.bleeding.color);

    _collisionEmoji = await MapMarkerGenerator.getMinimalPin(Icons.car_crash_rounded, AppColors.primaryDanger);
    _pedestrianEmoji = await MapMarkerGenerator.getMinimalPin(Icons.directions_run_rounded, AppColors.primaryWarning);
    _rolloverEmoji = await MapMarkerGenerator.getMinimalPin(Icons.car_repair_rounded, AppColors.primaryDanger);

    _incidentCardiacMarker = await MapMarkerGenerator.getMinimalPin(Icons.favorite_rounded, AppColors.primaryDanger);
    _incidentCollisionMarker = await MapMarkerGenerator.getMinimalPin(Icons.car_crash_rounded, AppColors.primaryWarning);
    _incidentBleedingMarker = await MapMarkerGenerator.getMinimalPin(Icons.bloodtype_rounded, AppColors.primaryDanger);
    _incidentFireMarker = await MapMarkerGenerator.getMinimalPin(Icons.local_fire_department_rounded, AppColors.primaryWarning);
    _incidentDrowningMarker = await MapMarkerGenerator.getMinimalPin(Icons.pool_rounded, AppColors.primaryInfo);
    _incidentStrokeMarker = await MapMarkerGenerator.getMinimalPin(Icons.psychology_rounded, const Color(0xFF9575CD));
    _incidentChokingMarker = await MapMarkerGenerator.getMinimalPin(Icons.air_rounded, const Color(0xFF26C6DA));
    _incidentDefaultMarker = await MapMarkerGenerator.getMinimalPin(Icons.emergency_rounded, AppColors.primaryDanger);

    _pharmacyIcon = await MapMarkerGenerator.getMinimalPin(Icons.local_pharmacy_rounded, const Color(0xFF26A69A));
    _coolingCenterIcon = await MapMarkerGenerator.getMinimalPin(Icons.ac_unit_rounded, const Color(0xFF42A5F5));
    _bloodBankIcon = await MapMarkerGenerator.getMinimalPin(Icons.bloodtype_rounded, const Color(0xFFE53935));
    _outbreakIcon = await MapMarkerGenerator.getMinimalPin(Icons.warning_rounded, const Color(0xFFFF9800));

    if (context.mounted) setState(() {});
  }

  Future<void> _startScanSequence() async {
    await _determinePosition();
    if (context.mounted) {
      setState(() => _isScanning = false);
      _scanCompleted = true;
    }
  }

  Future<void> _determinePosition({bool forcePlacesRefresh = false}) async {
    try {
      if (forcePlacesRefresh && context.mounted) {
        setState(() {
          _offlinePackComplete = false;
          _offlinePackProgress = 0;
        });
      }
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition();
      if (context.mounted) {
        setState(() {
          _bumpUserCourseFrom(position);
          _currentPosition = position;
        });
        unawaited(_loadEmergencyServicesData());
      }

      if (!widget.isDrillShell) {
        final user = FirebaseAuth.instance.currentUser;
        final uid = user?.uid;
        if (uid != null && uid.isNotEmpty) {
          try {
            await FirebaseFirestore.instance.collection('volunteers').doc(uid).set(
              {
                'lat': position.latitude,
                'lng': position.longitude,
                'updatedAt': DateTime.now().toIso8601String(),
                'isAvailable': true,
              },
              SetOptions(merge: true),
            );
          } catch (_) {}
        }
      }

      final OpsMapController controller = await _controller.future;
      final cam = IndiaOpsZones.lucknowSafeCamera(
        LatLng(position.latitude, position.longitude),
        preferZoom: 11.5,
      );
      await controller.animateCamera(CameraUpdate.newCameraPosition(cam));
      
      if (context.mounted) {
        setState(() {
          _offlinePackJobRunning = true;
          _offlinePackProgress = 0.06;
        });
      }

      // Persist user location for offline map restoration
      unawaited(OfflineMapPackService.saveLastLocation(position.latitude, position.longitude));

      final deferPlaces = ConnectivityService().shouldDeferExpensiveNetworkWork;
      final placesForceRefresh = forcePlacesRefresh || !deferPlaces;

      PlacesService.getNearby(
              lat: position.latitude, lng: position.longitude, type: 'hospital', forceRefresh: placesForceRefresh)
          .then((r) {
        _bumpOfflinePack(0.15);
        return r;
      }).then((results) {
        if (context.mounted) {
          setState(() {
            _hospitals = results;
            _offlinePackProgress = math.max(_offlinePackProgress, 0.52);
          });
          unawaited(OfflineCacheService.saveOfflinePackPlaces('hospital', results.map((p) => p.toJson()).toList()));
          unawaited(_refreshRoadRoutes());
          _expandRadiusIfNeeded(results.isNotEmpty);
        }
      }).catchError((_) {
        if (context.mounted) setState(() => _offlinePackJobRunning = false);
      });

      unawaited(_loadPastIncidents(position));
    } catch (_) {
      if (context.mounted) setState(() => _offlinePackJobRunning = false);
    }
  }

  Future<void> _loadPastIncidents(Position pos) async {
    if (_loadingPastIncidents) return;
    _loadingPastIncidents = true;
    try {
      final center = LatLng(pos.latitude, pos.longitude);
      if (widget.isDrillShell) {
        final now = DateTime.now();
        final archived = DrillMapDemoIncidents.archivedNear(center, now);
        if (context.mounted) {
          setState(() {
            _pastIncidents = archived;
            _areaIntel = IncidentService.computeAreaIntel(archived, center);
            _offlinePackProgress = math.max(_offlinePackProgress, 0.72);
          });
        }
        _loadingPastIncidents = false;
        return;
      }

      unawaited(IncidentService.autoArchiveExpiredIncidents());

      final past = await IncidentService.fetchPastIncidents(
        center: center,
        radiusMeters: _emergencyRadius,
      );
      if (context.mounted) {
        setState(() {
          _pastIncidents = past;
          _areaIntel = IncidentService.computeAreaIntel(past, center);
          _offlinePackProgress = math.max(_offlinePackProgress, 0.72);
        });
        unawaited(OfflineCacheService.savePastIncidentsArchive(
          past.map((i) => i.toJson()).toList(),
        ));
      }
    } catch (_) {}
    _loadingPastIncidents = false;
  }

  void _bumpOfflinePack(double delta) {
    if (!context.mounted) return;
    setState(() {
      _offlinePackProgress = (_offlinePackProgress + delta).clamp(0.0, 1.0);
    });
  }

  Future<void> _openExternalNavigationTo(EmergencyPlace place) async {
    final lat = place.lat;
    final lng = place.lng;
    final name = Uri.encodeComponent(place.name);
    var gStr = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving';
    if (place.placeId.isNotEmpty) {
      gStr += '&destination_place_id=${Uri.encodeComponent(place.placeId)}';
    }
    final g = Uri.parse(gStr);
    final geo = Uri.parse('geo:$lat,$lng?q=$lat,$lng($name)');
    try {
      if (await canLaunchUrl(g)) {
        await launchUrl(g, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    try {
      if (await canLaunchUrl(geo)) await launchUrl(geo, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showHospitalDetailSheet(EmergencyPlace place) {
    _presentEmergencyServiceSheet(place, 'hospital');
  }

  void _presentEmergencyServiceSheet(EmergencyPlace place, String layerKind) {
    _showEmergencyPlaceDetailSheet(
      place,
      layerKind: 'hospital',
      headerIcon: Icons.local_hospital_rounded,
      headerColor: const Color(0xFFFF1744).withValues(alpha: 0.9),
      serviceLabel: 'Hospital',
    );
  }

  void _showEmergencyPlaceDetailSheet(
    EmergencyPlace place, {
    required String layerKind,
    required IconData headerIcon,
    required Color headerColor,
    required String serviceLabel,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final dist = _currentPosition == null
            ? null
            : Geolocator.distanceBetween(
                _currentPosition!.latitude, _currentPosition!.longitude, place.lat, place.lng,
              );
        final spec = place.specializationForLayer(layerKind);
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(headerIcon, color: headerColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      place.name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(serviceLabel, style: TextStyle(color: headerColor.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(place.vicinity, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              if (dist != null) ...[
                const SizedBox(height: 6),
                Text('${(dist / 1000).toStringAsFixed(1)} km away', style: const TextStyle(color: AppColors.primaryInfo, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              const Text('Contact', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              SelectableText(
                place.phoneNumber,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.4),
              ),
              const SizedBox(height: 12),
              Text(
                layerKind == 'hospital' ? 'Specializations & services' : 'Role & specialization',
                style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(spec, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        unawaited(_openExternalNavigationTo(place));
                      },
                      icon: const Icon(Icons.navigation_rounded, size: 20),
                      label: const Text('Navigate'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primaryInfo, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    onPressed: () async {
                      final uri = Uri.parse('tel:${place.phoneNumber}');
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                    },
                    icon: const Icon(Icons.phone_in_talk_rounded),
                    tooltip: 'Call',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showPharmacyDetailSheet(PharmacyPlace p) {
    final dist = _currentPosition == null
        ? null
        : Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, p.lat, p.lng);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_pharmacy_rounded, color: const Color(0xFF26A69A)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  if (p.is24Hours)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF26A69A), borderRadius: BorderRadius.circular(8)),
                      child: const Text('24hr', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Pharmacy', style: TextStyle(color: const Color(0xFF26A69A).withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(p.vicinity, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              if (dist != null) ...[
                const SizedBox(height: 6),
                Text('${(dist / 1000).toStringAsFixed(1)} km away', style: const TextStyle(color: AppColors.primaryInfo, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
              if (p.availableMedicines.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Available Medicines', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: p.availableMedicines.map((med) => Chip(
                    label: Text(med, style: const TextStyle(fontSize: 10, color: Colors.white)),
                    backgroundColor: const Color(0xFF26A69A).withValues(alpha: 0.3),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )).toList(),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}');
                        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.navigation_rounded, size: 20),
                      label: const Text('Navigate'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primaryInfo, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    onPressed: () async {
                      final uri = Uri.parse('tel:${p.phoneNumber}');
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                    },
                    icon: const Icon(Icons.phone_in_talk_rounded),
                    tooltip: 'Call',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCoolingCenterDetailSheet(CoolingCenter c) {
    final dist = _currentPosition == null
        ? null
        : Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, c.lat, c.lng);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.ac_unit_rounded, color: const Color(0xFF42A5F5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(c.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('UP Govt Cooling Center', style: TextStyle(color: const Color(0xFF42A5F5).withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(c.address, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              if (c.operatingHours != null) ...[
                const SizedBox(height: 4),
                Text('Hours: ${c.operatingHours}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
              if (dist != null) ...[
                const SizedBox(height: 6),
                Text('${(dist / 1000).toStringAsFixed(1)} km away', style: const TextStyle(color: AppColors.primaryInfo, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (c.hasORS)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFFF9800).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.water_drop_rounded, size: 14, color: Color(0xFFFF9800)),
                          SizedBox(width: 4),
                          Text('ORS Available', style: TextStyle(fontSize: 11, color: Color(0xFFFF9800), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  if (c.hasMedicalSupport) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFE53935).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.medical_services_rounded, size: 14, color: Color(0xFFE53935)),
                          SizedBox(width: 4),
                          Text('Medical Support', style: TextStyle(fontSize: 11, color: Color(0xFFE53935), fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${c.lat},${c.lng}');
                        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.navigation_rounded, size: 20),
                      label: const Text('Navigate'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primaryInfo, foregroundColor: Colors.white),
                    ),
                  ),
                  if (c.phoneNumber.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: () async {
                        final uri = Uri.parse('tel:${c.phoneNumber}');
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                      icon: const Icon(Icons.phone_in_talk_rounded),
                      tooltip: 'Call',
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBloodBankDetailSheet(BloodBankInfo b) {
    final dist = _currentPosition == null
        ? null
        : Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, b.lat, b.lng);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bloodtype_rounded, color: const Color(0xFFE53935)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(b.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Blood Bank', style: TextStyle(color: const Color(0xFFE53935).withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(b.address, style: const TextStyle(color: Colors.white60, fontSize: 13)),
              if (dist != null) ...[
                const SizedBox(height: 6),
                Text('${(dist / 1000).toStringAsFixed(1)} km away', style: const TextStyle(color: AppColors.primaryInfo, fontWeight: FontWeight.w700, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              const Text('Blood Availability', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: b.bloodGroups.entries.map((e) {
                  final isAvailable = e.value.toLowerCase().contains('available') || e.value.toLowerCase().contains('stock');
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isAvailable ? const Color(0xFF4CAF50).withValues(alpha: 0.3) : const Color(0xFFE53935).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${e.key}: ${e.value}', style: TextStyle(fontSize: 11, color: isAvailable ? const Color(0xFF4CAF50) : const Color(0xFFE53935), fontWeight: FontWeight.bold)),
                  );
                }).toList(),
              ),
              if (b.lastUpdated != null) ...[
                const SizedBox(height: 8),
                Text('Updated: ${_timeAgo(DateTime.parse(b.lastUpdated!))}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${b.lat},${b.lng}');
                        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.navigation_rounded, size: 20),
                      label: const Text('Navigate'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primaryInfo, foregroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    onPressed: () async {
                      final uri = Uri.parse('tel:${b.phoneNumber}');
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                    },
                    icon: const Icon(Icons.phone_in_talk_rounded),
                    tooltip: 'Call',
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _markerSnippet(EmergencyPlace p, String layerKind, double distM) {
    final km = (distM / 1000).toStringAsFixed(1);
    final spec = p.specializationForLayer(layerKind);
    final short = spec.length > 38 ? '${spec.substring(0, 36)}…' : spec;
    return '$km km · $short';
  }

  void _expandRadiusIfNeeded(bool foundAnyService) {
    if (!foundAnyService && _emergencyRadius < 15000 && context.mounted) {
      setState(() { _emergencyRadius += 3000; });
    }
  }

  void _scheduleMapUiRepaint() {
    final now = DateTime.now();
    if (now.difference(_lastMapUiPaint) < _mapUiMinInterval) return;
    _lastMapUiPaint = now;
    if (context.mounted) setState(() {});
  }

  void _syncMapAnimationMode() {
    if (!context.mounted) return;
    final suppressMotion = suppressGoogleMapMarkerAnimations(context) ||
        ConnectivityService().shouldDeferExpensiveNetworkWork;
    if (suppressMotion == _lastSuppressMarkerMotion) return;
    _lastSuppressMarkerMotion = suppressMotion;

    final wantMotion = !suppressMotion;
    if (wantMotion) {
      _mapUiMinInterval = const Duration(milliseconds: 180);
      _rotationController.addListener(_scheduleMapUiRepaint);
      if (!_rotationController.isAnimating) _rotationController.repeat();
    } else {
      _rotationController.removeListener(_scheduleMapUiRepaint);
      _rotationController.stop();
      _mapUiMinInterval = const Duration(milliseconds: 500);
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMapAnimationMode());
  }

  void _onMapCreated(OpsMapController controller) {
    if (!_controller.isCompleted) _controller.complete(controller);
  }

  BitmapDescriptor _incidentStyleIconForCategory(String category) {
    if (category.contains('stroke')) {
      return _incidentStrokeMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
    }
    if (category.contains('cardiac') || category.contains('heart')) {
      return _incidentCardiacMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
    }
    if (category.contains('collision') ||
        category.contains('accident') ||
        category.contains('traffic') ||
        category.contains('rtc') ||
        category.contains('crash') ||
        category.contains('fall')) {
      return _incidentCollisionMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    }
    if (category.contains('bleeding') || category.contains('hemorrhage')) {
      return _incidentBleedingMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
    }
    if (category.contains('fire') || category.contains('lpg') || category.contains('chemical')) {
      return _incidentFireMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }
    if (category.contains('drown')) {
      return _incidentDrowningMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    }
    if (category.contains('choking') || category.contains('airway')) {
      return _incidentChokingMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    }
    return _incidentDefaultMarker ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
  }

  void _showMapDirectoryAccuracyDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Verify important places by phone',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Pins come from maps and third-party listings and can be wrong or out of date. '
            'Before you rely on a hospital or recovery service for routing, confirm the address, '
            'hours, and capabilities by phone — especially in an emergency.\n\n'
            'If you spot a wrong listing, tell your coordinator or operations contact so the directory can be corrected.',
            style: TextStyle(color: Colors.white70, height: 1.45, fontSize: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _regenerateMockHotspots() {
    if (_currentPosition == null) return;
    _mockHotspotCenters.clear();
    _mockHotspotRadii.clear();
    final lat = _currentPosition!.latitude;
    final lng = _currentPosition!.longitude;
    for (var i = 0; i < 16; i++) {
      final dLat = (_mockHotspotRng.nextDouble() - 0.5) * 0.07;
      final dLng = (_mockHotspotRng.nextDouble() - 0.5) * 0.07;
      _mockHotspotCenters.add(LatLng(lat + dLat, lng + dLng));
      _mockHotspotRadii.add(260 + _mockHotspotRng.nextDouble() * 880);
    }
  }

  void _toggleMockHotspotDemo() {
    setState(() {
      _mockHotspotsOn = !_mockHotspotsOn;
      if (_mockHotspotsOn) {
        _regenerateMockHotspots();
      } else {
        _mockHotspotCenters.clear();
        _mockHotspotRadii.clear();
      }
    });
  }

  Future<void> _hydrateOfflineFromPack() async {
    if (!context.mounted) return;
    final h = OfflineCacheService.loadOfflinePackPlaces('hospital')?.map(EmergencyPlace.fromJson).toList() ?? [];
    final routes = await OfflineMapPackService.loadRoutePolylines();
    if (!context.mounted) return;
    setState(() {
      if (h.isNotEmpty) _hospitals = h;
      if (routes.hospital.length > 1) _hospitalRoute = routes.hospital;
    });
    final pos = _currentPosition;
    if (pos != null && !widget.isDrillShell) {
      final center = LatLng(pos.latitude, pos.longitude);
      final cachedIncidents = OfflineCacheService.loadPastIncidentsArchive()
          .map((m) => SosIncident.fromJson(Map<String, dynamic>.from(m)))
          .where((inc) {
            final dist = Geolocator.distanceBetween(
              center.latitude, center.longitude, inc.location.latitude, inc.location.longitude,
            );
            return dist <= _emergencyRadius;
          })
          .toList();
      if (cachedIncidents.isNotEmpty && context.mounted) {
        setState(() {
          _pastIncidents = cachedIncidents;
          _areaIntel = IncidentService.computeAreaIntel(cachedIncidents, center);
        });
      }
    }
  }

  Future<void> _loadEmergencyServicesData() async {
    final fallback = IndiaOpsZones.lucknow.center;
    final pos = _currentPosition;
    final lat = pos?.latitude ?? fallback.latitude;
    final lng = pos?.longitude ?? fallback.longitude;
    final radiusKm = _emergencyRadius / 1000;

    final pharmacies = EmergencyServicesService.getNearbyPharmacies(
      lat, lng, radiusKm,
    );
    final coolingCenters = EmergencyServicesService.getNearbyCoolingCenters(
      lat, lng, radiusKm,
    );
    final bloodBanks = EmergencyServicesService.getNearbyBloodBanks(
      lat, lng, radiusKm,
    );
    List<DiseaseOutbreak> outbreaks = [];
    try {
      var country = 'IN';
      try {
        final marks = await placemarkFromCoordinates(lat, lng);
        final iso = marks.isNotEmpty ? marks.first.isoCountryCode : null;
        if (iso != null && iso.length == 2) {
          country = iso.toUpperCase();
        }
      } catch (_) {}
      outbreaks = await RegionalHealthAlertsService.fetchForLocation(
        lat: lat,
        lng: lng,
        countryCodeIso2: country,
      );
    } catch (e) {
      debugPrint('[MapScreen] regional health alerts: $e');
    }
    if (outbreaks.isEmpty) {
      outbreaks = EmergencyServicesService.getActiveOutbreaks();
    }

    AQIInfo? aqi;
    try {
      final hex = await EnvironmentalDataService.fetchForLocation(
        LatLng(lat, lng),
      );
      if (hex != null) {
        aqi = EnvironmentalDataService.toAqiInfo(hex);
      }
    } catch (e) {
      debugPrint('[MapScreen] Google AQI: $e');
    }
    aqi ??= await EmergencyServicesService.getAQI(lat, lng);

    if (!mounted) return;
    setState(() {
      _pharmacies = pharmacies;
      _coolingCenters = coolingCenters;
      _bloodBanks = bloodBanks;
      _outbreaks = outbreaks;
      _aqiInfo = aqi;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final activeHazards = ref.watch(activeHazardsProvider);
    final bedsAsync = ref.watch(bedAvailabilityProvider);
    final beds = bedsAsync.value ??
        const HospitalBedState(
          totalBedsAvailable: 0,
          totalBedsCapacity: 0,
          totalDoctorsOnDuty: 0,
          totalSpecialistsOnCall: 0,
        );
    final isOnlineAsync = ref.watch(connectivityProvider);
    final isOnline = isOnlineAsync.value ?? true;
    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : IndiaOpsZones.lucknow.center;
    final now = DateTime.now();
    final liveIncidents = widget.isDrillShell
        ? DrillMapDemoIncidents.activeNear(center, now)
        : (ref.watch(activeIncidentsProvider).value ?? []);
    // Main app: hide seeded training incidents (`demo_ops_*`); drill uses synthetic or full feed as needed.
    final mapLiveIncidents = widget.isDrillShell
        ? liveIncidents
        : liveIncidents.where((e) => !DemoFleetSimulation.isDemoIncident(e.id)).toList();
    final volSig = mapLiveIncidents
        .map((e) {
          final v = e.volunteerLiveLocation;
          if (v == null) return '';
          final p = e.liveVictimPin;
          return '${e.id}:${v.latitude.toStringAsFixed(4)}:${v.longitude.toStringAsFixed(4)}:'
              '${p.latitude.toStringAsFixed(4)}:${p.longitude.toStringAsFixed(4)}';
        })
        .where((s) => s.isNotEmpty)
        .join('|');
    if ((widget.isDrillShell || _mapShowVolunteers) && volSig != _lastVolunteerRouteRequestSig) {
      _lastVolunteerRouteRequestSig = volSig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) unawaited(_syncVolunteerResponderRoutes(mapLiveIncidents));
      });
    }
    final demoResponderSig = liveIncidents
        .where((e) => DemoResponderSimulation.isDemoIncident(e.id))
        .map((e) {
          final p = e.liveVictimPin;
          final bits = <String>[e.id, p.latitude.toStringAsFixed(5), p.longitude.toStringAsFixed(5)];
          if (e.ambulanceLiveLocation != null) bits.add('a');
          return bits.join('|');
        })
        .join('~');
    if (widget.isDrillShell && demoResponderSig != _lastDemoFleetResponderSig) {
      _lastDemoFleetResponderSig = demoResponderSig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || !widget.isDrillShell) return;
        final z = IndiaOpsZones.lucknow;
        for (final e in liveIncidents) {
          if (!DemoResponderSimulation.isDemoIncident(e.id)) continue;
          final scene = e.liveVictimPin;
          if (e.ambulanceLiveLocation != null) {
            DemoFleetRouteCache.prefetchResponderRoute(e.id, 'amb', scene, z);
          }
        }
      });
    }
    final demoVictimPinsForFleet = <String, LatLng>{
      for (final inc in liveIncidents)
        if (inc.id.startsWith('demo_ops_')) inc.id: inc.liveVictimPin,
    };
    final sortedDemoIds = demoVictimPinsForFleet.keys.toList()..sort();
    final fleetPrefetchSig = '${_fleetDemoDocs.map((d) {
      final aid = (d.data()['assignedIncidentId'] as String?) ?? '';
      return '${d.id}|$aid';
    }).join(',')}~${sortedDemoIds.join(',')}';
    if (widget.isDrillShell &&
        _fleetDemoDocs.isNotEmpty &&
        fleetPrefetchSig != _lastFleetDemoRouteSig) {
      _lastFleetDemoRouteSig = fleetPrefetchSig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || !widget.isDrillShell) return;
        final z = IndiaOpsZones.lucknow;
        final pins = <String, LatLng>{
          for (final inc in liveIncidents)
            if (inc.id.startsWith('demo_ops_')) inc.id: inc.liveVictimPin,
        };
        for (final d in _fleetDemoDocs) {
          if (!DemoFleetSimulation.isDemoDoc(d.id)) continue;
          final data = d.data();
          final aid = (data['assignedIncidentId'] as String?)?.trim();
          final pin = aid != null ? pins[aid] : null;
          final (a, b) = DemoFleetRouting.fleetEndpoints(d.id, z, aid, pin, pins);
          DemoFleetRouteCache.prefetchFleetLoop(DemoFleetRouting.fleetCacheKey(d.id, z, a, b), a, b);
        }
      });
    }
    final suppressMotion = suppressGoogleMapMarkerAnimations(context);
    final hazardsForMap = widget.isDrillShell ? activeHazards : const <HazardModel>[];

    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      if (next.value == true && context.mounted) {
        setState(() => _offlineHydrateRequested = false);
      }
    });

    if (!isOnline) {
      final hasPackSnapshot = OfflineCacheService.loadOfflinePackPlaces('hospital') != null;
      final hasLists = _hospitals.isNotEmpty;
      if (!_offlineHydrateRequested && (!hasLists && hasPackSnapshot)) {
        _offlineHydrateRequested = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_hydrateOfflineFromPack()));
      }
      if (!hasLists && !hasPackSnapshot) {
        return OfflineEmergencyDirectory(
          hospitals: _hospitals,
          currentPosition: _currentPosition,
        );
      }
    }

    final showPackProgress =
        !_isScanning && !_offlinePackComplete && (_offlinePackJobRunning || _offlinePackProgress > 0.04);

    return Scaffold(
      body: Stack(
        children: [
          EosHybridMap(
            mapType: MapType.normal,
            ignoreRemoteLeafletTiles: false,
            forceGoogleTiles: !widget.isDrillShell,
            mapId: AppConstants.googleMapsDarkMapId.isNotEmpty
                ? AppConstants.googleMapsDarkMapId
                : null,
            style: effectiveGoogleMapsEmbeddedStyleJson(),
            trafficEnabled: false,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
            },
            cameraTargetBounds: IndiaOpsZones.lucknowCameraTargetBounds,
            initialCameraPosition: IndiaOpsZones.lucknowSafeCamera(
              _currentPosition != null
                  ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                  : _initialPosition.target,
              preferZoom: _currentPosition != null ? 15.0 : _initialPosition.zoom,
            ),
            onMapCreated: _onMapCreated,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            circles: _mapCircles(mapLiveIncidents),
            polygons: _mapZonePolygons(),
            markers: _buildServiceMarkers(hazardsForMap, beds, mapLiveIncidents, suppressMotion),
            polylines: _buildRouteLines(),
          ),

          // Subtle loading overlay
          if (_isScanning)
            _buildScanOverlay(),

          if (showPackProgress)
            Positioned(
              top: MediaQuery.of(context).padding.top,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(
                      value: _offlinePackProgress.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: Colors.white10,
                      color: AppColors.primarySafe,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: Text(
                        l10n.mapCachingOfflinePct((_offlinePackProgress * 100).clamp(0, 100).round()),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (!_isScanning && widget.isDrillShell)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 12,
              right: 12,
              child: Material(
                color: Colors.cyan.shade900.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.school_rounded, color: Colors.cyanAccent.shade200, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.mapDrillPracticeBanner,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.94),
                            fontSize: 11,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (!_isScanning && !widget.isDrillShell)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 10,
              right: 220,
              child: _buildMainIntelCard(isOnline),
            ),

          // Top-right: re-center
          if (!_isScanning)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: _MapActionButton(
                icon: Icons.my_location,
                tooltip: l10n.mapRecenterTooltip,
                onTap: () => _determinePosition(forcePlacesRefresh: true),
              ),
            ),

          // Route legend — bottom-right; sits above system inset (no full-width chip bar).
          if (!_isScanning && _routeLegendVisible())
            Positioned(
              bottom: _mapChipBarBottomInset +
                  _mapChipBarHeightEstimate +
                  _mapLegendGapAboveChipBar +
                  MediaQuery.of(context).padding.bottom,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_mapShowZoneClassification) _buildZoneClassificationPanel(context),
                    if (_mapShowZoneClassification &&
                        ((widget.isDrillShell && _mapShowPastIncidents && _pastIncidents.isNotEmpty) ||
                            (!widget.isDrillShell && _showPastIncidentsForZone && _pastIncidentsInUserHex().isNotEmpty)))
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Container(height: 1, color: Colors.white24),
                      ),
                    if (!_mapShowZoneClassification) ...[
                      if (_mapShowEmergencyServices)
                        _legendRow(
                          const Color(0xFFFF1744),
                          l10n.mapLegendHospital,
                          _hospitalsForMapMarkers().isEmpty ? '' : _nearestDistLabel(_hospitalsForMapMarkers()),
                        ),
                      if (_mapShowPharmacies && _pharmacies.isNotEmpty)
                        _legendRow(const Color(0xFF26A69A), 'Pharmacy', '${_pharmacies.length} found'),
                      if (_mapShowCoolingCenters && _coolingCenters.isNotEmpty)
                        _legendRow(const Color(0xFF42A5F5), 'Cooling Centers', '${_coolingCenters.length} available'),
                      if (_mapShowBloodBanks && _bloodBanks.isNotEmpty)
                        _legendRow(const Color(0xFFE53935), 'Blood Banks', '${_bloodBanks.length} nearby'),
                    ],
                    if ((widget.isDrillShell && _mapShowPastIncidents && _pastIncidents.isNotEmpty) ||
                        (!widget.isDrillShell && _showPastIncidentsForZone && _pastIncidentsInUserHex().isNotEmpty)) ...[
                      if (!_mapShowZoneClassification && (_mapShowEmergencyServices && _hospitals.isNotEmpty))
                        const SizedBox(height: 4),
                      _legendRow(
                        Colors.blueGrey,
                        widget.isDrillShell ? l10n.mapLegendLiveSosHistory : l10n.mapLegendPastThisHex,
                        widget.isDrillShell
                            ? l10n.mapLegendIncidentsInArea(_pastIncidents.length)
                            : l10n.mapLegendIncidentsInCell(_pastIncidentsInUserHex().length),
                      ),
                    ],
                    if (_mapShowVolunteers && _nearbyOnDutyVolunteers().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _legendRow(
                          const Color(0xFF69F0AE),
                          l10n.mapLegendVolunteersOnDuty,
                          l10n.mapLegendVolunteersInGrid(_nearbyOnDutyVolunteers().length),
                        ),
                      ),
                    if (_volunteerResponderPolylines.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _legendRow(
                          AppColors.primarySafe,
                          l10n.mapResponderRoutes(_volunteerResponderPolylines.length),
                          '',
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Bottom bar: Info (left) + layer toggles (right, semi-transparent panel).
          if (!_isScanning)
            Positioned(
              left: 8,
              right: 8,
              bottom: _mapChipBarBottomInset +
                  MediaQuery.of(context).padding.bottom +
                  _mapChipBarHeightEstimate +
                  10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'View AQI and Health Alerts',
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(14),
                      elevation: 6,
                      child: InkWell(
                        onTap: () => unawaited(_showInfoPanel()),
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Info',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_mapShowPharmacies && _pharmacies.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Tooltip(
                        message: 'Filter pharmacies by medicine type',
                        child: Material(
                          color: _pharmacyMedicineFilter.isNotEmpty
                              ? const Color(0xFF26A69A).withValues(alpha: 0.95)
                              : Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(14),
                          elevation: 6,
                          child: InkWell(
                            onTap: _showPharmacyFilterDialog,
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.filter_list_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    _pharmacyMedicineFilter.isEmpty ? 'Filter' : _pharmacyMedicineFilter,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Material(
                    color: Colors.black.withValues(alpha: 0.78),
                    elevation: 6,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            CheckboxListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: EdgeInsets.zero,
                              tileColor: Colors.transparent,
                              title: const Text('Zones', style: _mapFilterCheckboxTitleStyle),
                              secondary: Icon(Icons.radar_rounded, size: 18, color: AppColors.primarySafe.withValues(alpha: _mapShowZoneClassification ? 1 : 0.5)),
                              value: _mapShowZoneClassification,
                              onChanged: (v) => setState(() => _mapShowZoneClassification = v ?? false),
                              activeColor: AppColors.primarySafe,
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            CheckboxListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: EdgeInsets.zero,
                              tileColor: Colors.transparent,
                              title: const Text('Emergency services', style: _mapFilterCheckboxTitleStyle),
                              secondary: Icon(Icons.health_and_safety_rounded, size: 18, color: const Color(0xFF2979FF).withValues(alpha: _mapShowEmergencyServices ? 1 : 0.5)),
                              value: _mapShowEmergencyServices,
                              onChanged: (v) => setState(() => _mapShowEmergencyServices = v ?? false),
                              activeColor: const Color(0xFF2979FF),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            if (widget.isDrillShell) ...[
                              CheckboxListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: EdgeInsets.zero,
                                tileColor: Colors.transparent,
                                title: const Text('Live SOS', style: _mapFilterCheckboxTitleStyle),
                                secondary: Icon(Icons.sos_rounded, size: 18, color: Colors.blueGrey.withValues(alpha: _mapShowPastIncidents ? 1 : 0.5)),
                                value: _mapShowPastIncidents,
                                onChanged: (v) => setState(() => _mapShowPastIncidents = v ?? false),
                                activeColor: Colors.blueGrey,
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
                              CheckboxListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: EdgeInsets.zero,
                                tileColor: Colors.transparent,
                                title: const Text('Volunteers', style: _mapFilterCheckboxTitleStyle),
                                secondary: Icon(Icons.groups_rounded, size: 18, color: const Color(0xFF69F0AE).withValues(alpha: _mapShowVolunteers ? 1 : 0.5)),
                                value: _mapShowVolunteers,
                                onChanged: (v) => setState(() => _mapShowVolunteers = v ?? false),
                                activeColor: const Color(0xFF69F0AE),
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
                            ],
                            CheckboxListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: EdgeInsets.zero,
                              tileColor: Colors.transparent,
                              title: const Text('24hr Pharmacy', style: _mapFilterCheckboxTitleStyle),
                              secondary: Icon(Icons.local_pharmacy_rounded, size: 18, color: const Color(0xFF26A69A).withValues(alpha: _mapShowPharmacies ? 1 : 0.5)),
                              value: _mapShowPharmacies,
                              onChanged: (v) => setState(() => _mapShowPharmacies = v ?? false),
                              activeColor: const Color(0xFF26A69A),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            CheckboxListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: EdgeInsets.zero,
                              tileColor: Colors.transparent,
                              title: const Text('Cooling Centers', style: _mapFilterCheckboxTitleStyle),
                              secondary: Icon(Icons.ac_unit_rounded, size: 18, color: const Color(0xFF42A5F5).withValues(alpha: _mapShowCoolingCenters ? 1 : 0.5)),
                              value: _mapShowCoolingCenters,
                              onChanged: (v) => setState(() => _mapShowCoolingCenters = v ?? false),
                              activeColor: const Color(0xFF42A5F5),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                            CheckboxListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: EdgeInsets.zero,
                              tileColor: Colors.transparent,
                              title: const Text('Blood Banks', style: _mapFilterCheckboxTitleStyle),
                              secondary: Icon(Icons.bloodtype_rounded, size: 18, color: const Color(0xFFE53935).withValues(alpha: _mapShowBloodBanks ? 1 : 0.5)),
                              value: _mapShowBloodBanks,
                              onChanged: (v) => setState(() => _mapShowBloodBanks = v ?? false),
                              activeColor: const Color(0xFFE53935),
                              controlAffinity: ListTileControlAffinity.leading,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MINIMAL SCAN OVERLAY
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMainIntelCard(bool isOnline) {
    final ai = _areaIntel;
    final ambM = ai.avgAmbulanceResponseMinutes;
    final volM = ai.avgVolunteerResponseMinutes;
    final legM = ai.avgResponseMinutes;
    final ambLabel = ambM > 0 ? '$ambM min' : '—';
    final volLabel = volM > 0 ? '$volM min' : '—';
    final legacyLabel = legM > 0 ? '$legM min' : '~8 min';
    final radiusM = _cachedPackRadiusM ?? _emergencyRadius.round();
    final radiusKm = (radiusM / 1000).toStringAsFixed(1);
    final nearestLine = _hospitals.isEmpty || _currentPosition == null
        ? 'Nearest hospital: —'
        : () {
            final n = _nearestPlace(_hospitals);
            final km = Geolocator.distanceBetween(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                  n.lat,
                  n.lng,
                ) /
                1000;
            return 'Nearest: ${n.name} · ${km.toStringAsFixed(1)} km';
          }();
    final packPct = (_offlinePackProgress * 100).clamp(0, 100).round();
    final syncLine = !isOnline
        ? 'Device offline · last cached area ~$radiusKm km'
        : (_offlinePackComplete
            ? 'Online · offline pack ready ($packPct%) · ~$radiusKm km'
            : (_offlinePackJobRunning || packPct > 4
                ? 'Online · caching routes/places $packPct%'
                : 'Online · grid data loading'));
    final zonePast = _pastIncidentsInUserHex();
    final zoneLine = _showPastIncidentsForZone
        ? 'This hex: ${zonePast.length} past incident${zonePast.length == 1 ? '' : 's'}'
        : 'Zone past: off — open Zone Info (legend) to plot this cell';

    return Material(
      color: Colors.black.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.38),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.timer_outlined, color: AppColors.primaryInfo, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ambulance avg $ambLabel · Volunteer avg $volLabel · blended $legacyLabel',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _showMapDirectoryAccuracyDialog,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Details', style: TextStyle(fontSize: 10)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                nearestLine,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.88), fontSize: 10, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                syncLine,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 9, height: 1.25),
              ),
              Text(
                'Caches places + routes within ~$radiusKm km (map tiles not stored offline).',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9, height: 1.25),
              ),
              const SizedBox(height: 4),
              Text(
                zoneLine,
                style: TextStyle(
                  color: _showPastIncidentsForZone ? Colors.blueGrey.shade200 : Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanOverlay() {
    return Container(
      color: AppColors.background.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (_, __) => Container(
                width: 56 + 12 * _pulseController.value,
                height: 56 + 12 * _pulseController.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryInfo.withValues(alpha: 0.08 + 0.06 * _pulseController.value),
                  border: Border.all(
                    color: AppColors.primaryInfo.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.gps_fixed_rounded, color: AppColors.primaryInfo, size: 24),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Locating you…',
              style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REPORT HAZARD SHEET
  // ═══════════════════════════════════════════════════════════════════════════

  void _showReportSosSheet() {
    if (_currentPosition == null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: 24.0, right: 24.0, top: 24.0,
              bottom: 24.0 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Report SOS for someone else', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              const Text('Drop an emergency pin at your location to instantly alert nearby volunteers and medics.', style: TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: HazardType.values.map((type) => InkWell(
                  onTap: () {
                    ref.read(activeHazardsProvider.notifier).addHazard(
                      type, 
                      _currentPosition!.latitude, 
                      _currentPosition!.longitude
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${type.label} reported successfully. Global routes updated.'),
                        backgroundColor: AppColors.primarySafe,
                      )
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: (MediaQuery.of(context).size.width - 60) / 2,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: type.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: type.color.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(type.icon, color: type.color, size: 32),
                        const SizedBox(height: 8),
                        Text(type.label, style: TextStyle(color: type.color, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ));
      }
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAP POLYGONS (hex zone mesh)
  // ═══════════════════════════════════════════════════════════════════════════

  Set<Polygon> _mapZonePolygons() {
    if (!_mapShowZoneClassification) return {};
    final model = _computeHexZoneModel();
    if (model == null) return {};
    return model.polygons;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MAP CIRCLES
  // ═══════════════════════════════════════════════════════════════════════════

  Set<Circle> _mapCircles(List<SosIncident> liveSosIncidents) {
    final Set<Circle> circles = {};
    final pulse = _pulseController.value;

    for (var i = 0; i < liveSosIncidents.length; i++) {
      final incident = liveSosIncidents[i];
      final center = LatLng(incident.location.latitude, incident.location.longitude);
      final ringRadius = 38 + 140 * pulse;
      circles.add(Circle(
        circleId: CircleId('live_sos_pulse_${incident.id}_$i'),
        center: center,
        radius: ringRadius,
        fillColor: Color.lerp(Colors.redAccent, Colors.orangeAccent, pulse)!.withValues(alpha: 0.06 + 0.14 * (1 - pulse)),
        strokeColor: Color.lerp(Colors.redAccent, Colors.amberAccent, pulse)!.withValues(alpha: 0.45 + 0.45 * pulse),
        strokeWidth: 2,
        zIndex: 4,
      ));
    }

    if (_mapShowZoneClassification) {
      final zone = _activeOpsZone;
      circles.add(Circle(
        circleId: const CircleId('emergency_radius_hex_zones'),
        center: zone.center,
        radius: _hexGridCoverRadiusM(zone),
        fillColor: Colors.transparent,
        strokeColor: const Color(0xFF37474F).withValues(alpha: 0.42),
        strokeWidth: 1,
        zIndex: 0,
      ));
    } else if (_currentPosition != null) {
      final LatLng c = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      circles.add(Circle(
        circleId: const CircleId('emergency_radius'),
        center: c,
        radius: _emergencyRadius,
        fillColor: AppColors.primaryInfo.withValues(alpha: 0.05),
        strokeColor: const Color(0xFF0D47A1).withValues(alpha: 0.65),
        strokeWidth: 2,
      ));
    }

    // Heat overlays: not gated on low-power map mode (that mode is for raster/hybrid stability).
    if (_showHeatmaps) {
      for (int i = 0; i < _areaIntel.dangerZones.length; i++) {
        final zone = _areaIntel.dangerZones[i];
        final intensity = (zone.incidentCount / (_areaIntel.totalPastIncidents.clamp(1, 999))).clamp(0.05, 0.3);
        circles.add(Circle(
          circleId: CircleId('hotspot_$i'),
          center: zone.center,
          radius: zone.radiusMeters,
          fillColor: Colors.deepOrange.withValues(alpha: intensity),
          strokeColor: Colors.deepOrange.withValues(alpha: 0.7),
          strokeWidth: 2,
          zIndex: 5,
        ));
      }
    }

    if (_mockHotspotsOn) {
      for (var i = 0; i < _mockHotspotCenters.length; i++) {
        final c = _mockHotspotCenters[i];
        final r = i < _mockHotspotRadii.length ? _mockHotspotRadii[i] : 400.0;
        final alpha = 0.07 + (i % 8) * 0.018;
        circles.add(Circle(
          circleId: CircleId('mock_risk_$i'),
          center: c,
          radius: r,
          fillColor: Color.lerp(Colors.red, Colors.deepOrange, (i % 3) / 3.0)!.withValues(alpha: alpha),
          strokeColor: Colors.redAccent.withValues(alpha: 0.35),
          strokeWidth: 1,
          zIndex: 6,
        ));
      }
    }

    return circles;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ROUTE LINES (polylines to nearest services)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _syncVolunteerResponderRoutes(List<SosIncident> incidents) async {
    final targets = incidents.where((e) => e.volunteerLiveLocation != null).toList();
    if (targets.isEmpty) {
      if (_volunteerResponderPolylines.isNotEmpty && context.mounted) {
        setState(() => _volunteerResponderPolylines.clear());
      }
      return;
    }
    final out = <String, List<LatLng>>{};
    await Future.wait(targets.map((inc) async {
      final v = inc.volunteerLiveLocation!;
      final pin = inc.liveVictimPin;
      var pts = await _getRoadRoute(v, pin);
      if (pts.length < 2) pts = [v, pin];
      out[inc.id] = pts;
    }));
    if (!context.mounted) return;
    setState(() {
      _volunteerResponderPolylines
        ..clear()
        ..addAll(out);
    });
  }

  Set<Polyline> _buildRouteLines() {
    if (_currentPosition == null) return {};
    final Set<Polyline> lines = {};

    if (_mapShowEmergencyServices && _hospitalRoute.length > 1) {
      lines.add(Polyline(
        polylineId: const PolylineId('route_hospital'),
        points: _hospitalRoute,
        color: const Color(0xFFB71C1C),
        width: 6,
        patterns: [PatternItem.dash(12), PatternItem.gap(8)],
      ));
    }

    if (widget.isDrillShell) {
      for (final e in _volunteerResponderPolylines.entries) {
        if (e.value.length < 2) continue;
        lines.add(Polyline(
          polylineId: PolylineId('volunteer_resp_${e.key}'),
          points: e.value,
          color: const Color(0xFF1B5E20),
          width: 7,
          zIndex: 24,
          patterns: [PatternItem.dash(14), PatternItem.gap(8)],
        ));
      }
    }

    return lines;
  }

  EmergencyPlace _nearestPlace(List<EmergencyPlace> places) {
    EmergencyPlace nearest = places.first;
    double minDist = double.infinity;
    for (final p in places) {
      final d = Geolocator.distanceBetween(
        _currentPosition!.latitude, _currentPosition!.longitude, p.lat, p.lng,
      );
      if (d < minDist) {
        minDist = d;
        nearest = p;
      }
    }
    return nearest;
  }

  HexAxial? _userHexAxial() {
    final p = _currentPosition;
    if (p == null) return null;
    final zone = _activeOpsZone;
    return volunteerToHex(
      kZoneHexCircumRadiusM,
      zone.center.latitude,
      zone.center.longitude,
      p.latitude,
      p.longitude,
    );
  }

  List<SosIncident> _pastIncidentsInUserHex() {
    final u = _userHexAxial();
    if (u == null) return [];
    final zone = _activeOpsZone;
    return _pastIncidents.where((inc) {
      final h = volunteerToHex(
        kZoneHexCircumRadiusM,
        zone.center.latitude,
        zone.center.longitude,
        inc.location.latitude,
        inc.location.longitude,
      );
      return h == u;
    }).toList();
  }

  List<SosIncident> _pastIncidentsForMapMarkers() {
    if (widget.isDrillShell) {
      if (!_mapShowPastIncidents) return [];
      return _pastIncidents;
    }
    if (!_showPastIncidentsForZone) return [];
    return _pastIncidentsInUserHex();
  }

  OpsHospitalRow? _opsHospitalNearPlace(EmergencyPlace place, {double meters = 450}) {
    for (final row in _opsHospitalRows) {
      final lat = row.lat;
      final lng = row.lng;
      if (lat == null || lng == null) continue;
      final d = Geolocator.distanceBetween(place.lat, place.lng, lat, lng);
      if (d <= meters) return row;
    }
    return null;
  }

  EmergencyPlace _emergencyPlaceFromOpsRow(OpsHospitalRow row) {
    return EmergencyPlace(
      name: row.name,
      vicinity: row.region,
      lat: row.lat!,
      lng: row.lng!,
      placeId: 'ops_hospital_${row.id}',
      types: const ['hospital'],
    );
  }

  /// Firestore [ops_hospitals] pins not already represented by a Places directory marker.
  List<OpsHospitalRow> _opsHospitalsForMapMarkers() {
    if (!_mapShowEmergencyServices || widget.isDrillShell || _currentPosition == null) {
      return const [];
    }
    final lat = _currentPosition!.latitude;
    final lng = _currentPosition!.longitude;
    final placePins = _hospitals.isEmpty ? <EmergencyPlace>[] : _hospitalsForMapMarkers();
    final eligible = <OpsHospitalRow>[];
    for (final row in _opsHospitalRows) {
      final olat = row.lat;
      final olng = row.lng;
      if (olat == null || olng == null) continue;
      if (Geolocator.distanceBetween(lat, lng, olat, olng) > _emergencyRadius) continue;
      var dup = false;
      for (final p in placePins) {
        if (Geolocator.distanceBetween(p.lat, p.lng, olat, olng) <= kOpsHospitalPlacesDedupeRadiusM) {
          dup = true;
          break;
        }
      }
      if (dup) continue;
      eligible.add(row);
    }
    if (eligible.isEmpty) return const [];
    if (_mapNearestOnly) {
      eligible.sort((a, b) {
        final da = Geolocator.distanceBetween(lat, lng, a.lat!, a.lng!);
        final db = Geolocator.distanceBetween(lat, lng, b.lat!, b.lng!);
        return da.compareTo(db);
      });
      return [eligible.first];
    }
    return eligible;
  }

  BitmapDescriptor? _incidentCategoryMarkerOrNull(String category) {
    if (category.contains('cardiac') || category.contains('heart')) {
      return _incidentCardiacMarker;
    }
    if (category.contains('collision') ||
        category.contains('accident') ||
        category.contains('traffic') ||
        category.contains('pedestrian') ||
        category.contains('casualty')) {
      return _incidentCollisionMarker;
    }
    if (category.contains('bleeding') || category.contains('hemorrhage')) {
      return _incidentBleedingMarker;
    }
    if (category.contains('fire')) {
      return _incidentFireMarker;
    }
    if (category.contains('drown')) {
      return _incidentDrowningMarker;
    }
    if (category.contains('stroke')) {
      return _incidentStrokeMarker;
    }
    if (category.contains('choking') || category.contains('airway')) {
      return _incidentChokingMarker;
    }
    return _incidentDefaultMarker;
  }

  BitmapDescriptor _bitmapForLiveSos(SosIncident incident, String category) {
    final catPin = _incidentCategoryMarkerOrNull(category);
    switch (incident.status) {
      case IncidentStatus.pending:
        return catPin ??
            OpsMapMarkers.liveSosPendingOr(
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            );
      case IncidentStatus.dispatched:
        return OpsMapMarkers.ambulanceOr(
          catPin ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        );
      case IncidentStatus.blocked:
        return OpsMapMarkers.sceneOr(
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        );
      case IncidentStatus.resolved:
        return catPin ??
            OpsMapMarkers.incidentOr(
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta),
            );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARKERS
  // ═══════════════════════════════════════════════════════════════════════════

  Set<Marker> _buildServiceMarkers(
    List<HazardModel> activeHazards,
    HospitalBedState beds,
    List<SosIncident> liveIncidents,
    bool suppressMarkerMotion,
  ) {
    final Set<Marker> markers = {};

    final liveSosFlash = 0.52 + 0.46 * _pulseController.value;

    for (final incident in liveIncidents) {
      final String statusEmoji = incident.status == IncidentStatus.pending
          ? '🆘'
          : (incident.status == IncidentStatus.blocked ? '⏸️' : '🚑');
      final String timeAgo = _timeAgo(incident.timestamp);
      final String category = incident.type.toLowerCase();

      final BitmapDescriptor icon = _bitmapForLiveSos(incident, category);

      markers.add(Marker(
        markerId: MarkerId('sos_${incident.id}'),
        position: LatLng(incident.location.latitude + 0.00015, incident.location.longitude + 0.00015),
        zIndexInt: 180,
        alpha: liveSosFlash,
        icon: icon,
        infoWindow: InfoWindow(
          title: '$statusEmoji ${incident.type}',
          snippet: '${incident.userDisplayName} • $timeAgo',
        ),
      ));
    }

    final pastForMarkers = _pastIncidentsForMapMarkers();
    if (pastForMarkers.isNotEmpty) {
      for (final inc in pastForMarkers) {
        final cat = inc.type.toLowerCase();
        markers.add(Marker(
          markerId: MarkerId('past_${inc.id}'),
          position: LatLng(inc.location.latitude, inc.location.longitude),
          zIndexInt: 55,
          alpha: 0.82,
          icon: _incidentStyleIconForCategory(cat),
          infoWindow: InfoWindow(
            title: widget.isDrillShell ? '📋 Practice: ${inc.type}' : '📋 Past: ${inc.type}',
            snippet: widget.isDrillShell ? '${inc.userDisplayName} · drill demo' : '${inc.userDisplayName} · area history',
          ),
        ));
      }
    }

    if (_currentPosition == null) return markers;
    final double lat = _currentPosition!.latitude;
    final double lng = _currentPosition!.longitude;

    markers.add(Marker(
      markerId: const MarkerId('user_location'),
      position: LatLng(lat, lng),
      icon: _userIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta),
      rotation: suppressMarkerMotion ? 0.0 : _userCourseDeg,
      flat: true,
      anchor: const Offset(0.5, 0.5),
      infoWindow: const InfoWindow(title: 'You', snippet: 'Active Unit'),
    ));

    if (widget.isDrillShell && _mapShowVolunteers) {
      for (final v in _nearbyOnDutyVolunteers()) {
        final dist = Geolocator.distanceBetween(lat, lng, v.lat, v.lng);
        final distLabel = dist >= 1000
            ? '${(dist / 1000).toStringAsFixed(1)} km away'
            : '${dist.round()} m away';
        // Pick the gendered marker (male default when gender is unknown)
        final BitmapDescriptor volunteerIcon = v.gender == 'female'
            ? (_volunteerFemaleIcon ??
                _volunteerDutyIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen))
            : (_volunteerMaleIcon ??
                _volunteerDutyIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen));
        markers.add(Marker(
          markerId: MarkerId('volunteer_${v.userId}'),
          position: LatLng(v.lat, v.lng),
          zIndexInt: 72,
          icon: volunteerIcon,
          infoWindow: InfoWindow(
            title: v.displayName,
            snippet: 'On duty · $distLabel',
          ),
        ));
      }
    }

    if (_mapShowEmergencyServices) {
      var hi = 0;
      for (var h in _hospitalsForMapMarkers()) {
        final suffix = h.placeId.isNotEmpty ? h.placeId : 'noid_${h.lat}_${h.lng}_$hi';
        final sLat = h.lat;
        final sLng = h.lng;
        final dist = Geolocator.distanceBetween(lat, lng, sLat, sLng);
        final hospital = h;
        final matched = !widget.isDrillShell ? _opsHospitalNearPlace(hospital) : null;
        final listing =
            matched == null ? '' : (matched.mapListingOnline ? ' · Online' : ' · Offline');
        markers.add(Marker(
          markerId: MarkerId('hospital_${hi}_$suffix'),
          position: LatLng(sLat, sLng),
          icon: _hospitalIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
          infoWindow: InfoWindow(
            title: '${h.name}$listing',
            snippet: _markerSnippet(hospital, 'hospital', dist),
          ),
          onTap: () => _showHospitalDetailSheet(hospital),
        ));
        hi++;
      }

      var oi = 0;
      for (final row in _opsHospitalsForMapMarkers()) {
        final olat = row.lat!;
        final olng = row.lng!;
        final dist = Geolocator.distanceBetween(lat, lng, olat, olng);
        final listing = row.mapListingOnline ? '' : ' · Offline';
        markers.add(Marker(
          markerId: MarkerId('ops_hospital_${row.id}_$oi'),
          position: LatLng(olat, olng),
          zIndexInt: 66,
          icon: _hospitalIcon ??
              OpsMapMarkers.hospitalOr(
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
              ),
          infoWindow: InfoWindow(
            title: '${row.name}$listing',
            snippet: '${row.region} · ${dist >= 1000 ? '${(dist / 1000).toStringAsFixed(1)} km' : '${dist.round()} m'}',
          ),
          onTap: () => _showHospitalDetailSheet(_emergencyPlaceFromOpsRow(row)),
        ));
        oi++;
      }
    }

    final hazardsForMap = widget.isDrillShell ? activeHazards : const <HazardModel>[];
    markers.addAll(hazardsForMap.map((hazard) {
      BitmapDescriptor icon;
      switch (hazard.type) {
        case HazardType.cardiacArrest: icon = _cardiacIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed); break;
        case HazardType.accident: icon = _accidentIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange); break;
        case HazardType.fire: icon = _fireHazardIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed); break;
        case HazardType.choking: icon = _chokingIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta); break;
        case HazardType.bleeding: icon = _bleedingIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed); break;
      }
      return Marker(
        markerId: MarkerId(hazard.id),
        position: hazard.location,
        icon: icon,
        infoWindow: InfoWindow(title: '${hazard.type.label} Reported', snippet: 'By ${hazard.reportedBy}'),
      );
    }));

    if (_mapShowPharmacies) {
      for (var pi = 0; pi < _pharmacies.length; pi++) {
        final p = _pharmacies[pi];
        final dist = Geolocator.distanceBetween(lat, lng, p.lat, p.lng);
        final distLabel = dist >= 1000
            ? '${(dist / 1000).toStringAsFixed(1)} km'
            : '${dist.round()} m';
        markers.add(Marker(
          markerId: MarkerId('pharmacy_$pi'),
          position: LatLng(p.lat, p.lng),
          icon: _pharmacyIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: '${p.name}${p.is24Hours ? " (24hr)" : ""}',
            snippet: '${p.medicineFilterSummary} · $distLabel',
          ),
          onTap: () => _showPharmacyDetailSheet(p),
        ));
      }
    }

    if (_mapShowCoolingCenters) {
      for (var ci = 0; ci < _coolingCenters.length; ci++) {
        final c = _coolingCenters[ci];
        final dist = Geolocator.distanceBetween(lat, lng, c.lat, c.lng);
        final distLabel = dist >= 1000
            ? '${(dist / 1000).toStringAsFixed(1)} km'
            : '${dist.round()} m';
        final facilities = <String>[];
        if (c.hasORS) facilities.add('ORS');
        if (c.hasMedicalSupport) facilities.add('Medical');
        markers.add(Marker(
          markerId: MarkerId('cooling_$ci'),
          position: LatLng(c.lat, c.lng),
          icon: _coolingCenterIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: c.name,
            snippet: '${facilities.isEmpty ? "Cool shelter" : facilities.join(" + ")} · $distLabel',
          ),
          onTap: () => _showCoolingCenterDetailSheet(c),
        ));
      }
    }

    if (_mapShowBloodBanks) {
      for (var bi = 0; bi < _bloodBanks.length; bi++) {
        final b = _bloodBanks[bi];
        final dist = Geolocator.distanceBetween(lat, lng, b.lat, b.lng);
        final distLabel = dist >= 1000
            ? '${(dist / 1000).toStringAsFixed(1)} km'
            : '${dist.round()} m';
        markers.add(Marker(
          markerId: MarkerId('bloodbank_$bi'),
          position: LatLng(b.lat, b.lng),
          icon: _bloodBankIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: b.name,
            snippet: 'Blood available · $distLabel',
          ),
          onTap: () => _showBloodBankDetailSheet(b),
        ));
      }
    }

    return markers;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildZoneClassificationPanel(BuildContext context) {
    final model = _computeHexZoneModel();
    final baseHeaderColor = model != null
        ? (model.zonePanelHeaderColorOverride ??
            zoneClassificationHeaderColor(model.userCellHealth))
        : const Color(0xFF424242);
    final coverPct = model != null ? model.coveragePercent.toStringAsFixed(0) : '–';
    final totalCells = model != null ? model.totalCells : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: baseHeaderColor,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (widget.isDrillShell) {
                setState(() => _zonePanelExpanded = !_zonePanelExpanded);
              } else {
                setState(() {
                  final next = !_zonePanelExpanded;
                  _zonePanelExpanded = next;
                  _showPastIncidentsForZone = next;
                });
              }
            },
            borderRadius: BorderRadius.circular(8),
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _zonePanelExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Zone Info',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_zonePanelExpanded) ...[
          const SizedBox(height: 4),
          Text(
            model != null && model.mainAppHospitalDensityLegend
                ? '$kZoneTierCount rings · 0–${(kMaxCoverageRadiusM / 1000).round()} km · $totalCells hex · $coverPct% cells with 3+ hospitals · 🟢≥3 🟡2 🔴1 ⬛0'
                : '$kZoneTierCount rings · 0–${(kMaxCoverageRadiusM / 1000).round()} km · $totalCells hex cells · $coverPct% covered',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 9, height: 1.25),
          ),
          const SizedBox(height: 6),
          if (model != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.32,
              ),
              child: Scrollbar(
                thumbVisibility: true,
                radius: const Radius.circular(8),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final t in model.tierSummaries)
                        _tierLegendRow(t, hospitalLegend: model.mainAppHospitalDensityLegend),
                    ],
                  ),
                ),
              ),
            )
          else
            const SizedBox.shrink(),
        ],
      ],
    );
  }

  Widget _tierLegendRow(TierAnnulusSummary t, {required bool hospitalLegend}) {
    final range = tierBandLabelKm(t.tierIndex);
    final total = t.total;
    final withHospital = t.greenHexes + t.yellowHexes + t.redHexes;
    final healthPct = total > 0
        ? ((hospitalLegend ? withHospital : t.greenHexes + t.yellowHexes) /
                total *
            100)
            .round()
        : 0;
    final parts = <String>[];
    if (t.greenHexes > 0) parts.add('${t.greenHexes}🟢');
    if (t.yellowHexes > 0) parts.add('${t.yellowHexes}🟡');
    if (t.redHexes > 0) parts.add('${t.redHexes}🔴');
    if (t.greyHexes > 0) parts.add('${t.greyHexes}⬛');
    final subLabel = hospitalLegend ? 'with hospital' : 'covered';
    final sub = parts.isEmpty ? 'No data' : '${parts.join(' ')}  ($healthPct% $subLabel)';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        'T${t.tierIndex + 1} · $range\n$sub',
        style: const TextStyle(
          color: Colors.white60,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildAQIInfoPanel() {
    final aqi = _aqiInfo!;
    Color aqiColor;
    if (aqi.aqi <= 50) {
      aqiColor = const Color(0xFF4CAF50);
    } else if (aqi.aqi <= 100) {
      aqiColor = const Color(0xFFFFEB3B);
    } else if (aqi.aqi <= 150) {
      aqiColor = const Color(0xFFFF9800);
    } else if (aqi.aqi <= 200) {
      aqiColor = const Color(0xFFE53935);
    } else {
      aqiColor = const Color(0xFF9C27B0);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: aqiColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.air_rounded, color: aqiColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'AQI: ${aqi.aqi.round()}',
                style: TextStyle(color: aqiColor, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: aqiColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                child: Text(aqi.category, style: TextStyle(color: aqiColor, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            aqi.personalizedImpact,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.masks_rounded, size: 14, color: Colors.white54),
              const SizedBox(width: 4),
              Expanded(
                child: Text(aqi.maskAdvisory, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ),
            ],
          ),
          if (aqi.sensitiveGroups.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: aqi.sensitiveGroups.map((g) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                child: Text(g, style: const TextStyle(color: Colors.white54, fontSize: 9)),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOutbreakAlertPanel() {
    final criticalOutbreaks = _outbreaks.where((o) => o.isCritical).toList();
    final otherOutbreaks = _outbreaks.where((o) => !o.isCritical).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.warning_rounded, color: const Color(0xFFFF9800), size: 20),
              const SizedBox(width: 8),
              const Text('Disease Outbreak Alerts', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ...criticalOutbreaks.take(2).map((outbreak) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(4)),
                        child: Text(outbreak.advisoryLevel ?? 'Alert', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Text(outbreak.disease, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(outbreak.description, style: const TextStyle(color: Colors.white70, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  if (outbreak.precautions.isNotEmpty)
                    Text('• ${outbreak.precautions.first}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ),
          )),
          if (otherOutbreaks.isNotEmpty) ...[
            const Divider(color: Colors.white24),
            Text('Other Alerts', style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...otherOutbreaks.take(2).map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 12, color: Colors.orange.shade300),
                  const SizedBox(width: 4),
                  Text('${o.disease} - ${o.affectedArea}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Future<void> _showInfoPanel() async {
    await _loadEmergencyServicesData();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    const Text('Health & Environment Info', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                if (_aqiInfo != null) ...[
                  _buildAQISection(),
                  const SizedBox(height: 16),
                ],
                if (_outbreaks.isNotEmpty) ...[
                  _buildOutbreakSection(),
                ],
                if (_aqiInfo == null && _outbreaks.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      children: [
                        Icon(Icons.cloud_off_rounded, color: Colors.white54),
                        SizedBox(width: 12),
                        Expanded(child: Text('No health alerts in your area', style: TextStyle(color: Colors.white70))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primaryInfo),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAQISection() {
    final aqi = _aqiInfo!;
    Color aqiColor;
    String aqiLabel;
    if (aqi.aqi <= 50) {
      aqiColor = const Color(0xFF4CAF50);
      aqiLabel = 'Good';
    } else if (aqi.aqi <= 100) {
      aqiColor = const Color(0xFFFFEB3B);
      aqiLabel = 'Moderate';
    } else if (aqi.aqi <= 150) {
      aqiColor = const Color(0xFFFF9800);
      aqiLabel = 'Unhealthy for Sensitive';
    } else if (aqi.aqi <= 200) {
      aqiColor = const Color(0xFFE53935);
      aqiLabel = 'Unhealthy';
    } else {
      aqiColor = const Color(0xFF9C27B0);
      aqiLabel = 'Very Unhealthy';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: aqiColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: aqiColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.air_rounded, color: aqiColor, size: 24),
              const SizedBox(width: 8),
              Text('AQI: ${aqi.aqi.round()}', style: TextStyle(color: aqiColor, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: aqiColor, borderRadius: BorderRadius.circular(8)),
                child: Text(aqiLabel, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(aqi.personalizedImpact, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.masks_rounded, size: 16, color: Colors.white54),
              const SizedBox(width: 6),
              Expanded(child: Text(aqi.maskAdvisory, style: const TextStyle(color: Colors.white54, fontSize: 11))),
            ],
          ),
          if (aqi.sensitiveGroups.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: aqi.sensitiveGroups.map((g) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                child: Text(g, style: const TextStyle(color: Colors.white70, fontSize: 10)),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOutbreakSection() {
    final criticalOutbreaks = _outbreaks.where((o) => o.isCritical).toList();
    final otherOutbreaks = _outbreaks.where((o) => !o.isCritical).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_rounded, color: const Color(0xFFFF9800), size: 24),
              const SizedBox(width: 8),
              Text('Disease Alerts (${_outbreaks.length})', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          ...criticalOutbreaks.take(2).map((outbreak) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(4)),
                        child: Text(outbreak.advisoryLevel ?? 'Alert', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Text(outbreak.disease, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(outbreak.description, style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (outbreak.precautions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('• ${outbreak.precautions.first}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  ],
                ],
              ),
            ),
          )),
          if (otherOutbreaks.isNotEmpty) ...[
            const Divider(color: Colors.white24),
            Text('Other Alerts', style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ...otherOutbreaks.take(3).map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.orange.shade300),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${o.disease} - ${o.affectedArea}', style: const TextStyle(color: Colors.white60, fontSize: 11))),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label, String dist) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Text(dist, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
      ],
    );
  }

  void _showPharmacyFilterDialog() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.filter_list_rounded, color: Color(0xFF26A69A)),
                  SizedBox(width: 10),
                  Text('Filter Pharmacies by Medicine', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterChip('All', null),
                  _buildFilterChip('ORS', 'ors'),
                  _buildFilterChip('Insulin', 'insulin'),
                  _buildFilterChip('Cardiac', 'cardiac'),
                  _buildFilterChip('Antibiotics', 'antibiotic'),
                  _buildFilterChip('Pain Relief', 'pain'),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String? filterValue) {
    final isSelected = _pharmacyMedicineFilter == (filterValue ?? '');
    return FilterChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12)),
      selected: isSelected,
      onSelected: (selected) {
        Navigator.pop(context);
        setState(() {
          _pharmacyMedicineFilter = filterValue ?? '';
          if (filterValue != null) {
            _pharmacies = _pharmacies.where((p) =>
              p.availableMedicines.any((m) => m.toLowerCase().contains(filterValue.toLowerCase()))
            ).toList();
          }
        });
      },
      backgroundColor: Colors.white10,
      selectedColor: const Color(0xFF26A69A),
      checkmarkColor: Colors.white,
    );
  }

  String _nearestDistLabel(List<EmergencyPlace> places) {
    if (_currentPosition == null || places.isEmpty) return '';
    final n = _nearestPlace(places);
    final km = Geolocator.distanceBetween(
      _currentPosition!.latitude, _currentPosition!.longitude, n.lat, n.lng,
    ) / 1000;
    return '${km.toStringAsFixed(1)} km';
  }

  Future<List<LatLng>> _getRoadRoute(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return [start, end];
      final data = json.decode(res.body);
      if (data is! Map<String, dynamic>) return [start, end];
      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) return [start, end];
      final geometry = routes.first['geometry'];
      if (geometry is! Map<String, dynamic>) return [start, end];
      final coords = geometry['coordinates'];
      if (coords is! List || coords.isEmpty) return [start, end];
      final points = <LatLng>[];
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          points.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
        }
      }
      return points.length > 1 ? points : [start, end];
    } catch (_) {
      return [start, end];
    }
  }

  Future<void> _refreshRoadRoutes() async {
    if (_currentPosition == null) return;
    final start = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    Future<List<LatLng>> buildFor(List<EmergencyPlace> places) async {
      if (places.isEmpty) return [];
      final nearest = _nearestPlace(places);
      return _getRoadRoute(start, LatLng(nearest.lat, nearest.lng));
    }

    final h = await buildFor(_hospitals);
    if (!context.mounted) return;
    setState(() {
      _hospitalRoute = h;
      _offlinePackProgress = math.max(_offlinePackProgress, 0.92);
    });
    await OfflineMapPackService.saveRoutePolylines(hospital: h, crane: const []);
    if (!context.mounted) return;
    final radiusM = _emergencyRadius.round();
    unawaited(OfflineMapPackService.saveLastPackRadiusMeters(radiusM));
    setState(() {
      _offlinePackProgress = 1.0;
      _offlinePackComplete = true;
      _offlinePackJobRunning = false;
      _cachedPackRadiusM = radiusM;
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _MapActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;
  final Color activeColor;

  const _MapActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.activeColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive ? activeColor.withValues(alpha: 0.15) : AppColors.surface.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(color: isActive ? activeColor.withValues(alpha: 0.6) : Colors.white10),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
            ),
            child: Icon(icon, color: isActive ? activeColor : Colors.white70, size: 20),
          ),
        ),
      ),
    );
  }
}
