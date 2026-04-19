import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/ems_workflow_labels.dart';
import '../../../../services/incident_service.dart';
import 'package:emergency_os/core/l10n/dashboard_l10n.dart';

export '../../../../core/utils/ems_workflow_labels.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.dispatchedAccent});

  final IncidentStatus status;
  final Color? dispatchedAccent;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      IncidentStatus.pending => Colors.orangeAccent,
      IncidentStatus.dispatched => dispatchedAccent ?? AppColors.accentBlue,
      IncidentStatus.blocked => Colors.grey,
      IncidentStatus.resolved => AppColors.primarySafe,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.name,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Hospital Overview: avoids overloaded [IncidentStatus.dispatched] (“assigned” can mean volunteers only).
String hospitalConsignmentStatusLabel(
  SosIncident e,
  String? ambulanceDispatchStatus, [
  String? hospitalAssignmentDispatchStatus,
]) {
  final chain = hospitalAssignmentDispatchStatus?.trim();
  if (chain == 'failed_to_assist') return 'Failed to assist';
  final phase = e.emsWorkflowPhase?.trim();
  if (phase != null && phase.isNotEmpty) {
    return emsWorkflowPhaseShortLabel(phase);
  }
  final amb = ambulanceDispatchStatus?.trim();
  if (amb != null && amb.isNotEmpty) {
    return switch (amb) {
      'pending_operator' => 'Ambulance pending',
      'ambulance_en_route' => 'Ambulance en route',
      'no_operator' => 'No ambulance assigned',
      _ => amb.replaceAll('_', ' '),
    };
  }
  switch (e.status) {
    case IncidentStatus.pending:
      return 'Open';
    case IncidentStatus.blocked:
      return 'Blocked';
    case IncidentStatus.resolved:
      return 'Closed';
    case IncidentStatus.dispatched:
      if (e.acceptedVolunteerIds.isNotEmpty) {
        return 'Responders active';
      }
      return 'In progress';
  }
}

Color hospitalConsignmentStatusColor(
  SosIncident e,
  String? ambulanceDispatchStatus, [
  String? hospitalAssignmentDispatchStatus,
]) {
  final chain = hospitalAssignmentDispatchStatus?.trim();
  if (chain == 'failed_to_assist') return Colors.white54;
  final phase = e.emsWorkflowPhase?.trim();
  if (phase != null && phase.isNotEmpty) {
    return switch (phase) {
      'inbound' => const Color(0xFF58A6FF),
      'on_scene' => Colors.tealAccent,
      'returning' => const Color(0xFFD29922),
      'complete' => AppColors.primarySafe,
      _ => Colors.cyanAccent,
    };
  }
  final amb = ambulanceDispatchStatus?.trim();
  if (amb != null && amb.isNotEmpty) {
    return switch (amb) {
      'ambulance_en_route' => Colors.lightGreenAccent,
      'pending_operator' => Colors.orangeAccent,
      'no_operator' => Colors.white54,
      _ => AppColors.accentBlue,
    };
  }
  return switch (e.status) {
    IncidentStatus.pending => Colors.orangeAccent,
    IncidentStatus.dispatched => Colors.lightBlueAccent,
    IncidentStatus.blocked => Colors.grey,
    IncidentStatus.resolved => AppColors.primarySafe,
  };
}

class HospitalConsignmentStatusPill extends StatelessWidget {
  const HospitalConsignmentStatusPill({
    super.key,
    required this.incident,
    this.ambulanceDispatchStatus,
    this.hospitalAssignmentDispatchStatus,
  });

  final SosIncident incident;
  final String? ambulanceDispatchStatus;
  /// From `ops_incident_hospital_assignments.dispatchStatus` (e.g. [failed_to_assist]).
  final String? hospitalAssignmentDispatchStatus;

