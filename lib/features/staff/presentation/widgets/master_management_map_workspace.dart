import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../../core/maps/eos_hybrid_map.dart';
import '../../../../core/maps/ops_map_controller.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/google_maps_illustrative_light_style.dart';
import '../../../../core/constants/india_ops_zones.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/fleet_unit_availability.dart';
import '../../../../core/utils/ops_fleet_docs_dedupe.dart';
import '../../../../core/utils/ops_map_markers.dart';
import '../../../../services/fleet_gate_credentials_service.dart';
import '../../../../services/fleet_unit_service.dart';
import '../../../../services/ops_hospital_service.dart';
import '../../domain/admin_panel_access.dart';
import '../admin_volunteers_screen.dart';
import 'command_center_shared_widgets.dart';
import 'fleet_credentials_dialog.dart';
import 'hospital_onboarding_dialog.dart';
import 'hospital_show_credentials_dialog.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

enum _MgmtCategory { fleet, volunteers, hospitals, facility }

/// Management console: map-first fleet & hospital overview with collapsible detail panel.
class MasterManagementMapWorkspace extends StatefulWidget {
  const MasterManagementMapWorkspace({
    super.key,
    required this.access,
    required this.accent,
  });

  final AdminPanelAccess access;
  final Color accent;

  @override
  State<MasterManagementMapWorkspace> createState() =>
      _MasterManagementMapWorkspaceState();
}

