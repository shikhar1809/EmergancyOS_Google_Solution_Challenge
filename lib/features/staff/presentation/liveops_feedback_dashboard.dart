import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../domain/admin_panel_access.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

class LiveOpsFeedbackDashboard extends StatefulWidget {
  const LiveOpsFeedbackDashboard({
    super.key,
    required this.access,

    /// When true, omits [Scaffold] and the duplicate title bar — for embedding under Analytics.
    this.embedInParent = false,
  });

  final AdminPanelAccess access;
  final bool embedInParent;

  @override
  State<LiveOpsFeedbackDashboard> createState() =>
      _LiveOpsFeedbackDashboardState();
}

class _LiveOpsFeedbackDashboardState extends State<LiveOpsFeedbackDashboard> {
  final _timeFmt = DateFormat('MMM d, HH:mm');

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPiePanel(
    String title,
    List<PieChartSectionData> sections,
    Map<String, Color> legend,
  ) {
    return Container(
      width: 300,
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: sections.isEmpty
                      ? const Center(
                          child: Text(
                            'No data',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : PieChart(
                          PieChartData(
                            sections: sections,
                            centerSpaceRadius: 24,
                            sectionsSpace: 2,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: legend.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(width: 12, height: 12, color: e.value),
                          const SizedBox(width: 8),
                          Text(
                            e.key,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  final Map<String, Color> _roleColors = {
    'ambulance': Colors.redAccent,
    'volunteer': Colors.green,
    'self': Colors.purpleAccent,
    'other': Colors.grey,
  };

  final Map<String, Color> _outcomeColors = {
    'resolved': Colors.greenAccent,
    'false_alarm': Colors.orangeAccent,
    'unresolved': Colors.redAccent,
  };

  @override
  Widget build(BuildContext context) {
    if (!widget.access.canUseLiveOpsFeedback) {
      return const Scaffold(
        primary: false,
        backgroundColor: AppColors.slate900,
        body: Center(
          child: Text(
            'Access restricted.',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final streamBody = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('incident_feedback')
          .orderBy('createdAt', descending: true)
          .limit(500)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              'Error: ${snap.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accentBlue),
          );
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No feedback received yet.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        int helpfulCount = 0;
        int totalRated = 0;
        double sumRating = 0;
        final roleCounts = <String, int>{};
        final outcomeCounts = <String, int>{};

        for (final d in docs) {
          final data = d.data();
          if (data['helpful'] == true) helpfulCount++;
          if (data['rating'] != null) {
            totalRated++;
            sumRating += (data['rating'] as num).toDouble();
          }

          final role = data['resolvedByRole'] as String?;
          if (role != null && role.isNotEmpty) {
            roleCounts[role] = (roleCounts[role] ?? 0) + 1;
          }

          final outcome = data['outcomeCategory'] as String?;
          if (outcome != null && outcome.isNotEmpty) {
            outcomeCounts[outcome] = (outcomeCounts[outcome] ?? 0) + 1;
          }
        }

        final avgRating = totalRated > 0
            ? (sumRating / totalRated).toStringAsFixed(1)
            : '-';
        final helpfulPct = docs.isNotEmpty
            ? ((helpfulCount / docs.length) * 100).toStringAsFixed(0)
            : '0';

        final roleSections = roleCounts.entries.map((e) {
          return PieChartSectionData(
            color: _roleColors[e.key] ?? Colors.white54,
            value: e.value.toDouble(),
            title: '${e.value}',
            radius: 40,
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }).toList();

        final outcomeSections = outcomeCounts.entries.map((e) {
          return PieChartSectionData(
            color: _outcomeColors[e.key] ?? Colors.white54,
            value: e.value.toDouble(),
            title: '${e.value}',
            radius: 40,
            titleStyle: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }).toList();

        final roleLegend = {
          for (final k in roleCounts.keys)
            k.toUpperCase(): _roleColors[k] ?? Colors.white54,
        };

        final outcomeLegend = {
          for (final k in outcomeCounts.keys)
            k.replaceAll('_', ' ').toUpperCase():
                _outcomeColors[k] ?? Colors.white54,
        };

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _statCard(
                    'Total Feedback',
                    '${docs.length}',
                    Icons.comment,
                    AppColors.accentBlue,
                  ),
                  _statCard(
                    'Helpful %',
                    '$helpfulPct%',
                    Icons.thumb_up,
                    Colors.greenAccent,
                  ),
                  _statCard('Avg Rating', avgRating, Icons.star, Colors.amber),
                ],
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildPiePanel('Resolution Roles', roleSections, roleLegend),
                  _buildPiePanel(
                    'Reported Outcomes',
                    outcomeSections,
                    outcomeLegend,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(context.opsTr('Recent Comments & Reports'), style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    const Divider(color: Colors.white12),
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final ts = data['createdAt'] as Timestamp?;
                  final timeStr = ts != null
                      ? _timeFmt.format(ts.toDate())
                      : 'Unknown time';
                  final comment = data['comment'] as String? ?? '';
                  final rating = data['rating'] as int?;
                  final helpful = data['helpful'] as bool? ?? false;

                  if (comment.isEmpty && rating == null)
                    return const SizedBox.shrink();

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        if (rating != null) ...[
                          Text(
                            '$rating ★',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Icon(
                          helpful ? Icons.thumb_up : Icons.thumb_down,
                          color: helpful ? Colors.green : Colors.redAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Inc: ${data['incidentId']?.substring(0, 8) ?? 'Unknown'}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    subtitle: comment.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              comment,
                              style: const TextStyle(color: Colors.white),
                            ),
                          )
                        : null,
                  );
                },
              ),
            ],
          ),
        );
      },
    );

    if (widget.embedInParent) {
      return ColoredBox(color: AppColors.slate900, child: streamBody);
    }

    return Scaffold(
      primary: false,
      backgroundColor: AppColors.slate900,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: AppColors.slate800,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.feedback_outlined,
                    color: AppColors.accentBlue,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Community Post-Incident Feedback',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          'Metrics & Comments from resolved SOS cases',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: streamBody),
        ],
      ),
    );
  }
}
