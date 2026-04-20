import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/dashboard_l10n.dart';
import '../../../../core/theme/app_colors.dart';

/// Left-rail inbound list + selected assignment detail + avg accept latency
/// for hospital (medical) analytics.
class HospitalAnalyticsInboundRail extends StatelessWidget {
  const HospitalAnalyticsInboundRail({
    super.key,
    required this.hospitalDocId,
    required this.accent,
    required this.selectedIncidentId,
    required this.onSelectIncident,
  });

  final String hospitalDocId;
  final Color accent;
  final String? selectedIncidentId;
  final ValueChanged<String?> onSelectIncident;

  static String _fmtDuration(Duration d) {
    if (d.isNegative) return '—';
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    if (d.inHours < 48) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inDays}d';
  }

  static String? _responseDurationLabel(Map<String, dynamic> m) {
    final notified = m['notifiedAt'];
    final accepted = m['acceptedAt'];
    if (notified is! Timestamp || accepted is! Timestamp) {
      return null;
    }
    final d = accepted.toDate().difference(notified.toDate());
    return _fmtDuration(d);
  }

  static String? _completionDurationLabel(Map<String, dynamic> m, BuildContext context) {
    final accepted = m['acceptedAt'];
    final closed = m['consignmentClosedAt'];
    if (accepted is! Timestamp) return null;
    if (closed is! Timestamp) {
      return context.opsTr('In progress (inbound / active)');
    }
    final d = closed.toDate().difference(accepted.toDate());
    return _fmtDuration(d);
  }

  static double? _avgResponseMinutes(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final samples = <double>[];
    for (final d in docs) {
      final m = d.data();
      final notified = m['notifiedAt'];
      final accepted = m['acceptedAt'];
      if (notified is Timestamp && accepted is Timestamp) {
        samples.add(accepted.toDate().difference(notified.toDate()).inMilliseconds / 60000.0);
      }
    }
    if (samples.isEmpty) return null;
    return samples.reduce((a, b) => a + b) / samples.length;
  }

  @override
  Widget build(BuildContext context) {
    final hid = hospitalDocId.trim();
    if (hid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .where('acceptedHospitalId', isEqualTo: hid)
          .limit(40)
          .snapshots(),
      builder: (context, snap) {
        final raw = snap.data?.docs ?? [];
        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(raw);
        docs.sort((a, b) {
          final aa = a.data()['acceptedAt'];
          final bb = b.data()['acceptedAt'];
          final at = aa is Timestamp ? aa.toDate() : DateTime(1970);
          final bt = bb is Timestamp ? bb.toDate() : DateTime(1970);
          return bt.compareTo(at);
        });

        final active = docs.where((d) => d.data()['consignmentClosedAt'] == null).toList();
        final avgMin = _avgResponseMinutes(docs);
        final df = DateFormat.MMMd().add_Hm();

        QueryDocumentSnapshot<Map<String, dynamic>>? selected;
        if (selectedIncidentId != null) {
          for (final d in docs) {
            if (d.id == selectedIncidentId) {
              selected = d;
              break;
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2D3A4A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_shipping_outlined, color: accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.opsTr('Inbound assignments'),
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (active.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accentBlue.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${active.length}',
                            style: const TextStyle(
                              color: AppColors.accentBlue,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Clear inbound requests',
                        icon: const Icon(Icons.refresh, size: 16),
                        color: Colors.white38,
                        onPressed: () async {
                          // Soft-archive: mark as expired rather than deleting.
                          // This clears the live inbound list while preserving
                          // historical data for analytics / avg-response-time.
                          final batch = FirebaseFirestore.instance.batch();
                          final toExpire = await FirebaseFirestore.instance
                              .collection('ops_incident_hospital_assignments')
                              .where('acceptedHospitalId', isEqualTo: hid)
                              .where('consignmentClosedAt', isNull: true)
                              .get();
                          final now = FieldValue.serverTimestamp();
                          for (final d in toExpire.docs) {
                            batch.update(d.reference, {
                              'dispatchStatus': 'expired',
                              'consignmentClosedAt': now,
                            });
                          }
                          await batch.commit();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (active.isEmpty)
                    Text(
                      context.opsTr('No units currently inbound.'),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    )
                  else
                    Column(
                      children: [
                        for (final d in active.take(8))
                          _InboundPickRow(
                            doc: d,
                            selected: d.id == selectedIncidentId,
                            accent: accent,
                            onTap: () => onSelectIncident(
                              d.id == selectedIncidentId ? null : d.id,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 10),
              _InboundDetailCard(
                doc: selected,
                accent: accent,
                dateFmt: df,
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.opsTr('Avg. hospital response time'),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    avgMin == null
                        ? context.opsTr('Not enough timestamps yet (notify → accept).')
                        : context
                            .opsTr('{min} min average ({n} assignments)')
                            .replaceAll('{min}', avgMin.toStringAsFixed(1))
                            .replaceAll('{n}', '${docs.length}'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.opsTr(
                      'Computed from accepted assignments for this facility (notify → accept).',
                    ),
                    style: const TextStyle(color: Colors.white38, fontSize: 9, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InboundPickRow extends StatelessWidget {
  const _InboundPickRow({
    required this.doc,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final callSign = (data['assignedFleetCallSign'] as String?)?.trim() ?? '—';
    final subtitle = callSign != '—'
        ? context.opsTr('Unit {cs}').replaceAll('{cs}', callSign)
        : doc.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.25) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.directions_car_filled_outlined,
                  size: 16,
                  color: selected ? accent : AppColors.accentBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        doc.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? accent : Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.expand_less : Icons.chevron_right,
                  color: Colors.white30,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InboundDetailCard extends StatelessWidget {
  const _InboundDetailCard({
    required this.doc,
    required this.accent,
    required this.dateFmt,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Color accent;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final lines = <({String k, String v})>[];

    void add(String k, String? v) {
      if (v == null || v.trim().isEmpty) return;
      lines.add((k: k, v: v.trim()));
    }

    add(context.opsTr('Incident'), doc.id);
    final resp = HospitalAnalyticsInboundRail._responseDurationLabel(m);
    add(context.opsTr('Hospital response time'), resp);
    final comp = HospitalAnalyticsInboundRail._completionDurationLabel(m, context);
    add(context.opsTr('Completion time'), comp);

    final disp = (m['ambulanceDispatchStatus'] as String?)?.trim();
    add(context.opsTr('Ambulance dispatch'), disp);

    final acceptedAt = m['acceptedAt'];
    if (acceptedAt is Timestamp) {
      add(context.opsTr('Accepted at'), dateFmt.format(acceptedAt.toDate().toLocal()));
    }
    final notifiedAt = m['notifiedAt'];
    if (notifiedAt is Timestamp) {
      add(context.opsTr('Last notified at'), dateFmt.format(notifiedAt.toDate().toLocal()));
    }
    final ambDisp = m['ambulanceDispatchedAt'];
    if (ambDisp is Timestamp) {
      add(context.opsTr('Ambulance dispatched at'), dateFmt.format(ambDisp.toDate().toLocal()));
    }
    final ambAcc = m['ambulanceAcceptedAt'];
    if (ambAcc is Timestamp) {
      add(context.opsTr('Ambulance crew accepted at'), dateFmt.format(ambAcc.toDate().toLocal()));
    }

    final req = (m['requiredServices'] as List?)?.map((e) => e.toString()).join(', ');
    add(context.opsTr('Required services'), req);

    final noteParts = <String>[];
    final reason = (m['reason'] as String?)?.trim();
    if (reason != null && reason.isNotEmpty) noteParts.add(reason);
    final ccr = (m['consignmentCloseReason'] as String?)?.trim();
    if (ccr != null && ccr.isNotEmpty) noteParts.add(ccr);
    final dispatching = (m['dispatchingHospitalName'] as String?)?.trim();
    if (dispatching != null && dispatching.isNotEmpty) {
      noteParts.add('${context.opsTr('Dispatching hospital')}: $dispatching');
    }
    if (noteParts.isNotEmpty) {
      add(context.opsTr('Notes'), noteParts.join('\n'));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: accent, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.opsTr('Inbound details'),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in lines) ...[
            Text(
              e.k,
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              e.v,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