class _MasterManagementMapWorkspaceState
    extends State<MasterManagementMapWorkspace> {
  static const double _detailZoom = 16.85;

  final IndiaOpsZone _zone = IndiaOpsZones.lucknow;
  OpsMapController? _mapCtl;

  _MgmtCategory _category = _MgmtCategory.fleet;
  bool _detailPanelOpen = true;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _fleetSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _fleetDocs = [];

  StreamSubscription<List<OpsHospitalRow>>? _hospSub;
  List<OpsHospitalRow> _hospitalRows = [];

  String? _selectedFleetDocId;
  String? _selectedHospitalId;

  final TextEditingController _onboardIdCtrl = TextEditingController();
  final TextEditingController _onboardNameCtrl = TextEditingController();
  final TextEditingController _onboardVicinityCtrl = TextEditingController();

  /// Facility setup: user must tap the map before opening the onboarding dialog.
  bool _onboardingMapPickActive = false;
  LatLng? _onboardingPickedLatLng;

  /// Hospitals: reposition GPS after initial onboarding (orange draft pin).
  bool _editingHospitalLocation = false;
  String? _editLocationHospitalId;
  LatLng? _editLocationDraft;

  @override
  void initState() {
    super.initState();
    unawaited(OpsMapMarkers.preload());
    _fleetSub = FleetUnitService.watchFleetUnits().listen((snap) {
      if (!mounted) return;
      setState(() => _fleetDocs = snap.docs.toList());
    });
    _hospSub = OpsHospitalService.watchHospitals().listen((rows) {
      if (!mounted) return;
      setState(() => _hospitalRows = rows);
    });
  }

  @override
  void dispose() {
    _fleetSub?.cancel();
    _hospSub?.cancel();
    _onboardIdCtrl.dispose();
    _onboardNameCtrl.dispose();
    _onboardVicinityCtrl.dispose();
    _mapCtl?.dispose();
    super.dispose();
  }

  void _clearSelection() {
    setState(() {
      _editingHospitalLocation = false;
      _editLocationHospitalId = null;
      _editLocationDraft = null;
      _selectedFleetDocId = null;
      _selectedHospitalId = null;
    });
  }

  void _cancelEditHospitalLocation() {
    if (!_editingHospitalLocation) return;
    setState(() {
      _editingHospitalLocation = false;
      _editLocationHospitalId = null;
      _editLocationDraft = null;
    });
  }

  void _beginEditHospitalLocation(OpsHospitalRow hosp) {
    final lat = hosp.lat;
    final lng = hosp.lng;
    if (lat == null || lng == null) return;
    if (_onboardingMapPickActive) {
      setState(() {
        _onboardingMapPickActive = false;
        _onboardingPickedLatLng = null;
      });
    }
    setState(() {
      _editingHospitalLocation = true;
      _editLocationHospitalId = hosp.id;
      _editLocationDraft = LatLng(lat, lng);
      _selectedHospitalId = hosp.id;
      _selectedFleetDocId = null;
    });
    unawaited(_focusOn(LatLng(lat, lng)));
  }

  Future<void> _saveEditedHospitalLocation() async {
    final hid = _editLocationHospitalId;
    final pick = _editLocationDraft;
    if (hid == null || pick == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.opsTr('Tap the map to mark the exact hospital location.')),
            backgroundColor: AppColors.slate700,
          ),
        );
      }
      return;
    }
    try {
      await OpsHospitalService.updateMapCoordinates(
        id: hid,
        lat: pick.latitude,
        lng: pick.longitude,
      );
      if (!mounted) return;
      setState(() {
        _editingHospitalLocation = false;
        _editLocationHospitalId = null;
        _editLocationDraft = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.opsTr('Hospital location updated.')),
          backgroundColor: AppColors.slate700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.opsTr('Could not save location.')} $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  void _onCategoryChanged(_MgmtCategory c) {
    setState(() {
      if (_onboardingMapPickActive && c == _MgmtCategory.volunteers) {
        _onboardingMapPickActive = false;
        _onboardingPickedLatLng = null;
      }
      _editingHospitalLocation = false;
      _editLocationHospitalId = null;
      _editLocationDraft = null;
      _category = c;
      _selectedFleetDocId = null;
      _selectedHospitalId = null;
    });
  }

  Future<void> _focusOn(LatLng p) async {
    await _mapCtl?.animateCamera(CameraUpdate.newLatLngZoom(p, _detailZoom));
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _fleetDoc(String? id) {
    if (id == null) return null;
    for (final d in _fleetDocs) {
      if (d.id == id) return d;
    }
    return null;
  }

  OpsHospitalRow? _hospitalRow(String? id) {
    if (id == null) return null;
    for (final r in _hospitalRows) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _fleetDocsInZone() {
    final z = _zone;
    final inZone = _fleetDocs.where((d) {
      final lat = (d.data()['lat'] as num?)?.toDouble();
      final lng = (d.data()['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        return true;
      }
      return z.containsLatLng(LatLng(lat, lng));
    }).toList();

    final out = dedupeFleetDocsByCallSign(inZone);
    return out;
  }

  void _appendFleetMarkers(Set<Marker> out, BitmapDescriptor fbBlue) {
    for (final d in _fleetDocsInZone()) {
      final data = d.data();
      if (!widget.access.isFleetDocVisible(data, d.id)) {
        continue;
      }
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        continue;
      }
      final pos = LatLng(lat, lng);
      final callSign = (data['fleetCallSign'] as String?)?.trim() ?? d.id;
      final sel = _selectedFleetDocId == d.id;
      out.add(
        Marker(
          markerId: MarkerId('mgmt_fleet_${d.id}'),
          position: pos,
          zIndexInt: sel ? 12 : 6,
          icon: OpsMapMarkers.ambulanceOr(fbBlue),
          infoWindow: InfoWindow(
            title: callSign,
            snippet: fleetUnitIsStaffedAvailable(data, d.id)
                ? context.opsTr('Available')
                : (isFleetUnitPlaceholderDoc(d.id)
                    ? context.opsTr('No operator signed in')
                    : context.opsTr('Dispatched / busy')),
          ),
          onTap: () {
            setState(() {
              _editingHospitalLocation = false;
              _editLocationHospitalId = null;
              _editLocationDraft = null;
              _selectedFleetDocId = d.id;
              _selectedHospitalId = null;
            });
            unawaited(_focusOn(pos));
          },
        ),
      );
    }
  }

  void _appendHospitalMarkers(Set<Marker> out, BitmapDescriptor fbBlue) {
    for (final r in _hospitalRows) {
      if (_editingHospitalLocation && _editLocationHospitalId == r.id) {
        continue;
      }
      final lat = r.lat;
      final lng = r.lng;
      if (lat == null || lng == null) {
        continue;
      }
      final pos = LatLng(lat, lng);
      final sel = _selectedHospitalId == r.id;
      out.add(
        Marker(
          markerId: MarkerId('mgmt_hosp_${r.id}'),
          position: pos,
          zIndexInt: sel ? 12 : 6,
          icon: OpsMapMarkers.hospitalOr(fbBlue),
          infoWindow: InfoWindow(title: '${r.id} · ${r.name}', snippet: r.region),
          onTap: () {
            setState(() {
              if (_editingHospitalLocation &&
                  _editLocationHospitalId != null &&
                  _editLocationHospitalId != r.id) {
                _editingHospitalLocation = false;
                _editLocationHospitalId = null;
                _editLocationDraft = null;
              }
              _selectedHospitalId = r.id;
              _selectedFleetDocId = null;
            });
            unawaited(_focusOn(pos));
          },
        ),
      );
    }
  }

  Set<Marker> _buildMarkers() {
    final fbBlue = BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueAzure,
    );
    final out = <Marker>{};
    if (_category == _MgmtCategory.fleet ||
        _category == _MgmtCategory.facility) {
      _appendFleetMarkers(out, fbBlue);
    }
    if (_category == _MgmtCategory.hospitals ||
        _category == _MgmtCategory.facility) {
      _appendHospitalMarkers(out, fbBlue);
    }
    if (_onboardingMapPickActive && _onboardingPickedLatLng != null) {
      final p = _onboardingPickedLatLng!;
      out.add(
        Marker(
          markerId: const MarkerId('mgmt_onboarding_draft'),
          position: p,
          zIndexInt: 20,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: context.opsTr('Hospital location'),
            snippet: context.opsTr('Exact point — saved with onboarding'),
          ),
        ),
      );
    }
    if (_editingHospitalLocation && _editLocationDraft != null) {
      final p = _editLocationDraft!;
      out.add(
        Marker(
          markerId: const MarkerId('mgmt_hospital_location_edit'),
          position: p,
          zIndexInt: 20,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          infoWindow: InfoWindow(
            title: context.opsTr('Hospital location (edit)'),
            snippet: context.opsTr('Tap the map to move the pin, then Save.'),
          ),
        ),
      );
    }
    return out;
  }

  void _cancelOnboardingMapPick() {
    setState(() {
      _onboardingMapPickActive = false;
      _onboardingPickedLatLng = null;
    });
  }

  void _beginOnboardingMapPick() {
    final id = _onboardIdCtrl.text.trim().toUpperCase();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.opsTr('Enter a hospital document ID first.')),
          backgroundColor: AppColors.slate700,
        ),
      );
      return;
    }
    setState(() {
      _editingHospitalLocation = false;
      _editLocationHospitalId = null;
      _editLocationDraft = null;
      _onboardingMapPickActive = true;
      _onboardingPickedLatLng = null;
      _selectedFleetDocId = null;
      _selectedHospitalId = null;
    });
  }

  void _completeOnboardingMapPickAndOpenDialog() {
    final pick = _onboardingPickedLatLng;
    if (pick == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.opsTr('Tap the map to mark the exact hospital location.')),
          backgroundColor: AppColors.slate700,
        ),
      );
      return;
    }
    final id = _onboardIdCtrl.text.trim().toUpperCase();
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    setState(() {
      _onboardingMapPickActive = false;
      _onboardingPickedLatLng = null;
    });
    showDialog<void>(
      context: context,
      builder: (ctx) => HospitalOnboardingDialog(
        hospitalDocId: id,
        hospitalName: _onboardNameCtrl.text.trim().isEmpty
            ? id
            : _onboardNameCtrl.text.trim(),
        hospitalVicinity: _onboardVicinityCtrl.text.trim().isEmpty
            ? '—'
            : _onboardVicinityCtrl.text.trim(),
        adminEmail: email,
        onboardingLatitude: pick.latitude,
        onboardingLongitude: pick.longitude,
      ),
    );
  }

  Widget _chip(_MgmtCategory c, String label, IconData icon) {
    final on = _category == c;
    return Material(
      color: on
          ? widget.accent.withValues(alpha: 0.2)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _onCategoryChanged(c),
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

  InputDecoration _fieldDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
      filled: true,
      fillColor: Colors.black26,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _detailBody() {
    final fleetDoc = _fleetDoc(_selectedFleetDocId);
    final hosp = _hospitalRow(_selectedHospitalId);

    if (_category == _MgmtCategory.facility) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            context.opsTr('Facility setup'),
            style: TextStyle(
              color: widget.accent,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(context.opsTr('Use the left column to enter a hospital document ID and open the onboarding gate. The map shows fleet and hospital pins together so you can sanity-check coverage while you onboard.'), style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
          ),
        ],
      );
    }

    if (fleetDoc != null && _category == _MgmtCategory.fleet) {
      final data = fleetDoc.data();
      final callSign =
          (data['fleetCallSign'] as String?)?.trim() ?? fleetDoc.id;
      final type = (data['vehicleType'] as String?)?.trim() ?? '—';
      final avail = fleetUnitIsStaffedAvailable(data, fleetDoc.id);
      final inc = (data['assignedIncidentId'] as String?)?.trim() ?? '';
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      final station = (data['stationedHospitalId'] as String?)?.trim() ?? '';
      final df = DateFormat.MMMd().add_Hm();
      final updated = data['updatedAt'];
      String updatedStr = '—';
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
          _kv(context.opsTr('Type'), type),
          _kv(
            context.opsTr('Status'),
            avail
                ? context.opsTr('Available')
                : (isFleetUnitPlaceholderDoc(fleetDoc.id)
                    ? context.opsTr('No operator signed in')
                    : context.opsTr('Busy / dispatched')),
          ),
          if (inc.isNotEmpty) _kv(context.opsTr('Incident'), inc),
          if (station.isNotEmpty) _kv(context.opsTr('Stationed at'), station),
          if (lat != null && lng != null)
            _kv(
              context.opsTr('Position'),
              '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
            ),
          _kv(context.opsTr('Updated'), updatedStr),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => FleetCredentialsDialog(
                  fleetCallSign: callSign,
                  vehicleType: type,
                ),
              );
            },
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(context.opsTr('Show credentials')),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: BorderSide(color: widget.accent.withValues(alpha: 0.5)),
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<bool>(
            key: ValueKey<String>('fleet-gate-$callSign'),
            future: FleetGateCredentialsService.gateAccountExists(callSign),
            builder: (context, snap) {
              final hasGate = snap.data ?? false;
              final label =
                  hasGate ? context.opsTr('Reset credentials') : context.opsTr('Get credentials');
              return FilledButton.icon(
                onPressed: snap.connectionState == ConnectionState.waiting
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
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(
                  snap.connectionState == ConnectionState.waiting
                      ? context.opsTr('Credentials…')
                      : label,
                ),
                style: FilledButton.styleFrom(backgroundColor: widget.accent),
              );
            },
          ),
        ],
      );
    }

    if (hosp != null && _category == _MgmtCategory.hospitals) {
      final df = DateFormat.MMMd().add_Hm();
      final note = (hosp.traumaBedsNote ?? '').trim();
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            hosp.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          _kv(context.opsTr('ID'), hosp.id),
          _kv(context.opsTr('Region'), hosp.region),
          _kv(
            context.opsTr('Beds'),
            context
                .opsTr('{available} available / {total} capacity')
                .replaceAll('{available}', '${hosp.bedsAvailable}')
                .replaceAll('{total}', '${hosp.bedsTotal}'),
          ),
          _kv(context.opsTr('Updated'), df.format(hosp.updatedAt.toLocal())),
          if (hosp.lat != null && hosp.lng != null) ...[
            _kv(
              context.opsTr('GPS'),
              '${hosp.lat!.toStringAsFixed(5)}, ${hosp.lng!.toStringAsFixed(5)}',
            ),
            const SizedBox(height: 12),
            if (_editingHospitalLocation && _editLocationHospitalId == hosp.id) ...[
              Text(
                context.opsTr('Move the orange pin on the map, then save.'),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: _cancelEditHospitalLocation,
                    child: Text(context.opsTr('Cancel')),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _saveEditedHospitalLocation,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(context.opsTr('Save location')),
                    style: FilledButton.styleFrom(backgroundColor: widget.accent),
                  ),
                ],
              ),
            ] else
              OutlinedButton.icon(
                onPressed: () => _beginEditHospitalLocation(hosp),
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: Text(context.opsTr('Edit location')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: widget.accent.withValues(alpha: 0.55)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
          ],
          if (hosp.offeredServices.isNotEmpty)
            _kv(context.opsTr('Services'), hosp.offeredServices.take(6).join(', ')),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              note,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (ctx) => HospitalShowCredentialsDialog(
                  hospitalDocId: hosp.id,
                  hospitalName: hosp.name,
                ),
              );
            },
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: Text(context.opsTr('Show credentials')),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () {
              final email = FirebaseAuth.instance.currentUser?.email ?? '';
              showDialog<void>(
                context: context,
                builder: (ctx) => HospitalOnboardingDialog(
                  hospitalDocId: hosp.id,
                  hospitalName: hosp.name,
                  hospitalVicinity: hosp.region,
                  adminEmail: email,
                  alreadyOnboarded: hosp.hasStaffCredentials,
                  onboardingLatitude: hosp.lat,
                  onboardingLongitude: hosp.lng,
                ),
              );
            },
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            label: Text(
              !hosp.hasStaffCredentials
                  ? context.opsTr('Get credentials')
                  : context.opsTr('Reset credentials'),
            ),
            style: FilledButton.styleFrom(backgroundColor: widget.accent),
          ),
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _category == _MgmtCategory.fleet
              ? context.opsTr('Tap a fleet marker or pick a unit in the list to manage it.')
              : _category == _MgmtCategory.hospitals
              ? context.opsTr(
                  'Tap a hospital marker or pick a row in the list for capacity and onboarding.',
                )
              : context.opsTr('Select a category in the left column.'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _sidebarListBody() {
    final df = DateFormat('MMM d HH:mm');
    switch (_category) {
      case _MgmtCategory.fleet:
        final inZone = _fleetDocsInZone();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: Text(
                '${inZone.length} ${inZone.length == 1 ? context.opsTr('unit') : context.opsTr('units')} · ${_zone.label}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
            Expanded(
              child: inZone.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          context.opsTr('No fleet documents in Firestore for this view.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
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
                            (data['assignedIncidentId'] as String?)?.trim() ??
                            '';
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              final lat = (data['lat'] as num?)?.toDouble();
                              final lng = (data['lng'] as num?)?.toDouble();
                              if (lat == null || lng == null) {
                                return;
                              }
                              final pos = LatLng(lat, lng);
                              setState(() {
                                _selectedFleetDocId = d.id;
                                _selectedHospitalId = null;
                              });
                              unawaited(_focusOn(pos));
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
                                              ? context
                                                  .opsTr('Responding · {incident}')
                                                  .replaceAll('{incident}', aid)
                                              : context.opsTr('Standby / available'))
                                        : (isFleetUnitPlaceholderDoc(d.id)
                                              ? context.opsTr('Registered · no operator signed in')
                                              : context.opsTr('Off duty / unavailable')),
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
      case _MgmtCategory.volunteers:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Icon(Icons.groups_rounded, size: 32, color: widget.accent),
            const SizedBox(height: 12),
            Text(context.opsTr('Volunteer console'), style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.opsTr('Approvals and Lookup are open in the main area →'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
        );
      case _MgmtCategory.hospitals:
        if (_hospitalRows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.opsTr('No hospitals in ops_hospitals yet.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          );
        }
        final avail = _hospitalRows.fold<int>(0, (a, r) => a + r.bedsAvailable);
        final cap = _hospitalRows.fold<int>(0, (a, r) => a + r.bedsTotal);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
              child: Text(
                context
                    .opsTr('Live grid · {detail}')
                    .replaceAll('{detail}', '$avail avail / $cap capacity'),
                style: const TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _hospitalRows.length,
                itemBuilder: (_, i) {
                  final r = _hospitalRows[i];
                  final note = (r.traumaBedsNote ?? '').trim();
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final lat = r.lat;
                        final lng = r.lng;
                        setState(() {
                          if (_editingHospitalLocation &&
                              _editLocationHospitalId != null &&
                              _editLocationHospitalId != r.id) {
                            _editingHospitalLocation = false;
                            _editLocationHospitalId = null;
                            _editLocationDraft = null;
                          }
                          _selectedHospitalId = r.id;
                          _selectedFleetDocId = null;
                        });
                        if (lat != null && lng != null) {
                          unawaited(_focusOn(LatLng(lat, lng)));
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
      case _MgmtCategory.facility:
        return Material(
          color: Colors.black.withValues(alpha: 0.22),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            children: [
              Text(
                context.opsTr('Onboard facility'),
                style: TextStyle(
                  color: widget.accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _onboardIdCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _fieldDeco(context.opsTr('Hospital doc ID (ops_hospitals)')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _onboardNameCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _fieldDeco(context.opsTr('Display name')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _onboardVicinityCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _fieldDeco(context.opsTr('City / area')),
              ),
              const SizedBox(height: 8),
              Text(
                context.opsTr(
                  "Next: tap the map at the hospital's exact entrance or ambulance bay, then continue to generate staff credentials.",
                ),
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _beginOnboardingMapPick,
                icon: const Icon(Icons.add_moderator_outlined, size: 18),
                label: Text(context.opsTr('Start onboarding')),
                style: FilledButton.styleFrom(backgroundColor: widget.accent),
              ),
            ],
          ),
        );
    }
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
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
    final markers = _buildMarkers();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _chip(
                            _MgmtCategory.fleet,
                            context.opsTr('Fleet'),
                            Icons.local_shipping_outlined,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _chip(
                            _MgmtCategory.volunteers,
                            context.opsTr('Volunteers'),
                            Icons.groups_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _chip(
                            _MgmtCategory.hospitals,
                            context.opsTr('Hospitals'),
                            Icons.local_hospital_outlined,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _chip(
                            _MgmtCategory.facility,
                            context.opsTr('Facility setup'),
                            Icons.add_business_outlined,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(child: _sidebarListBody()),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Colors.white12),
        Expanded(
          child: _category == _MgmtCategory.volunteers
              ? AdminVolunteersScreen(
                  access: widget.access,
                  embeddedInManagement: true,
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          EosHybridMap(
                            initialCameraPosition:
                                IndiaOpsZones.lucknowCameraPosition(
                                  zoom: _zone.defaultZoom,
                                ),
                            cameraTargetBounds:
                                IndiaOpsZones.lucknowCameraTargetBounds,
                            minMaxZoomPreference: const MinMaxZoomPreference(
                              5.5,
                              18.5,
                            ),
                            markers: markers,
                            mapType: MapType.normal,
                            mapId: AppConstants.googleMapsDarkMapId.isNotEmpty
                                ? AppConstants.googleMapsDarkMapId
                                : null,
                            style: effectiveGoogleMapsEmbeddedStyleJson(),
                            zoomControlsEnabled: false,
                            myLocationButtonEnabled: false,
                            // Panel is a [Row] sibling, not overlaid — extra right padding would double-count width and leave a gap.
                            padding: EdgeInsets.zero,
                            onMapCreated: (c) => _mapCtl = c,
                            onTap: (LatLng pos) {
                              if (_editingHospitalLocation) {
                                if (!_zone.containsLatLng(pos)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context
                                            .opsTr('Tap inside {zone} to place the hospital.')
                                            .replaceAll('{zone}', _zone.label),
                                      ),
                                      backgroundColor: AppColors.slate700,
                                    ),
                                  );
                                  return;
                                }
                                setState(() => _editLocationDraft = pos);
                                unawaited(_focusOn(pos));
                                return;
                              }
                              if (_onboardingMapPickActive) {
                                if (!_zone.containsLatLng(pos)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        context
                                            .opsTr('Tap inside {zone} to place the hospital.')
                                            .replaceAll('{zone}', _zone.label),
                                      ),
                                      backgroundColor: AppColors.slate700,
                                    ),
                                  );
                                  return;
                                }
                                setState(() => _onboardingPickedLatLng = pos);
                                unawaited(_focusOn(pos));
                                return;
                              }
                              if (_category == _MgmtCategory.fleet ||
                                  _category == _MgmtCategory.hospitals ||
                                  _category == _MgmtCategory.facility) {
                                _clearSelection();
                              }
                            },
                          ),
                          if (_editingHospitalLocation)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              child: Material(
                                color: Colors.black.withValues(alpha: 0.78),
                                elevation: 6,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    12,
                                    14,
                                    12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.edit_location_alt_rounded,
                                            color: widget.accent,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              context.opsTr(
                                                'Tap the map to move the pin, then Save.',
                                              ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                height: 1.35,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          TextButton(
                                            onPressed: _cancelEditHospitalLocation,
                                            child: Text(context.opsTr('Cancel')),
                                          ),
                                          const Spacer(),
                                          FilledButton.icon(
                                            onPressed: _saveEditedHospitalLocation,
                                            icon: const Icon(
                                              Icons.save_outlined,
                                              size: 18,
                                            ),
                                            label: Text(context.opsTr('Save location')),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: widget.accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else if (_onboardingMapPickActive)
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              child: Material(
                                color: Colors.black.withValues(alpha: 0.78),
                                elevation: 6,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    12,
                                    14,
                                    12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.touch_app_rounded,
                                            color: widget.accent,
                                            size: 22,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _onboardingPickedLatLng == null
                                                  ? context.opsTr(
                                                      'Tap the map at the exact hospital entrance or main drop-off point.',
                                                    )
                                                  : context.opsTr(
                                                      'Orange pin shows the saved point. Adjust by tapping elsewhere, or continue.',
                                                    ),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                height: 1.35,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          TextButton(
                                            onPressed: _cancelOnboardingMapPick,
                                            child: Text(context.opsTr('Cancel')),
                                          ),
                                          const Spacer(),
                                          FilledButton.icon(
                                            onPressed:
                                                _completeOnboardingMapPickAndOpenDialog,
                                            icon: const Icon(
                                              Icons.arrow_forward_rounded,
                                              size: 18,
                                            ),
                                            label: Text(
                                              context.opsTr('Continue to credentials'),
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: widget.accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    OpsCollapsibleDetailPanel(
                      expanded: _detailPanelOpen,
                      onToggleExpanded: () =>
                          setState(() => _detailPanelOpen = !_detailPanelOpen),
                      accent: widget.accent,
                      body: _detailBody(),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
