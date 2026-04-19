import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/india_ops_zones.dart';
import '../../../../core/l10n/dashboard_l10n.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../features/map/domain/emergency_zone_classification.dart';
import '../../../../services/environmental_data_service.dart';
import '../../../../services/incident_service.dart';
import '../../../../services/ops_hospital_service.dart';
import 'ops_analytics_trend_chart.dart';

/// Generic KPI tile with optional delta vs a reference value (shown as "+n / -n vs 7d med").
class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.delta,
    this.deltaLabel = 'vs 7d med',
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final num? delta;
  final String deltaLabel;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    Widget? deltaChip;
    if (delta != null) {
      final d = delta!;
      final up = d > 0;
      final flat = d == 0;
      deltaChip = Text(
        flat ? '±0 $deltaLabel' : '${up ? '+' : ''}$d $deltaLabel',
        style: TextStyle(
          color: flat
              ? Colors.white38
              : (up ? Colors.orangeAccent : Colors.greenAccent),
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: highlight
            ? color.withValues(alpha: 0.12)
            : AppColors.slate800.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight
              ? color.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
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
              fontSize: 20,
              height: 1.0,
            ),
          ),
          if (deltaChip != null) ...[
            const SizedBox(height: 4),
            deltaChip,
          ],
        ],
      ),
    );
  }
}

/// Compact row used inside anomalies / hotspots / inbound lists.
class _PulseRow extends StatelessWidget {
  const _PulseRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, color: iconColor, size: 14),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 6),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Thin card container used to group pulse sections.
class _PulseCard extends StatelessWidget {
  const _PulseCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF151A22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          height: 1.3,
        ),
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// FOCUS MODE — one hex cell is selected. Selection-aware detail card.
/// ═══════════════════════════════════════════════════════════════════════════

class AnalyticsFocusBody extends StatelessWidget {
  const AnalyticsFocusBody({
    super.key,
    required this.accent,
    required this.hexKey,
    required this.n48Bin,
    required this.inCell,
    required this.zone,
    required this.hexSize,
    required this.hospitals,
    required this.cachedHexCells,
    required this.isLoadingEnvData,
    required this.envData,
    required this.isMaster,
    required this.myHospitalDocId,
    required this.onClearSelection,
    required this.onOpenIncident,
  });

  final Color accent;
  final String hexKey;
  final int n48Bin;
  final List<SosIncident> inCell;
  final IndiaOpsZone zone;
  final double hexSize;
  final List<OpsHospitalRow> hospitals;
  final Map<HexAxial, HexCellCoverage>? cachedHexCells;
  final bool isLoadingEnvData;
  final HexEnvironmentalData? envData;
  final bool isMaster;
  final String? myHospitalDocId;
  final VoidCallback onClearSelection;
  final void Function(SosIncident incident) onOpenIncident;

