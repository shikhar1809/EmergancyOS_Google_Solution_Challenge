import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/google_maps_illustrative_light_style.dart';
import '../../../core/maps/eos_hybrid_map.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/family_alert_service.dart';
import '../../../services/incident_service.dart';

class FamilyTrackerScreen extends StatelessWidget {
  final String incidentId;
  final String? token;

  const FamilyTrackerScreen({
    super.key,
    required this.incidentId,
    this.token,
  });

  bool _tokenMatches(SosIncident inc) {
    final t = (token ?? '').trim();
    final stored = (inc.familyTrackingToken ?? '').trim();
    if (stored.isEmpty || t.isEmpty) return false;
    return stored == t;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Family tracker'),
        backgroundColor: AppColors.surface,
      ),
      body: StreamBuilder<SosIncident>(
        stream: FamilyAlertService.watchIncident(incidentId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData) {
            return const Center(
              child: Text(
                'Incident not found or no longer active.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          final inc = snap.data!;
          if (!_tokenMatches(inc)) {
            return const Center(
              child: Text(
                'Tracking link is invalid or expired.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final dest = inc.ambulanceLiveLocation ?? inc.liveVictimPin;
          final hospital = inc.emsWorkflowPhase == 'inbound'
              ? inc.ambulanceLiveLocation
              : null;

          final status = switch (inc.status) {
            IncidentStatus.pending => 'Waiting for responders',
            IncidentStatus.dispatched => inc.emsWorkflowPhase == 'on_scene'
                ? 'Team is on scene'
                : (inc.emsWorkflowPhase == 'inbound'
                    ? 'Ambulance is en route'
                    : 'Dispatch in progress'),
            IncidentStatus.blocked => 'On hold',
            IncidentStatus.resolved => 'Completed',
          };

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: AppColors.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inc.type,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      style: const TextStyle(
                        color: Colors.lightGreenAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Last updated from responders: '
                      '${inc.ambulanceLiveUpdatedAt ?? inc.lastLocationAt ?? inc.timestamp}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This view is for close family and emergency contacts only. '
                      'Do not share widely to protect privacy.',
                      style: TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: EosHybridMap(
                  ignoreRemoteLeafletTiles: false,
                  initialCameraPosition: CameraPosition(
                    target: dest,
                    zoom: 14,
                  ),
                  mapId: AppConstants.googleMapsDarkMapId.isNotEmpty ? AppConstants.googleMapsDarkMapId : null,
                  style: effectiveGoogleMapsEmbeddedStyleJson(),
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: {
                    Marker(
                      markerId: const MarkerId('scene'),
                      position: inc.liveVictimPin,
                      infoWindow: const InfoWindow(
                        title: 'Incident location',
                      ),
                    ),
                    if (inc.ambulanceLiveLocation != null)
                      Marker(
                        markerId: const MarkerId('ambulance'),
                        position: inc.ambulanceLiveLocation!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure,
                        ),
                        infoWindow: const InfoWindow(
                          title: 'Ambulance',
                        ),
                      ),
                    if (hospital != null)
                      Marker(
                        markerId: const MarkerId('hospital'),
                        position: hospital,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueGreen,
                        ),
                        infoWindow: const InfoWindow(
                          title: 'Hospital',
                        ),
                      ),
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

