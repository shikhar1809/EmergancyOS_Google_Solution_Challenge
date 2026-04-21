import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ops_map_markers.dart';
import '../../../core/utils/osrm_route_util.dart';
import '../../../core/widgets/shared_situation_brief_card.dart';
import '../domain/admin_panel_access.dart';
import '../../../services/incident_service.dart';
import '../../../services/fleet_operator_handoff_service.dart';
import '../../../services/ops_hospital_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';
import '../../../core/utils/ems_workflow_labels.dart';

/// Service ids for [OpsHospitalRow.offeredServices] — allocators match incidents to these.
const kLiveOpsServiceIds = <String>[
  'trauma',
  'trauma_support',
  'cardiology',
  'icu',
  'surgery',
  'orthopedics',
  'burns',
  'burn_unit',
  'ent',
  'pediatrics',
  'child_care',
  'blood_bank',
  'blood_availability',
  'neurology',
  'neurosurgery',
  'ventilator_available',
  'dialysis',
  'maternity',
  'cardiac_cathlab',
];

String _notifiedHospitalIdForAction(Map<String, dynamic> d, List<String> hospitalIds) {
  final fromDoc = (d['notifiedHospitalId'] as String?)?.trim();
  if (fromDoc != null && fromDoc.isNotEmpty) return fromDoc;
  if (hospitalIds.isNotEmpty) return hospitalIds.first;
  return '';
}

/// Relative age for UI (e.g. "12m ago"); falls back to full date if older than 24h.
String _acceptedAtDisplayLabel(Timestamp? acceptedAt) {
  if (acceptedAt == null) return '';
  final t = acceptedAt.toDate().toLocal();
  final diff = DateTime.now().difference(t);
  if (diff.isNegative) return DateFormat.MMMd().add_Hm().format(t);
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes.clamp(0, 59);
    return '${m}m ago';
  }
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return DateFormat.MMMd().add_Hm().format(t);
}

String liveOpsServiceLabel(BuildContext context, String id) {
  switch (id) {
    case 'icu':
      return context.opsTr('ICU');
    case 'ent':
      return context.opsTr('ENT');
    case 'blood_bank':
      return context.opsTr('Blood bank');
    case 'trauma_support':
      return context.opsTr('Trauma support');
    case 'child_care':
      return context.opsTr('Child care');
    case 'blood_availability':
      return context.opsTr('Blood availability');
    case 'burn_unit':
      return context.opsTr('Burn unit');
    case 'ventilator_available':
      return context.opsTr('Ventilators');
    case 'cardiac_cathlab':
      return context.opsTr('Cardiac cath lab');
    default:
      if (id.isEmpty) return id;
      return id[0].toUpperCase() + id.substring(1);
  }
}

/// Medical console tab: SOS dispatch alerts, specialties for allocators, map online toggle.
class HospitalLiveOperationsScreen extends StatelessWidget {
  const HospitalLiveOperationsScreen({super.key, required this.access});

  final AdminPanelAccess access;