  @override
  Widget build(BuildContext context) {
    final axial = HexAxial.tryParseStorageKey(hexKey);
    final cov = (axial != null ? (cachedHexCells?[axial]) : null) ??
        const HexCellCoverage(hospitals: 0, volunteers: 0);
    final tier = tierHealthForCell(cov);
    final tierLabel = switch (tier) {
      TierHealth.green => 'Well covered',
      TierHealth.yellow => 'Partial coverage',
      TierHealth.red => 'Sparse / no coverage',
    };
    final tierColor = switch (tier) {
      TierHealth.green => Colors.greenAccent,
      TierHealth.yellow => Colors.amberAccent,
      TierHealth.red => Colors.redAccent,
    };

    // Center of the selected hex → used to compute nearest hospital.
    LatLng? hexCenter;
    if (axial != null) {
      final pts = hexVerticesLatLng(zone.center, hexSize, axial);
      if (pts.isNotEmpty) {
        double lat = 0, lng = 0;
        for (final p in pts) {
          lat += p.latitude;
          lng += p.longitude;
        }
        hexCenter = LatLng(lat / pts.length, lng / pts.length);
      }
    }

    OpsHospitalRow? nearestHospital;
    double? nearestKm;
    if (hexCenter != null) {
      for (final h in hospitals) {
        if (h.lat == null || h.lng == null) continue;
        final m = Geolocator.distanceBetween(
          hexCenter.latitude,
          hexCenter.longitude,
          h.lat!,
          h.lng!,
        );
        final km = m / 1000.0;
        if (nearestKm == null || km < nearestKm) {
          nearestKm = km;
          nearestHospital = h;
        }
      }
    }

    final myHidT = myHospitalDocId?.trim();
    final myCoversThisHex = (!isMaster &&
            myHidT != null &&
            myHidT.isNotEmpty &&
            nearestHospital?.id == myHidT)
        ? true
        : (!isMaster ? false : null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        Row(
          children: [
            Icon(Icons.hexagon_outlined, color: accent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.opsTr('Hex {key}').replaceAll('{key}', hexKey),
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onClearSelection,
              icon: const Icon(Icons.close_rounded,
                  size: 16, color: Colors.white54),
              label: Text(
                context.opsTr('Clear'),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          context
              .opsTr('{n48} incidents in cell (48h bin) · {pins} pin(s) located in cell')
              .replaceAll('{n48}', '$n48Bin')
              .replaceAll('{pins}', '${inCell.length}'),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        _PulseCard(
          title: context.opsTr('Coverage at this cell'),
          icon: Icons.shield_moon_outlined,
          iconColor: tierColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tierLabel,
                style: TextStyle(
                  color: tierColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${cov.hospitals} hospital(s) · ${cov.volunteers} volunteer(s) in cell',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
              if (nearestHospital != null) ...[
                const SizedBox(height: 8),
                _PulseRow(
                  icon: Icons.local_hospital_outlined,
                  iconColor: AppColors.accentBlue,
                  title: nearestHospital.name,
                  subtitle: nearestKm == null
                      ? null
                      : '~${nearestKm.toStringAsFixed(1)} km from cell center · '
                          '${nearestHospital.bedsAvailable}/${nearestHospital.bedsTotal} beds',
                ),
              ],
              if (!isMaster && myCoversThisHex != null) ...[
                const SizedBox(height: 6),
                Text(
                  myCoversThisHex
                      ? context.opsTr('This is your facility\'s hex.')
                      : context.opsTr('Your facility is outside this hex.'),
                  style: TextStyle(
                    color: myCoversThisHex
                        ? Colors.tealAccent
                        : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        _PulseCard(
          title: context.opsTr('Incidents in this cell (48h)'),
          icon: Icons.emergency_outlined,
          iconColor: Colors.orangeAccent,
          child: inCell.isEmpty
              ? _EmptyHint(context.opsTr('No incident pins located here.'))
              : Column(
                  children: [
                    for (final e in inCell.take(6))
                      _PulseRow(
                        icon: _iconForStatus(e.status),
                        iconColor: _colorForStatus(e.status),
                        title: e.type.isEmpty ? 'Unknown' : e.type,
                        subtitle: '${e.id} · ${e.status.name}',
                        onTap: () => onOpenIncident(e),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: Colors.white30,
                          size: 16,
                        ),
                      ),
                    if (inCell.length > 6)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          context
                              .opsTr('+{count} more')
                              .replaceAll('{count}', '${inCell.length - 6}'),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (isLoadingEnvData || envData != null) ...[
          const SizedBox(height: 10),
          _PulseCard(
            title: context.opsTr('Environmental risk'),
            icon: Icons.air,
            iconColor: envData?.categoryColor ?? Colors.white54,
            child: isLoadingEnvData
                ? Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        context.opsTr('Fetching environmental data...'),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context
                            .opsTr('AQI: {aqi} ({category})')
                            .replaceAll('{aqi}', '${envData!.aqi}')
                            .replaceAll('{category}', envData!.category),
                        style: TextStyle(
                          color: envData!.categoryColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      if (envData!.healthRecommendation != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          envData!.healthRecommendation!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (envData!.hasHeatWarning) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2.0),
                              child: Icon(
                                Icons.local_fire_department,
                                color: Colors.orangeAccent,
                                size: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                envData!.heatStrokeWarning,
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

IconData _iconForStatus(IncidentStatus s) => switch (s) {
      IncidentStatus.pending => Icons.pending_actions,
      IncidentStatus.dispatched => Icons.send,
      IncidentStatus.blocked => Icons.report_problem_outlined,
      IncidentStatus.resolved => Icons.check_circle_outline,
    };

Color _colorForStatus(IncidentStatus s) => switch (s) {
      IncidentStatus.pending => Colors.amber,
      IncidentStatus.dispatched => AppColors.accentBlue,
      IncidentStatus.blocked => Colors.redAccent,
      IncidentStatus.resolved => Colors.greenAccent,
    };

/// ═══════════════════════════════════════════════════════════════════════════
/// MASTER MODE — city-wide "System pulse" (no hex selected, role == master).
/// ═══════════════════════════════════════════════════════════════════════════

class MasterSystemPulseBody extends StatelessWidget {
  const MasterSystemPulseBody({
    super.key,
    required this.accent,
    required this.now,
    required this.zone,
    required this.hexSize,
    required this.inc48h,
    required this.active,
    required this.pending,
    required this.dispatched,
    required this.emsAwait,
    required this.emsInbound,
    required this.emsScene,
    required this.hospitals,
    required this.volunteerDutyCount,
    required this.bins48,
    required this.cachedHexCells,
    required this.trend7,
    required this.onZoomHex,
  });

  final Color accent;
  final DateTime now;
  final IndiaOpsZone zone;
  final double hexSize;
  final List<SosIncident> inc48h;
  final List<SosIncident> active;
  final int pending;
  final int dispatched;
  final int emsAwait;
  final int emsInbound;
  final int emsScene;
  final List<OpsHospitalRow> hospitals;
  final int volunteerDutyCount;
  final Map<String, int> bins48;
  final Map<HexAxial, HexCellCoverage>? cachedHexCells;
  final List<int> trend7;
  final void Function(String hexKey) onZoomHex;

  int get _pendingOver5min => active
      .where((e) =>
          e.status == IncidentStatus.pending &&
          now.difference(e.timestamp) > const Duration(minutes: 5))
      .length;

  int get _todayCount {
    final start = DateTime(now.year, now.month, now.day);
    return inc48h
        .where((e) => e.timestamp.toLocal().isAfter(start))
        .length;
  }

  num get _sevenDayMedian {
    if (trend7.length < 7) return 0;
    final prior = trend7.sublist(0, 6).toList()..sort();
    if (prior.isEmpty) return 0;
    return prior[prior.length ~/ 2];
  }

  @override
  Widget build(BuildContext context) {
    final staleHospitalCutoff =
        now.subtract(const Duration(minutes: 15));
    final staleHospitals = hospitals
        .where((h) => h.updatedAt.isBefore(staleHospitalCutoff))
        .toList();

    final unacknowledgedSos = active
        .where((e) =>
            e.status == IncidentStatus.pending &&
            now.difference(e.timestamp) > const Duration(minutes: 5))
        .toList();

    // Gap: hex cells with ≥1 incident in 48h but zero hospitals+volunteers.
    final gapKeys = <String>[];
    if (cachedHexCells != null) {
      bins48.forEach((k, n) {
        if (n <= 0) return;
        final h = HexAxial.tryParseStorageKey(k);
        if (h == null) return;
        final cov = cachedHexCells![h];
        final hasCover = cov != null &&
            (cov.hospitals + cov.volunteers) > 0;
        if (!hasCover) gapKeys.add(k);
      });
    }

    final hotspots = bins48.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topHotspots = hotspots.take(3).toList();

    final trendTodayIdx = trend7.isEmpty ? 0 : trend7.length - 1;
    final todayTrend = trend7.isEmpty ? 0 : trend7[trendTodayIdx];
    final median7 = _sevenDayMedian;
    final trendDelta = todayTrend - median7;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        // KPI row — dense 2×2 grid of 4 tiles.
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                label: context.opsTr('Active'),
                value: '${active.length}',
                icon: Icons.emergency,
                color: Colors.orangeAccent,
                delta: _todayCount - median7,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiTile(
                label: context.opsTr('Pending > 5m'),
                value: '$_pendingOver5min',
                icon: Icons.schedule,
                color: Colors.amber,
                highlight: _pendingOver5min > 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _KpiTile(
                label: context.opsTr('Dispatched'),
                value: '$dispatched',
                icon: Icons.send,
                color: AppColors.accentBlue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiTile(
                label: context.opsTr('Volunteers on-duty'),
                value: '$volunteerDutyCount',
                icon: Icons.groups,
                color: Colors.lightGreenAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Anomalies — only if any.
        if (unacknowledgedSos.isNotEmpty ||
            staleHospitals.isNotEmpty ||
            gapKeys.isNotEmpty)
          _PulseCard(
            title: context.opsTr('Anomalies · needs attention'),
            icon: Icons.priority_high_rounded,
            iconColor: Colors.orangeAccent,
            child: Column(
              children: [
                if (unacknowledgedSos.isNotEmpty)
                  _PulseRow(
                    icon: Icons.pending_actions,
                    iconColor: Colors.amberAccent,
                    title: context
                        .opsTr('{n} SOS pending > 5 min')
                        .replaceAll('{n}', '${unacknowledgedSos.length}'),
                    subtitle: unacknowledgedSos
                        .take(3)
                        .map((e) => e.type.isEmpty ? 'Unknown' : e.type)
                        .join(' · '),
                  ),
                if (staleHospitals.isNotEmpty)
                  _PulseRow(
                    icon: Icons.cloud_off_outlined,
                    iconColor: Colors.redAccent,
                    title: context
                        .opsTr('{n} hospitals with stale heartbeat')
                        .replaceAll('{n}', '${staleHospitals.length}'),
                    subtitle:
                        staleHospitals.take(3).map((h) => h.name).join(' · '),
                  ),
                if (gapKeys.isNotEmpty)
                  _PulseRow(
                    icon: Icons.warning_amber_rounded,
                    iconColor: Colors.redAccent,
                    title: context
                        .opsTr('{n} hex cell(s) with incidents but 0 coverage')
                        .replaceAll('{n}', '${gapKeys.length}'),
                    subtitle: gapKeys.take(3).join(', '),
                    trailing: gapKeys.isNotEmpty
                        ? FilledButton.tonal(
                            onPressed: () => onZoomHex(gapKeys.first),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 28),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 0),
                              backgroundColor:
                                  Colors.redAccent.withValues(alpha: 0.18),
                              foregroundColor: Colors.redAccent,
                              textStyle: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            child: Text(context.opsTr('Zoom')),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        if (unacknowledgedSos.isNotEmpty ||
            staleHospitals.isNotEmpty ||
            gapKeys.isNotEmpty)
          const SizedBox(height: 10),

        // Top 3 hotspots.
        _PulseCard(
          title: context.opsTr('Top hotspots (48h)'),
          icon: Icons.local_fire_department,
          iconColor: Colors.deepOrangeAccent,
          child: topHotspots.isEmpty
              ? _EmptyHint(context.opsTr('No incidents in the last 48h.'))
              : Column(
                  children: [
                    for (final e in topHotspots)
                      _PulseRow(
                        icon: Icons.hexagon_outlined,
                        iconColor: Colors.deepOrangeAccent,
                        title: '#${e.key}',
                        subtitle: context
                            .opsTr('{n} incidents')
                            .replaceAll('{n}', '${e.value}'),
                        trailing: FilledButton.tonal(
                          onPressed: () => onZoomHex(e.key),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 0),
                            backgroundColor: accent.withValues(alpha: 0.18),
                            foregroundColor: accent,
                            textStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: Text(context.opsTr('Zoom')),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 10),

        // 7-day trend with delta caption.
        _PulseCard(
          title: context.opsTr('7-day zone trend'),
          icon: Icons.insights_rounded,
          iconColor: AppColors.accentBlue,
          trailing: Text(
            trendDelta == 0
                ? '±0 ${context.opsTr('vs 7d med')}'
                : '${trendDelta > 0 ? '+' : ''}$trendDelta ${context.opsTr('vs 7d med')}',
            style: TextStyle(
              color: trendDelta == 0
                  ? Colors.white54
                  : (trendDelta > 0
                      ? Colors.orangeAccent
                      : Colors.greenAccent),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: OpsAnalyticsTrendChart(counts: trend7, now: now),
        ),
        const SizedBox(height: 10),

        // EMS workflow pie.
        _PulseCard(
          title: context.opsTr('EMS workflow phase'),
          icon: Icons.local_shipping_outlined,
          iconColor: AppColors.accentBlue,
          child: _emsWorkflowMini(
            context,
            emsAwait: emsAwait,
            emsInbound: emsInbound,
            emsScene: emsScene,
          ),
        ),
      ],
    );
  }
}

Widget _emsWorkflowMini(
  BuildContext context, {
  required int emsAwait,
  required int emsInbound,
  required int emsScene,
}) {
  final total = emsAwait + emsInbound + emsScene;
  if (total == 0) {
    return _EmptyHint(context.opsTr('No EMS workflow activity right now.'));
  }
  final sections = <PieChartSectionData>[
    if (emsAwait > 0)
      PieChartSectionData(
        color: Colors.orange,
        value: emsAwait.toDouble(),
        title: '$emsAwait',
        radius: 32,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    if (emsInbound > 0)
      PieChartSectionData(
        color: AppColors.accentBlue,
        value: emsInbound.toDouble(),
        title: '$emsInbound',
        radius: 32,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    if (emsScene > 0)
      PieChartSectionData(
        color: Colors.greenAccent,
        value: emsScene.toDouble(),
        title: '$emsScene',
        radius: 32,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
  ];
  return SizedBox(
    height: 110,
    child: Row(
      children: [
        Expanded(
          flex: 5,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 26,
              sections: sections,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _legendRow(Colors.orange, context.opsTr('Awaiting'), emsAwait),
              const SizedBox(height: 4),
              _legendRow(AppColors.accentBlue, context.opsTr('Inbound'),
                  emsInbound),
              const SizedBox(height: 4),
              _legendRow(Colors.greenAccent, context.opsTr('On scene'),
                  emsScene),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _legendRow(Color c, String label, int n) {
  return Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ),
      Text(
        '$n',
        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

/// ═══════════════════════════════════════════════════════════════════════════
/// HOSPITAL MODE — "Facility pulse" scoped to [boundHospitalDocId].
/// ═══════════════════════════════════════════════════════════════════════════

class HospitalFacilityPulseBody extends StatefulWidget {
  const HospitalFacilityPulseBody({
    super.key,
    required this.accent,
    required this.now,
    required this.boundHospitalDocId,
    required this.hospitals,
    required this.zone,
    required this.hexSize,
    required this.cachedHexCells,
    required this.zoneIncidents,
    required this.onOpenIncident,
    required this.onManageServices,
    this.showInboundCard = true,
  });

  final Color accent;
  final DateTime now;
  final String boundHospitalDocId;
  final List<OpsHospitalRow> hospitals;
  final IndiaOpsZone zone;
  final double hexSize;
  final Map<HexAxial, HexCellCoverage>? cachedHexCells;
  /// Full zone incident list (up to [build()] query limit in parent) — used
  /// to derive facility-scoped trends over the last 7 days.
  final List<SosIncident> zoneIncidents;
  final void Function(String incidentId) onOpenIncident;
  final VoidCallback onManageServices;
  /// When false, the inbound list is omitted (e.g. shown on the analytics left rail).
  final bool showInboundCard;

  @override
  State<HospitalFacilityPulseBody> createState() =>
      _HospitalFacilityPulseBodyState();
}

class _HospitalFacilityPulseBodyState extends State<HospitalFacilityPulseBody> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hid = widget.boundHospitalDocId.trim();
    if (hid.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            context.opsTr('This account is not linked to a hospital.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      );
    }

    OpsHospitalRow? myRow;
    for (final h in widget.hospitals) {
      if (h.id == hid) {
        myRow = h;
        break;
      }
    }

    // 7-day trend scoped to incidents in this hospital's ~2-ring hex neighborhood.
    final trend7Mine = _sevenDayCountsForHospital(widget.zoneIncidents, hid);

    // Compute my-hex coverage (the hex this hospital sits in).
    HexAxial? myHexAxial;
    HexCellCoverage? myHexCov;
    if (myRow?.lat != null && myRow?.lng != null) {
      final h = volunteerToHex(
        widget.hexSize,
        widget.zone.center.latitude,
        widget.zone.center.longitude,
        myRow!.lat!,
        myRow.lng!,
      );
      myHexAxial = h;
      myHexCov = widget.cachedHexCells?[h];
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        if (myRow != null) _bedGaugeCard(myRow),
        if (myRow != null) const SizedBox(height: 10),
        _awaitingAcceptCard(hid),
        const SizedBox(height: 10),
        if (widget.showInboundCard) ...[
          _inboundCard(hid),
          const SizedBox(height: 10),
        ],
        _last24hKpisCard(hid),
        const SizedBox(height: 10),
        if (myRow != null) _servicesCard(myRow),
        if (myRow != null) const SizedBox(height: 10),
        _PulseCard(
          title: context.opsTr('7-day facility trend'),
          icon: Icons.insights_rounded,
          iconColor: AppColors.accentBlue,
          child: OpsAnalyticsTrendChart(
            counts: trend7Mine,
            now: widget.now,
          ),
        ),
        const SizedBox(height: 10),
        _myHexCoverageCard(myHexAxial, myHexCov),
      ],
    );
  }

  // ── Cards ────────────────────────────────────────────────────────────────

  Widget _bedGaugeCard(OpsHospitalRow row) {
    final total = row.bedsTotal <= 0 ? 1 : row.bedsTotal;
    final avail = row.bedsAvailable.clamp(0, total);
    final frac = avail / total;
    final color = frac > 0.3
        ? Colors.greenAccent
        : (frac > 0.1 ? Colors.amberAccent : Colors.redAccent);
    final df = DateFormat.MMMd().add_Hm();
    return _PulseCard(
      title: context.opsTr('My beds'),
      icon: Icons.bed_outlined,
      iconColor: color,
      trailing: Text(
        context
            .opsTr('Updated {t}')
            .replaceAll('{t}', df.format(row.updatedAt.toLocal())),
        style: const TextStyle(color: Colors.white38, fontSize: 9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$avail',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '/ ${row.bedsTotal} ${context.opsTr('beds available')}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white10,
              color: color,
            ),
          ),
          if ((row.traumaBedsNote ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              row.traumaBedsNote!.trim(),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            context.opsTr(
              'Edit beds in Hospital Live Operations (capacity card); changes sync here.',
            ),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _awaitingAcceptCard(String hid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .where('notifiedHospitalId', isEqualTo: hid)
          .where('dispatchStatus', isEqualTo: 'pending_acceptance')
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        return _PulseCard(
          title: context.opsTr('Awaiting my accept / decline'),
          icon: Icons.notifications_active_outlined,
          iconColor: Colors.amberAccent,
          trailing: docs.isEmpty
              ? null
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${docs.length}',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
          child: docs.isEmpty
              ? _EmptyHint(
                  context.opsTr('Nothing waiting on your decision.'),
                )
              : Column(
                  children: [
                    for (final d in docs.take(5))
                      _pendingAssignmentRow(d),
                    if (docs.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          context
                              .opsTr('+{count} more in Live Ops')
                              .replaceAll(
                                  '{count}', '${docs.length - 5}'),
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _pendingAssignmentRow(
      QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final notifiedAt = data['notifiedAt'];
    final escalateMs = (data['escalateAfterMs'] as num?)?.toInt();
    String countdown = '';
    Color countdownColor = Colors.white54;
    if (notifiedAt is Timestamp && escalateMs != null) {
      final deadline = notifiedAt.toDate().add(Duration(milliseconds: escalateMs));
      final remain = deadline.difference(DateTime.now());
      if (remain.isNegative) {
        countdown = context.opsTr('Escalating…');
        countdownColor = Colors.redAccent;
      } else {
        final m = remain.inMinutes;
        final s = remain.inSeconds % 60;
        countdown = '${m}m ${s.toString().padLeft(2, '0')}s';
        countdownColor = remain.inSeconds < 30
            ? Colors.redAccent
            : (remain.inMinutes < 2
                ? Colors.orangeAccent
                : Colors.amberAccent);
      }
    }
    final required = (data['requiredServices'] as List?)?.join(', ') ?? '';
    return _PulseRow(
      icon: Icons.warning_amber_rounded,
      iconColor: Colors.amberAccent,
      title: d.id,
      subtitle: required.isEmpty
          ? context.opsTr('Tap to open in Live Ops')
          : context
              .opsTr('Required: {req}')
              .replaceAll('{req}', required),
      onTap: () => widget.onOpenIncident(d.id),
      trailing: Text(
        countdown,
        style: TextStyle(
          color: countdownColor,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _inboundCard(String hid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .where('acceptedHospitalId', isEqualTo: hid)
          .limit(15)
          .snapshots(),
      builder: (context, snap) {
        final docs = (snap.data?.docs ?? []).where((d) {
          final cc = d.data()['consignmentClosedAt'];
          return cc is! Timestamp;
        }).toList();
        // Sort by most recent acceptedAt first.
        docs.sort((a, b) {
          final aa = a.data()['acceptedAt'];
          final bb = b.data()['acceptedAt'];
          final at = aa is Timestamp ? aa.toDate() : DateTime(1970);
          final bt = bb is Timestamp ? bb.toDate() : DateTime(1970);
          return bt.compareTo(at);
        });
        return _PulseCard(
          title: context.opsTr('My inbound'),
          icon: Icons.local_shipping_outlined,
          iconColor: AppColors.accentBlue,
          trailing: docs.isEmpty
              ? null
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${docs.length}',
                    style: const TextStyle(
                      color: AppColors.accentBlue,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
          child: docs.isEmpty
              ? _EmptyHint(context.opsTr('No units currently inbound.'))
              : Column(
                  children: [
                    for (final d in docs.take(5)) _inboundRow(d),
                  ],
                ),
        );
      },
    );
  }

  Widget _inboundRow(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final callSign =
        (data['assignedFleetCallSign'] as String?)?.trim() ?? '—';
    final dispStatus =
        (data['ambulanceDispatchStatus'] as String?)?.trim() ?? '';
    final acceptedAt = data['acceptedAt'];
    String relAccepted = '';
    if (acceptedAt is Timestamp) {
      final diff = DateTime.now().difference(acceptedAt.toDate());
      if (diff.inMinutes < 60) {
        relAccepted = context
            .opsTr('accepted {m}m ago')
            .replaceAll('{m}', '${diff.inMinutes.clamp(0, 59)}');
      } else if (diff.inHours < 24) {
        relAccepted = context
            .opsTr('accepted {h}h ago')
            .replaceAll('{h}', '${diff.inHours}');
      }
    }
    final subtitleParts = <String>[
      if (callSign.isNotEmpty && callSign != '—')
        context.opsTr('Unit {cs}').replaceAll('{cs}', callSign),
      if (dispStatus.isNotEmpty) dispStatus,
      if (relAccepted.isNotEmpty) relAccepted,
    ];
    return _PulseRow(
      icon: Icons.directions_car_filled_outlined,
      iconColor: AppColors.accentBlue,
      title: d.id,
      subtitle: subtitleParts.join(' · '),
      onTap: () => widget.onOpenIncident(d.id),
      trailing: const Icon(
        Icons.chevron_right,
        color: Colors.white30,
        size: 16,
      ),
    );
  }

  Widget _last24hKpisCard(String hid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .where('notifiedHospitalIds', arrayContains: hid)
          .limit(80)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final cutoff = widget.now.subtract(const Duration(hours: 24));
        var accepted = 0;
        var declined = 0;
        var diverted = 0;
        final acceptLatenciesMs = <int>[];
        for (final d in docs) {
          final m = d.data();
          final acceptedAt = m['acceptedAt'];
          final notifiedAt = m['notifiedAt'];
          final acceptedHid = (m['acceptedHospitalId'] as String?)?.trim();
          final reason = (m['reason'] as String?)?.trim().toLowerCase();
          final assignedAt = m['assignedAt'];
          final refTs = (acceptedAt is Timestamp)
              ? acceptedAt.toDate()
              : (assignedAt is Timestamp
                  ? assignedAt.toDate()
                  : DateTime.fromMillisecondsSinceEpoch(0));
          if (refTs.isBefore(cutoff)) continue;

          if (acceptedHid == hid && acceptedAt is Timestamp) {
            accepted++;
            if (notifiedAt is Timestamp) {
              acceptLatenciesMs.add(acceptedAt
                  .toDate()
                  .difference(notifiedAt.toDate())
                  .inMilliseconds
                  .abs());
            }
          } else if (acceptedHid != null &&
              acceptedHid.isNotEmpty &&
              acceptedHid != hid) {
            diverted++;
          } else if (reason != null && reason.contains('decline')) {
            declined++;
          }
        }
        int? medianSec;
        if (acceptLatenciesMs.isNotEmpty) {
          acceptLatenciesMs.sort();
          medianSec =
              (acceptLatenciesMs[acceptLatenciesMs.length ~/ 2] / 1000).round();
        }
        return _PulseCard(
          title: context.opsTr('Last 24h'),
          icon: Icons.query_stats_rounded,
          iconColor: AppColors.accentBlue,
          child: Row(
            children: [
              Expanded(
                child: _mini24(
                  context.opsTr('Accepted'),
                  '$accepted',
                  Colors.greenAccent,
                ),
              ),
              Expanded(
                child: _mini24(
                  context.opsTr('Declined'),
                  '$declined',
                  Colors.redAccent,
                ),
              ),
              Expanded(
                child: _mini24(
                  context.opsTr('Diverted'),
                  '$diverted',
                  Colors.amberAccent,
                ),
              ),
              Expanded(
                child: _mini24(
                  context.opsTr('Median accept'),
                  medianSec == null ? '—' : '${medianSec}s',
                  AppColors.accentBlue,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _mini24(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _servicesCard(OpsHospitalRow row) {
    final services = row.offeredServices;
    return _PulseCard(
      title: context.opsTr('My services'),
      icon: Icons.medical_services_outlined,
      iconColor: AppColors.accentBlue,
      trailing: TextButton.icon(
        onPressed: widget.onManageServices,
        icon: const Icon(Icons.open_in_new_rounded, size: 14),
        label: Text(context.opsTr('Manage')),
        style: TextButton.styleFrom(
          foregroundColor: widget.accent,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(0, 26),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
        ),
      ),
      child: services.isEmpty
          ? _EmptyHint(context.opsTr('No services configured yet.'))
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in services.take(12))
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          AppColors.accentBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.accentBlue.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      s,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (services.length > 12)
                  Text(
                    context
                        .opsTr('+{n} more')
                        .replaceAll('{n}', '${services.length - 12}'),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _myHexCoverageCard(HexAxial? axial, HexCellCoverage? cov) {
    if (axial == null) {
      return _PulseCard(
        title: context.opsTr('My hex coverage'),
        icon: Icons.hexagon_outlined,
        iconColor: Colors.white54,
        child: _EmptyHint(
          context.opsTr(
              'No GPS on the hospital record — location unavailable.'),
        ),
      );
    }
    final c = cov ?? const HexCellCoverage(hospitals: 0, volunteers: 0);
    final tier = tierHealthForCell(c);
    final tierLabel = switch (tier) {
      TierHealth.green => 'Well covered',
      TierHealth.yellow => 'Partial coverage',
      TierHealth.red => 'Sparse / no coverage',
    };
    final tierColor = switch (tier) {
      TierHealth.green => Colors.greenAccent,
      TierHealth.yellow => Colors.amberAccent,
      TierHealth.red => Colors.redAccent,
    };
    return _PulseCard(
      title: context.opsTr('My hex coverage'),
      icon: Icons.hexagon_outlined,
      iconColor: tierColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tierLabel,
            style: TextStyle(
              color: tierColor,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${c.hospitals} hospital(s) · ${c.volunteers} volunteer(s) '
            '· #${axial.storageKey}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  List<int> _sevenDayCountsForHospital(
    List<SosIncident> incidents,
    String hid,
  ) {
    final localNow = widget.now.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final counts = List<int>.filled(7, 0);
    for (final e in incidents) {
      if (!_incidentTouchesHospital(e, hid)) continue;
      final t = e.timestamp.toLocal();
      final day = DateTime(t.year, t.month, t.day);
      final diff = today.difference(day).inDays;
      if (diff >= 0 && diff <= 6) {
        counts[6 - diff]++;
      }
    }
    return counts;
  }

  /// Proximity heuristic: treat an incident as "facility-related" when its
  /// pin falls in this hospital's hex or within 2 hex rings of it.
  /// AdminAnalyticsDashboard doesn't stream per-incident assignments, so we
  /// approximate by geography rather than querying assignment docs here.
  bool _incidentTouchesHospital(SosIncident e, String hid) {
    // Best-effort proximity hint: incident happens inside my hospital's hex.
    final hospitals = widget.hospitals;
    OpsHospitalRow? myRow;
    for (final h in hospitals) {
      if (h.id == hid) {
        myRow = h;
        break;
      }
    }
    if (myRow == null || myRow.lat == null || myRow.lng == null) {
      return false;
    }
    final eHex = volunteerToHex(
      widget.hexSize,
      widget.zone.center.latitude,
      widget.zone.center.longitude,
      e.liveVictimPin.latitude,
      e.liveVictimPin.longitude,
    );
    final myHex = volunteerToHex(
      widget.hexSize,
      widget.zone.center.latitude,
      widget.zone.center.longitude,
      myRow.lat!,
      myRow.lng!,
    );
    // Same hex OR within ~2 rings (Manhattan-like axial distance ≤ 2).
    final dq = eHex.q - myHex.q;
    final dr = eHex.r - myHex.r;
    final ds = -(dq + dr);
    final dist = (dq.abs() + dr.abs() + ds.abs()) ~/ 2;
    return dist <= 2;
  }
}
