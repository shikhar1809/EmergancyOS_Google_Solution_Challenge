import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/text_file_download.dart';
import '../../../services/incident_report_service.dart';
import '../../../services/incident_service.dart';
import '../../../services/ops_incident_hospital_assignment_service.dart';
import '../domain/admin_panel_access.dart';
import 'hospital_live_ops_screen.dart' show liveOpsServiceLabel;
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Hospital console: **Active** pre-arrival triage + **Completed** narrative archive.
class AdminReportsHubScreen extends StatefulWidget {
  const AdminReportsHubScreen({super.key, required this.access});

  final AdminPanelAccess access;

  @override
  State<AdminReportsHubScreen> createState() => _AdminReportsHubScreenState();
}

class _AdminReportsHubScreenState extends State<AdminReportsHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    final startActive = widget.access.role == AdminConsoleRole.medical;
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: startActive ? 0 : 1,
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      primary: false,
      backgroundColor: AppColors.slate900,
      appBar: AppBar(
        backgroundColor: AppColors.slate800,
        title: Text(context.opsTr('Reports')),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.accentBlue,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(text: context.opsTr('Active inbound')),
            Tab(text: context.opsTr('Completed narratives')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ReportsActiveInboundTab(access: widget.access),
          _ReportsCompletedTab(access: widget.access),
        ],
      ),
    );
  }
}

