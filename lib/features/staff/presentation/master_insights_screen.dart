import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/india_ops_zones.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ai_advisory_banner.dart';
import '../../../core/utils/fleet_unit_availability.dart';
import '../../../services/fleet_unit_service.dart';
import '../../../services/incident_service.dart';
import '../../../services/ops_hospital_service.dart';
import '../../../services/ops_lifeline_analytics_chat.dart';
import '../domain/admin_panel_access.dart';
import '../navigation/ops_admin_routes.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

class MasterInsightsScreen extends StatefulWidget {
  const MasterInsightsScreen({super.key, required this.access});

  final AdminPanelAccess access;

  @override
  State<MasterInsightsScreen> createState() => _MasterInsightsScreenState();
}

class _InsightMsg {
  const _InsightMsg(this.isUser, this.text);
  final bool isUser;
  final String text;
}

class _MasterInsightsScreenState extends State<MasterInsightsScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <_InsightMsg>[];
  bool _loading = false;
  IndiaOpsZone _zone = IndiaOpsZones.lucknow;
  static const _scenarioHint =
      'Master Insights console — admin requests narrative reports and KPIs from live SOS analytics. '
      'Answer with clear sections, numbers from the digest when possible, and state uncertainty. '
      'For every incident you mention, include a line exactly: Incident: <incidentId> '
      '(use the real Firestore id from the digest, e.g. H-LKO-18 or UUID).';

  static final _incidentLineRe = RegExp(
    r'Incident:\s*([A-Za-z0-9\-]+)',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _msgs.add(
      _InsightMsg(
        false,
        'Ask for **structured briefs** on any ops zone. The strip above shows live pressure; '
        'quick prompts produce **actionable** output with `Incident: <id>` lines you can tap to open in Live Ops.\n\n'
        'Data comes from live `sos_incidents` + digest — **not** a substitute for 112.',
      ),
    );
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('insights_chat_v1_$uid');
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>?;
      if (list == null || list.isEmpty) return;
      final restored = <_InsightMsg>[];
      for (final e in list) {
        if (e is Map && e['t'] is String && e['u'] is bool) {
          restored.add(_InsightMsg(e['u'] as bool, e['t'] as String));
        }
      }
      if (restored.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(restored);
      });
      _scrollToEnd();
    } catch (_) {}
  }

  Future<void> _persistSession() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final list = _msgs
          .map((m) => <String, dynamic>{'u': m.isUser, 't': m.text})
          .toList();
      await p.setString('insights_chat_v1_$uid', jsonEncode(list));
    } catch (_) {}
  }

  Future<void> _clearSession() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('insights_chat_v1_$uid');
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _msgs
        ..clear()
        ..add(
          _InsightMsg(
            false,
            'Session cleared. Use the pressure strip and quick prompts to build a fresh brief.',
          ),
        );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<Map<String, String>> _historyBeforeLatest() {
    final hist = <Map<String, String>>[];
    for (var i = 0; i < _msgs.length - 1; i++) {
      final m = _msgs[i];
      hist.add({'role': m.isUser ? 'user' : 'model', 'text': m.text});
    }
    return hist;
  }

  Set<String> _incidentIdsInText(String text) {
    final out = <String>{};
    for (final m in _incidentLineRe.allMatches(text)) {
      final id = m.group(1)?.trim();
      if (id != null && id.isNotEmpty) out.add(id);
    }
    return out;
  }

  void _openIncidentInLiveOps(String incidentId) {
    final id = incidentId.trim();
    if (id.isEmpty) return;
    final path = OpsAdminRoutes.pathForRole(widget.access.role);
    context.go('$path?focus=${Uri.encodeComponent(id)}&dock=live');
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _msgs.add(_InsightMsg(true, t));
      _ctrl.clear();
    });
    unawaited(_persistSession());
    _scrollToEnd();
    try {
      final reply = await OpsLifelineAnalyticsChat.send(
        message: t,
        zone: _zone,
        history: _historyBeforeLatest(),
        scenario: _MasterInsightsScreenState._scenarioHint,
        analyticsMode: true,
      );
      if (mounted) {
        setState(() => _msgs.add(_InsightMsg(false, reply)));
        if (t.toLowerCase().contains('shift handoff')) {
          await Clipboard.setData(ClipboardData(text: reply));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.opsTr('Shift handoff copied to clipboard'))),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _msgs.add(_InsightMsg(false, 'Could not generate report: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToEnd();
      unawaited(_persistSession());
    }
  }

  Future<void> _quick(String prompt) async {
    await _send(prompt);
  }

  Future<void> _shareViaEmail(String body) async {
    final subject = Uri.encodeComponent('EmergencyOS ops brief — ${_zone.label}');
    final b = Uri.encodeComponent(body.length > 1800 ? '${body.substring(0, 1800)}…' : body);
    final uri = Uri.parse('mailto:?subject=$subject&body=$b');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await Clipboard.setData(ClipboardData(text: body));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Copied to clipboard (email app unavailable).')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      primary: false,
      backgroundColor: AppColors.slate900,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.insights_rounded, color: AppColors.accentBlue, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Insights',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.opsTr(
                          'Live pressure + AI briefs for the selected zone — tap KPI tiles to steer prompts, '
                          'then open incidents from chips.',
                        ),
                        style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.35),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _loading ? null : _clearSession,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white54),
                  label: Text(context.opsTr('Clear chat'), style: const TextStyle(color: Colors.white70)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: AiAdvisoryBanner.analytics(dense: true),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(context.opsTr('Zone:'), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<IndiaOpsZone>(
                    // ignore: deprecated_member_use
                    value: _zone,
                    dropdownColor: AppColors.slate800,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.slate800,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      for (final z in IndiaOpsZones.all)
                        DropdownMenuItem(value: z, child: Text(z.label)),
                    ],
                    onChanged: _loading
                        ? null
                        : (z) {
                            if (z == null) return;
                            setState(() => _zone = z);
                          },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _OpsPressureStrip(
            zone: _zone,
            onTileTap: (label, detail) {
              _send(
                '[$label] $detail\n\n'
                'Using digest data for ${_zone.label}, give a **3-bullet executive brief** plus '
                'numbered actions. Use lines starting with `Incident: <id>` for each affected incident.',
              );
            },
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: Text(context.opsTr('SLA breach & oldest open'), style: const TextStyle(fontSize: 11)),
                  onPressed: _loading
                      ? null
                      : () => _quick(
                            'For ${_zone.label}: list **open incidents breaching a 90s acknowledgement SLA** '
                            '(or closest to breach). Order by age. For each line start with `Incident: <id>`. '
                            'Add one-line recommended next action (dispatch / hospital / volunteer).',
                          ),
                ),
                ActionChip(
                  label: Text(context.opsTr('Pre-stage & hotspots'), style: const TextStyle(fontSize: 11)),
                  onPressed: _loading
                      ? null
                      : () => _quick(
                            'For ${_zone.label}: **pre-stage ambulances** recommendation from 48h hex hotspots + '
                            'which hospital catchment is hottest. Reference digest hotspot summaries. '
                            'When citing incidents use `Incident: <id>` lines.',
                          ),
                ),
                ActionChip(
                  label: Text(context.opsTr('Shift handoff brief'), style: const TextStyle(fontSize: 11)),
                  onPressed: _loading
                      ? null
                      : () => _quick(
                            'For ${_zone.label}: produce a **shift handoff brief** — active load, fleet posture, '
                            'hospital bed risk, top 3 risks, top 3 wins. Plain markdown, copy-ready.',
                          ),
                ),
                ActionChip(
                  label: Text(context.opsTr('Bottleneck analysis'), style: const TextStyle(fontSize: 11)),
                  onPressed: _loading
                      ? null
                      : () => _quick(
                            'For ${_zone.label}: **bottleneck analysis** — EMS lifecycle stalls vs hospital accept '
                            'delay vs volunteer coverage. Cite digest numbers; end with 3 prioritized fixes.',
                          ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _msgs.length,
                        itemBuilder: (_, i) {
                          final m = _msgs[i];
                          final ids = !m.isUser ? _incidentIdsInText(m.text) : <String>{};
                          return Align(
                            alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: const BoxConstraints(maxWidth: 620),
                              decoration: BoxDecoration(
                                color: m.isUser
                                    ? AppColors.accentBlue.withValues(alpha: 0.22)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    m.text,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      fontSize: 13,
                                      height: 1.45,
                                    ),
                                  ),
                                  if (!m.isUser) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        IconButton(
                                          tooltip: context.opsTr('Copy'),
                                          icon: const Icon(Icons.copy, size: 18, color: Colors.white54),
                                          onPressed: () async {
                                            await Clipboard.setData(ClipboardData(text: m.text));
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text(context.opsTr('Copied'))),
                                              );
                                            }
                                          },
                                        ),
                                        IconButton(
                                          tooltip: context.opsTr('Share via email'),
                                          icon: const Icon(Icons.outgoing_mail, size: 18, color: Colors.white54),
                                          onPressed: () => _shareViaEmail(m.text),
                                        ),
                                        for (final id in ids)
                                          ActionChip(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                            label: Text(id, style: const TextStyle(fontSize: 11)),
                                            onPressed: () => _openIncidentInLiveOps(id),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_loading) const LinearProgressIndicator(minHeight: 2),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              minLines: 1,
                              maxLines: 5,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: context.opsTr(
                                  'e.g. Summarize fleet + hospital pressure for tonight…',
                                ),
                                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                                filled: true,
                                fillColor: Colors.black26,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onSubmitted: (_) => _send(_ctrl.text),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _loading ? null : () => _send(_ctrl.text),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accentBlue,
                              padding: const EdgeInsets.all(14),
                            ),
                            child: const Icon(Icons.send_rounded, size: 22),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// Live KPI strip: zone-filtered incidents, hospitals, fleet.
class _OpsPressureStrip extends StatelessWidget {
  const _OpsPressureStrip({
    required this.zone,
    required this.onTileTap,
  });

  final IndiaOpsZone zone;
  final void Function(String label, String detail) onTileTap;

  static bool _activeSos(SosIncident e) =>
      e.status == IncidentStatus.pending ||
      e.status == IncidentStatus.dispatched ||
      e.status == IncidentStatus.blocked;

  static Duration? _oldestPendingAge(List<SosIncident> inZone) {
    final pending = inZone.where((e) => e.status == IncidentStatus.pending).toList();
    if (pending.isEmpty) return null;
    pending.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final oldest = pending.first;
    return DateTime.now().difference(oldest.timestamp);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('sos_incidents').limit(400).snapshots(),
        builder: (context, snapInc) {
          final incDocs = snapInc.data?.docs ?? const [];
          final incidents = incDocs.map(SosIncident.fromFirestore).where((e) {
            if (OpsLifelineAnalyticsChat.excludeTrainingIncident(e)) return false;
            return zone.containsLatLng(e.liveVictimPin);
          }).toList();

          final active = incidents.where(_activeSos).length;
          final oldest = _oldestPendingAge(incidents);
          final oldestLabel = oldest == null
              ? context.opsTr('None')
              : '${oldest.inMinutes}m ${(oldest.inSeconds % 60)}s';

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('ops_hospitals').snapshots(),
            builder: (context, snapH) {
              final rows = snapH.data?.docs.map(OpsHospitalRow.fromFirestore).toList() ?? [];
              final inZoneH = rows.where((h) {
                if (h.lat == null || h.lng == null) return false;
                return zone.containsLatLng(LatLng(h.lat!, h.lng!));
              }).toList();
              final atRisk = inZoneH.where((h) => h.bedsAvailable < 3 || !h.mapListingOnline).length;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FleetUnitService.watchFleetUnits(),
                builder: (context, snapF) {
                  var free = 0;
                  for (final d in snapF.data?.docs ?? const []) {
                    if (!fleetDocIsStaffedAvailable(d)) continue;
                    final lat = (d.data()['lat'] as num?)?.toDouble();
                    final lng = (d.data()['lng'] as num?)?.toDouble();
                    if (lat == null || lng == null) continue;
                    if (!zone.containsLatLng(LatLng(lat, lng))) continue;
                    final aid = (d.data()['assignedIncidentId'] as String?)?.trim() ?? '';
                    if (aid.isEmpty) free++;
                  }

                  Widget tile(String title, String value, Color accent, String detail) {
                    return Expanded(
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onTileTap(title, detail),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(color: Colors.white54, fontSize: 10, height: 1.2),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  value,
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final warn = oldest != null && oldest > const Duration(seconds: 90);

                  return Row(
                    children: [
                      tile(
                        context.opsTr('Active SOS'),
                        '$active',
                        AppColors.accentBlue,
                        'There are $active active SOS incidents in ${zone.label} right now.',
                      ),
                      const SizedBox(width: 8),
                      tile(
                        context.opsTr('Oldest pending'),
                        oldestLabel,
                        warn ? Colors.redAccent : Colors.white70,
                        oldest == null
                            ? 'No pending incidents in this zone.'
                            : 'Oldest pending incident has been waiting $oldestLabel.',
                      ),
                      const SizedBox(width: 8),
                      tile(
                        context.opsTr('Hospitals at risk'),
                        '$atRisk',
                        atRisk > 0 ? Colors.orangeAccent : Colors.white70,
                        '$atRisk hospitals in-zone have low beds or map offline.',
                      ),
                      const SizedBox(width: 8),
                      tile(
                        context.opsTr('Fleet free'),
                        '$free',
                        Colors.tealAccent,
                        '$free staffed available units in-zone with no assigned incident.',
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
