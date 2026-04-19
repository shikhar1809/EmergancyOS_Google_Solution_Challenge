import 'dart:async';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'eos_leaflet_map_view.dart';
import 'leaflet_map_runtime.dart';
import '../providers/ops_integration_routing_provider.dart';
import 'maps_leaflet_fallback_provider.dart';
import 'ops_map_controller.dart';

typedef EosMapCreatedCallback = void Function(OpsMapController controller);

/// Drop-in replacement for [GoogleMap]: **Google Maps is always tried first**.
/// OpenStreetMap via [flutter_map] is used only when Google fails (load timeout,
/// `gm_authFailure` on web, or persisted auto-fallback), or when Firestore
/// routing requests Leaflet **and** [ignoreRemoteLeafletTiles] is false.
///
/// Default [ignoreRemoteLeafletTiles] is true so fleet consoles use Google
/// unless this device has activated OSM fallback. Pass `false` on volunteer /
/// home surfaces that should honor `ops_integration_routing.mapsTiles: leaflet`.
class EosHybridMap extends ConsumerStatefulWidget {
  const EosHybridMap({
    super.key,
    required this.initialCameraPosition,
    this.style,
    this.onMapCreated,
    this.gestureRecognizers = const <Factory<OneSequenceGestureRecognizer>>{},
    this.webGestureHandling,
    this.webCameraControlPosition,
    this.webCameraControlEnabled = true,
    this.compassEnabled = true,
    this.mapToolbarEnabled = true,
    this.cameraTargetBounds = CameraTargetBounds.unbounded,
    this.mapType = MapType.normal,
    this.minMaxZoomPreference = MinMaxZoomPreference.unbounded,
    this.rotateGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.zoomControlsEnabled = true,
    this.zoomGesturesEnabled = true,
    this.liteModeEnabled = false,
    this.tiltGesturesEnabled = true,
    this.fortyFiveDegreeImageryEnabled = false,
    this.myLocationEnabled = false,
    this.myLocationButtonEnabled = true,
    this.layoutDirection,
    this.padding = EdgeInsets.zero,
    this.indoorViewEnabled = false,
    this.trafficEnabled = false,
    this.buildingsEnabled = true,
    this.markers = const <Marker>{},
    this.polygons = const <Polygon>{},
    this.polylines = const <Polyline>{},
    this.circles = const <Circle>{},
    this.clusterManagers = const <ClusterManager>{},
    this.heatmaps = const <Heatmap>{},
    this.onCameraMoveStarted,
    this.tileOverlays = const <TileOverlay>{},
    this.groundOverlays = const <GroundOverlay>{},
    this.onCameraMove,
    this.onCameraIdle,
    this.onTap,
    this.onLongPress,
    this.markerType = GoogleMapMarkerType.marker,
    this.colorScheme,
    String? mapId,
    @Deprecated('Use mapId instead.') String? cloudMapId,
    this.googleMapLoadTimeout = const Duration(seconds: 14),
    this.forceGoogleTiles = false,
    this.ignoreRemoteLeafletTiles = true,
  })  : assert(mapId == null || cloudMapId == null),
        mapId = mapId ?? cloudMapId;

  /// When true, always renders Google Maps tiles (ignores Leaflet fallback and remote routing).
  final bool forceGoogleTiles;

  /// Staff ops consoles: ignore Firestore fleet `mapsTiles: leaflet`; use OSM only
  /// when [mapsLeafletFallbackProvider] is true (real Google failure on this device).
  final bool ignoreRemoteLeafletTiles;

  final CameraPosition initialCameraPosition;
  final String? style;
  final EosMapCreatedCallback? onMapCreated;
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;
  final WebGestureHandling? webGestureHandling;
  final WebCameraControlPosition? webCameraControlPosition;
  final bool webCameraControlEnabled;
  final bool compassEnabled;
  final bool mapToolbarEnabled;
  final CameraTargetBounds cameraTargetBounds;
  final MapType mapType;
  final MinMaxZoomPreference minMaxZoomPreference;
  final bool rotateGesturesEnabled;
  final bool scrollGesturesEnabled;
  final bool zoomControlsEnabled;
  final bool zoomGesturesEnabled;
  final bool liteModeEnabled;
  final bool tiltGesturesEnabled;
  final bool fortyFiveDegreeImageryEnabled;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final TextDirection? layoutDirection;
  final EdgeInsets padding;
  final bool indoorViewEnabled;
  final bool trafficEnabled;
  final bool buildingsEnabled;
  final Set<Marker> markers;
  final Set<Polygon> polygons;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final Set<ClusterManager> clusterManagers;
  final Set<Heatmap> heatmaps;
  final VoidCallback? onCameraMoveStarted;
  final Set<TileOverlay> tileOverlays;
  final Set<GroundOverlay> groundOverlays;
  final CameraPositionCallback? onCameraMove;
  final VoidCallback? onCameraIdle;
  final ArgumentCallback<LatLng>? onTap;
  final ArgumentCallback<LatLng>? onLongPress;
  final GoogleMapMarkerType markerType;
  final MapColorScheme? colorScheme;
  final String? mapId;
  final Duration googleMapLoadTimeout;

  @override
  ConsumerState<EosHybridMap> createState() => _EosHybridMapState();
}

class _EosHybridMapState extends ConsumerState<EosHybridMap> {
  Timer? _googleLoadTimer;
  fm.MapController? _leafletController;
  LeafletMapRuntime? _leafletRuntime;
  var _leafletOnCreatedFired = false;

  bool _readUseLeaflet() {
    if (widget.forceGoogleTiles) return false;
    if (widget.ignoreRemoteLeafletTiles) {
      return ref.read(mapsLeafletFallbackProvider);
    }
    return ref.read(effectiveMapsUseLeafletProvider);
  }

