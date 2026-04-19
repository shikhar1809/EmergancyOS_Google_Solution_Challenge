import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/google_maps_illustrative_light_style.dart';
import '../../../core/maps/eos_hybrid_map.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/incident_service.dart';
import '../../../services/ops_support_service.dart';
import '../domain/admin_panel_access.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Master-console tabs: live picture, lifecycle/audit export, data quality, support tools.
class AdminOpsDeskScreen extends StatefulWidget {
  const AdminOpsDeskScreen({super.key, required this.access});

  final AdminPanelAccess access;

  @override
  State<AdminOpsDeskScreen> createState() => _AdminOpsDeskScreenState();
}

class _AdminOpsDeskScreenState extends State<AdminOpsDeskScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _auditIncidentId = TextEditingController();
  final _supportUid = TextEditingController();
  final _supportEmail = TextEditingController();
  Map<String, dynamic>? _digest;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _auditIncidentId.dispose();
    _supportUid.dispose();
    _supportEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.access.role != AdminConsoleRole.master) {
      return const Center(
        child: Text('Ops desk is limited to master role in this build.',
            style: TextStyle(color: Colors.white70)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppColors.slate800,
          child: TabBar(
            controller: _tabs,
            labelColor: AppColors.accentBlue,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(text: 'Live ops'),
              Tab(text: 'Lifecycle & audit'),
              Tab(text: 'Data quality'),
              Tab(text: 'Support'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              const _LiveOpsTab(),
              _LifecycleAuditTab(initialController: _auditIncidentId),
              const _DataQualityTab(),
              _SupportTab(
                uidCtrl: _supportUid,
                emailCtrl: _supportEmail,
                digest: _digest,
                onDigest: (m) => setState(() => _digest = m),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const p = 0.017453292519943295;
  final a = 0.5 -
      math.cos((lat2 - lat1) * p) / 2 +
      math.cos(lat1 * p) * math.cos(lat2 * p) * (1 - math.cos((lon2 - lon1) * p)) / 2;
  return 12742 * math.asin(math.sqrt(a));
}

class _LiveOpsTab extends StatelessWidget {
  const _LiveOpsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sos_incidents')
          .where('status', whereIn: ['pending', 'dispatched', 'blocked'])
          .limit(80)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('${snap.error}', style: const TextStyle(color: Colors.redAccent)));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accentBlue));
        }
        final docs = snap.data!.docs;
        final incidents = docs.map(SosIncident.fromFirestore).toList();
        final activeSos = incidents.length;

        final ackSeconds = <double>[];
        for (final i in incidents) {
          final a = i.firstAcknowledgedAt;
          if (a != null) {
            ackSeconds.add(a.difference(i.timestamp).inSeconds.toDouble());
          }
        }
        final avgAck = ackSeconds.isEmpty
            ? null
            : ackSeconds.reduce((a, b) => a + b) / ackSeconds.length;

        final zones = <String, int>{};
        for (final i in incidents) {
          final k =
              '${i.location.latitude.toStringAsFixed(2)}_${i.location.longitude.toStringAsFixed(2)}';
          zones[k] = (zones[k] ?? 0) + 1;
        }
        final hot = zones.entries.where((e) => e.value > 1).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metricCard('Active SOS (open list)', '$activeSos'),
                _metricCard(
                  'Avg. time to first ack',
                  avgAck == null ? '—' : '${avgAck.round()} s',
                ),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('ptt_channels').limit(200).snapshots(),
                  builder: (context, pttSnap) {
                    final n = pttSnap.data?.docs.length ?? 0;
                    return _metricCard('PTT channel roots (≤200 sample)', '$n');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(context.opsTr('Hot zones (rounded lat/lng, count > 1)'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (hot.isEmpty)
              Text(context.opsTr('No duplicate grid cells in current sample.'), style: TextStyle(color: Colors.white54, fontSize: 12))
            else
              ...hot.take(8).map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${e.key.replaceAll('_', ', ')} → ${e.value} open',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                  ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: EosHybridMap(
                  initialCameraPosition: CameraPosition(
                    target: incidents.isEmpty
                        ? const LatLng(26.85, 80.95)
                        : LatLng(
                            incidents.first.location.latitude,
                            incidents.first.location.longitude,
                          ),
                    zoom: incidents.length <= 1 ? 11.5 : 9,
                  ),
                  mapId: AppConstants.googleMapsDarkMapId.isNotEmpty ? AppConstants.googleMapsDarkMapId : null,
                  style: effectiveGoogleMapsEmbeddedStyleJson(),
                  markers: {
                    for (final i in incidents)
                      Marker(
                        markerId: MarkerId(i.id),
                        position: i.location,
                        infoWindow: InfoWindow(title: i.type, snippet: i.lifecyclePhaseLabel),
                      ),
                  },
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget _metricCard(String title, String value) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _LifecycleAuditTab extends StatefulWidget {
  const _LifecycleAuditTab({required this.initialController});

  final TextEditingController initialController;

  @override
  State<_LifecycleAuditTab> createState() => _LifecycleAuditTabState();
}

class _LifecycleAuditTabState extends State<_LifecycleAuditTab> {
  late final TextEditingController _c;
  String _streamId = '';

  static String _fmt(dynamic v) {
    if (v == null) return '';
    if (v is Timestamp) return DateFormat.yMMMd().add_Hms().format(v.toDate().toLocal());
    return v.toString();
  }

  @override
  void initState() {
    super.initState();
    _c = widget.initialController;
  }

  Future<void> _exportAudit(BuildContext context, String incidentId) async {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    final lines = <String>['at,actorUid,action,fromStatus,toStatus,note'];
    final snap =
        await FirebaseFirestore.instance.collection('sos_incidents').doc(id).collection('audit_log').get();
    for (final d in snap.docs) {
      final m = d.data();
      lines.add([
        _fmt(m['at']),
        m['actorUid'] ?? '',
        m['action'] ?? '',
        m['fromStatus'] ?? '',
        m['toStatus'] ?? '',
        (m['note'] ?? '').toString().replaceAll(',', ';'),
      ].join(','));
    }
    final csv = lines.join('\n');
    await Clipboard.setData(ClipboardData(text: csv));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Copied ${snap.docs.length} audit rows for $id')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(context.opsTr('Lifecycle phases in-app: Open (pending) → Assigned (dispatched) / Blocked → archived as Closed.'), style: TextStyle(color: Colors.white70, height: 1.35),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _c,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: context.opsTr('Incident ID'),
            labelStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: AppColors.slate800,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton(
              onPressed: () => setState(() => _streamId = _c.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: AppColors.slate700),
              child: Text(context.opsTr('Apply / stream')),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: () => _exportAudit(context, _c.text),
              icon: const Icon(Icons.copy_rounded),
              label: Text(context.opsTr('Copy audit CSV')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentBlue),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(context.opsTr('Live audit log'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (_streamId.isEmpty)
          Text(context.opsTr('Enter an incident id and tap Apply / stream.'), style: TextStyle(color: Colors.white38))
        else
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('sos_incidents')
                .doc(_streamId)
                .collection('audit_log')
                .orderBy('at', descending: true)
                .limit(80)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(color: AppColors.accentBlue)),
                );
              }
              if (snap.hasError) {
                return Text('${snap.error}', style: const TextStyle(color: Colors.redAccent));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Text(context.opsTr('No audit rows yet.'), style: TextStyle(color: Colors.white54));
              }
              return Column(
                children: [
                  for (final d in docs)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.slate800,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${d.data()['action'] ?? ''}  ${_fmt(d.data()['at'])}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          Text(
                            'actor: ${d.data()['actorUid'] ?? ''}  '
                            '${d.data()['fromStatus'] ?? ''} → ${d.data()['toStatus'] ?? ''}',
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                          if ((d.data()['note'] ?? '').toString().isNotEmpty)
                            Text(d.data()['note'].toString(),
                                style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _DataQualityTab extends StatefulWidget {
  const _DataQualityTab();

  @override
  State<_DataQualityTab> createState() => _DataQualityTabState();
}

class _DataQualityTabState extends State<_DataQualityTab> {
  bool _loading = false;
  String _report = '';

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _report = '';
    });
    try {
      final active = await FirebaseFirestore.instance
          .collection('sos_incidents')
          .where('status', whereIn: ['pending', 'dispatched', 'blocked'])
          .limit(100)
          .get();
      final archived =
          await FirebaseFirestore.instance.collection('sos_incidents_archive').limit(100).get();

      final buf = StringBuffer();
      int badGps = 0;
      final pairs = <List<SosIncident>>[];

      void scan(QuerySnapshot<Map<String, dynamic>> snap) {
        final list = snap.docs.map(SosIncident.fromFirestore).toList();
        for (final i in list) {
          final lat = i.location.latitude;
          final lng = i.location.longitude;
          if (lat.abs() < 0.02 && lng.abs() < 0.02) badGps++;
        }
        for (var a = 0; a < list.length; a++) {
          for (var b = a + 1; b < list.length; b++) {
            final x = list[a];
            final y = list[b];
            final km = _haversineKm(
              x.location.latitude,
              x.location.longitude,
              y.location.latitude,
              y.location.longitude,
            );
            final dt = x.timestamp.difference(y.timestamp).inMinutes.abs();
            if (km < 0.25 && dt < 20) {
              pairs.add([x, y]);
            }
          }
        }
      }

      scan(active);
      scan(archived);

      buf.writeln('Sample: ${active.docs.length} active + ${archived.docs.length} archived (each ≤100).');
      buf.writeln('Suspicious GPS near (0,0): $badGps');
      buf.writeln('Possible duplicate pairs (≤250m & ≤20min apart): ${pairs.length}');
      for (var i = 0; i < pairs.length && i < 12; i++) {
        final p = pairs[i];
        buf.writeln(' — ${p[0].id} / ${p[1].id}');
      }

      final met =
          await FirebaseFirestore.instance.collection('ops_health_metrics').doc('counters').get();
      if (met.exists && met.data() != null) {
        buf.writeln('\nBackend counters (Cloud Functions):');
        met.data()!.forEach((k, v) => buf.writeln(' $k: $v'));
      } else {
        buf.writeln('\nNo ops_health_metrics/counters yet (deploy functions & dispatch SOS).');
      }

      setState(() => _report = buf.toString());
    } catch (e) {
      setState(() => _report = 'Error: $e');
    } finally {
      if (context.mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: _loading ? null : _run,
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.analytics_outlined),
          label: Text(context.opsTr('Run checks')),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentBlue),
        ),
        const SizedBox(height: 16),
        SelectableText(_report.isEmpty ? 'Tap “Run checks”.' : _report,
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
      ],
    );
  }
}

class _SupportTab extends StatelessWidget {
  const _SupportTab({
    required this.uidCtrl,
    required this.emailCtrl,
    required this.digest,
    required this.onDigest,
  });

  final TextEditingController uidCtrl;
  final TextEditingController emailCtrl;
  final Map<String, dynamic>? digest;
  final void Function(Map<String, dynamic>?) onDigest;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Privacy-safe lookup: email is masked. Force sign-out sets a flag on the user doc; '
          'the main app signs out on next snapshot (demo — use admin claims in production).',
          style: TextStyle(color: Colors.white54, height: 1.35, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: uidCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: context.opsTr('User UID'),
            labelStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: AppColors.slate800,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: emailCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: context.opsTr('Email (exact match)'),
            labelStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: AppColors.slate800,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            try {
              final m = await OpsSupportService.userDigest(
                uid: uidCtrl.text.trim().isNotEmpty ? uidCtrl.text.trim() : null,
                email: emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null,
              );
              onDigest(m);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
              }
            }
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentBlue),
          child: Text(context.opsTr('Lookup')),
        ),
        if (digest != null) ...[
          const SizedBox(height: 20),
          SelectableText(JsonEncoder.withIndent('  ').convert(digest!),
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace')),
          const SizedBox(height: 12),
          if (digest!['found'] == true && (digest!['uid'] ?? '').toString().isNotEmpty) ...[
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: () async {
                final uid = digest!['uid'].toString();
                try {
                  await OpsSupportService.forceSignOutUser(uid);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Force sign-out written for $uid')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
              child: Text(context.opsTr('Force sign-out user')),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () async {
                final id = (digest!['lastActiveIncidentId'] ?? '').toString().trim();
                final path = id.isEmpty
                    ? '/master-dashboard'
                    : '/master-dashboard?focus=${Uri.encodeComponent(id)}';
                await Clipboard.setData(ClipboardData(text: path));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied deep link: $path')),
                  );
                }
              },
              child: Text(context.opsTr('Copy ops dashboard deep link (focus last incident)')),
            ),
          ],
        ],
      ],
    );
  }
}
