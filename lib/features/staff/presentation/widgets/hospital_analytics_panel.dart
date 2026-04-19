import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/ops_hospital_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

class HospitalAnalyticsPanel extends StatelessWidget {
  const HospitalAnalyticsPanel({
    super.key,
    required this.hospitals,
    this.isMasterView = false,
    this.boundHospitalId,
  });

  final List<OpsHospitalRow> hospitals;
  final bool isMasterView;
  final String? boundHospitalId;

  @override
  Widget build(BuildContext context) {
    final filtered = boundHospitalId != null
        ? hospitals.where((h) => h.id == boundHospitalId).toList()
        : hospitals;

    if (filtered.isEmpty) {
      return _buildEmptyState(context);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 20),
          if (isMasterView) _buildMasterSummary(context, filtered),
          if (!isMasterView && filtered.length == 1) ...[
            _buildHospitalDetail(filtered.first),
            const SizedBox(height: 20),
            _buildCapacityGauge(context, filtered.first),
            const SizedBox(height: 20),
            if (filtered.first.offeredServices.isNotEmpty)
              _buildServiceList(context, filtered.first.offeredServices),
            const SizedBox(height: 20),
            _buildStaffOverview(context, filtered.first),
          ],
          if (!isMasterView && filtered.length > 1)
            _buildHospitalList(filtered),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.slate800.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          const Icon(Icons.local_hospital, color: Colors.white24, size: 40),
          const SizedBox(height: 12),
          Text(
            context.opsTr('No hospital data available'),
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.accentBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          isMasterView ? 'HOSPITAL NETWORK' : 'FACILITY STATUS',
          style: const TextStyle(
            color: AppColors.accentBlue,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${hospitals.length} facilities',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildMasterSummary(BuildContext context, List<OpsHospitalRow> hospitals) {
    final totalBeds = hospitals.fold<int>(0, (sum, h) => sum + h.bedsTotal);
    final availBeds = hospitals.fold<int>(0, (sum, h) => sum + h.bedsAvailable);
    final totalDocs = hospitals.fold<int>(0, (sum, h) => sum + h.doctorsOnDuty);
    final totalSpecs = hospitals.fold<int>(
      0,
      (sum, h) => sum + h.specialistsOnCall,
    );
    final bloodBanks = hospitals.where((h) => h.hasBloodBank).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('NETWORK OVERVIEW'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.bed,
                label: 'Available / Total',
                value: '$availBeds / $totalBeds',
                color: AppColors.accentBlue,
                progress: totalBeds > 0 ? availBeds / totalBeds : 0,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                icon: Icons.medical_services,
                label: 'Doctors on Duty',
                value: '$totalDocs',
                color: Colors.greenAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                icon: Icons.science,
                label: 'Specialists on Call',
                value: '$totalSpecs',
                color: Colors.amberAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                icon: Icons.bloodtype,
                label: 'Blood Banks',
                value: '$bloodBanks',
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildOccupancyOverview(context, hospitals),
        const SizedBox(height: 20),
        _buildServiceBreakdown(hospitals),
      ],
    );
  }

  Widget _buildOccupancyOverview(BuildContext context, List<OpsHospitalRow> hospitals) {
    final occupancyValues = hospitals
        .where((h) => h.bedsTotal > 0)
        .map((h) => (h.bedsTotal - h.bedsAvailable) / h.bedsTotal)
        .toList();

    final avgOccupancy = occupancyValues.isEmpty
        ? 0.0
        : occupancyValues.reduce((a, b) => a + b) / occupancyValues.length;

    final criticalCount = hospitals
        .where(
          (h) =>
              h.bedsTotal > 0 &&
              ((h.bedsTotal - h.bedsAvailable) / h.bedsTotal) > 0.85,
        )
        .length;

    final warningCount = hospitals
        .where(
          (h) =>
              h.bedsTotal > 0 &&
              ((h.bedsTotal - h.bedsAvailable) / h.bedsTotal) > 0.7 &&
              ((h.bedsTotal - h.bedsAvailable) / h.bedsTotal) <= 0.85,
        )
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slate900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.opsTr('NETWORK OCCUPANCY'), style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildOccupancyGauge(avgOccupancy, showLabel: true),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOccupancyBadge(
                    '$criticalCount',
                    'Critical',
                    Colors.redAccent,
                  ),
                  const SizedBox(height: 6),
                  _buildOccupancyBadge(
                    '$warningCount',
                    'Warning',
                    Colors.amberAccent,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOccupancyBadge(String count, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$count $label',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildOccupancyGauge(double percent, {bool showLabel = false}) {
    final color = percent > 0.85
        ? Colors.redAccent
        : percent > 0.7
        ? Colors.amberAccent
        : Colors.greenAccent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          Text(
            '${(percent * 100).round()}%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Avg. occupancy',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 0,
                  centerSpaceRadius: 20,
                  sections: [
                    PieChartSectionData(
                      value: percent * 100,
                      color: color,
                      radius: 8,
                      showTitle: false,
                    ),
                    PieChartSectionData(
                      value: (1 - percent) * 100,
                      color: Colors.white.withValues(alpha: 0.08),
                      radius: 8,
                      showTitle: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServiceBreakdown(List<OpsHospitalRow> hospitals) {
    final serviceCounts = <String, int>{};
    for (final h in hospitals) {
      for (final s in h.offeredServices) {
        serviceCounts[s] = (serviceCounts[s] ?? 0) + 1;
      }
    }

    final sorted = serviceCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('SERVICE COVERAGE'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sorted.take(10).map((e) {
            final percent = (e.value / hospitals.length * 100).round();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.accentBlue.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.key,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentBlue.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$percent%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: AppColors.accentBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildHospitalDetail(OpsHospitalRow h) {
    final occupancy = h.bedsTotal > 0
        ? (h.bedsTotal - h.bedsAvailable) / h.bedsTotal
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      h.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${h.id}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(occupancy),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(double occupancy) {
    final color = occupancy > 0.85
        ? Colors.redAccent
        : occupancy > 0.7
        ? Colors.amberAccent
        : Colors.greenAccent;
    final label = occupancy > 0.85
        ? 'Critical'
        : occupancy > 0.7
        ? 'Warning'
        : 'Normal';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            occupancy > 0.85 ? Icons.warning_rounded : Icons.check_circle,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityGauge(BuildContext context, OpsHospitalRow h) {
    final used = h.bedsTotal - h.bedsAvailable;
    final percent = h.bedsTotal > 0 ? used / h.bedsTotal : 0.0;
    final color = percent > 0.85
        ? Colors.redAccent
        : percent > 0.7
        ? Colors.amberAccent
        : Colors.greenAccent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.slate900,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.opsTr('BED OCCUPANCY'), style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(percent * 100).round()}%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 32,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$used of ${h.bedsTotal} occupied',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 0,
                    centerSpaceRadius: 28,
                    sections: [
                      PieChartSectionData(
                        value: percent * 100,
                        color: color,
                        radius: 10,
                        showTitle: false,
                      ),
                      PieChartSectionData(
                        value: (1 - percent) * 100,
                        color: Colors.white.withValues(alpha: 0.08),
                        radius: 10,
                        showTitle: false,
                      ),
                    ],
                  ),
                ),
                Icon(
                  percent > 0.85 ? Icons.warning_rounded : Icons.check_circle,
                  color: color,
                  size: 24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffOverview(BuildContext context, OpsHospitalRow h) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slate900,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.opsTr('STAFFING'), style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStaffItem(
                  Icons.medical_services,
                  'Doctors',
                  '${h.doctorsOnDuty}',
                ),
              ),
              Expanded(
                child: _buildStaffItem(
                  Icons.science,
                  'Specialists',
                  '${h.specialistsOnCall}',
                ),
              ),
              Expanded(
                child: _buildStaffItem(
                  Icons.local_hospital,
                  'Beds',
                  '${h.bedsAvailable}/${h.bedsTotal}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStaffItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: AppColors.accentBlue, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildServiceList(BuildContext context, List<String> services) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slate900,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.opsTr('AVAILABLE SERVICES'), style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: services.map((s) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  s,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHospitalList(List<OpsHospitalRow> hospitals) {
    return Column(
      children: [
        _buildSectionHeader('ALL FACILITIES'),
        const SizedBox(height: 12),
        ...hospitals.map(
          (h) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _HospitalStatusCard(hospital: h, compact: true),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.progress,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HospitalStatusCard extends StatelessWidget {
  const _HospitalStatusCard({required this.hospital, this.compact = false});

  final OpsHospitalRow hospital;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final occupancy = hospital.bedsTotal > 0
        ? (hospital.bedsTotal - hospital.bedsAvailable) / hospital.bedsTotal
        : 0.0;

    final statusColor = occupancy > 0.85
        ? Colors.redAccent
        : occupancy > 0.7
        ? Colors.amberAccent
        : Colors.greenAccent;

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: AppColors.slate900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: compact ? 30 : 40,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hospital.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${hospital.bedsAvailable} / ${hospital.bedsTotal} beds · ${hospital.doctorsOnDuty} doctors',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(occupancy * 100).round()}%',
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              Text(context.opsTr('occupancy'), style: TextStyle(color: Colors.white30, fontSize: 9),
              ),
            ],
          ),
          if (hospital.hasBloodBank) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.bloodtype,
                color: Colors.redAccent,
                size: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