  bool _watchUseLeaflet() {
    if (widget.forceGoogleTiles) return false;
    if (widget.ignoreRemoteLeafletTiles) {
      return ref.watch(mapsLeafletFallbackProvider);
    }
    return ref.watch(effectiveMapsUseLeafletProvider);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.forceGoogleTiles || !_readUseLeaflet()) {
        _scheduleGoogleTimer();
      }
    });
  }

  @override
  void dispose() {
    _googleLoadTimer?.cancel();
    _leafletController?.dispose();
    super.dispose();
  }

  void _cancelGoogleTimer() {
    _googleLoadTimer?.cancel();
    _googleLoadTimer = null;
  }

  void _scheduleGoogleTimer() {
    _cancelGoogleTimer();
    _googleLoadTimer = Timer(widget.googleMapLoadTimeout, () {
      if (!mounted) return;
      ref.read(mapsLeafletFallbackProvider.notifier).activateLeaflet('google_map_load_timeout');
    });
  }

  GoogleMap _googleMap() {
    return GoogleMap(
      initialCameraPosition: widget.initialCameraPosition,
      style: widget.style,
      onMapCreated: (GoogleMapController c) {
        _cancelGoogleTimer();
        widget.onMapCreated?.call(OpsMapController.google(c));
      },
      gestureRecognizers: widget.gestureRecognizers,
      webGestureHandling: widget.webGestureHandling,
      webCameraControlPosition: widget.webCameraControlPosition,
      webCameraControlEnabled: widget.webCameraControlEnabled,
      compassEnabled: widget.compassEnabled,
      mapToolbarEnabled: widget.mapToolbarEnabled,
      cameraTargetBounds: widget.cameraTargetBounds,
      mapType: widget.mapType,
      minMaxZoomPreference: widget.minMaxZoomPreference,
      rotateGesturesEnabled: widget.rotateGesturesEnabled,
      scrollGesturesEnabled: widget.scrollGesturesEnabled,
      zoomControlsEnabled: widget.zoomControlsEnabled,
      zoomGesturesEnabled: widget.zoomGesturesEnabled,
      liteModeEnabled: widget.liteModeEnabled,
      tiltGesturesEnabled: widget.tiltGesturesEnabled,
      fortyFiveDegreeImageryEnabled: widget.fortyFiveDegreeImageryEnabled,
      myLocationEnabled: widget.myLocationEnabled,
      myLocationButtonEnabled: widget.myLocationButtonEnabled,
      layoutDirection: widget.layoutDirection,
      padding: widget.padding,
      indoorViewEnabled: widget.indoorViewEnabled,
      trafficEnabled: widget.trafficEnabled,
      buildingsEnabled: widget.buildingsEnabled,
      markers: widget.markers,
      polygons: widget.polygons,
      polylines: widget.polylines,
      circles: widget.circles,
      clusterManagers: widget.clusterManagers,
      heatmaps: widget.heatmaps,
      onCameraMoveStarted: widget.onCameraMoveStarted,
      tileOverlays: widget.tileOverlays,
      groundOverlays: widget.groundOverlays,
      onCameraMove: widget.onCameraMove,
      onCameraIdle: widget.onCameraIdle,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      markerType: widget.markerType,
      colorScheme: widget.colorScheme,
      mapId: widget.mapId,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ignoreRemoteLeafletTiles) {
      ref.listen<bool>(mapsLeafletFallbackProvider, (prev, next) {
        if (widget.forceGoogleTiles) return;
        if (next) _cancelGoogleTimer();
        if (next && mounted) setState(() {});
      });
    } else {
      ref.listen<bool>(effectiveMapsUseLeafletProvider, (prev, next) {
        if (widget.forceGoogleTiles) return;
        if (next) _cancelGoogleTimer();
        if (next && mounted) setState(() {});
      });
    }

    final useLeaflet = _watchUseLeaflet();
    if (useLeaflet) {
      _cancelGoogleTimer();
      _leafletController ??= fm.MapController();
      final init = widget.initialCameraPosition;
      _leafletRuntime ??= LeafletMapRuntime(
        controller: _leafletController!,
        minZoom: widget.minMaxZoomPreference.minZoom ?? 2,
        maxZoom: widget.minMaxZoomPreference.maxZoom ?? 19,
        initialCenter: ll.LatLng(init.target.latitude, init.target.longitude),
        initialZoom: init.zoom,
      );
      return EosLeafletMapView(
        initialCameraPosition: widget.initialCameraPosition,
        mapController: _leafletController!,
        runtime: _leafletRuntime!,
        onReady: () {
          if (_leafletOnCreatedFired) return;
          _leafletOnCreatedFired = true;
          widget.onMapCreated?.call(OpsMapController.leaflet(_leafletRuntime!));
        },
        markers: widget.markers,
        polylines: widget.polylines,
        polygons: widget.polygons,
        circles: widget.circles,
        cameraTargetBounds: widget.cameraTargetBounds,
        minMaxZoomPreference: widget.minMaxZoomPreference,
        padding: widget.padding,
        scrollGesturesEnabled: widget.scrollGesturesEnabled,
        zoomGesturesEnabled: widget.zoomGesturesEnabled,
        rotateGesturesEnabled: widget.rotateGesturesEnabled,
        tiltGesturesEnabled: widget.tiltGesturesEnabled,
        onCameraMove: widget.onCameraMove,
        onTap: widget.onTap,
        zoomControlsEnabled: widget.zoomControlsEnabled,
      );
    }

    return _googleMap();
  }
}