  @override
  Widget build(BuildContext context) {
    final label = hospitalConsignmentStatusLabel(
      incident,
      ambulanceDispatchStatus,
      hospitalAssignmentDispatchStatus,
    );
    final color = hospitalConsignmentStatusColor(
      incident,
      ambulanceDispatchStatus,
      hospitalAssignmentDispatchStatus,
    );
    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.end,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
      ],
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip(this.k, this.v, {super.key});

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$k: $v',
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
    );
  }
}

class FilterChipWidget extends StatelessWidget {
  const FilterChipWidget({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(width: 6),
          child,
        ],
      ),
    );
  }
}

class OpsTopBar extends StatelessWidget {
  const OpsTopBar({
    super.key,
    required this.child,
    required this.userEmail,
    required this.accent,
  });

  final Widget child;
  final String userEmail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bgColor = Color.lerp(AppColors.slate800, accent, 0.14) ?? AppColors.slate800;
    return Material(
      color: bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Image.asset(
                    AppConstants.logoPath,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(width: 8),
                Text(context.opsTr('Overview'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const Spacer(),
                Icon(Icons.person_outline, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(userEmail, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Right-hand collapsible strip (Live Ops / Management detail).
class OpsCollapsibleDetailPanel extends StatelessWidget {
  const OpsCollapsibleDetailPanel({
    super.key,
    required this.expanded,
    required this.onToggleExpanded,
    required this.accent,
    required this.body,
    this.title = 'Details',
    this.openWidth = widthOpen,
    this.shutWidth = widthShut,
  });

  static const double widthOpen = 300;
  static const double widthShut = 44;

  final bool expanded;
  final VoidCallback onToggleExpanded;
  final Color accent;
  final Widget body;
  final String title;
  final double openWidth;
  final double shutWidth;

  @override
  Widget build(BuildContext context) {
    final w = expanded ? openWidth : shutWidth;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: w,
      decoration: const BoxDecoration(
        color: Color(0xFF1B2634),
        border: Border(left: BorderSide(color: Colors.white12)),
      ),
      child: expanded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: Colors.black26,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 14),
                          ),
                        ),
                        IconButton(
                          tooltip: context.opsTr('Collapse panel'),
                          onPressed: onToggleExpanded,
                          icon: const Icon(Icons.keyboard_arrow_right_rounded, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: body),
              ],
            )
          : Center(
              child: IconButton(
                tooltip: context.opsTr('Show details'),
                onPressed: onToggleExpanded,
                icon: Icon(Icons.keyboard_arrow_left_rounded, color: accent),
              ),
            ),
    );
  }
}

/// Real-time strip for medical ops: incidents where this hospital must accept or decline hex dispatch.
class HospitalDispatchPendingBanner extends StatelessWidget {
  const HospitalDispatchPendingBanner({
    super.key,
    required this.hospitalDocId,
    required this.accent,
    required this.onOpenIncident,
  });

  final String hospitalDocId;
  final Color accent;
  final void Function(String incidentId) onOpenIncident;

  @override
  Widget build(BuildContext context) {
    final hid = hospitalDocId.trim();
    if (hid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('ops_incident_hospital_assignments')
          .where('notifiedHospitalId', isEqualTo: hid)
          .where('dispatchStatus', isEqualTo: 'pending_acceptance')
          .limit(12)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Material(
            color: Colors.red.shade900.withValues(alpha: 0.9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Dispatch query error: ${snap.error}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SizedBox.shrink();
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Material(
          color: accent.withValues(alpha: 0.22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_hospital, color: accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hospital dispatch — ${docs.length} incident${docs.length == 1 ? '' : 's'} awaiting your acceptance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in docs)
                      ActionChip(
                        label: Text(
                          d.id.length > 14 ? '${d.id.substring(0, 12)}…' : d.id,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        backgroundColor: AppColors.slate800,
                        side: BorderSide(color: accent.withValues(alpha: 0.6)),
                        onPressed: () => onOpenIncident(d.id),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
