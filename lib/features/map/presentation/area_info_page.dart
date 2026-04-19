import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/places_service.dart';
import '../../../services/incident_service.dart';

class AreaInfoPage extends StatelessWidget {
  final Position? currentPosition;
  final List<EmergencyPlace> hospitals;
  final AreaIntelligence areaIntel;
  final List<SosIncident> pastIncidents;

  const AreaInfoPage({
    super.key,
    required this.currentPosition,
    required this.hospitals,
    required this.areaIntel,
    required this.pastIncidents,
  });

  double _distKm(double lat, double lng) {
    if (currentPosition == null) return 0;
    return Geolocator.distanceBetween(
            currentPosition!.latitude, currentPosition!.longitude, lat, lng) /
        1000;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.surface.withValues(alpha: 0.95),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Area Intel',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18),
            ),
            actions: [
              if (currentPosition != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: Text(
                      '${currentPosition!.latitude.toStringAsFixed(2)}°, ${currentPosition!.longitude.toStringAsFixed(2)}°',
                      style: const TextStyle(
                          color: Colors.white30,
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ),
            ],
          ),

          // Risk header
          SliverToBoxAdapter(child: _buildRiskHeader(context)),

          // Things to keep in mind
          SliverToBoxAdapter(child: _buildSafetyTips(context)),

          // Common emergencies
          if (areaIntel.totalPastIncidents > 0)
            SliverToBoxAdapter(child: _buildCommonEmergencies(context)),

          // Hospitals with distance
          if (hospitals.isNotEmpty)
            SliverToBoxAdapter(
                child: _buildServiceSection(
              context,
              title: 'Hospitals',
              icon: Icons.local_hospital_rounded,
              color: Colors.cyan,
              places: hospitals,
            )),

          // Response time + stats
          SliverToBoxAdapter(child: _buildResponseStats(context)),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildRiskHeader(BuildContext context) {
    final ai = areaIntel;
    final riskColor = ai.riskScore >= 75
        ? AppColors.primaryDanger
        : ai.riskScore >= 50
            ? Colors.deepOrange
            : ai.riskScore >= 25
                ? Colors.amber
                : AppColors.primarySafe;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: riskColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: riskColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                '${ai.riskScore}',
                style: TextStyle(
                    color: riskColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Area Risk: ${ai.riskLabel}',
                  style: TextStyle(
                      color: riskColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  ai.totalPastIncidents > 0
                      ? '${ai.totalPastIncidents} past incidents · Peak at ${ai.peakHour}:00 on ${ai.peakDay}s'
                      : 'No incident history available yet',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyTips(BuildContext context) {
    final tips = <Map<String, dynamic>>[];

    if (areaIntel.riskScore >= 50) {
      tips.add({
        'icon': Icons.warning_amber_rounded,
        'color': Colors.amber,
        'text':
            'High incident area — stay alert, especially around ${areaIntel.peakHour}:00 on ${areaIntel.peakDay}s.',
      });
    }

    if (areaIntel.topIncidentType.toLowerCase().contains('collision') ||
        areaIntel.topIncidentType.toLowerCase().contains('accident')) {
      tips.add({
        'icon': Icons.car_crash_rounded,
        'color': Colors.orange,
        'text':
            'Vehicle collisions are the most common emergency here. Drive carefully and maintain safe distance.',
      });
    }

    if (areaIntel.topIncidentType.toLowerCase().contains('cardiac')) {
      tips.add({
        'icon': Icons.favorite_rounded,
        'color': const Color(0xFFFF1744),
        'text':
            'Cardiac emergencies are frequent. Know your nearest AED location and basic CPR.',
      });
    }

    if (hospitals.isEmpty) {
      tips.add({
        'icon': Icons.local_hospital_rounded,
        'color': Colors.cyan,
        'text':
            'No hospitals detected nearby. Consider pre-planning your route to the nearest facility.',
      });
    } else {
      final nearest = _distKm(hospitals.first.lat, hospitals.first.lng);
      if (nearest > 10) {
        tips.add({
          'icon': Icons.local_hospital_rounded,
          'color': Colors.cyan,
          'text':
              'Nearest hospital is ${nearest.toStringAsFixed(1)} km away — factor in travel time during emergencies.',
        });
      }
    }

    tips.add({
      'icon': Icons.phone_in_talk_rounded,
      'color': AppColors.primaryInfo,
      'text': 'Save emergency contacts. Dial 112 (universal) or 108 (ambulance) in India.',
    });

    tips.add({
      'icon': Icons.battery_alert_rounded,
      'color': Colors.green,
      'text':
          'Keep your phone charged. emergencyOS works offline for critical features.',
    });

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Things to Keep in Mind',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
          ...tips.map((tip) => _tipCard(
                tip['icon'] as IconData,
                tip['color'] as Color,
                tip['text'] as String,
              )),
        ],
      ),
    );
  }

  Widget _tipCard(IconData icon, Color color, String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildCommonEmergencies(BuildContext context) {
    final sorted = areaIntel.incidentTypeBreakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Common Emergencies in this Area',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
          ...top.map((e) {
            final pct = areaIntel.totalPastIncidents > 0
                ? (e.value / areaIntel.totalPastIncidents * 100).round()
                : 0;
            final sevColor = _severityColor(_getSeverity(e.key));
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_incidentIcon(e.key), color: sevColor, size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(e.key,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                      Text('${e.value} incidents',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value:
                          areaIntel.totalPastIncidents > 0
                              ? e.value / areaIntel.totalPastIncidents
                              : 0,
                      backgroundColor: Colors.white10,
                      color: sevColor.withValues(alpha: 0.6),
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('$pct% of total',
                        style: const TextStyle(
                            color: Colors.white30, fontSize: 10)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildServiceSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<EmergencyPlace> places,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                const Spacer(),
                Text('${places.length} nearby',
                    style:
                        const TextStyle(color: Colors.white30, fontSize: 11)),
              ],
            ),
          ),
          ...places.map((place) {
            final dist = _distKm(place.lat, place.lng);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(place.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${dist.toStringAsFixed(1)} km',
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(place.vicinity,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 14, color: Colors.white30),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Straight-line distance only. Travel time and bed availability are not shown here.',
                          style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildResponseStats(BuildContext context) {
    final ai = areaIntel;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Emergency Response',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _statBlock(
                      '${ai.avgResponseMinutes > 0 ? ai.avgResponseMinutes : '~8'} min',
                      'Avg Response',
                      AppColors.primaryInfo,
                    ),
                    _statBlock(
                      '${ai.resolvedPercent}%',
                      'Resolved',
                      AppColors.primarySafe,
                    ),
                    _statBlock(
                      '${ai.dangerZones.length}',
                      'Hotspots',
                      Colors.deepOrange,
                    ),
                  ],
                ),
                if (ai.severityCounts.values.any((v) => v > 0)) ...[
                  const SizedBox(height: 16),
                  _buildSeverityRow(ai),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBlock(String value, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildSeverityRow(AreaIntelligence ai) {
    final crit = ai.severityCounts['critical'] ?? 0;
    final high = ai.severityCounts['high'] ?? 0;
    final med = ai.severityCounts['medium'] ?? 0;
    final low = ai.severityCounts['low'] ?? 0;

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Row(
            children: [
              if (crit > 0)
                Expanded(
                    flex: crit,
                    child: Container(
                        height: 6, color: const Color(0xFFFF1744))),
              if (high > 0)
                Expanded(
                    flex: high,
                    child: Container(height: 6, color: Colors.deepOrange)),
              if (med > 0)
                Expanded(
                    flex: med,
                    child: Container(height: 6, color: Colors.amber)),
              if (low > 0)
                Expanded(
                    flex: low,
                    child: Container(height: 6, color: Colors.blueGrey)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sevDot(const Color(0xFFFF1744), 'Critical', crit),
            _sevDot(Colors.deepOrange, 'High', high),
            _sevDot(Colors.amber, 'Medium', med),
            _sevDot(Colors.blueGrey, 'Low', low),
          ],
        ),
      ],
    );
  }

  Widget _sevDot(Color c, String label, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$count',
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  String _getSeverity(String type) {
    final t = type.toLowerCase();
    if (t.contains('cardiac') || t.contains('stroke') || t.contains('hemorrhage')) return 'critical';
    if (t.contains('collision') || t.contains('accident') || t.contains('fire') || t.contains('drown')) return 'high';
    if (t.contains('bleeding') || t.contains('choking') || t.contains('fracture')) return 'medium';
    return 'low';
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical': return const Color(0xFFFF1744);
      case 'high': return Colors.deepOrange;
      case 'medium': return Colors.amber;
      default: return Colors.blueGrey;
    }
  }

  IconData _incidentIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('cardiac') || t.contains('heart')) return Icons.favorite_rounded;
    if (t.contains('collision') || t.contains('accident')) return Icons.car_crash_rounded;
    if (t.contains('fire')) return Icons.local_fire_department_rounded;
    if (t.contains('drown')) return Icons.pool_rounded;
    if (t.contains('stroke')) return Icons.psychology_rounded;
    if (t.contains('choking')) return Icons.air_rounded;
    if (t.contains('bleeding')) return Icons.bloodtype_rounded;
    return Icons.emergency_rounded;
  }
}
