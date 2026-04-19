import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/situation_brief_service.dart';
import '../theme/app_colors.dart';
import 'ai_advisory_banner.dart';

/// Live-updating card for `sos_incidents.sharedSituationBrief` (AI-generated debrief).
class SharedSituationBriefCard extends StatelessWidget {
  const SharedSituationBriefCard({
    super.key,
    required this.incidentId,
    this.accentColor = const Color(0xFF536DFE),
    this.compact = false,
    this.showRefreshButton = true,
  });

  final String incidentId;
  final Color accentColor;
  final bool compact;
  final bool showRefreshButton;

  static List<String> _stringList(dynamic v) {
    if (v is! List) return [];
    return v.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
  }

  static String? _relativeTime(dynamic v) {
    if (v is! Timestamp) return null;
    final d = v.toDate();
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    return DateFormat.MMMd().add_Hm().format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final id = incidentId.trim();
    if (id.isEmpty) return const SizedBox.shrink();
    final authed = FirebaseAuth.instance.currentUser != null;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sos_incidents').doc(id).snapshots(),
      builder: (context, snap) {
        final raw = snap.data?.data()?['sharedSituationBrief'];
        Map<String, dynamic> brief = {};
        if (raw is Map) {
          brief = Map<String, dynamic>.from(raw);
        }
        final status = (brief['status'] as String?)?.trim() ?? '';
        final summary = (brief['summary'] as String?)?.trim() ?? '';
        final highlights = _stringList(brief['highlights']);
        final actions = _stringList(brief['recommendedActions']);
        final sources = _stringList(brief['sourcesUsed']);
        final lastErr = (brief['lastError'] as String?)?.trim();
        final when = _relativeTime(brief['lastGeneratedAt']);
        final generating = status == 'generating';

        return Container(
          margin: EdgeInsets.only(bottom: compact ? 8 : 12),
          padding: EdgeInsets.all(compact ? 10 : 12),
          decoration: BoxDecoration(
            color: AppColors.slate800,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      'Situation brief',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w700,
                        fontSize: compact ? 12 : 13,
                      ),
                    ),
                  ),
                  Text(
                    'Gemini',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: compact ? 9 : 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (when != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      when,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.38),
                        fontSize: compact ? 9 : 10,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip(
                    generating
                        ? 'Generating…'
                        : status == 'ready'
                            ? 'Ready'
                            : status == 'error'
                                ? 'Error'
                                : 'No brief yet',
                    generating
                        ? Colors.amberAccent
                        : status == 'ready'
                            ? const Color(0xFF7EE787)
                            : status == 'error'
                                ? Colors.redAccent
                                : Colors.white38,
                  ),
                  if (sources.isNotEmpty)
                    for (final s in sources.take(4))
                      _chip(s, Colors.white54),
                ],
              ),
              if (generating) ...[
                const SizedBox(height: 10),
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                  ),
                ),
              ],
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  summary,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: compact ? 11 : 12,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (highlights.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Key findings',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ...highlights.map(
                  (h) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: TextStyle(color: Colors.white38, fontSize: compact ? 11 : 12)),
                        Expanded(
                          child: Text(
                            h,
                            style: TextStyle(color: Colors.white70, fontSize: compact ? 10 : 11, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Recommended actions',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                ...actions.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('– ', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        Expanded(
                          child: Text(
                            a,
                            style: TextStyle(color: Colors.white70, fontSize: compact ? 10 : 11, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (summary.isEmpty && !generating && status != 'error')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Save your on-scene report or add photos — a shared debrief for dispatch will appear here.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: compact ? 10 : 11, height: 1.35),
                  ),
                ),
              if (status == 'error' && lastErr != null && lastErr.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Brief update failed: $lastErr',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 10, height: 1.3),
                  ),
                ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 10),
                AiAdvisoryBanner.brief(dense: compact),
              ],
              if (showRefreshButton && authed) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: generating
                        ? null
                        : () => SituationBriefService.requestGeneration(id, force: true),
                    icon: Icon(Icons.refresh_rounded, size: compact ? 14 : 16, color: accentColor.withValues(alpha: 0.9)),
                    label: Text(
                      summary.isEmpty ? 'Generate brief' : 'Refresh brief',
                      style: TextStyle(fontSize: compact ? 10 : 11, color: accentColor.withValues(alpha: 0.9)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
}
