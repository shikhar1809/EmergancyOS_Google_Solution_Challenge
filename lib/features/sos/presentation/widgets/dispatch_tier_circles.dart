import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../map/domain/emergency_zone_classification.dart';

class DispatchTierCircles {
  static Set<Circle> build({
    required LatLng? victimLatLng,
    required int currentTier,
  }) {
    final victim = victimLatLng;
    if (victim == null) return const {};
    return {
      Circle(
        circleId: const CircleId('dispatch_tier1'),
        center: victim,
        radius: kDispatchTier1RadiusM,
        fillColor: Colors.red.withValues(alpha: 0.08),
        strokeColor: Colors.redAccent,
        strokeWidth: 2,
      ),
      Circle(
        circleId: const CircleId('dispatch_tier2'),
        center: victim,
        radius: kDispatchTier2RadiusM,
        fillColor: Colors.amber.withValues(
          alpha: currentTier >= 2 ? 0.06 : 0.02,
        ),
        strokeColor: Colors.amber,
        strokeWidth: 2,
      ),
      Circle(
        circleId: const CircleId('dispatch_tier3'),
        center: victim,
        radius: kDispatchTier3RadiusM,
        fillColor: Colors.blueGrey.withValues(
          alpha: currentTier >= 3 ? 0.05 : 0.01,
        ),
        strokeColor: Colors.blueGrey,
        strokeWidth: 2,
      ),
    };
  }
}

class DispatchPathLegend extends StatelessWidget {
  final Color lineColor;
  final String label;
  final int? routeMin;
  final String? docEta;

  const DispatchPathLegend({
    super.key,
    required this.lineColor,
    required this.label,
    this.routeMin,
    this.docEta,
  });

  @override
  Widget build(BuildContext context) {
    final routed = routeMin != null ? '~$routeMin min (route)' : null;
    final doc = (docEta?.isNotEmpty ?? false) ? docEta : null;
    final sub = [routed, doc].whereType<String>().join(' \u00b7 ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 4,
            decoration: BoxDecoration(
              color: lineColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 10,
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