  @override
  Widget build(BuildContext context) {
    final bound = (access.boundHospitalDocId ?? '').trim();
    final scopeNote = access.role == AdminConsoleRole.medical
        ? (bound.isEmpty
            ? context.opsTr('No hospital ID bound — sign in with a facility document ID.')
            : context.opsTr('Facility {bound}').replaceAll('{bound}', bound))
        : context.opsTr('Medical console only');

    return Scaffold(
      primary: false,
      backgroundColor: AppColors.slate900,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Text(
              context.opsTr('Live Operations'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              scopeNote,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder(
              stream: OpsHospitalService.watchHospitals(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      '${snap.error}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.accentBlue),
                  );
                }
                var rows = snap.data!;
                if (access.role == AdminConsoleRole.medical) {
                  if (bound.isEmpty) {
                    rows = [];
                  } else {
                    rows = rows.where((r) => r.id == bound).toList();
                  }
                }
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      context.opsTr('No hospital rows for your scope.'),
                      style: const TextStyle(color: Colors.white38),
                    ),
                  );
                }
                final hospitalIds = rows.map((r) => r.id).toList();
                final primaryChildren = <Widget>[
                  _HospitalFleetOnCallStrip(hospitalIds: hospitalIds),
                  _IncomingEmergencyAlerts(hospitalIds: hospitalIds),
                  for (final r in rows) ...[
                    HospitalOverviewCapacitySection(
                      hospitalDocId: r.id,
                      initiallyExpanded: true,
                    ),
                    _LiveOperationsFacilityCard(row: r),
                  ],
                ];
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 1100;
                    if (!isWide) {
                      return ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        children: [
                          ...primaryChildren,
                          _AcceptedConsignmentSection(
                            hospitalIds: hospitalIds,
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
                            children: primaryChildren,
                          ),
                        ),
                        Container(
                          width: 1,
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                        SizedBox(
                          width: 360,
                          child: _LiveOpsRightRail(hospitalIds: hospitalIds),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Beds, staffing, blood — for Overview; preserves [OpsHospitalRow.offeredServices] on save.
class HospitalCapacityCard extends StatefulWidget {
  const HospitalCapacityCard({super.key, required this.row});

  final OpsHospitalRow row;

  @override
  State<HospitalCapacityCard> createState() => _HospitalCapacityCardState();
}

class _HospitalCapacityCardState extends State<HospitalCapacityCard> {
  late final TextEditingController _avail;
  late final TextEditingController _total;
  late final TextEditingController _note;
  late final TextEditingController _doctors;
  late final TextEditingController _specialists;
  late final TextEditingController _bloodUnits;
  late bool _hasBloodBank;
  bool _saving = false;

  void _resyncAllFromRow(OpsHospitalRow r) {
    _avail.text = '${r.bedsAvailable}';
    _total.text = '${r.bedsTotal}';
    _note.text = r.traumaBedsNote ?? '';
    _doctors.text = '${r.doctorsOnDuty}';
    _specialists.text = '${r.specialistsOnCall}';
    _bloodUnits.text = '${r.bloodUnitsAvailable}';
    _hasBloodBank = r.hasBloodBank;
  }

  void _applyRemoteFieldPatches(OpsHospitalRow oldR, OpsHospitalRow r) {
    if (oldR.bedsAvailable != r.bedsAvailable) _avail.text = '${r.bedsAvailable}';
    if (oldR.bedsTotal != r.bedsTotal) _total.text = '${r.bedsTotal}';
    if ((oldR.traumaBedsNote ?? '') != (r.traumaBedsNote ?? '')) {
      _note.text = r.traumaBedsNote ?? '';
    }
    if (oldR.doctorsOnDuty != r.doctorsOnDuty) _doctors.text = '${r.doctorsOnDuty}';
    if (oldR.specialistsOnCall != r.specialistsOnCall) {
      _specialists.text = '${r.specialistsOnCall}';
    }
    if (oldR.bloodUnitsAvailable != r.bloodUnitsAvailable) {
      _bloodUnits.text = '${r.bloodUnitsAvailable}';
    }
    if (oldR.hasBloodBank != r.hasBloodBank) _hasBloodBank = r.hasBloodBank;
  }

  @override
  void didUpdateWidget(covariant HospitalCapacityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.id != widget.row.id) {
      _resyncAllFromRow(widget.row);
      return;
    }
    _applyRemoteFieldPatches(oldWidget.row, widget.row);
  }

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _avail = TextEditingController(text: '${r.bedsAvailable}');
    _total = TextEditingController(text: '${r.bedsTotal}');
    _note = TextEditingController(text: r.traumaBedsNote ?? '');
    _doctors = TextEditingController(text: '${r.doctorsOnDuty}');
    _specialists = TextEditingController(text: '${r.specialistsOnCall}');
    _bloodUnits = TextEditingController(text: '${r.bloodUnitsAvailable}');
    _hasBloodBank = r.hasBloodBank;
  }

  @override
  void dispose() {
    _avail.dispose();
    _total.dispose();
    _note.dispose();
    _doctors.dispose();
    _specialists.dispose();
    _bloodUnits.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final a = int.tryParse(_avail.text.trim()) ?? 0;
    final t = int.tryParse(_total.text.trim()) ?? 0;
    final doc = int.tryParse(_doctors.text.trim()) ?? 0;
    final spec = int.tryParse(_specialists.text.trim()) ?? 0;
    final blood = int.tryParse(_bloodUnits.text.trim()) ?? 0;
    final r = widget.row;
    setState(() => _saving = true);
    try {
      await OpsHospitalService.updateLiveOpsFull(
        id: r.id,
        bedsAvailable: a,
        bedsTotal: t,
        traumaBedsNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
        offeredServices: r.offeredServices,
        hasBloodBank: _hasBloodBank,
        doctorsOnDuty: doc,
        specialistsOnCall: spec,
        bloodUnitsAvailable: blood,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.opsTr('Capacity updated'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final df = DateFormat('MMM d, yyyy HH:mm');
    return Card(
      color: const Color(0xFF2D3A4A),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${r.id} · ${r.name}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            Text(
              '${r.region} · last update ${df.format(r.updatedAt.toLocal())}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Text(context.opsTr('Bed capacity'), style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _avail,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _capacityDeco(context.opsTr('Beds available')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _total,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _capacityDeco(context.opsTr('Beds total')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLines: 2,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              decoration: _capacityDeco(context.opsTr('Trauma / capacity notes')),
            ),
            const SizedBox(height: 20),
            Text(context.opsTr('Doctor availability'), style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _doctors,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _capacityDeco(context.opsTr('Doctors on duty')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _specialists,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _capacityDeco(context.opsTr('Specialists on call')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(context.opsTr('Blood bank'), style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bloodUnits,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: _capacityDeco(context.opsTr('Blood units available (approx.)')),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.opsTr('Has blood bank on-site'), style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              value: _hasBloodBank,
              onChanged: (v) => setState(() => _hasBloodBank = v),
              activeThumbColor: AppColors.accentBlue,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(backgroundColor: AppColors.accentBlue),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.opsTr('Save capacity')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _capacityDeco(String hint) => InputDecoration(
        labelText: hint,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF4A5568),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white30),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white70),
        ),
      );
}

/// Expandable block for the medical Overview (command center) body, or inline
/// on Hospital Live Operations (beds sync to Firestore → analytics "My beds").
class HospitalOverviewCapacitySection extends StatelessWidget {
  const HospitalOverviewCapacitySection({
    super.key,
    required this.hospitalDocId,
    this.initiallyExpanded = false,
  });

  final String hospitalDocId;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final id = hospitalDocId.trim();
    if (id.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: StreamBuilder<OpsHospitalRow?>(
        stream: OpsHospitalService.watchHospital(id),
        builder: (context, snap) {
          if (snap.hasError) {
            return Text(
              '${snap.error}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            );
          }
          final row = snap.data;
          if (row == null) {
            return const Padding(
              padding: EdgeInsets.all(8),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accentBlue,
                  ),
                ),
              ),
            );
          }
          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.white24),
            child: ExpansionTile(
              initiallyExpanded: initiallyExpanded,
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white24),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Colors.white24),
              ),
              backgroundColor: const Color(0xFF2D3A4A),
              collapsedBackgroundColor: const Color(0xFF1E293B),
              title: Text(context.opsTr('Hospital capacity & staffing'), style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                context.opsTr(
                  'Beds, staffing, and blood — saved to this facility and reflected in Analytics (My beds).',
                ),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: HospitalCapacityCard(row: row),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LiveOperationsFacilityCard extends StatefulWidget {
  const _LiveOperationsFacilityCard({required this.row});

  final OpsHospitalRow row;

  @override
  State<_LiveOperationsFacilityCard> createState() =>
      _LiveOperationsFacilityCardState();
}

class _LiveOperationsFacilityCardState extends State<_LiveOperationsFacilityCard> {
  late Set<String> _selectedServices;
  late bool _mapListingOnline;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _selectedServices = Set<String>.from(r.offeredServices);
    _mapListingOnline = r.mapListingOnline;
  }

  @override
  void didUpdateWidget(covariant _LiveOperationsFacilityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.id != widget.row.id) {
      _selectedServices = Set<String>.from(widget.row.offeredServices);
      _mapListingOnline = widget.row.mapListingOnline;
      return;
    }
    final r = widget.row;
    if (!listEquals(oldWidget.row.offeredServices, r.offeredServices)) {
      _selectedServices = Set<String>.from(r.offeredServices);
    }
    if (oldWidget.row.mapListingOnline != r.mapListingOnline) {
      _mapListingOnline = r.mapListingOnline;
    }
  }

  Future<void> _saveServices() async {
    setState(() => _saving = true);
    try {
      await OpsHospitalService.updateOfferedServicesOnly(
        id: widget.row.id,
        offeredServices: _selectedServices.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.opsTr('Capabilities saved'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return Card(
      color: AppColors.slate800,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${r.id} · ${r.name}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.opsTr('Public map listing (online)'), style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(context.opsTr('When off, the main grid map shows this hospital as offline.'), style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              value: _mapListingOnline,
              onChanged: (v) async {
                setState(() => _mapListingOnline = v);
                try {
                  await OpsHospitalService.updateMapListingOnline(
                    id: widget.row.id,
                    mapListingOnline: v,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        v ? context.opsTr('Map: online') : context.opsTr('Map: offline'),
                      ),
                    ),
                  );
                } catch (e) {
                  if (mounted) setState(() => _mapListingOnline = !v);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${context.opsTr('Update failed.')} $e'),
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 12),
            Text(context.opsTr('Capabilities for allocators'), style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(context.opsTr('Select specialties this facility can take (e.g. child care / pediatrics for pediatric referrals; cardiology & cath lab for cardiac).'), style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kLiveOpsServiceIds.map((id) {
                final selected = _selectedServices.contains(id);
                return FilterChip(
                  label: Text(liveOpsServiceLabel(context, id)),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _selectedServices.add(id);
                      } else {
                        _selectedServices.remove(id);
                      }
                    });
                  },
                  selectedColor: AppColors.accentBlue.withValues(alpha: 0.35),
                  checkmarkColor: Colors.white,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 11,
                  ),
                  side: BorderSide(
                    color: selected ? AppColors.accentBlue : Colors.white24,
                  ),
                  backgroundColor: AppColors.slate900,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _saveServices,
                style: FilledButton.styleFrom(backgroundColor: AppColors.accentBlue),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(context.opsTr('Save capabilities')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// While a fleet unit has accepted an EMS run for an incident consigned to this hospital,
/// surface **On call** until the response cycle completes (hospital arrival / archive).
class _HospitalFleetOnCallStrip extends StatelessWidget {
  const _HospitalFleetOnCallStrip({required this.hospitalIds});

  final List<String> hospitalIds;

  static String _phaseLabel(BuildContext context, String raw) {
    switch (raw.trim()) {
      case 'inbound':
        return context.opsTr('En route');
      case 'on_scene':
        return context.opsTr('On scene');
      case 'returning':
        return context.opsTr('Returning');
      default:
        return raw.isEmpty ? '—' : raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (hospitalIds.isEmpty) return const SizedBox.shrink();
    final take = hospitalIds.take(10).toList();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .where('acceptedHospitalId', whereIn: take)
          .where('dispatchStatus', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, assignSnap) {
        if (assignSnap.hasError || !assignSnap.hasData) return const SizedBox.shrink();
        final assignIds = assignSnap.data!.docs.map((d) => d.id).toSet();
        if (assignIds.isEmpty) return const SizedBox.shrink();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('sos_incidents').limit(200).snapshots(),
          builder: (context, incSnap) {
            if (!incSnap.hasData) return const SizedBox.shrink();
            final incidents = incSnap.data!.docs.map(SosIncident.fromFirestore).toList();
            final active = incidents.where((i) {
              if (!assignIds.contains(i.id)) return false;
              if ((i.emsAcceptedBy ?? '').trim().isEmpty) return false;
              final ph = (i.emsWorkflowPhase ?? '').trim();
              if (!const {'inbound', 'on_scene', 'returning'}.contains(ph)) return false;
              if (i.status == IncidentStatus.resolved || i.status == IncidentStatus.blocked) return false;
              return true;
            }).toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
            if (active.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.opsTr('Fleet on call (EMS)'),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...active.take(6).map(
                    (i) => _HospitalActiveConsignmentCard(incident: i),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _IncomingEmergencyAlerts extends StatelessWidget {
  const _IncomingEmergencyAlerts({required this.hospitalIds});
  final List<String> hospitalIds;

  @override
  Widget build(BuildContext context) {
    if (hospitalIds.isEmpty) return const SizedBox.shrink();
    // Use a single equality filter (automatically indexed by Firestore) to find
    // all actively incoming alerts globally, then filter for this hospital locally.
    // This avoids needing a composite index which fails silently if missing.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .where('dispatchStatus', isEqualTo: 'pending_acceptance')
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData) {
          if (snap.hasError) debugPrint('Alerts error: ${snap.error}');
          return const SizedBox.shrink();
        }
        
        final validDocs = snap.data!.docs.where((doc) {
          final d = doc.data();
          // Filter locally for the hospital ID
          final hId = (d['notifiedHospitalId'] as String?)?.trim() ?? '';
          if (!hospitalIds.contains(hId)) return false;
          return true;
        }).take(5).toList();

        if (validDocs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: validDocs.map((doc) {
            return _FlashingAlertCard(
              assignmentDoc: doc,
              hospitalIds: hospitalIds,
            );
          }).toList(),
        );
      },
    );
  }
}

class _FlashingAlertCard extends StatefulWidget {
  const _FlashingAlertCard({
    required this.assignmentDoc,
    required this.hospitalIds,
  });
  final QueryDocumentSnapshot<Map<String, dynamic>> assignmentDoc;
  final List<String> hospitalIds;

  @override
  State<_FlashingAlertCard> createState() => _FlashingAlertCardState();
}

class _FlashingAlertCardState extends State<_FlashingAlertCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Timer? _countdownTimer;
  int _secondsLeft = 120;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _startCountdown();
  }

  void _startCountdown() {
    final d = widget.assignmentDoc.data();
    final nt = d['notifiedAt'];
    final windowMs = (d['escalateAfterMs'] as num?)?.toInt() ?? 120000;
    if (nt is Timestamp) {
      final elapsed = DateTime.now().difference(nt.toDate()).inMilliseconds;
      _secondsLeft = ((windowMs - elapsed) / 1000).ceil().clamp(0, 999);
    }
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_secondsLeft > 0) _secondsLeft--;
      });
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    setState(() => _acting = true);
    try {
      final incId = widget.assignmentDoc.id;
      final hospId = _notifiedHospitalIdForAction(widget.assignmentDoc.data(), widget.hospitalIds);
      if (hospId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.opsTr('Missing notified hospital for this assignment.')),
              backgroundColor: AppColors.primaryDanger,
            ),
          );
        }
        return;
      }
      await FirebaseFunctions.instanceFor(region: 'us-east1')
          .httpsCallable('acceptHospitalDispatch')
          .call({'incidentId': incId, 'hospitalId': hospId});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Accept failed: $e'),
            backgroundColor: AppColors.primaryDanger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _refer() async {
    setState(() => _acting = true);
    try {
      final incId = widget.assignmentDoc.id;
      final hospId = _notifiedHospitalIdForAction(widget.assignmentDoc.data(), widget.hospitalIds);
      if (hospId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.opsTr('Missing notified hospital for this assignment.')),
              backgroundColor: AppColors.primaryDanger,
            ),
          );
        }
        return;
      }
      await FirebaseFunctions.instanceFor(region: 'us-east1')
          .httpsCallable('declineHospitalDispatch')
          .call({'incidentId': incId, 'hospitalId': hospId});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refer failed: $e'),
            backgroundColor: AppColors.primaryDanger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  String _formatLocation(dynamic loc) {
    if (loc == null) return '—';
    final lat = loc['latitude'] ?? loc['lat'];
    final lng = loc['longitude'] ?? loc['lng'];
    if (lat == null || lng == null) return '—';
    return '${lat.toString().substring(0, lat.toString().indexOf('.') + 6)}, ${lng.toString().substring(0, lng.toString().indexOf('.') + 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.assignmentDoc.data();
    final incId = widget.assignmentDoc.id;
    final reqSvc = (d['requiredServices'] as List?)?.map((e) => e.toString()).join(', ') ?? '—';
    final mins = _secondsLeft ~/ 60;
    final secs = _secondsLeft % 60;
    final countdown = '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    final emergencyType = (d['type'] as String?)?.trim() ?? '';
    final location = _formatLocation(d['location']);
    final bloodType = (d['bloodType'] as String?)?.trim() ?? '';
    final allergies = (d['allergies'] as String?)?.trim() ?? '';
    final medicalConditions = (d['medicalConditions'] as String?)?.trim() ?? '';
    final emsAcceptedBy = (d['emsAcceptedBy'] as String?)?.trim() ?? '';

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final borderColor = Color.lerp(
          AppColors.primaryDanger,
          Colors.orangeAccent,
          _pulse.value,
        )!;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF5C1A1A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 3),
          ),
          padding: const EdgeInsets.all(14),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_rounded, color: AppColors.primaryDanger, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'INCOMING EMERGENCY',
                  style: TextStyle(
                    color: AppColors.primaryDanger,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _secondsLeft <= 30
                      ? AppColors.primaryDanger.withValues(alpha: 0.3)
                      : Colors.white10,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  countdown,
                  style: TextStyle(
                    color: _secondsLeft <= 30 ? AppColors.primaryDanger : Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Incident: ${incId.length > 20 ? '${incId.substring(0, 18)}...' : incId}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    if (emergencyType.isNotEmpty)
                      Text('Type: $emergencyType', style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Location:', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  Text(location, style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace')),
                ],
              ),
            ],
          ),
          if (bloodType.isNotEmpty || allergies.isNotEmpty || medicalConditions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bloodType.isNotEmpty)
                    Text('Blood: $bloodType', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w700)),
                  if (allergies.isNotEmpty)
                    Text('Allergies: $allergies', style: TextStyle(color: Colors.red.shade300, fontSize: 10)),
                  if (medicalConditions.isNotEmpty)
                    Text('Conditions: $medicalConditions', style: TextStyle(color: Colors.white70, fontSize: 10)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Required services: $reqSvc',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          if (emsAcceptedBy.isNotEmpty)
            Text(
              'EMS Operator: $emsAcceptedBy',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _acting ? null : _accept,
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(context.opsTr('ACCEPT'), style: TextStyle(fontWeight: FontWeight.w900)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _acting ? null : _refer,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text(context.opsTr('REFER'), style: TextStyle(fontWeight: FontWeight.w900)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live EMS phase from `sos_incidents` (same labels as fleet operator strip).
class _ActiveConsignmentHospitalCard extends StatelessWidget {
  const _ActiveConsignmentHospitalCard({required this.assignmentDoc});

  final QueryDocumentSnapshot<Map<String, dynamic>> assignmentDoc;

  @override
  Widget build(BuildContext context) {
    final d = assignmentDoc.data();
    final incId = assignmentDoc.id;
    final hospName = (d['acceptedHospitalName'] as String?)?.trim() ?? '—';
    final hospCode = (d['acceptedHospitalId'] as String?)?.trim() ?? '';
    final acceptedAt = d['acceptedAt'];
    final acceptedLabel = acceptedAt is Timestamp ? _acceptedAtDisplayLabel(acceptedAt) : '';
    final reqSvc = (d['requiredServices'] as List?)?.map((e) => e.toString()).join(', ') ?? '';
    final ambStatus = (d['ambulanceDispatchStatus'] as String?)?.replaceAll('_', ' ') ?? '';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sos_incidents').doc(incId).snapshots(),
      builder: (context, incSnap) {
        final phase = (incSnap.data?.data()?['emsWorkflowPhase'] as String?)?.trim() ?? '';
        final emsLine = phase.isEmpty ? 'Not started' : emsWorkflowPhaseShortLabel(phase);
        return Card(
          color: AppColors.slate800,
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        context.opsTr('ACCEPTED'),
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Incident: ${incId.length > 16 ? '${incId.substring(0, 14)}...' : incId}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Hospital: $hospName',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                if (hospCode.isNotEmpty)
                  Text(
                    'Hospital code: $hospCode',
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                const SizedBox(height: 2),
                Text(
                  'EMS: $emsLine',
                  style: const TextStyle(color: Color(0xFF79C0FF), fontSize: 11, fontWeight: FontWeight.w700),
                ),
                if (reqSvc.isNotEmpty)
                  Text(
                    'Services: $reqSvc',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                if (ambStatus.isNotEmpty)
                  Text(
                    'Ambulance: $ambStatus',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                if (acceptedLabel.isNotEmpty)
                  Text(
                    'Accepted $acceptedLabel',
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Active Consignment card for the "Fleet on call" strip.
///
/// Streams the incident doc live so the phase chip, emergency banner and
/// planned hospital→scene polyline reflect reality. Ops actions (open the
/// operator channel / allot a new fleet) are surfaced inside the emergency
/// banner when the driver has raised an in-run SOS.
class _HospitalActiveConsignmentCard extends StatefulWidget {
  const _HospitalActiveConsignmentCard({required this.incident});

  final SosIncident incident;

  @override
  State<_HospitalActiveConsignmentCard> createState() =>
      _HospitalActiveConsignmentCardState();
}

class _HospitalActiveConsignmentCardState
    extends State<_HospitalActiveConsignmentCard> {
  List<LatLng> _planned = const [];
  LatLng? _routedFrom;
  LatLng? _routedTo;
  bool _routing = false;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    unawaited(OpsMapMarkers.preload());
    _maybeFetchRoute(widget.incident);
  }

  void _maybeFetchRoute(SosIncident inc) {
    final origin = inc.plannedOriginLatLng;
    final scene = inc.liveVictimPin;
    if (origin == null) return;
    if (_routing) return;
    if (_routedFrom != null &&
        _routedTo != null &&
        _sameLatLng(_routedFrom!, origin) &&
        _sameLatLng(_routedTo!, scene)) {
      return;
    }
    _routing = true;
    OsrmRouteUtil.drivingRoute(origin, scene).then((pts) {
      if (!mounted) return;
      setState(() {
        _planned = pts;
        _routedFrom = origin;
        _routedTo = scene;
        _routing = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _routing = false);
    });
  }

  static bool _sameLatLng(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < 1e-6 &&
      (a.longitude - b.longitude).abs() < 1e-6;

  Future<void> _openOperatorChannel(SosIncident inc) async {
    if (_acting) return;
    _acting = true;
    try {
      await IncidentService.acknowledgeFleetEmergency(incidentId: inc.id);
    } catch (_) {}
    if (!mounted) return;
    _acting = false;
    final hId = (inc.returnHospitalId ?? '').trim();
    final q = hId.isEmpty ? '' : '?h=$hId';
    context.push('/fleet-live/operation/${inc.id}$q');
  }

  Future<void> _allotNewFleet(SosIncident inc) async {
    if (_acting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF11181F),
        title: Text(context.opsTr('Allot new fleet?'),
            style: const TextStyle(color: Colors.white)),
        content: Text(
          context.opsTr(
            'The current unit will be released and a fresh ambulance will be dispatched to this incident.',
          ),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.opsTr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.opsTr('Allot new fleet')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _acting = true;
    String? newFleet;
    try {
      newFleet = await IncidentService.reassignFleetForEmergency(
        incidentId: inc.id,
      );
    } catch (_) {}
    _acting = false;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newFleet == null
              ? context.opsTr('No available ambulance found — manual dispatch required.')
              : context.opsTr('Dispatched new ambulance to the incident.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sos_incidents')
          .doc(widget.incident.id)
          .snapshots(),
      builder: (context, snap) {
        final inc = snap.hasData && snap.data!.exists
            ? SosIncident.fromFirestore(snap.data!)
            : widget.incident;
        _maybeFetchRoute(inc);
        return _buildCard(context, inc);
      },
    );
  }

  Widget _buildCard(BuildContext context, SosIncident inc) {
    final phaseRaw = (inc.emsWorkflowPhase ?? '').trim();
    final idShort = inc.id.length > 18 ? '${inc.id.substring(0, 16)}…' : inc.id;
    final emergencyState = (inc.fleetEmergencyState ?? '').trim();
    final emergencyActive =
        emergencyState == 'raised' || emergencyState == 'acknowledged';

    return Card(
      color: emergencyActive
          ? const Color(0xFF2A0F14)
          : const Color(0xFF1C2A3A),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: emergencyActive
              ? Colors.redAccent.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _PhaseChip(phase: phaseRaw),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        idShort,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitleFor(context, inc),
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (inc.bloodType != null && inc.bloodType!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                        child: Text(inc.bloodType!, style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    Text(
                      '${inc.location.latitude.toStringAsFixed(4)}, ${inc.location.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ],
            ),
            if (inc.allergies != null && inc.allergies!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('⚠️ Allergies: ${inc.allergies}', style: TextStyle(color: Colors.red.shade300, fontSize: 10, fontWeight: FontWeight.w600)),
            ],
            if (inc.medicalConditions != null && inc.medicalConditions!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Medical: ${inc.medicalConditions}', style: const TextStyle(color: Colors.white54, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
            if (emergencyActive) ...[
              const SizedBox(height: 10),
              _EmergencyBanner(
                incident: inc,
                onOpenChannel: () => _openOperatorChannel(inc),
                onAllotNewFleet: () => _allotNewFleet(inc),
              ),
            ],
            const SizedBox(height: 10),
            _MiniConsignmentMap(
              incident: inc,
              plannedRoute: _planned,
              emergencyActive: emergencyActive,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HandoffViewButton(incidentId: inc.id),
                OutlinedButton.icon(
                  onPressed: () => _showVictimMedicalRecord(context, inc),
                  icon: const Icon(Icons.medical_information, size: 14, color: Colors.white70),
                  label: const Text('Medical', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showFleetDetails(context, inc),
                  icon: const Icon(Icons.directions_car_rounded, size: 14, color: Colors.white70),
                  label: const Text('Fleet', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showSituationBrief(context, inc.id),
                  icon: const Icon(Icons.summarize_rounded, size: 14, color: Colors.white70),
                  label: const Text('Brief', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _LiveOpsVolunteerSceneSection(incidentId: inc.id),
            const SizedBox(height: 8),
            SharedSituationBriefCard(incidentId: inc.id, compact: true, showRefreshButton: false),
          ],
        ),
      ),
    );
  }

  void _showVictimMedicalRecord(BuildContext context, SosIncident inc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate900,
        title: const Text('Victim Medical Record', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 350,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _infoRow('Name', inc.userDisplayName ?? 'Unknown'),
                _infoRow('Blood Type', inc.bloodType ?? 'Not recorded'),
                _infoRow('Allergies', inc.allergies ?? 'None'),
                _infoRow('Medical Conditions', inc.medicalConditions ?? 'None'),
                _infoRow('Emergency Contact', inc.emergencyContactPhone ?? 'None'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showFleetDetails(BuildContext context, SosIncident inc) {
    if (inc.emsAcceptedBy == null || inc.emsAcceptedBy!.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.slate900,
          title: const Text('Fleet Details', style: TextStyle(color: Colors.white)),
          content: const Text('No fleet operator assigned yet.', style: TextStyle(color: Colors.white70)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate900,
        title: const Text('Fleet Details', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 350,
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('ops_fleet_units').doc(inc.emsAcceptedBy).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snap.data?.data() ?? {};
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _infoRow('Call Sign', (data['fleetCallSign'] as String?) ?? 'Unknown'),
                    _infoRow('Vehicle Type', (data['vehicleType'] as String?) ?? 'Unknown'),
                    _infoRow('Phone', (data['phoneNumber'] as String?) ?? (data['phone'] as String?) ?? 'N/A'),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  void _showSituationBrief(BuildContext context, String incidentId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate900,
        title: const Text('Situation Brief', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 400,
          height: 350,
          child: SharedSituationBriefCard(incidentId: incidentId),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12))),
        ],
      ),
    );
  }

  String _subtitleFor(BuildContext context, SosIncident inc) {
    final ph = _HospitalFleetOnCallStrip._phaseLabel(
        context, inc.emsWorkflowPhase ?? '');
    final type = inc.type.trim();
    return type.isEmpty ? ph : '$ph · $type';
  }
}

class _HandoffViewButton extends StatelessWidget {
  const _HandoffViewButton({required this.incidentId});

  final String incidentId;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _showHandoffDialog(context),
      icon: const Icon(Icons.local_hospital_rounded, size: 14, color: Colors.white70),
      label: const Text('EMS', style: TextStyle(color: Colors.white70, fontSize: 11)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        side: const BorderSide(color: Colors.white24),
      ),
    );
  }

  void _showHandoffDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate900,
        title: const Text('EMS Handoff Report', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 400,
          height: 300,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('sos_incidents')
                .doc(incidentId)
                .collection('fleet_operator_handoff')
                .limit(1)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.hourglass_empty, color: Colors.white38, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'Waiting for fleet operator to submit handoff...',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                );
              }
              final data = docs.first.data() ?? {};
              final notesText = (data['notesText'] as String?) ?? '';
              final v2Data = (data['v2Data'] as Map<String, dynamic>?) ?? {};

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (notesText.isNotEmpty)
                      Text(notesText, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    if (v2Data.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ...v2Data.entries.map((e) {
                        if (e.value == null || e.value.toString().isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 100,
                                child: Text('${e.key}:',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              ),
                              Expanded(
                                child: Text(e.value.toString(),
                                    style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  const _PhaseChip({required this.phase});
  final String phase;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String label;
    switch (phase) {
      case 'inbound':
        bg = const Color(0xFF1F3A58);
        fg = const Color(0xFF79C0FF);
        icon = Icons.navigation_rounded;
        label = context.opsTr('EN ROUTE');
        break;
      case 'on_scene':
        bg = const Color(0xFF3A2A10);
        fg = const Color(0xFFFFB74D);
        icon = Icons.location_on_rounded;
        label = context.opsTr('ON SCENE');
        break;
      case 'returning':
        bg = const Color(0xFF0F3A2A);
        fg = const Color(0xFF4DD0E1);
        icon = Icons.local_hospital_rounded;
        label = context.opsTr('RETURNING');
        break;
      default:
        bg = const Color(0xFF1F2A3A);
        fg = Colors.white70;
        icon = Icons.medical_services_rounded;
        label = phase.isEmpty ? context.opsTr('ON CALL') : phase.toUpperCase();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: fg.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner({
    required this.incident,
    required this.onOpenChannel,
    required this.onAllotNewFleet,
  });

  final SosIncident incident;
  final VoidCallback onOpenChannel;
  final VoidCallback onAllotNewFleet;

  @override
  Widget build(BuildContext context) {
    final state = (incident.fleetEmergencyState ?? '').trim();
    final acked = state == 'acknowledged';
    final cs = (incident.fleetEmergencyRaisedByCallSign ?? '').trim();
    final note = (incident.fleetEmergencyNote ?? '').trim();
    return Container(
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.12),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.priority_high_rounded,
                  color: Colors.redAccent, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  acked
                      ? context.opsTr('Driver SOS · ops on the channel')
                      : context.opsTr('Driver SOS · needs support'),
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          if (cs.isNotEmpty || note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (cs.isNotEmpty) '${context.opsTr('Unit')}: $cs',
                if (note.isNotEmpty) note,
              ].join(' · '),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                onPressed: onOpenChannel,
                icon: const Icon(Icons.headset_mic_rounded, size: 16),
                label: Text(context.opsTr('Open operator channel')),
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
                onPressed: onAllotNewFleet,
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: Text(context.opsTr('Allot new fleet')),
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
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniConsignmentMap extends StatelessWidget {
  const _MiniConsignmentMap({
    required this.incident,
    required this.plannedRoute,
    required this.emergencyActive,
  });

  final SosIncident incident;
  final List<LatLng> plannedRoute;
  final bool emergencyActive;

  String _fmt(double v) => v.toStringAsFixed(5);

  @override
  Widget build(BuildContext context) {
    final origin = incident.plannedOriginLatLng;
    final scene = incident.liveVictimPin;
    final driver = incident.craneLiveLocation;
    final sos = incident.fleetEmergencyLatLng;

    // Approximate straight-line distance hospital → scene (km).
    double? distKm;
    if (origin != null) {
      final dLat = (scene.latitude - origin.latitude) * 111.0;
      final dLng = (scene.longitude - origin.longitude) *
          111.0 *
          (scene.latitude * 3.14159 / 180.0).abs().clamp(0.01, 1.0);
      distKm = (dLat * dLat + dLng * dLng < 0) ? null : ((dLat * dLat + dLng * dLng) == 0 ? 0.0 : (dLat * dLat + dLng * dLng).abs().clamp(0.0, 999999.0));
      if (distKm != null) {
        // Pythagoras in km
        final rawKm = origin != null
            ? ((scene.latitude - origin.latitude) * (scene.latitude - origin.latitude) +
                    (scene.longitude - origin.longitude) * (scene.longitude - origin.longitude))
                .clamp(0, 999999)
                .toDouble()
            : 0.0;
        distKm = rawKm > 0 ? rawKm * 111.0 : 0.0; // rough, good enough for display
      }
    }

    Widget _pin(Color bg, IconData icon, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Icon(icon, color: Colors.white, size: 9),
            ),
            const SizedBox(width: 5),
            Text(label,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: emergencyActive
              ? Colors.redAccent.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Route header ─────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.route_rounded,
                  size: 14, color: Color(0xFF79C0FF)),
              const SizedBox(width: 6),
              const Text(
                'ROUTE',
                style: TextStyle(
                  color: Color(0xFF79C0FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              if (plannedRoute.length >= 2)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF79C0FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${plannedRoute.length} pts',
                    style: const TextStyle(
                        color: Color(0xFF79C0FF),
                        fontSize: 9,
                        fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Pin legend ───────────────────────────────────────────────
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _pin(Colors.redAccent, Icons.personal_injury_rounded,
                  'Scene: ${_fmt(scene.latitude)}, ${_fmt(scene.longitude)}'),
              if (origin != null)
                _pin(const Color(0xFF00BCD4),
                    Icons.local_hospital_rounded,
                    'Hospital: ${_fmt(origin.latitude)}, ${_fmt(origin.longitude)}'),
              if (driver != null)
                _pin(const Color(0xFF1565C0),
                    Icons.airport_shuttle_rounded,
                    'Unit: ${_fmt(driver.latitude)}, ${_fmt(driver.longitude)}'),
              if (emergencyActive && sos != null)
                _pin(Colors.pink.shade700,
                    Icons.warning_amber_rounded,
                    'SOS: ${_fmt(sos.latitude)}, ${_fmt(sos.longitude)}'),
            ],
          ),

          // ── Divider + distance ───────────────────────────────────────
          const SizedBox(height: 8),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.straighten_rounded,
                  size: 12, color: Colors.white38),
              const SizedBox(width: 4),
              Text(
                origin != null
                    ? 'Straight-line: approx ${((scene.latitude - origin.latitude).abs() * 111.0 + (scene.longitude - origin.longitude).abs() * 111.0).toStringAsFixed(1)} km'
                    : 'Origin not set',
                style:
                    const TextStyle(color: Colors.white38, fontSize: 10),
              ),
              if (plannedRoute.length >= 2) ...const [
                SizedBox(width: 8),
                Text('·',
                    style: TextStyle(color: Colors.white24, fontSize: 10)),
                SizedBox(width: 8),
              ],
              if (plannedRoute.length >= 2)
                const Text('OSRM route loaded',
                    style: TextStyle(
                        color: Color(0xFF79C0FF), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

/// **Data surface (vs command center / map):** this rail and [_AcceptedConsignmentSection]
/// only list `ops_incident_hospital_assignments` with `dispatchStatus == accepted` (plus a
/// 1h `acceptedAt` client window). Terminal `failed_to_assist` rows are not queried here.
/// The medical command center instead joins `sos_incidents` with assignments including
/// `failed_to_assist` for status pills; the main map path may run client SOS TTL via
/// [IncidentService.autoArchiveExpiredIncidents].
class _LiveOpsRightRail extends StatelessWidget {
  const _LiveOpsRightRail({required this.hospitalIds});

  final List<String> hospitalIds;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Row(
            children: [
              Icon(
                Icons.local_shipping_outlined,
                size: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                context.opsTr('Active consignments'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        _AcceptedConsignmentSection(
          hospitalIds: hospitalIds,
          showHeader: false,
        ),
      ],
    );
  }
}

class _AcceptedConsignmentSection extends StatelessWidget {
  const _AcceptedConsignmentSection({
    required this.hospitalIds,
    this.showHeader = true,
  });
  final List<String> hospitalIds;
  final bool showHeader;

  static const _activeWindow = Duration(hours: 1);

  static bool _isWithinActiveWindow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final ac = doc.data()['acceptedAt'];
    if (ac is! Timestamp) return false;
    final accepted = ac.toDate();
    return DateTime.now().difference(accepted) <= _activeWindow;
  }

  @override
  Widget build(BuildContext context) {
    if (hospitalIds.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .where('acceptedHospitalId', whereIn: hospitalIds.take(10).toList())
          .where('dispatchStatus', isEqualTo: 'accepted')
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs.where(_isWithinActiveWindow).toList();
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                'No active consignments for ${hospitalIds.length == 1 ? "this hospital" : "these hospitals"}.',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  context.opsTr('Active consignments'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            ...docs
                .take(8)
                .map((doc) => _ActiveConsignmentHospitalCard(assignmentDoc: doc)),
          ],
        );
      },
    );
  }
}

class _LiveOpsVolunteerSceneSection extends StatelessWidget {
  const _LiveOpsVolunteerSceneSection({required this.incidentId});

  final String incidentId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sos_incidents').doc(incidentId).snapshots(),
      builder: (context, snap) {
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.slate800,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.checklist_rounded, color: Colors.white38, size: 12),
                  const SizedBox(width: 6),
                  const Text('── VOLUNTEER SCENE REPORT ──', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                ],
              ),
              const SizedBox(height: 6),
              if (snap.connectionState == ConnectionState.waiting)
                const Row(
                  children: [
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)),
                    SizedBox(width: 8),
                    Text('Loading...', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                )
              else
                _buildReportContent(snap),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReportContent(AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snap) {
    final report = (snap.data?.data()?['volunteerSceneReport'] as Map<String, dynamic>?) ?? {};

    if (report.isEmpty) {
      return const Row(
        children: [
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)),
          SizedBox(width: 8),
          Text('Waiting for volunteer on-scene checklist...', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      );
    }

    final emergencyType = (report['emergencyType'] as String?) ?? '';
    final isBleeding = report['isBleeding'];
    final isTrapped = report['isTrapped'];
    final isConscious = report['isConscious'];
    final breathingStatus = (report['breathingStatus'] as String?) ?? '—';
    final notes = (report['incidentDescription'] as String?) ?? '';
    final photos = (report['photoPaths'] as List?)?.cast<String>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (emergencyType.isNotEmpty)
          Row(
            children: [
              const Icon(Icons.emergency_rounded, color: Colors.amberAccent, size: 12),
              const SizedBox(width: 6),
              Text(
                emergencyType,
                style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _miniChip('Bleeding', _b(isBleeding)),
            _miniChip('Trapped', _b(isTrapped)),
            _miniChip('Conscious', _b(isConscious)),
            _miniChip('Breathing', breathingStatus),
          ],
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(notes, style: const TextStyle(color: Colors.white54, fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Photos: ${photos.length} uploaded', style: const TextStyle(color: Colors.amberAccent, fontSize: 10)),
        ],
      ],
    );
  }

  Widget _miniChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(color: Colors.white54, fontSize: 9),
      ),
    );
  }

  String _b(dynamic v) {
    if (v == null) return '—';
    if (v is bool) return v ? 'Yes' : 'No';
    return v.toString();
  }
}
