import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

/// Seven vertical bars: index 0 = oldest day, 6 = today (local calendar days).
class OpsAnalyticsTrendChart extends StatelessWidget {
  const OpsAnalyticsTrendChart({
    super.key,
    required this.counts,
    required this.now,
  });

  final List<int> counts;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (counts.length != 7) {
      return const SizedBox.shrink();
    }
    final maxV = math.max(1, counts.reduce(math.max));
    final dayFmt = DateFormat('EEE');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.slate800.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.opsTr('7-day incident trend (zone)'), style: TextStyle(color: AppColors.accentBlue, fontWeight: FontWeight.w800, fontSize: 10),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${counts[i]}',
                            style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: counts[i] / maxV,
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        AppColors.accentBlue.withValues(alpha: 0.95),
                                        AppColors.accentBlue.withValues(alpha: 0.35),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dayFmt.format(DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - i))),
                            style: const TextStyle(color: Colors.white30, fontSize: 8),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