int? _etaMinutesFromString(String? s) {
  if (s == null) return null;
  final m = RegExp(r'(\d+)').firstMatch(s);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

class _ReportsActiveInboundTab extends StatefulWidget {
  const _ReportsActiveInboundTab({required this.access});

  final AdminPanelAccess access;

  @override
  State<_ReportsActiveInboundTab> createState() => _ReportsActiveInboundTabState();
}

class _ReportsActiveInboundTabState extends State<_ReportsActiveInboundTab> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<Map<String, SosIncident>> _loadIncidents(Iterable<String> ids) async {
    final out = <String, SosIncident>{};
    final unique = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    await Future.wait(unique.map((id) async {
      try {
        final s = await FirebaseFirestore.instance.collection('sos_incidents').doc(id).get();
        if (s.exists) {
          out[id] = SosIncident.fromFirestore(s);
        }
      } catch (_) {}
    }));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final hid = (widget.access.boundHospitalDocId ?? '').trim();
    if (hid.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.opsTr('No hospital ID bound — cannot list inbound patients.'),
            style: const TextStyle(color: Colors.white54, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .where('acceptedHospitalId', isEqualTo: hid)
          .limit(40)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('${snap.error}', style: const TextStyle(color: Colors.redAccent)),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
        }
        final open = snap.data!.docs.where((d) {
          final m = d.data();
          final cc = m['consignmentClosedAt'];
          if (cc != null) return false;
          final st = (m['dispatchStatus'] as String?)?.trim() ?? '';
          return st == 'accepted';
        }).toList();

        if (open.isEmpty) {
          return Center(
            child: Text(
              context.opsTr('No inbound patients — your facility is clear.'),
              style: const TextStyle(color: Colors.white54, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          );
        }

        final ids = open.map((d) => OpsIncidentHospitalAssignment.fromFirestore(d).incidentId).toList();
        final key = ids.join('|');

        return FutureBuilder<Map<String, SosIncident>>(
          key: ValueKey(key),
          future: _loadIncidents(ids),
          builder: (context, fut) {
            if (!fut.hasData) {
              return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
            }
            final incMap = fut.data!;

            final rows = <({OpsIncidentHospitalAssignment a, SosIncident? inc})>[];
            for (final d in open) {
              final a = OpsIncidentHospitalAssignment.fromFirestore(d);
              rows.add((a: a, inc: incMap[a.incidentId]));
            }
            rows.sort((x, y) {
              final ex = _etaMinutesFromString(x.inc?.ambulanceEta);
              final ey = _etaMinutesFromString(y.inc?.ambulanceEta);
              if (ex != null && ey != null) return ex.compareTo(ey);
              if (ex != null) return -1;
              if (ey != null) return 1;
              return 0;
            });

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final r = rows[i];
                final a = r.a;
                final inc = r.inc;
                final triage = inc?.triage ?? const <String, dynamic>{};
                final sev = (triage['severity'] ?? triage['triageLevel'] ?? triage['level'])?.toString();

                final acceptedAgo = a.acceptedAt != null
                    ? DateTime.now().difference(a.acceptedAt!)
                    : null;

                return Card(
                  color: AppColors.slate800,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                a.incidentId,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (sev != null && sev.isNotEmpty)
                              Chip(
                                label: Text('Triage: $sev', style: const TextStyle(fontSize: 11)),
                                backgroundColor: Colors.red.withValues(alpha: 0.25),
                                padding: EdgeInsets.zero,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          inc?.type ?? context.opsTr('Loading…'),
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        if (inc != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${context.opsTr('Ambulance ETA')}: ${(inc.ambulanceEta ?? '—').toString()} · '
                            '${context.opsTr('Since accept')}: ${acceptedAgo != null ? '${acceptedAgo.inMinutes}m ${acceptedAgo.inSeconds % 60}s' : '—'}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${context.opsTr('Blood')}: ${inc.bloodType ?? "—"} · '
                            '${context.opsTr('Allergies')}: ${inc.allergies ?? "—"}',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          Text(
                            '${context.opsTr('Conditions')}: ${inc.medicalConditions ?? "—"}',
                            style: const TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          if ((inc.emergencyContactPhone ?? '').trim().isNotEmpty)
                            Text(
                              '${context.opsTr('ICE phone')}: ${inc.emergencyContactPhone!.trim()}',
                              style: const TextStyle(color: Colors.tealAccent, fontSize: 12),
                            ),
                          if (a.requiredServices.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: a.requiredServices
                                  .map(
                                    (s) => Chip(
                                      label: Text(
                                        liveOpsServiceLabel(context, s),
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.white12,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () async {
                                  final t = IncidentReportService.buildTriageHandoffCard(inc);
                                  await Clipboard.setData(ClipboardData(text: t));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(context.opsTr('Triage card copied'))),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: Text(context.opsTr('Copy triage card')),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final pin = inc.liveVictimPin;
                                  final uri = Uri.parse(
                                    'https://www.google.com/maps/search/?api=1&query=${pin.latitude},${pin.longitude}',
                                  );
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                },
                                icon: const Icon(Icons.map, size: 16, color: Colors.white70),
                                label: Text(context.opsTr('Map'), style: const TextStyle(color: Colors.white70)),
                              ),
                            ],
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              context.opsTr('Incident details unavailable (check sos_incidents).'),
                              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

enum _ReportTimeWindow { h24, d7, d30, all }

class _ReportsCompletedTab extends StatefulWidget {
  const _ReportsCompletedTab({required this.access});

  final AdminPanelAccess access;

  @override
  State<_ReportsCompletedTab> createState() => _ReportsCompletedTabState();
}

class _ReportsCompletedTabState extends State<_ReportsCompletedTab> {
  final _search = TextEditingController();
  _ReportTimeWindow _window = _ReportTimeWindow.d7;
  bool _scopeAll = false;
  final Map<String, String?> _hospitalByIncident = {};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<bool> _prefetchHospitalBindings(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    for (final d in docs.take(50)) {
      final data = d.data();
      final rawId = (data['incidentId'] as String?)?.trim() ?? '';
      final fromRef = d.reference.parent.parent?.id;
      final incidentId = rawId.isNotEmpty ? rawId : (fromRef ?? d.id);
      await _acceptedHospitalForIncident(incidentId);
    }
    return true;
  }

  Future<String?> _acceptedHospitalForIncident(String incidentId) async {
    if (_hospitalByIncident.containsKey(incidentId)) {
      return _hospitalByIncident[incidentId];
    }
    try {
      final d = await FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .doc(incidentId)
          .get();
      final hid = (d.data()?['acceptedHospitalId'] as String?)?.trim();
      _hospitalByIncident[incidentId] = hid;
      return hid;
    } catch (_) {
      _hospitalByIncident[incidentId] = null;
      return null;
    }
  }

  bool _inTimeWindow(DateTime? t, _ReportTimeWindow w) {
    if (t == null) return w == _ReportTimeWindow.all;
    final now = DateTime.now();
    switch (w) {
      case _ReportTimeWindow.h24:
        return now.difference(t) <= const Duration(hours: 24);
      case _ReportTimeWindow.d7:
        return now.difference(t) <= const Duration(days: 7);
      case _ReportTimeWindow.d30:
        return now.difference(t) <= const Duration(days: 30);
      case _ReportTimeWindow.all:
        return true;
    }
  }

  Future<void> _runBatchGenerate() async {
    final hid = (widget.access.boundHospitalDocId ?? '').trim();
    if (hid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.opsTr('No hospital ID bound.'))),
      );
      return;
    }
    try {
      List<QueryDocumentSnapshot<Map<String, dynamic>>> archDocs;
      try {
        final arch = await FirebaseFirestore.instance
            .collection('sos_incidents_archive')
            .where('returnHospitalId', isEqualTo: hid)
            .orderBy('timestamp', descending: true)
            .limit(25)
            .get();
        archDocs = arch.docs;
      } catch (_) {
        final broad = await FirebaseFirestore.instance
            .collection('sos_incidents_archive')
            .orderBy('timestamp', descending: true)
            .limit(120)
            .get();
        archDocs = broad.docs.where((d) {
          final v = (d.data()['returnHospitalId'] as String?)?.trim() ?? '';
          return v == hid;
        }).toList();
      }

      if (archDocs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.opsTr('No archived incidents for this return hospital.'))),
          );
        }
        return;
      }

      final todo = <String>[];
      for (final d in archDocs) {
        final id = d.id;
        final sub = await FirebaseFirestore.instance
            .collection('sos_incidents')
            .doc(id)
            .collection('incident_reports')
            .limit(1)
            .get();
        if (sub.docs.isEmpty) todo.add(id);
      }

      if (todo.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.opsTr('All recent archive rows already have reports.'))),
          );
        }
        return;
      }

      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.slate800,
          title: Text(context.opsTr('Generate reports'), style: const TextStyle(color: Colors.white)),
          content: Text(
            context.opsTr('Create {n} missing narrative reports from archive?')
                .replaceAll('{n}', '${todo.length}'),
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.opsTr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(context.opsTr('Generate'))),
          ],
        ),
      );
      if (go != true || !mounted) return;

      var ok = 0;
      for (final id in todo) {
        try {
          final doc = await FirebaseFirestore.instance.collection('sos_incidents_archive').doc(id).get();
          if (!doc.exists) continue;
          final inc = SosIncident.fromFirestore(doc);
          await IncidentReportService.generateAndStoreReport(inc);
          ok++;
        } catch (e) {
          debugPrint('[reports batch] $id: $e');
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.opsTr('Generated {n} reports.').replaceAll('{n}', '$ok'))),
        );
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  void _openDetail(
    BuildContext context, {
    required String incidentId,
    required String narrative,
    required Map<String, dynamic> raw,
  }) {
    final shield = (raw['goodSamaritanShield'] as String?)?.trim() ?? '';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.slate800,
        title: Text(incidentId, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  narrative.isNotEmpty ? narrative : '$raw',
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                if (shield.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24),
                  Text(
                    context.opsTr('Good Samaritan shield'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    shield,
                    style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.35),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final body = narrative.isNotEmpty ? narrative : '$raw';
              await Clipboard.setData(ClipboardData(text: body));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(context.opsTr('Copied'))),
                );
              }
            },
            icon: const Icon(Icons.copy, color: Colors.white70, size: 18),
            label: Text(context.opsTr('Copy'), style: const TextStyle(color: Colors.white70)),
          ),
          TextButton.icon(
            onPressed: () {
              final body = narrative.isNotEmpty ? narrative : '$raw';
              downloadTextFile('report_$incidentId.txt', body);
            },
            icon: const Icon(Icons.download, color: Colors.white70, size: 18),
            label: Text(context.opsTr('Download .txt'), style: const TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.opsTr('Close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hid = (widget.access.boundHospitalDocId ?? '').trim();
    final showScope = widget.access.role == AdminConsoleRole.master;

    return Stack(
      children: [
        Column(
          children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: context.opsTr('Search by incident ID…'),
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: AppColors.slate800,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text(context.opsTr('24h')),
                selected: _window == _ReportTimeWindow.h24,
                onSelected: (_) => setState(() => _window = _ReportTimeWindow.h24),
              ),
              FilterChip(
                label: Text(context.opsTr('7d')),
                selected: _window == _ReportTimeWindow.d7,
                onSelected: (_) => setState(() => _window = _ReportTimeWindow.d7),
              ),
              FilterChip(
                label: Text(context.opsTr('30d')),
                selected: _window == _ReportTimeWindow.d30,
                onSelected: (_) => setState(() => _window = _ReportTimeWindow.d30),
              ),
              FilterChip(
                label: Text(context.opsTr('All')),
                selected: _window == _ReportTimeWindow.all,
                onSelected: (_) => setState(() => _window = _ReportTimeWindow.all),
              ),
              if (showScope) ...[
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(context.opsTr('All facilities')),
                  selected: _scopeAll,
                  onSelected: (_) => setState(() => _scopeAll = true),
                ),
                FilterChip(
                  label: Text(context.opsTr('My hospital')),
                  selected: !_scopeAll,
                  onSelected: (_) => setState(() => _scopeAll = false),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collectionGroup('incident_reports')
                .orderBy('createdAt', descending: true)
                .limit(80)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Text('${snap.error}', style: const TextStyle(color: Colors.redAccent)),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final prefetchKey = snap.data!.docs.take(20).map((e) => e.id).join('|');
              return FutureBuilder<bool>(
                key: ValueKey(prefetchKey),
                future: _prefetchHospitalBindings(snap.data!.docs),
                builder: (context, pref) {
                  if (pref.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final q = _search.text.trim().toLowerCase();
                  final docs = snap.data!.docs.where((d) {
                    final data = d.data();
                    final rawId = (data['incidentId'] as String?)?.trim() ?? '';
                    final fromRef = d.reference.parent.parent?.id;
                    final incidentId =
                        rawId.isNotEmpty ? rawId : (fromRef ?? d.id);
                    if (q.isNotEmpty && !incidentId.toLowerCase().contains(q)) {
                      return false;
                    }
                    final createdAt = data['createdAt'];
                    DateTime? t;
                    if (createdAt is Timestamp) t = createdAt.toDate();
                    if (!_inTimeWindow(t, _window)) return false;

                    if (!_scopeAll && hid.isNotEmpty) {
                      final repHid = (data['acceptedHospitalId'] as String?)?.trim();
                      final assignHid = _hospitalByIncident[incidentId];
                      final match = (repHid != null && repHid == hid) ||
                          (assignHid != null && assignHid == hid);
                      if (!match) return false;
                    }
                    return true;
                  }).toList();

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        context.opsTr('No reports match filters.'),
                        style: const TextStyle(color: Colors.white54),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88, left: 8, right: 8, top: 8),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final data = d.data();
                      final fromRef = d.reference.parent.parent?.id;
                      final rawId = (data['incidentId'] as String?)?.trim() ?? '';
                      final incidentId =
                          rawId.isNotEmpty ? rawId : (fromRef ?? d.id);
                      final narrative = (data['narrative'] as String?)?.trim() ?? '';
                      final preview = narrative.isNotEmpty
                          ? narrative.split('\n').where((s) => s.trim().isNotEmpty).take(3).join('\n')
                          : '';
                      final createdAt = data['createdAt'];
                      DateTime? t;
                      if (createdAt is Timestamp) t = createdAt.toDate();
                      final fmt = DateFormat.MMMd().add_Hm();
                      final rescue = data['rescueDurationSeconds'];
                      final total = data['totalCycleSeconds'];
                      final status = (data['status'] as String?)?.trim() ?? '';

                      return Card(
                        color: AppColors.slate800,
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: ListTile(
                          title: Text(
                            incidentId,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                children: [
                                  if (status.isNotEmpty)
                                    Chip(
                                      label: Text(status, style: const TextStyle(fontSize: 10)),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.blueGrey.withValues(alpha: 0.35),
                                    ),
                                  if (rescue is num)
                                    Chip(
                                      label: Text(
                                        '${context.opsTr('Rescue')}: ${rescue.toInt()}s',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.white12,
                                    ),
                                  if (total is num)
                                    Chip(
                                      label: Text(
                                        '${context.opsTr('Cycle')}: ${total.toInt()}s',
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.white12,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                preview.isNotEmpty ? preview : '—',
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
                              ),
                            ],
                          ),
                          trailing: t != null
                              ? Text(
                                  fmt.format(t.toLocal()),
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                )
                              : null,
                          onTap: () => _openDetail(
                            context,
                            incidentId: incidentId,
                            narrative: narrative,
                            raw: data,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
          ],
        ),
        if (hid.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: _runBatchGenerate,
              backgroundColor: AppColors.accentBlue,
              icon: const Icon(Icons.auto_fix_high),
              label: Text(context.opsTr('Generate missing')),
            ),
          ),
      ],
    );
  }
}
